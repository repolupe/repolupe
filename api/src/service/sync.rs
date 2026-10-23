use crate::config::error::AppError;
use crate::config::state::{AppState, DatabasePool};
use crate::model::remote_access::RemoteAccess;
use crate::model::repository::SyncJob;
use crate::repository;
use crate::service::extraction;
use crate::service::mirror::Update;
use chrono::{TimeDelta, Utc};
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};
use tokio::task::{JoinHandle, JoinSet};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// Repositories cloned or fetched at the same time.
const MAX_CONCURRENT_SYNCS: usize = 4;

/// How often due repositories are looked for, so a requested sync starts within this delay.
const POLL_INTERVAL: Duration = Duration::from_secs(5);

/// How often mirrors of deleted repositories, unused document extractions, unused attachments
/// and expired temporary chats are removed.
const CLEANUP_INTERVAL: Duration = Duration::from_mins(15);
/// Temporary chats are deleted when their last message is older.
const TEMPORARY_CHAT_LIFETIME: TimeDelta = TimeDelta::days(1);
/// LFS objects of files other than documents are downloaded up to this size, see
/// [`download_lfs_object`].
const MAX_TEXT_LFS_OBJECT_SIZE: u64 = 1024 * 1024;
/// Files that are never text, whose LFS objects are not downloaded.
const BINARY_EXTENSIONS: &[&str] = &[
    // Images
    "png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "tif", "tiff", "heic", "heif", "avif", "psd",
    // Audio and video
    "mp3", "wav", "flac", "ogg", "m4a", "aac", "mp4", "m4v", "mov", "avi", "mkv", "webm",
    // Archives
    "zip", "gz", "tgz", "bz2", "xz", "zst", "7z", "rar", "tar", "jar", "apk", "dmg", "iso",
    // Office documents
    "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "key", "pages", "numbers",
    // Fonts, executables and data
    "ttf", "otf", "woff", "woff2", "exe", "dll", "so", "dylib", "bin", "wasm", "sqlite", "db",
    "parquet",
];

pub(crate) async fn reset_interrupted(db: &DatabasePool) -> Result<u64, AppError> {
    repository::repository::reset_interrupted_syncs(db).await
}

/// Clones and fetches due repositories in the background until `shutdown` is cancelled, then
/// aborts the running syncs. Assumes a single API instance, since running syncs are only
/// tracked in memory.
pub(crate) fn spawn_sync_task(state: AppState, shutdown: CancellationToken) -> JoinHandle<()> {
    tokio::spawn(async move {
        // Running syncs by task, so a sync that panicked is still removed.
        let mut tasks = JoinSet::new();
        let mut running: HashMap<tokio::task::Id, Uuid> = HashMap::new();
        let mut last_cleanup: Option<Instant> = None;
        let mut interval = tokio::time::interval(POLL_INTERVAL);
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

        loop {
            tokio::select! {
                _ = interval.tick() => {}
                _ = shutdown.cancelled() => break,
            }

            while let Some(result) = tasks.try_join_next_with_id() {
                let task_id = match result {
                    Ok((task_id, ())) => task_id,
                    Err(e) => {
                        tracing::error!("Sync task failed: {e}");
                        e.id()
                    }
                };
                running.remove(&task_id);
            }

            // Runs between claims, so no sync can create a mirror while it is removed.
            if last_cleanup.is_none_or(|at| at.elapsed() >= CLEANUP_INTERVAL) {
                let in_use: HashSet<Uuid> = running.values().copied().collect();
                if let Err(e) = remove_orphaned_mirrors(&state, in_use).await {
                    tracing::error!("Failed to remove mirrors of deleted repositories: {e}");
                }
                // Before attachments, so the files of the deleted chats go in the same pass.
                match repository::chat::delete_expired_temporary_chats(
                    &state.db,
                    Utc::now() - TEMPORARY_CHAT_LIFETIME,
                )
                .await
                {
                    Ok(0) => {}
                    Ok(n) => tracing::info!("Removed {n} expired temporary chats"),
                    Err(e) => tracing::error!("Failed to remove expired temporary chats: {e}"),
                }
                if let Err(e) = extraction::remove_unused(&state.db).await {
                    tracing::error!("Failed to remove unused document extractions: {e}");
                }
                if let Err(e) = state.attachments.remove_unused(&state.db).await {
                    tracing::error!("Failed to remove unused attachments: {e}");
                }
                last_cleanup = Some(Instant::now());
            }

            let free = MAX_CONCURRENT_SYNCS - running.len();
            if free == 0 {
                continue;
            }
            let exclude: Vec<Uuid> = running.values().copied().collect();
            let jobs = match repository::repository::claim_due_repositories(
                &state.db,
                &exclude,
                free as i64,
            )
            .await
            {
                Ok(jobs) => jobs,
                Err(e) => {
                    tracing::error!("Failed to claim due repositories: {e}");
                    continue;
                }
            };

            for job in jobs {
                let id = job.id;
                let state = state.clone();
                let handle = tasks.spawn(async move { sync_repository(&state, job).await });
                running.insert(handle.id(), id);
            }
        }

        // Kills the git processes; the next start would reschedule the syncs anyway.
        tasks.shutdown().await;
        if !running.is_empty()
            && let Err(e) = reset_interrupted(&state.db).await
        {
            tracing::error!("Failed to reset aborted syncs: {e}");
        }
    })
}

async fn sync_repository(state: &AppState, job: SyncJob) {
    let id = job.id;
    let started = Instant::now();

    let finished = match fetch(state, &job).await {
        Ok(update) => {
            tracing::info!(
                "Synced repository {id} at {} in {:?}",
                update.sha,
                started.elapsed()
            );
            repository::repository::finish_sync(
                &state.db,
                id,
                &update.sha,
                update.git_size,
                update.lfs_size,
                &extraction::list_documents(&update.files),
            )
            .await
        }
        Err(e) => {
            let message = error_message(id, e);
            tracing::info!("Failed to sync repository {id}: {message}");
            repository::repository::fail_sync(&state.db, id, &message).await
        }
    };

    match finished {
        Ok(true) => state.extractor.notify_queued(),
        Ok(false) => tracing::info!(
            "Repository {id} was deleted or reset while syncing, discarded the result"
        ),
        Err(e) => tracing::error!("Failed to store the sync result of repository {id}: {e}"),
    }
}

/// Fetches the branch into the mirror of the repository, with the content of its documents,
/// which are converted afterwards, see [`extraction`]. A local repository is only read, and
/// created by its first sync.
async fn fetch(state: &AppState, job: &SyncJob) -> Result<Update, AppError> {
    let Some(remote) = job.remote() else {
        // Without a synced commit, nothing can have been committed to it yet.
        return state
            .mirrors
            .update_local(job.id, &job.branch, job.head_commit_sha.is_none())
            .await;
    };
    let url = remote.parsed_url()?;
    let token = remote.token(&state.token_cipher)?;

    // Without a synced commit there is nothing worth keeping, e.g. after the remote changed
    // or an interrupted first clone, so start over.
    if job.head_commit_sha.is_none() {
        state.mirrors.remove(job.id).await?;
    }
    // Before the commit is recorded, so the documents of a synced commit are always available.
    state
        .mirrors
        .update(
            job.id,
            &url,
            &job.branch,
            download_lfs_object,
            token.as_deref(),
            RemoteAccess::of(job.owner_role),
        )
        .await
}

/// Whether to download the LFS object of the file at `path`, of `size` bytes: documents, to
/// convert them, and small files that may be text, so the tools can read them.
fn download_lfs_object(path: &str, size: u64) -> bool {
    if extraction::is_document(path) {
        return true;
    }
    let binary = path.rsplit_once('.').is_some_and(|(_, extension)| {
        BINARY_EXTENSIONS
            .iter()
            .any(|e| e.eq_ignore_ascii_case(extension))
    });
    !binary && size <= MAX_TEXT_LFS_OBJECT_SIZE
}

/// Removes the mirrors of repositories that no longer exist, except those `in_use`.
async fn remove_orphaned_mirrors(state: &AppState, in_use: HashSet<Uuid>) -> Result<(), AppError> {
    let mut keep = in_use;
    keep.extend(repository::repository::list_repository_ids(&state.db).await?);
    state.mirrors.remove_others(&keep).await
}

/// The message stored in `last_error` and shown to the user. Internal details only go to the logs.
fn error_message(id: Uuid, error: AppError) -> String {
    match error {
        AppError::BadRequest(message)
        | AppError::Unprocessable(_, message)
        | AppError::BadGateway(_, message) => message,
        other => {
            tracing::error!("Failed to sync repository {id}: {other}");
            "Internal error while syncing, see the server logs".to_string()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn downloads_documents_and_small_files_that_may_be_text() {
        let large = MAX_TEXT_LFS_OBJECT_SIZE + 1;
        assert!(download_lfs_object("Mietangebot.typ", 2_000));
        assert!(download_lfs_object("Makefile", 2_000));
        assert!(!download_lfs_object("Mietangebot.typ", large));
        assert!(!download_lfs_object("Photo.JPG", 2_000));
        assert!(download_lfs_object("scan.pdf", large));
    }
}
