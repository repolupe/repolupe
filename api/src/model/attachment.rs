use chrono::{DateTime, Utc};
use uuid::Uuid;

/// A file the user attached to a chat, stored by `service::attachment::AttachmentStore`.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct Attachment {
    pub id: Uuid,
    /// The user message it was sent with, `None` until then.
    pub message_id: Option<Uuid>,
    /// How the model refers to it, counting from 1 per chat, `None` until sent.
    pub number: Option<i32>,
    pub file_name: String,
    /// As the browser reported it, `application/octet-stream` if unknown.
    pub content_type: String,
    pub size: i64,
    /// The id git gives the content.
    pub blob_oid: String,
    pub created_at: DateTime<Utc>,
}
