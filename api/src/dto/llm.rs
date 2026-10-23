//! LLM providers and their models.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fmt;
use uuid::Uuid;

/// The API format of an LLM server, not its vendor.
#[derive(Clone, Copy, Eq, PartialEq, Debug, Hash, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum LlmApiFormat {
    /// The Anthropic Messages API.
    Anthropic,
    /// The OpenAI Chat Completions API, also offered by OpenRouter, Ollama, vLLM, LM Studio, etc.
    #[sqlx(rename = "OPENAI")]
    #[serde(rename = "OPENAI")]
    OpenAi,
}

impl LlmApiFormat {
    /// Used when a provider is created without a base URL.
    pub(crate) fn default_base_url(self) -> &'static str {
        match self {
            Self::Anthropic => "https://api.anthropic.com",
            Self::OpenAi => "https://api.openai.com/v1",
        }
    }
}

impl fmt::Display for LlmApiFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Anthropic => "anthropic",
            Self::OpenAi => "openai",
        })
    }
}

#[derive(Serialize, Deserialize)]
pub struct LlmProviderDto {
    pub id: Uuid,
    pub name: String,
    pub api_format: LlmApiFormat,
    pub base_url: String,
    /// `null` for servers without authentication. The key itself is never returned.
    pub api_key: Option<ApiKeyDto>,
    /// ISO 4217 code of the model prices, e.g. `USD`. `null` if its models have no prices.
    pub currency: Option<String>,
    pub models: Vec<LlmModelDto>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct ApiKeyDto {
    pub hint: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct LlmModelDto {
    pub id: Uuid,
    pub provider_id: Uuid,
    /// Sent to the API, e.g. `claude-opus-5-5`.
    pub api_name: String,
    /// Shown to users, e.g. `Claude Opus 5.5`. `null` shows `api_name`.
    pub display_name: Option<String>,
    /// `null` uses the default of the API format.
    pub max_output_tokens: Option<i32>,
    /// Per million tokens in the provider's currency, as decimal strings. `null` if unknown.
    pub input_price: Option<String>,
    pub output_price: Option<String>,
    /// `null` charges `input_price`.
    pub cache_read_price: Option<String>,
    /// `null` charges `input_price`.
    pub cache_write_price: Option<String>,
    pub is_default: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A model as users see it, see [`LlmModelDto`] for admins.
#[derive(Serialize, Deserialize)]
pub struct ModelDto {
    pub id: Uuid,
    /// Falls back to the API name.
    pub display_name: String,
    pub provider_id: Uuid,
    pub provider_name: String,
    /// Used by users who did not choose a model.
    pub is_default: bool,
}

/// A model the provider's server offers, see `GET /api/v1/llm-providers/{id}/remote-models`.
#[derive(Serialize, Deserialize)]
pub struct RemoteModelDto {
    pub api_name: String,
    /// `null` if the server only has the id, or a name that is the same.
    pub display_name: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct CreateLlmProviderRequest {
    pub name: String,
    pub api_format: LlmApiFormat,
    /// Absent or blank uses the official API of `api_format`.
    pub base_url: Option<String>,
    /// Absent or blank for servers without authentication.
    pub api_key: Option<String>,
    /// ISO 4217 code of the model prices, e.g. `USD`. Absent, `null` or blank if its models have
    /// no prices.
    pub currency: Option<String>,
}

/// Replaces all fields. The key itself is never returned, so it is changed via `api_key`.
#[derive(Serialize, Deserialize)]
pub struct UpdateLlmProviderRequest {
    pub name: String,
    pub api_format: LlmApiFormat,
    /// Absent or blank uses the official API of `api_format`.
    pub base_url: Option<String>,
    pub api_key: ApiKeyChange,
    /// ISO 4217 code of the model prices, e.g. `USD`. Absent, `null` or blank if its models have
    /// no prices, which is only possible if none of them has prices.
    pub currency: Option<String>,
}

/// `KEEP` is not accepted when `base_url` moves to another host, so the key is never sent
/// to a server it was not entered for.
#[derive(Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ApiKeyChange {
    Keep,
    /// The server needs no authentication.
    Remove,
    Set {
        value: String,
    },
}

/// Creates and replaces a model.
#[derive(Serialize, Deserialize)]
pub struct LlmModelRequest {
    /// The model id sent to the API, e.g. `claude-opus-5-5`.
    pub api_name: String,
    /// Shown to users, e.g. `Claude Opus 5.5`. Absent, `null`, blank or the same as `api_name`
    /// shows `api_name` (and is stored as `null`). The name shown is unique among all models,
    /// ignoring case.
    pub display_name: Option<String>,
    /// Absent or `null` uses the default of the API format.
    pub max_output_tokens: Option<i32>,
    /// Per million tokens in the provider's currency, as decimal strings. Absent or `null` if
    /// unknown, then answers show no cost. Input and output are set together, and only if the
    /// provider has a currency.
    pub input_price: Option<String>,
    pub output_price: Option<String>,
    /// Absent or `null` charges `input_price`. Only with `input_price`.
    pub cache_read_price: Option<String>,
    /// Absent or `null` charges `input_price`. Only with `input_price`.
    pub cache_write_price: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct SetDefaultModelRequest {
    pub model_id: Uuid,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serializes_without_underscore() {
        assert_eq!(
            serde_json::to_string(&LlmApiFormat::OpenAi).unwrap(),
            r#""OPENAI""#
        );
        assert_eq!(
            serde_json::from_str::<LlmApiFormat>(r#""ANTHROPIC""#).unwrap(),
            LlmApiFormat::Anthropic
        );
    }
}
