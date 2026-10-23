use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::controller::auth;
use crate::controller::llm::unknown_model;
use crate::dto::error::ErrorCode;
use crate::dto::user::UserRole;
use crate::dto::user::{
    ChangePasswordRequest, DeleteUserRequest, RegisterRequest, ResetPasswordRequest,
    SetAutoCommitRequest, SetLocaleRequest, SetMyDefaultModelRequest, UpdateIdentityRequest,
    UpdateProfileRequest, UpdateUserRequest, UserDto,
};
use crate::middleware::auth::AuthenticatedUser;
use crate::util::extract::{JsonBody, PathParam};
use crate::{repository, util};
use axum::extract::State;
use axum::http::StatusCode;
use axum::{Extension, Json};
use uuid::Uuid;

pub(crate) async fn me(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
) -> Result<Json<UserDto>, AppError> {
    let user = repository::user::get_user(&state.db, auth.user_id)
        .await?
        .ok_or(AppError::Unauthorized)?;

    Ok(Json(user.into()))
}

/// Signs out every other session of the user, the current one stays valid. Ends a change an
/// admin required, so the new password must differ from the current one.
pub(crate) async fn change_password(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<ChangePasswordRequest>,
) -> Result<StatusCode, AppError> {
    util::validation::validate_password(&payload.new_password)?;

    let user = repository::user::get_user(&state.db, auth.user_id)
        .await?
        .ok_or(AppError::Unauthorized)?;

    // Someone with a stolen session must not be able to guess the password either.
    auth::count_password_attempt(&state, &user.user_name)?;
    if !util::password::verify_password(&payload.current_password, &user.password_hash).await? {
        return Err(AppError::Unprocessable(
            ErrorCode::WrongPassword,
            "Current password is incorrect".to_string(),
        ));
    }
    auth::reset_password_attempts(&state, &user.user_name);
    // The current password was just verified, so comparing them is enough.
    if payload.new_password == payload.current_password {
        return Err(AppError::Unprocessable(
            ErrorCode::SamePassword,
            "The new password must differ from the current one".to_string(),
        ));
    }

    let password_hash = util::password::hash_password(&payload.new_password).await?;
    repository::user::update_password(&state.db, auth.user_id, &password_hash, auth.session_id)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// Sets the model that answers the user's questions, `null` uses the default model.
pub(crate) async fn set_default_model(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<SetMyDefaultModelRequest>,
) -> Result<StatusCode, AppError> {
    let updated = repository::user::set_default_model(&state.db, auth.user_id, payload.model_id)
        .await
        .map_err(|e| match e {
            AppError::Database(sqlx::Error::Database(db_err))
                if db_err.is_foreign_key_violation() =>
            {
                unknown_model()
            }
            e => e,
        })?;
    if !updated {
        return Err(AppError::Unauthorized);
    }
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn set_locale(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<SetLocaleRequest>,
) -> Result<StatusCode, AppError> {
    let locale = payload.locale.as_deref().map(str::trim);
    if let Some(locale) = locale {
        util::validation::validate_locale(locale)?;
    }
    if !repository::user::set_locale(&state.db, auth.user_id, locale).await? {
        return Err(AppError::Unauthorized);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Sets whether the changes the model proposes are committed once its answer is complete.
pub(crate) async fn set_auto_commit(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<SetAutoCommitRequest>,
) -> Result<StatusCode, AppError> {
    if !repository::user::set_auto_commit(&state.db, auth.user_id, payload.auto_commit).await? {
        return Err(AppError::Unauthorized);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Replaces all fields of the profile, which the LLM is told about the user. `null` or an
/// empty string clears a field.
pub(crate) async fn update_profile(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<UpdateProfileRequest>,
) -> Result<StatusCode, AppError> {
    let full_name = non_empty(payload.full_name.as_deref());
    let first_name = non_empty(payload.first_name.as_deref());
    let about = non_empty(payload.about.as_deref());
    if let Some(full_name) = full_name {
        util::validation::validate_full_name(full_name)?;
    }
    if let Some(first_name) = first_name {
        util::validation::validate_first_name(first_name)?;
    }
    if let Some(about) = about {
        util::validation::validate_about(about)?;
    }

    if !repository::user::update_profile(&state.db, auth.user_id, full_name, first_name, about)
        .await?
    {
        return Err(AppError::Unauthorized);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Sets the user's own user name and email, unless an admin took that right away. The
/// sessions stay valid.
pub(crate) async fn update_identity(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<UpdateIdentityRequest>,
) -> Result<Json<UserDto>, AppError> {
    let user_name = payload.user_name.trim();
    util::validation::validate_user_name(user_name)?;
    let email = non_empty(payload.email.as_deref());
    if let Some(email) = email {
        util::validation::validate_email(email)?;
    }

    repository::user::update_identity(&state.db, auth.user_id, user_name, email)
        .await?
        .map(|user| Json(user.into()))
        .ok_or_else(|| {
            AppError::Forbidden(
                "You are not allowed to change your user name and email".to_string(),
            )
        })
}

/// Trimmed, with an empty string as `None`.
fn non_empty(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|v| !v.is_empty())
}

pub(crate) async fn list_users(
    State(state): State<AppState>,
) -> Result<Json<Vec<UserDto>>, AppError> {
    let users = repository::user::list_users(&state.db).await?;
    Ok(Json(users.into_iter().map(Into::into).collect()))
}

pub(crate) async fn register(
    State(state): State<AppState>,
    JsonBody(payload): JsonBody<RegisterRequest>,
) -> Result<Json<UserDto>, AppError> {
    let user_name = payload.user_name.trim();
    util::validation::validate_user_name(user_name)?;
    let email = non_empty(payload.email.as_deref());
    if let Some(email) = email {
        util::validation::validate_email(email)?;
    }
    util::validation::validate_password(&payload.password)?;

    let password_hash = util::password::hash_password(&payload.password).await?;

    let user = repository::user::create_user(
        &state.db,
        UserRole::User,
        user_name,
        email,
        &password_hash,
        payload.must_change_password,
    )
    .await?;

    Ok(Json(user.into()))
}

/// Sets the user name, email, what a user may do and whether they must change their password.
/// Disabling the login signs the user out everywhere. Admins can be renamed but not restricted.
pub(crate) async fn update_user(
    State(state): State<AppState>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<UpdateUserRequest>,
) -> Result<Json<UserDto>, AppError> {
    let user_name = payload.user_name.trim();
    util::validation::validate_user_name(user_name)?;
    let email = non_empty(payload.email.as_deref());
    if let Some(email) = email {
        util::validation::validate_email(email)?;
    }

    let updated = repository::user::update_user(
        &state.db,
        id,
        user_name,
        email,
        payload.can_login,
        payload.can_manage_repositories,
        payload.can_change_identity,
        payload.must_change_password,
    )
    .await?;
    if let Some(user) = updated {
        return Ok(Json(user.into()));
    }

    match repository::user::get_user(&state.db, id).await? {
        Some(_) => Err(AppError::Forbidden(
            "Admin users cannot be restricted".to_string(),
        )),
        None => Err(AppError::NotFound),
    }
}

/// Sets the password of another user, e.g. one who forgot theirs, and signs them out
/// everywhere. Admins change their own with the current password, like everyone else.
pub(crate) async fn reset_password(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<ResetPasswordRequest>,
) -> Result<Json<UserDto>, AppError> {
    if id == auth.user_id {
        return Err(AppError::BadRequest(
            "Change your own password with your current one".to_string(),
        ));
    }
    util::validation::validate_password(&payload.password)?;

    let password_hash = util::password::hash_password(&payload.password).await?;
    repository::user::reset_password(&state.db, id, &password_hash, payload.must_change_password)
        .await?
        .map(|user| Json(user.into()))
        .ok_or(AppError::NotFound)
}

pub(crate) async fn delete_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<DeleteUserRequest>,
) -> Result<(), AppError> {
    if payload.user_id == auth.user_id {
        return Err(AppError::BadRequest("Cannot delete yourself".to_string()));
    }

    let user = repository::user::get_user(&state.db, payload.user_id)
        .await?
        .ok_or(AppError::NotFound)?;

    if user.role == UserRole::Admin {
        return Err(AppError::Forbidden(
            "Admin users cannot be deleted".to_string(),
        ));
    }

    let deleted = repository::user::delete_user_if_not_admin(&state.db, payload.user_id).await?;
    if !deleted {
        return Err(AppError::NotFound);
    }

    Ok(())
}
