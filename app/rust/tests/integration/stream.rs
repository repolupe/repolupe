//! The message stream through both transports: against a small router for the transport's
//! side (errors, broken streams, cancelling), and against a real Repolupe that generates
//! answers with a mock Anthropic API on 127.0.0.1.

use std::collections::VecDeque;
use std::convert::Infallible;
use std::sync::mpsc as std_mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use axum::Router;
use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use bytes::Bytes;
use futures_executor::block_on;
use futures_util::stream::{self, StreamExt};
use repolupe::dto::auth::LoginRequest;
use repolupe::dto::chat::{CreateChatRequest, MessageStatus};
use repolupe::dto::error::{ErrorCode, ErrorDto};
use repolupe::dto::llm::{CreateLlmProviderRequest, LlmApiFormat, LlmModelRequest};
use repolupe::dto::user::ChangePasswordRequest;
use repolupe::{DEFAULT_INITIAL_ADMIN_PASSWORD, INITIAL_ADMIN_USER_NAME};
use serde_json::{Value, json};
use tokio::sync::Semaphore;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use repolupe_ffi::api::client::Client;
use repolupe_ffi::api::error::ClientError;
use repolupe_ffi::api::stream::MessageEvent;
use repolupe_ffi::message_stream::{MessageEvents, forward};
use repolupe_ffi::runtime::runtime;
use repolupe_ffi::transport::Transport;

use crate::client::{Local, PASSWORD, serve};

const TIMEOUT: Duration = Duration::from_secs(10);

/// The message ids the test router answers.
const ENDLESS: Uuid = Uuid::from_u128(1);
const BROKEN: Uuid = Uuid::from_u128(2);

/// The events as text, since the DTOs don't implement `Debug`.
fn describe(event: &MessageEvent) -> String {
    match event {
        MessageEvent::Snapshot { message } => {
            format!("snapshot {} {:?}", name(&message.status), message.content)
        }
        MessageEvent::ContentDelta { delta } => format!("delta {:?}", delta.text),
        MessageEvent::ToolCallStarted { tool_call } => {
            format!("started {} {}", tool_call.name, name(&tool_call.status))
        }
        MessageEvent::ToolCallFinished { tool_call } => {
            format!("finished {}", name(&tool_call.status))
        }
        MessageEvent::Done { message } => {
            format!("done {} {:?}", name(&message.status), message.content)
        }
        MessageEvent::Error { error } => format!("error {error:?}"),
    }
}

/// A status as the API names it.
fn name(status: &impl serde::Serialize) -> String {
    serde_json::to_value(status)
        .unwrap()
        .as_str()
        .unwrap()
        .to_owned()
}

/// Events forwarded on the crate's runtime, as `Client::stream_message` does, into a channel.
struct Forwarded {
    events: std_mpsc::Receiver<String>,
    task: JoinHandle<()>,
}

impl Forwarded {
    fn start(events: MessageEvents, cancel: CancellationToken) -> Self {
        let (sender, receiver) = std_mpsc::channel();
        let task = runtime().spawn(forward(events, cancel, move |event| {
            sender.send(describe(&event)).is_ok()
        }));
        Forwarded {
            events: receiver,
            task,
        }
    }

    fn next(&self) -> String {
        self.events
            .recv_timeout(TIMEOUT)
            .expect("no event within the timeout")
    }

    /// Waits until forwarding stopped and returns the events left.
    fn finish(self) -> Vec<String> {
        runtime()
            .block_on(async { tokio::time::timeout(TIMEOUT, self.task).await })
            .expect("forwarding did not stop")
            .unwrap();
        self.events.try_iter().collect()
    }
}

fn message_json(id: Uuid, status: &str, content: &str) -> Value {
    json!({
        "id": id, "role": "ASSISTANT", "content": content, "status": status, "error": null,
        "model_id": null, "tool_calls": [], "created_at": "2026-10-20T10:00:00Z",
        "finished_at": null, "usage": null, "cost": null, "attachment": null,
    })
}

/// Reports through `dropped` when dropped.
struct DropGuard(std_mpsc::Sender<()>);

impl Drop for DropGuard {
    fn drop(&mut self) {
        let _ = self.0.send(());
    }
}

/// `GET .../stream` like the server's: 401 without a token, 406 without `Accept`, else a
/// snapshot and a delta (in chunks that split a line and a UTF-8 sequence) and then either
/// nothing ([`ENDLESS`], reporting through `dropped` when the body is dropped) or a broken
/// body ([`BROKEN`]).
fn stream_router(dropped: std_mpsc::Sender<()>) -> Router {
    let handler = move |Path((_, message_id)): Path<(Uuid, Uuid)>, headers: HeaderMap| {
        let dropped = dropped.clone();
        async move {
            if headers
                .get(AUTHORIZATION)
                .is_none_or(|v| v != "Bearer token")
            {
                let body = serde_json::to_string(&ErrorDto {
                    code: ErrorCode::Unauthorized,
                    message: "Not logged in.".into(),
                })
                .unwrap();
                return (
                    StatusCode::UNAUTHORIZED,
                    [(CONTENT_TYPE, "application/json")],
                    body,
                )
                    .into_response();
            }
            if headers.get(ACCEPT).is_none_or(|v| v != "text/event-stream") {
                return StatusCode::NOT_ACCEPTABLE.into_response();
            }
            let snapshot = message_json(message_id, "GENERATING", "");
            let text = format!(
                ": keep-alive\n\nevent: snapshot\ndata: {snapshot}\n\nevent: content_delta\ndata: {{\"text\":\"Grüße\"}}\n\n"
            );
            // Inside the `ü`.
            let split = text.find('ü').unwrap() + 1;
            let bytes = Bytes::from(text);
            let first = stream::iter([
                Ok::<_, std::io::Error>(bytes.slice(..split)),
                Ok(bytes.slice(split..)),
            ]);
            let body = if message_id == BROKEN {
                // After a pause, so hyper sends the head and the chunks first.
                Body::from_stream(first.chain(stream::once(async {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    Err(std::io::Error::other("broken on purpose"))
                })))
            } else {
                let guard = DropGuard(dropped);
                let rest = stream::pending().map(move |()| {
                    let _ = &guard;
                    Ok(Bytes::new())
                });
                Body::from_stream(first.chain(rest))
            };
            ([(CONTENT_TYPE, "text/event-stream")], body).into_response()
        }
    };
    Router::new().route("/api/v1/chats/{chat_id}/messages/{id}/stream", get(handler))
}

fn transports(router: Router) -> Vec<Transport> {
    let remote = Transport::remote(&serve(router.clone())).unwrap();
    vec![Transport::local(router), remote]
}

#[test]
fn errors_before_the_stream_are_returned() {
    let (dropped, _) = std_mpsc::channel();
    for transport in transports(stream_router(dropped)) {
        let client = Client::new(transport, None);
        let result = block_on(client.message_events(Uuid::now_v7(), ENDLESS));
        assert!(
            matches!(
                result,
                Err(ClientError::Api {
                    status: 401,
                    code: ErrorCode::Unauthorized,
                    ..
                })
            ),
            "{:?}",
            result.err()
        );
    }
}

#[test]
fn broken_streams_end_with_an_error() {
    let (dropped, _) = std_mpsc::channel();
    for transport in transports(stream_router(dropped)) {
        let client = Client::new(transport, Some("token".into()));
        let events = block_on(client.message_events(Uuid::now_v7(), BROKEN)).unwrap();
        let events: Vec<String> = block_on(events.map(|event| describe(&event)).collect());
        assert_eq!(events.len(), 3, "{events:?}");
        assert_eq!(events[0], r#"snapshot GENERATING """#);
        assert_eq!(events[1], r#"delta "Grüße""#);
        assert!(events[2].starts_with("error Transport"), "{events:?}");
    }
}

#[test]
fn cancelling_ends_the_request() {
    let (dropped, dropped_bodies) = std_mpsc::channel();
    for transport in transports(stream_router(dropped)) {
        let client = Client::new(transport, Some("token".into()));
        let events = block_on(client.message_events(Uuid::now_v7(), ENDLESS)).unwrap();
        let cancel = CancellationToken::new();
        let forwarded = Forwarded::start(events, cancel.clone());
        assert_eq!(forwarded.next(), r#"snapshot GENERATING """#);
        assert_eq!(forwarded.next(), r#"delta "Grüße""#);
        cancel.cancel();
        assert!(forwarded.finish().is_empty());
        dropped_bodies
            .recv_timeout(TIMEOUT)
            .expect("the body was not dropped");
    }
}

/// Answers the n-th request with the n-th response. A response waits for a permit of its
/// gate, if it has one, and stalls after its events if `stall`, until the client disconnects.
/// Lists one model, [`MOCK_MODEL`].
pub(crate) struct MockLlm {
    pub(crate) base_url: String,
}

pub(crate) struct MockResponse {
    pub(crate) sse: String,
    pub(crate) gate: Option<Arc<Semaphore>>,
    pub(crate) stall: bool,
}

/// The model the mock LLM lists.
pub(crate) const MOCK_MODEL: &str = "mock-model";

impl MockLlm {
    pub(crate) fn start(responses: Vec<MockResponse>) -> Self {
        let responses = Arc::new(Mutex::new(VecDeque::from(responses)));
        let models = || async {
            axum::Json(json!({
                "data": [{"id": MOCK_MODEL, "display_name": "Mock Model"}],
                "has_more": false,
            }))
        };
        let router = Router::new()
            .route("/v1/messages", post(mock_messages))
            .route("/v1/models", get(models))
            .with_state(responses);
        MockLlm {
            base_url: serve(router),
        }
    }
}

async fn mock_messages(State(responses): State<Arc<Mutex<VecDeque<MockResponse>>>>) -> Response {
    let Some(response) = responses.lock().unwrap().pop_front() else {
        // 400, since the client retries server errors.
        let body = json!({"type": "error", "error": {"type": "invalid_request_error", "message": "No scripted response left"}});
        return (
            StatusCode::BAD_REQUEST,
            [(CONTENT_TYPE, "application/json")],
            body.to_string(),
        )
            .into_response();
    };
    let MockResponse { sse, gate, stall } = response;
    let events = stream::once(async move {
        if let Some(gate) = gate {
            gate.acquire().await.unwrap().forget();
        }
        Ok::<_, Infallible>(sse)
    });
    let body = if stall {
        Body::from_stream(events.chain(stream::pending()))
    } else {
        Body::from_stream(events)
    };
    ([(CONTENT_TYPE, "text/event-stream")], body).into_response()
}

/// The SSE of an Anthropic response with a text and a tool call (`(id, name, input)`), finished
/// unless `stall`.
pub(crate) fn anthropic(
    text: Option<&str>,
    tool_use: Option<(&str, &str, Value)>,
    stall: bool,
) -> String {
    let mut events =
        vec![json!({"type": "message_start", "message": {"usage": {"input_tokens": 1}}})];
    let mut index = 0;
    if let Some(text) = text {
        events.extend([
            json!({"type": "content_block_start", "index": index, "content_block": {"type": "text", "text": ""}}),
            json!({"type": "content_block_delta", "index": index, "delta": {"type": "text_delta", "text": text}}),
        ]);
        if !stall {
            events.push(json!({"type": "content_block_stop", "index": index}));
        }
        index += 1;
    }
    if let Some((id, name, input)) = &tool_use {
        events.extend([
            json!({"type": "content_block_start", "index": index, "content_block": {"type": "tool_use", "id": id, "name": name, "input": {}}}),
            json!({"type": "content_block_delta", "index": index, "delta": {"type": "input_json_delta", "partial_json": input.to_string()}}),
            json!({"type": "content_block_stop", "index": index}),
        ]);
    }
    if !stall {
        let stop_reason = if tool_use.is_some() {
            "tool_use"
        } else {
            "end_turn"
        };
        events.extend([
            json!({"type": "message_delta", "delta": {"stop_reason": stop_reason}, "usage": {"output_tokens": 1}}),
            json!({"type": "message_stop"}),
        ]);
    }
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

/// Logs in the initial admin, configures `llm` as the default model and starts an answer that
/// reads an attachment. Returns the chat and the answer's id.
fn start_answer(client: &Client, llm: &MockLlm) -> (Uuid, Uuid) {
    block_on(client.login(LoginRequest {
        user_name_or_email: INITIAL_ADMIN_USER_NAME.into(),
        password: DEFAULT_INITIAL_ADMIN_PASSWORD.into(),
    }))
    .unwrap();
    block_on(client.change_password(ChangePasswordRequest {
        current_password: DEFAULT_INITIAL_ADMIN_PASSWORD.into(),
        new_password: PASSWORD.into(),
    }))
    .unwrap();
    // An admin's provider may be on a private host over http.
    let provider = block_on(client.create_llm_provider(CreateLlmProviderRequest {
        name: "Mock".into(),
        api_format: LlmApiFormat::Anthropic,
        base_url: Some(llm.base_url.clone()),
        api_key: None,
        currency: None,
    }))
    .unwrap();
    let model = block_on(client.create_llm_model(
        provider.id,
        LlmModelRequest {
            api_name: MOCK_MODEL.into(),
            display_name: None,
            max_output_tokens: None,
            input_price: None,
            output_price: None,
            cache_read_price: None,
            cache_write_price: None,
        },
    ))
    .unwrap();
    assert!(model.is_default);
    let attachment = block_on(client.upload_attachment(
        "notes.txt".into(),
        Some("text/plain".into()),
        b"hello\n".to_vec(),
    ))
    .unwrap();
    let chat = block_on(client.create_chat(CreateChatRequest {
        content: "Read it".into(),
        attachment_id: Some(attachment.id),
        all_repositories: true,
        repository_ids: None,
        title: Some("Notes".into()),
        model_id: None,
        temporary: false,
    }))
    .unwrap();
    let answer = chat.messages.last().unwrap();
    assert_eq!(answer.status, MessageStatus::Generating);
    (chat.chat.id, answer.id)
}

/// A generation from the snapshot to `done`, with a tool call and text.
fn streams_a_generation(remote: bool) {
    let local = Local::start();
    let gate = Arc::new(Semaphore::new(0));
    let llm = MockLlm::start(vec![
        MockResponse {
            sse: anthropic(
                None,
                Some(("toolu_1", "read_attachment", json!({"attachment": 1}))),
                false,
            ),
            gate: Some(gate.clone()),
            stall: false,
        },
        MockResponse {
            sse: anthropic(Some("It says hello."), None, false),
            gate: None,
            stall: false,
        },
    ]);
    let client = if remote {
        Client::remote(serve(local.router()), None).unwrap()
    } else {
        Client::new(Transport::local(local.router()), None)
    };
    let (chat_id, answer_id) = start_answer(&client, &llm);

    // Subscribed before the model answered, so everything after the snapshot arrives live.
    let events = block_on(client.message_events(chat_id, answer_id)).unwrap();
    let forwarded = Forwarded::start(events, CancellationToken::new());
    assert_eq!(forwarded.next(), r#"snapshot GENERATING """#);
    gate.add_permits(1);
    let mut events = vec![forwarded.next()];
    events.extend(forwarded.finish());
    assert_eq!(
        events,
        [
            "started read_attachment RUNNING",
            "finished COMPLETED",
            r#"delta "It says hello.""#,
            r#"done COMPLETED "It says hello.""#,
        ]
    );

    // A finished message: its snapshot and `done`.
    let events = block_on(client.message_events(chat_id, answer_id)).unwrap();
    let events: Vec<String> = block_on(events.map(|event| describe(&event)).collect());
    assert_eq!(
        events,
        [
            r#"snapshot COMPLETED "It says hello.""#,
            r#"done COMPLETED "It says hello.""#,
        ]
    );
    // Another user's (or a missing) message.
    let result = block_on(client.message_events(chat_id, Uuid::now_v7()));
    assert!(matches!(
        result,
        Err(ClientError::Api {
            code: ErrorCode::NotFound,
            ..
        })
    ));
}

#[test]
fn streams_a_local_generation() {
    streams_a_generation(false);
}

#[test]
fn streams_a_remote_generation() {
    streams_a_generation(true);
}

/// Cancelling the stream leaves the answer running; cancelling the answer ends it.
#[test]
fn cancels_a_generation_stream() {
    let local = Local::start();
    let llm = MockLlm::start(vec![MockResponse {
        sse: anthropic(Some("Let me"), None, true),
        gate: None,
        stall: true,
    }]);
    let client = Client::new(Transport::local(local.router()), None);
    let (chat_id, answer_id) = start_answer(&client, &llm);

    let events = block_on(client.message_events(chat_id, answer_id)).unwrap();
    let cancel = CancellationToken::new();
    let forwarded = Forwarded::start(events, cancel.clone());
    let snapshot = forwarded.next();
    if snapshot == r#"snapshot GENERATING """# {
        assert_eq!(forwarded.next(), r#"delta "Let me""#);
    } else {
        assert_eq!(snapshot, r#"snapshot GENERATING "Let me""#);
    }
    cancel.cancel();
    assert!(forwarded.finish().is_empty());
    let chat = block_on(client.get_chat(chat_id)).unwrap();
    assert_eq!(
        chat.messages.last().unwrap().status,
        MessageStatus::Generating
    );

    // Subscribed again, the answer is cancelled while the stream runs.
    let events = block_on(client.message_events(chat_id, answer_id)).unwrap();
    let forwarded = Forwarded::start(events, CancellationToken::new());
    assert_eq!(forwarded.next(), r#"snapshot GENERATING "Let me""#);
    block_on(client.cancel_message(chat_id, answer_id)).unwrap();
    assert_eq!(forwarded.next(), r#"done CANCELLED "Let me""#);
    assert!(forwarded.finish().is_empty());
}
