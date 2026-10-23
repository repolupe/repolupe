//! Repolupe answers questions about git repositories with an LLM.
//!
//! Embed it by creating a [`Repolupe`] from a [`Config`] and a database pool and serving
//! [`Repolupe::router`], on its own or nested in another axum app. The `repolupe` binary does
//! exactly that, configured from environment variables with [`Config::from_env`] and
//! [`DatabaseConfig::from_env`]. Nothing else reads the environment.
//!
//! Only one instance may run per database: answer generations and repository syncs are
//! tracked in memory, and startup fails the answers and resets the syncs left unfinished.

use axum::Router;
use axum::http::StatusCode;
use axum::routing::{any, get, post};
use sqlx::SqlitePool;
use std::path::{Path, PathBuf};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use tower_http::services::{ServeDir, ServeFile};

mod config;
mod controller;
pub mod dto;
mod middleware;
mod model;
mod repository;
mod service;
mod util;

pub use config::env;
pub use config::env::EnvError;
pub use config::init::{
    Config, DEFAULT_INITIAL_ADMIN_PASSWORD, DEFAULT_SESSION_IDLE_TIMEOUT, DatabaseConfig,
    INITIAL_ADMIN_USER_NAME, InitError, OcrConfig, OcrEngine,
};
pub use config::runtime::{InvalidConfigValue, RuntimeConfig};

/// A running Repolupe: its database, background tasks and live answer generations.
///
/// Call [`Self::shutdown`] when done. Dropping it stops the background tasks without waiting.
pub struct Repolupe {
    state: config::state::AppState,
    shutdown: CancellationToken,
    tasks: Vec<JoinHandle<()>>,
    debug_api: bool,
    frontend_dir: Option<PathBuf>,
}

impl Repolupe {
    /// Migrates the database (if configured), creates the initial admin, recovers from an
    /// unclean shutdown and starts the background tasks. `db` is the database with Repolupe's
    /// schema, e.g. from [`DatabaseConfig::connect`].
    pub async fn new(config: Config, db: SqlitePool) -> Result<Self, InitError> {
        let background_tasks = config.background_tasks;
        let debug_api = config.debug_api;
        if debug_api {
            tracing::warn!("The debug API is enabled, do not use this in production");
        }
        let frontend_dir = config.frontend_dir.clone();
        let state = config::init::init(config, db).await?;
        let shutdown = CancellationToken::new();

        let mut tasks = Vec::new();
        if background_tasks {
            tasks.push(service::session::spawn_cleanup_task(
                state.db.clone(),
                shutdown.clone(),
            ));
            tasks.push(service::sync::spawn_sync_task(
                state.clone(),
                shutdown.clone(),
            ));
            tasks.push(service::extraction::spawn_extraction_task(
                state.clone(),
                shutdown.clone(),
            ));
        }

        Ok(Self {
            state,
            shutdown,
            tasks,
            debug_api,
            frontend_dir,
        })
    }

    /// The HTTP API, with all routes under `/api/v1` (and `/api/debug` if [`Config::debug_api`]
    /// is set). With [`Config::frontend_dir`], the frontend is served for every other path.
    /// Serve it at the root or nest it under a prefix.
    pub fn router(&self) -> Router {
        let router = app(self.state.clone(), self.debug_api);
        match &self.frontend_dir {
            Some(dir) => with_frontend(router, dir),
            None => router,
        }
    }

    /// Stops the background tasks and fails the answers still being generated. Afterwards,
    /// the router rejects new answers.
    pub async fn shutdown(mut self) {
        self.shutdown.cancel();
        service::generation::stop_all(&self.state).await;
        for task in std::mem::take(&mut self.tasks) {
            if let Err(e) = task.await {
                tracing::error!("Background task failed: {e}");
            }
        }
    }
}

/// Recognizes a sample scan with `ocr` and checks that its text was found. The engine
/// downloads what it is missing on first use. Mistral needs nothing, so it is not called.
pub async fn prepare_ocr(ocr: &OcrConfig) -> Result<(), InitError> {
    if ocr.engine == OcrEngine::Mistral {
        return Ok(());
    }
    config::runtime::validate_ocr_engine_built(Some(ocr.engine))?;
    config::runtime::validate_ocr_languages(&ocr.languages)?;
    service::extraction::check_ocr(ocr)
        .await
        .map_err(InitError::Ocr)
}

impl Drop for Repolupe {
    fn drop(&mut self) {
        self.shutdown.cancel();
    }
}

fn app(state: config::state::AppState, debug_api: bool) -> Router {
    let mut router = configure_routes(state.clone());
    if debug_api {
        router = router.merge(configure_debug_routes());
    }
    router.with_state(state)
}

/// Serves the frontend build in `dir` for every path the API doesn't handle. Paths without a
/// file get `index.html`, so the SPA can route them.
fn with_frontend(router: Router, dir: &Path) -> Router {
    let frontend = ServeDir::new(dir)
        .append_index_html_on_directories(false)
        .fallback(ServeFile::new(dir.join("index.html")));

    router
        // Unknown API paths and missing build assets stay errors instead of loading the app.
        .route("/api/{*path}", any(|| async { StatusCode::NOT_FOUND }))
        .nest_service("/_nuxt", ServeDir::new(dir.join("_nuxt")))
        .fallback_service(frontend)
}

#[rustfmt::skip]
fn configure_routes(state: config::state::AppState) -> Router<config::state::AppState> {
    // The middleware is a `route_layer`: a `layer` would also wrap the fallback, so a path the
    // API doesn't have would get 401 without a session and 403 for users who aren't admins
    // (from the admin routes' fallback) instead of 404.
    let public = Router::new()
        .route("/api/v1/login", post(controller::auth::login))
        .route("/api/v1/logout", post(controller::auth::logout))
        .route("/api/v1/instance", get(controller::instance::get_instance));

    // Also for users who must change their password first.
    let password_change = Router::new()
        .route("/api/v1/me", get(controller::user::me))
        .route("/api/v1/change-password", post(controller::user::change_password))
        .route_layer(axum::middleware::from_fn(middleware::content_type::require_json))
        .route_layer(axum::middleware::from_fn_with_state(state.clone(), middleware::auth::session_auth_allow_password_change));

    let authenticated = Router::new()
        .route("/api/v1/me/default-model", post(controller::user::set_default_model))
        .route("/api/v1/me/locale", post(controller::user::set_locale))
        .route("/api/v1/me/auto-commit", post(controller::user::set_auto_commit))
        .route("/api/v1/me/profile", post(controller::user::update_profile))
        .route("/api/v1/me/identity", post(controller::user::update_identity))
        .route("/api/v1/models", get(controller::llm::list_models))
        .route("/api/v1/attachments", post(controller::attachment::upload_attachment))
        .route("/api/v1/attachments/{id}", get(controller::attachment::download_attachment))
        .route("/api/v1/repositories", get(controller::repository::list_repositories).post(controller::repository::create_repository))
        .route("/api/v1/repositories/{id}", get(controller::repository::get_repository))
        .route("/api/v1/repositories/{id}/update", post(controller::repository::update_repository))
        .route("/api/v1/repositories/{id}/delete", post(controller::repository::delete_repository))
        .route("/api/v1/repositories/{id}/sync", post(controller::repository::request_sync))
        .route("/api/v1/repositories/{id}/documents", get(controller::repository::list_repository_documents))
        .route("/api/v1/repositories/{id}/users", get(controller::repository::list_repository_users).post(controller::repository::add_repository_user))
        .route("/api/v1/repositories/{id}/users/{user_id}/update", post(controller::repository::update_repository_user))
        .route("/api/v1/repositories/{id}/users/{user_id}/delete", post(controller::repository::remove_repository_user))
        .route("/api/v1/chats", get(controller::chat::list_chats).post(controller::chat::create_chat))
        .route("/api/v1/chats/{id}", get(controller::chat::get_chat))
        .route("/api/v1/chats/{id}/update", post(controller::chat::update_chat))
        .route("/api/v1/chats/{id}/delete", post(controller::chat::delete_chat))
        .route("/api/v1/chats/{id}/messages", post(controller::chat::send_message))
        .route("/api/v1/chats/{id}/messages/{message_id}/stream", get(controller::chat::stream_message))
        .route("/api/v1/chats/{id}/messages/{message_id}/cancel", post(controller::chat::cancel_message))
        .route("/api/v1/chats/{id}/messages/{message_id}/retry", post(controller::chat::retry_message))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}", get(controller::chat::get_tool_call))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}/file", get(controller::chat::get_presented_file))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}/patch", get(controller::chat::get_proposed_commit_patch))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}/diff", get(controller::chat::get_proposed_commit_diff))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}/proposed-commit", get(controller::chat::get_proposed_commit))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}/proposed-commit/file", get(controller::chat::get_proposed_commit_file))
        .route("/api/v1/chats/{id}/tool-calls/{tool_call_id}/commit", post(controller::chat::commit_proposed_commit))
        .route_layer(axum::middleware::from_fn(middleware::content_type::require_json))
        .route_layer(axum::middleware::from_fn_with_state(state.clone(), middleware::auth::session_auth));

    let admin = Router::new()
        .route("/api/v1/users", get(controller::user::list_users))
        .route("/api/v1/users/{id}/update", post(controller::user::update_user))
        .route("/api/v1/users/{id}/password", post(controller::user::reset_password))
        .route("/api/v1/register", post(controller::user::register))
        .route("/api/v1/delete-user", post(controller::user::delete_user))
        .route("/api/v1/llm-providers", get(controller::llm::list_providers).post(controller::llm::create_provider))
        .route("/api/v1/llm-providers/{id}/update", post(controller::llm::update_provider))
        .route("/api/v1/llm-providers/{id}/delete", post(controller::llm::delete_provider))
        .route("/api/v1/llm-providers/{id}/models", post(controller::llm::create_model))
        .route("/api/v1/llm-providers/{id}/remote-models", get(controller::llm::list_remote_models))
        .route("/api/v1/models/{id}/update", post(controller::llm::update_model))
        .route("/api/v1/models/{id}/delete", post(controller::llm::delete_model))
        .route("/api/v1/default-model", post(controller::llm::set_default_model))
        .route("/api/v1/config", get(controller::config::get_config).post(controller::config::set_config))
        .route("/api/v1/document-extraction", get(controller::extraction::get_extraction_overview))
        .route("/api/v1/document-extraction/documents", get(controller::extraction::list_extraction_documents))
        .route("/api/v1/document-extraction/retry", post(controller::extraction::retry_document))
        .route_layer(axum::middleware::from_fn(middleware::content_type::require_json))
        .route_layer(axum::middleware::from_fn_with_state(state, middleware::auth::session_auth_admin));

    public.merge(password_change).merge(authenticated).merge(admin)
}

/// Unauthenticated.
#[rustfmt::skip]
fn configure_debug_routes() -> Router<config::state::AppState> {
    Router::new()
        .route("/api/debug/dummy", get(controller::debug::create_dummy_data))
}
