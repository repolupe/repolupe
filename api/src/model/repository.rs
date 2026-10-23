use crate::config::error::AppError;
use crate::dto::error::ErrorCode;
use crate::dto::repository::RepositorySyncStatus;
use crate::dto::user::UserRole;
use crate::util::token_cipher::TokenCipher;
use chrono::{DateTime, Utc};
use url::Url;
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct Repository {
    pub id: Uuid,
    /// The owner, who manages it. Others can only read it, and commit if the owner lets them,
    /// see [`RepositoryUser`].
    pub user_id: Uuid,
    pub name: String,
    pub description: Option<String>,
    /// `None` for a local repository, which only exists in its mirror: its syncs read the branch
    /// there, and commits move it there instead of pushing.
    pub remote_url: Option<String>,
    pub branch: String,
    /// `None` for a local repository, which is synced only when requested, e.g. after a commit.
    pub poll_interval_seconds: Option<i32>,
    pub token_encrypted: Option<Vec<u8>>,
    pub token_hint: Option<String>,
    /// Whether the model proposes commits to the owner, and to the users it is shared with who
    /// may commit, see `tools::CHANGE_FILE`.
    pub allow_commits: bool,
    /// Whether the user it was read for may commit the changes proposed to it, unless they may
    /// not manage repositories: commits are allowed, and they own it or it is shared with them
    /// with [`RepositoryUser::can_commit`].
    pub viewer_can_commit: bool,
    pub sync_status: RepositorySyncStatus,
    pub sync_started_at: Option<DateTime<Utc>>,
    pub head_commit_sha: Option<String>,
    pub last_synced_at: Option<DateTime<Utc>>,
    /// Bytes of the git objects of the branch, `None` until the first sync.
    pub git_size: Option<i64>,
    /// Bytes of the LFS objects the head commit refers to, `None` until the first sync.
    pub lfs_size: Option<i64>,
    pub last_error: Option<String>,
    /// `None` while no sync is scheduled, e.g. of a local repository after its last sync.
    pub next_sync_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Repository {
    /// The remote it is synced from, `None` for a local repository.
    pub fn remote(&self) -> Option<Remote<'_>> {
        Remote::of(
            self.id,
            self.remote_url.as_deref(),
            self.poll_interval_seconds,
            self.token_encrypted.as_deref(),
        )
    }
}

/// The remote of a repository that has one, see [`Repository::remote`].
#[derive(Debug)]
pub struct Remote<'a> {
    /// The repository, whose id the token is encrypted with.
    repository_id: Uuid,
    /// As stored, validated by `parse_remote_url` then, and never containing the token.
    pub url: &'a str,
    pub poll_interval_seconds: i32,
    /// `None` for a public remote.
    pub token_encrypted: Option<&'a [u8]>,
}

impl<'a> Remote<'a> {
    /// The remote of the repository `id` from its columns: `None` if it is local, i.e. has no
    /// URL, and so no poll interval either, which the table checks.
    fn of(
        id: Uuid,
        url: Option<&'a str>,
        poll_interval_seconds: Option<i32>,
        token_encrypted: Option<&'a [u8]>,
    ) -> Option<Self> {
        Some(Remote {
            repository_id: id,
            url: url?,
            poll_interval_seconds: poll_interval_seconds?,
            token_encrypted,
        })
    }

    /// The URL to contact, parsed.
    pub fn parsed_url(&self) -> Result<Url, AppError> {
        Url::parse(self.url).map_err(|e| {
            AppError::InternalServerError(format!(
                "Stored remote URL of {} is invalid: {e}",
                self.repository_id
            ))
        })
    }

    /// The token to send, decrypted with `cipher`, `None` for a public remote.
    pub fn token(&self, cipher: &TokenCipher) -> Result<Option<String>, AppError> {
        let Some(ciphertext) = self.token_encrypted else {
            return Ok(None);
        };
        cipher
            .decrypt(self.repository_id, ciphertext)
            .map(Some)
            .map_err(|_| {
                AppError::Unprocessable(
                    ErrorCode::AuthFailed,
                    "The stored token could not be decrypted, please set it again".to_string(),
                )
            })
    }
}

/// Identifies a repository of any user to an admin.
#[derive(Debug)]
pub struct RepositoryLabel {
    pub id: Uuid,
    pub name: String,
    pub owner_name: String,
    /// Whether the viewer owns the repository or it is shared with them.
    pub readable: bool,
}

/// A user a repository is shared with.
#[derive(Debug)]
pub struct RepositoryUser {
    pub user_id: Uuid,
    pub user_name: String,
    pub email: Option<String>,
    /// Whether they commit the changes proposed to them, like the owner, if the repository
    /// allows commits.
    pub can_commit: bool,
    pub created_at: DateTime<Utc>,
}

/// What a sync needs of a repository it claimed.
#[derive(Debug)]
pub struct SyncJob {
    pub id: Uuid,
    /// `None` for a local repository, see [`Repository::remote_url`].
    pub remote_url: Option<String>,
    pub branch: String,
    pub poll_interval_seconds: Option<i32>,
    pub token_encrypted: Option<Vec<u8>>,
    pub head_commit_sha: Option<String>,
    /// Decides the [`RemoteAccess`](crate::model::remote_access::RemoteAccess) of the sync.
    pub owner_role: UserRole,
}

impl SyncJob {
    /// The remote to fetch from, `None` for a local repository.
    pub fn remote(&self) -> Option<Remote<'_>> {
        Remote::of(
            self.id,
            self.remote_url.as_deref(),
            self.poll_interval_seconds,
            self.token_encrypted.as_deref(),
        )
    }
}

/// A repository in the scope of a chat, as the model sees it.
#[derive(Debug)]
pub struct ScopedRepository {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub branch: String,
    /// `None` until the first sync finished.
    pub head_commit_sha: Option<String>,
    /// Whether the model may propose commits to the user of the chat: commits are allowed on
    /// it, they own it or it is shared with them with `can_commit`, and they may manage
    /// repositories.
    pub can_commit: bool,
}
