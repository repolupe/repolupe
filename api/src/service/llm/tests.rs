use super::*;
use axum::Router;
use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, Uri};
use axum::response::{IntoResponse, Response};
use serde_json::json;
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

/// A server on localhost that answers the n-th request with the n-th reply, whatever the path,
/// and records the requests.
struct FakeServer {
    base_url: String,
    state: Arc<FakeState>,
    task: tokio::task::JoinHandle<()>,
}

#[derive(Default)]
struct FakeState {
    replies: Mutex<VecDeque<Reply>>,
    requests: Mutex<Vec<Request>>,
}

struct Reply {
    status: u16,
    headers: Vec<(&'static str, &'static str)>,
    body: String,
}

#[derive(Debug, Clone)]
struct Request {
    path: String,
    headers: HeaderMap,
    body: Value,
}

impl FakeServer {
    async fn start(replies: Vec<Reply>) -> Self {
        let state = Arc::new(FakeState {
            replies: Mutex::new(replies.into()),
            ..Default::default()
        });
        let router = Router::new().fallback(handle).with_state(state.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        let task = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        Self {
            base_url,
            state,
            task,
        }
    }

    fn requests(&self) -> Vec<Request> {
        self.state.requests.lock().unwrap().clone()
    }

    fn config(&self, api_format: LlmApiFormat, api_key: Option<&str>) -> LlmConfig {
        let base_url = match api_format {
            LlmApiFormat::Anthropic => self.base_url.clone(),
            LlmApiFormat::OpenAi => format!("{}/v1", self.base_url),
        };
        LlmConfig {
            api_format,
            api_key: api_key.map(str::to_string),
            model: "test-model".to_string(),
            base_url,
            max_output_tokens: None,
        }
    }
}

impl Drop for FakeServer {
    fn drop(&mut self) {
        self.task.abort();
    }
}

async fn handle(
    State(state): State<Arc<FakeState>>,
    uri: Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    state.requests.lock().unwrap().push(Request {
        path: uri.path().to_string(),
        headers,
        body: serde_json::from_slice(&body).unwrap_or(Value::Null),
    });
    let reply = state
        .replies
        .lock()
        .unwrap()
        .pop_front()
        .expect("a scripted reply");
    let mut response = (
        axum::http::StatusCode::from_u16(reply.status).unwrap(),
        reply.body,
    )
        .into_response();
    for (name, value) in reply.headers {
        response.headers_mut().insert(name, value.parse().unwrap());
    }
    response
}

/// Server-sent events in the Anthropic format, named by their type.
fn anthropic_sse(events: &[Value]) -> Reply {
    let body = events
        .iter()
        .map(|event| {
            format!(
                "event: {}\ndata: {event}\n\n",
                event["type"].as_str().unwrap()
            )
        })
        .collect();
    Reply {
        status: 200,
        headers: vec![("content-type", "text/event-stream")],
        body,
    }
}

/// Server-sent events in the OpenAI format, unnamed.
fn openai_sse(chunks: &[Value]) -> Reply {
    let mut body: String = chunks
        .iter()
        .map(|chunk| format!("data: {chunk}\n\n"))
        .collect();
    body.push_str("data: [DONE]\n\n");
    Reply {
        status: 200,
        headers: vec![("content-type", "text/event-stream")],
        body,
    }
}

fn json_reply(status: u16, headers: Vec<(&'static str, &'static str)>, body: Value) -> Reply {
    let mut headers = headers;
    headers.push(("content-type", "application/json"));
    Reply {
        status,
        headers,
        body: body.to_string(),
    }
}

fn anthropic_text(text: &str) -> Reply {
    anthropic_sse(&[
        json!({"type": "message_start", "message": {"id": "msg_2", "type": "message", "role": "assistant", "content": [], "model": "test-model", "usage": {"input_tokens": 3, "output_tokens": 1}}}),
        json!({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
        json!({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text}}),
        json!({"type": "content_block_stop", "index": 0}),
        json!({"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 2}}),
        json!({"type": "message_stop"}),
    ])
}

/// The text deltas and the response, which must come last.
async fn collect(
    client: &LlmClient,
    config: &LlmConfig,
    request: &LlmRequest<'_>,
) -> Result<(Vec<String>, LlmResponse), (Vec<String>, LlmError)> {
    let stream = client.stream(config, request);
    tokio::pin!(stream);
    let mut texts = Vec::new();
    let mut response = None;
    while let Some(event) = stream.next().await {
        assert!(response.is_none(), "nothing follows Done");
        match event {
            Ok(LlmEvent::TextDelta(text)) => texts.push(text),
            Ok(LlmEvent::Done(done)) => response = Some(done),
            Err(e) => {
                assert!(stream.next().await.is_none(), "nothing follows an error");
                return Err((texts, e));
            }
        }
    }
    Ok((texts, response.expect("a response")))
}

fn user(text: &str) -> ChatMessage {
    ChatMessage {
        role: Role::User,
        content: vec![ContentBlock::Text(text.to_string())],
    }
}

fn grep_tool() -> ToolDefinition {
    ToolDefinition {
        name: "grep".to_string(),
        description: "Searches the files".to_string(),
        input_schema: json!({"type": "object", "properties": {"pattern": {"type": "string"}}}),
    }
}

/// The messages of the next request of the tool loop: `response` and a result for each call.
fn continue_loop(messages: &mut Vec<ChatMessage>, response: LlmResponse) {
    let results = response
        .tool_uses()
        .map(|tool_use| ContentBlock::ToolResult {
            tool_use_id: tool_use.id.clone(),
            content: "no matches".to_string(),
            is_error: tool_use.name != "grep",
        })
        .collect();
    messages.push(ChatMessage {
        role: Role::Assistant,
        content: response.content,
    });
    messages.push(ChatMessage {
        role: Role::User,
        content: results,
    });
}

#[tokio::test]
async fn sends_anthropic_thinking_back_in_the_tool_loop() {
    let server = FakeServer::start(vec![
        anthropic_sse(&[
            json!({"type": "message_start", "message": {"id": "msg_1", "type": "message", "role": "assistant", "content": [], "model": "test-model", "stop_reason": null, "usage": {"input_tokens": 25, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 1200, "output_tokens": 1}}}),
            json!({"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}}),
            json!({"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "Search for main."}}),
            json!({"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "EqQB"}}),
            json!({"type": "content_block_stop", "index": 0}),
            json!({"type": "content_block_start", "index": 1, "content_block": {"type": "redacted_thinking", "data": "secret"}}),
            json!({"type": "content_block_stop", "index": 1}),
            json!({"type": "content_block_start", "index": 2, "content_block": {"type": "text", "text": ""}}),
            json!({"type": "content_block_delta", "index": 2, "delta": {"type": "text_delta", "text": "Let me "}}),
            json!({"type": "ping"}),
            json!({"type": "content_block_delta", "index": 2, "delta": {"type": "text_delta", "text": "look."}}),
            json!({"type": "content_block_stop", "index": 2}),
            json!({"type": "content_block_start", "index": 3, "content_block": {"type": "tool_use", "id": "toolu_1", "name": "grep", "input": {}}}),
            json!({"type": "content_block_delta", "index": 3, "delta": {"type": "input_json_delta", "partial_json": "{\"pattern\":"}}),
            json!({"type": "content_block_delta", "index": 3, "delta": {"type": "input_json_delta", "partial_json": " \"fn main\"}"}}),
            json!({"type": "content_block_stop", "index": 3}),
            json!({"type": "content_block_start", "index": 4, "content_block": {"type": "tool_use", "id": "toolu_2", "name": "read_file", "input": {}}}),
            json!({"type": "content_block_delta", "index": 4, "delta": {"type": "input_json_delta", "partial_json": "{\"path\": \"src/"}}),
            json!({"type": "content_block_stop", "index": 4}),
            json!({"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 40}}),
            json!({"type": "message_stop"}),
        ]),
        anthropic_text("Found nothing."),
    ])
    .await;
    let client = LlmClient::new().unwrap();
    let config = server.config(LlmApiFormat::Anthropic, Some("sk-test"));
    let tools = [grep_tool()];
    let mut messages = vec![user("Where is main?")];
    let request = LlmRequest {
        system: "You answer questions.",
        messages: &messages,
        tools: &tools,
    };

    let (texts, response) = collect(&client, &config, &request).await.unwrap();
    assert_eq!(texts, ["Let me ", "look."]);
    assert_eq!(response.stop_reason, StopReason::ToolUse);
    assert_eq!(
        response.usage,
        Usage {
            input_tokens: 25,
            output_tokens: 40,
            cache_read_input_tokens: 1200,
            cache_creation_input_tokens: 100,
        }
    );
    assert!(matches!(response.content[0], ContentBlock::Provider(_)));
    assert!(matches!(response.content[1], ContentBlock::Provider(_)));
    assert_eq!(
        response.content[2],
        ContentBlock::Text("Let me look.".to_string())
    );
    let tool_uses: Vec<_> = response
        .tool_uses()
        .map(|tool_use| {
            (
                tool_use.id.as_str(),
                tool_use.name.as_str(),
                &tool_use.input,
            )
        })
        .collect();
    assert_eq!(
        tool_uses,
        [
            ("toolu_1", "grep", &json!({"pattern": "fn main"})),
            // Cut off, so not valid JSON
            ("toolu_2", "read_file", &json!("{\"path\": \"src/")),
        ]
    );

    continue_loop(&mut messages, response);
    let request = LlmRequest {
        system: "You answer questions.",
        messages: &messages,
        tools: &tools,
    };
    let (texts, response) = collect(&client, &config, &request).await.unwrap();
    assert_eq!(texts, ["Found nothing."]);
    assert_eq!(response.stop_reason, StopReason::EndTurn);

    let requests = server.requests();
    let first = &requests[0];
    assert_eq!(first.path, "/v1/messages");
    assert_eq!(first.headers["x-api-key"], "sk-test");
    assert_eq!(first.body["model"], "test-model");
    assert_eq!(first.body["max_tokens"], 32_000);
    assert_eq!(first.body["stream"], true);
    assert_eq!(first.body["system"][0]["text"], "You answer questions.");
    assert!(first.body["system"][0]["cache_control"].is_object());
    assert_eq!(first.body["tools"][0]["name"], "grep");
    assert_eq!(
        first.body["tools"][0]["input_schema"],
        tools[0].input_schema
    );

    let second = &requests[1].body;
    assert_eq!(second["messages"].as_array().unwrap().len(), 3);
    let assistant = &second["messages"][1];
    assert_eq!(assistant["role"], "assistant");
    assert_eq!(
        assistant["content"][0],
        json!({"type": "thinking", "thinking": "Search for main.", "signature": "EqQB"})
    );
    assert_eq!(
        assistant["content"][1],
        json!({"type": "redacted_thinking", "data": "secret"})
    );
    assert_eq!(assistant["content"][2]["text"], "Let me look.");
    assert_eq!(assistant["content"][3]["id"], "toolu_1");
    assert_eq!(
        assistant["content"][3]["input"],
        json!({"pattern": "fn main"})
    );
    assert_eq!(assistant["content"][4]["id"], "toolu_2");
    let results = &second["messages"][2]["content"];
    assert_eq!(results[0]["type"], "tool_result");
    assert_eq!(results[0]["tool_use_id"], "toolu_1");
    assert_eq!(results[1]["tool_use_id"], "toolu_2");
    assert_eq!(results[1]["is_error"], true);
    // Caches the conversation for the next request
    assert!(results[1]["cache_control"].is_object());
}

#[tokio::test]
async fn streams_openai_tool_calls_in_pieces() {
    let server = FakeServer::start(vec![openai_sse(&[
        json!({"id": "c1", "choices": [{"index": 0, "delta": {"role": "assistant", "content": "Let me "}, "finish_reason": null}]}),
        json!({"id": "c1", "choices": [{"index": 0, "delta": {"content": "search."}, "finish_reason": null}]}),
        json!({"id": "c1", "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": "call_a", "type": "function", "function": {"name": "grep", "arguments": ""}}]}, "finish_reason": null}]}),
        json!({"id": "c1", "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "function": {"arguments": "{\"pattern\":"}}]}, "finish_reason": null}]}),
        json!({"id": "c1", "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 1, "id": "call_b", "type": "function", "function": {"name": "list_files", "arguments": "{}"}}]}, "finish_reason": null}]}),
        json!({"id": "c1", "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "function": {"arguments": " \"fn main\"}"}}]}, "finish_reason": null}]}),
        json!({"id": "c1", "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]}),
        json!({"id": "c1", "choices": [], "usage": {"prompt_tokens": 1300, "completion_tokens": 40, "prompt_tokens_details": {"cached_tokens": 1024}}}),
    ])])
    .await;
    let client = LlmClient::new().unwrap();
    let mut config = server.config(LlmApiFormat::OpenAi, None);
    config.max_output_tokens = Some(1000);
    let messages = [user("Where is main?")];
    let request = LlmRequest {
        system: "You answer questions.",
        messages: &messages,
        tools: &[grep_tool()],
    };

    let (texts, response) = collect(&client, &config, &request).await.unwrap();
    assert_eq!(texts, ["Let me ", "search."]);
    assert_eq!(response.stop_reason, StopReason::ToolUse);
    assert_eq!(
        response.usage,
        Usage {
            input_tokens: 276,
            output_tokens: 40,
            cache_read_input_tokens: 1024,
            cache_creation_input_tokens: 0,
        }
    );
    let tool_uses: Vec<_> = response
        .tool_uses()
        .map(|tool_use| {
            (
                tool_use.id.as_str(),
                tool_use.name.as_str(),
                &tool_use.input,
            )
        })
        .collect();
    assert_eq!(
        tool_uses,
        [
            ("call_a", "grep", &json!({"pattern": "fn main"})),
            ("call_b", "list_files", &json!({})),
        ]
    );

    let request = &server.requests()[0];
    assert_eq!(request.path, "/v1/chat/completions");
    // No API key, no header
    assert!(!request.headers.contains_key("authorization"));
    let body = &request.body;
    assert_eq!(body["model"], "test-model");
    assert_eq!(body["stream"], true);
    assert_eq!(body["stream_options"]["include_usage"], true);
    assert_eq!(body["max_tokens"], 1000);
    assert_eq!(
        body["messages"],
        json!([
            {"role": "system", "content": [{"type": "text", "text": "You answer questions."}]},
            {"role": "user", "content": "Where is main?"},
        ])
    );
    assert_eq!(body["tools"][0]["function"]["name"], "grep");
}

#[tokio::test]
async fn sends_openai_reasoning_and_call_extras_back() {
    let server = FakeServer::start(vec![
        openai_sse(&[
            json!({"choices": [{"index": 0, "delta": {"reasoning_content": "Look for "}, "finish_reason": null}]}),
            json!({"choices": [{"index": 0, "delta": {"reasoning_content": "main.", "reasoning_details": [{"type": "reasoning.text", "text": "Look ", "format": "anthropic-claude-v1", "index": 0}]}, "finish_reason": null}]}),
            json!({"choices": [{"index": 0, "delta": {"reasoning_details": [{"type": "reasoning.text", "text": "here.", "index": 0}]}, "finish_reason": null}]}),
            json!({"choices": [{"index": 0, "delta": {"reasoning_details": [{"type": "reasoning.text", "signature": "sig", "index": 0}, {"type": "reasoning.encrypted", "data": "e", "index": 1}]}, "finish_reason": null}]}),
            json!({"choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": "function-call-1", "type": "function", "function": {"name": "grep", "arguments": "{\"pattern\":\"main\"}"}, "extra_content": {"google": {"thought_signature": "CvcQ"}}}]}, "finish_reason": "tool_calls"}]}),
        ]),
        openai_sse(&[
            json!({"choices": [{"index": 0, "delta": {"content": "Nothing."}, "finish_reason": "stop"}]}),
        ]),
    ])
    .await;
    let client = LlmClient::new().unwrap();
    let config = server.config(LlmApiFormat::OpenAi, Some("sk-test"));
    let tools = [grep_tool()];
    let mut messages = vec![user("Where is main?")];
    let request = LlmRequest {
        system: "",
        messages: &messages,
        tools: &tools,
    };
    let (texts, response) = collect(&client, &config, &request).await.unwrap();
    assert!(texts.is_empty());
    assert!(matches!(response.content[0], ContentBlock::Provider(_)));

    continue_loop(&mut messages, response);
    let request = LlmRequest {
        system: "",
        messages: &messages,
        tools: &tools,
    };
    let (texts, response) = collect(&client, &config, &request).await.unwrap();
    assert_eq!(texts, ["Nothing."]);
    assert_eq!(response.stop_reason, StopReason::EndTurn);

    let requests = server.requests();
    assert_eq!(requests[0].headers["authorization"], "Bearer sk-test");
    let body = &requests[1].body;
    let assistant = &body["messages"][1];
    assert_eq!(assistant["role"], "assistant");
    assert_eq!(assistant["reasoning_content"], "Look for main.");
    assert_eq!(
        assistant["reasoning_details"],
        json!([
            {"type": "reasoning.text", "text": "Look here.", "format": "anthropic-claude-v1", "index": 0, "signature": "sig"},
            {"type": "reasoning.encrypted", "data": "e", "index": 1},
        ])
    );
    assert_eq!(
        assistant["tool_calls"][0]["extra_content"],
        json!({"google": {"thought_signature": "CvcQ"}})
    );
    assert_eq!(
        body["messages"][2],
        json!({"role": "tool", "tool_call_id": "function-call-1", "content": "no matches"})
    );
}

#[tokio::test]
async fn retries_errors_before_the_first_text() {
    let server = FakeServer::start(vec![
        json_reply(
            529,
            vec![("retry-after", "0")],
            json!({"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}),
        ),
        json_reply(
            429,
            vec![("retry-after", "0")],
            json!({"error": {"message": "Rate limited", "type": "rate_limit_error"}}),
        ),
        anthropic_text("Hi"),
    ])
    .await;
    let client = LlmClient::new().unwrap();
    let config = server.config(LlmApiFormat::Anthropic, Some("sk-test"));
    let messages = [user("Hello")];
    let request = LlmRequest {
        system: "",
        messages: &messages,
        tools: &[],
    };
    let (texts, response) = collect(&client, &config, &request).await.unwrap();
    assert_eq!(texts, ["Hi"]);
    assert_eq!(response.content, [ContentBlock::Text("Hi".to_string())]);
    assert_eq!(server.requests().len(), 3);
}

#[tokio::test]
async fn returns_errors_after_the_first_text_and_rejections() {
    let server = FakeServer::start(vec![
        anthropic_sse(&[
            json!({"type": "message_start", "message": {"id": "msg_1", "type": "message", "role": "assistant", "content": [], "model": "test-model", "usage": {"input_tokens": 1, "output_tokens": 1}}}),
            json!({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            json!({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Partial"}}),
            json!({"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}),
        ]),
        json_reply(
            400,
            vec![],
            json!({"type": "error", "error": {"type": "invalid_request_error", "message": "Unknown model"}}),
        ),
    ])
    .await;
    let client = LlmClient::new().unwrap();
    let config = server.config(LlmApiFormat::Anthropic, Some("sk-test"));
    let messages = [user("Hello")];
    let request = LlmRequest {
        system: "",
        messages: &messages,
        tools: &[],
    };

    let (texts, error) = collect(&client, &config, &request).await.unwrap_err();
    assert_eq!(texts, ["Partial"]);
    assert!(error.is_retryable());
    assert_eq!(
        error.to_string(),
        "LLM API error (overloaded_error): Overloaded"
    );

    let (texts, error) = collect(&client, &config, &request).await.unwrap_err();
    assert!(texts.is_empty());
    assert!(!error.is_retryable());
    assert_eq!(
        error.to_string(),
        "LLM API returned 400 Bad Request: Unknown model"
    );
    assert_eq!(server.requests().len(), 2);
}

#[tokio::test]
async fn lists_models_of_both_formats() {
    let server = FakeServer::start(vec![
        json_reply(
            200,
            vec![],
            json!({
                "data": [{"type": "model", "id": "claude-opus-5-5", "display_name": "Claude Opus 5.5", "created_at": "2026-08-01T00:00:00Z"}],
                "has_more": true,
                "first_id": "claude-opus-5-5",
                "last_id": "claude-opus-5-5",
            }),
        ),
        json_reply(
            200,
            vec![],
            json!({
                "data": [{"type": "model", "id": "claude-sonnet-5-5", "display_name": "Claude Sonnet 5.5", "created_at": "2026-09-01T00:00:00Z"}],
                "has_more": false,
                "first_id": "claude-sonnet-5-5",
                "last_id": "claude-sonnet-5-5",
            }),
        ),
        json_reply(
            200,
            vec![],
            json!({
                "object": "list",
                "data": [
                    {"id": "local-model", "name": "local-model", "object": "model", "owned_by": "me"},
                    {"id": "gpt-old", "object": "model", "created": 1_600_000_000},
                    {"id": "anthropic/claude-opus-5.5", "name": "Anthropic: Claude Opus 5.5", "created": 1_780_000_000},
                    {"id": "gpt-old", "object": "model", "created": 1_600_000_000},
                ],
            }),
        ),
        json_reply(404, vec![], json!({"error": "not found"})),
    ])
    .await;
    let client = LlmClient::new().unwrap();
    let names = |models: Vec<RemoteModel>| -> Vec<(String, Option<String>)> {
        models
            .into_iter()
            .map(|model| (model.api_name, model.display_name))
            .collect()
    };

    let models = client
        .list_models(LlmApiFormat::Anthropic, &server.base_url, Some("sk-test"))
        .await
        .unwrap();
    assert_eq!(
        names(models),
        [
            (
                "claude-opus-5-5".to_string(),
                Some("Claude Opus 5.5".to_string())
            ),
            (
                "claude-sonnet-5-5".to_string(),
                Some("Claude Sonnet 5.5".to_string())
            ),
        ]
    );

    let base_url = format!("{}/v1", server.base_url);
    let models = client
        .list_models(LlmApiFormat::OpenAi, &base_url, None)
        .await
        .unwrap();
    assert_eq!(
        names(models),
        [
            (
                "anthropic/claude-opus-5.5".to_string(),
                Some("Anthropic: Claude Opus 5.5".to_string())
            ),
            ("gpt-old".to_string(), None),
            ("local-model".to_string(), None),
        ]
    );

    let error = client
        .list_models(LlmApiFormat::OpenAi, &base_url, None)
        .await
        .unwrap_err();
    assert!(
        matches!(&error, LlmError::Status { status, message } if status.as_u16() == 404 && message == "not found"),
        "{error:?}"
    );

    let requests = server.requests();
    assert_eq!(requests[0].path, "/v1/models");
    assert_eq!(requests[1].path, "/v1/models");
    assert_eq!(requests[2].path, "/v1/models");
}

#[test]
fn retries_only_temporary_status_codes() {
    let status = |code: u16| LlmError::Status {
        status: StatusCode::from_u16(code).unwrap(),
        message: String::new(),
    };
    assert!(status(429).is_retryable());
    assert!(status(529).is_retryable());
    assert!(status(503).is_retryable());
    assert!(!status(400).is_retryable());
    assert!(!status(401).is_retryable());
    assert!(!status(404).is_retryable());
}
