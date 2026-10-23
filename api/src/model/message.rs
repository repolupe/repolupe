use crate::dto::chat::MessageRole;
use crate::dto::chat::MessageStatus;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use sqlx::types::Text;
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Message {
    pub id: Uuid,
    pub role: MessageRole,
    pub content: String,
    pub status: MessageStatus,
    pub error: Option<String>,
    /// The model that wrote the answer, `None` for user messages or if the model was deleted.
    pub model_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    /// When the answer reached its final status, `None` for user messages, while `GENERATING`,
    /// or if it was interrupted by a restart.
    pub finished_at: Option<DateTime<Utc>>,
    /// Tokens used for the answer, summed over the tool loop. All `None` for user messages, while
    /// `GENERATING`, or if unknown (e.g. interrupted by a restart).
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub cache_write_tokens: Option<i64>,
    /// In `cost_currency`, at the prices when the answer finished. `None` if the model had no
    /// prices or the tokens are unknown.
    pub cost: Option<Text<Decimal>>,
    pub cost_currency: Option<String>,
}
