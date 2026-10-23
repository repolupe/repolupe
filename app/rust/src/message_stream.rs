//! The message stream of an answer (`GET /api/v1/chats/{id}/messages/{message_id}/stream`) as
//! typed events, read from the SSE body of either transport, and its hand-over to Dart.

use std::collections::VecDeque;
use std::pin::Pin;
use std::task::{Context, Poll, ready};

use axum::http::StatusCode;
use futures_util::stream::{Stream, StreamExt};
use repolupe::dto::chat::{ContentDeltaDto, MessageDto, ToolCallFinishedDto, ToolCallSummaryDto};
use serde::de::DeserializeOwned;
use tokio_util::sync::CancellationToken;

use crate::api::error::ClientError;
use crate::api::stream::MessageEvent;
use crate::sse::{SseEvent, SseParser};
use crate::transport::ByteStream;

/// The events of a message stream. Ends after `Done` or `Error`, or when the body ends;
/// the body (and so the request) is dropped as soon as it ends.
pub struct MessageEvents {
    status: StatusCode,
    body: Option<ByteStream>,
    parser: SseParser,
    pending: VecDeque<MessageEvent>,
}

impl MessageEvents {
    /// The events of the SSE `body` of a response with `status`.
    pub fn new(status: StatusCode, body: ByteStream) -> Self {
        MessageEvents {
            status,
            body: Some(body),
            parser: SseParser::new(),
            pending: VecDeque::new(),
        }
    }

    fn decode(&self, event: SseEvent) -> Option<MessageEvent> {
        let event = match event.event.as_str() {
            "snapshot" => self
                .parse::<MessageDto>(&event)
                .map(|message| MessageEvent::Snapshot { message }),
            "content_delta" => self
                .parse::<ContentDeltaDto>(&event)
                .map(|delta| MessageEvent::ContentDelta { delta }),
            "tool_call_started" => self
                .parse::<ToolCallSummaryDto>(&event)
                .map(|tool_call| MessageEvent::ToolCallStarted { tool_call }),
            "tool_call_finished" => self
                .parse::<ToolCallFinishedDto>(&event)
                .map(|tool_call| MessageEvent::ToolCallFinished { tool_call }),
            "done" => self
                .parse::<MessageDto>(&event)
                .map(|message| MessageEvent::Done { message }),
            // From a newer server.
            _ => return None,
        };
        Some(event.unwrap_or_else(|error| MessageEvent::Error { error }))
    }

    /// The data of a known event, which must parse: skipping it would leave the client with a
    /// different message than the server.
    fn parse<T: DeserializeOwned>(&self, event: &SseEvent) -> Result<T, ClientError> {
        serde_json::from_str(&event.data).map_err(|error| ClientError::InvalidResponse {
            status: self.status.as_u16(),
            message: format!("Invalid `{}` event: {error}", event.event),
        })
    }
}

impl Stream for MessageEvents {
    type Item = MessageEvent;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<MessageEvent>> {
        loop {
            if let Some(event) = self.pending.pop_front() {
                if matches!(
                    event,
                    MessageEvent::Done { .. } | MessageEvent::Error { .. }
                ) {
                    self.pending.clear();
                    self.body = None;
                }
                return Poll::Ready(Some(event));
            }
            let Some(body) = self.body.as_mut() else {
                return Poll::Ready(None);
            };
            match ready!(body.poll_next_unpin(cx)) {
                Some(Ok(chunk)) => {
                    for event in self.parser.push(&chunk) {
                        if let Some(event) = self.decode(event) {
                            self.pending.push_back(event);
                        }
                    }
                }
                Some(Err(error)) => {
                    self.body = None;
                    return Poll::Ready(Some(MessageEvent::Error { error }));
                }
                // An event not terminated by an empty line is discarded, as the spec says.
                None => {
                    self.body = None;
                    return Poll::Ready(None);
                }
            }
        }
    }
}

/// Hands the events to `send` until the stream ends, `send` returns `false` (the Dart stream
/// was closed), or `cancel` is cancelled. Dropping `events` and `send` then ends the request
/// and closes the Dart stream.
pub async fn forward(
    mut events: MessageEvents,
    cancel: CancellationToken,
    mut send: impl FnMut(MessageEvent) -> bool,
) {
    loop {
        let event = tokio::select! {
            biased;
            () = cancel.cancelled() => return,
            event = events.next() => event,
        };
        let Some(event) = event else { return };
        if !send(event) {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use bytes::Bytes;
    use futures_executor::block_on;
    use serde_json::json;
    use uuid::Uuid;

    use super::*;

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

    fn message(status: &str, content: &str) -> String {
        json!({
            "id": Uuid::now_v7(),
            "role": "ASSISTANT",
            "content": content,
            "status": status,
            "error": null,
            "model_id": null,
            "tool_calls": [],
            "created_at": "2026-10-20T10:00:00Z",
            "finished_at": null,
            "usage": null,
            "cost": null,
            "attachment": null,
        })
        .to_string()
    }

    /// A stream like the server's for one answer, with keep-alives and an unknown event.
    fn answer() -> String {
        let id = Uuid::now_v7();
        let tool_call = json!({
            "id": id,
            "name": "read_attachment",
            "input": {"attachment": 1},
            "repository_id": null,
            "commit_sha": null,
            "status": "RUNNING",
            "created_at": "2026-10-20T10:00:01Z",
        });
        let finished = json!({"id": id, "status": "COMPLETED"});
        let snapshot = message("GENERATING", "");
        let done = message("COMPLETED", "Hällo 😀");
        format!(
            "event: snapshot\ndata: {snapshot}\n\n:\n\n\
             event: tool_call_started\ndata: {tool_call}\n\n\
             event: tool_call_finished\ndata: {finished}\n\n\
             event: title_changed\ndata: {{\"title\":\"newer server\"}}\n\n\
             data: {{\"default\":\"type\"}}\n\n\
             event: content_delta\ndata: {{\"text\":\"Hällo\"}}\n\n\
             event: content_delta\r\ndata: {{\"text\":\" 😀\"}}\r\n\r\n\
             event: done\ndata: {done}\n\n"
        )
    }

    fn events(chunks: Vec<Result<Bytes, ClientError>>) -> Vec<String> {
        let events = MessageEvents::new(StatusCode::OK, ByteStream::from_chunks(chunks));
        block_on(events.map(|event| describe(&event)).collect())
    }

    const ANSWER: [&str; 6] = [
        r#"snapshot GENERATING """#,
        "started read_attachment RUNNING",
        "finished COMPLETED",
        r#"delta "Hällo""#,
        r#"delta " 😀""#,
        r#"done COMPLETED "Hällo 😀""#,
    ];

    #[test]
    fn decodes_every_event() {
        let answer = answer();
        assert_eq!(events(vec![Ok(Bytes::from(answer.clone()))]), ANSWER);
        // Split anywhere, also inside the UTF-8 sequences.
        let bytes = answer.as_bytes();
        for size in [1, 2, 3, 7, 64] {
            let chunks = bytes
                .chunks(size)
                .map(|chunk| Ok(Bytes::copy_from_slice(chunk)))
                .collect();
            assert_eq!(events(chunks), ANSWER, "chunks of {size}");
        }
    }

    #[test]
    fn ends_after_done() {
        let done = message("CANCELLED", "partial");
        let chunks = vec![
            Ok(Bytes::from(format!(
                "event: done\ndata: {done}\n\nevent: content_delta\ndata: {{\"text\":\"x\"}}\n\n"
            ))),
            Err(ClientError::Transport {
                message: "never read".into(),
            }),
        ];
        assert_eq!(events(chunks), [r#"done CANCELLED "partial""#]);
    }

    #[test]
    fn transport_errors_end_the_stream() {
        let snapshot = message("GENERATING", "a");
        let error = ClientError::Transport {
            message: "connection reset".into(),
        };
        let chunks = vec![
            Ok(Bytes::from(format!(
                "event: snapshot\ndata: {snapshot}\n\n"
            ))),
            Ok(Bytes::from_static(b"event: content_delta\ndata: {\"te")),
            Err(error.clone()),
        ];
        assert_eq!(
            events(chunks),
            [
                r#"snapshot GENERATING "a""#.to_owned(),
                format!("error {error:?}")
            ]
        );
    }

    #[test]
    fn invalid_events_end_the_stream() {
        let chunks = vec![Ok(Bytes::from_static(
            b"event: content_delta\ndata: {\"text\":1}\n\nevent: content_delta\ndata: {\"text\":\"b\"}\n\n",
        ))];
        let events = events(chunks);
        assert_eq!(events.len(), 1);
        assert!(
            events[0].starts_with(
                "error InvalidResponse { status: 200, message: \"Invalid `content_delta` event:"
            ),
            "{events:?}"
        );
    }

    #[test]
    fn ends_with_the_body() {
        // Without `done`, e.g. when the server dropped a client that fell behind. An event not
        // terminated is discarded.
        let chunks = vec![Ok(Bytes::from_static(
            b"event: content_delta\ndata: {\"text\":\"a\"}\n\nevent: content_delta\ndata: {\"text\":\"b\"}\n",
        ))];
        assert_eq!(events(chunks), [r#"delta "a""#]);
        assert!(events(vec![]).is_empty());
    }

    #[test]
    fn forward_stops_when_the_receiver_is_gone() {
        let chunks = vec![Ok(Bytes::from(answer()))];
        let events = MessageEvents::new(StatusCode::OK, ByteStream::from_chunks(chunks));
        let mut received = Vec::new();
        block_on(forward(events, CancellationToken::new(), |event| {
            received.push(describe(&event));
            received.len() < 2
        }));
        assert_eq!(received, ANSWER[..2]);
    }

    #[test]
    fn forward_stops_when_cancelled() {
        let chunks = vec![Ok(Bytes::from(answer()))];
        let events = MessageEvents::new(StatusCode::OK, ByteStream::from_chunks(chunks));
        let cancel = CancellationToken::new();
        cancel.cancel();
        let mut received = 0;
        block_on(forward(events, cancel, |_| {
            received += 1;
            true
        }));
        assert_eq!(received, 0);
    }
}
