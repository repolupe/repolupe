//! The bare repositories of the mirrors, read and fetched in-process with gitoxide (`gix`), so
//! no `git` executable is needed, e.g. on Android and iOS. Repositories are opened without the
//! system and user config, see [`open`]. Knows nothing about LFS, see [`super`].

mod grep;
mod http;
mod push;
mod remote;
mod repack;

use crate::config::error::AppError;
use chrono::{DateTime, Utc};
use gix::bstr::ByteSlice;
use gix::objs::tree::EntryKind;
use gix::refs::Target;
use gix::refs::transaction::{Change, LogChange, PreviousValue, RefEdit};
use gix::{ObjectId, Repository};
use std::collections::{HashMap, HashSet};
use std::fmt::Display;
use std::path::{Path, PathBuf};

pub(crate) use grep::{GrepFile, GrepOptions, GrepOutput, grep};
pub(crate) use push::PushResult;
pub(crate) use remote::{GitClient, TOKEN_USERNAME};

/// Creates an empty bare repository at `git_dir`.
pub(crate) async fn init_bare(git_dir: &Path) -> Result<(), AppError> {
    let git_dir = git_dir.to_path_buf();
    blocking(move || {
        gix::init_bare(&git_dir).map_err(|e| failed("init", e))?;
        Ok(())
    })
    .await
}

/// The id git gives a blob with `content`.
pub(crate) fn blob_oid(content: &[u8]) -> Result<String, AppError> {
    gix::objs::compute_hash(gix::hash::Kind::Sha1, gix::objs::Kind::Blob, content)
        .map(|oid| oid.to_string())
        .map_err(|e| failed("hash", e))
}

/// The bytes the git objects take on disk, like Forgejo's repository size. Only the fetched
/// branch is stored, so this is usually less than the remote reports, and LFS objects are not
/// included.
pub(crate) async fn objects_size(git_dir: &Path) -> Result<u64, AppError> {
    let objects = git_dir.join("objects");
    blocking(move || {
        files_size(&objects).map_err(|e| {
            AppError::InternalServerError(format!("Failed to measure {}: {e}", objects.display()))
        })
    })
    .await
}

/// The size of the files in `dir`, recursively. Leaves out `info`, which holds no objects.
fn files_size(dir: &Path) -> std::io::Result<u64> {
    let mut size = 0;
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            if entry.file_name() != "info" {
                size += files_size(&entry.path())?;
            }
        } else if file_type.is_file() {
            size += entry.metadata()?.len();
        }
    }
    Ok(size)
}

/// A blob in the tree of a commit.
pub(crate) struct TreeBlob {
    pub(crate) oid: String,
    pub(crate) size: u64,
    pub(crate) path: String,
}

/// Lists the blobs in the tree of `commit`, including subdirectories, sorted by path like
/// `git ls-tree -r`.
pub(crate) async fn list_blobs(git_dir: &Path, commit: &str) -> Result<Vec<TreeBlob>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let commit = commit.to_string();
    blocking(move || {
        let repo = open(&git_dir)?;
        let tree = commit_tree(&repo, &commit)?
            .ok_or_else(|| AppError::InternalServerError(format!("Commit {commit} is missing")))?;
        let mut recorder = gix::traverse::tree::Recorder::default();
        tree.traverse()
            .depthfirst(&mut recorder)
            .map_err(|e| failed("ls-tree", e))?;
        recorder
            .records
            .into_iter()
            // Like git, symlinks are blobs too. Submodules are commits.
            .filter(|entry| entry.mode.is_blob() || entry.mode.is_link())
            .map(|entry| {
                let header = repo
                    .find_header(entry.oid)
                    .map_err(|e| failed("ls-tree", e))?;
                Ok(TreeBlob {
                    oid: entry.oid.to_string(),
                    size: header.size(),
                    path: entry.filepath.to_str_lossy().into_owned(),
                })
            })
            .collect()
    })
    .await
}

/// Reads the contents of the blobs `oids`, by oid, leaving out the missing ones. They are kept
/// in memory, so only pass small ones.
pub(crate) async fn read_blobs(
    git_dir: &Path,
    oids: &[String],
) -> Result<HashMap<String, Vec<u8>>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let oids = oids.to_vec();
    blocking(move || {
        let repo = open(&git_dir)?;
        let mut blobs = HashMap::with_capacity(oids.len());
        for oid in oids {
            let id = parse_oid(&oid)?;
            if let Some(object) = repo
                .try_find_object(id)
                .map_err(|e| failed("cat-file", e))?
            {
                blobs.insert(oid, object.detach().data);
            }
        }
        Ok(blobs)
    })
    .await
}

/// A blob read by [`read_blob`].
pub(crate) enum Blob {
    Content(Vec<u8>),
    /// Larger than the limit, with its size.
    TooLarge(u64),
}

/// Reads the blob `oid` if it is at most `max_size` bytes, `None` if it is missing.
pub(crate) async fn read_blob(
    git_dir: &Path,
    oid: &str,
    max_size: u64,
) -> Result<Option<Blob>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let oid = oid.to_string();
    blocking(move || {
        let repo = open(&git_dir)?;
        let id = parse_oid(&oid)?;
        let Some(header) = repo
            .try_find_header(id)
            .map_err(|e| failed("cat-file", e))?
        else {
            return Ok(None);
        };
        if header.size() > max_size {
            return Ok(Some(Blob::TooLarge(header.size())));
        }
        let object = repo.find_object(id).map_err(|e| failed("cat-file", e))?;
        Ok(Some(Blob::Content(object.detach().data)))
    })
    .await
}

/// What a path names in the tree of a commit.
pub(crate) enum PathEntry {
    Blob {
        oid: String,
        mode: BlobMode,
    },
    Tree,
    /// E.g. a submodule.
    Other,
    Missing,
}

/// Looks up `path` in the tree of `commit`, the root tree if empty.
pub(crate) async fn path_entry(
    git_dir: &Path,
    commit: &str,
    path: &str,
) -> Result<PathEntry, AppError> {
    let git_dir = git_dir.to_path_buf();
    let commit = commit.to_string();
    let path = path.to_string();
    blocking(move || {
        let repo = open(&git_dir)?;
        let Some(tree) = commit_tree(&repo, &commit)? else {
            return Ok(PathEntry::Missing);
        };
        if path.is_empty() {
            return Ok(PathEntry::Tree);
        }
        let Some(entry) = tree
            .lookup_entry(path.split('/'))
            .map_err(|e| failed("cat-file", e))?
        else {
            return Ok(PathEntry::Missing);
        };
        let oid = entry.object_id().to_string();
        Ok(match entry.mode().kind() {
            EntryKind::Blob => PathEntry::Blob {
                oid,
                mode: BlobMode::Regular,
            },
            EntryKind::BlobExecutable => PathEntry::Blob {
                oid,
                mode: BlobMode::Executable,
            },
            EntryKind::Link => PathEntry::Blob {
                oid,
                mode: BlobMode::Link,
            },
            EntryKind::Tree => PathEntry::Tree,
            EntryKind::Commit => PathEntry::Other,
        })
    })
    .await
}

/// The values the files `paths` have for the attribute `name` in the `.gitattributes` files in
/// the tree of `commit`, like `git check-attr --source`, in the same order. `None` unless it is
/// set to a value.
pub(crate) async fn attributes(
    git_dir: &Path,
    commit: &str,
    paths: Vec<String>,
    name: &'static str,
) -> Result<Vec<Option<String>>, AppError> {
    use gix::attrs::StateRef;
    use gix::worktree::stack::state::attributes::Source;

    let git_dir = git_dir.to_path_buf();
    let commit = commit.to_string();
    blocking(move || {
        let repo = open(&git_dir)?;
        let tree = commit_tree(&repo, &commit)?
            .ok_or_else(|| AppError::InternalServerError(format!("Commit {commit} is missing")))?;
        // The attributes are read from the blobs the index lists, since there is no worktree.
        let index = repo
            .index_from_tree(&tree.id)
            .map_err(|e| failed("check-attr", e))?;
        let mut stack = repo
            .attributes_only(&index, Source::IdMapping)
            .map_err(|e| failed("check-attr", e))?;
        paths
            .iter()
            .map(|path| {
                let mut outcome = stack.selected_attribute_matches([name]);
                stack
                    .at_entry(path.as_str(), Some(gix::index::entry::Mode::FILE))
                    .map_err(|e| failed("check-attr", e))?
                    .matching_attributes(&mut outcome);
                Ok(outcome
                    .iter_selected()
                    .find_map(|m| match m.assignment.state {
                        StateRef::Value(value) => Some(value.as_bstr().to_str_lossy().into_owned()),
                        _ => None,
                    }))
            })
            .collect()
    })
    .await
}

/// The kinds of blobs in a tree. Like git, symlinks are blobs that hold their target.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum BlobMode {
    Regular,
    Executable,
    Link,
}

impl BlobMode {
    /// The mode as git writes it, e.g. in patches.
    pub(crate) fn octal(self) -> &'static str {
        match self {
            BlobMode::Regular => "100644",
            BlobMode::Executable => "100755",
            BlobMode::Link => "120000",
        }
    }

    fn kind(self) -> EntryKind {
        match self {
            BlobMode::Regular => EntryKind::Blob,
            BlobMode::Executable => EntryKind::BlobExecutable,
            BlobMode::Link => EntryKind::Link,
        }
    }
}

/// The author or committer of a commit.
pub(crate) struct Signature {
    pub(crate) name: String,
    pub(crate) email: String,
    pub(crate) time: DateTime<Utc>,
}

impl Signature {
    fn to_gix(&self) -> gix::actor::Signature {
        gix::actor::Signature {
            name: self.name.as_str().into(),
            email: self.email.as_str().into(),
            time: gix::date::Time::new(self.time.timestamp(), 0),
        }
    }
}

/// Creates `branch` in the empty repository at `git_dir` with a commit without files by
/// `signature` as author and committer, and points `HEAD` at it. Returns the commit. Like git, a
/// line break is appended to `message`.
pub(crate) async fn create_branch(
    git_dir: &Path,
    branch: &str,
    message: &str,
    signature: &Signature,
) -> Result<String, AppError> {
    let git_dir = git_dir.to_path_buf();
    let branch_ref = format!("refs/heads/{branch}");
    let message = format!("{}\n", message.trim_end());
    let signature = signature.to_gix();
    blocking(move || {
        let repo = open(&git_dir)?;
        let tree = repo
            .write_object(gix::objs::Tree::empty())
            .map_err(|e| failed("commit", e))?;
        let mut author_time = gix::date::parse::TimeBuf::default();
        let mut committer_time = gix::date::parse::TimeBuf::default();
        let commit = repo
            .new_commit_as(
                signature.to_ref(&mut committer_time),
                signature.to_ref(&mut author_time),
                message,
                tree,
                Vec::<ObjectId>::new(),
            )
            .map_err(|e| failed("commit", e))?
            .id;
        let name = |name: &str| name.try_into().map_err(|e| failed("update-ref", e));
        repo.edit_references([
            RefEdit {
                change: Change::Update {
                    log: LogChange::default(),
                    expected: PreviousValue::MustNotExist,
                    new: Target::Object(commit),
                },
                name: name(&branch_ref)?,
                deref: false,
            },
            RefEdit {
                change: Change::Update {
                    log: LogChange::default(),
                    expected: PreviousValue::Any,
                    new: Target::Symbolic(name(&branch_ref)?),
                },
                name: name("HEAD")?,
                deref: false,
            },
        ])
        .map_err(|e| failed("update-ref", e))?;
        Ok(commit.to_string())
    })
    .await
}

/// The commit `branch` points to in the repository at `git_dir`, `None` if there is no such
/// branch.
pub(crate) async fn branch_head(git_dir: &Path, branch: &str) -> Result<Option<String>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let branch_ref = format!("refs/heads/{branch}");
    blocking(move || {
        let repo = open(&git_dir)?;
        let Some(mut reference) = repo
            .try_find_reference(branch_ref.as_str())
            .map_err(|e| failed("rev-parse", e))?
        else {
            return Ok(None);
        };
        let commit = reference
            .peel_to_commit()
            .map_err(|e| failed("rev-parse", e))?;
        Ok(Some(commit.id.to_string()))
    })
    .await
}

/// Points `branch` in the repository at `git_dir` from `expected` to `commit`. Fails if it
/// points elsewhere.
pub(crate) async fn update_branch(
    git_dir: &Path,
    branch: &str,
    expected: &str,
    commit: &str,
) -> Result<(), AppError> {
    let git_dir = git_dir.to_path_buf();
    let branch_ref = format!("refs/heads/{branch}");
    let expected = parse_oid(expected)?;
    let commit = parse_oid(commit)?;
    blocking(move || {
        let repo = open(&git_dir)?;
        repo.edit_reference(RefEdit {
            change: Change::Update {
                log: LogChange::default(),
                expected: PreviousValue::MustExistAndMatch(Target::Object(expected)),
                new: Target::Object(commit),
            },
            name: branch_ref
                .as_str()
                .try_into()
                .map_err(|e| failed("update-ref", e))?,
            deref: false,
        })
        .map_err(|e| failed("update-ref", e))?;
        Ok(())
    })
    .await
}

/// Writes a commit on top of `parent` that only changes `path`: to `content` with its mode, or
/// removes it if `None`. Returns the commit, which no ref points to. Like git, a line break is
/// appended to `message`.
pub(crate) async fn commit_file(
    git_dir: &Path,
    parent: &str,
    path: &str,
    content: Option<(Vec<u8>, BlobMode)>,
    message: &str,
    author: &Signature,
    committer: &Signature,
) -> Result<String, AppError> {
    let path = path.to_string();
    write_commit(
        git_dir,
        parent,
        message,
        author,
        committer,
        move |repo, _, editor| {
            match content {
                Some((content, mode)) => {
                    let blob = repo.write_blob(&content).map_err(|e| failed("commit", e))?;
                    editor.upsert(&path, mode.kind(), blob)
                }
                None => editor.remove(&path),
            }
            .map_err(|e| failed("commit", e))?;
            Ok(())
        },
    )
    .await
}

/// Writes a commit on top of `parent` that moves the entry at the first path of each of
/// `moves` to the second, a file or a directory with all it contains. The paths must exist
/// and must not overlap. Returns the commit, which no ref points to. Like git, a line break is
/// appended to `message`.
pub(crate) async fn commit_moves(
    git_dir: &Path,
    parent: &str,
    moves: &[(String, String)],
    message: &str,
    author: &Signature,
    committer: &Signature,
) -> Result<String, AppError> {
    let moves = moves.to_vec();
    write_commit(
        git_dir,
        parent,
        message,
        author,
        committer,
        move |_, tree, editor| {
            for (from, to) in &moves {
                let entry = tree
                    .lookup_entry(from.split('/'))
                    .map_err(|e| failed("mv", e))?
                    .ok_or_else(|| failed("mv", format!("`{from}` is missing")))?;
                editor
                    .remove(from)
                    .and_then(|editor| editor.upsert(to, entry.mode().kind(), entry.object_id()))
                    .map_err(|e| failed("mv", e))?;
            }
            Ok(())
        },
    )
    .await
}

/// Writes a commit on top of `parent` with the tree `edit` makes of the parent's tree (which it
/// also gets to read). Returns the commit, which no ref points to.
async fn write_commit<F>(
    git_dir: &Path,
    parent: &str,
    message: &str,
    author: &Signature,
    committer: &Signature,
    edit: F,
) -> Result<String, AppError>
where
    F: FnOnce(
            &Repository,
            &gix::Tree<'_>,
            &mut gix::object::tree::Editor<'_>,
        ) -> Result<(), AppError>
        + Send
        + 'static,
{
    let git_dir = git_dir.to_path_buf();
    let parent = parse_oid(parent)?;
    let message = format!("{}\n", message.trim_end());
    let author = author.to_gix();
    let committer = committer.to_gix();
    blocking(move || {
        let repo = open(&git_dir)?;
        let tree = repo
            .find_commit(parent)
            .and_then(|commit| commit.tree())
            .map_err(|e| failed("commit", e))?;
        let mut editor = repo.edit_tree(tree.id).map_err(|e| failed("commit", e))?;
        edit(&repo, &tree, &mut editor)?;
        let tree = editor.write().map_err(|e| failed("commit", e))?;
        let mut author_time = gix::date::parse::TimeBuf::default();
        let mut committer_time = gix::date::parse::TimeBuf::default();
        let commit = repo
            .new_commit_as(
                committer.to_ref(&mut committer_time),
                author.to_ref(&mut author_time),
                message,
                tree,
                [parent],
            )
            .map_err(|e| failed("commit", e))?;
        Ok(commit.id.to_string())
    })
    .await
}

/// Writes `commit`, which changes only the entries at `paths` on top of its parent (none inside
/// another), again on top of `onto`, with the same author, committer and message, committed at
/// `time`. Returns `commit` itself if `onto` is its parent, and `None` if one of `paths` differs
/// between the parent and `onto` (for a directory, anything in it), or `onto` has a file where
/// one needs a directory, since the change would then undo changes it never saw.
pub(crate) async fn rebuild_file_commit(
    git_dir: &Path,
    commit: &str,
    paths: &[String],
    onto: &str,
    time: DateTime<Utc>,
) -> Result<Option<String>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let id = parse_oid(commit)?;
    let onto = parse_oid(onto)?;
    let paths = paths.to_vec();
    blocking(move || {
        let repo = open(&git_dir)?;
        let proposed = repo.find_commit(id).map_err(|e| failed("rebase", e))?;
        let parent = proposed
            .parent_ids()
            .next()
            .ok_or_else(|| failed("rebase", format!("{id} has no parent")))?
            .detach();
        if parent == onto {
            return Ok(Some(id.to_string()));
        }
        let tree_of = |commit: ObjectId| {
            repo.find_commit(commit)
                .and_then(|commit| commit.tree())
                .map_err(|e| failed("rebase", e))
        };
        let entry = |tree: &gix::Tree<'_>, path: &str| {
            tree.lookup_entry(path.split('/'))
                .map(|entry| entry.map(|entry| (entry.object_id(), entry.mode())))
                .map_err(|e| failed("rebase", e))
        };
        let onto_tree = tree_of(onto)?;
        let parent_tree = tree_of(parent)?;
        for path in &paths {
            if entry(&parent_tree, path)? != entry(&onto_tree, path)? {
                return Ok(None);
            }
            for (end, _) in path.match_indices('/') {
                if entry(&onto_tree, &path[..end])?.is_some_and(|(_, mode)| !mode.is_tree()) {
                    return Ok(None);
                }
            }
        }

        let mut editor = repo
            .edit_tree(onto_tree.id)
            .map_err(|e| failed("rebase", e))?;
        let proposed_tree = tree_of(id)?;
        for path in &paths {
            match entry(&proposed_tree, path)? {
                Some((oid, mode)) => editor.upsert(path, mode.kind(), oid),
                None => editor.remove(path),
            }
            .map_err(|e| failed("rebase", e))?;
        }
        let tree = editor.write().map_err(|e| failed("rebase", e))?;
        let decoded = proposed.decode().map_err(|e| failed("rebase", e))?;
        let author = decoded.author().map_err(|e| failed("rebase", e))?;
        let committer = decoded.committer().map_err(|e| failed("rebase", e))?;
        let committer = gix::actor::Signature {
            name: committer.name.into(),
            email: committer.email.into(),
            time: gix::date::Time::new(time.timestamp(), 0),
        };
        let mut time = gix::date::parse::TimeBuf::default();
        let message = decoded.message.to_str_lossy();
        let rebuilt = repo
            .new_commit_as(committer.to_ref(&mut time), author, message, tree, [onto])
            .map_err(|e| failed("rebase", e))?;
        Ok(Some(rebuilt.id.to_string()))
    })
    .await
}

/// The blobs at `paths` in `commit` that its parent has at none of them: the files it adds or
/// changes, not the ones it moves.
pub(crate) async fn added_blobs(
    git_dir: &Path,
    commit: &str,
    paths: &[String],
) -> Result<Vec<String>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let id = parse_oid(commit)?;
    let paths = paths.to_vec();
    blocking(move || {
        let repo = open(&git_dir)?;
        let commit = repo.find_commit(id).map_err(|e| failed("cat-file", e))?;
        let tree = commit.tree().map_err(|e| failed("cat-file", e))?;
        let existing = parent_entries(&repo, &commit, &paths)?;
        let mut blobs = Vec::new();
        for path in &paths {
            if let Some(entry) = tree
                .lookup_entry(path.split('/'))
                .map_err(|e| failed("cat-file", e))?
                && entry.mode().is_blob()
                && !existing.contains(&entry.object_id())
            {
                blobs.push(entry.object_id().to_string());
            }
        }
        Ok(blobs)
    })
    .await
}

/// The objects the parent of `commit` has at `paths`, which a remote that has the parent has.
fn parent_entries(
    repo: &Repository,
    commit: &gix::Commit<'_>,
    paths: &[String],
) -> Result<HashSet<ObjectId>, AppError> {
    let mut entries = HashSet::new();
    let Some(parent) = commit.parent_ids().next() else {
        return Ok(entries);
    };
    let tree = repo
        .find_commit(parent)
        .and_then(|parent| parent.tree())
        .map_err(|e| failed("pack-objects", e))?;
    for path in paths {
        if let Some(entry) = tree
            .lookup_entry(path.split('/'))
            .map_err(|e| failed("pack-objects", e))?
        {
            entries.insert(entry.object_id());
        }
    }
    Ok(entries)
}

/// A pack with the objects `commit` adds to its parent, assuming it changes only the entries at
/// `paths`: the commit, the trees along the paths, and the files there unless they were deleted
/// or moved there (which the parent has). Written without deltas, since it is small.
fn pack_file_commit(
    repo: &Repository,
    commit: ObjectId,
    paths: &[String],
) -> Result<Vec<u8>, AppError> {
    use gix::odb::pack::data::output;

    let found = repo
        .find_commit(commit)
        .map_err(|e| failed("pack-objects", e))?;
    let tree = found.tree().map_err(|e| failed("pack-objects", e))?;
    let existing = parent_entries(repo, &found, paths)?;
    let mut ids = vec![commit, tree.id];
    for path in paths {
        let names: Vec<&str> = path.split('/').collect();
        for end in 1..=names.len() {
            // Missing if deleted, also directories left empty.
            match tree
                .lookup_entry(names[..end].iter().copied())
                .map_err(|e| failed("pack-objects", e))?
            {
                Some(entry) if end == names.len() && existing.contains(&entry.object_id()) => {}
                Some(entry) => ids.push(entry.object_id()),
                None => break,
            }
        }
    }
    // Paths share the root tree, and maybe more.
    let mut seen = HashSet::new();
    ids.retain(|id| seen.insert(*id));

    let entries = ids
        .iter()
        .map(|id| {
            let object = repo
                .find_object(*id)
                .map_err(|e| failed("pack-objects", e))?;
            let data = gix::objs::Data::new(&object.data, object.kind, gix::hash::Kind::Sha1);
            output::Entry::from_data(
                &output::Count::from_data(*id, None),
                &data,
                gix::zlib::Compression::DEFAULT,
            )
            .map_err(|e| failed("pack-objects", e))
        })
        .collect::<Result<Vec<_>, AppError>>()?;
    let mut writer = output::bytes::FromEntriesIter::new(
        std::iter::once(Ok(entries)),
        Vec::new(),
        ids.len() as u32,
        gix::odb::pack::data::Version::V2,
        gix::hash::Kind::Sha1,
    );
    for written in &mut writer {
        written.map_err(|e| failed("pack-objects", e))?;
    }
    Ok(writer.into_write())
}

/// What [`read_commit`] reads of a commit.
pub(crate) struct CommitInfo {
    pub(crate) author: Signature,
    pub(crate) message: String,
}

/// Reads the author and message of `commit`, `None` if it is missing.
pub(crate) async fn read_commit(
    git_dir: &Path,
    commit: &str,
) -> Result<Option<CommitInfo>, AppError> {
    let git_dir = git_dir.to_path_buf();
    let id = parse_oid(commit)?;
    blocking(move || {
        let repo = open(&git_dir)?;
        let Some(object) = repo
            .try_find_object(id)
            .map_err(|e| failed("cat-file", e))?
        else {
            return Ok(None);
        };
        let commit = object
            .try_into_commit()
            .map_err(|e| failed("cat-file", e))?;
        let decoded = commit.decode().map_err(|e| failed("cat-file", e))?;
        let author = decoded.author().map_err(|e| failed("cat-file", e))?;
        let time = author.time().map_err(|e| failed("cat-file", e))?;
        Ok(Some(CommitInfo {
            author: Signature {
                name: author.name.to_str_lossy().into_owned(),
                email: author.email.to_str_lossy().into_owned(),
                time: DateTime::from_timestamp(time.seconds, 0).unwrap_or_default(),
            },
            message: decoded.message.to_str_lossy().into_owned(),
        }))
    })
    .await
}

/// Opens the repository at `git_dir`, ignoring the system and user config and the environment.
fn open(git_dir: &Path) -> Result<Repository, AppError> {
    gix::open_opts(git_dir, gix::open::Options::isolated()).map_err(|e| {
        AppError::InternalServerError(format!(
            "Failed to open the repository {}: {e}",
            git_dir.display()
        ))
    })
}

/// The tree of `commit`, or `None` if the commit is missing.
fn commit_tree<'repo>(
    repo: &'repo Repository,
    commit: &str,
) -> Result<Option<gix::Tree<'repo>>, AppError> {
    let Some(object) = repo
        .try_find_object(parse_oid(commit)?)
        .map_err(|e| failed("rev-parse", e))?
    else {
        return Ok(None);
    };
    let tree = object
        .try_into_commit()
        .map_err(|e| failed("rev-parse", e))?
        .tree()
        .map_err(|e| failed("rev-parse", e))?;
    Ok(Some(tree))
}

fn parse_oid(oid: &str) -> Result<ObjectId, AppError> {
    ObjectId::from_hex(oid.as_bytes())
        .map_err(|e| AppError::InternalServerError(format!("Invalid object id {oid}: {e}")))
}

/// Runs `f`, which reads or writes a repository, on a thread where blocking is fine.
async fn blocking<T, F>(f: F) -> Result<T, AppError>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, AppError> + Send + 'static,
{
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| AppError::InternalServerError(format!("Git task failed: {e}")))?
}

/// An error of a local git operation, named after the git command it replaces.
fn failed(operation: &str, error: impl Display) -> AppError {
    AppError::InternalServerError(format!("git {operation} failed: {error}"))
}

/// The directory of the packs in the repository at `git_dir`.
fn pack_dir(git_dir: &Path) -> PathBuf {
    git_dir.join("objects").join("pack")
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::io::Write;
    use std::process::{Command, Stdio};
    use uuid::Uuid;

    /// A non-bare repository with commits made by the git CLI, removed when dropped.
    pub(crate) struct Fixture {
        pub(crate) dir: PathBuf,
    }

    impl Fixture {
        pub(crate) fn new() -> Self {
            let dir = std::env::temp_dir().join(format!("repolupe-git-{}", Uuid::now_v7()));
            std::fs::create_dir_all(&dir).unwrap();
            let fixture = Self { dir };
            fixture.git(&["init", "--quiet", "--initial-branch=main"]);
            fixture
        }

        pub(crate) fn git_dir(&self) -> PathBuf {
            self.dir.join(".git")
        }

        /// Writes `files` and commits them, returns the commit.
        pub(crate) fn commit(&self, files: &[(&str, &[u8])]) -> String {
            for (path, content) in files {
                let path = self.dir.join(path);
                std::fs::create_dir_all(path.parent().unwrap()).unwrap();
                std::fs::write(path, content).unwrap();
            }
            self.git(&["add", "--all"]);
            self.git(&["commit", "--quiet", "--allow-empty", "--message", "commit"]);
            self.git(&["rev-parse", "HEAD"]).trim().to_string()
        }

        pub(crate) fn git(&self, args: &[&str]) -> String {
            let output = Command::new("git")
                .arg("-C")
                .arg(&self.dir)
                .args(["-c", "user.name=Test", "-c", "user.email=test@example.com"])
                .args(args)
                .output()
                .unwrap();
            assert!(output.status.success(), "{output:?}");
            String::from_utf8(output.stdout).unwrap()
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    #[tokio::test]
    async fn reads_trees_and_blobs() {
        let fixture = Fixture::new();
        let commit = fixture.commit(&[
            ("b.md", b"b"),
            ("a/z.md", b"z"),
            ("a.txt", b"a.txt"),
            ("a b/c.md", b"spaces"),
        ]);
        let git_dir = fixture.git_dir();

        let blobs = list_blobs(&git_dir, &commit).await.unwrap();
        let paths: Vec<&str> = blobs.iter().map(|b| b.path.as_str()).collect();
        // Sorted like git sorts trees, where `a/` comes after `a.txt`.
        assert_eq!(paths, ["a b/c.md", "a.txt", "a/z.md", "b.md"]);
        assert_eq!(blobs[0].size, 6);
        let expected = fixture.git(&["rev-parse", &format!("{commit}:a b/c.md")]);
        assert_eq!(blobs[0].oid, expected.trim());

        let contents = read_blobs(&git_dir, &[blobs[1].oid.clone(), "0".repeat(40)])
            .await
            .unwrap();
        assert_eq!(
            contents,
            HashMap::from([(blobs[1].oid.clone(), b"a.txt".to_vec())])
        );

        assert!(matches!(
            path_entry(&git_dir, &commit, "a b/c.md").await.unwrap(),
            PathEntry::Blob { oid, .. } if oid == blobs[0].oid
        ));
        assert!(matches!(
            read_blob(&git_dir, &blobs[0].oid, 6).await.unwrap(),
            Some(Blob::Content(content)) if content == b"spaces"
        ));
        assert!(matches!(
            read_blob(&git_dir, &blobs[0].oid, 5).await.unwrap(),
            Some(Blob::TooLarge(6))
        ));
        assert!(
            read_blob(&git_dir, &"0".repeat(40), 5)
                .await
                .unwrap()
                .is_none()
        );
        assert!(matches!(
            path_entry(&git_dir, &commit, "a").await.unwrap(),
            PathEntry::Tree
        ));
        assert!(matches!(
            path_entry(&git_dir, &commit, "").await.unwrap(),
            PathEntry::Tree
        ));
        for missing in ["nope", "a/nope", "b.md/x"] {
            assert!(matches!(
                path_entry(&git_dir, &commit, missing).await.unwrap(),
                PathEntry::Missing
            ));
        }
        assert!(matches!(
            path_entry(&git_dir, &"0".repeat(40), "b.md").await.unwrap(),
            PathEntry::Missing
        ));
    }

    fn author() -> Signature {
        Signature {
            name: "Repolupe+model".to_string(),
            email: "noreply@repolupe.com".to_string(),
            time: DateTime::from_timestamp(1_700_000_000, 0).unwrap(),
        }
    }

    fn committer() -> Signature {
        Signature {
            name: "Alice".to_string(),
            email: "alice@example.com".to_string(),
            time: DateTime::from_timestamp(1_700_000_000, 0).unwrap(),
        }
    }

    #[tokio::test]
    async fn rebuilds_file_commits_on_newer_commits() {
        let fixture = Fixture::new();
        let base = fixture.commit(&[("a.txt", b"a"), ("dir/b.txt", b"b")]);
        let git_dir = fixture.git_dir();
        let content = Some((b"b2".to_vec(), BlobMode::Regular));
        let proposed = commit_file(
            &git_dir,
            &base,
            "dir/b.txt",
            content,
            "Change b",
            &author(),
            &committer(),
        )
        .await
        .unwrap();
        let now = Utc::now();
        let paths = ["dir/b.txt".to_string()];

        // Nothing to rebuild.
        let same = rebuild_file_commit(&git_dir, &proposed, &paths, &base, now).await;
        assert_eq!(same.unwrap().as_deref(), Some(proposed.as_str()));

        // Another file changed.
        let other = fixture.commit(&[("a.txt", b"a2")]);
        let rebuilt = rebuild_file_commit(&git_dir, &proposed, &paths, &other, now)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            fixture.git(&["rev-parse", &format!("{rebuilt}^")]).trim(),
            other
        );
        assert_eq!(fixture.git(&["show", &format!("{rebuilt}:a.txt")]), "a2");
        assert_eq!(
            fixture.git(&["show", &format!("{rebuilt}:dir/b.txt")]),
            "b2"
        );
        assert_eq!(
            fixture.git(&[
                "log",
                "-1",
                "--format=%an <%ae> %at%n%cn <%ce>%n%B",
                &rebuilt
            ]),
            "Repolupe+model <noreply@repolupe.com> 1700000000\n\
            Alice <alice@example.com>\nChange b\n\n"
        );
        assert_ne!(
            fixture.git(&["log", "-1", "--format=%ct", &rebuilt]).trim(),
            "1700000000"
        );

        // The file itself changed.
        let changed = fixture.commit(&[("dir/b.txt", b"b3")]);
        let conflict = rebuild_file_commit(&git_dir, &proposed, &paths, &changed, now);
        assert_eq!(conflict.await.unwrap(), None);

        // A new file where a file now takes the place of its directory.
        let created = commit_file(
            &git_dir,
            &base,
            "new/c.txt",
            Some((b"c".to_vec(), BlobMode::Regular)),
            "Add c",
            &author(),
            &committer(),
        )
        .await
        .unwrap();
        let blocked = fixture.commit(&[("new", b"file")]);
        let new_paths = ["new/c.txt".to_string()];
        let conflict = rebuild_file_commit(&git_dir, &created, &new_paths, &blocked, now);
        assert_eq!(conflict.await.unwrap(), None);
    }

    fn moves(moves: &[(&str, &str)]) -> Vec<(String, String)> {
        moves
            .iter()
            .map(|(from, to)| (from.to_string(), to.to_string()))
            .collect()
    }

    /// The source and destination of each of `moves`.
    fn move_paths(moves: &[(String, String)]) -> Vec<String> {
        moves
            .iter()
            .flat_map(|(from, to)| [from.clone(), to.clone()])
            .collect()
    }

    #[tokio::test]
    async fn moves_files_and_directories() {
        let fixture = Fixture::new();
        let base = fixture.commit(&[
            ("a.txt", b"a"),
            ("docs/x.md", b"x"),
            ("docs/sub/y.md", b"y"),
            ("keep/k.txt", b"k"),
        ]);
        let git_dir = fixture.git_dir();
        let moves = moves(&[("docs", "archive/2026/docs"), ("a.txt", "keep/b.txt")]);
        let proposed = commit_moves(&git_dir, &base, &moves, "Archive", &author(), &committer())
            .await
            .unwrap();
        assert_eq!(
            fixture.git(&["ls-tree", "-r", "--name-only", &proposed]),
            "archive/2026/docs/sub/y.md\narchive/2026/docs/x.md\nkeep/b.txt\nkeep/k.txt\n"
        );
        // The same objects, only moved.
        assert_eq!(
            fixture.git(&["rev-parse", &format!("{proposed}:archive/2026/docs")]),
            fixture.git(&["rev-parse", &format!("{base}:docs")])
        );
        assert_eq!(
            fixture.git(&["diff", "--name-status", "-M", &base, &proposed]),
            "R100\tdocs/sub/y.md\tarchive/2026/docs/sub/y.md\n\
            R100\tdocs/x.md\tarchive/2026/docs/x.md\nR100\ta.txt\tkeep/b.txt\n"
        );

        // Only the files the commit adds, none of them.
        let paths = move_paths(&moves);
        assert!(
            added_blobs(&git_dir, &proposed, &paths)
                .await
                .unwrap()
                .is_empty()
        );

        // Rebuilt on top of changes elsewhere, also next to the destination.
        let now = Utc::now();
        let other = fixture.commit(&[("keep/other.txt", b"o")]);
        let rebuilt = rebuild_file_commit(&git_dir, &proposed, &paths, &other, now)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            fixture.git(&["ls-tree", "-r", "--name-only", &rebuilt]),
            "archive/2026/docs/sub/y.md\narchive/2026/docs/x.md\nkeep/b.txt\nkeep/k.txt\n\
            keep/other.txt\n"
        );

        // A conflict if anything in a moved directory changed, or the destination was taken.
        let changed = fixture.commit(&[("docs/sub/new.md", b"new")]);
        let conflict = rebuild_file_commit(&git_dir, &proposed, &paths, &changed, now);
        assert_eq!(conflict.await.unwrap(), None);
        fixture.git(&["rm", "--quiet", "-r", "docs/sub/new.md"]);
        let taken = fixture.commit(&[("keep/b.txt", b"taken")]);
        let conflict = rebuild_file_commit(&git_dir, &proposed, &paths, &taken, now);
        assert_eq!(conflict.await.unwrap(), None);
    }

    #[tokio::test]
    async fn packs_the_objects_of_file_commits() {
        let fixture = Fixture::new();
        let base = fixture.commit(&[("a.txt", b"a"), ("dir/sub/b.txt", b"b")]);
        let git_dir = fixture.git_dir();
        let changed = commit_file(
            &git_dir,
            &base,
            "dir/sub/b.txt",
            Some((b"b2".to_vec(), BlobMode::Executable)),
            "Change b",
            &author(),
            &committer(),
        )
        .await
        .unwrap();
        // Leaves `dir` empty, so it is gone.
        let deleted = commit_file(
            &git_dir,
            &base,
            "dir/sub/b.txt",
            None,
            "Remove b",
            &author(),
            &committer(),
        )
        .await
        .unwrap();

        // Moves `dir/sub` and `a.txt` into the new `moved` directory, whose tree is the only new
        // object besides the commit and the root tree, since the moved objects are on the
        // remote already.
        let moves = moves(&[("dir/sub", "moved/sub"), ("a.txt", "moved/a.txt")]);
        let moved = commit_moves(&git_dir, &base, &moves, "Move", &author(), &committer())
            .await
            .unwrap();
        let file_paths = ["dir/sub/b.txt".to_string()];
        let move_paths = move_paths(&moves);

        for (commit, paths, objects) in [
            (&changed, &file_paths[..], 5),
            (&deleted, &file_paths[..], 2),
            (&moved, &move_paths[..], 3),
        ] {
            let pack =
                pack_file_commit(&open(&git_dir).unwrap(), parse_oid(commit).unwrap(), paths)
                    .unwrap();
            // A repository with only the base commit takes the pack, and has the commit then.
            let target = std::env::temp_dir().join(format!("repolupe-git-{}", Uuid::now_v7()));
            let clone = Command::new("git")
                .args(["clone", "--quiet", "--bare", "--no-local"])
                .arg(&fixture.dir)
                .arg(&target)
                .output()
                .unwrap();
            assert!(clone.status.success(), "{clone:?}");
            let mut index = Command::new("git")
                .arg("-C")
                .arg(&target)
                .args(["index-pack", "--stdin", "--strict"])
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .spawn()
                .unwrap();
            index.stdin.take().unwrap().write_all(&pack).unwrap();
            let output = index.wait_with_output().unwrap();
            assert!(output.status.success(), "{output:?}");
            let check = |args: &[&str]| {
                let output = Command::new("git")
                    .arg("-C")
                    .arg(&target)
                    .args(args)
                    .output()
                    .unwrap();
                assert!(output.status.success(), "{args:?}: {output:?}");
                String::from_utf8(output.stdout).unwrap()
            };
            check(&["update-ref", "refs/heads/changed", commit]);
            check(&["fsck", "--connectivity-only", "--no-dangling"]);
            // Only what the commit adds.
            assert_eq!(u32::from_be_bytes(pack[8..12].try_into().unwrap()), objects);
            std::fs::remove_dir_all(&target).unwrap();
        }
    }

    #[tokio::test]
    async fn reads_attributes_of_commits() {
        let fixture = Fixture::new();
        let commit = fixture.commit(&[
            (
                ".gitattributes",
                b"*.pdf filter=lfs diff=lfs -text\n*.txt text\n",
            ),
            (
                "docs/.gitattributes",
                b"*.pdf -filter\nscans/** filter=lfs\n",
            ),
        ]);
        let git_dir = fixture.git_dir();
        let expected = [
            ("a.pdf", Some("lfs")),
            ("new/b.pdf", Some("lfs")),
            ("a.txt", None),
            // Nested files take precedence.
            ("docs/b.pdf", None),
            ("docs/scans/b.png", Some("lfs")),
        ];
        let paths = expected.iter().map(|(path, _)| path.to_string()).collect();
        let values = attributes(&git_dir, &commit, paths, "filter")
            .await
            .unwrap();
        for ((path, expected), value) in expected.iter().zip(&values) {
            assert_eq!(value.as_deref(), *expected, "{path}");
        }
        let empty = fixture.commit(&[]);
        fixture.git(&["rm", "--quiet", "-r", "."]);
        let none = fixture.commit(&[]);
        let pdf = || vec!["a.pdf".to_string()];
        assert_eq!(
            attributes(&git_dir, &empty, pdf(), "filter").await.unwrap(),
            [Some("lfs".to_string())]
        );
        assert_eq!(
            attributes(&git_dir, &none, pdf(), "filter").await.unwrap(),
            [None]
        );
    }

    #[tokio::test]
    async fn creates_bare_repositories() {
        let dir = std::env::temp_dir().join(format!("repolupe-git-{}", Uuid::now_v7()));
        init_bare(&dir).await.unwrap();
        assert!(dir.join("HEAD").is_file());
        assert!(open(&dir).unwrap().is_bare());
        assert_eq!(objects_size(&dir).await.unwrap(), 0);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[tokio::test]
    async fn creates_and_moves_branches() {
        let dir = std::env::temp_dir().join(format!("repolupe-git-{}", Uuid::now_v7()));
        init_bare(&dir).await.unwrap();
        let git = |args: &[&str]| {
            let output = Command::new("git")
                .arg("--git-dir")
                .arg(&dir)
                .args(args)
                .output()
                .unwrap();
            assert!(output.status.success(), "{args:?}: {output:?}");
            String::from_utf8(output.stdout).unwrap()
        };
        assert_eq!(branch_head(&dir, "docs").await.unwrap(), None);

        let initial = create_branch(&dir, "docs", "Initial commit", &committer())
            .await
            .unwrap();
        assert_eq!(
            branch_head(&dir, "docs").await.unwrap(),
            Some(initial.clone())
        );
        assert_eq!(git(&["symbolic-ref", "HEAD"]), "refs/heads/docs\n");
        assert_eq!(
            git(&["log", "--format=%P|%an <%ae>|%cn <%ce>|%B", "docs"]),
            "|Alice <alice@example.com>|Alice <alice@example.com>|Initial commit\n\n"
        );
        assert_eq!(git(&["ls-tree", "-r", "docs"]), "");
        git(&["fsck", "--strict", "--no-dangling"]);
        // Only once.
        assert!(
            create_branch(&dir, "docs", "Again", &committer())
                .await
                .is_err()
        );

        let content = Some((b"a".to_vec(), BlobMode::Regular));
        let changed = commit_file(
            &dir,
            &initial,
            "a.txt",
            content,
            "Add a",
            &author(),
            &committer(),
        )
        .await
        .unwrap();
        update_branch(&dir, "docs", &initial, &changed)
            .await
            .unwrap();
        assert_eq!(
            branch_head(&dir, "docs").await.unwrap(),
            Some(changed.clone())
        );
        assert_eq!(git(&["show", "docs:a.txt"]), "a");
        // Not from another commit.
        assert!(
            update_branch(&dir, "docs", &initial, &initial)
                .await
                .is_err()
        );
        assert_eq!(branch_head(&dir, "docs").await.unwrap(), Some(changed));
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
