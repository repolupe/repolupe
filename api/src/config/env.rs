//! The environment variables of the `repolupe` binary (see `.env.example.full`), read only by the
//! explicit `from_env` constructors: [`Config::from_env`], [`DatabaseConfig::from_env`] and
//! [`RuntimeConfig::from_env`]. The keys of [`RuntimeConfig`] are also the keys admins override
//! with `POST /api/v1/config`.

use crate::config::init::{Config, DEFAULT_SESSION_IDLE_TIMEOUT, DatabaseConfig};
use crate::config::runtime::RuntimeConfig;
use std::collections::BTreeMap;
use std::path::PathBuf;

/// [`DatabaseConfig::url`], defaults to [`DEFAULT_DATABASE_URL`]. Secret.
pub const DATABASE_URL: &str = "DATABASE_URL";
/// [`Config::token_encryption_key`], required. Secret.
pub const TOKEN_ENCRYPTION_KEY: &str = "TOKEN_ENCRYPTION_KEY";
/// [`Config::initial_admin_password`]. Secret.
pub const ADMIN_PASSWORD: &str = "ADMIN_PASSWORD";
/// [`Config::repos_dir`], defaults to [`DEFAULT_REPOS_DIR`].
pub const REPOS_DIR: &str = "REPOS_DIR";
/// [`Config::attachments_dir`], defaults to [`DEFAULT_ATTACHMENTS_DIR`].
pub const ATTACHMENTS_DIR: &str = "ATTACHMENTS_DIR";
/// [`Config::frontend_dir`].
pub const FRONTEND_DIR: &str = "FRONTEND_DIR";
/// [`Config::debug_api`], enabled by `true`.
pub const DEBUG_API: &str = "DEBUG_API";
/// [`Config::ocr_api_key_mistral`]. Secret.
pub const OCR_API_KEY_MISTRAL: &str = "OCR_API_KEY_MISTRAL";
/// [`RuntimeConfig::instance_name`].
pub const INSTANCE_NAME: &str = "INSTANCE_NAME";
/// [`RuntimeConfig::ocr_engine`].
pub const OCR_ENGINE: &str = "OCR_ENGINE";
/// [`RuntimeConfig::ocr_languages`].
pub const OCR_LANGUAGES: &str = "OCR_LANGUAGES";
/// [`RuntimeConfig::ocr_scan_confidence`].
pub const OCR_SCAN_CONFIDENCE: &str = "OCR_SCAN_CONFIDENCE";

/// A file in the working directory, created if missing.
pub const DEFAULT_DATABASE_URL: &str = "sqlite:rp.db";
/// Relative to the working directory.
pub const DEFAULT_REPOS_DIR: &str = "repos";
/// Relative to the working directory.
pub const DEFAULT_ATTACHMENTS_DIR: &str = "attachments";

/// Shown instead of the value of a secret by [`Config::to_env_map`].
pub(crate) const SECRET_MASK: &str = "******";

/// A missing or invalid environment variable.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub struct EnvError(String);

impl Config {
    /// Reads the config from the environment variables, see [`crate::env`]. Migrations and
    /// background tasks are enabled, and the initial admin has to change its password.
    pub fn from_env() -> Result<Self, EnvError> {
        Self::from_vars(env_var)
    }

    fn from_vars(var: impl Fn(&str) -> Option<String>) -> Result<Self, EnvError> {
        let Some(token_encryption_key) = var(TOKEN_ENCRYPTION_KEY) else {
            return Err(EnvError(format!(
                "{TOKEN_ENCRYPTION_KEY} must be set to a random string of at least 32 characters, e.g. `$(openssl rand -hex 32)`"
            )));
        };

        let repos_dir = var(REPOS_DIR).unwrap_or_else(|| {
            tracing::info!("{REPOS_DIR} is not set, using default value");
            DEFAULT_REPOS_DIR.to_string()
        });
        let attachments_dir = var(ATTACHMENTS_DIR).unwrap_or_else(|| {
            tracing::info!("{ATTACHMENTS_DIR} is not set, using default value");
            DEFAULT_ATTACHMENTS_DIR.to_string()
        });

        Ok(Self {
            token_encryption_key,
            repos_dir: PathBuf::from(repos_dir),
            attachments_dir: PathBuf::from(attachments_dir),
            frontend_dir: var(FRONTEND_DIR).map(PathBuf::from),
            initial_admin_password: var(ADMIN_PASSWORD),
            initial_admin_must_change_password: true,
            session_idle_timeout: Some(DEFAULT_SESSION_IDLE_TIMEOUT),
            run_migrations: true,
            background_tasks: true,
            debug_api: var(DEBUG_API).is_some_and(|value| value == "true"),
            ocr_api_key_mistral: var(OCR_API_KEY_MISTRAL),
            runtime: RuntimeConfig::from_vars(var)?,
        })
    }

    /// The config by every environment variable, `None` if unset, with [`SECRET_MASK`] instead
    /// of the secrets. Shown to admins by `GET /api/v1/config`.
    pub(crate) fn to_env_map(&self) -> BTreeMap<String, Option<String>> {
        let mut env: BTreeMap<String, Option<String>> = self
            .runtime
            .to_map()
            .into_iter()
            .map(|(key, value)| (key, Some(value)))
            .collect();
        let secret = |set: bool| set.then(|| SECRET_MASK.to_string());
        // The pool is passed to `Repolupe::new` separately, but there always is one.
        env.insert(DATABASE_URL.to_string(), secret(true));
        env.insert(TOKEN_ENCRYPTION_KEY.to_string(), secret(true));
        env.insert(
            ADMIN_PASSWORD.to_string(),
            secret(self.initial_admin_password.is_some()),
        );
        env.insert(
            REPOS_DIR.to_string(),
            Some(self.repos_dir.display().to_string()),
        );
        env.insert(
            ATTACHMENTS_DIR.to_string(),
            Some(self.attachments_dir.display().to_string()),
        );
        env.insert(
            FRONTEND_DIR.to_string(),
            self.frontend_dir
                .as_ref()
                .map(|dir| dir.display().to_string()),
        );
        env.insert(DEBUG_API.to_string(), Some(self.debug_api.to_string()));
        env.insert(
            OCR_API_KEY_MISTRAL.to_string(),
            secret(self.ocr_api_key_mistral.is_some()),
        );
        env
    }
}

impl DatabaseConfig {
    pub fn from_env() -> Self {
        Self::from_vars(env_var)
    }

    fn from_vars(var: impl Fn(&str) -> Option<String>) -> Self {
        let url = var(DATABASE_URL).unwrap_or_else(|| {
            tracing::info!("{DATABASE_URL} is not set, using default value");
            DEFAULT_DATABASE_URL.to_string()
        });
        Self { url }
    }
}

impl RuntimeConfig {
    /// [`RuntimeConfig::default`] with the values of the environment variables that are set.
    pub fn from_env() -> Result<Self, EnvError> {
        Self::from_vars(env_var)
    }

    fn from_vars(var: impl Fn(&str) -> Option<String>) -> Result<Self, EnvError> {
        let mut runtime = Self::default();
        for key in Self::KEYS {
            if let Some(value) = var(key) {
                runtime
                    .set(key, &value)
                    .map_err(|e| EnvError(format!("Invalid environment variable {e}")))?;
            }
        }
        Ok(runtime)
    }
}

/// Blank values count as unset.
fn env_var(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .filter(|value| !value.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::init::OcrEngine;

    fn vars(vars: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let vars: BTreeMap<String, String> = vars
            .iter()
            .map(|(key, value)| (key.to_string(), value.to_string()))
            .collect();
        move |key| vars.get(key).cloned()
    }

    #[test]
    fn reads_config_with_defaults() {
        let config = Config::from_vars(vars(&[(TOKEN_ENCRYPTION_KEY, "secret")])).unwrap();
        assert_eq!(config.token_encryption_key, "secret");
        assert_eq!(config.repos_dir, PathBuf::from(DEFAULT_REPOS_DIR));
        assert_eq!(
            config.attachments_dir,
            PathBuf::from(DEFAULT_ATTACHMENTS_DIR)
        );
        assert_eq!(config.frontend_dir, None);
        assert!(config.initial_admin_password.is_none());
        assert!(config.initial_admin_must_change_password);
        assert!(!config.debug_api);
        assert_eq!(config.runtime, RuntimeConfig::default());
        assert_eq!(
            DatabaseConfig::from_vars(vars(&[])).url,
            DEFAULT_DATABASE_URL
        );
    }

    #[test]
    fn reads_config() {
        let config = Config::from_vars(vars(&[
            (TOKEN_ENCRYPTION_KEY, "secret"),
            (ADMIN_PASSWORD, "password"),
            (REPOS_DIR, "/data/repos"),
            (ATTACHMENTS_DIR, "/data/attachments"),
            (FRONTEND_DIR, "/frontend"),
            (DEBUG_API, "true"),
            (OCR_API_KEY_MISTRAL, "key"),
            (OCR_ENGINE, "mistral"),
            (OCR_SCAN_CONFIDENCE, "0.7"),
        ]))
        .unwrap();
        assert_eq!(config.repos_dir, PathBuf::from("/data/repos"));
        assert_eq!(config.ocr_api_key_mistral.as_deref(), Some("key"));
        assert_eq!(config.runtime.ocr_engine, Some(OcrEngine::Mistral));
        assert_eq!(config.runtime.ocr_scan_confidence, 0.7);
        let set = |value: &str| Some(value.to_string());
        assert_eq!(
            config.to_env_map(),
            BTreeMap::from([
                (ADMIN_PASSWORD.to_string(), set(SECRET_MASK)),
                (ATTACHMENTS_DIR.to_string(), set("/data/attachments")),
                (DATABASE_URL.to_string(), set(SECRET_MASK)),
                (DEBUG_API.to_string(), set("true")),
                (FRONTEND_DIR.to_string(), set("/frontend")),
                (INSTANCE_NAME.to_string(), set("Repolupe")),
                (OCR_API_KEY_MISTRAL.to_string(), set(SECRET_MASK)),
                (OCR_ENGINE.to_string(), set("mistral")),
                (OCR_LANGUAGES.to_string(), set("eng")),
                (OCR_SCAN_CONFIDENCE.to_string(), set("0.7")),
                (REPOS_DIR.to_string(), set("/data/repos")),
                (TOKEN_ENCRYPTION_KEY.to_string(), set(SECRET_MASK)),
            ])
        );

        let config = Config::from_vars(vars(&[(TOKEN_ENCRYPTION_KEY, "secret")])).unwrap();
        let env = config.to_env_map();
        assert_eq!(env[ADMIN_PASSWORD], None);
        assert_eq!(env[FRONTEND_DIR], None);
        assert_eq!(env[OCR_API_KEY_MISTRAL], None);
    }

    #[test]
    fn rejects_invalid_config() {
        for invalid in [
            vec![],
            vec![(TOKEN_ENCRYPTION_KEY, "secret"), (OCR_ENGINE, "magic")],
            vec![
                (TOKEN_ENCRYPTION_KEY, "secret"),
                (OCR_SCAN_CONFIDENCE, "70%"),
            ],
        ] {
            assert!(Config::from_vars(vars(&invalid)).is_err(), "{invalid:?}");
        }
    }
}
