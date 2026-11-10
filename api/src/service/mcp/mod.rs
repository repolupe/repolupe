//! The MCP client: connects to the MCP servers users added (Streamable HTTP only), lists their
//! tools and calls them for [`crate::service::tools`].
//!
//! Like remotes, servers of users other than admins are only reached over https at public
//! addresses ([`RemoteAccess`]), and so are the authorization servers they sign in with
//! ([`oauth`]). That depends on the owner, also in the chats of the users a server is shared
//! with, who use it with the owner's credentials. Each answer connects once to each server it
//! calls a tool of.

mod oauth;

use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::dto::mcp::McpServerStatus;
use crate::model::mcp_server::{McpServer, McpTool, UsableMcpServer};
use crate::model::remote_access::RemoteAccess;
use crate::repository;
use crate::repository::mcp::Connection;
use crate::service::tools::{MAX_DEFINITION_BYTES, definition_bytes};
use crate::util::http::{check_public_url, redirect_policy, remote_client_builder};
use crate::util::ip::is_not_public;
use crate::util::token_cipher::TokenCipher;
use chrono::{DateTime, Utc};
use oauth::{OAuthHttp, PendingSignIns, RefreshLocks};
use reqwest::StatusCode;
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
/// Tools of a server beyond this are left out, so they don't crowd the prompt.
const MAX_TOOLS: usize = 100;
/// Longer descriptions of tools are cut.
const MAX_DESCRIPTION_CHARS: usize = 2_000;
/// Tools with larger argument schemas are left out.
const MAX_SCHEMA_BYTES: usize = 64 * 1024;
/// Tools of a server beyond this many bytes of definitions together are left out, so each
/// answer parses at most this much of each server. Four times what an answer gets of all
/// servers together, so turning off tools still leaves others to fill that, and far below
/// [`MAX_TOOLS`] times [`MAX_SCHEMA_BYTES`].
const MAX_SERVER_DEFINITION_BYTES: usize = 4 * MAX_DEFINITION_BYTES;
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

fn builder(access: RemoteAccess) -> reqwest::ClientBuilder {
    remote_client_builder(access)
        .connect_timeout(CONNECT_TIMEOUT)
        .user_agent(USER_AGENT)
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
    /// Shared by all OAuth clients of a server, also the ones no longer cached.
    refresh_locks: RefreshLocks,
}

struct CachedAuth {
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
    /// With `access` from the role of the server's owner.
    pub(crate) fn new(
        server: &McpServer,
        access: RemoteAccess,
        cipher: &TokenCipher,
    ) -> Result<Self, AppError> {
        Self::build(
            server.id,
            &server.url,
            server.token_encrypted.as_deref(),
            server.oauth_encrypted.is_some(),
            access,
            cipher,
        )
    }

    /// For a server whose tools the model gets, also in the chats of users it is shared with.
    pub(crate) fn usable(server: &UsableMcpServer, cipher: &TokenCipher) -> Result<Self, AppError> {
        Self::build(
            server.id,
            &server.url,
            server.token_encrypted.as_deref(),
            server.oauth_encrypted.is_some(),
            RemoteAccess::of(server.owner_role),
            cipher,
        )
    }

    fn build(
        id: Uuid,
        url: &str,
        token_encrypted: Option<&[u8]>,
        oauth: bool,
        access: RemoteAccess,
        cipher: &TokenCipher,
    ) -> Result<Self, AppError> {
        let credentials = match (token_encrypted, oauth) {
            (Some(token), _) => Credentials::Token(cipher.decrypt(id, token).map_err(|e| {
                AppError::InternalServerError(format!(
                    "Failed to decrypt the token of MCP server {id}: {e}"
                ))
            })?),
            (None, true) => Credentials::OAuth,
            (None, false) => Credentials::None,
        };
        Ok(Self {
            id,
            url: url.to_string(),
            access,
            credentials,
        })
    }
}

/// Why connecting to a server failed.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub(crate) enum ConnectError {
    /// The server asks for authentication, or rejected the token or the OAuth credentials
    /// (HTTP 401).
    #[error("The server requires authentication")]
    AuthorizationRequired {
        /// The server's `WWW-Authenticate` header, which may point to its OAuth metadata.
        challenge: Option<String>,
    },
    /// The server refused the request (HTTP 403), such as for a permission or an OAuth scope
    /// the credentials lack, or a firewall in front of it. Unlike
    /// [`Self::AuthorizationRequired`], the credentials may still be valid.
    #[error("The server refused the request")]
    Forbidden {
        /// The server's `WWW-Authenticate` header, if it sent one.
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

    /// Whether the server refused the request for an OAuth scope the credentials lack.
    pub(crate) fn insufficient_scope(&self) -> bool {
        matches!(self, Self::Forbidden { challenge: Some(challenge) }
            if challenge.contains("insufficient_scope"))
    }

    /// How the server is stored after the failure. A server that refused the connection or
    /// the list of tools is stored to sign in to again, like one that rejected the
    /// credentials: they most likely lack a permission.
    pub(crate) fn connection(&self) -> Connection<'_> {
        let (status, last_error) = match self {
            ConnectError::AuthorizationRequired { .. } | ConnectError::Forbidden { .. } => {
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
            refresh_locks: RefreshLocks::default(),
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
        Ok(stored_tools(tools, target.id))
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
            repository::mcp::record_connection(&self.db, server.id, None, connection).await?;
        Ok(updated.unwrap_or(server))
    }

    /// Marks the server as needing a new sign-in, after it rejected the credentials during an
    /// answer. Its tools are offered again once the user signed in. Only if the server still
    /// has the `updated_at` of when the answer read the credentials: if the user signed in
    /// since, the rejected ones are outdated.
    pub(crate) async fn require_authorization(&self, id: Uuid, updated_at: DateTime<Utc>) {
        self.forget(id);
        let connection = ConnectError::AuthorizationRequired { challenge: None };
        if let Err(e) = repository::mcp::record_connection(
            &self.db,
            id,
            Some(updated_at),
            connection.connection(),
        )
        .await
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
        redirect_uri: &Url,
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

/// See [`check_public_url`].
fn check_url(url: &str, access: RemoteAccess) -> Result<(), ConnectError> {
    let url = Url::parse(url).map_err(|_| ConnectError::failed("The URL is not valid"))?;
    check_public_url(&url, access).map_err(|_| not_public())
}

fn not_public() -> ConnectError {
    ConnectError::failed("The server's address is not public")
}

/// What replaces the parts of a server's URL that users it is shared with must not see.
const HIDDEN: &str = "[hidden]";
/// Stands in for the URL's origin while its parts are hidden, which could otherwise match in
/// it (the path `/mcp` in `https://mcp.example.com`). URLs never contain it.
const ORIGIN: &str = "\u{0}";
/// Path segments and query values shorter than this are not hidden on their own: keys are
/// longer, and hiding words like `mcp` everywhere would garble the messages.
const MIN_HIDDEN_PART: usize = 8;

/// The scheme, host and port of a server's URL. Users it is shared with see only this: some
/// servers take a key in the path or the query, which is the owner's.
pub(crate) fn url_origin(url: &str) -> String {
    Url::parse(url)
        .map(|url| url.origin().ascii_serialization())
        .unwrap_or_default()
}

/// `message` without the path and the query of the server's `url` (the URL itself as its
/// origin), for users the server is shared with, see [`url_origin`]. Also the longer path
/// segments and query values on their own, and wherever they appear, e.g. in the URLs of the
/// OAuth discovery, which contain the server's path.
pub(crate) fn hide_url(message: &str, url: &str) -> String {
    let Ok(parsed) = Url::parse(url) else {
        return message.to_string();
    };
    let origin = parsed.origin().ascii_serialization();
    let mut message = message
        .replace(url, ORIGIN)
        .replace(parsed.as_str(), ORIGIN)
        .replace(&origin, ORIGIN);
    let query = parsed.query().filter(|query| !query.is_empty());
    let path = Some(parsed.path()).filter(|path| *path != "/");
    let segments = parsed.path().split('/');
    let values = query
        .into_iter()
        .flat_map(|query| query.split('&'))
        .map(|pair| pair.split_once('=').map_or(pair, |(_, value)| value));
    let parts = query.into_iter().chain(path).chain(
        segments
            .chain(values)
            .filter(|part| part.len() >= MIN_HIDDEN_PART),
    );
    for part in parts {
        message = message.replace(part, HIDDEN);
    }
    message.replace(ORIGIN, &origin)
}

/// The tools as stored: at most [`MAX_TOOLS`], with definitions of at most
/// [`MAX_SERVER_DEFINITION_BYTES`] together. A tool too large for the bytes left is left out,
/// the following ones may still fit.
fn stored_tools(tools: Vec<Tool>, server_id: Uuid) -> Vec<McpTool> {
    let mut bytes = 0;
    tools
        .into_iter()
        .filter_map(|tool| stored_tool(tool, server_id))
        .filter(|tool| {
            let size = tool.definition_bytes;
            if bytes + size > MAX_SERVER_DEFINITION_BYTES {
                tracing::info!(
                    "Leaving out the tool {} of MCP server {server_id}, too many bytes of \
                    definitions altogether",
                    tool.name
                );
                return false;
            }
            bytes += size;
            true
        })
        .take(MAX_TOOLS)
        .collect()
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
    let mut tool = McpTool {
        name: tool.name.into_owned(),
        title,
        description,
        input_schema,
        definition_bytes: 0,
    };
    tool.definition_bytes = definition_bytes(&tool, size);
    Some(tool)
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

/// Whether the request failed with `error` because the connection was lost after it was sent,
/// so the server may have processed it.
pub(crate) fn maybe_processed(error: &ServiceError) -> bool {
    let error = match error {
        // The session ended, or the response stream closed before the response arrived.
        ServiceError::TransportClosed => return true,
        ServiceError::TransportSend(error) => error.error.as_ref(),
        _ => return false,
    };
    let lost = |e: &reqwest::Error| {
        !(e.is_connect() || e.is_status() || e.is_builder() || e.is_redirect())
    };
    let mut source: Option<&(dyn Error + 'static)> = Some(error);
    while let Some(e) = source {
        if let Some(e) = e.downcast_ref::<StreamableHttpError<reqwest::Error>>() {
            return match e {
                // For requests that were under way while rmcp opened a new session, and when
                // its worker is gone, which may have taken the request along.
                StreamableHttpError::SessionRecoveryTimeout
                | StreamableHttpError::TransportChannelClosed => true,
                StreamableHttpError::Client(e) => lost(e),
                _ => false,
            };
        }
        if let Some(e) = e.downcast_ref::<reqwest::Error>() {
            return lost(e);
        }
        source = e.source();
    }
    false
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
        // rmcp reports every 403 with a `WWW-Authenticate` header this way, not only those for
        // an `insufficient_scope`.
        if let Some(e) = e.downcast_ref::<InsufficientScopeError>() {
            return ConnectError::Forbidden {
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
                    return ConnectError::Forbidden {
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
                // rmcp reports a 401 or 403 without a `WWW-Authenticate` header only as
                // `HTTP <status>: <body>`. Guarded by the integration tests
                // `takes_rejections_without_a_challenge_as_such` (401 and 403) and
                // `fails_only_the_calls_the_server_refuses` (403).
                StreamableHttpError::UnexpectedServerResponse(message)
                    if message.starts_with("HTTP 401 ") =>
                {
                    return ConnectError::AuthorizationRequired { challenge: None };
                }
                StreamableHttpError::UnexpectedServerResponse(message)
                    if message.starts_with("HTTP 403 ") =>
                {
                    return ConnectError::Forbidden { challenge: None };
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
        // oauth2's message for an `invalid_client` response: the authorization server no
        // longer accepts the client, a new sign-in registers another one. Guarded by the
        // integration test `requires_a_sign_in_when_the_client_is_rejected`.
        AuthError::TokenRefreshFailed(message)
            if message.starts_with("Server returned error response: invalid_client") =>
        {
            ConnectError::AuthorizationRequired { challenge: None }
        }
        _ => {
            tracing::info!("Authorizing with MCP server {server_id} failed: {error}");
            ConnectError::Failed(format!("Authorizing failed: {error}"))
        }
    }
}

fn request_error(error: &reqwest::Error, server_id: Uuid) -> ConnectError {
    if is_not_public(error) {
        return not_public();
    }
    // From responses rmcp checked with `error_for_status`.
    if let Some(status) = error.status() {
        return match status {
            StatusCode::UNAUTHORIZED => ConnectError::AuthorizationRequired { challenge: None },
            StatusCode::FORBIDDEN => ConnectError::Forbidden { challenge: None },
            _ => ConnectError::Failed(format!(
                "The server responded with HTTP {}",
                status.as_u16()
            )),
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
        // Most likely, the token lacks a permission.
        ConnectError::Forbidden { .. } => AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The server refused access with the token".to_string(),
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
    fn tells_rejected_credentials_from_refused_requests() {
        let error = |e: StreamableHttpError<reqwest::Error>| transport_error(&e, Uuid::now_v7());
        let unexpected = |message: &'static str| {
            error(StreamableHttpError::UnexpectedServerResponse(
                message.into(),
            ))
        };
        assert_eq!(
            unexpected("HTTP 401 Unauthorized: "),
            ConnectError::AuthorizationRequired { challenge: None }
        );
        assert_eq!(
            error(StreamableHttpError::AuthRequired(AuthRequiredError::new(
                "Bearer".to_string()
            ))),
            ConnectError::AuthorizationRequired {
                challenge: Some("Bearer".to_string())
            }
        );
        let forbidden = unexpected("HTTP 403 Forbidden: blocked");
        assert_eq!(forbidden, ConnectError::Forbidden { challenge: None });
        assert!(!forbidden.insufficient_scope());

        let challenge = r#"Bearer error="insufficient_scope", scope="write""#;
        let refused = error(StreamableHttpError::InsufficientScope(
            InsufficientScopeError::new(challenge.to_string(), Some("write".to_string())),
        ));
        assert_eq!(
            refused,
            ConnectError::Forbidden {
                challenge: Some(challenge.to_string())
            }
        );
        assert!(refused.insufficient_scope());
    }

    #[test]
    fn caps_the_definitions_of_a_server() {
        let tool = |name: String, padding: usize| {
            let schema = json!({"type": "object", "description": "x".repeat(padding)});
            Tool::new(
                name,
                "Does things.",
                Arc::new(schema.as_object().unwrap().clone()),
            )
        };
        // Of some 60 KiB each, of which 8 fit.
        let mut tools: Vec<Tool> = (0..9)
            .map(|n| tool(format!("large{n}"), 60 * 1024))
            .collect();
        tools.push(tool("small".to_string(), 0));
        let stored = stored_tools(tools, Uuid::now_v7());
        let names: Vec<&str> = stored.iter().map(|t| t.name.as_str()).collect();
        let mut expected: Vec<String> = (0..8).map(|n| format!("large{n}")).collect();
        expected.push("small".to_string());
        assert_eq!(names, expected);
        let total: usize = stored.iter().map(|t| t.definition_bytes).sum();
        assert!(total <= MAX_SERVER_DEFINITION_BYTES);
        // As the answers would measure it.
        let schema = serde_json::to_vec(&stored[0].input_schema).unwrap().len();
        assert_eq!(
            stored[0].definition_bytes,
            definition_bytes(&stored[0], schema)
        );
        assert!(schema > 60 * 1024);
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

    #[test]
    fn hides_a_key_in_the_path() {
        let url = "https://mcp.example.com/s/k3y-in-the-path/mcp";
        assert_eq!(url_origin(url), "https://mcp.example.com");
        assert_eq!(
            hide_url(&format!("error sending request for url ({url})"), url),
            "error sending request for url (https://mcp.example.com)"
        );
        assert_eq!(
            hide_url("Unknown key k3y-in-the-path", url),
            "Unknown key [hidden]"
        );
        assert_eq!(
            hide_url("HTTP 404 for /s/x/mcp", url),
            "HTTP 404 for /s/x/mcp"
        );
    }

    #[test]
    fn hides_a_key_in_the_query() {
        let url = "https://mcp.example.com:8443/mcp?api_key=sk-live-123456&v=2";
        assert_eq!(url_origin(url), "https://mcp.example.com:8443");
        assert_eq!(
            hide_url(&format!("failed: {url}"), url),
            "failed: https://mcp.example.com:8443"
        );
        assert_eq!(
            hide_url("Invalid query api_key=sk-live-123456&v=2", url),
            "Invalid query [hidden]"
        );
        assert_eq!(
            hide_url("Invalid key sk-live-123456", url),
            "Invalid key [hidden]"
        );
        // Short values on their own stay.
        assert_eq!(hide_url("Version 2 failed", url), "Version 2 failed");
    }

    #[test]
    fn hides_the_path_in_discovery_urls() {
        let url = "https://mcp.example.com/s/k3y-in-the-path/mcp";
        assert_eq!(
            hide_url(
                "Metadata error: https://mcp.example.com/.well-known/oauth-protected-resource/s/\
                k3y-in-the-path/mcp returned 404",
                url
            ),
            "Metadata error: https://mcp.example.com/.well-known/oauth-protected-resource[hidden] \
            returned 404"
        );
        // The path also matches in the host, which stays.
        assert_eq!(
            hide_url(
                "https://mcp.example.com/.well-known/oauth-protected-resource/mcp",
                "https://mcp.example.com/mcp"
            ),
            "https://mcp.example.com/.well-known/oauth-protected-resource[hidden]"
        );
    }

    #[test]
    fn keeps_messages_of_urls_without_path_and_query() {
        let url = "https://mcp.example.com/";
        assert_eq!(url_origin(url), "https://mcp.example.com");
        assert_eq!(hide_url("HTTP 500 at /", url), "HTTP 500 at /");
        assert_eq!(
            hide_url("failed: https://mcp.example.com/", url),
            "failed: https://mcp.example.com"
        );
    }
}
