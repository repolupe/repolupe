//! Committing the changes the model proposed with [`CHANGE_FILE`], [`MOVE_FILES`] or
//! [`SAVE_ATTACHMENT`]: only the user pushes them to the branch of the repository, after seeing
//! the diff, or the answer once it is complete if the user turned on `auto_commit`, never the
//! model.
//!
//! [`CHANGE_FILE`]: crate::service::tools::CHANGE_FILE
//! [`MOVE_FILES`]: crate::service::tools::MOVE_FILES
//! [`SAVE_ATTACHMENT`]: crate::service::tools::SAVE_ATTACHMENT

use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::chat::ProposedCommitStatus;
use crate::dto::error::ErrorCode;
use crate::model::remote_access::RemoteAccess;
use crate::model::repository::{Remote, Repository};
use crate::model::tool_call::{ChangedPaths, ProposedCommit};
use crate::repository;
use crate::repository::message::CommitOutcome;
use crate::service::mirror::Push;
use uuid::Uuid;

/// Whether the user may commit the changes proposed for `repository`, read for them: commits are
/// allowed on it, they own it or the owner lets them commit, and they may manage repositories,
/// like the model needs to propose them.
pub(crate) fn can_commit(can_manage_repositories: bool, repository: &Repository) -> bool {
    repository.viewer_can_commit && can_manage_repositories
}

/// Pushes the change the call `tool_call_id` proposed to the branch of its repository (moves the
/// branch of a local one), and returns how that went. A change committed already is returned as it is. If the branch moved,
/// the change is made again on top of it, unless the paths it changes changed there too, which
/// is a `CONFLICT`. Failures the user can act on are stored as `FAILED`, others returned.
pub(crate) async fn commit(
    state: &AppState,
    user_id: Uuid,
    can_manage_repositories: bool,
    chat_id: Uuid,
    tool_call_id: Uuid,
) -> Result<ProposedCommit, AppError> {
    let tool_call = repository::message::get_tool_call(&state.db, user_id, chat_id, tool_call_id)
        .await?
        .ok_or(AppError::NotFound)?;
    let repository_id = tool_call.repository_id.ok_or(AppError::NotFound)?;
    let change = repository::message::get_proposed_commit(&state.db, tool_call.id)
        .await?
        .ok_or(AppError::NotFound)?;
    if change.status == ProposedCommitStatus::Committed {
        return Ok(change);
    }
    let repository = repository::repository::get_repository(&state.db, user_id, repository_id)
        .await?
        .ok_or(AppError::NotFound)?;
    if !can_commit(can_manage_repositories, &repository) {
        return Err(AppError::Forbidden(
            "Only the owner and the users they let commit can commit to the repository, if it allows the assistant to propose changes".to_string(),
        ));
    }

    let paths = change.changed.paths();
    let push = match repository.remote() {
        Some(remote) => push(state, &repository, &remote, &change.proposed_commit, &paths).await,
        // The mirror is all there is of a local repository.
        None => {
            state
                .mirrors
                .commit_local(
                    repository.id,
                    &repository.branch,
                    &change.proposed_commit,
                    &paths,
                )
                .await
        }
    };

    let push = match push {
        Ok(push) => Ok(push),
        // Messages meant for the user, like the ones of a failed sync.
        Err(
            AppError::BadRequest(message)
            | AppError::BadGateway(_, message)
            | AppError::Unprocessable(
                ErrorCode::AuthFailed
                | ErrorCode::RepoNotFound
                | ErrorCode::BranchNotFound
                | ErrorCode::RemoteUnreachable,
                message,
            ),
        ) => Err(message),
        Err(e) => return Err(e),
    };
    let message;
    let outcome = match &push {
        Ok(Push::Pushed { commit }) => CommitOutcome::Committed {
            commit,
            branch: &repository.branch,
        },
        Ok(Push::Conflict) => {
            message = match &change.changed {
                ChangedPaths::File(path) => format!(
                    "`{path}` was changed on {} since the change was proposed. Ask for the change again, so it is based on the current version.",
                    repository.branch
                ),
                ChangedPaths::Moves(_) => format!(
                    "Files to move were changed on {}, or their new paths taken, since the moves were proposed. Ask for the moves again, so they are based on the current version.",
                    repository.branch
                ),
            };
            CommitOutcome::Conflict(&message)
        }
        Ok(Push::Rejected(reason)) => {
            message = format!("The remote rejected the commit: {reason}");
            CommitOutcome::Failed(&message)
        }
        Err(message) => CommitOutcome::Failed(message),
    };
    let committed = matches!(outcome, CommitOutcome::Committed { .. });
    let change = repository::message::finish_commit(&state.db, tool_call.id, outcome)
        .await?
        .ok_or(AppError::NotFound)?;
    if committed {
        // So the chats see the commit soon.
        repository::repository::request_sync(&state.db, repository.user_id, repository.id).await?;
    }
    Ok(change)
}

/// Pushes `commit`, which changes `paths`, to the branch of `repository` at `remote`, see
/// [`MirrorStore::push_file_commit`](crate::service::mirror::MirrorStore::push_file_commit).
async fn push(
    state: &AppState,
    repository: &Repository,
    remote: &Remote<'_>,
    commit: &str,
    paths: &[String],
) -> Result<Push, AppError> {
    let url = remote.parsed_url()?;
    let token = remote.token(&state.token_cipher)?;
    // The owner's, like for the syncs, since the remote and token are theirs.
    let owner_role = repository::repository::get_repository_owner_role(&state.db, repository.id)
        .await?
        .ok_or(AppError::NotFound)?;
    state
        .mirrors
        .push_file_commit(
            repository.id,
            &url,
            &repository.branch,
            token.as_deref(),
            RemoteAccess::of(owner_role),
            commit,
            paths,
        )
        .await
}
