use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::model::attachment::Attachment;
use chrono::{DateTime, Utc};
use sqlx::SqliteConnection;
use std::collections::HashSet;
use uuid::Uuid;

pub(crate) struct NewAttachment<'a> {
    pub id: Uuid,
    pub user_id: Uuid,
    pub file_name: &'a str,
    pub content_type: &'a str,
    pub size: i64,
    pub blob_oid: &'a str,
    pub created_at: DateTime<Utc>,
}

/// Inserts an attachment that is not sent yet.
pub(crate) async fn insert_attachment(
    db: &DatabasePool,
    new: NewAttachment<'_>,
) -> Result<Attachment, AppError> {
    let attachment = sqlx::query_as!(
        Attachment,
        r#"INSERT INTO attachments (id, user_id, file_name, content_type, size, blob_oid, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id AS "id: Uuid", message_id AS "message_id: Uuid", number, file_name, content_type,
                     size, blob_oid, created_at AS "created_at: DateTime<Utc>""#,
        new.id,
        new.user_id,
        new.file_name,
        new.content_type,
        new.size,
        new.blob_oid,
        new.created_at,
    )
    .fetch_one(db)
    .await?;
    Ok(attachment)
}

/// An attachment of the user, sent or not.
pub(crate) async fn get_attachment(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<Option<Attachment>, AppError> {
    let attachment = sqlx::query_as!(
        Attachment,
        r#"SELECT id AS "id: Uuid", message_id AS "message_id: Uuid", number, file_name, content_type, size,
                  blob_oid, created_at AS "created_at: DateTime<Utc>"
           FROM attachments
           WHERE id = $1 AND user_id = $2"#,
        id,
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(attachment)
}

/// The attachments sent in the chat, by number.
pub(crate) async fn list_chat_attachments(
    db: &DatabasePool,
    chat_id: Uuid,
) -> Result<Vec<Attachment>, AppError> {
    let attachments = sqlx::query_as!(
        Attachment,
        r#"SELECT id AS "id: Uuid", message_id AS "message_id: Uuid", number, file_name, content_type, size,
                  blob_oid, created_at AS "created_at: DateTime<Utc>"
           FROM attachments
           WHERE chat_id = $1
           ORDER BY number"#,
        chat_id,
    )
    .fetch_all(db)
    .await?;
    Ok(attachments)
}

/// Sends the attachment `id` of the user with `message_id` and gives it the next number in the
/// chat. Fails with `UNKNOWN_ATTACHMENT` if the user has no such attachment or it was sent
/// already. Run in the transaction that inserts the message, which [`super::begin_write`]
/// serializes, so no other message of the chat takes the same number.
pub(crate) async fn send_attachment(
    conn: &mut SqliteConnection,
    user_id: Uuid,
    id: Uuid,
    chat_id: Uuid,
    message_id: Uuid,
) -> Result<Attachment, AppError> {
    let attachment = sqlx::query_as!(
        Attachment,
        r#"UPDATE attachments
           SET chat_id = $3, message_id = $4,
               number = (SELECT COALESCE(MAX(a.number), 0) + 1 FROM attachments a WHERE a.chat_id = $3)
           WHERE id = $1 AND user_id = $2 AND message_id IS NULL
           RETURNING id AS "id: Uuid", message_id AS "message_id: Uuid", number, file_name, content_type,
                     size, blob_oid, created_at AS "created_at: DateTime<Utc>""#,
        id,
        user_id,
        chat_id,
        message_id,
    )
    .fetch_optional(conn)
    .await?;
    attachment.ok_or_else(|| {
        AppError::Unprocessable(
            ErrorCode::UnknownAttachment,
            "The attachment does not exist or was sent already".to_string(),
        )
    })
}

/// Deletes the attachments not sent before `before`. Returns their ids.
pub(crate) async fn delete_unsent(
    db: &DatabasePool,
    before: DateTime<Utc>,
) -> Result<Vec<Uuid>, AppError> {
    let ids = sqlx::query_scalar!(
        r#"DELETE FROM attachments WHERE message_id IS NULL AND created_at < $1
           RETURNING id AS "id: Uuid""#,
        before,
    )
    .fetch_all(db)
    .await?;
    Ok(ids)
}

pub(crate) async fn list_attachment_ids(db: &DatabasePool) -> Result<HashSet<Uuid>, AppError> {
    let ids = sqlx::query_scalar!(r#"SELECT id AS "id: Uuid" FROM attachments"#)
        .fetch_all(db)
        .await?;
    Ok(ids.into_iter().collect())
}
