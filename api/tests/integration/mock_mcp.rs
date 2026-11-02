use axum::extract::{Request, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Form, Json, Router};
use base64::Engine;
use rmcp::ErrorData;
use rmcp::handler::server::ServerHandler;
use rmcp::model::{
    CallToolRequestParams, CallToolResponse, CallToolResult, ContentBlock, ListToolsResult,
    PaginatedRequestParams, ServerCapabilities, ServerConfig, Tool,
};
use rmcp::service::{RequestContext, RoleServer};
use rmcp::transport::streamable_http_server::session::local::LocalSessionManager;
use rmcp::transport::streamable_http_server::{StreamableHttpServerConfig, StreamableHttpService};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use url::Url;

/// The token [`McpAuth::Token`] accepts.
pub const TOKEN: &str = "mcp-secret-token";

pub enum McpAuth {
    None,
    /// Requires [`TOKEN`].
    Token,
    /// Requires [`TOKEN`] without saying so: answers 401 without a token and 403 with another
    /// one, without a `WWW-Authenticate` header.
    TokenWithoutChallenge,
    /// Requires an access token from the authorization server at the same address, which
    /// issues them for one second, so each use refreshes them.
    OAuth,
}

/// An MCP server on localhost (rmcp's own) with the tool `echo`, which answers
/// `echo: <text>`. With [`McpAuth::OAuth`], it is its own authorization server, with dynamic
/// client registration, PKCE and refresh tokens; [`MockMcp::approve`] stands in for the user
/// signing in. Stops when dropped.
pub struct MockMcp {
    /// The MCP endpoint.
    pub url: String,
    state: Arc<MockState>,
    server: JoinHandle<()>,
}

struct MockState {
    auth: McpAuth,
    base_url: String,
    /// The arguments of the calls of `echo`.
    calls: Arc<Mutex<Vec<Value>>>,
    oauth: Mutex<OAuthState>,
}

#[derive(Default)]
struct OAuthState {
    registrations: Vec<Value>,
    /// Issued codes, with the PKCE challenge and the client.
    codes: HashMap<String, (String, String)>,
    access_tokens: HashSet<String>,
    refresh_tokens: HashSet<String>,
    issued: usize,
    refreshes: usize,
}

impl MockMcp {
    pub async fn start(auth: McpAuth) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        let calls = Arc::new(Mutex::new(Vec::new()));
        let state = Arc::new(MockState {
            auth,
            base_url: base_url.clone(),
            calls: calls.clone(),
            oauth: Mutex::new(OAuthState::default()),
        });

        let mcp = StreamableHttpService::new(
            move || {
                Ok(EchoServer {
                    calls: calls.clone(),
                })
            },
            Arc::new(LocalSessionManager::default()),
            StreamableHttpServerConfig::default(),
        );
        let mut router =
            Router::new()
                .nest_service("/mcp", mcp)
                .layer(axum::middleware::from_fn_with_state(
                    state.clone(),
                    authenticate,
                ));
        if matches!(state.auth, McpAuth::OAuth) {
            router = router
                .route(
                    "/.well-known/oauth-protected-resource/mcp",
                    get(resource_metadata),
                )
                .route(
                    "/.well-known/oauth-authorization-server",
                    get(authorization_server_metadata),
                )
                .route("/register", post(register))
                .route("/token", post(token));
        }
        let router = router.with_state(state.clone());
        let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        Self {
            url: format!("{base_url}/mcp"),
            state,
            server,
        }
    }

    /// The arguments of the calls of `echo` so far.
    pub fn calls(&self) -> Vec<Value> {
        self.state.calls.lock().unwrap().clone()
    }

    /// The bodies of the client registrations so far.
    pub fn registrations(&self) -> Vec<Value> {
        self.state.oauth.lock().unwrap().registrations.clone()
    }

    /// The access tokens refreshed so far.
    pub fn refreshes(&self) -> usize {
        self.state.oauth.lock().unwrap().refreshes
    }

    /// Revokes all tokens, as if the user revoked the access.
    pub fn revoke(&self) {
        let mut oauth = self.state.oauth.lock().unwrap();
        oauth.access_tokens.clear();
        oauth.refresh_tokens.clear();
    }

    /// Signs in at `authorization_url` as the user would, and returns the code the
    /// authorization server sends them back with.
    pub fn approve(&self, authorization_url: &str) -> String {
        let url = Url::parse(authorization_url).unwrap();
        let param = |name: &str| {
            url.query_pairs()
                .find(|(key, _)| key == name)
                .unwrap_or_else(|| panic!("no {name} in {authorization_url}"))
                .1
                .into_owned()
        };
        assert_eq!(param("response_type"), "code");
        assert_eq!(param("code_challenge_method"), "S256");
        let mut oauth = self.state.oauth.lock().unwrap();
        oauth.issued += 1;
        let code = format!("code-{}", oauth.issued);
        oauth
            .codes
            .insert(code.clone(), (param("code_challenge"), param("client_id")));
        code
    }
}

impl Drop for MockMcp {
    fn drop(&mut self) {
        self.server.abort();
    }
}

#[derive(Clone)]
struct EchoServer {
    calls: Arc<Mutex<Vec<Value>>>,
}

impl ServerHandler for EchoServer {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
    }

    async fn list_tools(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        let schema = json!({
            "type": "object",
            "properties": {"text": {"type": "string"}},
            "required": ["text"],
        });
        Ok(ListToolsResult::with_all_items(vec![Tool::new(
            "echo",
            "Echoes the text.",
            Arc::new(schema.as_object().unwrap().clone()),
        )]))
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, ErrorData> {
        let arguments = Value::Object(request.arguments.unwrap_or_default());
        self.calls.lock().unwrap().push(arguments.clone());
        let Some(text) = arguments["text"].as_str() else {
            return Ok(CallToolResult::error(vec![ContentBlock::text("text is missing")]).into());
        };
        Ok(CallToolResult::success(vec![ContentBlock::text(format!("echo: {text}"))]).into())
    }
}

/// Protects only the MCP endpoint, the metadata and token endpoints are public.
async fn authenticate(
    State(state): State<Arc<MockState>>,
    request: Request,
    next: Next,
) -> Response {
    if !request.uri().path().starts_with("/mcp") {
        return next.run(request).await;
    }
    let bearer = bearer(request.headers());
    if let McpAuth::TokenWithoutChallenge = state.auth {
        return match bearer.as_deref() {
            Some(TOKEN) => next.run(request).await,
            Some(_) => StatusCode::FORBIDDEN.into_response(),
            None => StatusCode::UNAUTHORIZED.into_response(),
        };
    }
    let (allowed, challenge) = match &state.auth {
        McpAuth::None => (true, String::new()),
        McpAuth::Token | McpAuth::TokenWithoutChallenge => {
            (bearer.as_deref() == Some(TOKEN), "Bearer".to_string())
        }
        McpAuth::OAuth => (
            bearer.is_some_and(|token| state.oauth.lock().unwrap().access_tokens.contains(&token)),
            format!(
                "Bearer resource_metadata=\"{}/.well-known/oauth-protected-resource/mcp\"",
                state.base_url
            ),
        ),
    };
    if allowed {
        next.run(request).await
    } else {
        (
            StatusCode::UNAUTHORIZED,
            [(header::WWW_AUTHENTICATE, challenge)],
        )
            .into_response()
    }
}

fn bearer(headers: &HeaderMap) -> Option<String> {
    headers
        .get(header::AUTHORIZATION)?
        .to_str()
        .ok()?
        .strip_prefix("Bearer ")
        .map(str::to_string)
}

async fn resource_metadata(State(state): State<Arc<MockState>>) -> Json<Value> {
    Json(json!({
        "resource": format!("{}/mcp", state.base_url),
        "authorization_servers": [state.base_url],
    }))
}

async fn authorization_server_metadata(State(state): State<Arc<MockState>>) -> Json<Value> {
    let base = &state.base_url;
    Json(json!({
        "issuer": base,
        "authorization_endpoint": format!("{base}/authorize"),
        "token_endpoint": format!("{base}/token"),
        "registration_endpoint": format!("{base}/register"),
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": ["none"],
    }))
}

async fn register(
    State(state): State<Arc<MockState>>,
    Json(body): Json<Value>,
) -> (StatusCode, Json<Value>) {
    let mut oauth = state.oauth.lock().unwrap();
    oauth.registrations.push(body.clone());
    let client_id = format!("client-{}", oauth.registrations.len());
    (
        StatusCode::CREATED,
        Json(json!({"client_id": client_id, "redirect_uris": body["redirect_uris"]})),
    )
}

async fn token(
    State(state): State<Arc<MockState>>,
    Form(form): Form<HashMap<String, String>>,
) -> Response {
    let mut oauth = state.oauth.lock().unwrap();
    let client_id = form.get("client_id").cloned().unwrap_or_default();
    match form.get("grant_type").map(String::as_str) {
        Some("authorization_code") => {
            let code = form.get("code").cloned().unwrap_or_default();
            let Some((challenge, issued_to)) = oauth.codes.remove(&code) else {
                return invalid_grant();
            };
            let verifier = form.get("code_verifier").cloned().unwrap_or_default();
            let hashed = base64::engine::general_purpose::URL_SAFE_NO_PAD
                .encode(Sha256::digest(verifier.as_bytes()));
            if hashed != challenge || issued_to != client_id {
                return invalid_grant();
            }
        }
        Some("refresh_token") => {
            let refresh_token = form.get("refresh_token").cloned().unwrap_or_default();
            if !oauth.refresh_tokens.remove(&refresh_token) {
                return invalid_grant();
            }
            oauth.refreshes += 1;
        }
        _ => return invalid_grant(),
    }
    oauth.issued += 1;
    let access_token = format!("access-{}", oauth.issued);
    let refresh_token = format!("refresh-{}", oauth.issued);
    oauth.access_tokens.insert(access_token.clone());
    oauth.refresh_tokens.insert(refresh_token.clone());
    Json(json!({
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_in": 1,
        "refresh_token": refresh_token,
    }))
    .into_response()
}

fn invalid_grant() -> Response {
    (
        StatusCode::BAD_REQUEST,
        Json(json!({"error": "invalid_grant"})),
    )
        .into_response()
}
