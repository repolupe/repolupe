use crate::config::error::AppError;
use crate::config::runtime::RuntimeConfig;
use crate::config::state::AppState;
use crate::dto::config::ConfigEntryDto;
use crate::service;
use crate::util::extract::JsonBody;
use axum::Json;
use axum::extract::State;
use std::collections::BTreeMap;

/// Every environment variable, sorted by key, with the secrets masked.
pub(crate) async fn get_config(State(state): State<AppState>) -> Json<Vec<ConfigEntryDto>> {
    Json(config_entries(&state))
}

/// Replaces all overrides, so keys missing from the body fall back to `env`. Applied
/// immediately.
pub(crate) async fn set_config(
    State(state): State<AppState>,
    JsonBody(overrides): JsonBody<BTreeMap<String, String>>,
) -> Result<Json<Vec<ConfigEntryDto>>, AppError> {
    service::runtime_config::update(&state, &overrides).await?;
    Ok(Json(config_entries(&state)))
}

fn config_entries(state: &AppState) -> Vec<ConfigEntryDto> {
    let mut overrides = state.runtime_config.overrides();
    state
        .env
        .iter()
        .map(|(key, env)| ConfigEntryDto {
            key: key.clone(),
            env: env.clone(),
            override_value: overrides.remove(key),
            runtime: RuntimeConfig::KEYS.contains(&key.as_str()),
        })
        .collect()
}
