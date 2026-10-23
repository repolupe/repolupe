//! The mirrors of the registered repositories in `REPOS_DIR`: a bare git repository per
//! repository (see [`git`]) with the Git LFS objects it downloaded (see [`lfs`]). This module is
//! the only way in, so the rest of the server never sees LFS pointers: [`Snapshot::read`] and
//! [`MirrorStore::read`] return the content of LFS files, or [`Content::Unavailable`] if it was not
//! downloaded, and [`Snapshot::grep`] searches the downloaded ones and skips the others. [`Snapshot::commit_file`] stores files
//! that `.gitattributes` assigns to LFS as objects, which [`MirrorStore::push_file_commit`]
//! uploads. [`Snapshot::commit_moves`] moves files and directories, LFS pointers as they are.
//!
//! Local repositories have no remote, so their mirror is all there is of them: it is created by
//! [`MirrorStore::update_local`], and commits move its branch ([`MirrorStore::commit_local`]),
//! with their LFS objects kept in the mirror.

mod git;
mod lfs;

use crate::config::error::AppError;
use crate::dto::error::ErrorCode;
use crate::model::remote_access::RemoteAccess;
use chrono::Utc;
use git::{Blob, GitClient, PushResult};
use lfs::LfsClient;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use tokio::sync::OwnedMutexGuard;
use url::Url;
use uuid::Uuid;

pub(crate) use git::{
    BlobMode, CommitInfo, GrepFile, GrepOptions, GrepOutput, PathEntry, Signature, TreeBlob,
};

/// The mirrors in `REPOS_DIR`, with the clients that fetch them. Holds connection pools, so
/// share one instance.
pub(crate) struct MirrorStore {
    dir: PathBuf,
    git: GitClient,
    lfs: LfsClient,
    /// By repository, see [`MirrorStore::lock`].
    locks: Mutex<HashMap<Uuid, Arc<tokio::sync::Mutex<()>>>>,
}

/// Attempts of [`MirrorStore::push_file_commit`] when the branch moves in between.
const MAX_PUSH_ATTEMPTS: usize = 3;

/// The result of [`MirrorStore::update`] and [`MirrorStore::update_local`].
pub(crate) struct Update {
    /// The fetched commit.
    pub(crate) sha: String,
    /// The files in the commit.
    pub(crate) files: Vec<TreeBlob>,
    /// The bytes the git objects take on disk, like Forgejo's repository size. Only the fetched
    /// branch is stored, so this is usually less than the remote reports.
    pub(crate) git_size: u64,
    /// The bytes of the LFS objects the commit refers to, whether they were downloaded or not.
    pub(crate) lfs_size: u64,
}

/// The result of [`MirrorStore::push_file_commit`] and [`MirrorStore::commit_local`].
pub(crate) enum Push {
    /// The branch is at `commit` now: the proposed commit, or the same change on top of the
    /// newer commit the branch moved to.
    Pushed { commit: String },
    /// One of the paths it changes changed on the branch since the commit the change was based
    /// on.
    Conflict,
    /// The remote refused to update the branch, for this reason.
    Rejected(String),
}

/// The id git gives a blob with `content`, e.g. to tell whether a file already has it.
pub(crate) fn blob_oid(content: &[u8]) -> Result<String, AppError> {
    git::blob_oid(content)
}

/// The content of a file as far as it is available.
pub(crate) enum Content {
    Bytes(Vec<u8>),
    /// Larger than the limit, or than what is downloaded, with its size.
    TooLarge(u64),
    /// Stored outside the repository and not downloaded, e.g. because [`MirrorStore::update`] was
    /// not asked to (yet).
    Unavailable,
}

impl MirrorStore {
    /// Mirrors repositories in `dir`, which must exist.
    pub(crate) fn new(dir: &Path) -> Result<Self, reqwest::Error> {
        Ok(Self {
            dir: dir.to_path_buf(),
            git: GitClient::new()?,
            lfs: LfsClient::new()?,
            locks: Mutex::default(),
        })
    }

    /// Verifies that `url` is reachable with `token` and has `branch`, like `git ls-remote`.
    pub(crate) async fn check_remote(
        &self,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        self.git.check_remote(url, branch, token, access).await
    }

    /// Verifies that `url` accepts pushes to `branch` with `token`, as far as the remote
    /// tells before a push.
    pub(crate) async fn check_push(
        &self,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        self.git.check_push(url, branch, token, access).await
    }

    /// Fetches `branch` from `url` into the mirror of repository `id`, cloning it if needed,
    /// with the content of the LFS files that `download` accepts by their path and size. The
    /// files of the returned commit can be read as soon as this returns.
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn update(
        &self,
        id: Uuid,
        url: &Url,
        branch: &str,
        download: fn(&str, u64) -> bool,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<Update, AppError> {
        let _lock = self.lock(id).await;
        let dir = self.repository_dir(id);
        if !tokio::fs::try_exists(dir.join("HEAD"))
            .await
            .unwrap_or(false)
        {
            remove_dir(&dir).await?;
            git::init_bare(&dir).await?;
        }
        let sha = self
            .git
            .fetch_branch(&dir, url, branch, token, access)
            .await?;
        let files = git::list_blobs(&dir, &sha).await?;
        self.lfs
            .fetch_objects(&dir, url, branch, &files, download, token, access)
            .await?;
        Ok(Update {
            git_size: git::objects_size(&dir).await?,
            lfs_size: lfs::total_size(&dir, &files).await?,
            files,
            sha,
        })
    }

    /// Pushes `commit`, a commit in the mirror of repository `id` that only changes the entries
    /// at `paths` (see [`Snapshot::commit_file`] and [`Snapshot::commit_moves`]), to `branch` of
    /// `url`, after the LFS objects of the files it adds, if they are stored in LFS. Fetches the
    /// branch first: if it moved, the change is made again on top of it, unless one of `paths`
    /// changed there too.
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn push_file_commit(
        &self,
        id: Uuid,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
        commit: &str,
        paths: &[String],
    ) -> Result<Push, AppError> {
        let _lock = self.lock(id).await;
        let dir = self.repository_dir(id);
        if git::read_commit(&dir, commit).await?.is_none() {
            return Err(AppError::Unprocessable(
                ErrorCode::FileUnavailable,
                "The change is no longer available".to_string(),
            ));
        }
        // Unchanged when the commit is made again on top of a newer one.
        let pointers = added_pointers(&dir, commit, paths).await?;
        if !pointers.is_empty() {
            self.lfs
                .upload_objects(&dir, url, branch, &pointers, token, access)
                .await?;
        }
        for _ in 0..MAX_PUSH_ATTEMPTS {
            let head = self
                .git
                .fetch_branch(&dir, url, branch, token, access)
                .await?;
            let Some(commit) =
                git::rebuild_file_commit(&dir, commit, paths, &head, Utc::now()).await?
            else {
                return Ok(Push::Conflict);
            };
            match self
                .git
                .push_file_commit(&dir, url, branch, token, access, &head, &commit, paths)
                .await?
            {
                PushResult::Pushed => return Ok(Push::Pushed { commit }),
                PushResult::Moved => continue,
                PushResult::Rejected(reason) => return Ok(Push::Rejected(reason)),
            }
        }
        Ok(Push::Rejected(
            "the branch kept changing, please try again".to_string(),
        ))
    }

    /// Reads `branch` of the local repository `id`, like [`Self::update`] fetches it from a
    /// remote. If `create`, the mirror is created first, replacing what is left of an earlier
    /// attempt, with an empty initial commit on `branch`. Otherwise it fails if the mirror or the
    /// branch is missing, since the repository is lost then.
    pub(crate) async fn update_local(
        &self,
        id: Uuid,
        branch: &str,
        create: bool,
    ) -> Result<Update, AppError> {
        let _lock = self.lock(id).await;
        let dir = self.repository_dir(id);
        if create {
            remove_dir(&dir).await?;
            git::init_bare(&dir).await?;
            let signature = Signature {
                name: "Repolupe".to_string(),
                email: "noreply@repolupe.com".to_string(),
                time: Utc::now(),
            };
            git::create_branch(&dir, branch, "Initial commit", &signature).await?;
        }
        let sha = local_head(id, &dir, branch).await?;
        let files = git::list_blobs(&dir, &sha).await?;
        Ok(Update {
            git_size: git::objects_size(&dir).await?,
            lfs_size: lfs::total_size(&dir, &files).await?,
            files,
            sha,
        })
    }

    /// Moves `branch` of the local repository `id` to `commit`, a commit in its mirror that only
    /// changes the entries at `paths`, like [`Self::push_file_commit`] pushes it. If the branch
    /// moved since the commit's parent, the change is made again on top of it, unless one of
    /// `paths` changed there too.
    pub(crate) async fn commit_local(
        &self,
        id: Uuid,
        branch: &str,
        commit: &str,
        paths: &[String],
    ) -> Result<Push, AppError> {
        let _lock = self.lock(id).await;
        let dir = self.repository_dir(id);
        if git::read_commit(&dir, commit).await?.is_none() {
            return Err(AppError::Unprocessable(
                ErrorCode::FileUnavailable,
                "The change is no longer available".to_string(),
            ));
        }
        let head = local_head(id, &dir, branch).await?;
        let Some(commit) = git::rebuild_file_commit(&dir, commit, paths, &head, Utc::now()).await?
        else {
            return Ok(Push::Conflict);
        };
        // Nothing else moves the branch while the lock is held.
        git::update_branch(&dir, branch, &head, &commit).await?;
        Ok(Push::Pushed { commit })
    }

    /// Removes the mirror of repository `id`, if any.
    pub(crate) async fn remove(&self, id: Uuid) -> Result<(), AppError> {
        let _lock = self.lock(id).await;
        remove_dir(&self.repository_dir(id)).await
    }

    /// Removes the mirrors of the repositories not in `keep`. Only touches entries named like a
    /// repository id, in case `REPOS_DIR` is shared with something else.
    pub(crate) async fn remove_others(&self, keep: &HashSet<Uuid>) -> Result<(), AppError> {
        let list_failed =
            |e| AppError::InternalServerError(format!("Failed to list REPOS_DIR: {e}"));
        let mut entries = tokio::fs::read_dir(&self.dir).await.map_err(list_failed)?;
        while let Some(entry) = entries.next_entry().await.map_err(list_failed)? {
            let Some(id) = entry
                .file_name()
                .to_str()
                .and_then(|n| Uuid::parse_str(n).ok())
            else {
                continue;
            };
            if keep.contains(&id) {
                continue;
            }
            remove_dir(&entry.path()).await?;
            tracing::info!("Removed the mirror of deleted repository {id}");
        }
        Ok(())
    }

    /// Reads the file with blob `oid` from the mirror of repository `id`, if it is at most
    /// `max_size` bytes.
    pub(crate) async fn read(
        &self,
        id: Uuid,
        oid: &str,
        max_size: u64,
    ) -> Result<Content, AppError> {
        read(&self.repository_dir(id), oid, max_size).await
    }

    /// Repository `id` at `commit`, which must have been fetched by [`MirrorStore::update`] or
    /// written by [`Snapshot::commit_file`] or [`Snapshot::commit_moves`].
    pub(crate) fn snapshot(&self, id: Uuid, commit: String) -> Snapshot {
        Snapshot {
            dir: self.repository_dir(id),
            commit,
        }
    }

    fn repository_dir(&self, id: Uuid) -> PathBuf {
        self.dir.join(id.to_string())
    }

    /// Held while the mirror of repository `id` is updated, pushed from or removed, so these
    /// run one at a time. Reads need none.
    async fn lock(&self, id: Uuid) -> OwnedMutexGuard<()> {
        let lock = self
            .locks
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .entry(id)
            .or_default()
            .clone();
        lock.lock_owned().await
    }
}

/// A repository at one commit, so every read sees the same version, even while it is updated.
pub(crate) struct Snapshot {
    dir: PathBuf,
    commit: String,
}

impl Snapshot {
    /// The git repository at `dir`, also a non-bare one's `.git`, at `commit`.
    #[cfg(test)]
    pub(crate) fn at(dir: PathBuf, commit: String) -> Self {
        Self { dir, commit }
    }

    pub(crate) fn commit(&self) -> &str {
        &self.commit
    }

    /// The same repository at `commit`, e.g. one written by [`Snapshot::commit_moves`].
    pub(crate) fn at_commit(&self, commit: String) -> Snapshot {
        Snapshot {
            dir: self.dir.clone(),
            commit,
        }
    }

    /// The files in the commit, including subdirectories, sorted by path like `git ls-tree -r`.
    pub(crate) async fn files(&self) -> Result<Vec<TreeBlob>, AppError> {
        git::list_blobs(&self.dir, &self.commit).await
    }

    /// What `path` names in the commit, the root directory if empty.
    pub(crate) async fn entry(&self, path: &str) -> Result<PathEntry, AppError> {
        git::path_entry(&self.dir, &self.commit, path).await
    }

    /// Reads the file with blob `oid`, if it is at most `max_size` bytes.
    pub(crate) async fn read(&self, oid: &str, max_size: u64) -> Result<Content, AppError> {
        read(&self.dir, oid, max_size).await
    }

    /// Whether the file with blob `oid` has `content`, whose blob is `content_oid` (see
    /// [`blob_oid`]), also if it is stored in LFS.
    pub(crate) async fn has_content(
        &self,
        oid: &str,
        content_oid: &str,
        content: &[u8],
    ) -> Result<bool, AppError> {
        if oid == content_oid {
            return Ok(true);
        }
        let Some(Blob::Content(blob)) =
            git::read_blob(&self.dir, oid, lfs::MAX_POINTER_SIZE).await?
        else {
            return Ok(false);
        };
        match lfs::parse_pointer(&blob) {
            Some(pointer) => lfs::points_to(&pointer, content).await,
            None => Ok(false),
        }
    }

    /// Writes a commit on top of this one that only changes `path`: to `content` with its mode,
    /// or removes it if `None`. Returns the commit, which no ref points to, so it is only
    /// stored in the mirror (which keeps unreachable objects). If the `.gitattributes` files
    /// of this commit assign `path` to LFS, the content is stored as an LFS object and the
    /// commit has its pointer, like git-lfs does.
    pub(crate) async fn commit_file(
        &self,
        path: &str,
        content: Option<(Vec<u8>, BlobMode)>,
        message: &str,
        author: &Signature,
        committer: &Signature,
    ) -> Result<String, AppError> {
        let content = match content {
            Some((content, mode)) if mode != BlobMode::Link && self.is_lfs(path).await? => {
                let pointer = lfs::store_object(&self.dir, content).await?;
                Some((pointer.to_file(), mode))
            }
            content => content,
        };
        git::commit_file(
            &self.dir,
            &self.commit,
            path,
            content,
            message,
            author,
            committer,
        )
        .await
    }

    /// Writes a commit on top of this one that moves the entry at the first path of each of
    /// `moves` to the second, a file or a directory with all it contains. The paths must exist
    /// and must not overlap. Returns the commit, which no ref points to, like
    /// [`Self::commit_file`]. Files stored in LFS keep their pointers, so check with
    /// [`Self::lfs_paths`] that their new paths are stored in LFS too.
    pub(crate) async fn commit_moves(
        &self,
        moves: &[(String, String)],
        message: &str,
        author: &Signature,
        committer: &Signature,
    ) -> Result<String, AppError> {
        git::commit_moves(&self.dir, &self.commit, moves, message, author, committer).await
    }

    /// Whether git-lfs stores the content of `path` in this commit.
    async fn is_lfs(&self, path: &str) -> Result<bool, AppError> {
        Ok(self.lfs_paths(vec![path.to_string()]).await? == [true])
    }

    /// Whether git-lfs stores the content of each of `paths` in this commit, in the same order.
    pub(crate) async fn lfs_paths(&self, paths: Vec<String>) -> Result<Vec<bool>, AppError> {
        let filters = git::attributes(&self.dir, &self.commit, paths, "filter").await?;
        Ok(filters
            .iter()
            .map(|filter| filter.as_deref() == Some("lfs"))
            .collect())
    }

    /// The author and message of the commit, `None` if it is missing.
    pub(crate) async fn info(&self) -> Result<Option<CommitInfo>, AppError> {
        git::read_commit(&self.dir, &self.commit).await
    }

    /// Searches `files`, files of the commit or other texts, like `git grep -P -I`, LFS files by
    /// their downloaded content. LFS files that were not downloaded are skipped like binary ones.
    /// Stops after about `max_output` bytes of matching lines.
    pub(crate) async fn grep(
        &self,
        files: Vec<GrepFile>,
        options: &GrepOptions<'_>,
        max_output: usize,
    ) -> Result<GrepOutput, AppError> {
        git::grep(&self.dir, files, options, lfs::resolve_pointer, max_output).await
    }
}

/// The commit `branch` of the local repository `id` in `dir` points to.
async fn local_head(id: Uuid, dir: &Path, branch: &str) -> Result<String, AppError> {
    let head = if tokio::fs::try_exists(dir.join("HEAD"))
        .await
        .unwrap_or(false)
    {
        git::branch_head(dir, branch).await?
    } else {
        None
    };
    head.ok_or_else(|| {
        tracing::error!("The mirror of local repository {id} or its branch {branch} is missing");
        AppError::Unprocessable(
            ErrorCode::RepoNotFound,
            "The repository is missing on the server".to_string(),
        )
    })
}

/// Reads the blob `oid` from the repository at `dir`, or the LFS object if it is a pointer.
async fn read(dir: &Path, oid: &str, max_size: u64) -> Result<Content, AppError> {
    // Read pointers even with a smaller limit, since the object may still fit.
    let blob = git::read_blob(dir, oid, max_size.max(lfs::MAX_POINTER_SIZE))
        .await?
        .ok_or_else(|| AppError::InternalServerError(format!("Blob {oid} is missing")))?;
    let content = match blob {
        Blob::Content(content) => content,
        Blob::TooLarge(size) => return Ok(Content::TooLarge(size)),
    };
    let Some(pointer) = lfs::parse_pointer(&content) else {
        return Ok(if content.len() as u64 > max_size {
            Content::TooLarge(content.len() as u64)
        } else {
            Content::Bytes(content)
        });
    };
    // Larger objects are never downloaded.
    if pointer.size > max_size.min(lfs::MAX_OBJECT_SIZE) {
        return Ok(Content::TooLarge(pointer.size));
    }
    Ok(match lfs::read_object(dir, &pointer.oid).await? {
        Some(content) => Content::Bytes(content),
        None => Content::Unavailable,
    })
}

/// The LFS pointers among the files `commit` adds or changes at `paths`. Moved files are left
/// out, the remote has their objects already.
async fn added_pointers(
    dir: &Path,
    commit: &str,
    paths: &[String],
) -> Result<Vec<lfs::Pointer>, AppError> {
    let mut pointers = Vec::new();
    for oid in git::added_blobs(dir, commit, paths).await? {
        if let Some(Blob::Content(blob)) = git::read_blob(dir, &oid, lfs::MAX_POINTER_SIZE).await?
            && let Some(pointer) = lfs::parse_pointer(&blob)
        {
            pointers.push(pointer);
        }
    }
    Ok(pointers)
}

async fn remove_dir(dir: &Path) -> Result<(), AppError> {
    match tokio::fs::remove_dir_all(dir).await {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(AppError::InternalServerError(format!(
            "Failed to remove {}: {e}",
            dir.display()
        ))),
    }
}
