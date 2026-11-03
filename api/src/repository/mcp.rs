use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::dto::mcp::McpServerStatus;
use crate::dto::user::UserRole;
use crate::model::mcp_server::{
    McpServer, McpServerShare, McpServerUser, McpTool, McpToolSummary, UsableMcpServer,
};
use crate::repository::repository::StoredToken;
use crate::repository::{begin_write, violates_unique};
use crate::util::validation::ValidationError;
use chrono::{DateTime, Utc};
use sqlx::SqliteConnection;
use sqlx::types::Json;
use std::collections::HashMap;
use uuid::Uuid;

/// Servers whose tools a user may get, so the tools in their prompts stay manageable: the ones
/// they added and the ones shared with them that they turned on. Shares that are off don't
/// count, so others can't use up the limit.
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

/// The servers the user owns or that are shared with them, the latter with how.
pub(crate) async fn list_mcp_servers(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<Vec<(McpServer, Option<McpServerShare>)>, AppError> {
    // One snapshot, so every server shared with the user comes with its share.
    let mut tx = db.begin().await?;
    let servers = sqlx::query_as!(
        McpServer,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                  token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                  tools AS "tools: Json<Vec<McpToolSummary>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                  checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM mcp_servers s
           WHERE s.user_id = $1
              OR s.id IN (SELECT mcp_server_id FROM mcp_server_users WHERE user_id = $1)
           ORDER BY id"#,
        user_id,
    )
    .fetch_all(&mut *tx)
    .await?;
    let mut shares: HashMap<Uuid, McpServerShare> = sqlx::query_as!(
        McpServerShare,
        r#"SELECT su.mcp_server_id AS "mcp_server_id: Uuid", u.user_name AS owner_name, su.enabled,
                  su.created_at AS "created_at: DateTime<Utc>"
           FROM mcp_server_users su
           JOIN mcp_servers s ON s.id = su.mcp_server_id
           JOIN users u ON u.id = s.user_id
           WHERE su.user_id = $1"#,
        user_id,
    )
    .fetch_all(&mut *tx)
    .await?
    .into_iter()
    .map(|share| (share.mcp_server_id, share))
    .collect();
    tx.commit().await?;
    Ok(servers
        .into_iter()
        .map(|server| {
            let share = shares.remove(&server.id);
            (server, share)
        })
        .collect())
}

/// The servers whose tools the model gets in the user's chats: their own and the ones shared
/// with them that they turned on, enabled by the owner and connected at the last check. In the
/// order they were added, so the tools stay in the same order. With the schemas of the tools,
/// unlike the other queries.
pub(crate) async fn list_usable_mcp_servers(
    db: &DatabasePool,
    user_id: Uuid,
) -> Result<Vec<UsableMcpServer>, AppError> {
    let servers = sqlx::query_as!(
        UsableMcpServer,
        r#"SELECT s.id AS "id: Uuid", s.name, s.url, s.token_encrypted, s.oauth_encrypted,
                  u.role AS "owner_role: UserRole",
                  CASE WHEN s.user_id = $1 THEN NULL ELSE u.user_name END AS "shared_by?: String",
                  s.tools AS "tools: Json<Vec<McpTool>>",
                  s.disabled_tools AS "disabled_tools: Json<Vec<String>>",
                  s.updated_at AS "updated_at: DateTime<Utc>"
           FROM mcp_servers s
           JOIN users u ON u.id = s.user_id
           WHERE (s.user_id = $1
                  OR s.id IN (SELECT mcp_server_id FROM mcp_server_users WHERE user_id = $1 AND enabled))
             AND s.enabled AND s.status = 'READY'
           ORDER BY s.id"#,
        user_id,
    )
    .fetch_all(db)
    .await?;
    Ok(servers)
}

/// A server the user owns or that is shared with them.
pub(crate) async fn get_mcp_server(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<Option<McpServer>, AppError> {
    let server = sqlx::query_as!(
        McpServer,
        r#"SELECT id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                  token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                  tools AS "tools: Json<Vec<McpToolSummary>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                  checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                  updated_at AS "updated_at: DateTime<Utc>"
           FROM mcp_servers s
           WHERE s.id = $1
             AND (s.user_id = $2
                  OR s.id IN (SELECT mcp_server_id FROM mcp_server_users WHERE user_id = $2))"#,
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
    check_mcp_server_limit(&mut tx, new.user_id).await?;
    let server = sqlx::query_as!(
        McpServer,
        r#"INSERT INTO mcp_servers (id, user_id, name, url, enabled, token_encrypted, token_hint,
                                    oauth_encrypted, status, last_error, tools, disabled_tools,
                                    checked_at, created_at, updated_at)
           VALUES ($1, $2, $3, $4, TRUE, $5, $6, NULL, $7, $8, $9, '[]', $10, $11, $11)
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                     token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                     tools AS "tools: Json<Vec<McpToolSummary>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
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

/// Applies `changes`. Returns `None` if the user owns no such server. Its URL
/// never changes: allowing that would need to clear the token and the OAuth credentials,
/// which were issued for that server, and to forget the cached OAuth client.
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
                     tools AS "tools: Json<Vec<McpToolSummary>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
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

/// Stores the outcome of connecting to the server, and with `expected_updated_at` only if the
/// server's `updated_at` is still that. It changes when the user changes the credentials
/// (signs in), not when tokens are refreshed or outcomes stored, so an outcome of credentials
/// replaced in the meantime is left out. Returns `None` if the server no longer exists or was
/// changed, then the outcome is outdated.
pub(crate) async fn record_connection(
    db: &DatabasePool,
    id: Uuid,
    expected_updated_at: Option<DateTime<Utc>>,
    connection: Connection<'_>,
) -> Result<Option<McpServer>, AppError> {
    let tools = connection.tools.map(Json);
    let server = sqlx::query_as!(
        McpServer,
        r#"UPDATE mcp_servers
           SET status     = $2,
               last_error = $3,
               tools      = COALESCE($4, tools),
               checked_at = $5
           WHERE id = $1 AND ($6 IS NULL OR updated_at = $6)
           RETURNING id AS "id: Uuid", user_id AS "user_id: Uuid", name, url, enabled, token_encrypted,
                     token_hint, oauth_encrypted, status AS "status: McpServerStatus", last_error,
                     tools AS "tools: Json<Vec<McpToolSummary>>", disabled_tools AS "disabled_tools: Json<Vec<String>>",
                     checked_at AS "checked_at: DateTime<Utc>", created_at AS "created_at: DateTime<Utc>",
                     updated_at AS "updated_at: DateTime<Utc>""#,
        id,
        connection.status,
        connection.last_error,
        tools,
        connection.checked_at,
        expected_updated_at,
    )
    .fetch_optional(db)
    .await?;
    Ok(server)
}

/// Returns `false` if the user owns no such server.
pub(crate) async fn delete_mcp_server(
    db: &DatabasePool,
    user_id: Uuid,
    id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "DELETE FROM mcp_servers WHERE id = $1 AND user_id = $2",
        id,
        user_id,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// The users the server is shared with, without its owner. Empty if `owner_id` owns no such
/// server.
pub(crate) async fn list_mcp_server_users(
    db: &DatabasePool,
    owner_id: Uuid,
    id: Uuid,
) -> Result<Vec<McpServerUser>, AppError> {
    let users = sqlx::query_as!(
        McpServerUser,
        r#"SELECT u.id AS "user_id: Uuid", u.user_name, u.email, su.created_at AS "created_at: DateTime<Utc>"
           FROM mcp_server_users su
           JOIN mcp_servers s ON s.id = su.mcp_server_id
           JOIN users u ON u.id = su.user_id
           WHERE su.mcp_server_id = $1 AND s.user_id = $2
           ORDER BY su.created_at, u.id"#,
        id,
        owner_id,
    )
    .fetch_all(db)
    .await?;
    Ok(users)
}

/// Shares the server of `owner_id` with the user, off until they turn it on. Returns `false` if
/// nothing changed: `owner_id` owns no such server, or it already is shared with the user
/// (sharing it again never turns it on).
pub(crate) async fn add_mcp_server_user(
    db: &DatabasePool,
    owner_id: Uuid,
    id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        r#"INSERT INTO mcp_server_users (mcp_server_id, user_id, enabled, created_at)
           SELECT id, $3, FALSE, $4 FROM mcp_servers WHERE id = $1 AND user_id = $2
           ON CONFLICT DO NOTHING"#,
        id,
        owner_id,
        user_id,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Turns the server shared with the user on or off for their chats. Returns `false` if it is
/// not shared with them. Turning it on fails if the user has [`MAX_MCP_SERVERS_PER_USER`]
/// servers already.
pub(crate) async fn update_mcp_server_user(
    db: &DatabasePool,
    id: Uuid,
    user_id: Uuid,
    enabled: bool,
) -> Result<bool, AppError> {
    let mut tx = begin_write(db).await?;
    let Some(was_enabled) = sqlx::query_scalar!(
        "SELECT enabled FROM mcp_server_users WHERE mcp_server_id = $1 AND user_id = $2",
        id,
        user_id,
    )
    .fetch_optional(&mut *tx)
    .await?
    else {
        return Ok(false);
    };
    if enabled && !was_enabled {
        check_mcp_server_limit(&mut tx, user_id).await?;
    }
    sqlx::query!(
        "UPDATE mcp_server_users SET enabled = $3 WHERE mcp_server_id = $1 AND user_id = $2",
        id,
        user_id,
        enabled,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(true)
}

/// Fails if the user has [`MAX_MCP_SERVERS_PER_USER`] servers: their own and the ones shared
/// with them that they turned on.
async fn check_mcp_server_limit(
    conn: &mut SqliteConnection,
    user_id: Uuid,
) -> Result<(), AppError> {
    let count = sqlx::query_scalar!(
        r#"SELECT (SELECT COUNT(*) FROM mcp_servers WHERE user_id = $1)
                  + (SELECT COUNT(*) FROM mcp_server_users WHERE user_id = $1 AND enabled)
                  AS "count!: i64""#,
        user_id,
    )
    .fetch_one(&mut *conn)
    .await?;
    if count >= MAX_MCP_SERVERS_PER_USER {
        return Err(ValidationError(format!(
            "You can use at most {MAX_MCP_SERVERS_PER_USER} MCP servers, counting the ones shared \
            with you that you turned on"
        ))
        .into());
    }
    Ok(())
}

/// Stops sharing the server with the user, for its owner or the user themselves (`acting_id`).
/// Returns `false` if nothing changed: it was not shared with them, or `acting_id` is neither.
pub(crate) async fn remove_mcp_server_user(
    db: &DatabasePool,
    acting_id: Uuid,
    id: Uuid,
    user_id: Uuid,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        r#"DELETE FROM mcp_server_users
           WHERE mcp_server_id = $1 AND user_id = $2
             AND (user_id = $3 OR EXISTS (SELECT 1 FROM mcp_servers WHERE id = $1 AND user_id = $3))"#,
        id,
        user_id,
        acting_id,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// The encrypted OAuth credentials of the server.
pub(crate) async fn get_oauth_credentials(
    db: &DatabasePool,
    id: Uuid,
) -> Result<Option<Vec<u8>>, AppError> {
    let credentials =
        sqlx::query_scalar!("SELECT oauth_encrypted FROM mcp_servers WHERE id = $1", id)
            .fetch_optional(db)
            .await?;
    Ok(credentials.flatten())
}

/// Stores new OAuth credentials of the server. With `sign_in`, they replace the token,
/// otherwise (for refreshed tokens) only earlier credentials, so a sign-out or a token set in
/// the meantime stays. Returns whether they were stored.
pub(crate) async fn save_oauth_credentials(
    db: &DatabasePool,
    id: Uuid,
    encrypted: &[u8],
    sign_in: bool,
) -> Result<bool, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        r#"UPDATE mcp_servers
           SET oauth_encrypted = $2,
               token_encrypted = NULL,
               token_hint      = NULL,
               updated_at      = CASE WHEN $3 THEN $4 ELSE updated_at END
           WHERE id = $1 AND ($3 OR oauth_encrypted IS NOT NULL)"#,
        id,
        encrypted,
        sign_in,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

pub(crate) async fn clear_oauth_credentials(db: &DatabasePool, id: Uuid) -> Result<(), AppError> {
    sqlx::query!(
        "UPDATE mcp_servers SET oauth_encrypted = NULL WHERE id = $1",
        id,
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
