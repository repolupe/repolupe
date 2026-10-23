use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::auth::{LoginRequest, LoginResponse};
use crate::util::extract::JsonBody;
use crate::{middleware, repository, service, util};
use axum::Json;
use axum::extract::State;
use axum_extra::TypedHeader;
use axum_extra::extract::CookieJar;
use axum_extra::headers::authorization::Bearer;
use axum_extra::headers::{Authorization, UserAgent};

pub(crate) async fn login(
    State(state): State<AppState>,
    user_agent: Option<TypedHeader<UserAgent>>,
    cookies: CookieJar,
    JsonBody(payload): JsonBody<LoginRequest>,
) -> Result<(CookieJar, Json<LoginResponse>), AppError> {
    let login_failed = || AppError::Unauthorized;

    let login = payload.user_name_or_email.trim();
    // No user has an invalid user name or email. Rejecting them early also bounds the keys
    // of the attempt limiter.
    if util::validation::validate_user_name(login).is_err()
        && util::validation::validate_email(login).is_err()
    {
        return Err(login_failed());
    }

    let user = repository::user::get_user_by_login(&state.db, login).await?;
    // Counted by user name, so logging in by user name and by email share the limit, and for
    // unknown logins too, so the limit does not reveal which accounts exist.
    count_password_attempt(&state, user.as_ref().map_or(login, |u| &u.user_name))?;
    let user = user.ok_or_else(login_failed)?;

    if !util::password::verify_password(&payload.password, &user.password_hash).await? {
        return Err(login_failed());
    }
    reset_password_attempts(&state, &user.user_name);
    // Only told after the correct password, so it does not reveal which accounts exist.
    if !user.can_login {
        return Err(AppError::Forbidden("This account is disabled".to_string()));
    }

    let token = service::session::create_session(
        &state.db,
        state.session_idle_timeout,
        user.id,
        user_agent.as_ref().map(|ua| ua.as_str()),
    )
    .await?;

    Ok((
        cookies.add(service::session::session_cookie(token.clone())),
        Json(LoginResponse {
            token,
            user: user.into(),
        }),
    ))
}

/// Does not require a valid session, so that a stale HttpOnly cookie can always be cleared.
pub(crate) async fn logout(
    State(state): State<AppState>,
    authorization: Option<TypedHeader<Authorization<Bearer>>>,
    cookies: CookieJar,
) -> Result<CookieJar, AppError> {
    if let Some(token) = middleware::auth::extract_token(&authorization, &cookies) {
        service::session::delete_session(&state.db, token).await?;
    }
    Ok(cookies.remove(service::session::removal_cookie()))
}

/// Counts a password guess for the account `user_name`, see [`AppState::password_attempts`].
pub(crate) fn count_password_attempt(state: &AppState, user_name: &str) -> Result<(), AppError> {
    state
        .password_attempts
        .try_attempt(&user_name.to_lowercase())
        .map_err(|wait| {
            let minutes = wait.as_secs().div_ceil(60).max(1);
            let unit = if minutes == 1 { "minute" } else { "minutes" };
            AppError::TooManyRequests(format!(
                "Too many password attempts, try again in {minutes} {unit}"
            ))
        })
}

/// Forgets the password guesses for `user_name` after the correct password was given.
pub(crate) fn reset_password_attempts(state: &AppState, user_name: &str) {
    state.password_attempts.reset(&user_name.to_lowercase());
}
