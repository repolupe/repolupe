//! Chats, their messages and the tool calls of the answers.

use crate::dto::attachment::AttachmentDto;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Eq, PartialEq, Debug, Hash, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum MessageRole {
    User,
    Assistant,
}

#[derive(Clone, Copy, Eq, PartialEq, Debug, Hash, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum MessageStatus {
    Generating,
    Completed,
    Failed,
    Cancelled,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// How far a change proposed with `change_file`, `save_attachment` or `move_files` got.
#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ProposedCommitStatus {
    Proposed,
    /// Pushed to the branch.
    Committed,
    /// The paths it changes changed on the branch since the commit the change was based on.
    Conflict,
    /// The push failed, e.g. the remote refused it.
    Failed,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

#[derive(Serialize, Deserialize)]
pub struct ChatDto {
    pub id: Uuid,
    pub title: String,
    pub all_repositories: bool,
    /// Empty if `all_repositories` is true.
    pub repository_ids: Vec<Uuid>,
    /// `null` uses the user's model.
    pub model_id: Option<Uuid>,
    /// Not listed in `GET /api/v1/chats`, and deleted a day after its last message.
    pub temporary: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct ChatPageDto {
    pub items: Vec<ChatDto>,
    /// Pass as `cursor` to get the next page, `null` on the last page.
    pub next_cursor: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct ChatDetailDto {
    #[serde(flatten)]
    pub chat: ChatDto,
    pub messages: Vec<MessageDto>,
}

#[derive(Serialize, Deserialize)]
pub struct MessageDto {
    pub id: Uuid,
    pub role: MessageRole,
    /// Partial while `GENERATING`, and after `FAILED` or `CANCELLED`.
    pub content: String,
    pub status: MessageStatus,
    pub error: Option<String>,
    /// The model that wrote the answer, `null` for user messages or if the model was deleted.
    pub model_id: Option<Uuid>,
    pub tool_calls: Vec<ToolCallSummaryDto>,
    pub created_at: DateTime<Utc>,
    /// When the answer reached its final status, `null` for user messages, while `GENERATING`,
    /// or if it was interrupted by a restart.
    pub finished_at: Option<DateTime<Utc>>,
    /// Tokens used for the answer, `null` for user messages, while `GENERATING`, or if unknown.
    pub usage: Option<UsageDto>,
    /// At the prices when the answer finished, `null` if the model had no prices or the usage
    /// is unknown.
    pub cost: Option<CostDto>,
    /// The file sent with a user message, `null` if none.
    pub attachment: Option<AttachmentDto>,
}

#[derive(Serialize, Deserialize)]
pub struct UsageDto {
    /// Not read from or written to the cache.
    pub input_tokens: i64,
    pub output_tokens: i64,
    pub cache_read_tokens: i64,
    pub cache_write_tokens: i64,
}

#[derive(Serialize, Deserialize)]
pub struct CostDto {
    /// A decimal string, unrounded.
    pub amount: String,
    /// ISO 4217 code, e.g. `USD`.
    pub currency: String,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ToolCallStatus {
    Running,
    Completed,
    Failed,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// A tool call without its output, see [`ToolCallDto`].
#[derive(Serialize, Deserialize)]
pub struct ToolCallSummaryDto {
    pub id: Uuid,
    pub name: String,
    /// The JSON object the model called the tool with, as its text. In the API it is the
    /// object itself.
    #[serde(with = "json_text")]
    pub input: String,
    /// `null` for tools not bound to one repository, or if the repository was deleted.
    pub repository_id: Option<Uuid>,
    pub commit_sha: Option<String>,
    pub status: ToolCallStatus,
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct ToolCallDto {
    #[serde(flatten)]
    pub summary: ToolCallSummaryDto,
    /// `null` while running.
    pub output: Option<String>,
}

/// The change a successful `change_file`, `save_attachment` or `move_files` call proposed, and
/// whether it was committed.
#[derive(Serialize, Deserialize)]
pub struct ProposedCommitDto {
    /// The file `change_file` or `save_attachment` changes, `null` for `move_files`.
    pub path: Option<String>,
    /// What `move_files` moves, `null` for the other tools.
    pub moves: Option<Vec<FileMoveDto>>,
    /// The proposed commit, on top of the tool call's `commit_sha`. Only in the server's
    /// mirror, see `.../patch`.
    pub proposed_commit: String,
    pub status: ProposedCommitStatus,
    /// Once `COMMITTED`: the commit on the branch, `proposed_commit` or the same change on top of
    /// the newer commit the branch had moved to.
    pub pushed_commit: Option<String>,
    pub pushed_branch: Option<String>,
    /// Why the last attempt failed, set while `CONFLICT` or `FAILED`.
    pub error: Option<String>,
    pub committed_at: Option<DateTime<Utc>>,
    /// Whether the user may commit it: they own the repository, which allows commits, and
    /// may manage repositories.
    pub can_commit: bool,
}

/// A file or folder moved by `move_files`.
#[derive(Serialize, Deserialize)]
pub struct FileMoveDto {
    pub from: String,
    /// The new path of the file or folder itself.
    pub to: String,
}

/// The change a successful `change_file`, `save_attachment` or `move_files` call proposed, as
/// it is shown to the user: the diff of the file with the changed words marked, or the moves.
#[derive(Serialize, Deserialize)]
pub struct FileDiffDto {
    /// `MODIFIED` for moves.
    pub kind: DiffFileKind,
    /// Empty for files without a text diff (binary files, PDFs) and for moves.
    pub hunks: Vec<DiffHunkDto>,
    /// What `move_files` moves, `null` for the other tools.
    pub moves: Option<Vec<DiffMoveDto>>,
}

/// What a change does to its file.
#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DiffFileKind {
    Modified,
    Added,
    Deleted,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// Changed lines with up to 3 unchanged lines around them.
#[derive(Serialize, Deserialize)]
pub struct DiffHunkDto {
    /// Whether unchanged lines were left out before it.
    pub skipped: bool,
    pub lines: Vec<DiffLineDto>,
}

#[derive(Serialize, Deserialize)]
pub struct DiffLineDto {
    pub kind: DiffLineKind,
    /// The text of the line without its line break, in pieces; the pieces that differ from the
    /// line's counterpart in the other version are `changed`.
    pub parts: Vec<DiffPartDto>,
}

#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DiffLineKind {
    Context,
    Removed,
    Added,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

#[derive(Serialize, Deserialize)]
pub struct DiffPartDto {
    pub text: String,
    pub changed: bool,
}

/// A file or folder moved by `move_files`.
#[derive(Serialize, Deserialize)]
pub struct DiffMoveDto {
    pub from: String,
    /// The new path of the file or folder itself.
    pub to: String,
    /// How many files the folder holds, `null` if it is a file.
    pub folder_files: Option<i64>,
}

#[derive(Serialize, Deserialize)]
pub struct ListChatsQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct CreateChatRequest {
    /// The first message, may be blank with an attachment.
    pub content: String,
    /// An attachment uploaded with `POST /api/v1/attachments`, sent with the message.
    #[serde(default)]
    pub attachment_id: Option<Uuid>,
    pub all_repositories: bool,
    #[serde(default)]
    pub repository_ids: Option<Vec<Uuid>>,
    /// Derived from `content` if absent or blank.
    pub title: Option<String>,
    /// Absent or `null` uses the user's model.
    #[serde(default)]
    pub model_id: Option<Uuid>,
    /// Not listed, and deleted a day after its last message. Cannot be changed later.
    #[serde(default)]
    pub temporary: bool,
    /// The user's offset from UTC in minutes, e.g. 60 for UTC+01:00, so the model knows their
    /// local time. Absent uses UTC.
    #[serde(default)]
    pub utc_offset_minutes: Option<i32>,
}

/// Replaces the title and the model. `model_id` absent or `null` uses the user's model.
#[derive(Serialize, Deserialize)]
pub struct UpdateChatRequest {
    pub title: String,
    #[serde(default)]
    pub model_id: Option<Uuid>,
}

#[derive(Serialize, Deserialize)]
pub struct SendMessageRequest {
    /// May be blank with an attachment.
    pub content: String,
    /// An attachment uploaded with `POST /api/v1/attachments`, sent with the message.
    #[serde(default)]
    pub attachment_id: Option<Uuid>,
    /// The user's offset from UTC in minutes, e.g. 60 for UTC+01:00, so the model knows their
    /// local time. Absent uses UTC.
    #[serde(default)]
    pub utc_offset_minutes: Option<i32>,
}

#[derive(Serialize, Deserialize)]
pub struct RetryMessageRequest {
    /// The user's offset from UTC in minutes, e.g. 60 for UTC+01:00, so the model knows their
    /// local time. Absent uses UTC.
    #[serde(default)]
    pub utc_offset_minutes: Option<i32>,
}

/// The `content_delta` event of `GET .../messages/{id}/stream`.
#[derive(Serialize, Deserialize)]
pub struct ContentDeltaDto {
    pub text: String,
}

/// The `tool_call_finished` event of `GET .../messages/{id}/stream`.
#[derive(Serialize, Deserialize)]
pub struct ToolCallFinishedDto {
    pub id: Uuid,
    pub status: ToolCallStatus,
}

/// Serializes a JSON text as the value it holds, and a value as its text.
mod json_text {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};

    pub(super) fn serialize<S: Serializer>(text: &str, serializer: S) -> Result<S::Ok, S::Error> {
        let value: serde_json::Value =
            serde_json::from_str(text).map_err(serde::ser::Error::custom)?;
        value.serialize(serializer)
    }

    pub(super) fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<String, D::Error> {
        serde_json::Value::deserialize(deserializer).map(|value| value.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn tool_call_input_is_an_object_in_json() {
        let tool_call = ToolCallSummaryDto {
            id: Uuid::nil(),
            name: "read_file".to_string(),
            input: r#"{"path":"README.md"}"#.to_string(),
            repository_id: None,
            commit_sha: None,
            status: ToolCallStatus::Completed,
            created_at: DateTime::UNIX_EPOCH,
        };
        let value = serde_json::to_value(&tool_call).unwrap();
        assert_eq!(value["input"], json!({"path": "README.md"}));

        let parsed: ToolCallSummaryDto = serde_json::from_value(value).unwrap();
        assert_eq!(parsed.input, r#"{"path":"README.md"}"#);
    }
}
