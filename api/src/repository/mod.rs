pub(crate) mod attachment;
pub(crate) mod chat;
pub(crate) mod config;
pub(crate) mod debug;
pub(crate) mod document;
pub(crate) mod llm;
pub(crate) mod mcp;
pub(crate) mod message;
#[allow(clippy::module_inception)]
pub(crate) mod repository;
pub(crate) mod session;
pub(crate) mod user;

use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use sqlx::{Sqlite, SqliteConnection, Transaction};

/// An encrypted token or API key as stored in the `*_encrypted` and `*_hint` columns.
pub(crate) struct StoredToken {
    pub encrypted: Vec<u8>,
    pub hint: Option<String>,
}

/// The values of the `*_encrypted` and `*_hint` columns for `token`.
fn split_token(token: Option<StoredToken>) -> (Option<Vec<u8>>, Option<String>) {
    match token {
        Some(token) => (Some(token.encrypted), token.hint),
        None => (None, None),
    }
}

/// Starts a transaction that takes the write lock right away, so concurrent ones run one after
/// the other. A deferred transaction that reads before it writes would fail with `SQLITE_BUSY`
/// instead of waiting if another connection wrote in between.
pub(crate) async fn begin_write(
    db: &DatabasePool,
) -> Result<Transaction<'static, Sqlite>, sqlx::Error> {
    db.begin_with("BEGIN IMMEDIATE").await
}

/// The tables with rows whose foreign keys point nowhere, comma-separated, which only happens
/// if they were written with foreign keys off.
pub(crate) async fn foreign_key_violations(
    conn: &mut SqliteConnection,
) -> Result<Option<String>, sqlx::Error> {
    // An expression, because sqlx can't look up the columns of the pragma's virtual table.
    sqlx::query_scalar!(
        r#"SELECT group_concat("table", ', ') AS "tables: String"
           FROM (SELECT DISTINCT "table" FROM pragma_foreign_key_check)"#
    )
    .fetch_one(conn)
    .await
}

/// Whether `e` violates the unique index `target`. SQLite names the index only for indexes on
/// expressions, e.g. `index 'idx_users_email'`, otherwise the columns, e.g. `messages.chat_id`.
fn violates_unique(e: &sqlx::Error, target: &str) -> bool {
    match e {
        sqlx::Error::Database(db_err) => {
            db_err.is_unique_violation()
                && db_err.message().strip_prefix("UNIQUE constraint failed: ") == Some(target)
        }
        _ => false,
    }
}

/// Maps `e` to the `Conflict` of the first of `cases` whose unique index `target` it violates
/// (see [`violates_unique`]), otherwise to a database error.
fn map_unique(e: sqlx::Error, cases: &[(&str, ErrorCode, &str)]) -> AppError {
    match cases
        .iter()
        .find(|(target, _, _)| violates_unique(&e, target))
    {
        Some(&(_, code, message)) => AppError::Conflict(code, message.to_string()),
        None => AppError::Database(e),
    }
}
