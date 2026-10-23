//! Users, their profiles and their administration.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Eq, PartialEq, Debug, Hash, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum UserRole {
    User,
    Admin,
}

#[derive(Serialize, Deserialize)]
pub struct UserDto {
    pub id: Uuid,
    pub role: UserRole,
    pub user_name: String,
    pub email: Option<String>,
    /// `false` rejects logins. Always `true` for admins.
    pub can_login: bool,
    /// `false` only lets the user read repositories shared with them. Always `true` for admins.
    pub can_manage_repositories: bool,
    /// `false` keeps the user from changing their own user name and email. Always `true` for
    /// admins.
    pub can_change_identity: bool,
    /// Set by an admin: every request but `GET /me` and changing the password fails with
    /// `PASSWORD_CHANGE_REQUIRED` until the user changes it.
    pub must_change_password: bool,
    /// `null` uses the default model.
    pub default_model_id: Option<Uuid>,
    /// BCP 47 language tag such as `de-DE`, `null` uses the browser's language (`Accept-Language`).
    pub locale: Option<String>,
    /// Commits the changes the model proposes once its answer is complete, instead of leaving
    /// them to the user.
    pub auto_commit: bool,
    /// As it appears in documents, tells the LLM who "I" is in questions.
    pub full_name: Option<String>,
    pub first_name: Option<String>,
    /// What the user tells the LLM about themselves.
    pub about: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct RegisterRequest {
    pub user_name: String,
    /// `null` or an empty string registers the user without one.
    pub email: Option<String>,
    pub password: String,
    /// The user must change the password after logging in.
    #[serde(default)]
    pub must_change_password: bool,
}

#[derive(Serialize, Deserialize)]
pub struct UpdateUserRequest {
    pub user_name: String,
    /// `null` or an empty string removes it.
    pub email: Option<String>,
    pub can_login: bool,
    pub can_manage_repositories: bool,
    pub can_change_identity: bool,
    /// The user can do nothing but change their password until they do.
    pub must_change_password: bool,
}

#[derive(Serialize, Deserialize)]
pub struct ResetPasswordRequest {
    pub password: String,
    /// The user must change the password after logging in.
    pub must_change_password: bool,
}

#[derive(Serialize, Deserialize)]
pub struct DeleteUserRequest {
    pub user_id: Uuid,
}

#[derive(Serialize, Deserialize)]
pub struct UpdateIdentityRequest {
    pub user_name: String,
    /// `null` or an empty string removes it.
    pub email: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct UpdateProfileRequest {
    pub full_name: Option<String>,
    pub first_name: Option<String>,
    pub about: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct SetLocaleRequest {
    /// BCP 47 language tag such as `de-DE`, `null` uses the browser's language (`Accept-Language`).
    pub locale: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct SetAutoCommitRequest {
    pub auto_commit: bool,
}

#[derive(Serialize, Deserialize)]
pub struct SetMyDefaultModelRequest {
    /// `null` uses the default model.
    pub model_id: Option<Uuid>,
}

#[derive(Serialize, Deserialize)]
pub struct ChangePasswordRequest {
    pub current_password: String,
    pub new_password: String,
}
