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

/// A common LLM provider, offered when creating one, see [`llm_provider_suggestions`].
#[derive(Serialize, Deserialize)]
pub struct LlmProviderSuggestionDto {
    pub name: String,
    pub api_format: LlmApiFormat,
    pub base_url: String,
    /// ISO 4217 code the provider prices its models in, `null` for local servers.
    pub currency: Option<String>,
    /// ISO 3166-1 alpha-2 code of the provider's country, shown as its flag. `null` for local
    /// servers.
    pub country_code: Option<String>,
    /// Whether the provider serves the models itself, `false` for routers that forward requests
    /// to other providers.
    pub runs_inference: bool,
    /// Brand of the models the provider develops (e.g. Claude), shown as its subtitle. `null` for
    /// hosts and routers of other companies' models.
    pub model_brand: Option<String>,
}

/// The common LLM providers, offered when creating one. Served by
/// `GET /api/v1/llm-providers/suggestions`, and called directly by clients that embed the crate.
pub fn llm_provider_suggestions() -> Vec<LlmProviderSuggestionDto> {
    SUGGESTIONS
        .iter()
        .map(|s| LlmProviderSuggestionDto {
            name: s.name.to_owned(),
            api_format: s.api_format,
            base_url: s.base_url.to_owned(),
            currency: s.currency.map(str::to_owned),
            country_code: s.country_code.map(str::to_owned),
            runs_inference: s.runs_inference,
            model_brand: s.model_brand.map(str::to_owned),
        })
        .collect()
}

/// [`LlmProviderSuggestionDto`] as a constant.
struct Suggestion {
    name: &'static str,
    api_format: LlmApiFormat,
    base_url: &'static str,
    currency: Option<&'static str>,
    country_code: Option<&'static str>,
    runs_inference: bool,
    model_brand: Option<&'static str>,
}

const SUGGESTIONS: &[Suggestion] = &[
    // Model developers
    Suggestion {
        name: "Anthropic",
        api_format: LlmApiFormat::Anthropic,
        base_url: "https://api.anthropic.com",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: Some("Claude"),
    },
    Suggestion {
        name: "OpenAI",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.openai.com/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: Some("GPT"),
    },
    Suggestion {
        name: "DeepSeek",
        api_format: LlmApiFormat::Anthropic,
        base_url: "https://api.deepseek.com/anthropic",
        currency: Some("USD"),
        country_code: Some("CN"),
        runs_inference: true,
        model_brand: Some("DeepSeek"),
    },
    Suggestion {
        name: "Google Gemini",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://generativelanguage.googleapis.com/v1beta/openai",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: Some("Gemini"),
    },
    Suggestion {
        name: "Mistral",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.mistral.ai/v1",
        currency: Some("USD"),
        country_code: Some("FR"),
        runs_inference: true,
        model_brand: Some("Mistral"),
    },
    Suggestion {
        name: "xAI",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.x.ai/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: Some("Grok"),
    },
    Suggestion {
        name: "Perplexity",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.perplexity.ai",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: Some("Sonar"),
    },
    Suggestion {
        name: "Moonshot AI",
        api_format: LlmApiFormat::Anthropic,
        base_url: "https://api.moonshot.ai/anthropic",
        currency: Some("USD"),
        country_code: Some("CN"),
        runs_inference: true,
        model_brand: Some("Kimi"),
    },
    Suggestion {
        name: "Alibaba Cloud",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        currency: Some("USD"),
        country_code: Some("CN"),
        runs_inference: true,
        model_brand: Some("Qwen"),
    },
    Suggestion {
        name: "Z.ai",
        api_format: LlmApiFormat::Anthropic,
        base_url: "https://api.z.ai/api/anthropic",
        currency: Some("USD"),
        country_code: Some("CN"),
        runs_inference: true,
        model_brand: Some("GLM"),
    },
    Suggestion {
        name: "MiniMax",
        api_format: LlmApiFormat::Anthropic,
        base_url: "https://api.minimax.io/anthropic",
        currency: Some("USD"),
        country_code: Some("CN"),
        runs_inference: true,
        model_brand: Some("MiniMax"),
    },
    Suggestion {
        name: "Cohere",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.cohere.ai/compatibility/v1",
        currency: Some("USD"),
        country_code: Some("CA"),
        runs_inference: true,
        model_brand: Some("Command"),
    },
    // Routers
    Suggestion {
        name: "OpenRouter",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://openrouter.ai/api/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: false,
        model_brand: None,
    },
    Suggestion {
        name: "Hugging Face",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://router.huggingface.co/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: false,
        model_brand: None,
    },
    Suggestion {
        name: "Vercel AI Gateway",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://ai-gateway.vercel.sh/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: false,
        model_brand: None,
    },
    // Hosts of open models
    Suggestion {
        name: "Groq",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.groq.com/openai/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "Aki",
        api_format: LlmApiFormat::Anthropic,
        base_url: "https://aki.io/anthropic",
        currency: Some("EUR"),
        country_code: Some("DE"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "IONOS AI Model Hub",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://openai.inference.de-txl.ionos.com/v1",
        currency: Some("EUR"),
        country_code: Some("DE"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "Scaleway",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.scaleway.ai/v1",
        currency: Some("EUR"),
        country_code: Some("FR"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "OVHcloud AI Endpoints",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1",
        currency: Some("EUR"),
        country_code: Some("FR"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "Together AI",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.together.xyz/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "Fireworks AI",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.fireworks.ai/inference/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "Cerebras",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.cerebras.ai/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "SambaNova",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.sambanova.ai/v1",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "DeepInfra",
        api_format: LlmApiFormat::OpenAi,
        base_url: "https://api.deepinfra.com/v1/openai",
        currency: Some("USD"),
        country_code: Some("US"),
        runs_inference: true,
        model_brand: None,
    },
    // Local servers
    Suggestion {
        name: "Ollama",
        api_format: LlmApiFormat::OpenAi,
        base_url: "http://localhost:11434/v1",
        currency: None,
        country_code: None,
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "LM Studio",
        api_format: LlmApiFormat::OpenAi,
        base_url: "http://localhost:1234/v1",
        currency: None,
        country_code: None,
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "llama.cpp",
        api_format: LlmApiFormat::OpenAi,
        base_url: "http://localhost:8080/v1",
        currency: None,
        country_code: None,
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "vLLM",
        api_format: LlmApiFormat::OpenAi,
        base_url: "http://localhost:8000/v1",
        currency: None,
        country_code: None,
        runs_inference: true,
        model_brand: None,
    },
    Suggestion {
        name: "Jan",
        api_format: LlmApiFormat::OpenAi,
        base_url: "http://localhost:1337/v1",
        currency: None,
        country_code: None,
        runs_inference: true,
        model_brand: None,
    },
];

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
