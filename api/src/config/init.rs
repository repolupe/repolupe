use crate::config::env::FRONTEND_DIR;
use crate::config::error::AppError;
use crate::config::runtime::{InvalidConfigValue, RuntimeConfig};
use crate::config::state::{AppState, DatabasePool};
use crate::dto::user::UserRole;
use crate::repository;
use crate::service;
use crate::service::attachment::AttachmentStore;
use crate::service::llm::LlmClient;
use crate::service::mirror::MirrorStore;
use crate::service::mistral_ocr::{self, MistralOcr};
use crate::service::runtime_config::LiveConfig;
use crate::util;
use crate::util::token_cipher::TokenCipher;
use chrono::TimeDelta;
use sqlx::SqlitePool;
use sqlx::migrate::{MigrateError, Migrator};
use sqlx::sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous};
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Duration;

pub(crate) static MIGRATOR: Migrator = sqlx::migrate!();

/// The user name of the admin created from [`Config::initial_admin_password`].
pub const INITIAL_ADMIN_USER_NAME: &str = "admin";

/// The password of the initial admin if [`Config::initial_admin_password`] is not set.
pub const DEFAULT_INITIAL_ADMIN_PASSWORD: &str = "repolupe123";

/// How long a session lasts without use on a server, see [`Config::session_idle_timeout`].
pub const DEFAULT_SESSION_IDLE_TIMEOUT: TimeDelta = TimeDelta::days(30);

/// Everything [`crate::Repolupe::new`] needs besides the database. Plain data, read from the
/// environment variables by [`Self::from_env`].
pub struct Config {
    /// Encrypts repository access tokens and LLM API keys. At least 32 characters, e.g.
    /// `openssl rand -hex 32`. Changing it later makes the stored tokens unreadable.
    pub token_encryption_key: String,
    /// Where the repositories are cloned to. Created if missing.
    pub repos_dir: PathBuf,
    /// Where the files users attach to chats are stored. Created if missing.
    pub attachments_dir: PathBuf,
    /// The frontend build (`nuxt generate`), served by [`crate::Repolupe::router`] for every
    /// path the API doesn't handle. Must contain `index.html`.
    pub frontend_dir: Option<PathBuf>,
    /// The password of the admin user [`INITIAL_ADMIN_USER_NAME`], created if the database
    /// has no users yet, [`DEFAULT_INITIAL_ADMIN_PASSWORD`] if not set.
    pub initial_admin_password: Option<String>,
    /// Whether the initial admin has to change its password on the first login, as on a
    /// server ([`Config::from_env`] sets it). Turned off by apps that run a local instance
    /// with a generated password they log in with themselves.
    pub initial_admin_must_change_password: bool,
    /// How long a session lasts without use (each use extends it), on a server
    /// [`DEFAULT_SESSION_IDLE_TIMEOUT`] ([`Config::from_env`] sets it). `None` keeps sessions
    /// until they are logged out, e.g. for a local instance in an app, whose token is stored next
    /// to the password it logs in with anyway.
    pub session_idle_timeout: Option<TimeDelta>,
    /// Applies the migrations on startup. Turn off only if they are applied elsewhere.
    pub run_migrations: bool,
    /// Runs the repository sync loop and the expired session cleanup. Without it, repositories
    /// are never fetched.
    pub background_tasks: bool,
    /// Serves unauthenticated debug routes under `/api/debug`, e.g. to create dummy data.
    /// Never enable it in production.
    pub debug_api: bool,
    /// The API key for [`OcrEngine::Mistral`], which can only be selected with it.
    pub ocr_api_key_mistral: Option<String>,
    /// The defaults of the settings admins can change at runtime.
    pub runtime: RuntimeConfig,
}

/// The SQLite database opened by [`Self::connect`], read from the environment variables by
/// [`Self::from_env`].
pub struct DatabaseConfig {
    /// E.g. `sqlite:rp.db` (relative to the working directory) or
    /// `sqlite:///data/rp.db`. The file is created if missing.
    pub url: String,
}

impl DatabaseConfig {
    /// Opens the database in WAL mode, so reads don't wait for writes. Writers wait for each
    /// other up to the busy timeout.
    pub async fn connect(&self) -> Result<SqlitePool, InitError> {
        tracing::info!("Connecting to database");
        let options = SqliteConnectOptions::from_str(&self.url)
            .map_err(InitError::Database)?
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal)
            .busy_timeout(Duration::from_secs(10));
        let db = SqlitePoolOptions::new()
            .max_connections(10)
            .acquire_timeout(Duration::from_secs(3))
            .connect_with(options)
            .await
            .map_err(InitError::Database)?;
        tracing::info!("Connected to database!");
        Ok(db)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct OcrConfig {
    pub engine: OcrEngine,
    /// Tesseract language codes, e.g. `eng` or `deu`, which are mapped to PaddleOCR's models.
    /// PaddleOCR uses one model per document, chosen by the first language. English, Latin
    /// languages like `deu`, and Chinese share one model that covers all of them, even though
    /// xberg warns that the other languages are not covered. Other scripts, e.g. `rus`, need
    /// their own model, so `eng,rus` recognizes no Cyrillic. Mistral ignores them, it detects
    /// the languages itself. Language data that is not installed is downloaded on first use.
    pub languages: Vec<String>,
    /// How likely a page must be a scan, from 0 to 1, to be recognized, see
    /// [`crate::RuntimeConfig::ocr_scan_confidence`].
    pub scan_confidence: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OcrEngine {
    /// Uses the system's Tesseract, which is linked into the binary.
    Tesseract,
    /// PaddleOCR on ONNX Runtime. Recognizes scans better than Tesseract but needs about
    /// twice the memory. The models are downloaded from Hugging Face on first use, or
    /// beforehand with [`crate::prepare_ocr`].
    Paddle,
    /// Mistral's OCR API, which recognizes scans and their tables much better, but receives
    /// the documents. Only documents with pages that look like scans are sent, as a whole, and
    /// replace xberg's text. Needs [`Config::ocr_api_key_mistral`].
    Mistral,
}

#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum InitError {
    #[error("Invalid token encryption key: {0}")]
    InvalidTokenEncryptionKey(String),

    #[error("Invalid initial admin: {0}")]
    InvalidInitialAdmin(String),

    #[error("Invalid config: {0}")]
    InvalidConfig(#[from] InvalidConfigValue),

    #[error("OCR does not work: {0}")]
    Ocr(String),

    #[error("Failed to prepare the repositories directory {}: {source}", path.display())]
    ReposDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("Failed to prepare the attachments directory {}: {source}", path.display())]
    AttachmentsDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("{FRONTEND_DIR} does not contain index.html: {}", .0.display())]
    FrontendDir(PathBuf),

    #[error("Failed to connect to the database: {0}")]
    Database(#[source] sqlx::Error),

    #[error("Failed to create an HTTP client: {0}")]
    HttpClient(#[source] reqwest::Error),

    #[error("Failed to run migrations: {0}")]
    Migrate(#[from] MigrateError),

    #[error("Startup failed: {0}")]
    Startup(String),
}

impl From<AppError> for InitError {
    fn from(e: AppError) -> Self {
        InitError::Startup(e.to_string())
    }
}

/// Prepares the database and returns the state. The background tasks are started by the caller.
pub(crate) async fn init(config: Config, db: DatabasePool) -> Result<AppState, InitError> {
    let env = config.to_env_map();
    let token_cipher = TokenCipher::from_secret(&config.token_encryption_key)
        .map_err(|e| InitError::InvalidTokenEncryptionKey(e.to_string()))?;
    config.runtime.validate()?;
    let has_ocr_api_key_mistral = config.ocr_api_key_mistral.is_some();
    config
        .runtime
        .validate_ocr_engine(has_ocr_api_key_mistral)?;
    let mistral = config
        .ocr_api_key_mistral
        .map(MistralOcr::new)
        .transpose()
        .map_err(InitError::HttpClient)?;
    let llm = LlmClient::new().map_err(InitError::HttpClient)?;
    let repos_dir = prepare_repos_dir(config.repos_dir)?;
    let mirrors = MirrorStore::new(&repos_dir).map_err(InitError::HttpClient)?;
    let attachments_dir = prepare_attachments_dir(config.attachments_dir)?;
    if let Some(dir) = &config.frontend_dir {
        if !dir.join("index.html").is_file() {
            return Err(InitError::FrontendDir(dir.clone()));
        }
        tracing::info!("Serving the frontend from {}", dir.display());
    }

    if config.run_migrations {
        MIGRATOR.run(&db).await?;
    }

    create_initial_admin_user(
        &db,
        config.initial_admin_password,
        config.initial_admin_must_change_password,
    )
    .await?;

    let runtime_config = LiveConfig::load(&db, config.runtime, has_ocr_api_key_mistral).await?;
    log_ocr(runtime_config.current().ocr().as_ref());

    let interrupted = service::generation::fail_interrupted(&db).await?;
    if interrupted > 0 {
        tracing::info!("Marked {interrupted} interrupted answers as failed");
    }

    let interrupted = service::sync::reset_interrupted(&db).await?;
    if interrupted > 0 {
        tracing::info!("Rescheduled {interrupted} interrupted repository syncs");
    }

    Ok(AppState::new(
        db,
        token_cipher,
        llm,
        mirrors,
        AttachmentStore::new(attachments_dir),
        mistral,
        config.session_idle_timeout,
        runtime_config,
        env,
    ))
}

pub(crate) fn log_ocr(ocr: Option<&OcrConfig>) {
    match ocr {
        Some(ocr) if ocr.engine == OcrEngine::Mistral => tracing::info!(
            "Recognizing scanned documents with Mistral ({}, scan confidence {})",
            mistral_ocr::MODEL,
            ocr.scan_confidence
        ),
        Some(ocr) => tracing::info!(
            "Recognizing scanned documents with {:?} ({:?}, scan confidence {})",
            ocr.engine,
            ocr.languages,
            ocr.scan_confidence
        ),
        None => tracing::info!("Not recognizing scanned documents, OCR is off"),
    }
}

/// Creates the admin user [`INITIAL_ADMIN_USER_NAME`] with `password` (or
/// [`DEFAULT_INITIAL_ADMIN_PASSWORD`]) if there are no users in the database yet. With
/// `must_change_password`, the admin has to change it before doing anything else.
async fn create_initial_admin_user(
    db: &DatabasePool,
    password: Option<String>,
    must_change_password: bool,
) -> Result<(), InitError> {
    if repository::user::count_users(db).await? > 0 {
        return Ok(());
    }

    let password = password.unwrap_or_else(|| {
        tracing::warn!(
            "No initial admin password is configured, creating the admin with the default one"
        );
        DEFAULT_INITIAL_ADMIN_PASSWORD.to_string()
    });
    util::validation::validate_password(&password)
        .map_err(|e| InitError::InvalidInitialAdmin(format!("password: {}", e.0)))?;

    let password_hash = util::password::hash_password(&password).await?;
    let admin = repository::user::create_user(
        db,
        UserRole::Admin,
        INITIAL_ADMIN_USER_NAME,
        None,
        &password_hash,
        must_change_password,
    )
    .await?;

    if must_change_password {
        tracing::info!(
            "Admin user created: {} ({}), the password has to be changed on the first login",
            admin.user_name,
            admin.id
        );
    } else {
        tracing::info!("Admin user created: {} ({})", admin.user_name, admin.id);
    }
    Ok(())
}

/// Creates the directory the repositories are cloned to and makes its path absolute.
fn prepare_repos_dir(dir: PathBuf) -> Result<PathBuf, InitError> {
    let error = |source| InitError::ReposDir {
        path: dir.clone(),
        source,
    };
    std::fs::create_dir_all(&dir).map_err(error)?;
    let absolute = std::path::absolute(&dir).map_err(error)?;
    tracing::info!("Storing repositories in {}", absolute.display());
    Ok(absolute)
}

/// Creates the directory the attachments are stored in and makes its path absolute.
fn prepare_attachments_dir(dir: PathBuf) -> Result<PathBuf, InitError> {
    let error = |source| InitError::AttachmentsDir {
        path: dir.clone(),
        source,
    };
    std::fs::create_dir_all(&dir).map_err(error)?;
    let absolute = std::path::absolute(&dir).map_err(error)?;
    tracing::info!("Storing attachments in {}", absolute.display());
    Ok(absolute)
}
