use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::dto::mcp::McpServerStatus;
use crate::model::mcp_server::{McpServer, McpTool};
use crate::repository::repository::StoredToken;
use crate::repository::{begin_write, violates_unique};
use crate::util::validation::ValidationError;
use chrono::{DateTime, Utc};
use sqlx::types::Json;
use uuid::Uuid;

/// Servers a user may add, so the tools in their prompts stay manageable.
pub(crate) const MAX_MCP_SERVERS_PER_USER: i64 = 20;

/// The outcome of connecting to a server.
pub(crate) struct Connection<'a> {
    pub status: McpServerStatus,
    /// With `FAILED`.
    pub last_error: Option<&'a str>,
    /// The tools listed with `READY`, `None` keeps the ones of the last successful connection.
    pub tools: Option<&'a [McpTool]>,
    pub checked_at: DateTime<Utc>,
}

pub(crate) struct NewMcpServer<'a> {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: &'a str,
    pub url: &'a str,
    pub token: Option<StoredToken>,
    pub connection: Connection<'a>,
}

pub(crate) struct McpServerChanges<'a> {
    pub name: &'a str,
    pub enabled: bool,
    /// Sorted and without duplicates.
    pub disabled_tools: &'a [String],
}

pub(crate) async fn list_mcp_servers(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<Vec<McpServer>, AppError> {
    let servers = sqlx::query_as!(
        McpServer,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                  token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                  tools AS "tools: Json<Vec<McpTool>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                  checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM mcp_servers
           WHERE user_id = $1
           ORDER BY id"#,
        user_id,
    )
    .fetch_all(db)
    .await?;
    Ok(servers)
}

/// The servers whose tools the model gets in the user's chats: enabled, and connected at the
/// last check. In the order they were added, so the tools stay in the same order.
pub(crate) async fn list_usable_mcp_servers(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<Vec<McpServer>, AppError> {
    let servers = sqlx::query_as!(
        McpServer,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                  token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                  tools AS "tools: Json<Vec<McpTool>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                  checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM mcp_servers
           WHERE user_id = $1 AND enabled AND status = 'READY'
           ORDER BY id"#,
        user_id,
    )
    .fetch_all(db)
    .await?;
    Ok(servers)
}

pub(crate) async fn get_mcp_server(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<Option<McpServer>, AppError> {
    let server = sqlx::query_as!(
        McpServer,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                  token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                  tools AS "tools: Json<Vec<McpTool>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                  checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM mcp_servers
           WHERE id = $1 AND user_id = $2"#,
        id,
        user_id,
    )
    .fetch_optional(db)
    .await?;
    Ok(server)
}

/// Fails if the user has [`MAX_MCP_SERVERS_PER_USER`] servers already.
pub(crate) async fn create_mcp_server(
    db: &DatabasePool,
    new: NewMcpServer<'_>,
) -> Result<McpServer, AppError> {
    let (token_encrypted, token_hint) = split_token(new.token);
    let tools = Json(new.connection.tools.unwrap_or_default());
    let now = Utc::now();

    let mut tx = begin_write(db).await?;
    let count = sqlx::query_scalar!(
        r#"SELECT COUNT(*) AS "count!: i64" FROM mcp_servers WHERE user_id = $1"#,
        new.user_id,
    )
    .fetch_one(&mut *tx)
    .await?;
    if count >= MAX_MCP_SERVERS_PER_USER {
        return Err(ValidationError(format!(
            "You can add at most {MAX_MCP_SERVERS_PER_USER} MCP servers"
        ))
        .into());
    }
    let server = sqlx::query_as!(
        McpServer,
        r#"INSERT INTO mcp_servers (id, user_id, name, url, enabled, token_encrypted, token_hint,
                                    oauth_encrypted, status, last_error, tools, disabled_tools,
                                    checked_at, created_at, updated_at)
           VALUES ($1, $2, $3, $4, TRUE, $5, $6, NULL, $7, $8, $9, '[]', $10, $11, $11)
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                     token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                     tools AS "tools: Json<Vec<McpTool>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                     checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                     updated_at AS "updated_at: DateTime<Utc>""#,
        new.id,
        new.user_id,
        new.name,
        new.url,
        token_encrypted,
        token_hint,
        new.connection.status,
        new.connection.last_error,
        tools,
        new.connection.checked_at,
        now,
    )
    .fetch_one(&mut *tx)
    .await
    .map_err(map_name_conflict)?;
    tx.commit().await?;
    Ok(server)
}

/// Applies `changes` if the server still has `expected_url`. Returns `None` if it does not
/// exist (for the user), or its URL changed in the meantime.
pub(crate) async fn update_mcp_server(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
    changes: McpServerChanges<'_>,
) -> Result<Option<McpServer>, AppError> {
    let disabled_tools = Json(changes.disabled_tools);
    let now = Utc::now();
    let server = sqlx::query_as!(
        McpServer,
        r#"UPDATE mcp_servers
           SET name           = $3,
               enabled        = $4,
               disabled_tools = $5,
               updated_at     = $6
           WHERE id = $1 AND user_id = $2
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                     token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                     tools AS "tools: Json<Vec<McpTool>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                     checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                     updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        user_id,
        changes.name,
        changes.enabled,
        disabled_tools,
        now,
    )
    .fetch_optional(db)
    .await
    .map_err(map_name_conflict)?;
    Ok(server)
}

/// Stores the outcome of connecting to the server at `expected_url`. Returns `None` if it no
/// longer exists or has another URL by now, then the outcome is outdated.
pub(crate) async fn record_connection(
    db: &DatabasePool,
    id: Uuid,
    expected_url: &str,
    connection: Connection<'_>,
) -> Result<Option<McpServer>, AppError> {
    let tools = connection.tools.map(Json);
    let server = sqlx::query_as!(
        McpServer,
        r#"UPDATE mcp_servers
           SET status     = $3,
               last_error = $4,
               tools      = COALESCE($5, tools),
               checked_at = $6
           WHERE id = $1 AND url = $2
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                     token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                     tools AS "tools: Json<Vec<McpTool>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                     checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                     updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        expected_url,
        connection.status,
        connection.last_error,
        tools,
        connection.checked_at,
    )
    .fetch_optional(db)
    .await?;
    Ok(server)
}

/// Deleting a missing server also succeeds, so the request is safe to retry.
pub(crate) async fn delete_mcp_server(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<(), AppError> {
    sqlx::query!(
        "DELETE FROM mcp_servers WHERE id = $1 AND user_id = $2",
        id,
        user_id,
    )
    .execute(db)
    .await?;
    Ok(())
}

/// The encrypted OAuth credentials of the server, if it still has `url`.
pub(crate) async fn get_oauth_credentials(
    db: &DatabasePool,
    id: Uuid,
    url: &str,
) -> Result<Option<Vec<u8>>, AppError> {
    let credentials = sqlx::query_scalar!(
        "SELECT oauth_encrypted FROM mcp_servers WHERE id = $1 AND url = $2",
        id,
        url,
    )
    .fetch_optional(db)
    .await?;
    Ok(credentials.flatten())
}

/// Stores new OAuth credentials of the server, if it still has `url`. With `sign_in`, they
/// replace the token, otherwise (for refreshed tokens) only earlier credentials, so a sign-out
/// or a token set in the meantime stays. Returns whether they were stored.
pub(crate) async fn save_oauth_credentials(
    db: &DatabasePool,
    id: Uuid,
    url: &str,
    encrypted: &[u8],
    sign_in: bool,
) -> Result<bool, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        r#"UPDATE mcp_servers
           SET oauth_encrypted = $3,
               token_encrypted = NULL,
               token_hint      = NULL,
               updated_at      = CASE WHEN $4 THEN $5 ELSE updated_at END
           WHERE id = $1 AND url = $2 AND ($4 OR oauth_encrypted IS NOT NULL)"#,
        id,
        url,
        encrypted,
        sign_in,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

pub(crate) async fn clear_oauth_credentials(
    db: &DatabasePool,
    id: Uuid,
    url: &str,
) -> Result<(), AppError> {
    sqlx::query!(
        "UPDATE mcp_servers SET oauth_encrypted = NULL WHERE id = $1 AND url = $2",
        id,
        url,
    )
    .execute(db)
    .await?;
    Ok(())
}

fn split_token(token: Option<StoredToken>) -> (Option<Vec<u8>>, Option<String>) {
    match token {
        Some(token) => (Some(token.encrypted), token.hint),
        None => (None, None),
    }
}

fn map_name_conflict(e: sqlx::Error) -> AppError {
    if violates_unique(&e, "index 'idx_mcp_servers_user_name'") {
        AppError::Conflict(
            ErrorCode::NameTaken,
            "You already have an MCP server with this name".to_string(),
        )
    } else {
        AppError::Database(e)
    }
}
