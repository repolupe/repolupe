use crate::dto::llm::LlmApiFormat;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use sqlx::types::Text;
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct LlmModel {
    pub id: Uuid,
    pub provider_id: Uuid,
    /// Sent to the API, e.g. `claude-opus-5-5`.
    pub api_name: String,
    /// Shown to users, e.g. `Claude Opus 5.5`. `None` shows `api_name`.
    pub display_name: Option<String>,
    pub max_output_tokens: Option<i32>,
    /// Per million tokens in the provider's currency, see [`crate::service::pricing::Pricing`].
    pub input_price: Option<Text<Decimal>>,
    pub output_price: Option<Text<Decimal>>,
    pub cache_read_price: Option<Text<Decimal>>,
    pub cache_write_price: Option<Text<Decimal>>,
    pub is_default: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Per million tokens. Input and output are set together, cache prices only with them.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ModelPrices {
    pub input: Option<Decimal>,
    pub output: Option<Decimal>,
    pub cache_read: Option<Decimal>,
    pub cache_write: Option<Decimal>,
}

/// A model as users see it, without the provider's connection details.
#[derive(Debug)]
pub struct AvailableModel {
    pub id: Uuid,
    /// Falls back to the API name.
    pub display_name: String,
    pub provider_id: Uuid,
    pub provider_name: String,
    pub is_default: bool,
}

/// Everything needed to send requests to a model.
#[derive(Debug)]
pub struct ModelConnection {
    pub model_id: Uuid,
    pub provider_id: Uuid,
    pub api_format: LlmApiFormat,
    pub base_url: String,
    pub api_key_encrypted: Option<Vec<u8>>,
    pub model: String,
    pub max_output_tokens: Option<i32>,
    pub currency: Option<String>,
    pub input_price: Option<Text<Decimal>>,
    pub output_price: Option<Text<Decimal>>,
    pub cache_read_price: Option<Text<Decimal>>,
    pub cache_write_price: Option<Text<Decimal>>,
}
