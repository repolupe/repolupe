//! The tools of the user's MCP servers and the ones shared with them, see
//! [`crate::service::mcp`]. The model calls them as
//! `mcp__<server>__<tool>`: `<server>` is a slug of the server's name (lowercase letters,
//! digits and single `_`), `<tool>` the tool's own name, with characters the LLM APIs reject
//! replaced. Names that would be longer than 64 characters get a hash instead of their end.
//!
//! The tools come from the list stored at the last connection, so the definitions stay the
//! same during the answer. A server is connected to on its first call of the answer.
//!
//! An answer gets at most [`MAX_TOOLS`] MCP tools, with definitions of at most
//! [`MAX_DEFINITION_BYTES`] together, shared fairly by the servers (see [`select`]).
//!
//! The model sees only errors and short results of the tools: the results are stored for
//! [`RUN_SCRIPT`], so the model processes them with scripts instead of reading them, see
//! [`super::support::results`].

use super::support::MAX_OUTPUT_CHARS;
use super::support::results::{ResultValue, StoredResults};
use super::{Call, RUN_SCRIPT, ToolError};
use crate::model::mcp_server::McpTool;
use crate::service::llm::ToolDefinition;
use crate::service::mcp::{
    ConnectError, McpClient, McpSession, McpTarget, hide_url, maybe_processed, service_error,
};
use chrono::{DateTime, Utc};
use rmcp::model::{CallToolRequestParams, CallToolResult, ContentBlock, ResourceContents};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

pub(crate) const PREFIX: &str = "mcp__";
/// The longest tool names the LLM APIs accept.
const MAX_NAME_LENGTH: usize = 64;
const MAX_SLUG_LENGTH: usize = 20;
const HASH_LENGTH: usize = 8;
const CALL_TIMEOUT: Duration = Duration::from_mins(2);
/// OpenAI accepts at most 128 tools per request, which leaves room for the built-in ones.
const MAX_TOOLS: usize = 100;
/// Some 30k to 40k tokens, sent with every request of an answer.
pub(crate) const MAX_DEFINITION_BYTES: usize = 128 * 1024;

/// A server whose tools the model gets, with how to connect to it.
pub(crate) struct McpServerTools {
    pub(crate) target: McpTarget,
    /// The server's `updated_at` when `target` was read, see
    /// [`McpClient::require_authorization`].
    pub(crate) updated_at: DateTime<Utc>,
    pub(crate) name: String,
    /// The owner's user name if the server is shared with the user, `None` for their own.
    pub(crate) shared_by: Option<String>,
    pub(crate) tools: Vec<McpTool>,
}

/// The MCP tools of an answer.
#[derive(Default)]
pub(super) struct McpTools {
    client: Option<Arc<McpClient>>,
    servers: Vec<Server>,
    /// The name the model calls a tool by, to its server and tool.
    names: BTreeMap<String, (usize, usize)>,
}

struct Server {
    target: McpTarget,
    updated_at: DateTime<Utc>,
    name: String,
    shared_by: Option<String>,
    /// With the names the model calls them by.
    tools: Vec<(String, McpTool)>,
    /// Opened by the first call.
    session: Mutex<Option<Arc<McpSession>>>,
}

pub(super) struct Args {
    server: usize,
    tool: usize,
    arguments: Map<String, Value>,
}

impl McpTools {
    pub(super) fn new(client: Arc<McpClient>, servers: Vec<McpServerTools>) -> Self {
        Self::build(Some(client), servers)
    }

    /// Without a client for tests, which then can't connect.
    fn build(client: Option<Arc<McpClient>>, mut servers: Vec<McpServerTools>) -> Self {
        select(&mut servers);
        let mut slugs = BTreeSet::new();
        let mut names = BTreeMap::new();
        let servers = servers
            .into_iter()
            .enumerate()
            .map(|(index, server)| {
                let base = slug(&server.name);
                let mut slug = base.clone();
                let mut n = 2;
                while !slugs.insert(slug.clone()) {
                    slug = format!("{base}_{n}");
                    n += 1;
                }
                let tools = server
                    .tools
                    .into_iter()
                    .enumerate()
                    .map(|(tool_index, tool)| {
                        let base = tool_name(&slug, &tool.name);
                        let mut name = base.clone();
                        let mut n = 2;
                        while names.contains_key(&name) {
                            name = tool_name(&slug, &format!("{}_{n}", tool.name));
                            n += 1;
                        }
                        names.insert(name.clone(), (index, tool_index));
                        (name, tool)
                    })
                    .collect();
                Server {
                    target: server.target,
                    updated_at: server.updated_at,
                    name: server.name,
                    shared_by: server.shared_by,
                    tools,
                    session: Mutex::new(None),
                }
            })
            .collect();
        Self {
            client,
            servers,
            names,
        }
    }

    /// Whether the model gets any MCP tools.
    pub(super) fn has_tools(&self) -> bool {
        !self.names.is_empty()
    }

    /// The names of the servers whose tools the model gets, with the owner's user name for the
    /// ones shared with the user.
    pub(super) fn server_names(&self) -> Vec<(&str, Option<&str>)> {
        self.servers
            .iter()
            .filter(|s| !s.tools.is_empty())
            .map(|s| (s.name.as_str(), s.shared_by.as_deref()))
            .collect()
    }

    pub(super) fn definitions(&self) -> impl Iterator<Item = ToolDefinition> + '_ {
        self.servers.iter().flat_map(|server| {
            server.tools.iter().map(|(name, tool)| {
                let about = tool
                    .description
                    .as_deref()
                    .or(tool.title.as_deref())
                    .unwrap_or_default();
                ToolDefinition {
                    name: name.clone(),
                    description: format!(
                        "A tool of the MCP server \"{}\", an external service {}. Its result \
                        is stored for {RUN_SCRIPT}, and shown to you only if it is short. \
                        {about}",
                        server.name,
                        match &server.shared_by {
                            Some(owner) => format!("{owner} shared with the user"),
                            None => "the user connected".to_string(),
                        }
                    )
                    .trim_end()
                    .to_string(),
                    input_schema: Value::Object(tool.input_schema.clone()),
                }
            })
        })
    }

    /// `None` if there is no MCP tool named `name`.
    pub(super) fn parse(&self, name: &str, input: &Value) -> Option<Result<Call, String>> {
        let &(server, tool) = self.names.get(name)?;
        Some(match input {
            Value::Object(arguments) => Ok(Call::Mcp(Args {
                server,
                tool,
                arguments: arguments.clone(),
            })),
            Value::Null => Ok(Call::Mcp(Args {
                server,
                tool,
                arguments: Map::new(),
            })),
            _ => Err(format!("The arguments of {name} must be a JSON object.")),
        })
    }

    /// Stores the result in `results`, the model only gets errors and short results.
    pub(super) async fn run(
        &self,
        args: &Args,
        results: &StoredResults,
    ) -> Result<String, ToolError> {
        let server = &self.servers[args.server];
        let (_, tool) = &server.tools[args.tool];
        let session = self.session(server).await?;
        let params =
            CallToolRequestParams::new(tool.name.clone()).with_arguments(args.arguments.clone());
        let result = match tokio::time::timeout(CALL_TIMEOUT, session.call_tool(params)).await {
            Ok(Ok(result)) => result,
            Ok(Err(e)) if maybe_processed(&e) => {
                tracing::info!(
                    "Lost the connection to MCP server {} during a tool call: {e}",
                    server.target.id
                );
                return Err(ToolError::Invalid(format!(
                    "The connection to the MCP server \"{}\" was lost during the call. The \
                    tool may or may not have run, so check that before calling it again.",
                    server.name
                )));
            }
            Ok(Err(e)) => {
                return Err(self
                    .failure(server, service_error(&e, server.target.id))
                    .await);
            }
            Err(_) => {
                return Err(ToolError::Invalid(format!(
                    "The MCP server \"{}\" did not respond within {} minutes.",
                    server.name,
                    CALL_TIMEOUT.as_secs() / 60
                )));
            }
        };
        if result.is_error == Some(true) {
            return Err(ToolError::Invalid(error_text(result)));
        }
        match result_value(result) {
            Some(value) => results.store(value),
            None => Ok("The tool returned nothing.".to_string()),
        }
    }

    /// The session with the server, connecting on the first call. Calls running at the same
    /// time share it.
    async fn session(&self, server: &Server) -> Result<Arc<McpSession>, ToolError> {
        let mut session = server.session.lock().await;
        if let Some(session) = session.as_ref() {
            return Ok(session.clone());
        }
        let client = self.client.as_ref().ok_or_else(|| {
            ToolError::Internal(crate::config::error::AppError::InternalServerError(
                "MCP tools without a client".to_string(),
            ))
        })?;
        match client.connect(&server.target).await {
            Ok(connected) => Ok(session.insert(Arc::new(connected)).clone()),
            Err(e) => Err(self.failure(server, e).await),
        }
    }

    /// The result for the model when the server failed. A server that wants a new sign-in is
    /// marked as such, so its tools are not offered until the user signed in again. One that
    /// refused the request (HTTP 403) fails only this call: the credentials may lack a
    /// permission for it, but are still valid. For servers shared with the user, the reasons
    /// leave out the server's URL but its origin, which may contain the owner's key.
    async fn failure(&self, server: &Server, error: ConnectError) -> ToolError {
        match error {
            ConnectError::AuthorizationRequired { .. } => {
                if let Some(client) = &self.client {
                    client
                        .require_authorization(server.target.id, server.updated_at)
                        .await;
                }
                let who = match &server.shared_by {
                    Some(owner) => format!("Its owner, {owner}, who shared it with the user,"),
                    None => "The user".to_string(),
                };
                ToolError::Invalid(format!(
                    "The MCP server \"{}\" rejected the credentials. {who} has to sign in to it \
                    again (or set a new token) in the settings.",
                    server.name
                ))
            }
            ConnectError::Forbidden { .. } => {
                let reason = if error.insufficient_scope() {
                    "It needs a permission (OAuth scope) the user did not grant."
                } else {
                    "The credentials may lack a permission for it."
                };
                ToolError::Invalid(format!(
                    "The MCP server \"{}\" refused the request (HTTP 403 Forbidden). {reason}",
                    server.name
                ))
            }
            ConnectError::Failed(message) => {
                // May contain its URL, e.g. in the errors of requests.
                let message = match server.shared_by {
                    Some(_) => hide_url(&message, &server.target.url),
                    None => message,
                };
                ToolError::Invalid(format!(
                    "The MCP server \"{}\" failed: {message}",
                    server.name
                ))
            }
        }
    }
}

#[cfg(test)]
impl McpTools {
    /// The tools `tools` of a server named `name`, without a client, so calls fail.
    pub(super) fn unconnected(name: &str, tools: &[&str]) -> Self {
        Self::build(None, vec![tests::server(name, tools)])
    }
}

/// Leaves out the tools beyond [`MAX_TOOLS`] and [`MAX_DEFINITION_BYTES`]. The servers take
/// turns, one tool each in their order, so each gets a fair share. A tool too large for the
/// bytes left is skipped, the following ones may still fit.
fn select(servers: &mut [McpServerTools]) {
    let mut keep: Vec<Vec<bool>> = servers
        .iter()
        .map(|server| vec![false; server.tools.len()])
        .collect();
    let rounds = servers.iter().map(|s| s.tools.len()).max().unwrap_or(0);
    let mut count = 0;
    let mut bytes = 0;
    'rounds: for round in 0..rounds {
        for (server, keep) in servers.iter().zip(&mut keep) {
            let Some(tool) = server.tools.get(round) else {
                continue;
            };
            if count == MAX_TOOLS {
                break 'rounds;
            }
            let size = tool.definition_bytes;
            if bytes + size <= MAX_DEFINITION_BYTES {
                keep[round] = true;
                count += 1;
                bytes += size;
            }
        }
    }
    for (server, keep) in servers.iter_mut().zip(keep) {
        let total = server.tools.len();
        let mut keep = keep.into_iter();
        server.tools.retain(|_| keep.next().unwrap_or(false));
        if server.tools.len() < total {
            tracing::info!(
                "Offering {} of the {total} tools of MCP server {}, too many tools altogether",
                server.tools.len(),
                server.target.id
            );
        }
    }
}

/// About the size of the tool's definition as sent to the LLM, with `schema_bytes` the size of
/// its schema as JSON. Stored with the tool as [`McpTool::definition_bytes`].
pub(crate) fn definition_bytes(tool: &McpTool, schema_bytes: usize) -> usize {
    let about = tool.description.as_ref().or(tool.title.as_ref());
    schema_bytes.saturating_add(tool.name.len() + about.map_or(0, String::len))
}

/// What the tool returned: its structured content, or else its content as text, parsed if it
/// is a JSON object or array, as tools often return JSON as text. `None` if it returned nothing.
fn result_value(result: CallToolResult) -> Option<ResultValue> {
    if let Some(structured) = result.structured_content {
        return Some(ResultValue::Json(structured));
    }
    let text = content_text(result.content);
    if text.is_empty() {
        return None;
    }
    if text.trim_start().starts_with(['{', '['])
        && let Ok(value) = serde_json::from_str(&text)
    {
        return Some(ResultValue::Json(value));
    }
    Some(ResultValue::Text(text))
}

/// What a failed call returned, cut at [`MAX_OUTPUT_CHARS`].
fn error_text(result: CallToolResult) -> String {
    let mut text = content_text(result.content);
    if text.is_empty()
        && let Some(structured) = result.structured_content
    {
        text = serde_json::to_string_pretty(&structured).unwrap_or_default();
    }
    if text.is_empty() {
        return "The tool failed without saying why.".to_string();
    }
    match text.char_indices().nth(MAX_OUTPUT_CHARS) {
        Some((end, _)) => format!(
            "{}\n\n[The result was cut at {MAX_OUTPUT_CHARS} characters.]",
            &text[..end]
        ),
        None => text,
    }
}

/// The content as text. Images and audio are only described, since tool results are text here.
fn content_text(content: Vec<ContentBlock>) -> String {
    content
        .into_iter()
        .map(|block| match block {
            ContentBlock::Text(text) => text.text,
            ContentBlock::Image(image) => format!("[An image ({}) not shown]", image.mime_type),
            ContentBlock::Audio(audio) => format!("[Audio ({}) not shown]", audio.mime_type),
            ContentBlock::Resource(resource) => match resource.resource {
                ResourceContents::TextResourceContents { uri, text, .. } => {
                    format!("[Resource {uri}]\n{text}")
                }
                ResourceContents::BlobResourceContents { uri, mime_type, .. } => format!(
                    "[Resource {uri} ({}) not shown]",
                    mime_type.as_deref().unwrap_or("binary")
                ),
                _ => "[A resource of an unknown kind not shown]".to_string(),
            },
            ContentBlock::ResourceLink(link) => format!("[Resource {}: {}]", link.name, link.uri),
            _ => "[Content of an unknown kind not shown]".to_string(),
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

/// Lowercase ASCII letters and digits, separated by single `_`.
fn slug(name: &str) -> String {
    let mut slug = String::new();
    for c in name.chars() {
        if c.is_ascii_alphanumeric() {
            slug.push(c.to_ascii_lowercase());
        } else if !slug.is_empty() && !slug.ends_with('_') {
            slug.push('_');
        }
    }
    let mut slug: String = slug.chars().take(MAX_SLUG_LENGTH).collect();
    while slug.ends_with('_') {
        slug.pop();
    }
    if slug.is_empty() {
        "server".to_string()
    } else {
        slug
    }
}

/// `mcp__<slug>__<tool>`, with the characters of `tool` the LLM APIs reject replaced, and a
/// hash of `tool` instead of its end if it would be too long.
fn tool_name(slug: &str, tool: &str) -> String {
    let prefix = format!("{PREFIX}{slug}__");
    let sanitized: String = tool
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if prefix.len() + sanitized.len() <= MAX_NAME_LENGTH {
        return format!("{prefix}{sanitized}");
    }
    let hash = hex::encode(Sha256::digest(tool.as_bytes()));
    let keep = MAX_NAME_LENGTH - prefix.len() - HASH_LENGTH - 1;
    format!("{prefix}{}_{}", &sanitized[..keep], &hash[..HASH_LENGTH])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::remote_access::RemoteAccess;
    use crate::service::mcp::Credentials;
    use serde_json::json;
    use uuid::Uuid;

    fn tool(name: &str) -> McpTool {
        McpTool {
            name: name.to_string(),
            title: None,
            description: Some("Does things.".to_string()),
            input_schema: json!({"type": "object"}).as_object().unwrap().clone(),
            definition_bytes: 100,
        }
    }

    pub(super) fn server(name: &str, tools: &[&str]) -> McpServerTools {
        McpServerTools {
            target: McpTarget {
                id: Uuid::now_v7(),
                url: "https://mcp.example.com/mcp".to_string(),
                access: RemoteAccess::Public,
                credentials: Credentials::None,
            },
            updated_at: Utc::now(),
            name: name.to_string(),
            shared_by: None,
            tools: tools.iter().map(|t| tool(t)).collect(),
        }
    }

    fn tools(servers: Vec<McpServerTools>) -> McpTools {
        McpTools::build(None, servers)
    }

    #[test]
    fn slugs_names() {
        assert_eq!(slug("Linear"), "linear");
        assert_eq!(slug("My  Server (prod)"), "my_server_prod");
        assert_eq!(slug("--Ünïcode--"), "n_code");
        assert_eq!(slug("日本"), "server");
        assert_eq!(
            slug("a very long server name indeed"),
            "a_very_long_server_n"
        );
        assert_eq!(slug("abcdefghijklmnopqrs_t"), "abcdefghijklmnopqrs");
    }

    #[test]
    fn names_tools() {
        assert_eq!(
            tool_name("linear", "list_issues"),
            "mcp__linear__list_issues"
        );
        assert_eq!(tool_name("x", "get.user/info"), "mcp__x__get_user_info");
        let long = "a".repeat(80);
        let name = tool_name("linear", &long);
        assert_eq!(name.len(), MAX_NAME_LENGTH);
        assert!(name.starts_with("mcp__linear__aaaa"));
        assert_ne!(name, tool_name("linear", &format!("{long}b")));
    }

    #[test]
    fn keeps_names_unique() {
        let mut wiki = server("Wiki", &["a.b", "a_b"]);
        wiki.shared_by = Some("alice".to_string());
        let tools = tools(vec![
            server("Docs", &["search", "search"]),
            server("docs", &["search"]),
            wiki,
        ]);
        let names: Vec<String> = tools.definitions().map(|d| d.name).collect();
        assert_eq!(
            names,
            [
                "mcp__docs__search",
                "mcp__docs__search_2",
                "mcp__docs_2__search",
                "mcp__wiki__a_b",
                "mcp__wiki__a_b_2",
            ]
        );
        assert_eq!(
            tools.server_names(),
            [("Docs", None), ("docs", None), ("Wiki", Some("alice"))]
        );
        let descriptions: Vec<String> = tools.definitions().map(|d| d.description).collect();
        assert_eq!(
            descriptions[0],
            "A tool of the MCP server \"Docs\", an external service the user connected. Its \
            result is stored for run_script, and shown to you only if it is short. Does things."
        );
        assert_eq!(
            descriptions[3],
            "A tool of the MCP server \"Wiki\", an external service alice shared with the user. \
            Its result is stored for run_script, and shown to you only if it is short. Does \
            things."
        );
    }

    #[test]
    fn shares_the_tools_among_servers() {
        let names =
            |prefix: &str| -> Vec<String> { (0..70).map(|n| format!("{prefix}{n}")).collect() };
        let (a, b) = (names("a"), names("b"));
        let a: Vec<&str> = a.iter().map(String::as_str).collect();
        let b: Vec<&str> = b.iter().map(String::as_str).collect();
        let tools = tools(vec![server("A", &a), server("B", &b)]);
        let names: Vec<String> = tools.definitions().map(|d| d.name).collect();
        assert_eq!(names.len(), MAX_TOOLS);
        assert_eq!(names[0], "mcp__a__a0");
        assert_eq!(names[49], "mcp__a__a49");
        assert_eq!(names[50], "mcp__b__b0");
    }

    #[test]
    fn skips_tools_beyond_the_bytes() {
        let mut large = server("A", &["large", "small"]);
        large.tools[0].definition_bytes = 100 * 1024;
        let mut other = server("B", &["large"]);
        other.tools[0].definition_bytes = 100 * 1024;
        let tools = tools(vec![large, other]);
        let names: Vec<String> = tools.definitions().map(|d| d.name).collect();
        assert_eq!(names, ["mcp__a__large", "mcp__a__small"]);
        assert_eq!(tools.server_names(), [("A", None)]);
    }

    #[test]
    fn parses_calls() {
        let tools = tools(vec![server("Docs", &["search"])]);
        assert!(tools.parse("mcp__docs__other", &json!({})).is_none());
        assert!(matches!(
            tools.parse("mcp__docs__search", &json!({"q": "x"})),
            Some(Ok(Call::Mcp(Args {
                server: 0,
                tool: 0,
                ..
            })))
        ));
        assert!(matches!(
            tools.parse("mcp__docs__search", &Value::Null),
            Some(Ok(Call::Mcp(_)))
        ));
        assert_eq!(
            tools
                .parse("mcp__docs__search", &json!([1]))
                .unwrap()
                .err()
                .unwrap(),
            "The arguments of mcp__docs__search must be a JSON object."
        );
    }

    #[test]
    fn converts_results() {
        let text = |t: &str| ContentBlock::text(t);
        let value = |content: Vec<ContentBlock>, structured: Option<Value>| {
            let mut result = CallToolResult::success(content);
            result.structured_content = structured;
            result_value(result).map(|value| match value {
                ResultValue::Text(text) => json!({"text": text}),
                ResultValue::Json(json) => json!({"json": json}),
            })
        };
        assert_eq!(
            value(vec![text("one"), text("two")], None),
            Some(json!({"text": "one\n\ntwo"}))
        );
        // Tools often return JSON as text.
        assert_eq!(
            value(vec![text(" [1, {\"a\": 2}]")], None),
            Some(json!({"json": [1, {"a": 2}]}))
        );
        assert_eq!(
            value(vec![text("{not JSON}")], None),
            Some(json!({"text": "{not JSON}"}))
        );
        assert_eq!(value(vec![text("42")], None), Some(json!({"text": "42"})));
        assert_eq!(
            value(vec![text("summary")], Some(json!({"a": 1}))),
            Some(json!({"json": {"a": 1}}))
        );
        assert_eq!(value(Vec::new(), None), None);
    }

    #[test]
    fn shows_errors() {
        let mut failed = CallToolResult::error(Vec::new());
        assert_eq!(
            error_text(failed.clone()),
            "The tool failed without saying why."
        );
        failed.structured_content = Some(json!({"a": 1}));
        assert_eq!(error_text(failed.clone()), "{\n  \"a\": 1\n}");
        failed.content = vec![ContentBlock::text("x".repeat(MAX_OUTPUT_CHARS + 1))];
        assert!(error_text(failed).ends_with("[The result was cut at 40000 characters.]"));
    }
}
