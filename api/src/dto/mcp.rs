//! MCP servers: remote services whose tools the model can use in the chats of the user who
//! added them, and of the users they share them with. Only remote servers (Streamable HTTP)
//! are supported.

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

/// Users the server is shared with use it in their chats once they turn it on, as the owner set
/// it up (with the owner's token or OAuth sign-in, and only the tools the owner enabled), but
/// only the owner manages it.
#[derive(Serialize, Deserialize)]
pub struct McpServerDto {
    pub id: Uuid,
    pub owner_id: Uuid,
    /// How the server is shared with the user, `null` for its owner.
    pub shared: Option<McpServerShareDto>,
    pub name: String,
    /// For users it is shared with only the origin (`https://mcp.example.com`), since some
    /// servers take a key in the path or the query, which is the owner's.
    pub url: String,
    /// Whether the owner turned it on: its tools are offered in the owner's chats (once it is
    /// `READY`), and in those of the users it is shared with who turned it on as well.
    pub enabled: bool,
    pub auth: McpServerAuth,
    /// The last 4 characters of the token with `TOKEN`, `null` for short tokens, otherwise and
    /// for users it is shared with.
    pub token_hint: Option<String>,
    pub status: McpServerStatus,
    /// Why the last connection failed, with `FAILED`. `null` for users it is shared with, since
    /// it may contain the URL.
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

/// How a server is shared with the user, who decides whether to use it.
#[derive(Serialize, Deserialize)]
pub struct McpServerShareDto {
    /// The user name of the owner, who shared it.
    pub owner_name: String,
    /// Whether the user turned it on for their chats. Off when it is shared, see
    /// [`UpdateMcpServerUserRequest`].
    pub enabled: bool,
    /// When it was shared with the user.
    pub created_at: DateTime<Utc>,
}

/// Turns a server shared with the user on or off for their chats. Only for that user, not for
/// the owner, and also without the permission to manage MCP servers. Turning it on fails with
/// `VALIDATION_ERROR` if the user has 20 servers already: their own and the shared ones they
/// turned on.
#[derive(Serialize, Deserialize)]
pub struct UpdateMcpServerUserRequest {
    pub enabled: bool,
}

#[derive(Serialize, Deserialize)]
pub struct McpServerUserDto {
    pub user_id: Uuid,
    pub user_name: String,
    pub email: Option<String>,
    /// When the server was shared with the user.
    pub created_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct AddMcpServerUserRequest {
    pub user_name_or_email: String,
}

#[derive(Serialize, Deserialize)]
pub struct McpToolDto {
    /// As the server names it.
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
}

/// Connects to the server and lists its tools before saving. Fails with `REMOTE_UNREACHABLE` if
/// it cannot be reached or is no MCP server, `AUTH_FAILED` if it rejects `token`, and
/// `VALIDATION_ERROR` if the user has 20 servers already (counting the shared ones they turned
/// on). A server that asks for authentication without a token is saved as
/// `AUTHORIZATION_REQUIRED`.
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

/// What an MCP server is for, shown as the subtitle of its suggestion.
#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum McpServerKind {
    /// Searches the web.
    Search,
    /// Reads and extracts web pages.
    WebScraping,
    /// Looks up documentation.
    Documentation,
    /// Works with developer platforms.
    DevTools,
    /// Manages hosting and deployments.
    Cloud,
    /// Queries and manages databases.
    Database,
    /// Reads monitoring, profiling or tracing data.
    Observability,
    /// Tracks issues and projects.
    ProjectManagement,
    /// Works with notes, documents and tasks.
    Productivity,
    /// Works with customer relationships.
    Crm,
    /// Handles payments.
    Payments,
    /// Provides financial data.
    Finance,
    /// Works with designs.
    Design,
    /// Runs actions in other apps.
    Automation,
    /// Answers factual questions and computes.
    Knowledge,
    /// Looks up places and routes.
    Maps,
    /// Looks up travel connections.
    Travel,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// A common MCP server, offered when adding one, see `GET /api/v1/mcp-servers/suggestions`.
#[derive(Serialize, Deserialize)]
pub struct McpServerSuggestionDto {
    pub name: String,
    /// The Streamable HTTP endpoint.
    pub url: String,
    pub kind: McpServerKind,
    /// ISO 3166-1 alpha-2 code of the operator's country, shown as its flag.
    pub country_code: String,
}

/// The common MCP servers, offered when adding one. Served by
/// `GET /api/v1/mcp-servers/suggestions`.
pub(crate) fn mcp_server_suggestions() -> Vec<McpServerSuggestionDto> {
    crate::data::mcp_servers::SUGGESTIONS
        .iter()
        .map(|s| McpServerSuggestionDto {
            name: s.name.to_owned(),
            url: s.url.to_owned(),
            kind: s.kind,
            country_code: s.country_code.to_owned(),
        })
        .collect()
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
