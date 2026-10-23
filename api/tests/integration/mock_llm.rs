use axum::body::Body;
use axum::extract::{Query, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use futures_util::{StreamExt, stream};
use serde_json::{Value, json};
use std::collections::{HashMap, VecDeque};
use std::convert::Infallible;
use std::sync::{Arc, Mutex};
use std::task::Poll;
use std::time::Duration;
use tokio::sync::watch;
use tokio::task::JoinHandle;

/// The models [`MockLlm`] lists, oldest first.
pub const MODELS: [(&str, &str); 3] = [
    ("mock-model", "Mock Model"),
    ("mock-model-2", "Mock Model 2"),
    ("mock-model-3", "Mock Model 3"),
];

/// Longest wait in [`MockLlm::wait_for_stalled`].
const STALL_TIMEOUT: Duration = Duration::from_secs(10);

/// An Anthropic Messages API on localhost that answers the n-th request with the n-th
/// scripted response and records the request bodies. Lists [`MODELS`], two per page. Stops
/// when dropped.
pub struct MockLlm {
    pub base_url: String,
    state: Arc<MockState>,
    server: JoinHandle<()>,
}

struct MockState {
    responses: Mutex<VecDeque<MockResponse>>,
    requests: Mutex<Vec<Value>>,
    /// Stalled responses still streaming, see [`StallGuard`].
    stalled: watch::Sender<usize>,
}

impl MockLlm {
    pub async fn start(responses: Vec<MockResponse>) -> Self {
        let state = Arc::new(MockState {
            responses: Mutex::new(responses.into()),
            requests: Mutex::new(Vec::new()),
            stalled: watch::Sender::new(0),
        });
        let router = Router::new()
            .route("/v1/messages", post(messages))
            .route("/v1/models", get(models))
            .with_state(state.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        Self {
            base_url,
            state,
            server,
        }
    }

    /// The bodies of the requests so far.
    pub fn requests(&self) -> Vec<Value> {
        self.state.requests.lock().unwrap().clone()
    }

    /// The stalled responses still streaming. A response stops when the client disconnects.
    pub fn stalled(&self) -> usize {
        *self.state.stalled.borrow()
    }

    /// Waits until [`Self::stalled`] is `count`.
    pub async fn wait_for_stalled(&self, count: usize) {
        let mut stalled = self.state.stalled.subscribe();
        tokio::time::timeout(STALL_TIMEOUT, stalled.wait_for(|&n| n == count))
            .await
            .unwrap_or_else(|_| {
                panic!("expected {count} stalled responses, got {}", self.stalled())
            })
            .unwrap();
    }
}

/// Counts a stalled response in [`MockState::stalled`] until its body is dropped, which
/// happens when the client disconnects.
struct StallGuard(Arc<MockState>);

impl StallGuard {
    fn new(state: Arc<MockState>) -> Self {
        state.stalled.send_modify(|n| *n += 1);
        Self(state)
    }
}

impl Drop for StallGuard {
    fn drop(&mut self) {
        self.0.stalled.send_modify(|n| *n -= 1);
    }
}

impl Drop for MockLlm {
    fn drop(&mut self) {
        self.server.abort();
    }
}

async fn messages(State(state): State<Arc<MockState>>, Json(body): Json<Value>) -> Response {
    state.requests.lock().unwrap().push(body);
    match state.responses.lock().unwrap().pop_front() {
        Some(response) => {
            let body = stream::once(async move { Ok::<_, Infallible>(response.sse) });
            let body = if response.stall {
                let guard = StallGuard::new(state.clone());
                let pending = stream::poll_fn(move |_| {
                    let _guard = &guard;
                    Poll::Pending
                });
                Body::from_stream(body.chain(pending))
            } else {
                Body::from_stream(body)
            };
            ([(header::CONTENT_TYPE, "text/event-stream")], body).into_response()
        }
        // 400, since the client retries server errors
        None => (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "type": "error",
                "error": {"type": "invalid_request_error", "message": "No scripted response left"},
            })),
        )
            .into_response(),
    }
}

/// Two per page, newest first, in the format of the Anthropic Models API.
async fn models(Query(query): Query<HashMap<String, String>>) -> Json<Value> {
    let models: Vec<Value> = MODELS
        .iter()
        .enumerate()
        .rev()
        .map(|(i, (id, display_name))| {
            json!({
                "type": "model",
                "id": id,
                "display_name": display_name,
                "created_at": format!("2026-01-0{}T00:00:00Z", i + 1),
            })
        })
        .collect();
    let start = match query.get("after_id") {
        Some(after_id) => models.iter().position(|m| m["id"] == **after_id).unwrap() + 1,
        None => 0,
    };
    let page = &models[start..models.len().min(start + 2)];
    Json(json!({
        "data": page,
        "has_more": start + page.len() < models.len(),
        "first_id": page.first().map(|m| m["id"].clone()),
        "last_id": page.last().map(|m| m["id"].clone()),
    }))
}

/// A scripted response, see [`text_response`], [`tool_use_response`],
/// [`text_and_tool_use_response`], [`error_response`] and [`stalled_response`].
pub struct MockResponse {
    sse: String,
    /// Keeps the stream open after `sse` until the client disconnects, so the answer stays
    /// `GENERATING`. Counted in [`MockLlm::stalled`].
    stall: bool,
}

/// A response with one text block.
pub fn text_response(text: &str) -> MockResponse {
    complete(&[
        json!({"type": "message_start", "message": {"usage": {"input_tokens": 1}}}),
        json!({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
        json!({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text}}),
        json!({"type": "content_block_stop", "index": 0}),
        json!({"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 1}}),
        json!({"type": "message_stop"}),
    ])
}

/// A response that calls the tool `name` with `input`.
pub fn tool_use_response(id: &str, name: &str, input: Value) -> MockResponse {
    complete(&[
        json!({"type": "message_start", "message": {"usage": {"input_tokens": 1}}}),
        json!({"type": "content_block_start", "index": 0, "content_block": {"type": "tool_use", "id": id, "name": name, "input": {}}}),
        json!({"type": "content_block_delta", "index": 0, "delta": {"type": "input_json_delta", "partial_json": input.to_string()}}),
        json!({"type": "content_block_stop", "index": 0}),
        json!({"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 1}}),
        json!({"type": "message_stop"}),
    ])
}

/// Like [`tool_use_response`], with a text block like "Let me look" before the tool call.
pub fn text_and_tool_use_response(text: &str, id: &str, name: &str, input: Value) -> MockResponse {
    complete(&[
        json!({"type": "message_start", "message": {"usage": {"input_tokens": 1}}}),
        json!({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
        json!({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text}}),
        json!({"type": "content_block_stop", "index": 0}),
        json!({"type": "content_block_start", "index": 1, "content_block": {"type": "tool_use", "id": id, "name": name, "input": {}}}),
        json!({"type": "content_block_delta", "index": 1, "delta": {"type": "input_json_delta", "partial_json": input.to_string()}}),
        json!({"type": "content_block_stop", "index": 1}),
        json!({"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 1}}),
        json!({"type": "message_stop"}),
    ])
}

/// A response that fails with an error event of `kind` after the status 200 and `text`, if
/// not empty.
pub fn error_response(kind: &str, text: &str) -> MockResponse {
    let mut events =
        vec![json!({"type": "message_start", "message": {"usage": {"input_tokens": 1}}})];
    if !text.is_empty() {
        events.extend([
            json!({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            json!({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": text}}),
        ]);
    }
    events.push(json!({"type": "error", "error": {"type": kind, "message": "Overloaded"}}));
    complete(&events)
}

/// A response that starts a text block and never finishes.
pub fn stalled_response() -> MockResponse {
    MockResponse {
        sse: sse(&[
            json!({"type": "message_start", "message": {"usage": {"input_tokens": 1}}}),
            json!({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}),
            json!({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Let me"}}),
        ]),
        stall: true,
    }
}

/// The result the model got for its tool call in `request`, the first block of the last
/// message, with its text content as one string and `is_error` also when it is false, which
/// the client may leave out.
pub fn tool_result(request: &Value) -> Value {
    let messages = request["messages"].as_array().unwrap();
    let mut result = messages.last().unwrap()["content"][0].clone();
    assert_eq!(result["type"], "tool_result", "{result}");
    if let Some(blocks) = result["content"].as_array() {
        let text: Vec<&str> = blocks
            .iter()
            .map(|block| block["text"].as_str().unwrap())
            .collect();
        result["content"] = json!(text.join("\n"));
    }
    if result["is_error"].is_null() {
        result["is_error"] = json!(false);
    }
    result
}

fn complete(events: &[Value]) -> MockResponse {
    MockResponse {
        sse: sse(events),
        stall: false,
    }
}

fn sse(events: &[Value]) -> String {
    events
        .iter()
        .map(|event| {
            format!(
                "event: {}\ndata: {event}\n\n",
                event["type"].as_str().unwrap()
            )
        })
        .collect()
}
