use crate::dto::error::{ErrorCode, ErrorDto};
use crate::util::validation::ValidationError;
use axum::Json;
use axum::extract::rejection::{JsonRejection, PathRejection, QueryRejection};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("Internal server error: {0}")]
    InternalServerError(String),

    #[error("Invalid request: {0}")]
    BadRequest(String),

    #[error("Unsupported media type")]
    UnsupportedMediaType,

    #[error("Forbidden: {0}")]
    Forbidden(String),

    #[error("Conflict: {1}")]
    Conflict(ErrorCode, String),

    #[error("Unprocessable: {1}")]
    Unprocessable(ErrorCode, String),

    #[error("Too many requests: {0}")]
    TooManyRequests(String),

    #[error("Bad gateway: {1}")]
    BadGateway(ErrorCode, String),

    #[error("Unavailable: {0}")]
    Unavailable(String),

    #[error("Not found")]
    NotFound,

    #[error("Unauthorized")]
    Unauthorized,

    #[error("Password change required")]
    PasswordChangeRequired,
}

impl From<ValidationError> for AppError {
    fn from(err: ValidationError) -> Self {
        AppError::BadRequest(err.0)
    }
}

impl From<JsonRejection> for AppError {
    fn from(rejection: JsonRejection) -> Self {
        match rejection {
            JsonRejection::MissingJsonContentType(_) => AppError::UnsupportedMediaType,
            other => AppError::BadRequest(other.body_text()),
        }
    }
}

impl From<QueryRejection> for AppError {
    fn from(rejection: QueryRejection) -> Self {
        AppError::BadRequest(rejection.body_text())
    }
}

/// A malformed id cannot match any row, so it is treated like a missing one.
impl From<PathRejection> for AppError {
    fn from(_: PathRejection) -> Self {
        AppError::NotFound
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            AppError::Database(e) => {
                tracing::error!("Database error: {e:?}");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    ErrorCode::InternalError,
                    "Internal server error".to_string(),
                )
            }
            AppError::InternalServerError(msg) => {
                tracing::error!("Internal server error: {msg}");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    ErrorCode::InternalError,
                    "Internal server error".to_string(),
                )
            }
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, ErrorCode::ValidationError, msg),
            AppError::UnsupportedMediaType => (
                StatusCode::UNSUPPORTED_MEDIA_TYPE,
                ErrorCode::UnsupportedMediaType,
                "Expected Content-Type: application/json".to_string(),
            ),
            AppError::Forbidden(msg) => (StatusCode::FORBIDDEN, ErrorCode::Forbidden, msg),
            AppError::Conflict(code, msg) => (StatusCode::CONFLICT, code, msg),
            AppError::Unprocessable(code, msg) => (StatusCode::UNPROCESSABLE_ENTITY, code, msg),
            AppError::TooManyRequests(msg) => {
                (StatusCode::TOO_MANY_REQUESTS, ErrorCode::RateLimited, msg)
            }
            AppError::BadGateway(code, msg) => (StatusCode::BAD_GATEWAY, code, msg),
            AppError::Unavailable(msg) => {
                (StatusCode::SERVICE_UNAVAILABLE, ErrorCode::Unavailable, msg)
            }
            AppError::NotFound => (
                StatusCode::NOT_FOUND,
                ErrorCode::NotFound,
                "Not found".to_string(),
            ),
            AppError::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                ErrorCode::Unauthorized,
                "Unauthorized".to_string(),
            ),
            AppError::PasswordChangeRequired => (
                StatusCode::FORBIDDEN,
                ErrorCode::PasswordChangeRequired,
                "You must change your password first".to_string(),
            ),
        };
        (status, Json(ErrorDto { code, message })).into_response()
    }
}
