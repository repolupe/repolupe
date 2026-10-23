//! Repositories and the users they are shared with.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Eq, PartialEq, Debug, Hash, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RepositorySyncStatus {
    Pending,
    Syncing,
    Ready,
    Failed,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

#[derive(Serialize, Deserialize)]
pub struct RepositoryDto {
    pub id: Uuid,
    /// Only the owner manages the repository, others it is shared with can only read it.
    pub owner_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    /// `null` for a local repository, which only exists on the server: it is changed only by
    /// committing the changes the model proposes, and cannot be cloned or pushed to.
    pub remote: Option<RemoteSettingsDto>,
    /// Whether the model proposes commits to the owner (`change_file`), who reviews them, and to
    /// the users it is shared with who may commit.
    pub allow_commits: bool,
    /// Whether the viewer commits the changes proposed to them: commits are allowed, they own it
    /// or the owner lets them commit, and they may manage repositories.
    pub can_commit: bool,
    pub sync_status: RepositorySyncStatus,
    pub sync_started_at: Option<DateTime<Utc>>,
    pub head_commit_sha: Option<String>,
    pub last_synced_at: Option<DateTime<Utc>>,
    /// Bytes of the git objects of the branch (other branches and tags are not fetched),
    /// `null` until the first sync.
    pub git_size: Option<i64>,
    /// Bytes of the LFS objects in the head commit, `null` until the first sync.
    pub lfs_size: Option<i64>,
    pub last_error: Option<String>,
    /// `null` while no sync is scheduled, e.g. of a local repository after its last sync.
    pub next_sync_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// The remote a repository is synced from, see [`RepositoryDto::remote`].
#[derive(Serialize, Deserialize)]
pub struct RemoteSettingsDto {
    pub url: String,
    /// The branch that is synced.
    pub branch: String,
    pub poll_interval_seconds: i32,
    /// `null` for public remotes. The token itself is never returned, and the hint only to the
    /// owner.
    pub token: Option<RepositoryTokenDto>,
}

#[derive(Serialize, Deserialize)]
pub struct RepositoryTokenDto {
    pub hint: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct RepositoryUserDto {
    pub user_id: Uuid,
    pub user_name: String,
    pub email: Option<String>,
    /// Whether they commit the changes proposed to them, like the owner, if the repository
    /// allows commits.
    pub can_commit: bool,
    /// When the repository was shared with the user.
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct CreateRepositoryRequest {
    pub name: String,
    pub description: Option<String>,
    /// `null` (or missing) creates a local repository, which starts with an empty commit on its
    /// branch `main`.
    pub remote: Option<RemoteSettings>,
    /// Whether the model proposes commits to the owner, `false` if missing.
    #[serde(default)]
    pub allow_commits: bool,
}

/// The remote of a repository to create, see [`CreateRepositoryRequest::remote`].
#[derive(Serialize, Deserialize)]
pub struct RemoteSettings {
    pub url: String,
    pub branch: String,
    pub poll_interval_seconds: i32,
    pub token: Option<String>,
}

/// Replaces all fields.
#[derive(Serialize, Deserialize)]
pub struct UpdateRepositoryRequest {
    pub name: String,
    pub description: Option<String>,
    /// `null` (or missing) for a local repository, which stays local. A repository with a remote
    /// keeps one.
    pub remote: Option<RemoteSettingsChange>,
    /// Whether the model proposes commits to the owner, `false` if missing.
    #[serde(default)]
    pub allow_commits: bool,
}

/// The remote of a repository that has one, see [`UpdateRepositoryRequest::remote`]. The token
/// itself is never returned, so it is changed via `token`.
#[derive(Serialize, Deserialize)]
pub struct RemoteSettingsChange {
    pub url: String,
    pub branch: String,
    pub poll_interval_seconds: i32,
    pub token: TokenChange,
}

/// `KEEP` is not accepted when the `url` moves to another host,
/// since the stored token was only checked against the current one.
#[derive(Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TokenChange {
    Keep,
    /// The remote is public.
    Remove,
    Set {
        value: String,
    },
}

#[derive(Serialize, Deserialize)]
pub struct AddRepositoryUserRequest {
    pub user_name_or_email: String,
}

#[derive(Serialize, Deserialize)]
pub struct UpdateRepositoryUserRequest {
    pub can_commit: bool,
}
