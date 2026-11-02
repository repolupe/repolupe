//! The user's MCP servers, see [`crate::service::mcp`].

use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::controller::encrypt_token;
use crate::dto::mcp::{
    AuthorizationUrlDto, AuthorizeMcpServerRequest, CreateMcpServerRequest,
    McpAuthorizationCallbackRequest, McpServerDto, McpServerStatus, UpdateMcpServerRequest,
};
use crate::middleware::auth::AuthenticatedUser;
use crate::model::mcp_server::{McpServer, McpTool};
use crate::model::remote_access::RemoteAccess;
use crate::repository::mcp::{Connection, McpServerChanges, NewMcpServer};
use crate::service::mcp::{ConnectError, Credentials, McpTarget, connect_app_error};
use crate::util::extract::{JsonBody, PathParam};
use crate::util::validation::ValidationError;
use crate::{repository, util};
use axum::extract::State;
use axum::http::StatusCode;
use axum::{Extension, Json};
use chrono::Utc;
use uuid::Uuid;

pub(crate) async fn list_mcp_servers(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
) -> Result<Json<Vec<McpServerDto>>, AppError> {
    let servers = repository::mcp::list_mcp_servers(&state.db, auth.user_id).await?;
    Ok(Json(servers.into_iter().map(Into::into).collect()))
}

pub(crate) async fn create_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<CreateMcpServerRequest>,
) -> Result<(StatusCode, Json<McpServerDto>), AppError> {
    let access = RemoteAccess::of(auth.role);
    let name = parse_name(&payload.name)?;
    let url = util::validation::parse_mcp_url(payload.url.trim(), access)?;
    let token = match payload.token.as_deref().map(str::trim) {
        Some(token) if !token.is_empty() => Some(parse_token(token)?),
        _ => None,
    };

    // The id is the token's associated data, so it is generated before encrypting.
    let id = Uuid::now_v7();
    let credentials = match token {
        Some(token) => Credentials::Token(token.to_string()),
        None => Credentials::None,
    };
    let target = McpTarget {
        id,
        url: url.to_string(),
        access,
        credentials,
    };
    let tools = state.mcp.list_tools(&target).await;
    let connection = connection(&target, &tools)?;
    let token = token.map(|t| encrypt_token(&state, id, t)).transpose()?;

    let server = repository::mcp::create_mcp_server(
        &state.db,
        NewMcpServer {
            id,
            user_id: auth.user_id,
            name,
            url: url.as_str(),
            token,
            connection,
        },
    )
    .await?;
    Ok((StatusCode::CREATED, Json(server.into())))
}

pub(crate) async fn update_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<UpdateMcpServerRequest>,
) -> Result<Json<McpServerDto>, AppError> {
    let name = parse_name(&payload.name)?;
    let disabled_tools = util::validation::parse_disabled_tools(&payload.disabled_tools)?;
    let server = repository::mcp::update_mcp_server(
        &state.db,
        auth.user_id,
        id,
        McpServerChanges {
            name,
            enabled: payload.enabled,
            disabled_tools: &disabled_tools,
        },
    )
    .await?
    .ok_or(AppError::NotFound)?;
    Ok(Json(server.into()))
}

/// Deleting a missing server also succeeds, so the request is safe to retry.
pub(crate) async fn delete_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    repository::mcp::delete_mcp_server(&state.db, auth.user_id, id).await?;
    state.mcp.forget(id);
    Ok(StatusCode::NO_CONTENT)
}

/// Connects again and lists the tools. Failures are stored with the server, not returned.
pub(crate) async fn refresh_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<McpServerDto>, AppError> {
    let server = find_mcp_server(&state, auth.user_id, id).await?;
    let server = state
        .mcp
        .refresh(server, RemoteAccess::of(auth.role))
        .await?;
    Ok(Json(server.into()))
}

pub(crate) async fn authorize_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<AuthorizeMcpServerRequest>,
) -> Result<Json<AuthorizationUrlDto>, AppError> {
    let redirect_uri = util::validation::parse_redirect_uri(payload.redirect_uri.trim())?;
    let server = find_mcp_server(&state, auth.user_id, id).await?;
    let authorization_url = state
        .mcp
        .start_sign_in(
            auth.user_id,
            &server,
            RemoteAccess::of(auth.role),
            redirect_uri.as_str(),
        )
        .await?;
    Ok(Json(AuthorizationUrlDto { authorization_url }))
}

/// Stores the credentials, then connects again.
pub(crate) async fn complete_mcp_authorization(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<McpAuthorizationCallbackRequest>,
) -> Result<Json<McpServerDto>, AppError> {
    let id = state
        .mcp
        .complete_sign_in(
            auth.user_id,
            &payload.state,
            &payload.code,
            payload.iss.as_deref(),
        )
        .await?;
    let server = find_mcp_server(&state, auth.user_id, id).await?;
    let server = state
        .mcp
        .refresh(server, RemoteAccess::of(auth.role))
        .await?;
    Ok(Json(server.into()))
}

/// How a new or changed server is stored after connecting to it. A server that asks for
/// authentication is stored to sign in to, unless it rejected the token, which fails like an
/// unreachable server.
fn connection<'a>(
    target: &McpTarget,
    tools: &'a Result<Vec<McpTool>, ConnectError>,
) -> Result<Connection<'a>, AppError> {
    let checked_at = Utc::now();
    match tools {
        Ok(tools) => Ok(Connection {
            status: McpServerStatus::Ready,
            last_error: None,
            tools: Some(tools),
            checked_at,
        }),
        Err(ConnectError::AuthorizationRequired { .. })
            if !matches!(target.credentials, Credentials::Token(_)) =>
        {
            Ok(Connection {
                status: McpServerStatus::AuthorizationRequired,
                last_error: None,
                tools: None,
                checked_at,
            })
        }
        Err(e) => Err(connect_app_error(e.clone())),
    }
}

/// Servers of other users are reported as missing.
async fn find_mcp_server(state: &AppState, user_id: Uuid, id: Uuid) -> Result<McpServer, AppError> {
    repository::mcp::get_mcp_server(&state.db, user_id, id)
        .await?
        .ok_or(AppError::NotFound)
}

fn parse_name(name: &str) -> Result<&str, ValidationError> {
    let name = name.trim();
    util::validation::validate_name(name)?;
    Ok(name)
}

fn parse_token(token: &str) -> Result<&str, ValidationError> {
    let token = token.trim();
    util::validation::validate_token(token)?;
    Ok(token)
}
