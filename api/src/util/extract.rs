use crate::config::error::AppError;
use crate::middleware::auth::AuthenticatedUser;
use axum::extract::FromRequest;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;

/// The user the auth middleware of the route let in.
impl<S: Send + Sync> FromRequestParts<S> for AuthenticatedUser {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, _: &S) -> Result<Self, Self::Rejection> {
        parts
            .extensions
            .get::<AuthenticatedUser>()
            .cloned()
            .ok_or_else(|| {
                AppError::InternalServerError("Route is not behind an auth middleware".to_string())
            })
    }
}

/// `axum::Json` with rejections rendered as [`AppError`].
#[derive(FromRequest)]
#[from_request(via(axum::Json), rejection(AppError))]
pub(crate) struct JsonBody<T>(pub T);

/// `axum::extract::Path` with rejections rendered as [`AppError`].
#[derive(FromRequestParts)]
#[from_request(via(axum::extract::Path), rejection(AppError))]
pub(crate) struct PathParam<T>(pub T);

/// `axum::extract::Query` with rejections rendered as [`AppError`].
#[derive(FromRequestParts)]
#[from_request(via(axum::extract::Query), rejection(AppError))]
pub(crate) struct QueryParams<T>(pub T);
