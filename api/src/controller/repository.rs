use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::controller::encrypt_token;
use crate::dto::error::ErrorCode;
use crate::dto::extraction::RepositoryDocumentsDto;
use crate::dto::repository::{
    AddRepositoryUserRequest, CreateRepositoryRequest, RemoteSettingsChange, RepositoryDto,
    RepositoryUserDto, TokenChange, UpdateRepositoryRequest, UpdateRepositoryUserRequest,
};
use crate::dto::user::UserRole;
use crate::middleware::auth::AuthenticatedUser;
use crate::model::remote_access::RemoteAccess;
use crate::model::repository::{Remote, Repository};
use crate::repository::repository::{NewRepository, RepositoryChanges};
use crate::util::extract::{JsonBody, PathParam};
use crate::util::validation::ValidationError;
use crate::{repository, util};
use axum::extract::State;
use axum::http::StatusCode;
use axum::{Extension, Json};
use url::Url;
use uuid::Uuid;

/// The branch of local repositories. Nobody can clone them, so only the model sees it.
const LOCAL_BRANCH: &str = "main";

pub(crate) async fn list_repositories(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
) -> Result<Json<Vec<RepositoryDto>>, AppError> {
    let repositories = repository::repository::list_repositories(&state.db, auth.user_id).await?;
    Ok(Json(
        repositories
            .into_iter()
            .map(|r| RepositoryDto::new(r, &auth))
            .collect(),
    ))
}

pub(crate) async fn get_repository(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<RepositoryDto>, AppError> {
    let repository = find_repository(&state, auth.user_id, id).await?;
    Ok(Json(RepositoryDto::new(repository, &auth)))
}

/// The documents in the synced commit, and how far their conversion to Markdown is.
pub(crate) async fn list_repository_documents(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<RepositoryDocumentsDto>, AppError> {
    find_repository(&state, auth.user_id, id).await?;
    // Before the extractions, so a document converted in between is not shown as waiting.
    let status = state.extractor.status();
    let documents = repository::document::list_documents(&state.db, id).await?;
    Ok(Json(RepositoryDocumentsDto::new(documents, &status)))
}

pub(crate) async fn create_repository(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    JsonBody(payload): JsonBody<CreateRepositoryRequest>,
) -> Result<(StatusCode, Json<RepositoryDto>), AppError> {
    require_repository_management(&auth)?;
    let access = RemoteAccess::of(auth.role);
    let name = parse_name(&payload.name)?;
    let description = parse_description(payload.description.as_deref())?;

    let (remote_url, branch, poll_interval_seconds, token) = match &payload.remote {
        Some(remote) => {
            let remote_url = util::validation::parse_remote_url(remote.url.trim(), access)?;
            let branch = parse_branch(&remote.branch)?;
            util::validation::validate_poll_interval(remote.poll_interval_seconds)?;
            let token = remote.token.as_deref().map(parse_token).transpose()?;

            state
                .mirrors
                .check_remote(&remote_url, branch, token, access)
                .await?;
            if payload.allow_commits {
                state
                    .mirrors
                    .check_push(&remote_url, branch, token, access)
                    .await?;
            }
            (
                Some(remote_url),
                branch,
                Some(remote.poll_interval_seconds),
                token,
            )
        }
        None => (None, LOCAL_BRANCH, None, None),
    };

    // The id is the token's associated data, so it is generated before encrypting.
    let id = Uuid::now_v7();
    let token = token.map(|t| encrypt_token(&state, id, t)).transpose()?;

    let repository = repository::repository::create_repository(
        &state.db,
        NewRepository {
            id,
            user_id: auth.user_id,
            name,
            description,
            remote_url: remote_url.as_ref().map(Url::as_str),
            branch,
            poll_interval_seconds,
            token,
            allow_commits: payload.allow_commits,
        },
    )
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(RepositoryDto::new(repository, &auth)),
    ))
}

pub(crate) async fn update_repository(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<UpdateRepositoryRequest>,
) -> Result<Json<RepositoryDto>, AppError> {
    require_repository_management(&auth)?;
    let access = RemoteAccess::of(auth.role);
    let name = parse_name(&payload.name)?;
    let description = parse_description(payload.description.as_deref())?;
    let current = find_owned_repository(&state, auth.user_id, id).await?;
    // The changes to a local repository, which stays local.
    let changes = RepositoryChanges {
        name,
        description,
        remote_url: None,
        branch: &current.branch,
        poll_interval_seconds: None,
        token: None,
        allow_commits: payload.allow_commits,
        reset_sync: false,
        retry_failed_sync: false,
    };
    // Outlives `changes`, which refers to it.
    let remote_url;
    let changes = match (current.remote(), &payload.remote) {
        (Some(current_remote), Some(remote)) => {
            remote_url = util::validation::parse_remote_url(remote.url.trim(), access)?;
            remote_changes(
                &state,
                access,
                &current,
                &current_remote,
                remote,
                &remote_url,
                changes,
            )
            .await?
        }
        (None, None) => changes,
        (None, Some(_)) => {
            return Err(AppError::BadRequest(
                "A local repository cannot get a remote".to_string(),
            ));
        }
        (Some(_), None) => {
            return Err(AppError::BadRequest(
                "The remote of a repository cannot be removed".to_string(),
            ));
        }
    };

    let updated = repository::repository::update_repository(
        &state.db,
        auth.user_id,
        id,
        current.remote_url.as_deref(),
        changes,
    )
    .await?;

    match updated {
        Some(repository) => Ok(Json(RepositoryDto::new(repository, &auth))),
        None => Err(not_found_or_conflict(&state, auth.user_id, id).await),
    }
}

/// Completes `changes` to `current`, a repository at `current_remote` that keeps a remote, with
/// `remote` at `remote_url`: checks the remote if it or the token changes, and that it takes
/// pushes when commits are turned on.
async fn remote_changes<'a>(
    state: &AppState,
    access: RemoteAccess,
    current: &Repository,
    current_remote: &Remote<'_>,
    remote: &'a RemoteSettingsChange,
    remote_url: &'a Url,
    changes: RepositoryChanges<'a>,
) -> Result<RepositoryChanges<'a>, AppError> {
    let branch = parse_branch(&remote.branch)?;
    util::validation::validate_poll_interval(remote.poll_interval_seconds)?;
    let host_changed = remote_url.origin() != current_remote.parsed_url()?.origin();
    let remote_changed = remote_url.as_str() != current_remote.url || branch != current.branch;

    // The existing token was only ever checked against the current host, so it is never
    // sent to a new one. `None` keeps it, `Some(_)` replaces it.
    let new_token: Option<Option<&str>> = match &remote.token {
        TokenChange::Keep if host_changed && current_remote.token_encrypted.is_some() => {
            return Err(AppError::Unprocessable(
                ErrorCode::TokenRequired,
                "The host changed, so the token cannot be kept. Set a new token, or remove it if the new remote is public".to_string(),
            ));
        }
        TokenChange::Keep => None,
        TokenChange::Remove => Some(None),
        TokenChange::Set { value } => Some(Some(parse_token(value)?)),
    };
    let token_set = matches!(new_token, Some(Some(_)));

    // Pushes are checked when commits are turned on, and when the remote or the token they
    // use changes.
    let check_push =
        changes.allow_commits && (!current.allow_commits || remote_changed || token_set);

    // Removing a token alone is not checked, so a leaked token can be removed
    // even while the remote is unreachable.
    if remote_changed || token_set || check_push {
        let token = match new_token {
            Some(token) => token.map(str::to_string),
            None => current_remote.token(&state.token_cipher)?,
        };
        if remote_changed || token_set {
            state
                .mirrors
                .check_remote(remote_url, branch, token.as_deref(), access)
                .await?;
        }
        if check_push {
            state
                .mirrors
                .check_push(remote_url, branch, token.as_deref(), access)
                .await?;
        }
    }

    let token = new_token
        .map(|token| {
            token
                .map(|t| encrypt_token(state, current.id, t))
                .transpose()
        })
        .transpose()?;
    Ok(RepositoryChanges {
        remote_url: Some(remote_url.as_str()),
        branch,
        poll_interval_seconds: Some(remote.poll_interval_seconds),
        token,
        reset_sync: remote_changed,
        // A failed sync was likely caused by the old token.
        retry_failed_sync: token_set,
        ..changes
    })
}

/// Deleting a missing repository also succeeds, so the request is safe to retry.
pub(crate) async fn delete_repository(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    require_repository_management(&auth)?;
    if !repository::repository::delete_repository(&state.db, auth.user_id, id).await?
        && repository::repository::get_repository(&state.db, auth.user_id, id)
            .await?
            .is_some()
    {
        return Err(not_owner());
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Only makes the repository due; the sync itself runs in the background.
pub(crate) async fn request_sync(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    require_repository_management(&auth)?;
    if !state.sync_throttle.try_acquire(id) {
        return Err(AppError::TooManyRequests(
            "A sync was requested less than a minute ago".to_string(),
        ));
    }
    match repository::repository::request_sync(&state.db, auth.user_id, id).await {
        Ok(true) => Ok(StatusCode::ACCEPTED),
        Ok(false) => {
            state.sync_throttle.release(id);
            // Shared with the user, but not theirs to manage.
            find_repository(&state, auth.user_id, id).await?;
            Err(not_owner())
        }
        Err(e) => {
            state.sync_throttle.release(id);
            Err(e)
        }
    }
}

/// The users the repository is shared with. Only for its owner and admins.
pub(crate) async fn list_repository_users(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<Vec<RepositoryUserDto>>, AppError> {
    find_managed_repository_owner(&state, &auth, id).await?;
    let users = repository::repository::list_repository_users(&state.db, id).await?;
    Ok(Json(users.into_iter().map(Into::into).collect()))
}

/// Shares the repository with the user of `user_name_or_email`, who can then read it and use it in
/// chats. Sharing it again does nothing. Only for its owner and admins.
pub(crate) async fn add_repository_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<AddRepositoryUserRequest>,
) -> Result<StatusCode, AppError> {
    let owner_id = find_managed_repository_owner(&state, &auth, id).await?;
    let user = repository::user::get_user_by_login(&state.db, payload.user_name_or_email.trim())
        .await?
        .ok_or_else(|| {
            AppError::Unprocessable(
                ErrorCode::UnknownUser,
                "There is no user with this user name or email".to_string(),
            )
        })?;
    if user.id == owner_id {
        return Err(AppError::BadRequest(
            "The owner already has access to the repository".to_string(),
        ));
    }
    repository::repository::add_repository_user(&state.db, id, user.id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Sets whether the user the repository is shared with commits the changes proposed to them,
/// like the owner, if the repository allows commits. Only for its owner and admins.
pub(crate) async fn update_repository_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((id, user_id)): PathParam<(Uuid, Uuid)>,
    JsonBody(payload): JsonBody<UpdateRepositoryUserRequest>,
) -> Result<StatusCode, AppError> {
    find_managed_repository_owner(&state, &auth, id).await?;
    if !repository::repository::set_repository_user_can_commit(
        &state.db,
        id,
        user_id,
        payload.can_commit,
    )
    .await?
    {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Stops sharing the repository with the user and removes it from their chats.
/// Allowed for its owner and admins, and for the user themselves to leave it. Removing a
/// user it is not shared with also succeeds, so the request is safe to retry.
pub(crate) async fn remove_repository_user(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((id, user_id)): PathParam<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    if user_id != auth.user_id {
        find_managed_repository_owner(&state, &auth, id).await?;
    }
    repository::repository::remove_repository_user(&state.db, id, user_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Repositories of other users are reported as missing, never as forbidden, unless they
/// are shared with the user.
async fn find_repository(
    state: &AppState,
    user_id: Uuid,
    id: Uuid,
) -> Result<Repository, AppError> {
    repository::repository::get_repository(&state.db, user_id, id)
        .await?
        .ok_or(AppError::NotFound)
}

/// Like [`find_repository`], but forbidden if the repository is only shared with the user.
async fn find_owned_repository(
    state: &AppState,
    user_id: Uuid,
    id: Uuid,
) -> Result<Repository, AppError> {
    let repository = find_repository(state, user_id, id).await?;
    if repository.user_id != user_id {
        return Err(not_owner());
    }
    Ok(repository)
}

/// The owner of a repository whose sharing the user may manage: their own, or any if
/// they are an admin.
async fn find_managed_repository_owner(
    state: &AppState,
    auth: &AuthenticatedUser,
    id: Uuid,
) -> Result<Uuid, AppError> {
    require_repository_management(auth)?;
    match auth.role {
        UserRole::Admin => repository::repository::get_repository_owner(&state.db, id)
            .await?
            .ok_or(AppError::NotFound),
        UserRole::User => Ok(find_owned_repository(state, auth.user_id, id)
            .await?
            .user_id),
    }
}

fn not_owner() -> AppError {
    AppError::Forbidden("Only the owner can manage the repository".to_string())
}

/// Users without the permission keep reading repositories shared with them, and may
/// leave them, but cannot create or manage any, not even their own.
fn require_repository_management(auth: &AuthenticatedUser) -> Result<(), AppError> {
    if !auth.can_manage_repositories {
        return Err(AppError::Forbidden(
            "You are not allowed to manage repositories".to_string(),
        ));
    }
    Ok(())
}

/// For guarded updates that matched no row: either the repository is gone,
/// or its URL was changed by a concurrent request.
async fn not_found_or_conflict(state: &AppState, user_id: Uuid, id: Uuid) -> AppError {
    match repository::repository::get_repository(&state.db, user_id, id).await {
        Ok(Some(_)) => AppError::Conflict(
            ErrorCode::Conflict,
            "The repository was changed by another request, please retry".to_string(),
        ),
        Ok(None) => AppError::NotFound,
        Err(e) => e,
    }
}

fn parse_name(name: &str) -> Result<&str, ValidationError> {
    let name = name.trim();
    util::validation::validate_name(name)?;
    Ok(name)
}

/// Blank descriptions are stored as `NULL`.
fn parse_description(description: Option<&str>) -> Result<Option<&str>, ValidationError> {
    let description = description.map(str::trim).filter(|d| !d.is_empty());
    if let Some(description) = description {
        util::validation::validate_description(description)?;
    }
    Ok(description)
}

fn parse_branch(branch: &str) -> Result<&str, ValidationError> {
    let branch = branch.trim();
    util::validation::validate_branch(branch)?;
    Ok(branch)
}

fn parse_token(token: &str) -> Result<&str, ValidationError> {
    let token = token.trim();
    util::validation::validate_token(token)?;
    Ok(token)
}
