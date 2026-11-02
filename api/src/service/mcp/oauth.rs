//! Signing in to MCP servers with OAuth, with rmcp's [`AuthorizationManager`]: it discovers
//! the authorization server from the MCP server, registers Repolupe as a client there
//! (dynamic client registration) and exchanges the code for tokens with PKCE.
//!
//! The tokens are stored encrypted with the server ([`DbCredentialStore`]). A sign-in in
//! progress is kept in memory, so it is lost when the server restarts.

use super::{ConnectError, Credentials, McpClient, McpTarget, builder, check_url};
use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::model::mcp_server::McpServer;
use crate::model::remote_access::RemoteAccess;
use crate::repository;
use crate::util::ip::{NotPublic, has_public_host};
use crate::util::token_cipher::TokenCipher;
use futures_util::StreamExt;
use reqwest::redirect::Policy;
use rmcp::transport::auth::{
    AuthError, AuthorizationManager, AuthorizationMetadataSource, AuthorizationRequest,
    AuthorizationSession, CredentialStore, OAuthHttpClient, OAuthHttpClientError,
    OAuthHttpClientFuture, OAuthHttpRedirectPolicy, OAuthHttpRequest, StoredCredentials,
};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use url::Url;
use uuid::Uuid;

/// The client name Repolupe registers with, which authorization servers show when asking the
/// user for consent.
const CLIENT_NAME: &str = "Repolupe";
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;
/// How long a user has to sign in.
const SIGN_IN_TIMEOUT: Duration = Duration::from_mins(10);
/// Sign-ins a user can have in progress, the oldest is dropped beyond.
const MAX_SIGN_INS_PER_USER: usize = 5;

/// Sends rmcp's OAuth requests (metadata discovery, client registration, token requests) with
/// the policy of [`RemoteAccess`].
pub(super) struct OAuthHttp {
    follow: reqwest::Client,
    stop: reqwest::Client,
    access: RemoteAccess,
}

impl OAuthHttp {
    pub(super) fn new(access: RemoteAccess) -> Result<Self, reqwest::Error> {
        let builder = || builder(access).timeout(REQUEST_TIMEOUT);
        Ok(Self {
            follow: builder().redirect(super::redirect_policy(access)).build()?,
            stop: builder().redirect(Policy::none()).build()?,
            access,
        })
    }
}

impl OAuthHttpClient for OAuthHttp {
    fn execute(&self, request: OAuthHttpRequest) -> OAuthHttpClientFuture<'_> {
        Box::pin(async move {
            let client = match request.redirect_policy {
                OAuthHttpRedirectPolicy::Follow => &self.follow,
                _ => &self.stop,
            };
            let request = reqwest::Request::try_from(request.request).map_err(boxed)?;
            if self.access == RemoteAccess::Public && !has_public_host(request.url()) {
                return Err(boxed(NotPublic));
            }
            let response = client.execute(request).await.map_err(boxed)?;

            let mut builder = axum::http::Response::builder()
                .status(response.status())
                .version(response.version());
            for (name, value) in response.headers() {
                builder = builder.header(name, value);
            }
            let mut body = Vec::new();
            let mut chunks = response.bytes_stream();
            while let Some(chunk) = chunks.next().await {
                let chunk = chunk.map_err(boxed)?;
                if body.len() + chunk.len() > MAX_RESPONSE_BYTES {
                    return Err(boxed(TooLarge));
                }
                body.extend_from_slice(&chunk);
            }
            builder.body(body).map_err(boxed)
        })
    }
}

#[derive(Debug, thiserror::Error)]
#[error("the response is larger than {MAX_RESPONSE_BYTES} bytes")]
struct TooLarge;

fn boxed(error: impl std::error::Error + Send + Sync + 'static) -> OAuthHttpClientError {
    Box::new(error)
}

/// Loads and stores the OAuth credentials of a server (rmcp's [`StoredCredentials`]), as
/// encrypted JSON in its row. Only while the server still has the URL they were issued for.
struct DbCredentialStore {
    db: DatabasePool,
    cipher: Arc<TokenCipher>,
    server_id: Uuid,
    url: String,
    /// Whether storing credentials signs in, replacing a token. Otherwise only refreshed
    /// credentials are stored, so a sign-out in the meantime stays.
    sign_in: bool,
}

#[async_trait::async_trait]
impl CredentialStore for DbCredentialStore {
    async fn load(&self) -> Result<Option<StoredCredentials>, AuthError> {
        let Some(encrypted) =
            repository::mcp::get_oauth_credentials(&self.db, self.server_id, &self.url)
                .await
                .map_err(store_error)?
        else {
            return Ok(None);
        };
        let json = self
            .cipher
            .decrypt(self.server_id, &encrypted)
            .map_err(store_error)?;
        serde_json::from_str(&json).map(Some).map_err(store_error)
    }

    async fn save(&self, credentials: StoredCredentials) -> Result<(), AuthError> {
        let json = serde_json::to_string(&credentials).map_err(store_error)?;
        let encrypted = self
            .cipher
            .encrypt(self.server_id, &json)
            .map_err(store_error)?;
        let saved = repository::mcp::save_oauth_credentials(
            &self.db,
            self.server_id,
            &self.url,
            &encrypted,
            self.sign_in,
        )
        .await
        .map_err(store_error)?;
        if !saved {
            return Err(AuthError::CredentialStoreError(
                "the MCP server was changed or deleted".to_string(),
            ));
        }
        Ok(())
    }

    async fn clear(&self) -> Result<(), AuthError> {
        repository::mcp::clear_oauth_credentials(&self.db, self.server_id, &self.url)
            .await
            .map_err(store_error)
    }
}

fn store_error(error: impl std::fmt::Display) -> AuthError {
    AuthError::CredentialStoreError(error.to_string())
}

/// The authorization manager of a server the user signed in to, which refreshes the tokens.
pub(super) async fn signed_in_manager(
    client: &McpClient,
    target: &McpTarget,
) -> Result<AuthorizationManager, ConnectError> {
    debug_assert!(matches!(target.credentials, Credentials::OAuth));
    let mut manager = new_manager(client, &target.url, target.access, target.id, false)
        .await
        .map_err(|e| super::auth_error(&e, target.id))?;
    // Discovers the metadata of the authorization server.
    let signed_in = manager
        .initialize_from_store()
        .await
        .map_err(|e| super::auth_error(&e, target.id))?;
    if !signed_in {
        return Err(ConnectError::AuthorizationRequired { challenge: None });
    }
    Ok(manager)
}

async fn new_manager(
    client: &McpClient,
    url: &str,
    access: RemoteAccess,
    server_id: Uuid,
    sign_in: bool,
) -> Result<AuthorizationManager, AuthError> {
    let http: Arc<dyn OAuthHttpClient> = client.http.clients(access).oauth.clone();
    let mut manager = AuthorizationManager::new_with_oauth_http_client(url, http).await?;
    manager.set_credential_store(DbCredentialStore {
        db: client.db.clone(),
        cipher: client.cipher.clone(),
        server_id,
        url: url.to_string(),
        sign_in,
    });
    Ok(manager)
}

/// The sign-ins in progress, by their `state` parameter.
#[derive(Default)]
pub(super) struct PendingSignIns(Mutex<HashMap<String, PendingSignIn>>);

struct PendingSignIn {
    user_id: Uuid,
    server_id: Uuid,
    /// Holds the PKCE verifier and the registered client.
    session: AuthorizationSession,
    started_at: Instant,
}

impl PendingSignIns {
    fn insert(&self, state: String, sign_in: PendingSignIn) {
        let mut pending = self.0.lock().unwrap();
        pending.retain(|_, p| p.started_at.elapsed() < SIGN_IN_TIMEOUT);
        let mut own: Vec<(Instant, String)> = pending
            .iter()
            .filter(|(_, p)| p.user_id == sign_in.user_id)
            .map(|(state, p)| (p.started_at, state.clone()))
            .collect();
        own.sort();
        let excess = (own.len() + 1).saturating_sub(MAX_SIGN_INS_PER_USER);
        for (_, state) in own.into_iter().take(excess) {
            pending.remove(&state);
        }
        pending.insert(state, sign_in);
    }

    /// The sign-in with `state`, if it is the user's and has not expired.
    fn take(&self, user_id: Uuid, state: &str) -> Option<PendingSignIn> {
        let mut pending = self.0.lock().unwrap();
        match pending.get(state) {
            Some(p) if p.user_id == user_id && p.started_at.elapsed() < SIGN_IN_TIMEOUT => {
                pending.remove(state)
            }
            _ => None,
        }
    }
}

pub(super) async fn start_sign_in(
    client: &McpClient,
    user_id: Uuid,
    server: &McpServer,
    access: RemoteAccess,
    redirect_uri: &str,
) -> Result<String, AppError> {
    check_url(&server.url, access).map_err(super::connect_app_error)?;
    // The server's challenge may name its metadata, which spares guessing where it is.
    let target = McpTarget {
        id: server.id,
        url: server.url.clone(),
        access,
        credentials: Credentials::None,
    };
    let challenge = match client.connect(&target).await {
        Ok(session) => {
            super::close(session).await;
            return Err(AppError::BadRequest(
                "The server does not require signing in".to_string(),
            ));
        }
        Err(ConnectError::AuthorizationRequired { challenge }) => challenge,
        Err(ConnectError::Failed(message)) => {
            return Err(AppError::BadGateway(ErrorCode::RemoteUnreachable, message));
        }
    };

    let mut manager = new_manager(client, &server.url, access, server.id, true)
        .await
        .map_err(|e| sign_in_error(e, server.id))?;
    let resolution = manager
        .resolve_metadata_from_challenge(challenge.as_deref())
        .await
        .map_err(|e| sign_in_error(e, server.id))?;
    if resolution.source == AuthorizationMetadataSource::LegacyEndpointFallback {
        return Err(AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The server does not support signing in with OAuth, set a token instead".to_string(),
        ));
    }
    manager.set_metadata(resolution.metadata);

    // A web application, since the redirect URI is the frontend's (`native` is the default).
    let request = AuthorizationRequest::new(redirect_uri)
        .with_client_name(CLIENT_NAME)
        .with_application_type("web");
    let session = AuthorizationSession::new(manager, request)
        .await
        .map_err(|(_, e)| sign_in_error(e, server.id))?;
    let authorization_url = session.get_authorization_url().to_string();
    let parsed = Url::parse(&authorization_url)
        .map_err(|e| AppError::InternalServerError(format!("Invalid authorization URL: {e}")))?;
    // The frontend navigates to it, so e.g. `javascript:` would run in its origin.
    let allowed = match access {
        RemoteAccess::Public => parsed.scheme() == "https",
        RemoteAccess::Unrestricted => matches!(parsed.scheme(), "https" | "http"),
    };
    if !allowed {
        return Err(AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The authorization server's address does not use https://".to_string(),
        ));
    }
    let state = parsed
        .query_pairs()
        .find(|(key, _)| key == "state")
        .map(|(_, value)| value.into_owned())
        .ok_or_else(|| {
            AppError::InternalServerError("The authorization URL has no state".to_string())
        })?;
    client.sign_ins.insert(
        state,
        PendingSignIn {
            user_id,
            server_id: server.id,
            session,
            started_at: Instant::now(),
        },
    );
    Ok(authorization_url)
}

pub(super) async fn complete_sign_in(
    client: &McpClient,
    user_id: Uuid,
    state: &str,
    code: &str,
    issuer: Option<&str>,
) -> Result<Uuid, AppError> {
    let sign_in = client
        .sign_ins
        .take(user_id, state)
        .ok_or(AppError::NotFound)?;
    // Stores the tokens with the server (through `DbCredentialStore`).
    sign_in
        .session
        .handle_callback_with_issuer(code, state, issuer)
        .await
        .map_err(|e| match e {
            AuthError::CredentialStoreError(_) => AppError::Conflict(
                ErrorCode::Conflict,
                "The server was changed while signing in, please sign in again".to_string(),
            ),
            e => sign_in_error(e, sign_in.server_id),
        })?;
    Ok(sign_in.server_id)
}

/// The messages of rmcp name the step that failed, and the server's own message.
fn sign_in_error(error: AuthError, server_id: Uuid) -> AppError {
    tracing::info!("Signing in to MCP server {server_id} failed: {error}");
    match error {
        AuthError::HttpError(_) | AuthError::MetadataError(_) => AppError::BadGateway(
            ErrorCode::RemoteUnreachable,
            format!("Signing in failed: {error}"),
        ),
        _ => AppError::Unprocessable(ErrorCode::AuthFailed, format!("Signing in failed: {error}")),
    }
}
