use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::chat::MessageRole;
use crate::dto::chat::MessageStatus;
use crate::dto::chat::ProposedCommitStatus;
use crate::dto::error::ErrorCode;
use crate::model::message::Message;
use crate::model::tool_call::{
    ChangedPaths, FileMove, ProposedChange, ProposedCommit, ToolCall, ToolCallSummary,
};
use crate::repository::{begin_write, violates_unique};
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use sqlx::SqliteConnection;
use sqlx::types::{Json, Text};
use uuid::Uuid;

/// Output stored for tool calls that were still running when their message finished.
const INTERRUPTED_TOOL_CALL_OUTPUT: &str = "The tool call was interrupted";

pub(crate) struct NewMessage<'a> {
    pub id: Uuid,
    pub chat_id: Uuid,
    pub role: MessageRole,
    pub content: &'a str,
    /// The model that writes the answer, `None` for user messages.
    pub model_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

/// The final state of an answer, see [`finish_message`].
pub(crate) struct FinishedMessage<'a> {
    pub status: MessageStatus,
    /// `None` keeps the stored content.
    pub content: Option<&'a str>,
    pub error: Option<&'a str>,
    /// `None` if unknown.
    pub usage: Option<TokenUsage>,
    /// The amount and its currency, `None` if unknown.
    pub cost: Option<(Decimal, &'a str)>,
    pub finished_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct TokenUsage {
    pub input: i64,
    pub output: i64,
    pub cache_read: i64,
    pub cache_write: i64,
}

pub(crate) struct NewToolCall<'a> {
    pub id: Uuid,
    pub message_id: Uuid,
    pub name: &'a str,
    pub input: &'a serde_json::Value,
    pub repository_id: Option<Uuid>,
    pub commit_sha: Option<&'a str>,
    pub created_at: DateTime<Utc>,
}

/// User messages are stored `COMPLETED`, assistant messages `GENERATING`.
/// Fails with `GENERATION_IN_PROGRESS` if the chat already has a `GENERATING` message.
pub(crate) async fn insert_message(
    conn: &mut SqliteConnection,
    new: NewMessage<'_>,
) -> Result<Message, AppError> {
    let status = match new.role {
        MessageRole::User => MessageStatus::Completed,
        MessageRole::Assistant => MessageStatus::Generating,
    };
    let message = sqlx::query_as!(
        Message,
        r#"INSERT INTO messages (id, chat_id, role, content, status, model_id, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id AS "id: Uuid", role AS "role: MessageRole", content,
                     status AS "status: MessageStatus", error, model_id AS "model_id: Uuid",
                     created_at AS "created_at: DateTime<Utc>", finished_at AS "finished_at: DateTime<Utc>",
                     input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
                     cost AS "cost: Text<Decimal>", cost_currency"#,
        new.id,
        new.chat_id,
        new.role,
        new.content,
        status,
        new.model_id,
        new.created_at,
    )
    .fetch_one(conn)
    .await
    .map_err(|e| {
        // idx_messages_generating
        if violates_unique(&e, "messages.chat_id") {
            AppError::Conflict(
                ErrorCode::GenerationInProgress,
                "An answer is already being generated in this chat".to_string(),
            )
        } else {
            AppError::Database(e)
        }
    })?;
    Ok(message)
}

/// The caller must have checked that the chat belongs to the user.
pub(crate) async fn list_messages(
    db: &DatabasePool,
    chat_id: Uuid,
) -> Result<Vec<Message>, AppError> {
    let messages = sqlx::query_as!(
        Message,
        r#"SELECT id AS "id: Uuid", role AS "role: MessageRole", content,
                  status AS "status: MessageStatus", error, model_id AS "model_id: Uuid",
                  created_at AS "created_at: DateTime<Utc>", finished_at AS "finished_at: DateTime<Utc>",
                  input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
                  cost AS "cost: Text<Decimal>", cost_currency
           FROM messages
           WHERE chat_id = $1
           ORDER BY created_at, id"#,
        chat_id,
    )
    .fetch_all(db)
    .await?;
    Ok(messages)
}

pub(crate) async fn get_message(
    db: &DatabasePool,
    user_id: Uuid,
    chat_id: Uuid,
    id: Uuid,
) -> Result<Option<Message>, AppError> {
    let message = sqlx::query_as!(
        Message,
        r#"SELECT m.id AS "id: Uuid", m.role AS "role: MessageRole", m.content,
                  m.status AS "status: MessageStatus", m.error, m.model_id AS "model_id: Uuid",
                  m.created_at AS "created_at: DateTime<Utc>", m.finished_at AS "finished_at: DateTime<Utc>",
                  m.input_tokens, m.output_tokens, m.cache_read_tokens, m.cache_write_tokens,
                  m.cost AS "cost: Text<Decimal>", m.cost_currency
           FROM messages m
           JOIN chats c ON c.id = m.chat_id
           WHERE m.id = $1 AND m.chat_id = $2 AND c.user_id = $3"#,
        id,
        chat_id,
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(message)
}

/// The caller must have checked that the chat belongs to the user.
pub(crate) async fn list_tool_call_summaries(
    db: &DatabasePool,
    chat_id: Uuid,
) -> Result<Vec<ToolCallSummary>, AppError> {
    let tool_calls = sqlx::query_as!(
        ToolCallSummary,
        r#"SELECT t.id AS "id: Uuid", t.message_id AS "message_id: Uuid", t.name,
                  t.input AS "input: serde_json::Value", t.repository_id AS "repository_id: Uuid",
                  t.commit_sha, t.output IS NOT NULL AS "finished!: bool", t.is_error,
                  t.created_at AS "created_at: DateTime<Utc>"
           FROM tool_calls t
           JOIN messages m ON m.id = t.message_id
           WHERE m.chat_id = $1
           ORDER BY t.message_id, t.id"#,
        chat_id,
    )
    .fetch_all(db)
    .await?;
    Ok(tool_calls)
}

pub(crate) async fn list_tool_call_summaries_of_message(
    db: &DatabasePool,
    message_id: Uuid,
) -> Result<Vec<ToolCallSummary>, AppError> {
    let tool_calls = sqlx::query_as!(
        ToolCallSummary,
        r#"SELECT id AS "id: Uuid", message_id AS "message_id: Uuid", name,
                  input AS "input: serde_json::Value", repository_id AS "repository_id: Uuid",
                  commit_sha, output IS NOT NULL AS "finished!: bool", is_error,
                  created_at AS "created_at: DateTime<Utc>"
           FROM tool_calls
           WHERE message_id = $1
           ORDER BY id"#,
        message_id,
    )
    .fetch_all(db)
    .await?;
    Ok(tool_calls)
}

pub(crate) async fn get_tool_call(
    db: &DatabasePool,
    user_id: Uuid,
    chat_id: Uuid,
    id: Uuid,
) -> Result<Option<ToolCall>, AppError> {
    let tool_call = sqlx::query_as!(
        ToolCall,
        r#"SELECT t.id AS "id: Uuid", t.name, t.input AS "input: serde_json::Value", t.output,
                  t.repository_id AS "repository_id: Uuid", t.commit_sha, t.is_error,
                  t.created_at AS "created_at: DateTime<Utc>"
           FROM tool_calls t
           JOIN messages m ON m.id = t.message_id
           JOIN chats c ON c.id = m.chat_id
           WHERE t.id = $1 AND m.chat_id = $2 AND c.user_id = $3"#,
        id,
        chat_id,
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(tool_call)
}

/// Moves a `GENERATING` message to its final state, and marks its running tool calls as
/// interrupted. Returns `None` if the message is gone or no longer `GENERATING`.
pub(crate) async fn finish_message(
    db: &DatabasePool,
    id: Uuid,
    finished: FinishedMessage<'_>,
) -> Result<Option<Message>, AppError> {
    let usage = finished.usage;
    let (cost, cost_currency) = finished.cost.unzip();
    let cost = cost.map(Text);
    let (input_tokens, output_tokens, cache_read_tokens, cache_write_tokens) = (
        usage.map(|u| u.input),
        usage.map(|u| u.output),
        usage.map(|u| u.cache_read),
        usage.map(|u| u.cache_write),
    );
    let mut tx = begin_write(db).await?;
    let message = sqlx::query_as!(
        Message,
        r#"UPDATE messages
           SET status             = $2,
               content            = COALESCE($3, content),
               error              = $4,
               finished_at        = $5,
               input_tokens       = $6,
               output_tokens      = $7,
               cache_read_tokens  = $8,
               cache_write_tokens = $9,
               cost               = $10,
               cost_currency      = $11
           WHERE id = $1 AND status = 'GENERATING'
           RETURNING id AS "id: Uuid", role AS "role: MessageRole", content,
                     status AS "status: MessageStatus", error, model_id AS "model_id: Uuid",
                     created_at AS "created_at: DateTime<Utc>", finished_at AS "finished_at: DateTime<Utc>",
                     input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
                     cost AS "cost: Text<Decimal>", cost_currency"#,
        id,
        finished.status,
        finished.content,
        finished.error,
        finished.finished_at,
        input_tokens,
        output_tokens,
        cache_read_tokens,
        cache_write_tokens,
        cost,
        cost_currency,
    )
    .fetch_optional(&mut *tx)
    .await?;
    if message.is_some() {
        sqlx::query!(
            "UPDATE tool_calls SET output = $2, is_error = true WHERE message_id = $1 AND output IS NULL",
            id,
            INTERRUPTED_TOOL_CALL_OUTPUT,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(message)
}

/// Fails all `GENERATING` messages. Only safe at startup, before any generation runs.
pub(crate) async fn fail_interrupted_messages(
    db: &DatabasePool,
    error: &str,
) -> Result<u64, AppError> {
    let mut tx = begin_write(db).await?;
    sqlx::query!(
        r#"UPDATE tool_calls SET output = $1, is_error = true
           WHERE output IS NULL
             AND message_id IN (SELECT id FROM messages WHERE status = 'GENERATING')"#,
        INTERRUPTED_TOOL_CALL_OUTPUT,
    )
    .execute(&mut *tx)
    .await?;
    let result = sqlx::query!(
        "UPDATE messages SET status = 'FAILED', error = $1 WHERE status = 'GENERATING'",
        error,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(result.rows_affected())
}

/// Returns `false` if the message is no longer `GENERATING`. SQLite runs one write at a time,
/// so the insert cannot race with [`finish_message`] and leave a running tool call behind.
pub(crate) async fn insert_tool_call(
    db: &DatabasePool,
    new: NewToolCall<'_>,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        r#"INSERT INTO tool_calls (id, message_id, name, input, repository_id, commit_sha, is_error, created_at)
           SELECT $1, m.id, $3, $4, $5, $6, false, $7
           FROM messages m
           WHERE m.id = $2 AND m.status = 'GENERATING'"#,
        new.id,
        new.message_id,
        new.name,
        new.input,
        new.repository_id,
        new.commit_sha,
        new.created_at,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Stores the output, and the commit a call like `change_file` proposed. Returns `false` if the
/// tool call is gone or already finished (e.g. interrupted).
pub(crate) async fn finish_tool_call(
    db: &DatabasePool,
    id: Uuid,
    output: &str,
    is_error: bool,
    change: Option<&ProposedChange>,
) -> Result<bool, AppError> {
    let mut tx = begin_write(db).await?;
    let result = sqlx::query!(
        "UPDATE tool_calls SET output = $2, is_error = $3 WHERE id = $1 AND output IS NULL",
        id,
        output,
        is_error,
    )
    .execute(&mut *tx)
    .await?;
    if result.rows_affected() == 0 {
        return Ok(false);
    }
    if let Some(change) = change {
        let (path, moves) = match &change.changed {
            ChangedPaths::File(path) => (Some(path), None),
            ChangedPaths::Moves(moves) => (None, Some(Json(moves))),
        };
        sqlx::query!(
            "INSERT INTO proposed_commits (tool_call_id, path, moves, proposed_commit, status) VALUES ($1, $2, $3, $4, 'PROPOSED')",
            id,
            path,
            moves,
            change.proposed_commit,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(true)
}

/// The commit the `change_file`, `save_attachment` or `move_files` call `tool_call_id`
/// proposed, if it succeeded.
pub(crate) async fn get_proposed_commit(
    db: &DatabasePool,
    tool_call_id: Uuid,
) -> Result<Option<ProposedCommit>, AppError> {
    let Some(row) = sqlx::query!(
        r#"SELECT path, moves AS "moves: Json<Vec<FileMove>>", proposed_commit,
                  status AS "status: ProposedCommitStatus", pushed_commit, pushed_branch, error,
                  committed_at AS "committed_at: DateTime<Utc>"
           FROM proposed_commits WHERE tool_call_id = $1"#,
        tool_call_id,
    )
    .fetch_optional(db)
    .await?
    else {
        return Ok(None);
    };
    let changed = match (row.path, row.moves) {
        (Some(path), None) => ChangedPaths::File(path),
        (None, Some(Json(moves))) => ChangedPaths::Moves(moves),
        _ => {
            return Err(AppError::InternalServerError(format!(
                "File change {tool_call_id} has both or neither a path and moves"
            )));
        }
    };
    Ok(Some(ProposedCommit {
        changed,
        proposed_commit: row.proposed_commit,
        status: row.status,
        pushed_commit: row.pushed_commit,
        pushed_branch: row.pushed_branch,
        error: row.error,
        committed_at: row.committed_at,
    }))
}

/// How an attempt to commit a [`ProposedCommit`] ended.
pub(crate) enum CommitOutcome<'a> {
    Committed { commit: &'a str, branch: &'a str },
    Conflict(&'a str),
    Failed(&'a str),
}

/// Stores how the attempt to commit the change of `tool_call_id` ended, unless it was
/// committed already, e.g. by a concurrent request. Returns the change as it is now.
pub(crate) async fn finish_commit(
    db: &DatabasePool,
    tool_call_id: Uuid,
    outcome: CommitOutcome<'_>,
) -> Result<Option<ProposedCommit>, AppError> {
    let (status, pushed_commit, pushed_branch, error) = match outcome {
        CommitOutcome::Committed { commit, branch } => (
            ProposedCommitStatus::Committed,
            Some(commit),
            Some(branch),
            None,
        ),
        CommitOutcome::Conflict(error) => (ProposedCommitStatus::Conflict, None, None, Some(error)),
        CommitOutcome::Failed(error) => (ProposedCommitStatus::Failed, None, None, Some(error)),
    };
    let committed_at = pushed_commit.map(|_| Utc::now());
    sqlx::query!(
        r#"UPDATE proposed_commits
           SET status = $2, pushed_commit = $3, pushed_branch = $4, error = $5, committed_at = $6
           WHERE tool_call_id = $1 AND status != 'COMMITTED'"#,
        tool_call_id,
        status,
        pushed_commit,
        pushed_branch,
        error,
        committed_at,
    )
    .execute(db)
    .await?;
    get_proposed_commit(db, tool_call_id).await
}
