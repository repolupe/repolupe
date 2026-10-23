use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::user::UserRole;
use crate::model::session::ActiveSession;
use chrono::{DateTime, Utc};
use uuid::Uuid;

pub(crate) async fn create_session(
    db: &DatabasePool,
    user_id: Uuid,
    token_hash: &str,
    user_agent: Option<&str>,
    now: DateTime<Utc>,
    expires_at: DateTime<Utc>,
) -> Result<Uuid, AppError> {
    let id = Uuid::now_v7();
    sqlx::query!(
        r#"INSERT INTO sessions (id, user_id, token_hash, user_agent, created_at, last_used_at, expires_at)
           VALUES ($1, $2, $3, $4, $5, $5, $6)"#,
        id,
        user_id,
        token_hash,
        user_agent,
        now,
        expires_at,
    )
    .execute(db)
    .await?;
    Ok(id)
}

/// Returns the session for `token_hash` if it has not expired and its user can log in.
pub(crate) async fn get_active_session(
    db: &DatabasePool,
    token_hash: &str,
    now: DateTime<Utc>,
) -> Result<Option<ActiveSession>, AppError> {
    let session = sqlx::query_as!(
        ActiveSession,
        r#"SELECT s.id AS "id: Uuid", s.user_id AS "user_id: Uuid", u.role AS "role: UserRole", u.can_manage_repositories,
                  u.must_change_password, s.last_used_at AS "last_used_at: DateTime<Utc>"
           FROM sessions s
           JOIN users u ON u.id = s.user_id
           WHERE s.token_hash = $1 AND s.expires_at > $2 AND u.can_login"#,
        token_hash,
        now,
    )
    .fetch_optional(db)
    .await?;
    Ok(session)
}

pub(crate) async fn touch_session(
    db: &DatabasePool,
    session_id: Uuid,
    now: DateTime<Utc>,
    expires_at: DateTime<Utc>,
) -> Result<(), AppError> {
    sqlx::query!(
        "UPDATE sessions SET last_used_at = $2, expires_at = $3 WHERE id = $1",
        session_id,
        now,
        expires_at,
    )
    .execute(db)
    .await?;
    Ok(())
}

pub(crate) async fn delete_session_by_token_hash(
    db: &DatabasePool,
    token_hash: &str,
) -> Result<(), AppError> {
    sqlx::query!("DELETE FROM sessions WHERE token_hash = $1", token_hash)
        .execute(db)
        .await?;
    Ok(())
}

/// Returns the number of deleted sessions.
pub(crate) async fn delete_expired_sessions(
    db: &DatabasePool,
    now: DateTime<Utc>,
) -> Result<u64, AppError> {
    let result = sqlx::query!("DELETE FROM sessions WHERE expires_at <= $1", now)
        .execute(db)
        .await?;
    Ok(result.rows_affected())
}
