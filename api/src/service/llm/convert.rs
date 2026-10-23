//! Translates between the types of [`super`], which the tool loop uses, and rig's. Rig keeps
//! each block of a response together with the provider's own form of it (a thinking block's
//! signature, DeepSeek's `reasoning_content`, Gemini's thought signature on a tool call, ...)
//! and sends that back verbatim to the model that produced it. [`ProviderBlock`] carries rig's
//! block through the tool loop for that, so nothing provider-specific is modeled here.

use super::{
    ChatMessage, ContentBlock, LlmConfig, LlmError, LlmRequest, LlmResponse, Role, StopReason,
    ToolUse, Usage,
};
use crate::dto::llm::LlmApiFormat;
use rig_core::completion::{self, CompletionRequest, CompletionResponse, FinishReason};
use rig_core::message::{
    AssistantContent, AssistantMessage, CallId, Message, Origin, Text, ToolCall, ToolFunction,
    ToolName, ToolResult, ToolResultContent, UserContent,
};
use serde_json::Value;
use std::collections::HashMap;

/// The Messages API requires `max_tokens`, unlike OpenAI-compatible servers.
const DEFAULT_MAX_OUTPUT_TOKENS: u64 = 32_000;

/// A block of a response as rig decoded it, with the turn it came from: reasoning, other
/// provider items, and the provider's form of a tool call. Rig sends it back unchanged as
/// long as the model stays the same (and, for models that bind thinking to it, the system
/// prompt and tools).
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct ProviderBlock {
    content: AssistantContent,
    origin: Origin,
}

pub(super) fn request(
    config: &LlmConfig,
    request: &LlmRequest<'_>,
) -> Result<CompletionRequest, LlmError> {
    let mut messages = messages(config.api_format, request.messages)?;
    let prompt = messages
        .pop()
        .ok_or_else(|| LlmError::Request("The request has no messages".to_string()))?;
    let tools = request
        .tools
        .iter()
        .map(|tool| {
            Ok(completion::ToolDefinition::new(
                tool_name(&tool.name)?,
                &tool.description,
                tool.input_schema.clone(),
            ))
        })
        .collect::<Result<Vec<_>, LlmError>>()?;
    let max_tokens = config.max_output_tokens.map(u64::from);
    let max_tokens = match config.api_format {
        LlmApiFormat::Anthropic => Some(max_tokens.unwrap_or(DEFAULT_MAX_OUTPUT_TOKENS)),
        LlmApiFormat::OpenAi => max_tokens,
    };
    let mut completion = CompletionRequest::new(prompt)
        .messages(messages)
        .tools(tools)
        .max_tokens(max_tokens);
    if !request.system.is_empty() {
        completion = completion.preamble(request.system);
    }
    Ok(completion)
}

/// Messages without content are left out, the APIs reject them.
fn messages(api_format: LlmApiFormat, messages: &[ChatMessage]) -> Result<Vec<Message>, LlmError> {
    // The calls by their id, which the results refer to
    let mut calls: HashMap<&str, (CallId, ToolName)> = HashMap::new();
    let mut converted = Vec::new();
    for message in messages {
        let message = match message.role {
            Role::Assistant => assistant_message(message, &mut calls)?,
            Role::User => user_message(api_format, message, &calls),
        };
        converted.extend(message);
    }
    Ok(converted)
}

fn assistant_message<'a>(
    message: &'a ChatMessage,
    calls: &mut HashMap<&'a str, (CallId, ToolName)>,
) -> Result<Option<Message>, LlmError> {
    let mut origin = None;
    let mut content = Vec::new();
    for block in &message.content {
        let block = match block {
            ContentBlock::Text(text) if text.is_empty() => continue,
            ContentBlock::Text(text) => AssistantContent::Text(Text::new(text)),
            ContentBlock::ToolUse(tool_use) => {
                let call = match &tool_use.native {
                    Some(native) if tool_use.is_from(native) => {
                        origin.get_or_insert_with(|| native.origin.clone());
                        native.content.clone()
                    }
                    _ => AssistantContent::ToolCall(ToolCall::from_wire(
                        &tool_use.id,
                        ToolFunction::new(tool_name(&tool_use.name)?, tool_use.input.clone()),
                    )),
                };
                if let AssistantContent::ToolCall(call) = &call {
                    calls.insert(&tool_use.id, (call.id.clone(), call.function.name.clone()));
                }
                call
            }
            ContentBlock::Provider(native) => {
                origin.get_or_insert_with(|| native.origin.clone());
                native.content.clone()
            }
            ContentBlock::ToolResult { .. } => continue,
        };
        content.push(block);
    }
    if content.is_empty() {
        return Ok(None);
    }
    Ok(Some(Message::Assistant(
        AssistantMessage::new(content).with_origin(origin),
    )))
}

fn user_message(
    api_format: LlmApiFormat,
    message: &ChatMessage,
    calls: &HashMap<&str, (CallId, ToolName)>,
) -> Option<Message> {
    let content: Vec<UserContent> = message
        .content
        .iter()
        .filter_map(|block| match block {
            ContentBlock::Text(text) if text.is_empty() => None,
            ContentBlock::Text(text) => Some(UserContent::Text(Text::new(text))),
            ContentBlock::ToolResult {
                tool_use_id,
                content,
                is_error,
            } => {
                let (call, name) = calls.get(tool_use_id.as_str()).cloned().unwrap_or_else(|| {
                    // Every result answers a call of the previous message
                    let name = ToolName::new("unknown").expect("the name is not empty");
                    (CallId::from_wire(tool_use_id), name)
                });
                let content = match api_format {
                    // The format has no error flag
                    LlmApiFormat::OpenAi if *is_error => format!("Error: {content}"),
                    _ => content.clone(),
                };
                Some(UserContent::ToolResult(ToolResult {
                    call,
                    name,
                    content: vec![ToolResultContent::Text(Text::new(content))],
                    is_error: *is_error,
                }))
            }
            ContentBlock::ToolUse(_) | ContentBlock::Provider(_) => None,
        })
        .collect();
    (!content.is_empty()).then_some(Message::User { content })
}

fn tool_name(name: &str) -> Result<ToolName, LlmError> {
    ToolName::new(name).map_err(|_| LlmError::Request("A tool has no name".to_string()))
}

pub(super) fn response(response: CompletionResponse) -> LlmResponse {
    let stop_reason = stop_reason(&response);
    let usage = usage(&response.usage);
    let origin = response.origin;
    let content = response
        .choice
        .into_iter()
        .map(|block| match block {
            AssistantContent::Text(text) => ContentBlock::Text(text.text),
            AssistantContent::ToolCall(call) => ContentBlock::ToolUse(ToolUse {
                id: call.id.wire().into_owned(),
                name: call.function.name.to_string(),
                input: tool_input(&call.function),
                native: Some(ProviderBlock {
                    content: AssistantContent::ToolCall(call),
                    origin: origin.clone(),
                }),
            }),
            content => ContentBlock::Provider(ProviderBlock {
                content,
                origin: origin.clone(),
            }),
        })
        .collect();
    LlmResponse {
        content,
        stop_reason,
        usage,
    }
}

/// Arguments that are not a JSON object come as the text the model sent, see [`ToolUse::input`].
fn tool_input(function: &ToolFunction) -> Value {
    match &function.invalid_arguments {
        Some(raw) => Value::String(raw.clone()),
        None => Value::Object(function.arguments.clone()),
    }
}

impl ToolUse {
    /// Whether this is still the call `native` was decoded to.
    fn is_from(&self, native: &ProviderBlock) -> bool {
        match &native.content {
            AssistantContent::ToolCall(call) => {
                call.id.wire() == self.id
                    && call.function.name == self.name
                    && tool_input(&call.function) == self.input
            }
            _ => false,
        }
    }
}

fn stop_reason(response: &CompletionResponse) -> StopReason {
    // E.g. a refusal with its explanation
    if response.error.is_some() {
        return StopReason::Refusal;
    }
    match response.finish_reason() {
        Some(FinishReason::Stop) => StopReason::EndTurn,
        Some(FinishReason::ToolCalls) => StopReason::ToolUse,
        Some(FinishReason::Length) => StopReason::MaxTokens,
        Some(FinishReason::ContentFilter) => StopReason::Refusal,
        Some(FinishReason::Other(reason)) => StopReason::Other(reason),
        Some(reason) => StopReason::Other(format!("{reason:?}")),
        // Some servers end without a reason, also after tool calls
        None if response.tool_calls().next().is_some() => StopReason::ToolUse,
        None => StopReason::EndTurn,
    }
}

/// Rig counts the tokens read from and written to the cache in the input tokens.
fn usage(usage: &completion::Usage) -> Usage {
    let cache_read_input_tokens = usage.cached_input_tokens.unwrap_or(0);
    let cache_creation_input_tokens = usage.cache_creation_input_tokens.unwrap_or(0);
    Usage {
        input_tokens: usage
            .input_tokens
            .unwrap_or(0)
            .saturating_sub(cache_read_input_tokens + cache_creation_input_tokens),
        output_tokens: usage.output_tokens.unwrap_or(0),
        cache_read_input_tokens,
        cache_creation_input_tokens,
    }
}
