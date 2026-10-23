use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::chat::MessageRole;
use crate::dto::chat::MessageStatus;
use crate::dto::error::ErrorCode;
use crate::model::attachment::Attachment;
use crate::model::chat::Chat;
use crate::model::message::Message;
use crate::repository::attachment::send_attachment;
use crate::repository::begin_write;
use crate::repository::message::{NewMessage, insert_message};
use chrono::{DateTime, Utc};
use sqlx::types::Json;
use sqlx::{SqliteConnection, SqliteExecutor};
use uuid::Uuid;

/// Which repositories a chat can read from.
pub(crate) enum RepositoryScope {
    /// Every repository of the user, including ones added later.
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
    pub scope: &'a RepositoryScope,
    /// Chosen for the chat, `None` uses the user's model.
    pub model_id: Option<Uuid>,
    pub temporary: bool,
    pub content: &'a str,
    /// An unsent attachment of the user, sent with the first message.
    pub attachment_id: Option<Uuid>,
    pub user_message_id: Uuid,
    pub assistant_message_id: Uuid,
    /// The model that writes the first answer.
    pub answer_model_id: Uuid,
    pub created_at: DateTime<Utc>,
}

/// The repositories of a chat cannot be changed.
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
    pub model_id: Uuid,
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

pub(crate) enum RetryOutcome {
    Retried(Box<Message>),
    ChatNotFound,
    MessageNotFound,
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
    let all_repositories = matches!(new.scope, RepositoryScope::All);
    let mut tx = begin_write(db).await?;
    sqlx::query!(
        r#"INSERT INTO chats (id, user_id, title, all_repositories, model_id, temporary, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $7)"#,
        new.id,
        new.user_id,
        new.title,
        all_repositories,
        new.model_id,
        new.temporary,
        new.created_at,
    )
    .execute(&mut *tx)
    .await
    .map_err(map_unknown_model)?;
    if let RepositoryScope::Selected(ids) = new.scope {
        link_repositories(&mut tx, new.user_id, new.id, ids).await?;
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
            model_id: new.answer_model_id,
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

/// Replaces the failed or cancelled last answer with a new `GENERATING` one written by
/// `model_id`, and bumps `updated_at`.
pub(crate) async fn retry_message(
    db: &DatabasePool,
    user_id: Uuid,
    chat_id: Uuid,
    message_id: Uuid,
    new_message_id: Uuid,
    model_id: Uuid,
    created_at: DateTime<Utc>,
) -> Result<RetryOutcome, AppError> {
    let mut tx = begin_write(db).await?;
    if !has_chat(&mut tx, user_id, chat_id).await? {
        return Ok(RetryOutcome::ChatNotFound);
    }

    let target = sqlx::query!(
        r#"SELECT role AS "role: MessageRole", status AS "status: MessageStatus",
                  NOT EXISTS (SELECT 1 FROM messages later
                              WHERE later.chat_id = m.chat_id
                                AND (later.created_at, later.id) > (m.created_at, m.id)) AS "is_last!: bool"
           FROM messages m
           WHERE m.id = $1 AND m.chat_id = $2"#,
        message_id,
        chat_id,
    )
    .fetch_optional(&mut *tx)
    .await?;
    let Some(target) = target else {
        return Ok(RetryOutcome::MessageNotFound);
    };
    let retryable = target.role == MessageRole::Assistant
        && matches!(
            target.status,
            MessageStatus::Failed | MessageStatus::Cancelled
        )
        && target.is_last;
    if !retryable {
        return Err(AppError::Unprocessable(
            ErrorCode::NotRetryable,
            "Only a failed or cancelled answer at the end of the chat can be retried".to_string(),
        ));
    }

    sqlx::query!("DELETE FROM messages WHERE id = $1", message_id)
        .execute(&mut *tx)
        .await?;
    let message = insert_message(
        &mut tx,
        NewMessage {
            id: new_message_id,
            chat_id,
            role: MessageRole::Assistant,
            content: "",
            model_id: Some(model_id),
            created_at,
        },
    )
    .await?;
    bump_updated_at(&mut tx, chat_id, created_at).await?;
    tx.commit().await?;
    Ok(RetryOutcome::Retried(Box::new(message)))
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

/// Whether the user has the chat. Concurrent sends and retries within one chat are serialized
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
            model_id: None,
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
            model_id: Some(exchange.model_id),
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
