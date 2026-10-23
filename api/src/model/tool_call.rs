use crate::dto::chat::ProposedCommitStatus;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct ToolCall {
    pub id: Uuid,
    pub name: String,
    pub input: serde_json::Value,
    pub output: Option<String>,
    pub repository_id: Option<Uuid>,
    pub commit_sha: Option<String>,
    pub is_error: bool,
    pub created_at: DateTime<Utc>,
}

/// A file or directory that a `move_files` call moves.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileMove {
    pub from: String,
    /// The new path of the file or directory itself.
    pub to: String,
}

/// What a proposed commit changes.
#[derive(Debug, PartialEq, Eq)]
pub enum ChangedPaths {
    /// One file, changed, created or deleted by `change_file` or `save_attachment`.
    File(String),
    /// Files and directories moved by `move_files`, none inside another's paths.
    Moves(Vec<FileMove>),
}

impl ChangedPaths {
    /// The paths whose entries the commit changes: the file, or the source and destination of
    /// each move.
    pub fn paths(&self) -> Vec<String> {
        match self {
            ChangedPaths::File(path) => vec![path.clone()],
            ChangedPaths::Moves(moves) => moves
                .iter()
                .flat_map(|m| [m.from.clone(), m.to.clone()])
                .collect(),
        }
    }
}

/// The commit a successful `change_file`, `save_attachment` or `move_files` call proposed, on
/// top of the call's `commit_sha`.
#[derive(Debug)]
pub struct ProposedChange {
    pub changed: ChangedPaths,
    pub proposed_commit: String,
}

/// A [`ProposedChange`] as stored in `proposed_commits`, and whether it was committed.
#[derive(Debug)]
pub struct ProposedCommit {
    pub changed: ChangedPaths,
    pub proposed_commit: String,
    pub status: ProposedCommitStatus,
    /// Once committed: `proposed_commit`, or the same change on top of the branch's newer head.
    pub pushed_commit: Option<String>,
    pub pushed_branch: Option<String>,
    /// Why the last attempt to commit failed.
    pub error: Option<String>,
    pub committed_at: Option<DateTime<Utc>>,
}

/// A tool call without its output, which can be large (e.g. whole files).
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ToolCallSummary {
    pub id: Uuid,
    pub message_id: Uuid,
    pub name: String,
    pub input: serde_json::Value,
    pub repository_id: Option<Uuid>,
    pub commit_sha: Option<String>,
    /// `false` while the tool is running.
    pub finished: bool,
    pub is_error: bool,
    pub created_at: DateTime<Utc>,
}
