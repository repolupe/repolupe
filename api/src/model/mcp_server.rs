use crate::dto::mcp::{McpServerAuth, McpServerStatus};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sqlx::types::Json;
use uuid::Uuid;

#[derive(Debug, sqlx::FromRow)]
pub struct McpServer {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub url: String,
    pub enabled: bool,
    /// A bearer token the user entered. Never set together with `oauth_encrypted`.
    pub token_encrypted: Option<Vec<u8>>,
    pub token_hint: Option<String>,
    /// The OAuth credentials (rmcp's `StoredCredentials` as JSON) after signing in.
    pub oauth_encrypted: Option<Vec<u8>>,
    pub status: McpServerStatus,
    pub last_error: Option<String>,
    pub tools: Json<Vec<McpTool>>,
    /// The names of the tools the model doesn't get, sorted. May include tools the server no
    /// longer lists, so they stay off if they return.
    pub disabled_tools: Json<Vec<String>>,
    pub checked_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl McpServer {
    pub fn auth(&self) -> McpServerAuth {
        match (&self.token_encrypted, &self.oauth_encrypted) {
            (Some(_), _) => McpServerAuth::Token,
            (None, Some(_)) => McpServerAuth::OAuth,
            (None, None) => McpServerAuth::None,
        }
    }
}

/// A tool of an MCP server, as listed at the last successful connection.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct McpTool {
    /// As the server names it, which the model may not accept, see
    /// [`crate::service::tools`].
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
    /// The JSON schema of the arguments, an object schema.
    pub input_schema: Map<String, Value>,
}
