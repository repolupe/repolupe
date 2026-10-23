use crate::dto::user::UserRole;
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct User {
    pub id: Uuid,
    pub role: UserRole,
    /// Unique ignoring case, see `validate_user_name`.
    pub user_name: String,
    /// Unique ignoring case.
    pub email: Option<String>,
    pub password_hash: String,
    /// `false` rejects logins and ends the sessions.
    pub can_login: bool,
    /// `false` only lets the user read repositories shared with them.
    pub can_manage_repositories: bool,
    /// `false` keeps the user from changing their own user name and email.
    pub can_change_identity: bool,
    /// Set by an admin: the user can do nothing but change their password until they do.
    pub must_change_password: bool,
    /// `None` uses the default model.
    pub default_model_id: Option<Uuid>,
    /// BCP 47 language tag, `None` uses the browser's language (`Accept-Language`).
    pub locale: Option<String>,
    /// Commits the changes the model proposes once its answer is complete, instead of leaving
    /// them to the user.
    pub auto_commit: bool,
    /// As it appears in documents, so the LLM knows who "I" is in questions.
    pub full_name: Option<String>,
    pub first_name: Option<String>,
    /// What the user tells the LLM about themselves.
    pub about: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// What the LLM is told about the user asking.
#[derive(Debug, Default)]
pub struct UserProfile {
    pub full_name: Option<String>,
    pub about: Option<String>,
    pub locale: Option<String>,
    /// The changes the model proposes are committed once its answer is complete.
    pub auto_commit: bool,
}
