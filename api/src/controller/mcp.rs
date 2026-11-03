//! The user's MCP servers and the ones shared with them, see [`crate::service::mcp`]. Only the
//! owner manages a server, including its sharing.

use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::controller::encrypt_token;
use crate::dto::error::ErrorCode;
use crate::dto::mcp::{
    AddMcpServerUserRequest, AuthorizationUrlDto, AuthorizeMcpServerRequest,
    CreateMcpServerRequest, McpAuthorizationCallbackRequest, McpServerDto, McpServerStatus,
    McpServerUserDto, UpdateMcpServerRequest, UpdateMcpServerUserRequest,
};
use crate::middleware::auth::AuthenticatedUser;
use crate::model::mcp_server::{McpServer, McpTool};
use crate::model::remote_access::RemoteAccess;
use crate::repository::mcp::{Connection, McpServerChanges, NewMcpServer};
use crate::service::mcp::{ConnectError, Credentials, McpTarget, connect_app_error};
use crate::util::extract::{JsonBody, PathParam};
use crate::util::validation::{parse_name, parse_token};
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
    Ok(Json(
        servers
            .into_iter()
            .map(|(server, share)| McpServerDto::new(server, share, auth.user_id))
            .collect(),
    ))
}

pub(crate) async fn create_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<CreateMcpServerRequest>,
) -> Result<(StatusCode, Json<McpServerDto>), AppError> {
    require_mcp_server_management(&auth)?;
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
    Ok((
        StatusCode::CREATED,
        Json(McpServerDto::new(server, None, auth.user_id)),
    ))
}

pub(crate) async fn update_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<UpdateMcpServerRequest>,
) -> Result<Json<McpServerDto>, AppError> {
    require_mcp_server_management(&auth)?;
    let name = parse_name(&payload.name)?;
    let disabled_tools = util::validation::parse_disabled_tools(&payload.disabled_tools)?;
    let Some(server) = repository::mcp::update_mcp_server(
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
    else {
        // Shared with the user, but not theirs to manage.
        find_mcp_server(&state, auth.user_id, id).await?;
        return Err(not_owner());
    };
    Ok(Json(McpServerDto::new(server, None, auth.user_id)))
}

/// Deleting a missing server also succeeds, so the request is safe to retry.
pub(crate) async fn delete_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    require_mcp_server_management(&auth)?;
    if repository::mcp::delete_mcp_server(&state.db, auth.user_id, id).await? {
        state.mcp.forget(id);
    } else if repository::mcp::get_mcp_server(&state.db, auth.user_id, id)
        .await?
        .is_some()
    {
        return Err(not_owner());
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Connects again and lists the tools. Failures are stored with the server, not returned.
pub(crate) async fn refresh_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<McpServerDto>, AppError> {
    require_mcp_server_management(&auth)?;
    let server = find_owned_mcp_server(&state, auth.user_id, id).await?;
    let server = state
        .mcp
        .refresh(server, RemoteAccess::of(auth.role))
        .await?;
    Ok(Json(McpServerDto::new(server, None, auth.user_id)))
}

pub(crate) async fn authorize_mcp_server(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<AuthorizeMcpServerRequest>,
) -> Result<Json<AuthorizationUrlDto>, AppError> {
    require_mcp_server_management(&auth)?;
    let redirect_uri = util::validation::parse_redirect_uri(payload.redirect_uri.trim())?;
    let server = find_owned_mcp_server(&state, auth.user_id, id).await?;
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
    require_mcp_server_management(&auth)?;
    let id = state
        .mcp
        .complete_sign_in(
            auth.user_id,
            &payload.state,
            &payload.code,
            payload.iss.as_deref(),
        )
        .await?;
    let server = find_owned_mcp_server(&state, auth.user_id, id).await?;
    let server = state
        .mcp
        .refresh(server, RemoteAccess::of(auth.role))
        .await?;
    Ok(Json(McpServerDto::new(server, None, auth.user_id)))
}

/// The users the server is shared with. Only for its owner.
pub(crate) async fn list_mcp_server_users(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<Vec<McpServerUserDto>>, AppError> {
    require_mcp_server_management(&auth)?;
    let users = repository::mcp::list_mcp_server_users(&state.db, auth.user_id, id).await?;
    if users.is_empty() {
        // Shared with nobody, or not the user's server.
        find_owned_mcp_server(&state, auth.user_id, id).await?;
    }
    Ok(Json(users.into_iter().map(Into::into).collect()))
}

/// Shares the server with the user of `user_name_or_email`, whose chats get its tools, used
/// with the owner's credentials, once they turn it on (see [`update_mcp_server_user`]): its
/// tools and what they return go into their chats, so they decide whether to trust it. Sharing
/// it again does nothing. Only for its owner: unlike repositories, not for admins, since the
/// server acts with the owner's credentials.
pub(crate) async fn add_mcp_server_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<AddMcpServerUserRequest>,
) -> Result<StatusCode, AppError> {
    require_mcp_server_management(&auth)?;
    let user =
        repository::user::get_user_by_login(&state.db, payload.user_name_or_email.trim()).await?;
    let user = match user {
        Some(user) if user.id != auth.user_id => user,
        user => {
            // Not finding the server is reported first.
            find_owned_mcp_server(&state, auth.user_id, id).await?;
            return Err(match user {
                None => AppError::Unprocessable(
                    ErrorCode::UnknownUser,
                    "There is no user with this user name or email".to_string(),
                ),
                Some(_) => AppError::BadRequest(
                    "The owner already has access to the MCP server".to_string(),
                ),
            });
        }
    };
    if !repository::mcp::add_mcp_server_user(&state.db, auth.user_id, id, user.id).await? {
        // Already shared with them, or not the user's server.
        find_owned_mcp_server(&state, auth.user_id, id).await?;
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Turns a server shared with the user on or off for their chats. Only for that user, also
/// without the permission to manage MCP servers, like leaving it.
pub(crate) async fn update_mcp_server_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((id, user_id)): PathParam<(Uuid, Uuid)>,
    JsonBody(payload): JsonBody<UpdateMcpServerUserRequest>,
) -> Result<StatusCode, AppError> {
    if user_id != auth.user_id {
        find_mcp_server(&state, auth.user_id, id).await?;
        return Err(AppError::Forbidden(
            "Only the user an MCP server is shared with decides whether to use it".to_string(),
        ));
    }
    if !repository::mcp::update_mcp_server_user(&state.db, id, user_id, payload.enabled).await? {
        // Not shared with the user: someone else's, or their own.
        find_mcp_server(&state, auth.user_id, id).await?;
        return Err(AppError::BadRequest(
            "The owner turns the MCP server on or off by changing it".to_string(),
        ));
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Stops sharing the server with the user, whose chats no longer get its tools. Allowed for
/// its owner, and for the user themselves to leave it, also without the permission to manage
/// MCP servers. Removing a user it is not shared with also succeeds, so the request is safe to
/// retry.
pub(crate) async fn remove_mcp_server_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((id, user_id)): PathParam<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let leaving = user_id == auth.user_id;
    if !leaving {
        require_mcp_server_management(&auth)?;
    }
    if !repository::mcp::remove_mcp_server_user(&state.db, auth.user_id, id, user_id).await?
        && !leaving
    {
        // Not shared with them, or not the user's server.
        find_owned_mcp_server(&state, auth.user_id, id).await?;
    }
    Ok(StatusCode::NO_CONTENT)
}

/// How a new or changed server is stored after connecting to it. A server that asks for
/// authentication (or refuses the connection) is stored to sign in to, unless it rejected (or
/// refused) the token, which fails.
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
        Err(ConnectError::AuthorizationRequired { .. } | ConnectError::Forbidden { .. })
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

/// Users without the permission keep listing their servers (and the ones shared with them) and
/// using them in chats, and may turn shared ones on or off and leave them, but cannot add,
/// change, connect, share or delete any, like repositories.
fn require_mcp_server_management(auth: &AuthenticatedUser) -> Result<(), AppError> {
    if !auth.can_manage_mcp_servers {
        return Err(AppError::Forbidden(
            "You are not allowed to manage MCP servers".to_string(),
        ));
    }
    Ok(())
}

/// Servers of other users are reported as missing, never as forbidden, unless they are shared
/// with the user.
async fn find_mcp_server(state: &AppState, user_id: Uuid, id: Uuid) -> Result<McpServer, AppError> {
    repository::mcp::get_mcp_server(&state.db, user_id, id)
        .await?
        .ok_or(AppError::NotFound)
}

/// Like [`find_mcp_server`], but forbidden if the server is only shared with the user.
async fn find_owned_mcp_server(
    state: &AppState,
    user_id: Uuid,
    id: Uuid,
) -> Result<McpServer, AppError> {
    let server = find_mcp_server(state, user_id, id).await?;
    if server.user_id != user_id {
        return Err(not_owner());
    }
    Ok(server)
}

fn not_owner() -> AppError {
    AppError::Forbidden("Only the owner can manage the MCP server".to_string())
}
