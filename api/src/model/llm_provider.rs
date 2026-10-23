use crate::dto::llm::LlmApiFormat;
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct LlmProvider {
    pub id: Uuid,
    pub name: String,
    pub api_format: LlmApiFormat,
    pub base_url: String,
    pub api_key_encrypted: Option<Vec<u8>>,
    pub api_key_hint: Option<String>,
    /// ISO 4217 code of the model prices, e.g. `USD`. `None` if its models have no prices.
    pub currency: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
