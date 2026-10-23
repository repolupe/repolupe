use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::repository::RepositorySyncStatus;
use crate::dto::user::UserRole;
use crate::model::repository::{
    Repository, RepositoryLabel, RepositoryUser, ScopedRepository, SyncJob,
};
use crate::model::repository_document::RepositoryDocument;
use crate::repository::begin_write;
use chrono::{DateTime, Utc};
use sqlx::types::Json;
use uuid::Uuid;

/// The encrypted token as stored in the `token_*` columns.
pub(crate) struct StoredToken {
    pub encrypted: Vec<u8>,
    pub hint: Option<String>,
}

pub(crate) struct NewRepository<'a> {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: &'a str,
    pub description: Option<&'a str>,
    /// `None` for a local repository, see [`Repository::remote_url`].
    pub remote_url: Option<&'a str>,
    pub branch: &'a str,
    pub poll_interval_seconds: Option<i32>,
    pub token: Option<StoredToken>,
    pub allow_commits: bool,
}

pub(crate) struct RepositoryChanges<'a> {
    pub name: &'a str,
    pub description: Option<&'a str>,
    /// `None` for a local repository, see [`Repository::remote_url`].
    pub remote_url: Option<&'a str>,
    pub branch: &'a str,
    pub poll_interval_seconds: Option<i32>,
    /// `None` keeps the token, `Some(None)` clears it, `Some(Some(_))` replaces it.
    pub token: Option<Option<StoredToken>>,
    pub allow_commits: bool,
    /// Resets the sync state to `PENDING` and schedules an immediate sync.
    pub reset_sync: bool,
    /// Schedules an immediate sync if the last one failed.
    pub retry_failed_sync: bool,
}

/// The repositories the user owns or that are shared with them.
pub(crate) async fn list_repositories(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<Vec<Repository>, AppError> {
    let repositories = sqlx::query_as!(
        Repository,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, description, remote_url, branch, poll_interval_seconds,
                  token_encrypted, token_hint, allow_commits,
                  allow_commits AND (user_id = $1 OR EXISTS (SELECT 1
                                                             FROM repository_users ru
                                                             WHERE ru.repository_id = r.id AND ru.user_id = $1 AND ru.can_commit)) AS "viewer_can_commit!: bool",
                  sync_status AS "sync_status: RepositorySyncStatus", sync_started_at AS "sync_started_at: DateTime<Utc>",
                  head_commit_sha, last_synced_at AS "last_synced_at: DateTime<Utc>", git_size, lfs_size, last_error,
                  next_sync_at AS "next_sync_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>"
           FROM repositories r
           WHERE r.user_id = $1
              OR EXISTS (SELECT 1 FROM repository_users ru WHERE ru.repository_id = r.id AND ru.user_id = $1)
           ORDER BY created_at DESC, id DESC"#,
        user_id,
    )
    .fetch_all(db)
    .await?;
    Ok(repositories)
}

/// A repository the user owns or that is shared with them.
pub(crate) async fn get_repository(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<Option<Repository>, AppError> {
    let repository = sqlx::query_as!(
        Repository,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, description, remote_url, branch, poll_interval_seconds,
                  token_encrypted, token_hint, allow_commits,
                  allow_commits AND (user_id = $2 OR EXISTS (SELECT 1
                                                             FROM repository_users ru
                                                             WHERE ru.repository_id = r.id AND ru.user_id = $2 AND ru.can_commit)) AS "viewer_can_commit!: bool",
                  sync_status AS "sync_status: RepositorySyncStatus", sync_started_at AS "sync_started_at: DateTime<Utc>",
                  head_commit_sha, last_synced_at AS "last_synced_at: DateTime<Utc>", git_size, lfs_size, last_error,
                  next_sync_at AS "next_sync_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>"
           FROM repositories r
           WHERE r.id = $1
             AND (r.user_id = $2
                  OR EXISTS (SELECT 1 FROM repository_users ru WHERE ru.repository_id = r.id AND ru.user_id = $2))"#,
        id,
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(repository)
}

/// The repositories a chat can read from, by name. Empty if the chat does
/// not exist.
pub(crate) async fn list_scoped_repositories(
    db: &DatabasePool,
    chat_id: Uuid,
) -> Result<Vec<ScopedRepository>, AppError> {
    let repositories = sqlx::query_as!(
        ScopedRepository,
        r#"SELECT r.id AS "id: Uuid", r.name, r.description, r.branch, r.head_commit_sha,
                  r.allow_commits AND u.can_manage_repositories
                      AND (r.user_id = c.user_id
                           OR EXISTS (SELECT 1
                                      FROM repository_users ru
                                      WHERE ru.repository_id = r.id AND ru.user_id = c.user_id AND ru.can_commit)) AS "can_commit!: bool"
           FROM chats c
           JOIN users u ON u.id = c.user_id
           JOIN repositories r
                ON r.user_id = c.user_id
                    OR EXISTS (SELECT 1 FROM repository_users ru WHERE ru.repository_id = r.id AND ru.user_id = c.user_id)
           WHERE c.id = $1
             AND (c.all_repositories
                  OR EXISTS (SELECT 1
                             FROM chat_repositories cr
                             WHERE cr.chat_id = c.id AND cr.repository_id = r.id))
           ORDER BY lower(r.name), r.id"#,
        chat_id,
    )
    .fetch_all(db)
    .await?;
    Ok(repositories)
}

/// Inserts a `PENDING` repository that is due for its first sync immediately, which clones it,
/// or creates the mirror of a local one.
pub(crate) async fn create_repository(
    db: &DatabasePool,
    new: NewRepository<'_>,
) -> Result<Repository, AppError> {
    let (token_encrypted, token_hint) = split_token(new.token);
    let now = Utc::now();
    let repository = sqlx::query_as!(
        Repository,
        r#"INSERT INTO repositories (id, user_id, name, description, remote_url, branch, poll_interval_seconds,
                                     token_encrypted, token_hint, allow_commits,
                                     sync_status, next_sync_at, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'PENDING', $11, $11, $11)
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, description, remote_url, branch, poll_interval_seconds,
                     token_encrypted, token_hint, allow_commits, allow_commits AS "viewer_can_commit!: bool",
                     sync_status AS "sync_status: RepositorySyncStatus", sync_started_at AS "sync_started_at: DateTime<Utc>",
                     head_commit_sha, last_synced_at AS "last_synced_at: DateTime<Utc>", git_size, lfs_size, last_error,
                     next_sync_at AS "next_sync_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>""#,
        new.id,
        new.user_id,
        new.name,
        new.description,
        new.remote_url,
        new.branch,
        new.poll_interval_seconds,
        token_encrypted,
        token_hint,
        new.allow_commits,
        now,
    )
    .fetch_one(db)
    .await?;
    Ok(repository)
}

/// Applies `changes` if the user owns the repository and it still has `expected_remote_url`.
/// Returns `None` if no such repository exists or its URL changed in the meantime.
pub(crate) async fn update_repository(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
    expected_remote_url: Option<&str>,
    changes: RepositoryChanges<'_>,
) -> Result<Option<Repository>, AppError> {
    let replace_token = changes.token.is_some();
    let (token_encrypted, token_hint) = split_token(changes.token.flatten());
    let now = Utc::now();
    let repository = sqlx::query_as!(
        Repository,
        r#"UPDATE repositories
           SET name                  = $4,
               description           = $5,
               remote_url            = $6,
               branch                = $7,
               poll_interval_seconds = $8,
               token_encrypted       = CASE WHEN $9 THEN $10 ELSE token_encrypted END,
               token_hint            = CASE WHEN $9 THEN $11 ELSE token_hint END,
               allow_commits         = $15,
               sync_status           = CASE WHEN $12 THEN 'PENDING' ELSE sync_status END,
               sync_started_at       = CASE WHEN $12 THEN NULL ELSE sync_started_at END,
               head_commit_sha       = CASE WHEN $12 THEN NULL ELSE head_commit_sha END,
               last_synced_at        = CASE WHEN $12 THEN NULL ELSE last_synced_at END,
               git_size              = CASE WHEN $12 THEN NULL ELSE git_size END,
               lfs_size              = CASE WHEN $12 THEN NULL ELSE lfs_size END,
               last_error            = CASE WHEN $12 THEN NULL ELSE last_error END,
               next_sync_at          = CASE
                                           WHEN $12 THEN $14
                                           WHEN $13 AND sync_status = 'FAILED' THEN $14
                                           ELSE next_sync_at
                                       END,
               updated_at            = $14
           WHERE id = $1 AND user_id = $2 AND remote_url IS $3
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, description, remote_url, branch, poll_interval_seconds,
                     token_encrypted, token_hint, allow_commits, allow_commits AS "viewer_can_commit!: bool",
                     sync_status AS "sync_status: RepositorySyncStatus", sync_started_at AS "sync_started_at: DateTime<Utc>",
                     head_commit_sha, last_synced_at AS "last_synced_at: DateTime<Utc>", git_size, lfs_size, last_error,
                     next_sync_at AS "next_sync_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>", updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        user_id,
        expected_remote_url,
        changes.name,
        changes.description,
        changes.remote_url,
        changes.branch,
        changes.poll_interval_seconds,
        replace_token,
        token_encrypted,
        token_hint,
        changes.reset_sync,
        changes.retry_failed_sync,
        now,
        changes.allow_commits,
    )
    .fetch_optional(db)
    .await?;
    Ok(repository)
}

/// Returns `false` if the user owns no such repository.
pub(crate) async fn delete_repository(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "DELETE FROM repositories WHERE id = $1 AND user_id = $2",
        id,
        user_id,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Makes the repository due for sync now. Returns `false` if the user owns no such repository.
pub(crate) async fn request_sync(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<bool, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        "UPDATE repositories SET next_sync_at = $3 WHERE id = $1 AND user_id = $2",
        id,
        user_id,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// The role of the owner of any repository, which decides the
/// [`RemoteAccess`](crate::model::remote_access::RemoteAccess) of pushes, whoever commits.
pub(crate) async fn get_repository_owner_role(
    db: &DatabasePool,
    id: Uuid,
) -> Result<Option<UserRole>, AppError> {
    let role = sqlx::query_scalar!(
        r#"SELECT u.role AS "role: UserRole"
           FROM repositories r
           JOIN users u ON u.id = r.user_id
           WHERE r.id = $1"#,
        id
    )
    .fetch_optional(db)
    .await?;
    Ok(role)
}

/// The owner of any repository, not scoped to a user. Only for admins.
pub(crate) async fn get_repository_owner(
    db: &DatabasePool,
    id: Uuid,
) -> Result<Option<Uuid>, AppError> {
    let owner = sqlx::query_scalar!(
        r#"SELECT user_id AS "user_id: Uuid" FROM repositories WHERE id = $1"#,
        id
    )
    .fetch_optional(db)
    .await?;
    Ok(owner)
}

/// Any repository as `viewer_id` sees it in admin views, not scoped to a user.
pub(crate) async fn get_repository_label(
    db: &DatabasePool,
    id: Uuid,
    viewer_id: Uuid,
) -> Result<Option<RepositoryLabel>, AppError> {
    let label = sqlx::query_as!(
        RepositoryLabel,
        r#"SELECT r.id AS "id: Uuid",
                  r.name,
                  u.user_name AS owner_name,
                  (r.user_id = $2 OR EXISTS (SELECT 1
                                             FROM repository_users ru
                                             WHERE ru.repository_id = r.id AND ru.user_id = $2)) AS "readable!: bool"
           FROM repositories r
                    JOIN users u ON u.id = r.user_id
           WHERE r.id = $1"#,
        id,
        viewer_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(label)
}

/// The users the repository is shared with, without its owner.
pub(crate) async fn list_repository_users(
    db: &DatabasePool,
    id: Uuid,
) -> Result<Vec<RepositoryUser>, AppError> {
    let users = sqlx::query_as!(
        RepositoryUser,
        r#"SELECT u.id AS "user_id: Uuid", u.user_name, u.email, ru.can_commit, ru.created_at AS "created_at: DateTime<Utc>"
           FROM repository_users ru
           JOIN users u ON u.id = ru.user_id
           WHERE ru.repository_id = $1
           ORDER BY ru.created_at, u.id"#,
        id,
    )
    .fetch_all(db)
    .await?;
    Ok(users)
}

/// Shares the repository with the user, who cannot commit to it. Does nothing if it already is.
pub(crate) async fn add_repository_user(
    db: &DatabasePool,
    id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let now = Utc::now();
    sqlx::query!(
        r#"INSERT INTO repository_users (repository_id, user_id, can_commit, created_at)
           VALUES ($1, $2, false, $3)
           ON CONFLICT DO NOTHING"#,
        id,
        user_id,
        now,
    )
    .execute(db)
    .await?;
    Ok(())
}

/// Sets whether the user the repository is shared with may commit to it. Returns `false` if it
/// is not shared with them.
pub(crate) async fn set_repository_user_can_commit(
    db: &DatabasePool,
    id: Uuid,
    user_id: Uuid,
    can_commit: bool,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "UPDATE repository_users SET can_commit = $3 WHERE repository_id = $1 AND user_id = $2",
        id,
        user_id,
        can_commit,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Stops sharing the repository with the user, and removes it from their chats.
/// Does nothing if it was not shared with them.
pub(crate) async fn remove_repository_user(
    db: &DatabasePool,
    id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let mut tx = begin_write(db).await?;
    let removed = sqlx::query!(
        "DELETE FROM repository_users WHERE repository_id = $1 AND user_id = $2",
        id,
        user_id,
    )
    .execute(&mut *tx)
    .await?;
    // Only if it was shared, the owner keeps the repository in their chats.
    if removed.rows_affected() > 0 {
        sqlx::query!(
            r#"DELETE FROM chat_repositories
               WHERE repository_id = $1 AND chat_id IN (SELECT id FROM chats WHERE user_id = $2)"#,
            id,
            user_id,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

pub(crate) async fn list_repository_ids(db: &DatabasePool) -> Result<Vec<Uuid>, AppError> {
    let ids = sqlx::query_scalar!(r#"SELECT id AS "id: Uuid" FROM repositories"#)
        .fetch_all(db)
        .await?;
    Ok(ids)
}

/// Marks up to `limit` due repositories as `SYNCING`, skipping the ones in `exclude`.
pub(crate) async fn claim_due_repositories(
    db: &DatabasePool,
    exclude: &[Uuid],
    limit: i64,
) -> Result<Vec<SyncJob>, AppError> {
    let exclude = Json(exclude);
    let now = Utc::now();
    let jobs = sqlx::query_as!(
        SyncJob,
        r#"UPDATE repositories
           SET sync_status     = 'SYNCING',
               sync_started_at = $3
           WHERE id IN (SELECT id
                        FROM repositories
                        WHERE next_sync_at <= $3
                          AND id NOT IN (SELECT unhex(value, '-') FROM json_each($1))
                        ORDER BY next_sync_at
                        LIMIT $2)
           RETURNING id AS "id: Uuid", remote_url, branch, poll_interval_seconds, token_encrypted, head_commit_sha,
                     (SELECT role FROM users u WHERE u.id = user_id) AS "owner_role!: UserRole""#,
        exclude,
        limit,
        now,
    )
    .fetch_all(db)
    .await?;
    Ok(jobs)
}

/// Records a successful sync. Returns `false` if the repository was deleted or reset
/// while syncing, in which case the result is outdated and nothing is written.
///
/// A sync requested while this one ran is kept, otherwise the next one is scheduled
/// after the poll interval, or not at all for a local repository.
///
/// `documents` are the documents in the commit, the ones without an extraction are queued for
/// conversion.
pub(crate) async fn finish_sync(
    db: &DatabasePool,
    id: Uuid,
    head_commit_sha: &str,
    git_size: u64,
    lfs_size: u64,
    documents: &[RepositoryDocument],
) -> Result<bool, AppError> {
    let mut tx = begin_write(db).await?;
    let (git_size, lfs_size) = (git_size as i64, lfs_size as i64);
    let now = Utc::now();
    let result = sqlx::query!(
        r#"UPDATE repositories
           SET sync_status     = 'READY',
               sync_started_at = NULL,
               head_commit_sha = $2,
               last_synced_at  = $5,
               git_size        = $3,
               lfs_size        = $4,
               last_error      = NULL,
               next_sync_at    = CASE
                                     WHEN next_sync_at > sync_started_at THEN next_sync_at
                                     -- a local repository is synced only when requested
                                     WHEN poll_interval_seconds IS NULL THEN NULL
                                     ELSE strftime('%Y-%m-%dT%H:%M:%f+00:00', $5,
                                                   poll_interval_seconds || ' seconds')
                                 END
           WHERE id = $1 AND sync_status = 'SYNCING'"#,
        id,
        head_commit_sha,
        git_size,
        lfs_size,
        now,
    )
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() == 0 {
        return Ok(false);
    }

    sqlx::query!(
        "DELETE FROM repository_documents WHERE repository_id = $1",
        id
    )
    .execute(&mut *tx)
    .await?;
    for document in documents {
        sqlx::query!(
            "INSERT INTO repository_documents (repository_id, path, blob_oid) VALUES ($1, $2, $3)",
            id,
            document.path,
            document.blob_oid,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(true)
}

/// Like [`finish_sync`], for a failed sync. The last synced commit is kept.
pub(crate) async fn fail_sync(db: &DatabasePool, id: Uuid, error: &str) -> Result<bool, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        r#"UPDATE repositories
           SET sync_status     = 'FAILED',
               sync_started_at = NULL,
               last_error      = $2,
               next_sync_at    = CASE
                                     WHEN next_sync_at > sync_started_at THEN next_sync_at
                                     -- a local repository is synced only when requested
                                     WHEN poll_interval_seconds IS NULL THEN NULL
                                     ELSE strftime('%Y-%m-%dT%H:%M:%f+00:00', $3,
                                                   poll_interval_seconds || ' seconds')
                                 END
           WHERE id = $1 AND sync_status = 'SYNCING'"#,
        id,
        error,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Restores the status of syncs left `SYNCING` by a crash and schedules them again.
pub(crate) async fn reset_interrupted_syncs(db: &DatabasePool) -> Result<u64, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        r#"UPDATE repositories
           SET sync_status     = CASE
                                     WHEN last_error IS NOT NULL THEN 'FAILED'
                                     WHEN head_commit_sha IS NULL THEN 'PENDING'
                                     ELSE 'READY'
                                 END,
               sync_started_at = NULL,
               next_sync_at    = $1
           WHERE sync_status = 'SYNCING'"#,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected())
}

fn split_token(token: Option<StoredToken>) -> (Option<Vec<u8>>, Option<String>) {
    match token {
        Some(token) => (Some(token.encrypted), token.hint),
        None => (None, None),
    }
}
