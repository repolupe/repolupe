use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::user::UserRole;
use crate::service;
use axum::extract::State;
use axum::{extract::Request, middleware::Next, response::Response};
use axum_extra::TypedHeader;
use axum_extra::extract::CookieJar;
use axum_extra::headers::Authorization;
use axum_extra::headers::authorization::Bearer;
use uuid::Uuid;

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub(crate) struct AuthenticatedUser {
    pub session_id: Uuid,
    pub user_id: Uuid,
    pub role: UserRole,
    pub can_manage_repositories: bool,
}

/// Browsers send the token in the session cookie, mobile clients as `Authorization: Bearer`.
pub(crate) fn extract_token<'a>(
    authorization: &'a Option<TypedHeader<Authorization<Bearer>>>,
    cookies: &'a CookieJar,
) -> Option<&'a str> {
    match authorization {
        Some(authorization) => Some(authorization.token()),
        None => cookies
            .get(service::session::SESSION_COOKIE)
            .map(|cookie| cookie.value()),
    }
}

/// Whether a route lets in users who must change their password (`users.must_change_password`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PasswordChange {
    /// They are let in, for the routes they need to change it.
    Allowed,
    /// They are rejected with `PASSWORD_CHANGE_REQUIRED` until they changed it.
    Required,
}

async fn authenticate(
    state: &AppState,
    authorization: Option<TypedHeader<Authorization<Bearer>>>,
    cookies: &CookieJar,
    password_change: PasswordChange,
) -> Result<AuthenticatedUser, AppError> {
    let token = extract_token(&authorization, cookies).ok_or(AppError::Unauthorized)?;

    let session =
        service::session::authenticate(&state.db, state.session_idle_timeout, token).await?;
    if session.must_change_password && password_change == PasswordChange::Required {
        return Err(AppError::PasswordChangeRequired);
    }
    Ok(AuthenticatedUser {
        session_id: session.id,
        user_id: session.user_id,
        role: session.role,
        can_manage_repositories: session.can_manage_repositories,
    })
}

pub async fn session_auth(
    State(state): State<AppState>,
    authorization: Option<TypedHeader<Authorization<Bearer>>>,
    cookies: CookieJar,
    mut request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let user = authenticate(&state, authorization, &cookies, PasswordChange::Required).await?;

    request.extensions_mut().insert(user);

    Ok(next.run(request).await)
}

/// Like [`session_auth`], but also lets users in who must change their password, for the
/// routes they need to do so.
pub async fn session_auth_allow_password_change(
    State(state): State<AppState>,
    authorization: Option<TypedHeader<Authorization<Bearer>>>,
    cookies: CookieJar,
    mut request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let user = authenticate(&state, authorization, &cookies, PasswordChange::Allowed).await?;

    request.extensions_mut().insert(user);

    Ok(next.run(request).await)
}

pub async fn session_auth_admin(
    State(state): State<AppState>,
    authorization: Option<TypedHeader<Authorization<Bearer>>>,
    cookies: CookieJar,
    mut request: Request,
    next: Next,
) -> Result<Response, AppError> {
    let user = authenticate(&state, authorization, &cookies, PasswordChange::Required).await?;

    if user.role != UserRole::Admin {
        return Err(AppError::Forbidden("Admin access required".to_string()));
    }

    request.extensions_mut().insert(user);

    Ok(next.run(request).await)
}
