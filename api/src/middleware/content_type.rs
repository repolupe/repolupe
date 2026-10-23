use crate::config::error::AppError;
use axum::extract::Request;
use axum::http::{HeaderMap, Method, header};
use axum::middleware::Next;
use axum::response::Response;

/// Rejects POST requests that are not `application/json`, including those without a body, or
/// `application/octet-stream` for uploads. Browsers cannot send these content types cross-site
/// without a CORS preflight, so this also protects the cookie-authenticated routes against CSRF.
pub async fn require_json(request: Request, next: Next) -> Result<Response, AppError> {
    if request.method() == Method::POST && !is_json_or_bytes(request.headers()) {
        return Err(AppError::UnsupportedMediaType);
    }
    Ok(next.run(request).await)
}

fn is_json_or_bytes(headers: &HeaderMap) -> bool {
    headers
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(';').next())
        .is_some_and(|mime| {
            let mime = mime.trim();
            mime.eq_ignore_ascii_case("application/json")
                || mime.eq_ignore_ascii_case("application/octet-stream")
        })
}
