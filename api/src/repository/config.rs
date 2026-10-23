use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::repository::begin_write;
use std::collections::BTreeMap;

pub(crate) async fn get_config(db: &DatabasePool) -> Result<BTreeMap<String, String>, AppError> {
    let rows = sqlx::query!("SELECT key, value FROM config")
        .fetch_all(db)
        .await?;
    Ok(rows.into_iter().map(|row| (row.key, row.value)).collect())
}

/// Replaces all entries with `config`.
pub(crate) async fn set_config(
    db: &DatabasePool,
    config: &BTreeMap<String, String>,
) -> Result<(), AppError> {
    let mut tx = begin_write(db).await?;
    sqlx::query!("DELETE FROM config").execute(&mut *tx).await?;
    for (key, value) in config {
        sqlx::query!(
            "INSERT INTO config (key, value) VALUES ($1, $2)",
            key,
            value
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}
