use axum::body::Body;
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
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{Notify, Semaphore};
use tokio::task::JoinHandle;
use url::Url;

/// The token [`McpAuth::Token`] accepts.
pub const TOKEN: &str = "mcp-secret-token";
/// Calls of `echo` with this text are refused with 403, without a `WWW-Authenticate` header.
pub const FORBIDDEN: &str = "forbidden";
/// Calls of `echo` with this text are refused with 403 for an `insufficient_scope`.
pub const INSUFFICIENT_SCOPE: &str = "insufficient scope";
/// Calls of `echo` with this text run, but the connection is lost before their result arrives.
pub const LOSE_RESULT: &str = "lose result";
/// Calls of `echo` with this text run, but answer only after [`MockMcp::release`].
pub const HOLD: &str = "hold";
/// The delay of [`MockMcp::slow_down`].
const SLOW_DOWN: Duration = Duration::from_millis(200);

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
    /// Like [`McpAuth::OAuth`], but registers confidential clients, with a secret its token
    /// endpoint requires, although Repolupe asks for a public client.
    ConfidentialOAuth,
    /// Like [`McpAuth::OAuth`], but also accepts [`TOKEN`] until [`MockMcp::reject_token`].
    TokenOrOAuth,
}

/// An MCP server on localhost (rmcp's own) with the tool `echo`, which answers
/// `echo: <text>`, except for [`FORBIDDEN`], [`INSUFFICIENT_SCOPE`], [`LOSE_RESULT`] and
/// [`HOLD`]. With [`McpAuth::OAuth`], it is its own authorization server, with dynamic client registration,
/// PKCE and refresh tokens; [`MockMcp::approve`] stands in for the user signing in. Stops when
/// dropped.
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
    /// See [`MockMcp::slow_down`].
    slow: AtomicBool,
    /// See [`MockMcp::reject_token`].
    token_rejected: AtomicBool,
    hold: Arc<Hold>,
}

/// The calls of `echo` with [`HOLD`].
struct Hold {
    held: Notify,
    released: Semaphore,
}

#[derive(Default)]
struct OAuthState {
    registrations: Vec<Value>,
    /// The IDs of the registered clients, until [`MockMcp::forget_clients`].
    clients: HashSet<String>,
    /// The secrets of the registered clients, with [`McpAuth::ConfidentialOAuth`].
    client_secrets: HashMap<String, String>,
    /// Issued codes, with the PKCE challenge and the client.
    codes: HashMap<String, (String, String)>,
    access_tokens: HashSet<String>,
    refresh_tokens: HashSet<String>,
    issued: usize,
    refreshes: usize,
    /// Refreshes with a refresh token that was already used or revoked.
    rejected_refreshes: usize,
}

impl MockMcp {
    pub async fn start(auth: McpAuth) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        let calls = Arc::new(Mutex::new(Vec::new()));
        let hold = Arc::new(Hold {
            held: Notify::new(),
            released: Semaphore::new(0),
        });
        let state = Arc::new(MockState {
            auth,
            base_url: base_url.clone(),
            calls: calls.clone(),
            oauth: Mutex::new(OAuthState::default()),
            slow: AtomicBool::new(false),
            token_rejected: AtomicBool::new(false),
            hold: hold.clone(),
        });

        let mcp = StreamableHttpService::new(
            move || {
                Ok(EchoServer {
                    calls: calls.clone(),
                    hold: hold.clone(),
                })
            },
            Arc::new(LocalSessionManager::default()),
            StreamableHttpServerConfig::default(),
        );
        let mut router = Router::new()
            .nest_service("/mcp", mcp)
            .layer(axum::middleware::from_fn(lose_results))
            .layer(axum::middleware::from_fn(refuse_calls))
            .layer(axum::middleware::from_fn_with_state(
                state.clone(),
                authenticate,
            ));
        if matches!(
            state.auth,
            McpAuth::OAuth | McpAuth::ConfidentialOAuth | McpAuth::TokenOrOAuth
        ) {
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

    /// The refreshes rejected because their refresh token was already used or revoked.
    pub fn rejected_refreshes(&self) -> usize {
        self.state.oauth.lock().unwrap().rejected_refreshes
    }

    /// Answers the metadata and token requests of the authorization server only after
    /// [`SLOW_DOWN`] from now on, so connections that start together overlap.
    pub fn slow_down(&self) {
        self.state.slow.store(true, Ordering::Relaxed);
    }

    /// Stops accepting [`TOKEN`] with [`McpAuth::TokenOrOAuth`], as if the user revoked it.
    pub fn reject_token(&self) {
        self.state.token_rejected.store(true, Ordering::Relaxed);
    }

    /// Waits until a call of `echo` with [`HOLD`] has run.
    pub async fn wait_for_held(&self) {
        tokio::time::timeout(Duration::from_secs(10), self.state.hold.held.notified())
            .await
            .expect("no call was held");
    }

    /// Lets a held call of `echo` answer.
    pub fn release(&self) {
        self.state.hold.released.add_permits(1);
    }

    /// Revokes all tokens, as if the user revoked the access.
    pub fn revoke(&self) {
        let mut oauth = self.state.oauth.lock().unwrap();
        oauth.access_tokens.clear();
        oauth.refresh_tokens.clear();
    }

    /// Forgets the registered clients, as an authorization server that deletes unused ones
    /// would: their token requests are rejected with `invalid_client`.
    pub fn forget_clients(&self) {
        self.state.oauth.lock().unwrap().clients.clear();
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
    hold: Arc<Hold>,
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
        if text == HOLD {
            self.hold.held.notify_one();
            self.hold.released.acquire().await.unwrap().forget();
        }
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
        McpAuth::TokenOrOAuth
            if bearer.as_deref() == Some(TOKEN)
                && !state.token_rejected.load(Ordering::Relaxed) =>
        {
            (true, String::new())
        }
        McpAuth::OAuth | McpAuth::ConfidentialOAuth | McpAuth::TokenOrOAuth => (
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

/// Refuses the calls of `echo` with [`FORBIDDEN`] or [`INSUFFICIENT_SCOPE`], as a firewall or
/// a server checking permissions per call would. After [`authenticate`].
async fn refuse_calls(request: Request, next: Next) -> Response {
    let (parts, body) = request.into_parts();
    let bytes = axum::body::to_bytes(body, usize::MAX).await.unwrap();
    let message: Value = serde_json::from_slice(&bytes).unwrap_or_default();
    if message["method"] == "tools/call" {
        match message["params"]["arguments"]["text"].as_str() {
            Some(FORBIDDEN) => return StatusCode::FORBIDDEN.into_response(),
            Some(INSUFFICIENT_SCOPE) => {
                let challenge = r#"Bearer error="insufficient_scope", scope="echo:write""#;
                return (
                    StatusCode::FORBIDDEN,
                    [(header::WWW_AUTHENTICATE, challenge)],
                )
                    .into_response();
            }
            _ => {}
        }
    }
    next.run(Request::from_parts(parts, Body::from(bytes)))
        .await
}

/// Loses the connection of calls of `echo` with [`LOSE_RESULT`] once they have run. After
/// [`refuse_calls`].
async fn lose_results(request: Request, next: Next) -> Response {
    let (parts, body) = request.into_parts();
    let bytes = axum::body::to_bytes(body, usize::MAX).await.unwrap();
    let message: Value = serde_json::from_slice(&bytes).unwrap_or_default();
    let lose =
        message["method"] == "tools/call" && message["params"]["arguments"]["text"] == LOSE_RESULT;
    let response = next
        .run(Request::from_parts(parts, Body::from(bytes)))
        .await;
    if !lose {
        return response;
    }
    // The response stream ends with the result, so the call has run.
    axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    ([(header::CONTENT_TYPE, "text/event-stream")], "").into_response()
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
    slow_down(&state).await;
    let base = &state.base_url;
    Json(json!({
        "issuer": base,
        "authorization_endpoint": format!("{base}/authorize"),
        "token_endpoint": format!("{base}/token"),
        "registration_endpoint": format!("{base}/register"),
        "response_types_supported": ["code"],
        "grant_types_supported": ["authorization_code", "refresh_token"],
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": match state.auth {
            McpAuth::ConfidentialOAuth => ["client_secret_basic"],
            _ => ["none"],
        },
    }))
}

async fn register(
    State(state): State<Arc<MockState>>,
    Json(body): Json<Value>,
) -> (StatusCode, Json<Value>) {
    let mut oauth = state.oauth.lock().unwrap();
    oauth.registrations.push(body.clone());
    let client_id = format!("client-{}", oauth.registrations.len());
    oauth.clients.insert(client_id.clone());
    let mut registered = json!({"client_id": client_id, "redirect_uris": body["redirect_uris"]});
    if let McpAuth::ConfidentialOAuth = state.auth {
        let secret = format!("secret-{}", oauth.registrations.len());
        registered["client_secret"] = json!(secret);
        oauth.client_secrets.insert(client_id, secret);
    }
    (StatusCode::CREATED, Json(registered))
}

async fn token(
    State(state): State<Arc<MockState>>,
    headers: HeaderMap,
    Form(form): Form<HashMap<String, String>>,
) -> Response {
    slow_down(&state).await;
    let mut oauth = state.oauth.lock().unwrap();
    let (client_id, secret) = client_credentials(&headers, &form);
    if !oauth.clients.contains(&client_id) {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "invalid_client"})),
        )
            .into_response();
    }
    if let McpAuth::ConfidentialOAuth = state.auth
        && (secret.is_none() || oauth.client_secrets.get(&client_id) != secret.as_ref())
    {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({"error": "invalid_client"})),
        )
            .into_response();
    }
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
            // Rotated: each refresh token is used once.
            if !oauth.refresh_tokens.remove(&refresh_token) {
                oauth.rejected_refreshes += 1;
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

/// The client ID and secret of a token request, from HTTP Basic authentication or the form.
/// The IDs and secrets the mock issues need no URL decoding.
fn client_credentials(
    headers: &HeaderMap,
    form: &HashMap<String, String>,
) -> (String, Option<String>) {
    let basic = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok()?.strip_prefix("Basic "))
        .and_then(|encoded| {
            base64::engine::general_purpose::STANDARD
                .decode(encoded)
                .ok()
        })
        .and_then(|decoded| String::from_utf8(decoded).ok());
    if let Some((id, secret)) = basic.as_deref().and_then(|basic| basic.split_once(':')) {
        return (id.to_string(), Some(secret.to_string()));
    }
    let client_id = form.get("client_id").cloned().unwrap_or_default();
    (client_id, form.get("client_secret").cloned())
}

async fn slow_down(state: &MockState) {
    if state.slow.load(Ordering::Relaxed) {
        tokio::time::sleep(SLOW_DOWN).await;
    }
}

fn invalid_grant() -> Response {
    (
        StatusCode::BAD_REQUEST,
        Json(json!({"error": "invalid_grant"})),
    )
        .into_response()
}
