use crate::dto::chat::MessageRole;
use crate::dto::chat::MessageStatus;
use chrono::{DateTime, Utc};
use flate2::Compression;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::types::Text;
use std::io::{self, Read, Write};
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
    /// `GENERATING` (except in the snapshot of a live generation, which has the tokens so far), or
    /// if unknown (e.g. interrupted by a restart).
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub cache_write_tokens: Option<i64>,
    /// How long the responses of the language model took in milliseconds, from sending each
    /// request to its last token, summed over the tool loop. Known exactly when the tokens are,
    /// 0 despite output tokens for answers from before it was measured.
    pub response_ms: Option<i64>,
    /// In `cost_currency`, at the prices when the answer finished. `None` if the model had no
    /// prices or the tokens are unknown.
    pub cost: Option<Text<Decimal>>,
    pub cost_currency: Option<String>,
}

/// What the language model got and returned for an answer, stored as gzip-compressed JSON in
/// `raw_answers`: the system prompt and tools, which stay the same during the tool loop, and the
/// messages of the last request followed by the last response. Each request only appends to the
/// one before, so the messages contain every response and the results of its tool calls. Kept
/// apart from the DTO, so stored answers stay readable when the API changes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RawAnswer {
    pub system: String,
    pub tools: Vec<RawTool>,
    /// The chat before the answer as the model saw it, then the responses of the answer and
    /// the results of their tool calls. Ends with the partial response of an answer that failed
    /// or was cancelled while the text was streamed.
    pub messages: Vec<RawMessage>,
}

impl RawAnswer {
    /// As stored, JSON compressed with gzip, which shrinks it to about a quarter.
    pub(crate) fn to_gzip(&self) -> io::Result<Vec<u8>> {
        let json = serde_json::to_vec(self)?;
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(&json)?;
        encoder.finish()
    }

    pub(crate) fn from_gzip(gzip: &[u8]) -> io::Result<Self> {
        let mut json = Vec::new();
        GzDecoder::new(gzip).read_to_end(&mut json)?;
        Ok(serde_json::from_slice(&json)?)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RawTool {
    pub name: String,
    pub description: String,
    /// JSON schema of the arguments.
    pub input_schema: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RawMessage {
    pub role: MessageRole,
    pub content: Vec<RawBlock>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RawBlock {
    Text {
        text: String,
    },
    /// Reasoning the model showed. Empty if the provider withheld it, then `redacted`.
    Reasoning {
        text: String,
        redacted: bool,
    },
    ToolUse {
        id: String,
        name: String,
        /// The arguments, usually an object. A string holds arguments that were not a JSON
        /// object.
        input: Value,
    },
    /// Answers the [`RawBlock::ToolUse`] with the same id.
    ToolResult {
        tool_use_id: String,
        content: String,
        is_error: bool,
    },
}
