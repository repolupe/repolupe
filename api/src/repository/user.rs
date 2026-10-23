use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::dto::user::UserRole;
use crate::model::user::{User, UserProfile};
use crate::repository::{begin_write, violates_unique};
use chrono::{DateTime, Utc};
use uuid::Uuid;

pub(crate) async fn count_users(db: &DatabasePool) -> Result<i64, AppError> {
    let count = sqlx::query_scalar!(r#"SELECT count(*) AS "count!" FROM users"#)
        .fetch_one(db)
        .await?;
    Ok(count)
}

pub(crate) async fn create_user(
    db: &DatabasePool,
    role: UserRole,
    user_name: &str,
    email: Option<&str>,
    password_hash: &str,
    must_change_password: bool,
) -> Result<User, AppError> {
    let id = Uuid::now_v7();
    let now = Utc::now();
    let user = sqlx::query_as!(
        User,
        r#"INSERT INTO users (id, role, user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, auto_commit, created_at)
           VALUES ($1, $2, $3, $4, $5, true, true, true, $6, false, $7)
           RETURNING id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>""#,
        id,
        role,
        user_name,
        email,
        password_hash,
        must_change_password,
        now,
    )
    .fetch_one(db)
    .await
    .map_err(unique_violation)?;

    Ok(user)
}

/// Maps a taken user name or email to its `Conflict`.
fn unique_violation(e: sqlx::Error) -> AppError {
    if violates_unique(&e, "index 'idx_users_user_name'") {
        AppError::Conflict(
            ErrorCode::UserNameTaken,
            "User name already taken".to_string(),
        )
    } else if violates_unique(&e, "index 'idx_users_email'") {
        AppError::Conflict(
            ErrorCode::EmailTaken,
            "Email already registered".to_string(),
        )
    } else {
        AppError::Database(e)
    }
}

pub(crate) async fn get_user(db: &DatabasePool, user_id: Uuid) -> Result<Option<User>, AppError> {
    let user = sqlx::query_as!(
        User,
        r#"SELECT id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>"
           FROM users WHERE id = $1"#,
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(user)
}

/// The user whose user name or email is `login`, ignoring case. User names contain no `@`,
/// so at most one user matches.
pub(crate) async fn get_user_by_login(
    db: &DatabasePool,
    login: &str,
) -> Result<Option<User>, AppError> {
    let user = sqlx::query_as!(
        User,
        r#"SELECT id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>"
           FROM users WHERE lower(user_name) = lower($1) OR lower(email) = lower($1)"#,
        login,
    )
    .fetch_optional(db)
    .await?;
    Ok(user)
}

pub(crate) async fn list_users(db: &DatabasePool) -> Result<Vec<User>, AppError> {
    let users = sqlx::query_as!(
        User,
        r#"SELECT id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>"
           FROM users
           ORDER BY created_at, id"#,
    )
    .fetch_all(db)
    .await?;
    Ok(users)
}

/// Sets the password the user chose, which ends a required change, and deletes every session
/// of the user except `keep_session_id`.
pub(crate) async fn update_password(
    db: &DatabasePool,
    user_id: Uuid,
    password_hash: &str,
    keep_session_id: Uuid,
) -> Result<(), AppError> {
    let mut tx = begin_write(db).await?;
    let result = sqlx::query!(
        "UPDATE users SET password_hash = $2, must_change_password = false WHERE id = $1",
        user_id,
        password_hash,
    )
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::Unauthorized);
    }
    sqlx::query!(
        "DELETE FROM sessions WHERE user_id = $1 AND id <> $2",
        user_id,
        keep_session_id,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

/// Sets the password an admin chose and whether the user must change it, and signs the user
/// out everywhere. Returns `None` if there is no such user.
pub(crate) async fn reset_password(
    db: &DatabasePool,
    user_id: Uuid,
    password_hash: &str,
    must_change_password: bool,
) -> Result<Option<User>, AppError> {
    let mut tx = begin_write(db).await?;
    let user = sqlx::query_as!(
        User,
        r#"UPDATE users SET password_hash = $2, must_change_password = $3
           WHERE id = $1
           RETURNING id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>""#,
        user_id,
        password_hash,
        must_change_password,
    )
    .fetch_optional(&mut *tx)
    .await?;
    if user.is_some() {
        sqlx::query!("DELETE FROM sessions WHERE user_id = $1", user_id)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(user)
}

/// Sets the model the user's answers are generated with, `None` uses the default model.
/// Returns `false` if the user does not exist.
pub(crate) async fn set_default_model(
    db: &DatabasePool,
    user_id: Uuid,
    model_id: Option<Uuid>,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "UPDATE users SET default_model_id = $2 WHERE id = $1",
        user_id,
        model_id,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Sets the user's locale, `None` uses the browser's language (`Accept-Language`).
/// Returns `false` if the user does not exist.
pub(crate) async fn set_locale(
    db: &DatabasePool,
    user_id: Uuid,
    locale: Option<&str>,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "UPDATE users SET locale = $2 WHERE id = $1",
        user_id,
        locale,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Sets whether the changes the model proposes are committed once its answer is complete.
/// Returns `false` if the user does not exist.
pub(crate) async fn set_auto_commit(
    db: &DatabasePool,
    user_id: Uuid,
    auto_commit: bool,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "UPDATE users SET auto_commit = $2 WHERE id = $1",
        user_id,
        auto_commit,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

pub(crate) async fn get_user_profile(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<Option<UserProfile>, AppError> {
    let profile = sqlx::query_as!(
        UserProfile,
        "SELECT full_name, about, locale, auto_commit FROM users WHERE id = $1",
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(profile)
}

/// Returns `false` if the user does not exist.
pub(crate) async fn update_profile(
    db: &DatabasePool,
    user_id: Uuid,
    full_name: Option<&str>,
    first_name: Option<&str>,
    about: Option<&str>,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "UPDATE users SET full_name = $2, first_name = $3, about = $4 WHERE id = $1",
        user_id,
        full_name,
        first_name,
        about,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Sets the user's own user name and email. Returns `None` if there is no such user, or if
/// they may not change them.
pub(crate) async fn update_identity(
    db: &DatabasePool,
    user_id: Uuid,
    user_name: &str,
    email: Option<&str>,
) -> Result<Option<User>, AppError> {
    let user = sqlx::query_as!(
        User,
        r#"UPDATE users SET user_name = $2, email = $3
           WHERE id = $1 AND can_change_identity
           RETURNING id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>""#,
        user_id,
        user_name,
        email,
    )
    .fetch_optional(db)
    .await
    .map_err(unique_violation)?;
    Ok(user)
}

/// Sets the user name, email, what the user may do and whether they must change their
/// password, and ends their sessions if they can no longer log in. Returns `None` if there is
/// no such user, or if it is an admin and would be restricted.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn update_user(
    db: &DatabasePool,
    user_id: Uuid,
    user_name: &str,
    email: Option<&str>,
    can_login: bool,
    can_manage_repositories: bool,
    can_change_identity: bool,
    must_change_password: bool,
) -> Result<Option<User>, AppError> {
    let mut tx = begin_write(db).await?;
    let user = sqlx::query_as!(
        User,
        r#"UPDATE users SET user_name = $2, email = $3, can_login = $4, can_manage_repositories = $5,
                            can_change_identity = $6, must_change_password = $7
           WHERE id = $1 AND (role != 'ADMIN' OR ($4 AND $5 AND $6))
           RETURNING id AS "id: Uuid", role AS "role: UserRole", user_name, email, password_hash, can_login, can_manage_repositories, can_change_identity, must_change_password, default_model_id AS "default_model_id: Uuid", locale, auto_commit, full_name, first_name, about, created_at AS "created_at: DateTime<Utc>""#,
        user_id,
        user_name,
        email,
        can_login,
        can_manage_repositories,
        can_change_identity,
        must_change_password,
    )
    .fetch_optional(&mut *tx)
    .await
    .map_err(unique_violation)?;
    if user.is_some() && !can_login {
        sqlx::query!("DELETE FROM sessions WHERE user_id = $1", user_id)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(user)
}

/// Deletes a user. Returns `false` if no user was deleted.
pub(crate) async fn delete_user_if_not_admin(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "DELETE FROM users WHERE id = $1 AND role != 'ADMIN'",
        user_id,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}
