use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::model::session::ActiveSession;
use crate::repository;
use axum_extra::extract::cookie::{Cookie, SameSite};
use chrono::{DateTime, NaiveDate, TimeDelta, Utc};
use sha2::{Digest, Sha256};
use std::time::Duration;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

pub const SESSION_COOKIE: &str = "session";

/// The cookie is not refreshed on use, so it outlives any realistic session
/// and the server-side expiry stays authoritative. Browsers cap it at 400 days.
const COOKIE_MAX_AGE: TimeDelta = TimeDelta::days(400);

/// `last_used_at` / `expires_at` are only written if the last bump is older than this.
const TOUCH_INTERVAL: TimeDelta = TimeDelta::minutes(5);

const CLEANUP_INTERVAL: Duration = Duration::from_mins(60);

const MAX_USER_AGENT_LENGTH: usize = 512;

/// Creates a session that expires after `idle_timeout` without use (`None`: never) and returns
/// its token. Only the token's hash is stored.
pub async fn create_session(
    db: &DatabasePool,
    idle_timeout: Option<TimeDelta>,
    user_id: Uuid,
    user_agent: Option<&str>,
) -> Result<String, AppError> {
    let token = generate_token();
    let now = Utc::now();
    let user_agent = user_agent.map(|ua| truncate(ua, MAX_USER_AGENT_LENGTH));

    repository::session::create_session(
        db,
        user_id,
        &hash_token(&token),
        user_agent,
        now,
        expires_at(now, idle_timeout),
    )
    .await?;

    Ok(token)
}

/// Resolves a token to its session and slides the idle timeout forward. Without one, sessions
/// created with one stop expiring.
pub async fn authenticate(
    db: &DatabasePool,
    idle_timeout: Option<TimeDelta>,
    token: &str,
) -> Result<ActiveSession, AppError> {
    let now = Utc::now();
    let session = repository::session::get_active_session(db, &hash_token(token), now)
        .await?
        .ok_or(AppError::Unauthorized)?;

    if now - session.last_used_at >= TOUCH_INTERVAL {
        let expires_at = expires_at(now, idle_timeout);
        repository::session::touch_session(db, session.id, now, expires_at).await?;
    }

    Ok(session)
}

/// Deletes the session for `token`, if any.
pub async fn delete_session(db: &DatabasePool, token: &str) -> Result<(), AppError> {
    repository::session::delete_session_by_token_hash(db, &hash_token(token)).await
}

/// Periodically removes expired sessions from the database until `shutdown` is cancelled.
pub(crate) fn spawn_cleanup_task(db: DatabasePool, shutdown: CancellationToken) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(CLEANUP_INTERVAL);
        loop {
            tokio::select! {
                _ = interval.tick() => {}
                _ = shutdown.cancelled() => break,
            }
            match repository::session::delete_expired_sessions(&db, Utc::now()).await {
                Ok(0) => {}
                Ok(count) => tracing::info!("Deleted {count} expired sessions"),
                Err(e) => tracing::error!("Failed to delete expired sessions: {e}"),
            }
        }
    })
}

/// When a session used `now` expires.
fn expires_at(now: DateTime<Utc>, idle_timeout: Option<TimeDelta>) -> DateTime<Utc> {
    idle_timeout.map_or_else(never, |timeout| now + timeout)
}

/// The expiry of sessions without an idle timeout. `expires_at` stays `NOT NULL`, and
/// timestamps compare as text, so it is the last one with a four-digit year (a later one starts
/// with `+` and would sort before every other).
fn never() -> DateTime<Utc> {
    NaiveDate::from_ymd_opt(9999, 12, 31)
        .and_then(|date| date.and_hms_opt(23, 59, 59))
        .expect("valid date")
        .and_utc()
}

pub fn session_cookie(token: String) -> Cookie<'static> {
    Cookie::build((SESSION_COOKIE, token))
        .path("/")
        .http_only(true)
        .secure(true)
        .same_site(SameSite::Lax)
        .max_age(COOKIE_MAX_AGE.to_std().unwrap().try_into().unwrap())
        .build()
}

pub fn removal_cookie() -> Cookie<'static> {
    Cookie::build(SESSION_COOKIE).path("/").build()
}

fn generate_token() -> String {
    hex::encode(rand::random::<[u8; 32]>())
}

fn hash_token(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

fn truncate(s: &str, max_chars: usize) -> &str {
    match s.char_indices().nth(max_chars) {
        Some((idx, _)) => &s[..idx],
        None => s,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_are_unique_and_hashed() {
        let a = generate_token();
        let b = generate_token();
        assert_eq!(a.len(), 64);
        assert_ne!(a, b);
        assert_eq!(hash_token(&a), hash_token(&a));
        assert_ne!(hash_token(&a), a);
    }

    #[test]
    fn sessions_without_idle_timeout_never_expire() {
        let now = Utc::now();
        assert_eq!(
            expires_at(now, Some(TimeDelta::days(30))),
            now + TimeDelta::days(30)
        );
        assert_eq!(
            expires_at(now, None).to_rfc3339(),
            "9999-12-31T23:59:59+00:00"
        );
    }

    #[test]
    fn truncates_on_char_boundary() {
        assert_eq!(truncate("abc", 5), "abc");
        assert_eq!(truncate("äöü", 2), "äö");
    }
}
