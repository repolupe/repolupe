//! The [`RuntimeConfig`] in effect: the defaults from [`crate::Config::runtime`] with the
//! overrides admins stored in the `config` table, which are applied without a restart.

use crate::config::error::AppError;
use crate::config::init;
use crate::config::runtime::RuntimeConfig;
use crate::config::state::{AppState, DatabasePool};
use crate::repository;
use std::collections::BTreeMap;
use std::sync::{Arc, RwLock};

pub(crate) struct LiveConfig {
    defaults: RuntimeConfig,
    /// Whether [`crate::config::init::OcrEngine::Mistral`] can be selected.
    has_ocr_api_key_mistral: bool,
    current: RwLock<Arc<RuntimeConfig>>,
    /// The overrides [`Self::current`] was built from: the stored ones, without those skipped
    /// on startup.
    overrides: RwLock<BTreeMap<String, String>>,
    /// Held while the overrides are replaced, so the stored ones and [`Self::current`] agree.
    updates: tokio::sync::Mutex<()>,
}

impl LiveConfig {
    /// Applies the stored overrides to `defaults`. Invalid ones, e.g. stored by an older
    /// version, or `mistral` after `OCR_API_KEY_MISTRAL` was removed, are skipped, so they cannot
    /// keep the server from starting.
    pub(crate) async fn load(
        db: &DatabasePool,
        defaults: RuntimeConfig,
        has_ocr_api_key_mistral: bool,
    ) -> Result<Self, AppError> {
        let mut current = defaults.clone();
        let mut overrides = BTreeMap::new();
        for (key, value) in repository::config::get_config(db).await? {
            let mut config = current.clone();
            match config
                .set(&key, &value)
                .and_then(|()| config.validate_ocr_engine(has_ocr_api_key_mistral))
            {
                Ok(()) => {
                    tracing::info!("{key} is overridden in the database");
                    current = config;
                    overrides.insert(key, value);
                }
                Err(e) => tracing::warn!("Ignoring the stored config value: {e}"),
            }
        }
        Ok(Self {
            defaults,
            has_ocr_api_key_mistral,
            current: RwLock::new(Arc::new(current)),
            overrides: RwLock::new(overrides),
            updates: tokio::sync::Mutex::new(()),
        })
    }

    pub(crate) fn current(&self) -> Arc<RuntimeConfig> {
        self.current.read().unwrap().clone()
    }

    pub(crate) fn overrides(&self) -> BTreeMap<String, String> {
        self.overrides.read().unwrap().clone()
    }
}

/// Replaces all overrides with `overrides` and applies them, so keys missing from it fall
/// back to the defaults.
pub(crate) async fn update(
    state: &AppState,
    overrides: &BTreeMap<String, String>,
) -> Result<(), AppError> {
    let live = &state.runtime_config;
    let config = live
        .defaults
        .with_overrides(overrides)
        .and_then(|config| {
            config.validate_ocr_engine(live.has_ocr_api_key_mistral)?;
            Ok(config)
        })
        .map_err(|e| AppError::BadRequest(e.to_string()))?;

    let _guard = live.updates.lock().await;
    repository::config::set_config(&state.db, overrides).await?;
    // Running extractions finish with the previous settings.
    let ocr = config.ocr();
    if ocr != live.current().ocr() {
        init::log_ocr(ocr.as_ref());
        state.extractor.set_ocr(ocr.as_ref());
    }
    *live.current.write().unwrap() = Arc::new(config);
    *live.overrides.write().unwrap() = overrides.clone();
    Ok(())
}
