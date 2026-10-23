use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::error::ErrorCode;
use crate::repository;
use crate::service::llm::LlmConfig;
use crate::service::pricing::Pricing;
use uuid::Uuid;

/// The model that writes an answer.
pub(crate) struct AnsweringModel {
    /// Recorded on the answer.
    pub id: Uuid,
    pub config: LlmConfig,
    /// `None` if the model has no prices, then the answer has no cost.
    pub pricing: Option<Pricing>,
}

/// The model that answers in a chat: `model_id` (chosen for the chat), else
/// the one the user chose, else the default model. A `model_id` that no longer exists is
/// skipped, like a deleted model clears the column.
pub(crate) async fn resolve(
    state: &AppState,
    user_id: Uuid,
    model_id: Option<Uuid>,
) -> Result<AnsweringModel, AppError> {
    let connection = repository::llm::get_model_connection(&state.db, user_id, model_id)
        .await?
        .ok_or_else(|| {
            AppError::Unprocessable(
                ErrorCode::NoModelConfigured,
                "No language model is configured, ask an admin to add one".to_string(),
            )
        })?;
    let api_key = decrypt_api_key(
        state,
        connection.provider_id,
        connection.api_key_encrypted.as_deref(),
    )?;
    Ok(AnsweringModel {
        id: connection.model_id,
        pricing: Pricing::new(
            connection.currency,
            connection.input_price.map(|price| price.0),
            connection.output_price.map(|price| price.0),
            connection.cache_read_price.map(|price| price.0),
            connection.cache_write_price.map(|price| price.0),
        ),
        config: LlmConfig {
            api_format: connection.api_format,
            api_key,
            model: connection.model,
            base_url: connection.base_url,
            max_output_tokens: connection
                .max_output_tokens
                .and_then(|tokens| u32::try_from(tokens).ok()),
        },
    })
}

/// The provider's API key, `None` for servers without authentication.
pub(crate) fn decrypt_api_key(
    state: &AppState,
    provider_id: Uuid,
    api_key_encrypted: Option<&[u8]>,
) -> Result<Option<String>, AppError> {
    api_key_encrypted
        .map(|ciphertext| {
            state
                .token_cipher
                .decrypt(provider_id, ciphertext)
                .map_err(|e| {
                    AppError::InternalServerError(format!(
                        "Failed to decrypt API key of LLM provider {provider_id}: {e}"
                    ))
                })
        })
        .transpose()
}
