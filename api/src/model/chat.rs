use chrono::{DateTime, Utc};
use sqlx::types::Json;
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct Chat {
    pub id: Uuid,
    pub title: String,
    pub all_repositories: bool,
    /// Empty if `all_repositories` is true.
    pub repository_ids: Json<Vec<Uuid>>,
    /// `None` uses the user's model.
    pub model_id: Option<Uuid>,
    /// Not listed, and deleted a while after its last message.
    pub temporary: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
