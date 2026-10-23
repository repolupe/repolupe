//! The events of an answer's message stream (`Client::stream_message`) and the token that
//! cancels it.

use flutter_rust_bridge::frb;
use repolupe::dto::chat::{ContentDeltaDto, MessageDto, ToolCallFinishedDto, ToolCallSummaryDto};

use crate::api::error::ClientError;

/// An event of `GET /api/v1/chats/{id}/messages/{message_id}/stream`.
///
/// The stream starts with `Snapshot` and ends after `Done` or `Error`. Between them, the deltas
/// apply to the snapshot in order. It may also close without either: when it was cancelled, or
/// when the client fell behind the answer, in which case the server ends it and the client
/// subscribes again to start from a fresh snapshot (as the web's `EventSource` does).
/// Events of a newer server that this client does not know are skipped.
pub enum MessageEvent {
    /// The message as it is now, the first event: replaces what the client had, also when it
    /// subscribes again. A message that already finished is followed by `Done` right away.
    Snapshot { message: MessageDto },
    /// Text appended to the message's `content`.
    ContentDelta { delta: ContentDeltaDto },
    /// A tool call started (status `RUNNING`), appended to the message's `tool_calls`.
    ToolCallStarted { tool_call: ToolCallSummaryDto },
    /// A tool call in the message's `tool_calls` finished with `status`.
    ToolCallFinished { tool_call: ToolCallFinishedDto },
    /// The final message (`COMPLETED`, `FAILED` or `CANCELLED`), the last event.
    Done { message: MessageDto },
    /// The stream broke off after it started (e.g. the connection was lost) or sent an event
    /// this client could not read; the last event. Subscribe again to continue.
    Error { error: ClientError },
}

/// Cancels the message streams it was passed to (`Client::stream_message`): their Rust side
/// stops, the request ends, and the Dart streams close. Cancelling the Dart subscription alone
/// does not stop the Rust side while no event arrives. A stream started with a token that was
/// already cancelled closes right away.
#[frb(opaque)]
pub struct CancellationToken {
    inner: tokio_util::sync::CancellationToken,
}

// A `Default` impl would add an async `default_()` to the Dart class.
#[allow(clippy::new_without_default)]
impl CancellationToken {
    #[frb(sync)]
    pub fn new() -> CancellationToken {
        CancellationToken {
            inner: tokio_util::sync::CancellationToken::new(),
        }
    }

    /// Cancels the streams of this token. Idempotent.
    #[frb(sync)]
    pub fn cancel(&self) {
        self.inner.cancel();
    }

    /// Whether [`CancellationToken::cancel`] was called.
    #[frb(sync)]
    pub fn is_cancelled(&self) -> bool {
        self.inner.is_cancelled()
    }

    /// The token the streams wait on.
    pub(crate) fn inner(&self) -> tokio_util::sync::CancellationToken {
        self.inner.clone()
    }
}
