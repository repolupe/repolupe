use crate::dto::user::UserRole;
use chrono::{DateTime, Utc};
use uuid::Uuid;

/// A valid session of a user who can log in, joined with what the user may do.
#[derive(Debug, sqlx::FromRow)]
pub struct ActiveSession {
    pub id: Uuid,
    pub user_id: Uuid,
    pub role: UserRole,
    pub can_manage_repositories: bool,
    pub must_change_password: bool,
    pub last_used_at: DateTime<Utc>,
}
