//! Files attached to chats.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A file the user attached to a chat, downloaded from `GET /api/v1/attachments/{id}`.
#[derive(Serialize, Deserialize)]
pub struct AttachmentDto {
    pub id: Uuid,
    /// How the model refers to it, counting from 1 per chat, `null` until sent.
    pub number: Option<i32>,
    pub file_name: String,
    pub content_type: String,
    pub size: i64,
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct UploadAttachmentQuery {
    pub file_name: String,
    /// The type the browser reports, e.g. `application/pdf`.
    pub content_type: Option<String>,
}
