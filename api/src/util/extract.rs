use crate::config::error::AppError;
use axum::extract::FromRequest;
use axum::extract::FromRequestParts;

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
