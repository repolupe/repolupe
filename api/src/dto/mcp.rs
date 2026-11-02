//! MCP servers: remote services whose tools the model can use in the chats of the user who
//! added them. Only remote servers (Streamable HTTP) are supported.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum McpServerStatus {
    /// The last connection succeeded. While enabled, its tools are offered in chats.
    Ready,
    /// The server asks for authentication: the user signs in with OAuth (see
    /// `POST /api/v1/mcp-servers/{id}/authorize`), or adds it again with a token if it does not
    /// support that.
    AuthorizationRequired,
    /// The last connection failed, see `last_error`.
    Failed,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// How requests to the server are authenticated.
#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum McpServerAuth {
    None,
    /// A token the user entered, sent as `Authorization: Bearer <token>`.
    Token,
    /// The user signed in with OAuth.
    #[serde(rename = "OAUTH")]
    OAuth,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

#[derive(Serialize, Deserialize)]
pub struct McpServerDto {
    pub id: Uuid,
    pub name: String,
    pub url: String,
    /// Whether its tools are offered in the user's chats (once it is `READY`).
    pub enabled: bool,
    pub auth: McpServerAuth,
    /// The last 4 characters of the token with `TOKEN`, `null` for short tokens and otherwise.
    pub token_hint: Option<String>,
    pub status: McpServerStatus,
    /// Why the last connection failed, with `FAILED`.
    pub last_error: Option<String>,
    /// The tools as of the last successful connection, in the server's order.
    pub tools: Vec<McpToolDto>,
    /// The names of the tools the user turned off, which the model doesn't get, sorted. May
    /// include tools the server no longer lists, so they stay off if they return.
    pub disabled_tools: Vec<String>,
    /// When the server was last connected to, successfully or not.
    pub checked_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct McpToolDto {
    /// As the server names it.
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
}

/// Connects to the server and lists its tools before saving. Fails with `REMOTE_UNREACHABLE` if
/// it cannot be reached or is no MCP server, and `AUTH_FAILED` if it rejects `token`. A server
/// that asks for authentication without a token is saved as `AUTHORIZATION_REQUIRED`.
#[derive(Serialize, Deserialize)]
pub struct CreateMcpServerRequest {
    /// Unique among the user's servers, ignoring case.
    pub name: String,
    /// The Streamable HTTP endpoint, e.g. `https://mcp.example.com/mcp`. `https://` and a host
    /// with public addresses, except for admins.
    pub url: String,
    /// Absent, `null` or blank without one.
    pub token: Option<String>,
}

/// Replaces all fields. The URL and the token of a server can't be changed: it is deleted and
/// added again instead. Signing in again with OAuth goes through
/// `POST /api/v1/mcp-servers/{id}/authorize`.
#[derive(Serialize, Deserialize)]
pub struct UpdateMcpServerRequest {
    pub name: String,
    pub enabled: bool,
    /// The names of the tools to turn off, as the server names them. Names it doesn't list
    /// are kept, duplicates removed.
    pub disabled_tools: Vec<String>,
}

/// Starts signing in to the server with OAuth, see [`AuthorizationUrlDto`].
#[derive(Serialize, Deserialize)]
pub struct AuthorizeMcpServerRequest {
    /// Where the authorization server sends the user back to, with `code` and `state` (and
    /// maybe `iss`) as query parameters, which go to
    /// `POST /api/v1/mcp-servers/authorize/callback`. An absolute `https://` or `http://` URL.
    pub redirect_uri: String,
}

#[derive(Serialize, Deserialize)]
pub struct AuthorizationUrlDto {
    /// Where to send the user to sign in. Valid for 10 minutes.
    pub authorization_url: String,
}

/// Completes signing in with the query parameters the authorization server sent the user back
/// with, then connects again. Fails with `NOT_FOUND` if `state` is unknown or expired (also
/// after a restart of the server), or belongs to another user.
#[derive(Serialize, Deserialize)]
pub struct McpAuthorizationCallbackRequest {
    pub state: String,
    pub code: String,
    /// The `iss` parameter (RFC 9207), if the authorization server sent it.
    pub iss: Option<String>,
}
