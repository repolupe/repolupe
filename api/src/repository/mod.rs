pub(crate) mod attachment;
pub(crate) mod chat;
pub(crate) mod config;
pub(crate) mod debug;
pub(crate) mod document;
pub(crate) mod llm;
pub(crate) mod message;
#[allow(clippy::module_inception)]
pub(crate) mod repository;
pub(crate) mod session;
pub(crate) mod user;

use crate::config::state::DatabasePool;
use sqlx::{Sqlite, Transaction};

/// Starts a transaction that takes the write lock right away, so concurrent ones run one after
/// the other. A deferred transaction that reads before it writes would fail with `SQLITE_BUSY`
/// instead of waiting if another connection wrote in between.
pub(crate) async fn begin_write(
    db: &DatabasePool,
) -> Result<Transaction<'static, Sqlite>, sqlx::Error> {
    db.begin_with("BEGIN IMMEDIATE").await
}

/// Whether `e` violates the unique index `target`. SQLite names the index only for indexes on
/// expressions, e.g. `index 'idx_users_email'`, otherwise the columns, e.g. `messages.chat_id`.
pub(crate) fn violates_unique(e: &sqlx::Error, target: &str) -> bool {
    match e {
        sqlx::Error::Database(db_err) => {
            db_err.is_unique_violation()
                && db_err.message().strip_prefix("UNIQUE constraint failed: ") == Some(target)
        }
        _ => false,
    }
}
