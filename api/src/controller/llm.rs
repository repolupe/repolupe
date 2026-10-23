use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::controller::encrypt_token;
use crate::dto::error::ErrorCode;
use crate::dto::llm::LlmApiFormat;
use crate::dto::llm::{
    ApiKeyChange, CreateLlmProviderRequest, LlmModelDto, LlmModelRequest, LlmProviderDto, ModelDto,
    RemoteModelDto, SetDefaultModelRequest, UpdateLlmProviderRequest,
};
use crate::model::llm_model::ModelPrices;
use crate::model::llm_provider::LlmProvider;
use crate::repository::llm::{LlmModelFields, LlmProviderChanges, NewLlmProvider};
use crate::service::llm::LlmError;
use crate::service::llm_config::decrypt_api_key;
use crate::util::extract::{JsonBody, PathParam};
use crate::util::validation::ValidationError;
use crate::{repository, util};
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use rust_decimal::Decimal;
use std::str::FromStr;
use url::Url;
use uuid::Uuid;

/// All models, for users choosing their default model.
pub(crate) async fn list_models(
    State(state): State<AppState>,
) -> Result<Json<Vec<ModelDto>>, AppError> {
    let models = repository::llm::list_available_models(&state.db).await?;
    Ok(Json(models.into_iter().map(Into::into).collect()))
}

/// Sets the model used by users who did not choose one, the previous default model loses the
/// flag. It cannot be unset, only moved to another model.
pub(crate) async fn set_default_model(
    State(state): State<AppState>,
    JsonBody(payload): JsonBody<SetDefaultModelRequest>,
) -> Result<StatusCode, AppError> {
    if !repository::llm::set_default_model(&state.db, payload.model_id).await? {
        return Err(unknown_model());
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Providers with their models, including the ones without models.
pub(crate) async fn list_providers(
    State(state): State<AppState>,
) -> Result<Json<Vec<LlmProviderDto>>, AppError> {
    let providers = repository::llm::list_providers(&state.db).await?;
    let mut models = repository::llm::list_models(&state.db).await?;
    let providers = providers
        .into_iter()
        .map(|provider| {
            let (own, rest) = models
                .drain(..)
                .partition(|model| model.provider_id == provider.id);
            models = rest;
            LlmProviderDto::new(provider, own.into_iter().map(Into::into).collect())
        })
        .collect();
    Ok(Json(providers))
}

pub(crate) async fn create_provider(
    State(state): State<AppState>,
    JsonBody(payload): JsonBody<CreateLlmProviderRequest>,
) -> Result<(StatusCode, Json<LlmProviderDto>), AppError> {
    let name = parse_name(&payload.name)?;
    let base_url = parse_base_url(payload.api_format, payload.base_url.as_deref())?;
    let currency = parse_currency(payload.currency.as_deref())?;
    let api_key = match payload.api_key.as_deref().map(str::trim) {
        Some(key) if !key.is_empty() => Some(parse_api_key(key)?),
        _ => None,
    };
    require_api_key(payload.api_format, &base_url, api_key.is_some())?;

    // The id is the key's associated data, so it is generated before encrypting.
    let id = Uuid::now_v7();
    let api_key = api_key.map(|k| encrypt_token(&state, id, k)).transpose()?;

    let provider = repository::llm::create_provider(
        &state.db,
        NewLlmProvider {
            id,
            name,
            api_format: payload.api_format,
            base_url: &base_url,
            api_key,
            currency: currency.as_deref(),
        },
    )
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(LlmProviderDto::new(provider, vec![])),
    ))
}

pub(crate) async fn update_provider(
    State(state): State<AppState>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<UpdateLlmProviderRequest>,
) -> Result<Json<LlmProviderDto>, AppError> {
    let name = parse_name(&payload.name)?;
    let base_url = parse_base_url(payload.api_format, payload.base_url.as_deref())?;
    let currency = parse_currency(payload.currency.as_deref())?;

    let current = find_provider(&state, id).await?;
    let host_changed = origin(&base_url)? != origin(&current.base_url)?;

    // `None` keeps the key, `Some(_)` replaces it.
    let new_key: Option<Option<&str>> = match &payload.api_key {
        ApiKeyChange::Keep if host_changed && current.api_key_encrypted.is_some() => {
            return Err(AppError::Unprocessable(
                ErrorCode::TokenRequired,
                "The host changed, so the API key cannot be kept. Set a new key, or remove it if the new server needs none".to_string(),
            ));
        }
        ApiKeyChange::Keep => None,
        ApiKeyChange::Remove => Some(None),
        ApiKeyChange::Set { value } => Some(Some(parse_api_key(value)?)),
    };
    let has_key = match new_key {
        Some(key) => key.is_some(),
        None => current.api_key_encrypted.is_some(),
    };
    require_api_key(payload.api_format, &base_url, has_key)?;

    let api_key = new_key
        .map(|key| key.map(|k| encrypt_token(&state, id, k)).transpose())
        .transpose()?;

    let updated = repository::llm::update_provider(
        &state.db,
        id,
        &current.base_url,
        LlmProviderChanges {
            name,
            api_format: payload.api_format,
            base_url: &base_url,
            api_key,
            currency: currency.as_deref(),
        },
    )
    .await?;
    let Some(provider) = updated else {
        if currency.is_none() && has_priced_models(&state, id).await? {
            return Err(ValidationError(
                "The currency is needed while models of the provider have prices".to_string(),
            )
            .into());
        }
        return Err(match repository::llm::get_provider(&state.db, id).await? {
            Some(_) => AppError::Conflict(
                ErrorCode::Conflict,
                "The provider was changed by another request, please retry".to_string(),
            ),
            None => AppError::NotFound,
        });
    };

    let models = repository::llm::list_models(&state.db)
        .await?
        .into_iter()
        .filter(|model| model.provider_id == id)
        .map(Into::into)
        .collect();
    Ok(Json(LlmProviderDto::new(provider, models)))
}

/// Also deletes its models. Deleting a missing provider also succeeds, so the request is safe
/// to retry.
pub(crate) async fn delete_provider(
    State(state): State<AppState>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    repository::llm::delete_provider(&state.db, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The models the provider's server offers, so admins can choose which to add. Fails with
/// `AUTH_FAILED` if the server rejects the key, and `REMOTE_UNREACHABLE` if it cannot be
/// reached or does not list its models.
pub(crate) async fn list_remote_models(
    State(state): State<AppState>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<Vec<RemoteModelDto>>, AppError> {
    let provider = find_provider(&state, id).await?;
    let api_key = decrypt_api_key(&state, provider.id, provider.api_key_encrypted.as_deref())?;
    let models = state
        .llm
        .list_models(provider.api_format, &provider.base_url, api_key.as_deref())
        .await
        .map_err(|e| remote_models_error(&provider, e))?;
    Ok(Json(models.into_iter().map(Into::into).collect()))
}

/// Only admins see these, so the server's own messages are included.
fn remote_models_error(provider: &LlmProvider, error: LlmError) -> AppError {
    match error {
        LlmError::Status { status, message } => match status.as_u16() {
            401 | 403 => AppError::Unprocessable(
                ErrorCode::AuthFailed,
                format!("The server rejected the API key: {message}"),
            ),
            404 => AppError::BadGateway(
                ErrorCode::RemoteUnreachable,
                "The server does not list its models, add them by name instead".to_string(),
            ),
            _ => AppError::BadGateway(
                ErrorCode::RemoteUnreachable,
                format!("The server responded with {status}: {message}"),
            ),
        },
        LlmError::Http(e) => {
            tracing::warn!(
                "Failed to list the models of LLM provider {}: {e:?}",
                provider.id
            );
            AppError::BadGateway(
                ErrorCode::RemoteUnreachable,
                format!("Could not reach {}", provider.base_url),
            )
        }
        LlmError::Request(message) => AppError::BadGateway(
            ErrorCode::RemoteUnreachable,
            format!("Could not send the request: {message}"),
        ),
        LlmError::InvalidResponse(message) | LlmError::Stream { message, .. } => {
            AppError::BadGateway(
                ErrorCode::RemoteUnreachable,
                format!("The server sent no valid model list: {message}"),
            )
        }
    }
}

/// The first model becomes the default model.
pub(crate) async fn create_model(
    State(state): State<AppState>,
    PathParam(provider_id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<LlmModelRequest>,
) -> Result<(StatusCode, Json<LlmModelDto>), AppError> {
    let fields = parse_model_fields(&payload)?;
    let has_prices = fields.prices.input.is_some();
    let Some(model) = repository::llm::create_model(&state.db, provider_id, fields).await? else {
        if has_prices
            && repository::llm::get_provider(&state.db, provider_id)
                .await?
                .is_some()
        {
            return Err(prices_need_currency());
        }
        return Err(AppError::NotFound);
    };
    Ok((StatusCode::CREATED, Json(model.into())))
}

pub(crate) async fn update_model(
    State(state): State<AppState>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<LlmModelRequest>,
) -> Result<Json<LlmModelDto>, AppError> {
    let fields = parse_model_fields(&payload)?;
    let has_prices = fields.prices.input.is_some();
    let Some(model) = repository::llm::update_model(&state.db, id, fields).await? else {
        if has_prices && repository::llm::model_exists(&state.db, id).await? {
            return Err(prices_need_currency());
        }
        return Err(AppError::NotFound);
    };
    Ok(Json(model.into()))
}

/// Users who chose the model fall back to the default model. Deleting the default model leaves
/// none. Deleting a missing model also succeeds, so the request is safe to retry.
pub(crate) async fn delete_model(
    State(state): State<AppState>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    repository::llm::delete_model(&state.db, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) fn unknown_model() -> AppError {
    AppError::Unprocessable(ErrorCode::UnknownModel, "Unknown model".to_string())
}

fn prices_need_currency() -> AppError {
    ValidationError("Prices need a currency, set one for the provider first".to_string()).into()
}

async fn has_priced_models(state: &AppState, provider_id: Uuid) -> Result<bool, AppError> {
    let models = repository::llm::list_models(&state.db).await?;
    Ok(models
        .iter()
        .any(|model| model.provider_id == provider_id && model.input_price.is_some()))
}

async fn find_provider(state: &AppState, id: Uuid) -> Result<LlmProvider, AppError> {
    repository::llm::get_provider(&state.db, id)
        .await?
        .ok_or(AppError::NotFound)
}

/// The official APIs always need a key.
fn require_api_key(
    api_format: LlmApiFormat,
    base_url: &str,
    has_key: bool,
) -> Result<(), ValidationError> {
    if !has_key && base_url == api_format.default_base_url() {
        return Err(ValidationError(
            "An API key is required, unless the base URL points to a server without authentication"
                .to_string(),
        ));
    }
    Ok(())
}

fn origin(base_url: &str) -> Result<url::Origin, AppError> {
    Url::parse(base_url)
        .map(|url| url.origin())
        .map_err(|e| AppError::InternalServerError(format!("Invalid base URL {base_url}: {e}")))
}

fn parse_name(name: &str) -> Result<&str, ValidationError> {
    let name = name.trim();
    util::validation::validate_name(name)?;
    Ok(name)
}

fn parse_base_url(
    api_format: LlmApiFormat,
    base_url: Option<&str>,
) -> Result<String, ValidationError> {
    match base_url.map(str::trim) {
        Some(base_url) if !base_url.is_empty() => util::validation::parse_llm_base_url(base_url),
        _ => Ok(api_format.default_base_url().to_string()),
    }
}

fn parse_currency(currency: Option<&str>) -> Result<Option<String>, ValidationError> {
    match currency.map(str::trim) {
        Some(currency) if !currency.is_empty() => {
            util::validation::parse_currency(currency).map(Some)
        }
        _ => Ok(None),
    }
}

fn parse_api_key(api_key: &str) -> Result<&str, ValidationError> {
    let api_key = api_key.trim();
    util::validation::validate_api_key(api_key)?;
    Ok(api_key)
}

/// Accepts what `Decimal` accepts as JSON: a decimal or in scientific notation.
fn parse_price(price: Option<&str>) -> Result<Option<Decimal>, ValidationError> {
    price
        .map(|price| {
            Decimal::from_str(price)
                .or_else(|_| Decimal::from_scientific(price))
                .map_err(|_| ValidationError("Prices must be decimal numbers".to_string()))
        })
        .transpose()
}

fn parse_model_api_name(api_name: &str) -> Result<&str, ValidationError> {
    let api_name = api_name.trim();
    util::validation::validate_model_api_name(api_name)?;
    Ok(api_name)
}

fn parse_model_fields(payload: &LlmModelRequest) -> Result<LlmModelFields<'_>, ValidationError> {
    let api_name = parse_model_api_name(&payload.api_name)?;
    let display_name = match payload.display_name.as_deref().map(str::trim) {
        Some(display_name) if !display_name.is_empty() && display_name != api_name => {
            Some(parse_name(display_name)?)
        }
        _ => None,
    };
    if let Some(tokens) = payload.max_output_tokens {
        util::validation::validate_max_output_tokens(tokens)?;
    }
    let prices = ModelPrices {
        input: parse_price(payload.input_price.as_deref())?,
        output: parse_price(payload.output_price.as_deref())?,
        cache_read: parse_price(payload.cache_read_price.as_deref())?,
        cache_write: parse_price(payload.cache_write_price.as_deref())?,
    };
    util::validation::validate_model_prices(&prices)?;
    Ok(LlmModelFields {
        api_name,
        display_name,
        max_output_tokens: payload.max_output_tokens,
        prices,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_prices_like_decimal_json() {
        let price = |value: &str| parse_price(Some(value)).unwrap().unwrap();
        assert_eq!(price("15.50"), Decimal::new(1550, 2));
        assert_eq!(price("1.5e1"), Decimal::new(15, 0));
        assert_eq!(parse_price(None).unwrap(), None);
        assert!(parse_price(Some("3 USD")).is_err());
        assert!(parse_price(Some("")).is_err());
    }
}
