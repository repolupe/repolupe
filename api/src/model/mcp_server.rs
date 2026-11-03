use crate::dto::mcp::{McpServerAuth, McpServerStatus};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sqlx::types::Json;
use uuid::Uuid;

/// With the stored tools as `Tool`: [`McpToolSummary`] where their schemas aren't needed,
/// [`McpTool`] for the model.
#[derive(Debug, sqlx::FromRow)]
pub struct McpServer<Tool = McpToolSummary> {
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
    pub tools: Json<Vec<Tool>>,
    /// The names of the tools the model doesn't get, sorted. May include tools the server no
    /// longer lists, so they stay off if they return.
    pub disabled_tools: Json<Vec<String>>,
    pub checked_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl<Tool> McpServer<Tool> {
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
    /// About the size of the tool's definition as sent to the LLM, measured when the list was
    /// stored. `None` in lists stored before it was added.
    #[serde(default)]
    pub definition_bytes: Option<usize>,
}

/// A stored [`McpTool`] without its schema, which is skipped when reading it.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct McpToolSummary {
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_tools_stored_without_their_size() {
        let stored = json!([{
            "name": "search",
            "title": null,
            "description": "Searches.",
            "input_schema": {"type": "object"},
        }]);
        let tools: Vec<McpTool> = serde_json::from_value(stored.clone()).unwrap();
        assert_eq!(tools[0].name, "search");
        assert_eq!(tools[0].definition_bytes, None);
        let summaries: Vec<McpToolSummary> = serde_json::from_value(stored).unwrap();
        assert_eq!(
            summaries,
            [McpToolSummary {
                name: "search".to_string(),
                title: None,
                description: Some("Searches.".to_string()),
            }]
        );
    }
}
