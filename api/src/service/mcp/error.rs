//! Why connecting to an MCP server or a request to it failed, found out from the errors of rmcp,
//! oauth2 and reqwest. Some of them only tell by their text, which the integration tests named
//! below guard.

use crate::config::error::AppError;
use crate::dto::error::ErrorCode;
use crate::dto::mcp::McpServerStatus;
use crate::repository::mcp::Connection;
use crate::util::ip::is_not_public;
use chrono::Utc;
use reqwest::StatusCode;
use rmcp::service::{ClientInitializeError, ServiceError};
use rmcp::transport::auth::AuthError;
use rmcp::transport::streamable_http_client::{
    AuthRequiredError, InsufficientScopeError, StreamableHttpError,
};
use std::error::Error;
use uuid::Uuid;

/// Why connecting to a server failed.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub(crate) enum ConnectError {
    /// The server asks for authentication, or rejected the token or the OAuth credentials
    /// (HTTP 401).
    #[error("The server requires authentication")]
    AuthorizationRequired {
        /// The server's `WWW-Authenticate` header, which may point to its OAuth metadata.
        challenge: Option<String>,
    },
    /// The server refused the request (HTTP 403), such as for a permission or an OAuth scope
    /// the credentials lack, or a firewall in front of it. Unlike
    /// [`Self::AuthorizationRequired`], the credentials may still be valid.
    #[error("The server refused the request")]
    Forbidden {
        /// The server's `WWW-Authenticate` header, if it sent one.
        challenge: Option<String>,
    },
    /// For the user, without internals.
    #[error("{0}")]
    Failed(String),
}

impl ConnectError {
    pub(super) fn failed(message: &str) -> Self {
        Self::Failed(message.to_string())
    }

    pub(super) fn timed_out() -> Self {
        Self::failed("The server did not respond in time")
    }

    pub(super) fn not_public() -> Self {
        Self::failed("The server's address is not public")
    }

    fn not_mcp() -> Self {
        Self::failed("The server did not respond like an MCP server")
    }

    fn rejected(error: &AuthRequiredError) -> Self {
        Self::AuthorizationRequired {
            challenge: Some(error.www_authenticate_header.clone()),
        }
    }

    fn refused(error: &InsufficientScopeError) -> Self {
        Self::Forbidden {
            challenge: Some(error.www_authenticate_header.clone()),
        }
    }

    /// Whether the server refused the request for an OAuth scope the credentials lack.
    pub(crate) fn insufficient_scope(&self) -> bool {
        matches!(self, Self::Forbidden { challenge: Some(challenge) }
            if challenge.contains("insufficient_scope"))
    }

    /// How the server is stored after the failure. A server that refused the connection or
    /// the list of tools is stored to sign in to again, like one that rejected the
    /// credentials: they most likely lack a permission.
    pub(crate) fn connection(&self) -> Connection<'_> {
        let (status, last_error) = match self {
            ConnectError::AuthorizationRequired { .. } | ConnectError::Forbidden { .. } => {
                (McpServerStatus::AuthorizationRequired, None)
            }
            ConnectError::Failed(message) => (McpServerStatus::Failed, Some(message.as_str())),
        };
        Connection {
            status,
            last_error,
            tools: None,
            checked_at: Utc::now(),
        }
    }
}

/// Why the initialize handshake failed.
pub(super) fn initialize_error(error: &ClientInitializeError, server_id: Uuid) -> ConnectError {
    match error {
        ClientInitializeError::TransportError { error, .. } => {
            transport_error(error.error.as_ref(), server_id)
        }
        ClientInitializeError::JsonRpcError(data) => ConnectError::Failed(format!(
            "The server refused the connection: {}",
            data.message
        )),
        ClientInitializeError::NoCompatibleProtocolVersion { .. } => {
            ConnectError::failed("The server supports none of the protocol versions of this client")
        }
        ClientInitializeError::ConnectionClosed(_) => {
            tracing::info!("MCP server {server_id} closed the connection: {error}");
            ConnectError::failed("The server closed the connection")
        }
        _ => {
            tracing::info!("Connecting to MCP server {server_id} failed: {error}");
            ConnectError::not_mcp()
        }
    }
}

/// Why a request to a connected server failed.
pub(crate) fn service_error(error: &ServiceError, server_id: Uuid) -> ConnectError {
    match error {
        ServiceError::McpError(data) => {
            ConnectError::Failed(format!("The server returned an error: {}", data.message))
        }
        ServiceError::TransportSend(error) => transport_error(error.error.as_ref(), server_id),
        ServiceError::TransportClosed => ConnectError::failed("The server closed the connection"),
        ServiceError::Timeout { .. } => ConnectError::timed_out(),
        _ => {
            tracing::info!("Request to MCP server {server_id} failed: {error}");
            ConnectError::not_mcp()
        }
    }
}

/// Whether the request failed with `error` because the connection was lost after it was sent,
/// so the server may have processed it.
pub(crate) fn maybe_processed(error: &ServiceError) -> bool {
    let error = match error {
        // The session ended, or the response stream closed before the response arrived.
        ServiceError::TransportClosed => return true,
        ServiceError::TransportSend(error) => error.error.as_ref(),
        _ => return false,
    };
    let lost = |e: &reqwest::Error| {
        !(e.is_connect() || e.is_status() || e.is_builder() || e.is_redirect())
    };
    let mut source: Option<&(dyn Error + 'static)> = Some(error);
    while let Some(e) = source {
        if let Some(e) = e.downcast_ref::<StreamableHttpError<reqwest::Error>>() {
            return match e {
                // For requests that were under way while rmcp opened a new session, and when
                // its worker is gone, which may have taken the request along.
                StreamableHttpError::SessionRecoveryTimeout
                | StreamableHttpError::TransportChannelClosed => true,
                StreamableHttpError::Client(e) => lost(e),
                _ => false,
            };
        }
        if let Some(e) = e.downcast_ref::<reqwest::Error>() {
            return lost(e);
        }
        source = e.source();
    }
    false
}

/// Finds out from the errors in the chain of `error` why a request failed.
fn transport_error(error: &(dyn Error + Send + Sync + 'static), server_id: Uuid) -> ConnectError {
    let mut source: Option<&(dyn Error + 'static)> = Some(error);
    while let Some(e) = source {
        if let Some(e) = e.downcast_ref::<AuthRequiredError>() {
            return ConnectError::rejected(e);
        }
        // rmcp reports every 403 with a `WWW-Authenticate` header this way, not only those for
        // an `insufficient_scope`.
        if let Some(e) = e.downcast_ref::<InsufficientScopeError>() {
            return ConnectError::refused(e);
        }
        if let Some(e) = e.downcast_ref::<StreamableHttpError<reqwest::Error>>() {
            match e {
                StreamableHttpError::AuthRequired(e) => return ConnectError::rejected(e),
                StreamableHttpError::InsufficientScope(e) => return ConnectError::refused(e),
                StreamableHttpError::HttpStatus(e) => {
                    return ConnectError::Failed(format!(
                        "The server responded with HTTP {}",
                        e.status
                    ));
                }
                // Not a source of the error, so the loop would not find it.
                StreamableHttpError::Client(e) => return request_error(e, server_id),
                // rmcp reports a 401 or 403 without a `WWW-Authenticate` header only as
                // `HTTP <status>: <body>`. Guarded by the integration tests
                // `takes_rejections_without_a_challenge_as_such` (401 and 403) and
                // `fails_only_the_calls_the_server_refuses` (403).
                StreamableHttpError::UnexpectedServerResponse(message)
                    if message.starts_with("HTTP 401 ") =>
                {
                    return ConnectError::AuthorizationRequired { challenge: None };
                }
                StreamableHttpError::UnexpectedServerResponse(message)
                    if message.starts_with("HTTP 403 ") =>
                {
                    return ConnectError::Forbidden { challenge: None };
                }
                StreamableHttpError::UnexpectedContentType(_)
                | StreamableHttpError::UnexpectedServerResponse(_)
                | StreamableHttpError::Deserialize(_)
                | StreamableHttpError::Sse(_) => {
                    tracing::info!("MCP server {server_id} sent an unexpected response: {e}");
                    return ConnectError::not_mcp();
                }
                _ => {}
            }
        }
        if let Some(e) = e.downcast_ref::<AuthError>() {
            return auth_error(e, server_id);
        }
        if let Some(e) = e.downcast_ref::<reqwest::Error>() {
            return request_error(e, server_id);
        }
        source = e.source();
    }
    tracing::info!("Request to MCP server {server_id} failed: {error}");
    ConnectError::Failed(format!("The request failed: {error}"))
}

pub(super) fn auth_error(error: &AuthError, server_id: Uuid) -> ConnectError {
    match error {
        AuthError::AuthorizationRequired | AuthError::TokenRefreshRejected(_) => {
            ConnectError::AuthorizationRequired { challenge: None }
        }
        // oauth2's message for an `invalid_client` response: the authorization server no
        // longer accepts the client, a new sign-in registers another one. Guarded by the
        // integration test `requires_a_sign_in_when_the_client_is_rejected`.
        AuthError::TokenRefreshFailed(message)
            if message.starts_with("Server returned error response: invalid_client") =>
        {
            ConnectError::AuthorizationRequired { challenge: None }
        }
        _ => {
            tracing::info!("Authorizing with MCP server {server_id} failed: {error}");
            ConnectError::Failed(format!("Authorizing failed: {error}"))
        }
    }
}

fn request_error(error: &reqwest::Error, server_id: Uuid) -> ConnectError {
    if is_not_public(error) {
        return ConnectError::not_public();
    }
    // From responses rmcp checked with `error_for_status`.
    if let Some(status) = error.status() {
        return match status {
            StatusCode::UNAUTHORIZED => ConnectError::AuthorizationRequired { challenge: None },
            StatusCode::FORBIDDEN => ConnectError::Forbidden { challenge: None },
            _ => ConnectError::Failed(format!(
                "The server responded with HTTP {}",
                status.as_u16()
            )),
        };
    }
    tracing::info!("Request to MCP server {server_id} failed: {error:?}");
    if error.is_timeout() {
        ConnectError::timed_out()
    } else if error.is_connect() {
        ConnectError::failed("Could not connect to the server")
    } else {
        ConnectError::failed("The request to the server failed")
    }
}

/// For the errors of creating and changing servers.
pub(crate) fn connect_app_error(error: ConnectError) -> AppError {
    match error {
        ConnectError::AuthorizationRequired { .. } => AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The server rejected the token".to_string(),
        ),
        // Most likely, the token lacks a permission.
        ConnectError::Forbidden { .. } => AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The server refused access with the token".to_string(),
        ),
        ConnectError::Failed(message) => {
            AppError::BadGateway(ErrorCode::RemoteUnreachable, message)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tells_rejected_credentials_from_refused_requests() {
        let error = |e: StreamableHttpError<reqwest::Error>| transport_error(&e, Uuid::now_v7());
        let unexpected = |message: &'static str| {
            error(StreamableHttpError::UnexpectedServerResponse(
                message.into(),
            ))
        };
        assert_eq!(
            unexpected("HTTP 401 Unauthorized: "),
            ConnectError::AuthorizationRequired { challenge: None }
        );
        assert_eq!(
            error(StreamableHttpError::AuthRequired(AuthRequiredError::new(
                "Bearer".to_string()
            ))),
            ConnectError::AuthorizationRequired {
                challenge: Some("Bearer".to_string())
            }
        );
        let forbidden = unexpected("HTTP 403 Forbidden: blocked");
        assert_eq!(forbidden, ConnectError::Forbidden { challenge: None });
        assert!(!forbidden.insufficient_scope());

        let challenge = r#"Bearer error="insufficient_scope", scope="write""#;
        let refused = error(StreamableHttpError::InsufficientScope(
            InsufficientScopeError::new(challenge.to_string(), Some("write".to_string())),
        ));
        assert_eq!(
            refused,
            ConnectError::Forbidden {
                challenge: Some(challenge.to_string())
            }
        );
        assert!(refused.insufficient_scope());
    }
}
