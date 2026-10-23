//! Streaming client for the LLM API in the formats of [`LlmApiFormat`], built on rig-core,
//! which encodes the requests and decodes the responses of each format; [`convert`]
//! translates between rig's types and the ones here. It sends one request and returns one
//! response; the tool loop lives in [`crate::service::answer`]. It also lists the models a
//! server offers, for admins adding them.

mod convert;

pub(crate) use convert::ProviderBlock;

use crate::dto::llm::LlmApiFormat;
use crate::util::http::client_builder;
use chrono::{DateTime, Utc};
use futures_util::{Stream, StreamExt, stream};
use reqwest::StatusCode;
use rig_core::error::{ErrorKind, ProviderError};
use rig_core::operation::Completion;
use rig_core::providers::anthropic::AnthropicConfig;
use rig_core::providers::openai::OpenAIConfig;
use rig_core::providers::openai::wire::Auth;
use rig_core::streaming::{CompletionStream, Item, StreamEvent};
use rig_core::{DynModel, completion::CompletionRequest};
use rig_reqwest::ReqwestClient;
use serde_json::Value;
use std::fmt;
use std::time::{Duration, SystemTime};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// Longest silence between two chunks. Reasoning models can think for minutes before
/// the first token, Anthropic sends pings meanwhile, OpenAI-compatible servers do not.
const READ_TIMEOUT: Duration = Duration::from_secs(300);
/// Attempts to get a response, also when it fails before its first event, e.g. with
/// Anthropic's `overloaded_error` right after the status 200. Errors after the first event
/// are returned instead, since its text may already be shown.
const MAX_ATTEMPTS: u32 = 3;
const MAX_RETRY_DELAY: Duration = Duration::from_secs(30);
/// Error bodies that are not JSON are cut to this many characters.
const MAX_ERROR_BODY_CHARS: usize = 500;
/// For all pages of [`LlmClient::list_models`], which an admin waits for.
const MODELS_TIMEOUT: Duration = Duration::from_secs(60);

/// How to reach a model, resolved for each answer, see [`crate::service::llm_config`].
pub(crate) struct LlmConfig {
    pub(crate) api_format: LlmApiFormat,
    /// `None` for servers without authentication, e.g. a local Ollama.
    pub(crate) api_key: Option<String>,
    pub(crate) model: String,
    /// Without trailing slash, e.g. `https://api.openai.com/v1`.
    pub(crate) base_url: String,
    /// `None` leaves the limit to the server, or the default of [`convert`] for the
    /// Anthropic format.
    pub(crate) max_output_tokens: Option<u32>,
}

impl fmt::Debug for LlmConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LlmConfig")
            .field("api_format", &self.api_format)
            .field("api_key", &self.api_key.as_ref().map(|_| "<redacted>"))
            .field("model", &self.model)
            .field("base_url", &self.base_url)
            .field("max_output_tokens", &self.max_output_tokens)
            .finish()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Role {
    User,
    Assistant,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ChatMessage {
    pub role: Role,
    pub content: Vec<ContentBlock>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum ContentBlock {
    Text(String),
    ToolUse(ToolUse),
    /// In a [`Role::User`] message, answers the [`ToolUse`] with the same id.
    ToolResult {
        tool_use_id: String,
        content: String,
        is_error: bool,
    },
    /// Reasoning and other provider items of a response, e.g. Anthropic's thinking blocks.
    /// Has to be sent back unchanged for the rest of the tool loop, and the history before it
    /// must not change meanwhile.
    Provider(ProviderBlock),
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ToolUse {
    pub id: String,
    pub name: String,
    /// The arguments, usually an object. A [`Value::String`] holds arguments that are not
    /// a JSON object: answer with an error result instead of running the tool.
    pub input: Value,
    /// The call as the server sent it, e.g. with Gemini's thought signature, which has to be
    /// sent back with it unchanged. `None` for calls not made by a model.
    pub native: Option<ProviderBlock>,
}

#[derive(Debug, Clone)]
pub(crate) struct ToolDefinition {
    pub name: String,
    pub description: String,
    /// JSON schema of the arguments.
    pub input_schema: Value,
}

/// Keep `system` and `tools` the same during a tool loop, and only append to `messages`:
/// both prompt caching and Anthropic thinking blocks depend on an unchanged prefix.
pub(crate) struct LlmRequest<'a> {
    pub system: &'a str,
    pub messages: &'a [ChatMessage],
    pub tools: &'a [ToolDefinition],
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum LlmEvent {
    TextDelta(String),
    /// The last event.
    Done(LlmResponse),
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct LlmResponse {
    /// Append as an assistant message to continue the conversation.
    pub content: Vec<ContentBlock>,
    pub stop_reason: StopReason,
    pub usage: Usage,
}

impl LlmResponse {
    pub(crate) fn tool_uses(&self) -> impl Iterator<Item = &ToolUse> {
        self.content.iter().filter_map(|block| match block {
            ContentBlock::ToolUse(tool_use) => Some(tool_use),
            _ => None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum StopReason {
    EndTurn,
    /// Run the tools of [`LlmResponse::tool_uses`] and send their results.
    ToolUse,
    /// The output was cut off, tool calls in it may be incomplete. Do not run them.
    MaxTokens,
    /// The model or a content filter declined. Do not run tool calls in it.
    Refusal,
    Other(String),
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct Usage {
    /// Input tokens that were neither read from nor written to the cache.
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_input_tokens: u64,
    /// Reported by Anthropic and a few OpenAI-compatible servers, e.g. OpenRouter.
    pub cache_creation_input_tokens: u64,
}

impl std::ops::AddAssign<&Usage> for Usage {
    fn add_assign(&mut self, other: &Usage) {
        self.input_tokens += other.input_tokens;
        self.output_tokens += other.output_tokens;
        self.cache_read_input_tokens += other.cache_read_input_tokens;
        self.cache_creation_input_tokens += other.cache_creation_input_tokens;
    }
}

/// A model a server offers, see [`LlmClient::list_models`].
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct RemoteModel {
    /// The id sent to the API.
    pub api_name: String,
    /// `None` if the server only has the id, or a name that is the same.
    pub display_name: Option<String>,
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum LlmError {
    /// The server could not be reached, or the connection broke.
    #[error("Request to the LLM API failed: {0}")]
    Http(String),

    /// The request was rejected, e.g. because of a wrong API key or an unknown model.
    #[error("LLM API returned {status}: {message}")]
    Status { status: StatusCode, message: String },

    /// An error event in the response, e.g. Anthropic's `overloaded_error`.
    #[error("LLM API error ({kind}): {message}")]
    Stream { kind: String, message: String },

    /// The request could not be built, e.g. from an invalid base URL.
    #[error("Invalid request to the LLM API: {0}")]
    Request(String),

    #[error("Invalid response from the LLM API: {0}")]
    InvalidResponse(String),
}

impl LlmError {
    /// Whether the same request may succeed later. Requests are only retried before
    /// the response started, afterwards the caller decides.
    pub(crate) fn is_retryable(&self) -> bool {
        match self {
            Self::Http(_) => true,
            Self::Status { status, .. } => {
                matches!(status.as_u16(), 408 | 409 | 429) || status.is_server_error()
            }
            Self::Stream { kind, .. } => matches!(
                kind.as_str(),
                "overloaded_error" | "api_error" | "rate_limit_error" | "timeout_error"
            ),
            Self::Request(_) | Self::InvalidResponse(_) => false,
        }
    }
}

impl From<ProviderError> for LlmError {
    fn from(error: ProviderError) -> Self {
        if let Some(response) = error.provider_response() {
            let message = match serde_json::from_str::<Value>(&response.body) {
                Ok(value) => error_message(&value),
                Err(_) => None,
            };
            let message = message.unwrap_or_else(|| {
                let body = response.body.trim();
                body.chars().take(MAX_ERROR_BODY_CHARS).collect()
            });
            let status = response
                .status
                .filter(|status| !status.is_success())
                .and_then(|status| StatusCode::from_u16(status.as_u16()).ok());
            return match status {
                Some(status) => Self::Status { status, message },
                // An error event, after the status 200
                None => Self::Stream {
                    kind: response
                        .machine_code()
                        .unwrap_or_else(|| "unknown_error".to_string()),
                    message,
                },
            };
        }
        match error.kind() {
            ErrorKind::Http | ErrorKind::Timeout => Self::Http(error.to_string()),
            ErrorKind::Request | ErrorKind::Url => Self::Request(error.to_string()),
            _ => Self::InvalidResponse(error.to_string()),
        }
    }
}

/// `{"error": {"message": "..."}}`, or `{"error": "..."}` on some OpenAI-compatible servers.
fn error_message(value: &Value) -> Option<String> {
    let error = value.get("error")?;
    error
        .get("message")
        .unwrap_or(error)
        .as_str()
        .map(str::to_string)
}

/// Streams model responses. Holds a connection pool, so share one instance.
pub(crate) struct LlmClient {
    http: ReqwestClient,
}

impl LlmClient {
    pub(crate) fn new() -> Result<Self, reqwest::Error> {
        let http = client_builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .read_timeout(READ_TIMEOUT)
            .build()?;
        Ok(Self {
            http: ReqwestClient::from(http),
        })
    }

    /// Streams one response of the model in `config`, ending with [`LlmEvent::Done`] or an
    /// error. Dropping the stream aborts the request.
    pub(crate) fn stream(
        &self,
        config: &LlmConfig,
        request: &LlmRequest<'_>,
    ) -> impl Stream<Item = Result<LlmEvent, LlmError>> + Send + 'static {
        let attempts = convert::request(config, request).map(|request| Attempts {
            model: self.model(config),
            request,
            attempt: 1,
            events: None,
            started: false,
        });
        stream::unfold(Some(attempts), |attempts| async move {
            let mut attempts = match attempts? {
                Ok(attempts) => attempts,
                Err(e) => return Some((Err(e), None)),
            };
            let item = attempts.next().await?;
            // Nothing follows the response or an error
            let attempts = matches!(item, Ok(LlmEvent::TextDelta(_))).then_some(Ok(attempts));
            Some((item, attempts))
        })
    }

    fn model(&self, config: &LlmConfig) -> DynModel<Completion> {
        let api_key = config.api_key.clone().unwrap_or_default();
        match config.api_format {
            LlmApiFormat::Anthropic => {
                let mut model = AnthropicConfig::new(api_key)
                    .with_base_url(&config.base_url)
                    .connect(self.http.clone())
                    .completion(&config.model);
                // Caches the system prompt and tools, and the conversation for the next
                // request of the tool loop and the next question.
                model.wire = model.wire.with_prompt_caching();
                model.erase()
            }
            LlmApiFormat::OpenAi => OpenAIConfig::new(api_key)
                .with_base_url(&config.base_url)
                .with_auth(Auth::OptionalBearer)
                .connect(self.http.clone())
                .chat(&config.model)
                .erase(),
        }
    }

    /// The models the server offers, sorted by id.
    /// Not every OpenAI-compatible server lists them, those usually respond with 404. Errors
    /// are not retried, since an admin waits for the list.
    pub(crate) async fn list_models(
        &self,
        api_format: LlmApiFormat,
        base_url: &str,
        api_key: Option<&str>,
    ) -> Result<Vec<RemoteModel>, LlmError> {
        let api_key = api_key.unwrap_or_default();
        let models = async {
            match api_format {
                LlmApiFormat::Anthropic => {
                    AnthropicConfig::new(api_key)
                        .with_base_url(base_url)
                        .connect(self.http.clone())
                        .list_models()
                        .await
                }
                LlmApiFormat::OpenAi => {
                    OpenAIConfig::new(api_key)
                        .with_base_url(base_url)
                        .with_auth(Auth::OptionalBearer)
                        .connect(self.http.clone())
                        .list_models()
                        .await
                }
            }
        };
        let models = tokio::time::timeout(MODELS_TIMEOUT, models)
            .await
            .map_err(|_| LlmError::Http("The model list timed out".to_string()))??;
        let models = models
            .data
            .into_iter()
            .map(|model| RemoteModel {
                created_at: model
                    .created_at
                    .and_then(|created| DateTime::from_timestamp(created.try_into().ok()?, 0)),
                api_name: model.id,
                display_name: model.name,
            })
            .collect();
        Ok(sort_models(models))
    }
}

/// By id, without duplicates. A display name that only repeats the id is dropped.
fn sort_models(mut models: Vec<RemoteModel>) -> Vec<RemoteModel> {
    models.sort_by(|a, b| a.api_name.cmp(&b.api_name));
    models.dedup_by(|a, b| a.api_name == b.api_name);
    for model in &mut models {
        if model.display_name.as_deref().map(str::trim) == Some(model.api_name.as_str()) {
            model.display_name = None;
        }
    }
    models
}

/// The attempts of [`LlmClient::stream`], see [`MAX_ATTEMPTS`].
struct Attempts {
    model: DynModel<Completion>,
    request: CompletionRequest,
    /// The current one, from 1.
    attempt: u32,
    /// Of the current response, `None` until it is requested.
    events: Option<CompletionStream>,
    /// Whether an event of the current response was passed on, after which errors are not
    /// retried.
    started: bool,
}

impl Attempts {
    /// The next event, or the error that ends the stream. `None` after the last event.
    async fn next(&mut self) -> Option<Result<LlmEvent, LlmError>> {
        loop {
            let events = match &mut self.events {
                Some(events) => events,
                None => match self.model.stream(self.request.clone()) {
                    Ok(events) => self.events.insert(events),
                    Err(e) => return Some(Err(e.into())),
                },
            };
            let error = match events.next().await {
                Some(Ok(Item::Event(StreamEvent::Text { text, .. }))) if !text.is_empty() => {
                    self.started = true;
                    return Some(Ok(LlmEvent::TextDelta(text)));
                }
                // Reasoning, tool calls and the like arrive whole with the response
                Some(Ok(_)) => continue,
                Some(Err(e)) => e,
                None => {
                    let events = self.events.take()?;
                    match events.finish().await {
                        Ok(response) => {
                            return Some(Ok(LlmEvent::Done(convert::response(response))));
                        }
                        Err(e) => e,
                    }
                }
            };
            let retry_after = error.report().retry_after(SystemTime::now());
            let error = LlmError::from(error);
            if self.started || self.attempt >= MAX_ATTEMPTS || !error.is_retryable() {
                self.events = None;
                return Some(Err(error));
            }
            let delay = retry_delay(self.attempt, retry_after);
            tracing::warn!(
                "LLM request failed (attempt {} of {MAX_ATTEMPTS}), retrying in {delay:?}: {error}",
                self.attempt
            );
            self.events = None;
            tokio::time::sleep(delay).await;
            self.attempt += 1;
        }
    }
}

/// Exponential backoff with jitter after `attempt`, or the server's `Retry-After`.
fn retry_delay(attempt: u32, retry_after: Option<Duration>) -> Duration {
    let backoff =
        Duration::from_secs(1 << (attempt - 1)) + Duration::from_millis(rand::random_range(0..500));
    retry_after.unwrap_or(backoff).min(MAX_RETRY_DELAY)
}

#[cfg(test)]
mod tests;
