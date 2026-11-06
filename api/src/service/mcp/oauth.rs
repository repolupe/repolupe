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
use crate::util::http::redirect_policy;
use crate::util::ip::{NotPublic, has_public_host};
use crate::util::token_cipher::TokenCipher;
use futures_util::StreamExt;
use reqwest::redirect::Policy;
use rmcp::transport::auth::{
    AuthError, AuthorizationManager, AuthorizationMetadataSource, AuthorizationRequest,
    AuthorizationSession, CredentialRefreshGuard, CredentialStore, OAuthClientConfig,
    OAuthHttpClient, OAuthHttpClientError, OAuthHttpClientFuture, OAuthHttpRedirectPolicy,
    OAuthHttpRequest, StoredCredentials,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant};
use tokio::sync::OwnedMutexGuard;
use url::{Host, Url};
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
            follow: builder().redirect(redirect_policy(access)).build()?,
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

/// What a server's row holds, as encrypted JSON: rmcp's credentials, and the secret of the
/// client, which they have no field for. Authorization servers may register Repolupe as a
/// confidential client although it asks for a public one, and then require the secret for
/// refreshing the tokens.
#[derive(Serialize, Deserialize)]
struct StoredOAuth {
    #[serde(flatten)]
    credentials: StoredCredentials,
    /// Absent in the credentials stored before it was kept.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    client_secret: Option<String>,
}

/// Loads and stores the OAuth credentials of a server ([`StoredOAuth`]), encrypted in its row.
struct DbCredentialStore {
    db: DatabasePool,
    cipher: Arc<TokenCipher>,
    server_id: Uuid,
    /// Whether storing credentials signs in, replacing a token. Otherwise only refreshed
    /// credentials are stored, so a sign-out in the meantime stays.
    sign_in: bool,
    /// The secret of the client, stored with the credentials.
    client_secret: Option<String>,
    refresh_locks: RefreshLocks,
}

impl DbCredentialStore {
    fn new(client: &McpClient, server_id: Uuid, sign_in: bool) -> Self {
        Self {
            db: client.db.clone(),
            cipher: client.cipher.clone(),
            server_id,
            sign_in,
            client_secret: None,
            refresh_locks: client.refresh_locks.clone(),
        }
    }

    async fn load_stored(&self) -> Result<Option<StoredOAuth>, AuthError> {
        let Some(encrypted) = repository::mcp::get_oauth_credentials(&self.db, self.server_id)
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
}

#[async_trait::async_trait]
impl CredentialStore for DbCredentialStore {
    async fn load(&self) -> Result<Option<StoredCredentials>, AuthError> {
        Ok(self.load_stored().await?.map(|stored| stored.credentials))
    }

    async fn save(&self, credentials: StoredCredentials) -> Result<(), AuthError> {
        let stored = StoredOAuth {
            credentials,
            client_secret: self.client_secret.clone(),
        };
        let json = serde_json::to_string(&stored).map_err(store_error)?;
        let encrypted = self
            .cipher
            .encrypt(self.server_id, &json)
            .map_err(store_error)?;
        let saved = repository::mcp::save_oauth_credentials(
            &self.db,
            self.server_id,
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
        repository::mcp::clear_oauth_credentials(&self.db, self.server_id)
            .await
            .map_err(store_error)
    }

    /// rmcp loads the credentials again once it has the guard, so a refresh waiting for
    /// another one uses the refresh token that one got.
    async fn acquire_refresh_guard(&self) -> Result<Option<CredentialRefreshGuard>, AuthError> {
        let guard = self.refresh_locks.lock(self.server_id).await;
        Ok(Some(CredentialRefreshGuard::new(guard)))
    }
}

/// Lets only one authorization manager of a server refresh its tokens at a time. A server
/// can have several: connections that miss the cached OAuth client at the same time build one
/// each, and an answer keeps using the one it connected with after it is dropped from the
/// cache. Authorization servers may rotate the refresh token, and then reject the second
/// refresh with the same one, or even revoke the access. Only the servers with a refresh in
/// progress or waiting have a lock.
#[derive(Clone, Default)]
pub(super) struct RefreshLocks(Arc<Mutex<HashMap<Uuid, Weak<tokio::sync::Mutex<()>>>>>);

impl RefreshLocks {
    async fn lock(&self, server_id: Uuid) -> OwnedMutexGuard<()> {
        let lock = {
            let mut locks = self.0.lock().unwrap();
            locks.retain(|_, lock| lock.strong_count() > 0);
            match locks.get(&server_id).and_then(Weak::upgrade) {
                Some(lock) => lock,
                None => {
                    let lock = Arc::new(tokio::sync::Mutex::new(()));
                    locks.insert(server_id, Arc::downgrade(&lock));
                    lock
                }
            }
        };
        lock.lock_owned().await
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
    let error = |e: AuthError| super::auth_error(&e, target.id);
    let mut manager = new_manager(client, &target.url, target.access, target.id, false)
        .await
        .map_err(error)?;
    // Discovers the metadata of the authorization server.
    let signed_in = manager.initialize_from_store().await.map_err(error)?;
    if !signed_in {
        return Err(ConnectError::AuthorizationRequired { challenge: None });
    }
    // rmcp configures the client without its secret, which its credentials don't hold.
    let store = DbCredentialStore::new(client, target.id, false);
    if let Some(StoredOAuth {
        credentials,
        client_secret: Some(secret),
    }) = store.load_stored().await.map_err(error)?
    {
        let config = OAuthClientConfig::new(credentials.client_id, target.url.as_str())
            .with_client_secret(secret.clone());
        manager.configure_client(config).map_err(error)?;
        manager.set_credential_store(DbCredentialStore {
            client_secret: Some(secret),
            ..store
        });
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
    manager.set_credential_store(DbCredentialStore::new(client, server_id, sign_in));
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
    redirect_url: &Url,
) -> Result<String, AppError> {
    check_url(&server.url, access).map_err(super::connect_app_error)?;
    let redirect_uri = redirect_url.as_str();
    let application_type = application_type(redirect_url);
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
        // Without credentials, a refusal is taken as asking for them too.
        Err(
            ConnectError::AuthorizationRequired { challenge }
            | ConnectError::Forbidden { challenge },
        ) => challenge,
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

    // Registers the client here rather than in `AuthorizationSession`, which would keep its
    // secret only in memory (see `StoredOAuth`). `register_client` takes the application type
    // from the client configured before, so this one is replaced right away.
    let error = |e| sign_in_error(e, server.id);
    manager
        .configure_client(
            OAuthClientConfig::new("", redirect_uri).with_application_type(application_type),
        )
        .map_err(error)?;
    // The scopes `AuthorizationSession` would select.
    let scopes = manager.select_scopes(None, &[]);
    let scope_refs: Vec<&str> = scopes.iter().map(String::as_str).collect();
    let registered = manager
        .register_client(CLIENT_NAME, redirect_uri, &scope_refs)
        .await
        .map_err(error)?;
    let store = DbCredentialStore {
        client_secret: registered.client_secret.clone(),
        ..DbCredentialStore::new(client, server.id, true)
    };
    manager.set_credential_store(store);

    let mut request = AuthorizationRequest::new(redirect_uri)
        .with_preregistered_client(registered.client_id)
        .with_scopes(scopes)
        .with_application_type(application_type);
    if let Some(secret) = registered.client_secret {
        request = request.with_client_secret(secret);
    }
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

/// The OIDC `application_type` Repolupe registers as: `native` for a loopback redirect URI (RFC
/// 8252), which the app receives the code on, as authorization servers may reject a web
/// application redirecting there. Otherwise `web`, since the redirect URI is the frontend's.
fn application_type(redirect_url: &Url) -> &'static str {
    let loopback = match redirect_url.host() {
        Some(Host::Domain(domain)) => domain.eq_ignore_ascii_case("localhost"),
        Some(Host::Ipv4(ip)) => ip.is_loopback(),
        Some(Host::Ipv6(ip)) => ip.is_loopback(),
        None => false,
    };
    if loopback { "native" } else { "web" }
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn reads_credentials_stored_without_a_client_secret() {
        let old = json!({
            "client_id": "client-1",
            "token_response": {"access_token": "a", "token_type": "bearer", "refresh_token": "r"},
            "granted_scopes": [],
            "token_received_at": 1,
        });
        let stored: StoredOAuth = serde_json::from_value(old).unwrap();
        assert_eq!(stored.credentials.client_id, "client-1");
        assert!(stored.credentials.token_response.is_some());
        assert_eq!(stored.client_secret, None);

        let stored = StoredOAuth {
            client_secret: Some("secret".to_string()),
            ..stored
        };
        let read: StoredOAuth =
            serde_json::from_str(&serde_json::to_string(&stored).unwrap()).unwrap();
        assert_eq!(read.client_secret.as_deref(), Some("secret"));
        assert!(read.credentials.token_response.is_some());
    }

    #[test]
    fn registers_as_native_application_for_loopback_redirects() {
        let of = |uri: &str| application_type(&Url::parse(uri).unwrap());
        assert_eq!(of("http://localhost:4242/callback"), "native");
        assert_eq!(of("http://LOCALHOST:4242/callback"), "native");
        assert_eq!(of("http://127.0.0.1:4242/callback"), "native");
        assert_eq!(of("http://[::1]:4242/callback"), "native");
        assert_eq!(of("https://repolupe.example.com/callback"), "web");
        assert_eq!(of("http://localhost.example.com/callback"), "web");
        assert_eq!(of("http://192.168.1.2:3000/callback"), "web");
    }

    #[tokio::test]
    async fn refresh_locks_wait_only_for_the_same_server() {
        let locks = RefreshLocks::default();
        let (first, second) = (Uuid::now_v7(), Uuid::now_v7());
        let wait = Duration::from_millis(50);

        let guard = locks.lock(first).await;
        assert!(tokio::time::timeout(wait, locks.lock(first)).await.is_err());
        assert!(tokio::time::timeout(wait, locks.lock(second)).await.is_ok());
        drop(guard);
        assert!(tokio::time::timeout(wait, locks.lock(first)).await.is_ok());

        // Unused locks are dropped.
        let _guard = locks.lock(second).await;
        assert_eq!(locks.0.lock().unwrap().len(), 1);
    }
}
