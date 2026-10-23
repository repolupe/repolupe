use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::chat::MessageRole;
use crate::repository::begin_write;
use chrono::{DateTime, Utc};
use uuid::Uuid;

pub(crate) struct DummyChat {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: String,
    pub all_repositories: bool,
    /// Only used if `all_repositories` is false. Must be accessible to the user.
    pub repository_id: Option<Uuid>,
    pub model_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub messages: Vec<DummyMessage>,
}

/// Stored `COMPLETED`. User messages have no `model_id` and `finished_at`.
pub(crate) struct DummyMessage {
    pub id: Uuid,
    pub is_user: bool,
    pub content: String,
    pub model_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub finished_at: Option<DateTime<Utc>>,
}

/// Inserts the chats with their messages.
pub(crate) async fn insert_dummy_chats(
    db: &DatabasePool,
    chats: &[DummyChat],
) -> Result<(), AppError> {
    let mut tx = begin_write(db).await?;
    for chat in chats {
        sqlx::query!(
            r#"INSERT INTO chats (id, user_id, title, all_repositories, model_id, temporary, created_at, updated_at)
               VALUES ($1, $2, $3, $4, $5, FALSE, $6, $7)"#,
            chat.id,
            chat.user_id,
            chat.title,
            chat.all_repositories,
            chat.model_id,
            chat.created_at,
            chat.updated_at,
        )
        .execute(&mut *tx)
        .await?;

        if let (false, Some(repository_id)) = (chat.all_repositories, chat.repository_id) {
            sqlx::query!(
                "INSERT INTO chat_repositories (chat_id, repository_id) VALUES ($1, $2)",
                chat.id,
                repository_id,
            )
            .execute(&mut *tx)
            .await?;
        }

        for message in &chat.messages {
            let role = if message.is_user {
                MessageRole::User
            } else {
                MessageRole::Assistant
            };
            sqlx::query!(
                r#"INSERT INTO messages (id, chat_id, role, content, status, model_id, created_at, finished_at)
                   VALUES ($1, $2, $3, $4, 'COMPLETED', $5, $6, $7)"#,
                message.id,
                chat.id,
                role,
                message.content,
                message.model_id,
                message.created_at,
                message.finished_at,
            )
            .execute(&mut *tx)
            .await?;
        }
    }

    tx.commit().await?;
    Ok(())
}
