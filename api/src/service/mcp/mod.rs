//! The MCP client: connects to the MCP servers users added (Streamable HTTP only), lists their
//! tools and calls them for [`crate::service::tools`].
//!
//! Like remotes, servers of users other than admins are only reached over https at public
//! addresses ([`RemoteAccess`]), and so are the authorization servers they sign in with
//! ([`oauth`]). Each answer connects once to each server it calls a tool of.

mod oauth;

use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::dto::mcp::McpServerStatus;
use crate::model::mcp_server::{McpServer, McpTool};
use crate::model::remote_access::RemoteAccess;
use crate::repository;
use crate::repository::mcp::Connection;
use crate::util::http::client_builder;
use crate::util::ip::{NotPublic, PublicResolver, has_public_host, is_not_public};
use crate::util::token_cipher::TokenCipher;
use chrono::Utc;
use oauth::{OAuthHttp, PendingSignIns};
use reqwest::StatusCode;
use reqwest::redirect::{Attempt, Policy};
use rmcp::ServiceExt;
use rmcp::model::{ClientCapabilities, ClientConfig, Implementation, Tool};
use rmcp::service::{ClientInitializeError, RoleClient, RunningService, ServiceError};
use rmcp::transport::StreamableHttpClientTransport;
use rmcp::transport::auth::{AuthClient, AuthError};
use rmcp::transport::streamable_http_client::{
    AuthRequiredError, InsufficientScopeError, StreamableHttpClientTransportConfig,
    StreamableHttpError,
};
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::error::Error;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use url::Url;
use uuid::Uuid;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// For connecting (the initialize handshake) and for listing the tools.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(30);
/// For closing a session, which tells the server to drop it.
const CLOSE_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_REDIRECTS: usize = 5;
/// Tools of a server beyond this are left out, so they don't crowd the prompt.
const MAX_TOOLS: usize = 100;
/// Longer descriptions of tools are cut.
const MAX_DESCRIPTION_CHARS: usize = 2_000;
/// Tools with larger argument schemas are left out.
const MAX_SCHEMA_BYTES: usize = 64 * 1024;
const USER_AGENT: &str = concat!("repolupe/", env!("CARGO_PKG_VERSION"));

/// A connection to an MCP server. Dropping it closes it in the background, [`close`] waits.
pub(crate) type McpSession = RunningService<RoleClient, ClientConfig>;

/// The HTTP clients for MCP servers and their authorization servers. Holds connection pools,
/// so share one instance.
pub(crate) struct McpHttp {
    public: Clients,
    unrestricted: Clients,
}

struct Clients {
    mcp: reqwest::Client,
    oauth: Arc<OAuthHttp>,
}

impl McpHttp {
    pub(crate) fn new() -> Result<Self, reqwest::Error> {
        Ok(Self {
            public: Clients::new(RemoteAccess::Public)?,
            unrestricted: Clients::new(RemoteAccess::Unrestricted)?,
        })
    }

    fn clients(&self, access: RemoteAccess) -> &Clients {
        match access {
            RemoteAccess::Public => &self.public,
            RemoteAccess::Unrestricted => &self.unrestricted,
        }
    }
}

impl Clients {
    fn new(access: RemoteAccess) -> Result<Self, reqwest::Error> {
        Ok(Self {
            // No overall timeout: tool calls may stream their results for a while.
            mcp: builder(access).redirect(redirect_policy(access)).build()?,
            oauth: Arc::new(OAuthHttp::new(access)?),
        })
    }
}

/// Without the proxy environment variables, which would resolve the hosts instead of
/// [`PublicResolver`].
fn builder(access: RemoteAccess) -> reqwest::ClientBuilder {
    let builder = client_builder()
        .no_proxy()
        .connect_timeout(CONNECT_TIMEOUT)
        .user_agent(USER_AGENT);
    match access {
        RemoteAccess::Public => builder.https_only(true).dns_resolver(PublicResolver),
        RemoteAccess::Unrestricted => builder,
    }
}

fn redirect_policy(access: RemoteAccess) -> Policy {
    match access {
        RemoteAccess::Public => Policy::custom(check_redirect),
        RemoteAccess::Unrestricted => Policy::limited(MAX_REDIRECTS),
    }
}

/// [`PublicResolver`] never sees IP addresses in redirects, so they are checked here.
fn check_redirect(attempt: Attempt) -> reqwest::redirect::Action {
    if attempt.previous().len() >= MAX_REDIRECTS {
        attempt.error("too many redirects")
    } else if !has_public_host(attempt.url()) {
        attempt.error(NotPublic)
    } else {
        attempt.follow()
    }
}

/// Connects to the MCP servers of users and signs them in.
pub(crate) struct McpClient {
    http: McpHttp,
    /// For the OAuth credentials, which rmcp loads and stores through [`oauth`].
    db: DatabasePool,
    cipher: Arc<TokenCipher>,
    /// The OAuth clients of the servers users signed in to, so the metadata of their
    /// authorization servers is discovered once, not for every connection. Dropped when the
    /// server is deleted or its credentials change.
    auth: Mutex<HashMap<Uuid, CachedAuth>>,
    sign_ins: PendingSignIns,
}

struct CachedAuth {
    url: String,
    access: RemoteAccess,
    client: AuthClient<reqwest::Client>,
}

/// How to connect to a server.
pub(crate) struct McpTarget {
    pub(crate) id: Uuid,
    pub(crate) url: String,
    /// From the role of the server's owner.
    pub(crate) access: RemoteAccess,
    pub(crate) credentials: Credentials,
}

pub(crate) enum Credentials {
    None,
    /// Sent as a bearer token.
    Token(String),
    /// The OAuth tokens stored with the server, refreshed when they expire.
    OAuth,
}

impl McpTarget {
    pub(crate) fn new(
        server: &McpServer,
        access: RemoteAccess,
        cipher: &TokenCipher,
    ) -> Result<Self, AppError> {
        let credentials = match (&server.token_encrypted, &server.oauth_encrypted) {
            (Some(token), _) => {
                Credentials::Token(cipher.decrypt(server.id, token).map_err(|e| {
                    AppError::InternalServerError(format!(
                        "Failed to decrypt the token of MCP server {}: {e}",
                        server.id
                    ))
                })?)
            }
            (None, Some(_)) => Credentials::OAuth,
            (None, None) => Credentials::None,
        };
        Ok(Self {
            id: server.id,
            url: server.url.clone(),
            access,
            credentials,
        })
    }
}

/// Why connecting to a server failed.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub(crate) enum ConnectError {
    /// The server asks for authentication, or rejected the token or the OAuth credentials.
    #[error("The server requires authentication")]
    AuthorizationRequired {
        /// The server's `WWW-Authenticate` header, which may point to its OAuth metadata.
        challenge: Option<String>,
    },
    /// For the user, without internals.
    #[error("{0}")]
    Failed(String),
}

impl ConnectError {
    fn failed(message: &str) -> Self {
        Self::Failed(message.to_string())
    }

    /// How the server is stored after the failure.
    pub(crate) fn connection(&self) -> Connection<'_> {
        let (status, last_error) = match self {
            ConnectError::AuthorizationRequired { .. } => {
                (McpServerStatus::AuthorizationRequired, None)
            }
            ConnectError::Failed(message) => (McpServerStatus::Failed, Some(message.as_str())),
        };
        Connection {
            status,
            last_error,
            tools: None,
            checked_at: Utc::now(),
        }
    }
}

impl McpClient {
    pub(crate) fn new(http: McpHttp, db: DatabasePool, cipher: Arc<TokenCipher>) -> Self {
        Self {
            http,
            db,
            cipher,
            auth: Mutex::new(HashMap::new()),
            sign_ins: PendingSignIns::default(),
        }
    }

    /// Opens a session with the server: connects and initializes.
    pub(crate) async fn connect(&self, target: &McpTarget) -> Result<McpSession, ConnectError> {
        check_url(&target.url, target.access)?;
        let http = self.http.clients(target.access).mcp.clone();
        let config = StreamableHttpClientTransportConfig::with_uri(target.url.as_str());
        let handshake = async {
            match &target.credentials {
                Credentials::None => {
                    client_config()
                        .serve(StreamableHttpClientTransport::with_client(http, config))
                        .await
                }
                Credentials::Token(token) => {
                    let config = config.auth_header(token.clone());
                    client_config()
                        .serve(StreamableHttpClientTransport::with_client(http, config))
                        .await
                }
                Credentials::OAuth => {
                    let client = match self.auth_client(target).await {
                        Ok(client) => client,
                        Err(e) => return Ok(Err(e)),
                    };
                    client_config()
                        .serve(StreamableHttpClientTransport::with_client(client, config))
                        .await
                }
            }
            .map(Ok)
        };
        match tokio::time::timeout(HANDSHAKE_TIMEOUT, handshake).await {
            Ok(Ok(Ok(session))) => Ok(session),
            Ok(Ok(Err(e))) => Err(e),
            Ok(Err(e)) => Err(initialize_error(&e, target.id)),
            Err(_) => Err(ConnectError::failed("The server did not respond in time")),
        }
    }

    /// Connects to the server and lists its tools.
    pub(crate) async fn list_tools(
        &self,
        target: &McpTarget,
    ) -> Result<Vec<McpTool>, ConnectError> {
        let session = self.connect(target).await?;
        let listed = tokio::time::timeout(HANDSHAKE_TIMEOUT, session.list_all_tools()).await;
        close(session).await;
        let tools = match listed {
            Ok(Ok(tools)) => tools,
            Ok(Err(e)) => return Err(service_error(&e, target.id)),
            Err(_) => {
                return Err(ConnectError::failed(
                    "The server did not list its tools in time",
                ));
            }
        };
        Ok(tools
            .into_iter()
            .filter_map(|tool| stored_tool(tool, target.id))
            .take(MAX_TOOLS)
            .collect())
    }

    /// Lists the tools of `server` and stores the outcome, unless the server was changed in
    /// the meantime. Returns the server as stored.
    pub(crate) async fn refresh(
        &self,
        server: McpServer,
        access: RemoteAccess,
    ) -> Result<McpServer, AppError> {
        let target = McpTarget::new(&server, access, &self.cipher)?;
        let result = self.list_tools(&target).await;
        let connection = match &result {
            Ok(tools) => Connection {
                status: McpServerStatus::Ready,
                last_error: None,
                tools: Some(tools),
                checked_at: Utc::now(),
            },
            Err(e) => e.connection(),
        };
        let updated =
            repository::mcp::record_connection(&self.db, server.id, &server.url, connection)
                .await?;
        Ok(updated.unwrap_or(server))
    }

    /// Marks the server as needing a new sign-in, after it rejected the credentials during an
    /// answer. Its tools are offered again once the user signed in.
    pub(crate) async fn require_authorization(&self, id: Uuid, url: &str) {
        self.forget(id);
        let connection = ConnectError::AuthorizationRequired { challenge: None };
        if let Err(e) =
            repository::mcp::record_connection(&self.db, id, url, connection.connection()).await
        {
            tracing::warn!("Failed to mark MCP server {id} as requiring authorization: {e}");
        }
    }

    /// Drops the cached OAuth client of the server, after it was deleted or its credentials
    /// changed.
    pub(crate) fn forget(&self, id: Uuid) {
        self.auth.lock().unwrap().remove(&id);
    }

    /// The OAuth client of a server the user signed in to.
    async fn auth_client(
        &self,
        target: &McpTarget,
    ) -> Result<AuthClient<reqwest::Client>, ConnectError> {
        if let Some(cached) = self.auth.lock().unwrap().get(&target.id)
            && cached.url == target.url
            && cached.access == target.access
        {
            return Ok(cached.client.clone());
        }
        // Discovers the metadata, so the lock is not held meanwhile. Concurrent connections
        // may both discover it, the last one is kept.
        let manager = oauth::signed_in_manager(self, target).await?;
        let client = AuthClient::new(self.http.clients(target.access).mcp.clone(), manager);
        self.auth.lock().unwrap().insert(
            target.id,
            CachedAuth {
                url: target.url.clone(),
                access: target.access,
                client: client.clone(),
            },
        );
        Ok(client)
    }

    /// Starts signing in to `server` with OAuth. Returns the URL to send the user to, who comes
    /// back to `redirect_uri` with what [`Self::complete_sign_in`] needs.
    pub(crate) async fn start_sign_in(
        &self,
        user_id: Uuid,
        server: &McpServer,
        access: RemoteAccess,
        redirect_uri: &str,
    ) -> Result<String, AppError> {
        oauth::start_sign_in(self, user_id, server, access, redirect_uri).await
    }

    /// Completes signing in with what the authorization server sent the user back with, and
    /// stores the credentials with the server. Returns the server's id.
    pub(crate) async fn complete_sign_in(
        &self,
        user_id: Uuid,
        state: &str,
        code: &str,
        issuer: Option<&str>,
    ) -> Result<Uuid, AppError> {
        let id = oauth::complete_sign_in(self, user_id, state, code, issuer).await?;
        self.forget(id);
        Ok(id)
    }
}

/// Closes the session, telling the server to drop it. Waits only briefly.
pub(crate) async fn close(mut session: McpSession) {
    if tokio::time::timeout(CLOSE_TIMEOUT, session.close())
        .await
        .is_err()
    {
        tracing::debug!("Closing an MCP session timed out");
    }
}

/// Identifies Repolupe to the servers. It offers none of the optional client capabilities
/// (sampling, roots, elicitation).
fn client_config() -> ClientConfig {
    ClientConfig::new(
        ClientCapabilities::default(),
        Implementation::new("repolupe", env!("CARGO_PKG_VERSION")).with_title("Repolupe"),
    )
}

/// Checks what [`PublicResolver`] cannot: IP addresses in the URL are never resolved.
fn check_url(url: &str, access: RemoteAccess) -> Result<(), ConnectError> {
    let url = Url::parse(url).map_err(|_| ConnectError::failed("The URL is not valid"))?;
    if access == RemoteAccess::Public && (url.scheme() != "https" || !has_public_host(&url)) {
        return Err(not_public());
    }
    Ok(())
}

fn not_public() -> ConnectError {
    ConnectError::failed("The server's address is not public")
}

/// The tool as stored, `None` for tools the model cannot get.
fn stored_tool(tool: Tool, server_id: Uuid) -> Option<McpTool> {
    let Some(input_schema) = object_schema((*tool.input_schema).clone()) else {
        tracing::info!(
            "Leaving out the tool {} of MCP server {server_id}, its arguments are no object",
            tool.name
        );
        return None;
    };
    let size = serde_json::to_vec(&input_schema).map_or(usize::MAX, |json| json.len());
    if size > MAX_SCHEMA_BYTES {
        tracing::info!(
            "Leaving out the tool {} of MCP server {server_id}, its schema has {size} bytes",
            tool.name
        );
        return None;
    }
    let description = tool.description.map(|description| {
        let description = description.trim();
        match description.char_indices().nth(MAX_DESCRIPTION_CHARS) {
            Some((end, _)) => format!("{}…", &description[..end]),
            None => description.to_string(),
        }
    });
    let title = tool
        .title
        .or_else(|| tool.annotations.and_then(|annotations| annotations.title));
    Some(McpTool {
        name: tool.name.into_owned(),
        title,
        description,
        input_schema,
    })
}

/// `schema` as the LLM APIs accept it: of type `object`, without `allOf`, `anyOf` or `oneOf`
/// at the top. Their variants are merged into the schema, so the model sees all arguments,
/// and the server checks how they combine. `None` for a schema of another type.
fn object_schema(mut schema: Map<String, Value>) -> Option<Map<String, Value>> {
    match schema.get("type") {
        None => {}
        Some(Value::String(t)) if t == "object" => {}
        // Such as ["object", "null"]: the arguments are always sent as an object.
        Some(Value::Array(types)) if types.iter().any(|t| t == "object") => {}
        Some(_) => return None,
    }
    schema.insert("type".to_string(), Value::from("object"));
    for (keyword, all) in [("allOf", true), ("anyOf", false), ("oneOf", false)] {
        if let Some(Value::Array(variants)) = schema.remove(keyword) {
            merge_variants(&mut schema, &variants, all);
        }
    }
    Some(schema)
}

/// Adds the properties of the `variants` to those of `schema`, which keeps its own. A property
/// several variants define differently gets those definitions as `allOf` if `all` variants
/// apply, as `anyOf` otherwise. Required are the properties that any variant requires if `all`
/// apply, otherwise those that every variant requires.
fn merge_variants(schema: &mut Map<String, Value>, variants: &[Value], all: bool) {
    let mut definitions: Vec<(&String, Vec<&Value>)> = Vec::new();
    let mut required: Option<Vec<&str>> = None;
    for variant in variants {
        // A variant that is no inline object schema (such as a `$ref`) adds no properties,
        // but may let all of them be left out.
        let variant = variant.as_object();
        if let Some(Value::Object(properties)) = variant.and_then(|v| v.get("properties")) {
            for (name, definition) in properties {
                match definitions.iter_mut().find(|(n, _)| *n == name) {
                    Some((_, list)) if list.contains(&definition) => {}
                    Some((_, list)) => list.push(definition),
                    None => definitions.push((name, vec![definition])),
                }
            }
        }
        let names = variant.map(required_names).unwrap_or_default();
        required = Some(match required {
            None => names,
            Some(mut merged) if all => {
                for name in names {
                    if !merged.contains(&name) {
                        merged.push(name);
                    }
                }
                merged
            }
            Some(mut merged) => {
                merged.retain(|n| names.contains(n));
                merged
            }
        });
    }
    let mut merged_required: Vec<Value> = required
        .unwrap_or_default()
        .into_iter()
        .map(Value::from)
        .collect();
    let mut properties = match schema.remove("properties") {
        Some(Value::Object(properties)) => properties,
        _ => Map::new(),
    };
    for (name, list) in definitions {
        if properties.contains_key(name) {
            continue;
        }
        let definition = match list.as_slice() {
            [definition] => (*definition).clone(),
            list => {
                let keyword = if all { "allOf" } else { "anyOf" };
                let list = list.iter().map(|d| (*d).clone()).collect();
                Value::Object(Map::from_iter([(keyword.to_string(), Value::Array(list))]))
            }
        };
        properties.insert(name.clone(), definition);
    }
    if !properties.is_empty() {
        schema.insert("properties".to_string(), Value::Object(properties));
    }
    if let Some(Value::Array(own)) = schema.get("required") {
        merged_required.retain(|n| !own.contains(n));
        merged_required.splice(0..0, own.iter().cloned());
    }
    if !merged_required.is_empty() {
        schema.insert("required".to_string(), Value::Array(merged_required));
    }
}

fn required_names(schema: &Map<String, Value>) -> Vec<&str> {
    match schema.get("required") {
        Some(Value::Array(names)) => names.iter().filter_map(Value::as_str).collect(),
        _ => Vec::new(),
    }
}

/// Why the initialize handshake failed.
fn initialize_error(error: &ClientInitializeError, server_id: Uuid) -> ConnectError {
    match error {
        ClientInitializeError::TransportError { error, .. } => {
            transport_error(error.error.as_ref(), server_id)
        }
        ClientInitializeError::JsonRpcError(data) => ConnectError::Failed(format!(
            "The server refused the connection: {}",
            data.message
        )),
        ClientInitializeError::NoCompatibleProtocolVersion { .. } => {
            ConnectError::failed("The server supports none of the protocol versions of this client")
        }
        ClientInitializeError::ConnectionClosed(_) => {
            tracing::info!("MCP server {server_id} closed the connection: {error}");
            ConnectError::failed("The server closed the connection")
        }
        _ => {
            tracing::info!("Connecting to MCP server {server_id} failed: {error}");
            ConnectError::failed("The server did not respond like an MCP server")
        }
    }
}

/// Why a request to a connected server failed.
pub(crate) fn service_error(error: &ServiceError, server_id: Uuid) -> ConnectError {
    match error {
        ServiceError::McpError(data) => {
            ConnectError::Failed(format!("The server returned an error: {}", data.message))
        }
        ServiceError::TransportSend(error) => transport_error(error.error.as_ref(), server_id),
        ServiceError::TransportClosed => ConnectError::failed("The server closed the connection"),
        ServiceError::Timeout { .. } => ConnectError::failed("The server did not respond in time"),
        _ => {
            tracing::info!("Request to MCP server {server_id} failed: {error}");
            ConnectError::failed("The server did not respond like an MCP server")
        }
    }
}

/// Finds out from the errors in the chain of `error` why a request failed.
fn transport_error(error: &(dyn Error + Send + Sync + 'static), server_id: Uuid) -> ConnectError {
    let mut source: Option<&(dyn Error + 'static)> = Some(error);
    while let Some(e) = source {
        if let Some(e) = e.downcast_ref::<AuthRequiredError>() {
            return ConnectError::AuthorizationRequired {
                challenge: Some(e.www_authenticate_header.clone()),
            };
        }
        if let Some(e) = e.downcast_ref::<InsufficientScopeError>() {
            return ConnectError::AuthorizationRequired {
                challenge: Some(e.www_authenticate_header.clone()),
            };
        }
        if let Some(e) = e.downcast_ref::<StreamableHttpError<reqwest::Error>>() {
            match e {
                StreamableHttpError::AuthRequired(e) => {
                    return ConnectError::AuthorizationRequired {
                        challenge: Some(e.www_authenticate_header.clone()),
                    };
                }
                StreamableHttpError::InsufficientScope(e) => {
                    return ConnectError::AuthorizationRequired {
                        challenge: Some(e.www_authenticate_header.clone()),
                    };
                }
                StreamableHttpError::HttpStatus(e) => {
                    return ConnectError::Failed(format!(
                        "The server responded with HTTP {}",
                        e.status
                    ));
                }
                // Not a source of the error, so the loop would not find it.
                StreamableHttpError::Client(e) => return request_error(e, server_id),
                StreamableHttpError::UnexpectedServerResponse(message)
                    if rejects_credentials(message) =>
                {
                    return ConnectError::AuthorizationRequired { challenge: None };
                }
                StreamableHttpError::UnexpectedContentType(_)
                | StreamableHttpError::UnexpectedServerResponse(_)
                | StreamableHttpError::Deserialize(_)
                | StreamableHttpError::Sse(_) => {
                    tracing::info!("MCP server {server_id} sent an unexpected response: {e}");
                    return ConnectError::failed("The server did not respond like an MCP server");
                }
                _ => {}
            }
        }
        if let Some(e) = e.downcast_ref::<AuthError>() {
            return auth_error(e, server_id);
        }
        if let Some(e) = e.downcast_ref::<reqwest::Error>() {
            return request_error(e, server_id);
        }
        source = e.source();
    }
    tracing::info!("Request to MCP server {server_id} failed: {error}");
    ConnectError::Failed(format!("The request failed: {error}"))
}

fn auth_error(error: &AuthError, server_id: Uuid) -> ConnectError {
    match error {
        AuthError::AuthorizationRequired | AuthError::TokenRefreshRejected(_) => {
            ConnectError::AuthorizationRequired { challenge: None }
        }
        _ => {
            tracing::info!("Authorizing with MCP server {server_id} failed: {error}");
            ConnectError::Failed(format!("Authorizing failed: {error}"))
        }
    }
}

/// Whether rmcp's message is about a response with status 401 or 403. It reports those without
/// a `WWW-Authenticate` header only as `HTTP <status>: <body>`.
fn rejects_credentials(message: &str) -> bool {
    message.starts_with("HTTP 401 ") || message.starts_with("HTTP 403 ")
}

fn request_error(error: &reqwest::Error, server_id: Uuid) -> ConnectError {
    if is_not_public(error) {
        return not_public();
    }
    // From responses rmcp checked with `error_for_status`.
    if let Some(status) = error.status() {
        return if matches!(status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN) {
            ConnectError::AuthorizationRequired { challenge: None }
        } else {
            ConnectError::Failed(format!(
                "The server responded with HTTP {}",
                status.as_u16()
            ))
        };
    }
    tracing::info!("Request to MCP server {server_id} failed: {error:?}");
    if error.is_timeout() {
        ConnectError::failed("The server did not respond in time")
    } else if error.is_connect() {
        ConnectError::failed("Could not connect to the server")
    } else {
        ConnectError::failed("The request to the server failed")
    }
}

/// For the errors of creating and changing servers.
pub(crate) fn connect_app_error(error: ConnectError) -> AppError {
    match error {
        ConnectError::AuthorizationRequired { .. } => AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The server rejected the token".to_string(),
        ),
        ConnectError::Failed(message) => {
            AppError::BadGateway(ErrorCode::RemoteUnreachable, message)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn normalized(schema: Value) -> Option<Value> {
        object_schema(schema.as_object().unwrap().clone()).map(Value::Object)
    }

    #[test]
    fn keeps_object_schemas() {
        let schema = json!({
            "type": "object",
            "properties": {"q": {"type": "string"}},
            "required": ["q"],
        });
        assert_eq!(normalized(schema.clone()), Some(schema));
        assert_eq!(normalized(json!({})), Some(json!({"type": "object"})));
        assert_eq!(
            normalized(json!({"type": ["object", "null"]})),
            Some(json!({"type": "object"}))
        );
    }

    #[test]
    fn leaves_out_other_types() {
        assert_eq!(normalized(json!({"type": "string"})), None);
        assert_eq!(normalized(json!({"type": ["array", "null"]})), None);
    }

    #[test]
    fn merges_alternatives() {
        let schema = json!({
            "type": "object",
            "properties": {"dry_run": {"type": "boolean"}},
            "anyOf": [
                {
                    "type": "object",
                    "properties": {"kind": {"const": "id"}, "id": {"type": "integer"}},
                    "required": ["kind", "id"],
                    "additionalProperties": false,
                },
                {
                    "type": "object",
                    "properties": {"kind": {"const": "url"}, "url": {"type": "string"}},
                    "required": ["kind", "url"],
                },
            ],
        });
        assert_eq!(
            normalized(schema),
            Some(json!({
                "type": "object",
                "properties": {
                    "dry_run": {"type": "boolean"},
                    "kind": {"anyOf": [{"const": "id"}, {"const": "url"}]},
                    "id": {"type": "integer"},
                    "url": {"type": "string"},
                },
                "required": ["kind"],
            }))
        );
    }

    #[test]
    fn requires_nothing_of_alternatives_by_reference() {
        let schema = json!({
            "oneOf": [
                {"properties": {"id": {"type": "integer"}}, "required": ["id"]},
                {"$ref": "#/$defs/ByUrl"},
            ],
            "$defs": {"ByUrl": {"type": "object"}},
        });
        assert_eq!(
            normalized(schema),
            Some(json!({
                "type": "object",
                "properties": {"id": {"type": "integer"}},
                "$defs": {"ByUrl": {"type": "object"}},
            }))
        );
    }

    #[test]
    fn merges_all_parts() {
        let schema = json!({
            "type": "object",
            "required": ["a"],
            "allOf": [
                {"properties": {"a": {"type": "string"}, "b": {"minimum": 0}}, "required": ["a"]},
                {"properties": {"b": {"maximum": 9}}, "required": ["b"]},
            ],
        });
        assert_eq!(
            normalized(schema),
            Some(json!({
                "type": "object",
                "properties": {
                    "a": {"type": "string"},
                    "b": {"allOf": [{"minimum": 0}, {"maximum": 9}]},
                },
                "required": ["a", "b"],
            }))
        );
    }
}
