//! The error of every client request.

use std::error::Error;

use axum::http::StatusCode;
use repolupe::dto::error::{ErrorCode, ErrorDto};

/// Why a request failed. Plain data (no sources, numeric status), so it can be exposed to Dart
/// as a typed exception.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ClientError {
    /// The API answered with an error (`ErrorDto`). Clients branch on `code`, which is
    /// `ErrorCode::Unknown` for a code of a newer server.
    #[error("{message} ({code:?}, status {status})")]
    Api {
        status: u16,
        code: ErrorCode,
        message: String,
    },
    /// The API answered, but not as expected: an error status without an `ErrorDto` body
    /// (e.g. from a proxy), or a body that isn't the expected JSON.
    #[error("{message} (status {status})")]
    InvalidResponse { status: u16, message: String },
    /// There is no (complete) response: invalid URL, connection, TLS or timeout errors, a body
    /// that broke off, or a local request that panicked.
    #[error("{message}")]
    Transport { message: String },
}

impl ClientError {
    /// The error for a response with an unsuccessful `status` and its `body`.
    pub(crate) fn from_error_response(status: StatusCode, body: &[u8]) -> Self {
        match serde_json::from_slice::<ErrorDto>(body) {
            Ok(ErrorDto { code, message }) => ClientError::Api {
                status: status.as_u16(),
                code,
                message,
            },
            Err(_) => ClientError::InvalidResponse {
                status: status.as_u16(),
                message: format!("Unexpected response: {status}"),
            },
        }
    }

    pub(crate) fn transport(error: &(dyn Error + 'static)) -> Self {
        ClientError::Transport {
            message: error_chain(error),
        }
    }
}

/// The error and its sources, since reqwest's own message is mostly "error sending request".
fn error_chain(error: &(dyn Error + 'static)) -> String {
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(error) = source {
        let text = error.to_string();
        if !message.contains(&text) {
            message.push_str(": ");
            message.push_str(&text);
        }
        source = error.source();
    }
    message
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_error_dto() {
        let body = br#"{"code":"NOT_FOUND","message":"Chat not found."}"#;
        assert_eq!(
            ClientError::from_error_response(StatusCode::NOT_FOUND, body),
            ClientError::Api {
                status: 404,
                code: ErrorCode::NotFound,
                message: "Chat not found.".into(),
            }
        );
    }

    #[test]
    fn codes_of_newer_servers_are_unknown() {
        let body = br#"{"code":"NEWER_CODE","message":"New."}"#;
        assert_eq!(
            ClientError::from_error_response(StatusCode::CONFLICT, body),
            ClientError::Api {
                status: 409,
                code: ErrorCode::Unknown,
                message: "New.".into(),
            }
        );
    }

    #[test]
    fn other_bodies_are_invalid_responses() {
        for body in [&b"<html>Bad Gateway</html>"[..], b"", br#"{"message":"?"}"#] {
            assert_eq!(
                ClientError::from_error_response(StatusCode::BAD_GATEWAY, body),
                ClientError::InvalidResponse {
                    status: 502,
                    message: "Unexpected response: 502 Bad Gateway".into(),
                }
            );
        }
    }

    #[test]
    fn transport_message_includes_sources() {
        #[derive(Debug, thiserror::Error)]
        #[error("error sending request")]
        struct Outer(#[source] std::io::Error);

        let error = Outer(std::io::Error::new(
            std::io::ErrorKind::ConnectionRefused,
            "connection refused",
        ));
        assert_eq!(
            ClientError::transport(&error),
            ClientError::Transport {
                message: "error sending request: connection refused".into(),
            }
        );
    }
}
