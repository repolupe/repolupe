use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::chat::MessageStatus;
use crate::dto::chat::{
    ChatDetailDto, ChatDto, ChatPageDto, ContentDeltaDto, CreateChatRequest, FileDiffDto,
    ListChatsQuery, MessageDto, ProposedCommitDto, RetryMessageRequest, SendMessageRequest,
    ToolCallDto, ToolCallFinishedDto, ToolCallStatus, ToolCallSummaryDto, UpdateChatRequest,
};
use crate::dto::error::ErrorCode;
use crate::middleware::auth::AuthenticatedUser;
use crate::model::attachment::Attachment;
use crate::model::chat::Chat;
use crate::model::message::Message;
use crate::model::tool_call::{ChangedPaths, ProposedCommit, ToolCallSummary};
use crate::repository::chat::{
    ChatChanges, ChatCursor, Exchange, NewChat, NewExchange, RepositoryScope, RetryOutcome,
};
use crate::service::generation::{ClientContext, GenerationEvent, Subscription};
use crate::service::llm_config::AnsweringModel;
use crate::service::mirror::Snapshot;
use crate::util::extract::{JsonBody, PathParam, QueryParams};
use crate::util::validation::ValidationError;
use crate::{repository, service, util};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Json};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use chrono::{DateTime, SecondsFormat, Utc};
use futures_util::{Stream, StreamExt, stream};
use std::collections::HashMap;
use uuid::Uuid;

const DEFAULT_PAGE_SIZE: i64 = 50;
const MAX_PAGE_SIZE: i64 = 100;

/// Titles derived from the first message are cut to this many characters.
const DERIVED_TITLE_LENGTH: usize = 80;
const FALLBACK_TITLE: &str = "New chat";

pub(crate) async fn list_chats(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    QueryParams(query): QueryParams<ListChatsQuery>,
) -> Result<Json<ChatPageDto>, AppError> {
    let limit = query.limit.unwrap_or(DEFAULT_PAGE_SIZE);
    if !(1..=MAX_PAGE_SIZE).contains(&limit) {
        return Err(
            ValidationError(format!("`limit` must be between 1 and {MAX_PAGE_SIZE}")).into(),
        );
    }
    let after = query.cursor.as_deref().map(decode_cursor).transpose()?;

    // One extra row tells whether there is a next page.
    let mut chats =
        repository::chat::list_chats(&state.db, auth.user_id, after.as_ref(), limit + 1).await?;
    let next_cursor = if chats.len() as i64 > limit {
        chats.truncate(limit as usize);
        chats.last().map(encode_cursor)
    } else {
        None
    };

    Ok(Json(ChatPageDto {
        items: chats.into_iter().map(Into::into).collect(),
        next_cursor,
    }))
}

pub(crate) async fn get_chat(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Json<ChatDetailDto>, AppError> {
    let chat = repository::chat::get_chat(&state.db, auth.user_id, id)
        .await?
        .ok_or(AppError::NotFound)?;
    let messages = repository::message::list_messages(&state.db, id).await?;
    let tool_calls = repository::message::list_tool_call_summaries(&state.db, id).await?;
    let mut attachments: HashMap<Uuid, Attachment> =
        repository::attachment::list_chat_attachments(&state.db, id)
            .await?
            .into_iter()
            .filter_map(|attachment| Some((attachment.message_id?, attachment)))
            .collect();

    let mut tool_calls_by_message: HashMap<Uuid, Vec<ToolCallSummary>> = HashMap::new();
    for tool_call in tool_calls {
        tool_calls_by_message
            .entry(tool_call.message_id)
            .or_default()
            .push(tool_call);
    }
    let messages = messages
        .into_iter()
        .map(|message| {
            let tool_calls = tool_calls_by_message
                .remove(&message.id)
                .unwrap_or_default();
            let attachment = attachments.remove(&message.id);
            MessageDto::new(message, tool_calls).with_attachment(attachment)
        })
        .collect();

    Ok(Json(ChatDetailDto {
        chat: chat.into(),
        messages,
    }))
}

/// Creates the chat with its first message and starts generating the answer.
pub(crate) async fn create_chat(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    headers: HeaderMap,
    JsonBody(payload): JsonBody<CreateChatRequest>,
) -> Result<(StatusCode, Json<ChatDetailDto>), AppError> {
    validate_content(&payload.content, payload.attachment_id)?;
    let title = match payload.title.as_deref().map(str::trim) {
        Some(title) if !title.is_empty() => title.to_string(),
        _ if payload.content.trim().is_empty() => {
            attachment_title(&state, auth.user_id, payload.attachment_id).await?
        }
        _ => derive_title(&payload.content),
    };
    util::validation::validate_chat_title(&title)?;
    let scope = parse_scope(
        payload.all_repositories,
        payload.repository_ids.unwrap_or_default(),
    )?;

    let model = service::llm_config::resolve(&state, auth.user_id, payload.model_id).await?;

    let id = Uuid::now_v7();
    let user_message_id = Uuid::now_v7();
    let assistant_message_id = Uuid::now_v7();
    let now = Utc::now();

    let generation = state.generations.reserve(
        auth.user_id,
        id,
        assistant_message_id,
        &model,
        client_context(&headers, payload.utc_offset_minutes)?,
        now,
    )?;
    let created = repository::chat::create_chat(
        &state.db,
        NewChat {
            id,
            user_id: auth.user_id,
            title: &title,
            scope: &scope,
            model_id: payload.model_id,
            temporary: payload.temporary,
            content: &payload.content,
            attachment_id: payload.attachment_id,
            user_message_id,
            assistant_message_id,
            answer_model_id: model.id,
            created_at: now,
        },
    )
    .await;
    let (chat, exchange) = match created {
        Ok(created) => created,
        Err(e) => {
            state.generations.release(assistant_message_id);
            return Err(e);
        }
    };
    service::generation::spawn(state.clone(), generation, model.config);

    Ok((
        StatusCode::CREATED,
        Json(ChatDetailDto {
            chat: chat.into(),
            messages: exchange_dtos(exchange),
        }),
    ))
}

pub(crate) async fn update_chat(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
    JsonBody(payload): JsonBody<UpdateChatRequest>,
) -> Result<Json<ChatDto>, AppError> {
    let title = parse_title(&payload.title)?;

    let chat = repository::chat::update_chat(
        &state.db,
        auth.user_id,
        id,
        ChatChanges {
            title,
            model_id: payload.model_id,
        },
    )
    .await?
    .ok_or(AppError::NotFound)?;
    Ok(Json(chat.into()))
}

/// Deleting a missing chat also succeeds, so the request is safe to retry.
pub(crate) async fn delete_chat(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<StatusCode, AppError> {
    // Generations are looked up by chat id alone, so only the owner may stop them.
    if repository::chat::delete_chat(&state.db, auth.user_id, id).await? {
        service::generation::stop_chat(&state, id).await;
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Returns the user's message and the `GENERATING` answer.
pub(crate) async fn send_message(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(chat_id): PathParam<Uuid>,
    headers: HeaderMap,
    JsonBody(payload): JsonBody<SendMessageRequest>,
) -> Result<(StatusCode, Json<Vec<MessageDto>>), AppError> {
    validate_content(&payload.content, payload.attachment_id)?;
    let model = chat_model(&state, auth.user_id, chat_id).await?;

    let user_message_id = Uuid::now_v7();
    let assistant_message_id = Uuid::now_v7();
    let now = Utc::now();

    let generation = state.generations.reserve(
        auth.user_id,
        chat_id,
        assistant_message_id,
        &model,
        client_context(&headers, payload.utc_offset_minutes)?,
        now,
    )?;
    let added = repository::chat::add_exchange(
        &state.db,
        auth.user_id,
        chat_id,
        NewExchange {
            content: &payload.content,
            attachment_id: payload.attachment_id,
            user_message_id,
            assistant_message_id,
            model_id: model.id,
            created_at: now,
        },
    )
    .await;
    let exchange = match added {
        Ok(Some(exchange)) => exchange,
        Ok(None) => {
            state.generations.release(assistant_message_id);
            return Err(AppError::NotFound);
        }
        Err(e) => {
            state.generations.release(assistant_message_id);
            return Err(e);
        }
    };
    service::generation::spawn(state.clone(), generation, model.config);

    Ok((StatusCode::CREATED, Json(exchange_dtos(exchange))))
}

/// Server-sent events of a message: `snapshot` with the state so far, then `content_delta`,
/// `tool_call_started` and `tool_call_finished` while generating, and finally `done`. The
/// content while generating includes the preambles to tool calls, which `done` leaves out.
/// A finished message gets `snapshot` and `done` right away.
pub(crate) async fn stream_message(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, message_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Sse<impl Stream<Item = Result<Event, axum::Error>>>, AppError> {
    let message = repository::message::get_message(&state.db, auth.user_id, chat_id, message_id)
        .await?
        .ok_or(AppError::NotFound)?;

    let generation = match message.status {
        MessageStatus::Generating => state.generations.get(message_id),
        _ => None,
    };
    let subscription = match generation {
        Some(generation) => generation.subscribe(),
        None => {
            // Re-read, since the message may have finished after it was read above.
            let message = match message.status {
                MessageStatus::Generating => {
                    repository::message::get_message(&state.db, auth.user_id, chat_id, message_id)
                        .await?
                        .ok_or(AppError::NotFound)?
                }
                _ => message,
            };
            let tool_calls =
                repository::message::list_tool_call_summaries_of_message(&state.db, message_id)
                    .await?;
            Subscription::Done {
                message,
                tool_calls,
            }
        }
    };

    let (initial, events) = match subscription {
        Subscription::Live {
            message,
            tool_calls,
            events,
        } => (
            vec![message_event("snapshot", message, tool_calls)],
            Some(events),
        ),
        Subscription::Done {
            message,
            tool_calls,
        } => (
            vec![
                message_event("snapshot", message.clone(), tool_calls.clone()),
                message_event("done", message, tool_calls),
            ],
            None,
        ),
    };

    let live = stream::unfold(events, |events| async move {
        let mut events = events?;
        let event = match events.recv().await {
            Ok(GenerationEvent::Done {
                message,
                tool_calls,
            }) => return Some((message_event("done", message, tool_calls), None)),
            Ok(event) => generation_event(event),
            // A client that fell behind reconnects and starts from a fresh snapshot.
            Err(_) => return None,
        };
        Some((event, Some(events)))
    });

    Ok(Sse::new(stream::iter(initial).chain(live)).keep_alive(KeepAlive::default()))
}

/// Keeps the partial content. Cancelling a finished message does nothing.
pub(crate) async fn cancel_message(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, message_id)): PathParam<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let message = repository::message::get_message(&state.db, auth.user_id, chat_id, message_id)
        .await?
        .ok_or(AppError::NotFound)?;
    if message.status == MessageStatus::Generating {
        service::generation::cancel(&state, message_id).await?;
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Replaces the failed or cancelled last answer with a new one.
pub(crate) async fn retry_message(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, message_id)): PathParam<(Uuid, Uuid)>,
    headers: HeaderMap,
    JsonBody(payload): JsonBody<RetryMessageRequest>,
) -> Result<(StatusCode, Json<MessageDto>), AppError> {
    let model = chat_model(&state, auth.user_id, chat_id).await?;

    let new_message_id = Uuid::now_v7();
    let now = Utc::now();

    let generation = state.generations.reserve(
        auth.user_id,
        chat_id,
        new_message_id,
        &model,
        client_context(&headers, payload.utc_offset_minutes)?,
        now,
    )?;
    let outcome = repository::chat::retry_message(
        &state.db,
        auth.user_id,
        chat_id,
        message_id,
        new_message_id,
        model.id,
        now,
    )
    .await;
    let message = match outcome {
        Ok(RetryOutcome::Retried(message)) => *message,
        Ok(RetryOutcome::ChatNotFound | RetryOutcome::MessageNotFound) => {
            state.generations.release(new_message_id);
            return Err(AppError::NotFound);
        }
        Err(e) => {
            state.generations.release(new_message_id);
            return Err(e);
        }
    };
    service::generation::spawn(state.clone(), generation, model.config);

    Ok((StatusCode::CREATED, Json(MessageDto::new(message, vec![]))))
}

fn client_context(
    headers: &HeaderMap,
    utc_offset_minutes: Option<i32>,
) -> Result<ClientContext, AppError> {
    Ok(ClientContext {
        locale: util::http::preferred_locale(headers),
        utc_offset: utc_offset_minutes
            .map(util::validation::parse_utc_offset)
            .transpose()?,
    })
}

pub(crate) async fn get_tool_call(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Json<ToolCallDto>, AppError> {
    let tool_call =
        repository::message::get_tool_call(&state.db, auth.user_id, chat_id, tool_call_id)
            .await?
            .ok_or(AppError::NotFound)?;
    Ok(Json(tool_call.into()))
}

/// The file of a successful `present_file_to_user` call as it is in the repository (documents
/// like PDFs are the original files), at the commit the answer read. Like the chat itself, it is
/// only available while the user can still read the repository.
pub(crate) async fn get_presented_file(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    let tool_call =
        repository::message::get_tool_call(&state.db, auth.user_id, chat_id, tool_call_id)
            .await?
            .ok_or(AppError::NotFound)?;
    let (Some(repository_id), Some(commit_sha), Some(path)) = (
        tool_call.repository_id,
        tool_call.commit_sha,
        tool_call.input.get("path").and_then(|p| p.as_str()),
    ) else {
        return Err(AppError::NotFound);
    };
    if tool_call.name != service::tools::PRESENT_FILE
        || tool_call.output.is_none()
        || tool_call.is_error
    {
        return Err(AppError::NotFound);
    }
    let repository = repository::repository::get_repository(&state.db, auth.user_id, repository_id)
        .await?
        .ok_or(AppError::NotFound)?;
    let tool_repository = service::tools::ToolRepository {
        id: repository.id,
        name: repository.name,
        snapshot: state.mirrors.snapshot(repository.id, commit_sha),
        can_commit: false,
    };
    let file = service::tools::read_presented_file(&tool_repository, &state.db, path).await?;
    Ok(file_response(file))
}

/// The file a successful `change_file` or `save_attachment` call proposed, as it is in the
/// proposed commit, like [`get_presented_file`]. `FILE_UNAVAILABLE` if the change deletes it,
/// `NOT_FOUND` for the moves of `move_files`.
pub(crate) async fn get_proposed_commit_file(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    let tool_call =
        repository::message::get_tool_call(&state.db, auth.user_id, chat_id, tool_call_id)
            .await?
            .ok_or(AppError::NotFound)?;
    let repository_id = tool_call.repository_id.ok_or(AppError::NotFound)?;
    let change = repository::message::get_proposed_commit(&state.db, tool_call.id)
        .await?
        .ok_or(AppError::NotFound)?;
    let ChangedPaths::File(path) = change.changed else {
        return Err(AppError::NotFound);
    };
    let repository = repository::repository::get_repository(&state.db, auth.user_id, repository_id)
        .await?
        .ok_or(AppError::NotFound)?;
    let tool_repository = service::tools::ToolRepository {
        id: repository.id,
        name: repository.name,
        snapshot: state
            .mirrors
            .snapshot(repository.id, change.proposed_commit),
        can_commit: false,
    };
    let file = service::tools::read_presented_file(&tool_repository, &state.db, &path).await?;
    Ok(file_response(file))
}

fn file_response(file: service::tools::PresentedFile) -> Response {
    let headers = [
        (header::CONTENT_TYPE, file.content_type),
        // The content comes from the repository, so the browser must not guess a type that
        // runs scripts, e.g. HTML.
        (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
    ];
    (headers, file.content).into_response()
}

/// The commit a successful `change_file`, `save_attachment` or `move_files` call proposed, as a
/// patch that `git am` applies. Like
/// the chat itself, it is only available while the user can still read the repository.
pub(crate) async fn get_proposed_commit_patch(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Response, AppError> {
    let (repository, proposed, change) =
        proposed_change(&state, &auth, chat_id, tool_call_id).await?;
    let patch =
        service::tools::read_proposed_commit_patch(&repository, &proposed, &change.changed).await?;
    let headers = [
        (header::CONTENT_TYPE, "text/x-patch; charset=utf-8"),
        (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
    ];
    Ok((headers, patch).into_response())
}

/// The commit a successful `change_file`, `save_attachment` or `move_files` call proposed, as
/// the clients show it: the diff of the patch with the changed words marked, or the moves. Like
/// the patch, it is only available while the user can still read the repository.
pub(crate) async fn get_proposed_commit_diff(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Json<FileDiffDto>, AppError> {
    let (repository, proposed, change) =
        proposed_change(&state, &auth, chat_id, tool_call_id).await?;
    let diff =
        service::tools::read_proposed_commit_diff(&repository, &proposed, &change.changed).await?;
    Ok(Json(diff))
}

/// The repository at the commit a tool call read, the commit it proposed, and its change.
async fn proposed_change(
    state: &AppState,
    auth: &AuthenticatedUser,
    chat_id: Uuid,
    tool_call_id: Uuid,
) -> Result<(service::tools::ToolRepository, Snapshot, ProposedCommit), AppError> {
    let tool_call =
        repository::message::get_tool_call(&state.db, auth.user_id, chat_id, tool_call_id)
            .await?
            .ok_or(AppError::NotFound)?;
    let (Some(repository_id), Some(commit_sha)) = (tool_call.repository_id, tool_call.commit_sha)
    else {
        return Err(AppError::NotFound);
    };
    let change = repository::message::get_proposed_commit(&state.db, tool_call.id)
        .await?
        .ok_or(AppError::NotFound)?;
    let repository = repository::repository::get_repository(&state.db, auth.user_id, repository_id)
        .await?
        .ok_or(AppError::NotFound)?;
    let tool_repository = service::tools::ToolRepository {
        id: repository.id,
        name: repository.name,
        snapshot: state.mirrors.snapshot(repository.id, commit_sha),
        can_commit: false,
    };
    let proposed = state
        .mirrors
        .snapshot(repository.id, change.proposed_commit.clone());
    Ok((tool_repository, proposed, change))
}

/// The change a successful `change_file`, `save_attachment` or `move_files` call proposed, and
/// whether it was committed. Like the patch, it is only available while the user can still read
/// the repository.
pub(crate) async fn get_proposed_commit(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Json<ProposedCommitDto>, AppError> {
    let tool_call =
        repository::message::get_tool_call(&state.db, auth.user_id, chat_id, tool_call_id)
            .await?
            .ok_or(AppError::NotFound)?;
    let repository_id = tool_call.repository_id.ok_or(AppError::NotFound)?;
    let change = repository::message::get_proposed_commit(&state.db, tool_call.id)
        .await?
        .ok_or(AppError::NotFound)?;
    let repository = repository::repository::get_repository(&state.db, auth.user_id, repository_id)
        .await?
        .ok_or(AppError::NotFound)?;
    let can_commit = service::commit::can_commit(auth.can_manage_repositories, &repository);
    Ok(Json(ProposedCommitDto::new(change, can_commit)))
}

/// Pushes the change a successful `change_file`, `save_attachment` or `move_files` call proposed
/// to the branch of the repository. Returns the change with how it went: `COMMITTED`, `CONFLICT`
/// if the paths it changes changed on the branch, or `FAILED`, e.g. if the remote refused it. A
/// committed change stays committed.
pub(crate) async fn commit_proposed_commit(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam((chat_id, tool_call_id)): PathParam<(Uuid, Uuid)>,
) -> Result<Json<ProposedCommitDto>, AppError> {
    let change = service::commit::commit(
        &state,
        auth.user_id,
        auth.can_manage_repositories,
        chat_id,
        tool_call_id,
    )
    .await?;
    Ok(Json(ProposedCommitDto::new(change, true)))
}

/// The user's message with its attachment, and the `GENERATING` answer.
fn exchange_dtos(exchange: Exchange) -> Vec<MessageDto> {
    vec![
        MessageDto::new(exchange.user_message, vec![]).with_attachment(exchange.attachment),
        MessageDto::new(exchange.assistant_message, vec![]),
    ]
}

/// A message needs text, unless it sends an attachment.
fn validate_content(content: &str, attachment_id: Option<Uuid>) -> Result<(), ValidationError> {
    if attachment_id.is_some() && content.trim().is_empty() {
        return Ok(());
    }
    util::validation::validate_message(content)
}

/// The title of a chat that starts with only an attachment: its file name.
async fn attachment_title(
    state: &AppState,
    user_id: Uuid,
    attachment_id: Option<Uuid>,
) -> Result<String, AppError> {
    let unknown = || {
        AppError::Unprocessable(
            ErrorCode::UnknownAttachment,
            "The attachment does not exist or was sent already".to_string(),
        )
    };
    let id = attachment_id.ok_or_else(unknown)?;
    let attachment = repository::attachment::get_attachment(&state.db, user_id, id)
        .await?
        .ok_or_else(unknown)?;
    Ok(derive_title(&attachment.file_name))
}

/// The model that writes the next answer in the chat.
async fn chat_model(
    state: &AppState,
    user_id: Uuid,
    chat_id: Uuid,
) -> Result<AnsweringModel, AppError> {
    let chat = repository::chat::get_chat(&state.db, user_id, chat_id)
        .await?
        .ok_or(AppError::NotFound)?;
    service::llm_config::resolve(state, user_id, chat.model_id).await
}

fn message_event(
    name: &str,
    message: Message,
    tool_calls: Vec<ToolCallSummary>,
) -> Result<Event, axum::Error> {
    Event::default()
        .event(name)
        .json_data(MessageDto::new(message, tool_calls))
}

fn generation_event(event: GenerationEvent) -> Result<Event, axum::Error> {
    match event {
        GenerationEvent::ContentDelta(text) => Event::default()
            .event("content_delta")
            .json_data(ContentDeltaDto { text }),
        GenerationEvent::ToolCallStarted(tool_call) => Event::default()
            .event("tool_call_started")
            .json_data(ToolCallSummaryDto::from(tool_call)),
        GenerationEvent::ToolCallFinished { id, is_error } => Event::default()
            .event("tool_call_finished")
            .json_data(ToolCallFinishedDto {
                id,
                status: ToolCallStatus::new(true, is_error),
            }),
        GenerationEvent::Done {
            message,
            tool_calls,
        } => message_event("done", message, tool_calls),
    }
}

fn parse_title(title: &str) -> Result<&str, ValidationError> {
    let title = title.trim();
    util::validation::validate_chat_title(title)?;
    Ok(title)
}

fn parse_scope(
    all_repositories: bool,
    mut repository_ids: Vec<Uuid>,
) -> Result<RepositoryScope, ValidationError> {
    if all_repositories {
        if !repository_ids.is_empty() {
            return Err(ValidationError(
                "`repository_ids` must be empty if `all_repositories` is true".to_string(),
            ));
        }
        return Ok(RepositoryScope::All);
    }
    repository_ids.sort();
    repository_ids.dedup();
    util::validation::validate_repository_selection(&repository_ids)?;
    Ok(RepositoryScope::Selected(repository_ids))
}

/// The first words of the message on one line.
fn derive_title(content: &str) -> String {
    let mut title = String::new();
    let mut length = 0;
    for word in content.split_whitespace() {
        let word: String = word.chars().filter(|c| !c.is_control()).collect();
        let word_length = word.chars().count();
        if word_length == 0 {
            continue;
        }
        let separator = usize::from(!title.is_empty());
        if length + separator + word_length > DERIVED_TITLE_LENGTH {
            if title.is_empty() {
                title.extend(word.chars().take(DERIVED_TITLE_LENGTH));
            }
            title.push('…');
            break;
        }
        if separator == 1 {
            title.push(' ');
        }
        title.push_str(&word);
        length += separator + word_length;
    }
    if title.is_empty() {
        FALLBACK_TITLE.to_string()
    } else {
        title
    }
}

/// With nanoseconds, the stored precision, so the cursor is exact.
fn encode_cursor(chat: &Chat) -> String {
    URL_SAFE_NO_PAD.encode(format!(
        "{}_{}",
        chat.updated_at.to_rfc3339_opts(SecondsFormat::Nanos, true),
        chat.id
    ))
}

fn decode_cursor(cursor: &str) -> Result<ChatCursor, ValidationError> {
    let invalid = || ValidationError("Invalid cursor".to_string());
    let decoded = URL_SAFE_NO_PAD.decode(cursor).map_err(|_| invalid())?;
    let decoded = String::from_utf8(decoded).map_err(|_| invalid())?;
    let (updated_at, id) = decoded.split_once('_').ok_or_else(invalid)?;
    let updated_at = DateTime::parse_from_rfc3339(updated_at).map_err(|_| invalid())?;
    Ok(ChatCursor {
        updated_at: updated_at.to_utc(),
        id: Uuid::parse_str(id).map_err(|_| invalid())?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::types::Json;

    #[test]
    fn derives_title_from_first_words() {
        assert_eq!(
            derive_title("  How does\n\tsync work?  "),
            "How does sync work?"
        );

        let long = "word ".repeat(30);
        let title = derive_title(&long);
        assert!(title.ends_with("word…"), "{title}");
        assert!(title.chars().count() <= DERIVED_TITLE_LENGTH + 1);

        let single = "x".repeat(100);
        assert_eq!(
            derive_title(&single),
            format!("{}…", "x".repeat(DERIVED_TITLE_LENGTH))
        );

        assert_eq!(derive_title("\u{0}\u{1}"), FALLBACK_TITLE);
    }

    #[test]
    fn cursor_round_trips() {
        let chat = Chat {
            id: Uuid::now_v7(),
            title: String::new(),
            all_repositories: true,
            repository_ids: Json(vec![]),
            model_id: None,
            temporary: false,
            created_at: Utc::now(),
            updated_at: DateTime::from_timestamp_nanos(1_760_000_000_123_456_789),
        };
        let cursor = decode_cursor(&encode_cursor(&chat)).unwrap();
        assert_eq!(cursor.updated_at, chat.updated_at);
        assert_eq!(cursor.id, chat.id);

        assert!(decode_cursor("not a cursor").is_err());
        assert!(decode_cursor(&URL_SAFE_NO_PAD.encode("1_x")).is_err());
    }

    #[test]
    fn parses_scope() {
        let a = Uuid::now_v7();
        let b = Uuid::now_v7();
        assert!(matches!(
            parse_scope(true, vec![]),
            Ok(RepositoryScope::All)
        ));
        assert!(parse_scope(true, vec![a]).is_err());
        assert!(matches!(
            parse_scope(false, vec![]),
            Ok(RepositoryScope::Selected(ids)) if ids.is_empty()
        ));
        match parse_scope(false, vec![b, a, b]) {
            Ok(RepositoryScope::Selected(ids)) => assert_eq!(ids, vec![a, b]),
            _ => panic!("expected a selection"),
        }
    }
}
