//! Errors as the API renders them.

use serde::{Deserialize, Serialize};

/// Stable, machine-readable error codes. Clients branch on these, never on the message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    InternalError,
    ValidationError,
    UnsupportedMediaType,
    Unauthorized,
    Forbidden,
    NotFound,
    Conflict,
    RateLimited,
    UserNameTaken,
    EmailTaken,
    NameTaken,
    RepoNotFound,
    BranchNotFound,
    AuthFailed,
    TokenRequired,
    RemoteUnreachable,
    UnknownRepository,
    UnknownUser,
    GenerationInProgress,
    NotRetryable,
    WrongPassword,
    SamePassword,
    PasswordChangeRequired,
    UnknownModel,
    NoModelConfigured,
    Unavailable,
    FileUnavailable,
    UnknownAttachment,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// The body of every error response.
#[derive(Serialize, Deserialize)]
pub struct ErrorDto {
    pub code: ErrorCode,
    /// For people. Internal errors get a generic one.
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unknown_codes_parse() {
        let error: ErrorDto =
            serde_json::from_str(r#"{"code":"NEWER_CODE","message":"m"}"#).unwrap();
        assert_eq!(error.code, ErrorCode::Unknown);
        let error: ErrorDto =
            serde_json::from_str(r#"{"code":"NOT_FOUND","message":"m"}"#).unwrap();
        assert_eq!(error.code, ErrorCode::NotFound);
    }
}
