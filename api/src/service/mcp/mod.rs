//! The MCP client: connects to the MCP servers users added (Streamable HTTP only), lists their
//! tools and calls them for [`crate::service::tools`].
//!
//! Like remotes, servers of users other than admins are only reached over https at public
//! addresses ([`RemoteAccess`]), and so are the authorization servers they sign in with
//! ([`oauth`]). That depends on the owner, also in the chats of the users a server is shared
//! with, who use it with the owner's credentials. Each answer connects once to each server it
//! calls a tool of.

mod error;
mod oauth;
mod schema;
mod url;

pub(crate) use error::{ConnectError, connect_app_error, maybe_processed, service_error};
pub(crate) use url::{hide_url, url_origin};

use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::mcp::McpServerStatus;
use crate::model::mcp_server::{McpServer, McpTool, UsableMcpServer};
use crate::model::remote_access::RemoteAccess;
use crate::repository;
use crate::repository::mcp::Connection;
use crate::util::http::{check_public_url, redirect_policy, remote_client_builder};
use crate::util::token_cipher::TokenCipher;
use ::url::Url;
use chrono::{DateTime, Utc};
use error::initialize_error;
use oauth::{OAuthHttp, PendingSignIns, RefreshLocks};
use rmcp::ServiceExt;
use rmcp::model::{ClientCapabilities, ClientConfig, Implementation};
use rmcp::service::{RoleClient, RunningService};
use rmcp::transport::StreamableHttpClientTransport;
use rmcp::transport::auth::AuthClient;
use rmcp::transport::streamable_http_client::{
    StreamableHttpClient, StreamableHttpClientTransportConfig,
};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use uuid::Uuid;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// For connecting (the initialize handshake) and for listing the tools.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(30);
/// For closing a session, which tells the server to drop it.
const CLOSE_TIMEOUT: Duration = Duration::from_secs(5);
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
                Credentials::None => serve(http, config, target.id).await,
                Credentials::Token(token) => {
                    serve(http, config.auth_header(token.clone()), target.id).await
                }
                Credentials::OAuth => {
                    serve(self.auth_client(target).await?, config, target.id).await
                }
            }
        };
        tokio::time::timeout(HANDSHAKE_TIMEOUT, handshake)
            .await
            .unwrap_or_else(|_| Err(ConnectError::timed_out()))
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
        Ok(schema::stored_tools(tools, target.id))
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

/// Opens a session over `client`: connects and initializes.
async fn serve<C: StreamableHttpClient>(
    client: C,
    config: StreamableHttpClientTransportConfig,
    server_id: Uuid,
) -> Result<McpSession, ConnectError> {
    client_config()
        .serve(StreamableHttpClientTransport::with_client(client, config))
        .await
        .map_err(|e| initialize_error(&e, server_id))
}

/// See [`check_public_url`].
fn check_url(url: &str, access: RemoteAccess) -> Result<(), ConnectError> {
    let url = Url::parse(url).map_err(|_| ConnectError::failed("The URL is not valid"))?;
    check_public_url(&url, access).map_err(|_| ConnectError::not_public())
}
