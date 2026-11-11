use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::chat::MessageRole;
use crate::dto::chat::MessageStatus;
use crate::dto::error::ErrorCode;
use crate::model::attachment::Attachment;
use crate::model::chat::Chat;
use crate::model::message::Message;
use crate::repository::attachment::{get_message_attachment, send_attachment};
use crate::repository::begin_write;
use crate::repository::message::{MessageModel, NewMessage, insert_message};
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use sqlx::types::{Json, Text};
use sqlx::{SqliteConnection, SqliteExecutor};
use uuid::Uuid;

/// Which repositories a chat can read from, or which MCP servers it gets the tools of.
pub(crate) enum Scope {
    /// All the user can use, including ones added later.
    All,
    /// Deduplicated, may be empty.
    Selected(Vec<Uuid>),
}

/// Position after the last chat of a page, in `updated_at DESC, id DESC` order.
pub(crate) struct ChatCursor {
    pub updated_at: DateTime<Utc>,
    pub id: Uuid,
}

pub(crate) struct NewChat<'a> {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: &'a str,
    pub repositories: &'a Scope,
    pub mcp_servers: &'a Scope,
    /// Chosen for the chat, `None` uses the user's model.
    pub model_id: Option<Uuid>,
    pub temporary: bool,
    pub content: &'a str,
    /// An unsent attachment of the user, sent with the first message.
    pub attachment_id: Option<Uuid>,
    pub user_message_id: Uuid,
    pub assistant_message_id: Uuid,
    /// The model that writes the first answer.
    pub answer_model: MessageModel<'a>,
    pub created_at: DateTime<Utc>,
}

/// The repositories and MCP servers of a chat cannot be changed.
pub(crate) struct ChatChanges<'a> {
    pub title: &'a str,
    pub model_id: Option<Uuid>,
}

/// The user's message and the ids of the messages to insert.
pub(crate) struct NewExchange<'a> {
    pub content: &'a str,
    /// An unsent attachment of the user, sent with the message.
    pub attachment_id: Option<Uuid>,
    pub user_message_id: Uuid,
    pub assistant_message_id: Uuid,
    /// The model that writes the answer.
    pub model: MessageModel<'a>,
    pub created_at: DateTime<Utc>,
}

/// The messages inserted for a question.
pub(crate) struct Exchange {
    pub user_message: Message,
    /// `GENERATING`.
    pub assistant_message: Message,
    /// Sent with the user message.
    pub attachment: Option<Attachment>,
}

/// A user message to ask again, see [`resend_message`].
pub(crate) struct Resend<'a> {
    pub message_id: Uuid,
    /// Replaces the text of the message, `None` keeps it.
    pub content: Option<&'a str>,
    pub assistant_message_id: Uuid,
    /// The model that writes the answer.
    pub model: MessageModel<'a>,
    pub created_at: DateTime<Utc>,
}

pub(crate) async fn list_chats(
    db: &DatabasePool,
    user_id: Uuid,
    after: Option<&ChatCursor>,
    limit: i64,
) -> Result<Vec<Chat>, AppError> {
    let after_updated_at = after.map(|c| c.updated_at);
    let after_id = after.map(|c| c.id);
    let chats = sqlx::query_as!(
        Chat,
        r#"SELECT c.id AS "id: Uuid", c.title, c.all_repositories,
                  (SELECT json_group_array(lower(hex(cr.repository_id)) ORDER BY cr.repository_id)
                   FROM chat_repositories cr
                   WHERE cr.chat_id = c.id) AS "repository_ids!: Json<Vec<Uuid>>",
                  c.all_mcp_servers,
                  (SELECT json_group_array(lower(hex(cm.mcp_server_id)) ORDER BY cm.mcp_server_id)
                   FROM chat_mcp_servers cm
                   WHERE cm.chat_id = c.id) AS "mcp_server_ids!: Json<Vec<Uuid>>",
                  c.model_id AS "model_id: Uuid", c.temporary, c.created_at AS "created_at: DateTime<Utc>",
                  c.updated_at AS "updated_at: DateTime<Utc>"
           FROM chats c
           WHERE c.user_id = $1
             AND NOT c.temporary
             AND ($2 IS NULL OR (c.updated_at, c.id) < ($2, $3))
           ORDER BY c.updated_at DESC, c.id DESC
           LIMIT $4"#,
        user_id,
        after_updated_at,
        after_id,
        limit,
    )
    .fetch_all(db)
    .await?;
    Ok(chats)
}

/// Like [`list_chats`], but only the chats in which each of `words` occurs in the title or in a
/// message. SQLite's `LIKE` ignores the case of ASCII letters only.
pub(crate) async fn search_chats(
    db: &DatabasePool,
    user_id: Uuid,
    words: &[&str],
    after: Option<&ChatCursor>,
    limit: i64,
) -> Result<Vec<Chat>, AppError> {
    let patterns = Json(
        words
            .iter()
            .map(|word| format!("%{}%", escape_like(word)))
            .collect::<Vec<_>>(),
    );
    let after_updated_at = after.map(|c| c.updated_at);
    let after_id = after.map(|c| c.id);
    let chats = sqlx::query_as!(
        Chat,
        r#"SELECT c.id AS "id: Uuid", c.title, c.all_repositories,
                  (SELECT json_group_array(lower(hex(cr.repository_id)) ORDER BY cr.repository_id)
                   FROM chat_repositories cr
                   WHERE cr.chat_id = c.id) AS "repository_ids!: Json<Vec<Uuid>>",
                  c.all_mcp_servers,
                  (SELECT json_group_array(lower(hex(cm.mcp_server_id)) ORDER BY cm.mcp_server_id)
                   FROM chat_mcp_servers cm
                   WHERE cm.chat_id = c.id) AS "mcp_server_ids!: Json<Vec<Uuid>>",
                  c.model_id AS "model_id: Uuid", c.temporary, c.created_at AS "created_at: DateTime<Utc>",
                  c.updated_at AS "updated_at: DateTime<Utc>"
           FROM chats c
           WHERE c.user_id = $1
             AND NOT c.temporary
             AND ($2 IS NULL OR (c.updated_at, c.id) < ($2, $3))
             AND NOT EXISTS (SELECT 1
                             FROM json_each($4) w
                             WHERE c.title NOT LIKE w.value ESCAPE '\'
                               AND NOT EXISTS (SELECT 1
                                               FROM messages m
                                               WHERE m.chat_id = c.id
                                                 AND m.content LIKE w.value ESCAPE '\'))
           ORDER BY c.updated_at DESC, c.id DESC
           LIMIT $5"#,
        user_id,
        after_updated_at,
        after_id,
        patterns,
        limit,
    )
    .fetch_all(db)
    .await?;
    Ok(chats)
}

/// Escapes the wildcards of `LIKE ... ESCAPE '\'`.
fn escape_like(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    for c in text.chars() {
        if matches!(c, '\\' | '%' | '_') {
            escaped.push('\\');
        }
        escaped.push(c);
    }
    escaped
}

pub(crate) async fn get_chat(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<Option<Chat>, AppError> {
    fetch_chat(db, user_id, id).await
}

/// Inserts the chat together with its first exchange: the user's message
/// and the `GENERATING` answer. Fails with `UNKNOWN_MODEL` if `model_id` does not exist.
pub(crate) async fn create_chat(
    db: &DatabasePool,
    new: NewChat<'_>,
) -> Result<(Chat, Exchange), AppError> {
    let all_repositories = matches!(new.repositories, Scope::All);
    let all_mcp_servers = matches!(new.mcp_servers, Scope::All);
    let mut tx = begin_write(db).await?;
    sqlx::query!(
        r#"INSERT INTO chats (id, user_id, title, all_repositories, all_mcp_servers, model_id, temporary, created_at,
                              updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)"#,
        new.id,
        new.user_id,
        new.title,
        all_repositories,
        all_mcp_servers,
        new.model_id,
        new.temporary,
        new.created_at,
    )
    .execute(&mut *tx)
    .await
    .map_err(map_unknown_model)?;
    if let Scope::Selected(ids) = new.repositories {
        link_repositories(&mut tx, new.user_id, new.id, ids).await?;
    }
    if let Scope::Selected(ids) = new.mcp_servers {
        link_mcp_servers(&mut tx, new.user_id, new.id, ids).await?;
    }

    let exchange = insert_exchange(
        &mut tx,
        new.user_id,
        new.id,
        NewExchange {
            content: new.content,
            attachment_id: new.attachment_id,
            user_message_id: new.user_message_id,
            assistant_message_id: new.assistant_message_id,
            model: new.answer_model,
            created_at: new.created_at,
        },
    )
    .await?;

    let chat = fetch_chat(&mut *tx, new.user_id, new.id)
        .await?
        .ok_or_else(|| AppError::InternalServerError(format!("Chat {} vanished", new.id)))?;
    tx.commit().await?;
    Ok((chat, exchange))
}

/// Does not bump `updated_at`, which only tracks new messages. Fails with `UNKNOWN_MODEL`
/// if `model_id` does not exist. Returns `None` if the chat does not exist.
pub(crate) async fn update_chat(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
    changes: ChatChanges<'_>,
) -> Result<Option<Chat>, AppError> {
    let result = sqlx::query!(
        "UPDATE chats SET title = $3, model_id = $4 WHERE id = $1 AND user_id = $2",
        id,
        user_id,
        changes.title,
        changes.model_id,
    )
    .execute(db)
    .await
    .map_err(map_unknown_model)?;
    if result.rows_affected() == 0 {
        return Ok(None);
    }
    fetch_chat(db, user_id, id).await
}

/// Returns `false` if the user has no chat with this id.
pub(crate) async fn delete_chat(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "DELETE FROM chats WHERE id = $1 AND user_id = $2",
        id,
        user_id,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Deletes the temporary chats without a new message since `before`, except those still
/// generating an answer. Returns how many were deleted.
pub(crate) async fn delete_expired_temporary_chats(
    db: &DatabasePool,
    before: DateTime<Utc>,
) -> Result<u64, AppError> {
    let result = sqlx::query!(
        r#"DELETE FROM chats
           WHERE temporary
             AND updated_at < $1
             AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.chat_id = chats.id AND m.status = 'GENERATING')"#,
        before,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected())
}

/// Adds the user's message and the `GENERATING` answer, and bumps `updated_at`.
/// Returns `None` if the chat does not exist.
pub(crate) async fn add_exchange(
    db: &DatabasePool,
    user_id: Uuid,
    chat_id: Uuid,
    exchange: NewExchange<'_>,
) -> Result<Option<Exchange>, AppError> {
    let mut tx = begin_write(db).await?;
    if !has_chat(&mut tx, user_id, chat_id).await? {
        return Ok(None);
    }
    let exchange = insert_exchange(&mut tx, user_id, chat_id, exchange).await?;
    tx.commit().await?;
    Ok(Some(exchange))
}

/// Asks a message of the user again: removes every message after it, adds a `GENERATING`
/// answer, and bumps `updated_at`. The message is sent at `created_at` from then on, and keeps
/// its attachment. Returns `None` if the chat or the message does not exist, or if it is an
/// answer. Fails with `GENERATION_IN_PROGRESS` while an answer is generated in the chat, so
/// that none is removed while it is still written.
pub(crate) async fn resend_message(
    db: &DatabasePool,
    user_id: Uuid,
    chat_id: Uuid,
    resend: Resend<'_>,
) -> Result<Option<Exchange>, AppError> {
    let Resend {
        message_id,
        content,
        assistant_message_id,
        model,
        created_at,
    } = resend;
    let mut tx = begin_write(db).await?;
    if !has_chat(&mut tx, user_id, chat_id).await? {
        return Ok(None);
    }
    let generating = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM messages WHERE chat_id = $1 AND status = 'GENERATING') AS "generating!: bool""#,
        chat_id,
    )
    .fetch_one(&mut *tx)
    .await?;
    if generating {
        return Err(AppError::Conflict(
            ErrorCode::GenerationInProgress,
            "An answer is already being generated in this chat".to_string(),
        ));
    }

    // Before the message is dated anew, which would also put it after the answers to remove
    let removed = sqlx::query!(
        r#"DELETE FROM messages
           WHERE chat_id = $2
             AND (created_at, id) > (SELECT m.created_at, m.id
                                     FROM messages m
                                     WHERE m.id = $1 AND m.chat_id = $2 AND m.role = 'USER')"#,
        message_id,
        chat_id,
    )
    .execute(&mut *tx)
    .await?;
    let user_message = sqlx::query_as!(
        Message,
        r#"UPDATE messages
           SET content = COALESCE($3, content), created_at = $4
           WHERE id = $1 AND chat_id = $2 AND role = 'USER'
           RETURNING id AS "id: Uuid", role AS "role: MessageRole", content,
                     status AS "status: MessageStatus", error, model_id AS "model_id: Uuid", model_name,
                     created_at AS "created_at: DateTime<Utc>", finished_at AS "finished_at: DateTime<Utc>",
                     input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, response_ms,
                     cost AS "cost: Text<Decimal>", cost_currency, input_price AS "input_price: Text<Decimal>",
                     output_price AS "output_price: Text<Decimal>",
                     cache_read_price AS "cache_read_price: Text<Decimal>",
                     cache_write_price AS "cache_write_price: Text<Decimal>""#,
        message_id,
        chat_id,
        content,
        created_at,
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(user_message) = user_message else {
        // Nothing was removed either, the subquery had no row to compare with
        debug_assert_eq!(removed.rows_affected(), 0);
        return Ok(None);
    };

    let assistant_message = insert_message(
        &mut tx,
        NewMessage {
            id: assistant_message_id,
            chat_id,
            role: MessageRole::Assistant,
            content: "",
            model: Some(model),
            created_at,
        },
    )
    .await?;
    let attachment = get_message_attachment(&mut *tx, message_id).await?;
    bump_updated_at(&mut tx, chat_id, created_at).await?;
    tx.commit().await?;
    Ok(Some(Exchange {
        user_message,
        assistant_message,
        attachment,
    }))
}

async fn fetch_chat<'e>(
    executor: impl SqliteExecutor<'e>,
    user_id: Uuid,
    id: Uuid,
) -> Result<Option<Chat>, AppError> {
    let chat = sqlx::query_as!(
        Chat,
        r#"SELECT c.id AS "id: Uuid", c.title, c.all_repositories,
                  (SELECT json_group_array(lower(hex(cr.repository_id)) ORDER BY cr.repository_id)
                   FROM chat_repositories cr
                   WHERE cr.chat_id = c.id) AS "repository_ids!: Json<Vec<Uuid>>",
                  c.all_mcp_servers,
                  (SELECT json_group_array(lower(hex(cm.mcp_server_id)) ORDER BY cm.mcp_server_id)
                   FROM chat_mcp_servers cm
                   WHERE cm.chat_id = c.id) AS "mcp_server_ids!: Json<Vec<Uuid>>",
                  c.model_id AS "model_id: Uuid", c.temporary, c.created_at AS "created_at: DateTime<Utc>",
                  c.updated_at AS "updated_at: DateTime<Utc>"
           FROM chats c
           WHERE c.id = $1 AND c.user_id = $2"#,
        id,
        user_id,
    )
    .fetch_optional(executor)
    .await?;
    Ok(chat)
}

/// Whether the user has the chat. Concurrent sends and resends within one chat are serialized
/// by [`begin_write`].
async fn has_chat(conn: &mut SqliteConnection, user_id: Uuid, id: Uuid) -> Result<bool, AppError> {
    let row = sqlx::query!(
        r#"SELECT id AS "id: Uuid" FROM chats WHERE id = $1 AND user_id = $2"#,
        id,
        user_id,
    )
    .fetch_optional(conn)
    .await?;
    Ok(row.is_some())
}

/// Fails with `UNKNOWN_REPOSITORY` unless every id is a repository the user owns or that is
/// shared with them.
async fn link_repositories(
    conn: &mut SqliteConnection,
    user_id: Uuid,
    chat_id: Uuid,
    repository_ids: &[Uuid],
) -> Result<(), AppError> {
    let repository_ids_json = Json(repository_ids);
    let result = sqlx::query!(
        r#"INSERT INTO chat_repositories (chat_id, repository_id)
           SELECT $1, r.id
           FROM repositories r
           WHERE r.id IN (SELECT unhex(value, '-') FROM json_each($3))
             AND (r.user_id = $2
                  OR EXISTS (SELECT 1 FROM repository_users ru WHERE ru.repository_id = r.id AND ru.user_id = $2))"#,
        chat_id,
        user_id,
        repository_ids_json,
    )
    .execute(conn)
    .await?;
    if result.rows_affected() != repository_ids.len() as u64 {
        return Err(AppError::Unprocessable(
            ErrorCode::UnknownRepository,
            "One or more repositories do not exist".to_string(),
        ));
    }
    Ok(())
}

/// Fails with `UNKNOWN_MCP_SERVER` unless every id is an MCP server the user owns or that is
/// shared with them, turned on or not.
async fn link_mcp_servers(
    conn: &mut SqliteConnection,
    user_id: Uuid,
    chat_id: Uuid,
    mcp_server_ids: &[Uuid],
) -> Result<(), AppError> {
    let mcp_server_ids_json = Json(mcp_server_ids);
    let result = sqlx::query!(
        r#"INSERT INTO chat_mcp_servers (chat_id, mcp_server_id)
           SELECT $1, s.id
           FROM mcp_servers s
           WHERE s.id IN (SELECT unhex(value, '-') FROM json_each($3))
             AND (s.user_id = $2
                  OR s.id IN (SELECT mcp_server_id FROM mcp_server_users WHERE user_id = $2))"#,
        chat_id,
        user_id,
        mcp_server_ids_json,
    )
    .execute(conn)
    .await?;
    if result.rows_affected() != mcp_server_ids.len() as u64 {
        return Err(AppError::Unprocessable(
            ErrorCode::UnknownMcpServer,
            "One or more MCP servers do not exist".to_string(),
        ));
    }
    Ok(())
}

/// Both messages share `created_at`, so the order relies on the v7 ids. Fails with
/// `UNKNOWN_ATTACHMENT` if the attachment is not an unsent one of `user_id`.
async fn insert_exchange(
    conn: &mut SqliteConnection,
    user_id: Uuid,
    chat_id: Uuid,
    exchange: NewExchange<'_>,
) -> Result<Exchange, AppError> {
    let user_message = insert_message(
        conn,
        NewMessage {
            id: exchange.user_message_id,
            chat_id,
            role: MessageRole::User,
            content: exchange.content,
            model: None,
            created_at: exchange.created_at,
        },
    )
    .await?;
    let assistant_message = insert_message(
        conn,
        NewMessage {
            id: exchange.assistant_message_id,
            chat_id,
            role: MessageRole::Assistant,
            content: "",
            model: Some(exchange.model),
            created_at: exchange.created_at,
        },
    )
    .await?;
    let attachment = match exchange.attachment_id {
        Some(id) => {
            Some(send_attachment(conn, user_id, id, chat_id, exchange.user_message_id).await?)
        }
        None => None,
    };
    bump_updated_at(conn, chat_id, exchange.created_at).await?;
    Ok(Exchange {
        user_message,
        assistant_message,
        attachment,
    })
}

async fn bump_updated_at(
    conn: &mut SqliteConnection,
    id: Uuid,
    updated_at: DateTime<Utc>,
) -> Result<(), AppError> {
    sqlx::query!(
        "UPDATE chats SET updated_at = $2 WHERE id = $1",
        id,
        updated_at,
    )
    .execute(conn)
    .await?;
    Ok(())
}

/// The other foreign key, `user_id`, is the authenticated user.
fn map_unknown_model(e: sqlx::Error) -> AppError {
    match &e {
        sqlx::Error::Database(db_err) if db_err.is_foreign_key_violation() => {
            AppError::Unprocessable(ErrorCode::UnknownModel, "Unknown model".to_string())
        }
        _ => AppError::Database(e),
    }
}
