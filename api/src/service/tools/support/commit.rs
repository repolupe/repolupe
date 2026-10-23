//! What the tools that propose commits share: who writes the commits, their paths and message,
//! and the patch and diff the user reviews.

use super::{diff, normalize_path, patch};
use crate::config::error::AppError;
use crate::dto::chat::{DiffFileKind, DiffMoveDto, FileDiffDto};
use crate::dto::error::ErrorCode;
use crate::model::tool_call::{ChangedPaths, FileMove};
use crate::service::mirror::{BlobMode, Content, PathEntry, Snapshot, TreeBlob};
use crate::service::tools::ToolRepository;

/// Larger files are not changed.
pub(crate) const MAX_CHANGE_BYTES: u64 = 1024 * 1024;
const MAX_COMMIT_MESSAGE_CHARS: usize = 5_000;

/// The email of the proposed commits that have no one to reply to.
const NOREPLY_EMAIL: &str = "noreply@repolupe.com";

/// A name and email of [`CommitIdentities`].
pub(crate) struct Identity {
    pub(crate) name: String,
    pub(crate) email: String,
}

/// Who the proposed commits are written by.
pub(crate) struct CommitIdentities {
    /// The model writing the answer.
    pub(crate) author: Identity,
    /// The user asking, who reviews the commits and pushes them.
    pub(crate) committer: Identity,
}

impl CommitIdentities {
    /// `model` by the name its provider knows it by. Users without an email commit with
    /// [`NOREPLY_EMAIL`].
    pub(crate) fn new(model: &str, user_name: String, email: Option<String>) -> Self {
        Self {
            author: Identity {
                name: format!("Repolupe+{model}"),
                email: NOREPLY_EMAIL.to_string(),
            },
            committer: Identity {
                name: user_name,
                email: email.unwrap_or_else(|| NOREPLY_EMAIL.to_string()),
            },
        }
    }
}

/// The path of a file to commit, outside of `.git`.
pub(crate) fn parse_commit_path(path: &str) -> Result<String, String> {
    let path = normalize_path(path)?;
    if path.is_empty() {
        return Err("`path` must be a file.".to_string());
    }
    check_outside_git(&path)?;
    Ok(path)
}

/// Fails for paths in `.git`, which git does not let a commit change.
pub(crate) fn check_outside_git(path: &str) -> Result<(), String> {
    if path
        .split('/')
        .any(|segment| segment.eq_ignore_ascii_case(".git"))
    {
        return Err("Files in `.git` can't be changed.".to_string());
    }
    Ok(())
}

pub(crate) fn parse_commit_message(message: &str) -> Result<String, String> {
    let message = message.trim().to_string();
    if message.is_empty() {
        return Err("`message` must not be empty.".to_string());
    }
    if message.chars().count() > MAX_COMMIT_MESSAGE_CHARS {
        return Err(format!(
            "`message` must be at most {MAX_COMMIT_MESSAGE_CHARS} characters."
        ));
    }
    Ok(message)
}

/// The files `moves` move in `snapshot`, each with its new path: a moved file itself, and the
/// files in a moved directory one by one. Missing paths are left out.
pub(crate) async fn moved_files(
    snapshot: &Snapshot,
    moves: &[FileMove],
) -> Result<Vec<(String, String)>, AppError> {
    let mut files: Option<Vec<TreeBlob>> = None;
    let mut moved = Vec::new();
    for FileMove { from, to } in moves {
        match snapshot.entry(from).await? {
            PathEntry::Tree => {
                if files.is_none() {
                    files = Some(snapshot.files().await?);
                }
                let prefix = format!("{from}/");
                for file in files.iter().flatten() {
                    if let Some(rest) = file.path.strip_prefix(&prefix) {
                        moved.push((file.path.clone(), format!("{to}/{rest}")));
                    }
                }
            }
            PathEntry::Missing => {}
            PathEntry::Blob { .. } | PathEntry::Other => moved.push((from.clone(), to.clone())),
        }
    }
    Ok(moved)
}

/// The commit a tool call proposed as a patch that `git am` applies. `repository` is at the
/// commit the call read, `change` at the proposed one, which changes `changed`.
pub(crate) async fn read_proposed_commit_patch(
    repository: &ToolRepository,
    change: &Snapshot,
    changed: &ChangedPaths,
) -> Result<String, AppError> {
    let info = change.info().await?.ok_or_else(unavailable)?;
    let diff = match changed {
        ChangedPaths::File(path) => {
            let (old, new) = file_sides(repository, change, path).await?;
            patch::file_diff(path, as_side(&old), as_side(&new))
        }
        ChangedPaths::Moves(moves) => moved_files(&repository.snapshot, moves)
            .await?
            .iter()
            .map(|(from, to)| patch::rename_diff(from, to))
            .collect(),
    };
    Ok(patch::format_patch(change.commit(), &info, &diff))
}

/// The commit a tool call proposed as the user reviews it, see [`read_proposed_commit_patch`]: the
/// diff of the file with the changed words marked, or the moves with the number of files in
/// each moved folder.
pub(crate) async fn read_proposed_commit_diff(
    repository: &ToolRepository,
    change: &Snapshot,
    changed: &ChangedPaths,
) -> Result<FileDiffDto, AppError> {
    change.info().await?.ok_or_else(unavailable)?;
    Ok(match changed {
        ChangedPaths::File(path) => {
            let (old, new) = file_sides(repository, change, path).await?;
            let diff = diff::file_diff(content(&old), content(&new));
            FileDiffDto {
                kind: diff.kind,
                hunks: diff.hunks,
                moves: None,
            }
        }
        ChangedPaths::Moves(moves) => {
            let files = moved_files(&repository.snapshot, moves).await?;
            let moves = moves
                .iter()
                .map(|FileMove { from, to }| {
                    let prefix = format!("{from}/");
                    let folder_files = (!files.iter().any(|(file, _)| file == from)).then(|| {
                        files
                            .iter()
                            .filter(|(file, _)| file.starts_with(&prefix))
                            .count() as i64
                    });
                    DiffMoveDto {
                        from: from.clone(),
                        to: to.clone(),
                        folder_files,
                    }
                })
                .collect();
            FileDiffDto {
                kind: DiffFileKind::Modified,
                hunks: vec![],
                moves: Some(moves),
            }
        }
    })
}

fn unavailable() -> AppError {
    AppError::Unprocessable(
        ErrorCode::FileUnavailable,
        "The change is no longer available".to_string(),
    )
}

/// A file on one side of a change, see [`patch::Side`].
type FileSide = (String, BlobMode, Vec<u8>);

/// `path` in `repository` and in `change`, `None` where it is not a file.
async fn file_sides(
    repository: &ToolRepository,
    change: &Snapshot,
    path: &str,
) -> Result<(Option<FileSide>, Option<FileSide>), AppError> {
    // The content of LFS files rather than their pointers (the oid stays the pointer's blob), so
    // the diff shows what changed in the file.
    let side = async |snapshot: &Snapshot| -> Result<Option<FileSide>, AppError> {
        let PathEntry::Blob { oid, mode } = snapshot.entry(path).await? else {
            return Ok(None);
        };
        let content = match snapshot.read(&oid, MAX_CHANGE_BYTES).await? {
            Content::Bytes(content) => content,
            // Shown as binary.
            Content::TooLarge(_) | Content::Unavailable => vec![0],
        };
        Ok(Some((oid, mode, content)))
    };
    Ok((side(&repository.snapshot).await?, side(change).await?))
}

fn content(side: &Option<FileSide>) -> Option<&[u8]> {
    side.as_ref().map(|(_, _, content)| content.as_slice())
}

fn as_side(side: &Option<FileSide>) -> Option<patch::Side<'_>> {
    side.as_ref().map(|(oid, mode, content)| patch::Side {
        oid,
        mode: *mode,
        content,
    })
}
