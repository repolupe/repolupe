//! A Repolupe instance running in the app, for offline mode.
//!
//! [`start_local`] starts one on a data directory and returns its [`LocalHandle`]; clients of it
//! are created with [`Client::local`](crate::api::client::Client::local), which runs every
//! request through the instance's router in-process (with all of its middleware, exactly as on a
//! server). Logging in goes through `POST /api/v1/login` like on a server: the initial admin
//! [`local_admin_user_name`] is created with [`LocalConfig::admin_password`] on the first start,
//! without having to change it.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock};

use axum::Router;
use flutter_rust_bridge::frb;
use percent_encoding::{AsciiSet, CONTROLS, utf8_percent_encode};
use repolupe::{
    Config, DatabaseConfig, INITIAL_ADMIN_USER_NAME, InitError, Repolupe, RuntimeConfig,
};
use sqlx::SqlitePool;
use tokio::sync::Mutex;

use crate::runtime::runtime;
use crate::transport::Transport;

/// The SQLite database in the data directory.
const DATABASE_FILE: &str = "repolupe.db";
/// The mirrored repositories in the data directory.
const REPOS_DIR: &str = "repos";
/// The files attached to chats in the data directory.
const ATTACHMENTS_DIR: &str = "attachments";

/// What sqlx's SQLite URLs need escaped in a path: it percent-decodes the path and starts the
/// parameters at `?`.
const URL_PATH: &AsciiSet = &CONTROLS.add(b'%').add(b'?').add(b'#');

/// How to start a local instance.
pub struct LocalConfig {
    /// The directory with everything of the instance, created if missing: the database
    /// `repolupe.db` and the directories `repos` (the mirrored repositories) and `attachments`.
    /// Delete it (after [`LocalHandle::shutdown`]) to remove the instance.
    pub data_dir: String,
    /// Encrypts the repository access tokens and LLM API keys in the database, at least 32
    /// characters. Generate it once with [`generate_secret`] and keep it in secure storage:
    /// with another key, the stored tokens and keys can't be read anymore.
    pub token_encryption_key: String,
    /// The password of the admin [`local_admin_user_name`], who is created with it when the
    /// database has no users yet (on the first start), without having to change it. Ignored
    /// afterwards. Generate it once with [`generate_secret`] and keep it in secure storage, to
    /// log in again when the session expired (after 30 days without use).
    pub admin_password: String,
}

/// Why a local instance could not be started, e.g. an invalid key or a data directory that
/// can't be written.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{message}")]
pub struct LocalError {
    pub message: String,
}

/// A running local instance. It runs until [`LocalHandle::shutdown`] (or until [`start_local`]
/// is called again for the same data directory), also when the handle is dropped.
#[frb(opaque)]
pub struct LocalHandle {
    instance: Arc<Instance>,
}

struct Instance {
    data_dir: PathBuf,
    router: Router,
    /// Set first by [`Instance::stop`], so the clients' requests fail from then on.
    stopped: Arc<AtomicBool>,
    /// `None` once stopped.
    running: Mutex<Option<Running>>,
}

struct Running {
    repolupe: Repolupe,
    pool: SqlitePool,
}

/// The running instances by their canonical data directory, so there is at most one per
/// database (Repolupe tracks answers and syncs in memory).
static INSTANCES: LazyLock<Mutex<HashMap<PathBuf, Arc<Instance>>>> = LazyLock::new(Mutex::default);

/// Starts a local instance on `config.data_dir`: opens (or creates) its database, migrates it,
/// creates the initial admin if there are no users yet, and starts the background tasks
/// (repository syncs, document conversion without OCR, session cleanup). LLM providers and git
/// remotes are still reached over the network.
///
/// An instance already running on the same data directory is shut down first, e.g. after a
/// Flutter hot restart, which keeps the Rust library and its instances alive.
pub async fn start_local(config: LocalConfig) -> Result<LocalHandle, LocalError> {
    // Spawned, not aborted when the caller stops waiting, so it never stops halfway.
    runtime()
        .spawn(start(config))
        .await
        .map_err(|e| LocalError {
            message: format!("Failed to start the local instance: {e}"),
        })?
}

/// A random secret for [`LocalConfig::token_encryption_key`] and
/// [`LocalConfig::admin_password`]: 32 random bytes as 64 hexadecimal characters.
#[frb(sync)]
pub fn generate_secret() -> String {
    rand::random::<[u8; 32]>()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

/// The user name of the initial admin of a local instance, who logs in with
/// [`LocalConfig::admin_password`]. Admins can rename themselves, so after a rename, the app
/// has to log in with the new name.
#[frb(sync)]
pub fn local_admin_user_name() -> String {
    INITIAL_ADMIN_USER_NAME.to_owned()
}

impl LocalHandle {
    /// Stops the instance: fails the answers still being generated, stops the background tasks
    /// and closes the database (waiting for the queries still running). Afterwards, the requests
    /// of its clients fail with `ClientError::Transport`, and the data directory can be deleted
    /// or started again. Calling it again does nothing.
    pub async fn shutdown(&self) {
        let instance = self.instance.clone();
        // Spawned, not aborted when the caller stops waiting, so it never stops halfway.
        let stopped = runtime().spawn(async move {
            instance.stop().await;
            let mut instances = INSTANCES.lock().await;
            if instances
                .get(&instance.data_dir)
                .is_some_and(|running| Arc::ptr_eq(running, &instance))
            {
                instances.remove(&instance.data_dir);
            }
        });
        // It can only fail by panicking, after which there is nothing left to stop.
        let _ = stopped.await;
    }

    /// Whether the instance runs, i.e. was neither shut down nor replaced by [`start_local`].
    #[frb(sync)]
    pub fn is_running(&self) -> bool {
        !self.instance.stopped.load(Ordering::Acquire)
    }

    /// The transport of the clients of this instance.
    pub(crate) fn transport(&self) -> Transport {
        Transport::stoppable_local(self.instance.router.clone(), self.instance.stopped.clone())
    }
}

impl Instance {
    async fn stop(&self) {
        // Held until the end, so a concurrent call returns only when it is stopped too.
        let mut running = self.running.lock().await;
        let Some(Running { repolupe, pool }) = running.take() else {
            return;
        };
        self.stopped.store(true, Ordering::Release);
        repolupe.shutdown().await;
        pool.close().await;
    }
}

/// Runs on the crate's runtime, since the pool and Repolupe spawn tasks.
async fn start(config: LocalConfig) -> Result<LocalHandle, LocalError> {
    let data_dir = prepare_data_dir(&config.data_dir)?;
    // Held until the instance runs, so two starts on one directory don't overlap.
    let mut instances = INSTANCES.lock().await;
    if let Some(previous) = instances.remove(&data_dir) {
        previous.stop().await;
    }

    let database = DatabaseConfig {
        url: database_url(&data_dir.join(DATABASE_FILE))?,
    };
    let pool = database.connect().await.map_err(LocalError::from)?;
    let repolupe = match Repolupe::new(repolupe_config(config, &data_dir), pool.clone()).await {
        Ok(repolupe) => repolupe,
        Err(e) => {
            pool.close().await;
            return Err(e.into());
        }
    };

    let instance = Arc::new(Instance {
        data_dir: data_dir.clone(),
        router: repolupe.router(),
        stopped: Arc::default(),
        running: Mutex::new(Some(Running { repolupe, pool })),
    });
    instances.insert(data_dir, instance.clone());
    Ok(LocalHandle { instance })
}

fn repolupe_config(config: LocalConfig, data_dir: &Path) -> Config {
    Config {
        token_encryption_key: config.token_encryption_key,
        repos_dir: data_dir.join(REPOS_DIR),
        attachments_dir: data_dir.join(ATTACHMENTS_DIR),
        frontend_dir: None,
        initial_admin_password: Some(config.admin_password),
        // The app logs in with the password it generated, the user never sees it.
        initial_admin_must_change_password: false,
        // The app keeps the token next to the password anyway, and the instance can't be
        // reached from outside the app, so an expiry would only make it log in again.
        session_idle_timeout: None,
        run_migrations: true,
        background_tasks: true,
        debug_api: false,
        ocr_api_key_mistral: None,
        // Without OCR (the crate is built without local OCR, and Mistral would need a key) and
        // named "Repolupe"; admins can change the runtime settings with `set_config`.
        runtime: RuntimeConfig::default(),
    }
}

/// Creates the data directory and returns its canonical path.
fn prepare_data_dir(data_dir: &str) -> Result<PathBuf, LocalError> {
    let error = |e: std::io::Error| LocalError {
        message: format!("Failed to prepare the data directory {data_dir}: {e}"),
    };
    if data_dir.trim().is_empty() {
        return Err(LocalError {
            message: "The data directory is missing.".into(),
        });
    }
    std::fs::create_dir_all(data_dir).map_err(error)?;
    std::fs::canonicalize(data_dir).map_err(error)
}

/// The URL of the SQLite file at `path`, which may contain any character.
fn database_url(path: &Path) -> Result<String, LocalError> {
    let path = path.to_str().ok_or_else(|| LocalError {
        message: format!("The data directory is not valid UTF-8: {}", path.display()),
    })?;
    Ok(format!("sqlite://{}", utf8_percent_encode(path, URL_PATH)))
}

impl From<InitError> for LocalError {
    fn from(e: InitError) -> Self {
        LocalError {
            message: e.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use futures_executor::block_on;
    use repolupe::dto::auth::{LoginRequest, LoginResponse};
    use repolupe::dto::user::RegisterRequest;
    use tempfile::TempDir;

    use super::*;
    use crate::api::client::Client;
    use crate::api::error::ClientError;
    use crate::transport::STOPPED;

    /// A data directory whose path needs escaping in the database URL.
    fn data_dir(dir: &TempDir) -> String {
        dir.path()
            .join("Application Support/data ?#%20")
            .to_str()
            .unwrap()
            .to_owned()
    }

    fn config(data_dir: &str, admin_password: &str) -> LocalConfig {
        LocalConfig {
            data_dir: data_dir.to_owned(),
            token_encryption_key: generate_secret(),
            admin_password: admin_password.to_owned(),
        }
    }

    fn login(
        client: &Client,
        user_name: &str,
        password: &str,
    ) -> Result<LoginResponse, ClientError> {
        block_on(client.login(LoginRequest {
            user_name_or_email: user_name.into(),
            password: password.into(),
        }))
    }

    fn assert_stopped<T>(result: Result<T, ClientError>) {
        match result {
            Err(ClientError::Transport { message }) => assert_eq!(message, STOPPED),
            Err(error) => panic!("expected a transport error, got {error:?}"),
            Ok(_) => panic!("expected a transport error, got a response"),
        }
    }

    // The tests block on a futures executor, not tokio, as FRB does.

    #[test]
    fn starts_logs_in_and_shuts_down() {
        let dir = tempfile::tempdir().unwrap();
        let password = generate_secret();
        let local = block_on(start_local(config(&data_dir(&dir), &password))).unwrap();
        assert!(local.is_running());
        assert!(
            dir.path()
                .join("Application Support/data ?#%20/repolupe.db")
                .is_file()
        );

        // The admin needs no password change.
        let client = Client::local(&local, None);
        let response = login(&client, &local_admin_user_name(), &password).unwrap();
        assert!(!response.user.must_change_password);
        assert!(
            block_on(client.list_chats(None, None))
                .unwrap()
                .items
                .is_empty()
        );
        assert_eq!(block_on(client.me()).unwrap().user_name, "admin");

        block_on(local.shutdown());
        assert!(!local.is_running());
        assert_stopped(block_on(client.me()));
        assert_stopped(block_on(Client::local(&local, None).instance()));
        // Idempotent.
        block_on(local.shutdown());
    }

    #[test]
    fn restarts_on_the_same_data_dir() {
        let dir = tempfile::tempdir().unwrap();
        let data_dir = data_dir(&dir);
        let password = generate_secret();
        let mut config = config(&data_dir, &password);
        let key = config.token_encryption_key.clone();
        let local = block_on(start_local(config)).unwrap();
        let client = Client::local(&local, None);
        login(&client, &local_admin_user_name(), &password).unwrap();
        block_on(client.register_user(RegisterRequest {
            user_name: "alice".into(),
            email: None,
            password: "alice-password".into(),
            must_change_password: false,
        }))
        .unwrap();
        let token = client.token();
        block_on(local.shutdown());

        // The admin password of a later start is ignored, the data and sessions are kept.
        config = LocalConfig {
            data_dir,
            token_encryption_key: key,
            admin_password: generate_secret(),
        };
        let restarted = block_on(start_local(config)).unwrap();
        let client = Client::local(&restarted, token);
        let users = block_on(client.list_users()).unwrap();
        assert!(users.iter().any(|user| user.user_name == "alice"));
        login(&client, &local_admin_user_name(), &password).unwrap();
        assert_stopped(block_on(Client::local(&local, None).instance()));
        block_on(restarted.shutdown());
    }

    #[test]
    fn starting_again_replaces_the_running_instance() {
        let dir = tempfile::tempdir().unwrap();
        let password = generate_secret();
        let first = block_on(start_local(config(&data_dir(&dir), &password))).unwrap();
        let first_client = Client::local(&first, None);
        login(&first_client, &local_admin_user_name(), &password).unwrap();

        let second = block_on(start_local(config(&data_dir(&dir), &password))).unwrap();
        assert!(!first.is_running());
        assert_stopped(block_on(first_client.me()));
        let client = Client::local(&second, first_client.token());
        assert_eq!(block_on(client.me()).unwrap().user_name, "admin");

        // Shutting down the replaced instance leaves the new one alone.
        block_on(first.shutdown());
        assert!(second.is_running());
        assert_eq!(block_on(client.me()).unwrap().user_name, "admin");
        block_on(second.shutdown());
    }

    #[test]
    fn rejects_invalid_configs() {
        let dir = tempfile::tempdir().unwrap();
        let data_dir = data_dir(&dir);
        let password = generate_secret();
        for (config, expected) in [
            (
                LocalConfig {
                    token_encryption_key: "too short".into(),
                    ..config(&data_dir, &password)
                },
                "token encryption key",
            ),
            (config(&data_dir, "short"), "initial admin"),
            (config(" ", &password), "data directory"),
        ] {
            let error = block_on(start_local(config)).err().unwrap();
            assert!(error.message.contains(expected), "{error}");
        }
        // Nothing was left running.
        let local = block_on(start_local(config(&data_dir, &password))).unwrap();
        let client = Client::local(&local, None);
        login(&client, &local_admin_user_name(), &password).unwrap();
        block_on(local.shutdown());
    }

    #[test]
    fn generates_secrets() {
        let secret = generate_secret();
        assert_eq!(secret.len(), 64);
        assert!(secret.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(secret, generate_secret());
    }

    #[test]
    fn escapes_database_urls() {
        assert_eq!(
            database_url(Path::new("/data/a b?c#d%e.db")).unwrap(),
            "sqlite:///data/a b%3Fc%23d%25e.db"
        );
    }
}
