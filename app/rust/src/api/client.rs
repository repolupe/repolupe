//! The typed client of the Repolupe API (`/api/v1`), one per account.
//!
//! Every method is a thin wrapper over [`Transport::request`]: it builds the path, sends the
//! request DTO as JSON (or the raw bytes of an upload) with the session token as
//! `Authorization: Bearer`, and parses the response DTO. So a server and a local instance behave
//! the same, and errors are always a [`ClientError`]. The message stream of an answer
//! (`GET .../messages/{id}/stream`) goes through [`Transport::request_stream`] instead, see
//! [`Client::stream_message`].

use std::collections::HashMap;
use std::sync::RwLock;

use axum::http::header::{
    ACCEPT, ACCEPT_LANGUAGE, AUTHORIZATION, CONTENT_DISPOSITION, CONTENT_TYPE,
};
use axum::http::{HeaderMap, HeaderValue, Method};
use bytes::Bytes;
use flutter_rust_bridge::frb;
use repolupe::dto::attachment::{AttachmentDto, UploadAttachmentQuery};
use repolupe::dto::auth::{LoginRequest, LoginResponse};
use repolupe::dto::chat::{
    ChatDetailDto, ChatDto, ChatPageDto, CreateChatRequest, FileDiffDto, ListChatsQuery,
    MessageDto, ProposedCommitDto, SendMessageRequest, ToolCallDto, UpdateChatRequest,
};
use repolupe::dto::config::ConfigEntryDto;
use repolupe::dto::extraction::{
    DocumentFilter, ExtractionDocumentPageDto, ExtractionOverviewDto, ListExtractionDocumentsQuery,
    RepositoryDocumentsDto, RetryDocumentRequest,
};
use repolupe::dto::instance::InstanceDto;
use repolupe::dto::llm::{
    CreateLlmProviderRequest, LlmModelDto, LlmModelRequest, LlmProviderDto, ModelDto,
    RemoteModelDto, SetDefaultModelRequest, UpdateLlmProviderRequest,
};
use repolupe::dto::repository::{
    AddRepositoryUserRequest, CreateRepositoryRequest, RepositoryDto, RepositoryUserDto,
    UpdateRepositoryRequest, UpdateRepositoryUserRequest,
};
use repolupe::dto::server::ServerDto;
use repolupe::dto::user::{
    ChangePasswordRequest, DeleteUserRequest, RegisterRequest, ResetPasswordRequest,
    SetAutoCommitRequest, SetLocaleRequest, SetMyDefaultModelRequest, UpdateIdentityRequest,
    UpdateProfileRequest, UpdateUserRequest, UserDto,
};
use serde::Serialize;
use serde::de::DeserializeOwned;
use uuid::Uuid;

use crate::api::error::ClientError;
use crate::api::local::LocalHandle;
use crate::api::stream::{CancellationToken, MessageEvent};
use crate::frb_generated::StreamSink;
use crate::message_stream::{MessageEvents, forward};
use crate::runtime;
use crate::transport::{Response, Transport};

const JSON: &str = "application/json";
const OCTET_STREAM: &str = "application/octet-stream";

/// A client for one account on a server or a local instance. Requests may run concurrently.
///
/// Created without a session token, only [`Client::instance`] and [`Client::login`] work;
/// `login` stores the token it gets, which the caller keeps (e.g. in secure storage) to create
/// the client with it next time.
#[frb(opaque)]
pub struct Client {
    transport: Transport,
    token: RwLock<Option<String>>,
    accept_language: RwLock<Option<String>>,
}

/// A file as the API returns it.
pub struct FileDownload {
    pub content: Vec<u8>,
    /// The `Content-Type` header, e.g. `application/pdf`.
    pub content_type: Option<String>,
    /// From `Content-Disposition`, only for attachments.
    pub file_name: Option<String>,
}

impl Client {
    /// A client for the server at `base_url` (http or https, without `/api/v1`, may have a path
    /// prefix), with the session token of a previous [`Client::login`] or `None`.
    #[frb(sync)]
    pub fn remote(base_url: String, token: Option<String>) -> Result<Client, ClientError> {
        Ok(Client::new(Transport::remote(&base_url)?, token))
    }

    /// A client for the local instance `instance` (started with `start_local`), with the session
    /// token of a previous [`Client::login`] or `None`. Its requests run in-process; once the
    /// instance was shut down, they fail with [`ClientError::Transport`].
    #[frb(sync)]
    pub fn local(instance: &LocalHandle, token: Option<String>) -> Client {
        Client::new(instance.transport(), token)
    }

    /// A client over any transport, e.g. [`Transport::local`] with the router of a local
    /// instance.
    #[frb(ignore)]
    pub fn new(transport: Transport, token: Option<String>) -> Client {
        Client {
            transport,
            token: RwLock::new(token),
            accept_language: RwLock::new(None),
        }
    }

    /// The session token sent with every request.
    #[frb(sync)]
    pub fn token(&self) -> Option<String> {
        self.token.read().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// Replaces the session token, e.g. with one restored from storage. Requests already sent
    /// keep the one they were sent with.
    #[frb(sync)]
    pub fn set_token(&self, token: Option<String>) {
        *self.token.write().unwrap_or_else(|e| e.into_inner()) = token;
    }

    /// The `Accept-Language` header sent with every request, e.g. `de-DE`. The server uses its
    /// first language for users without a locale, e.g. for chat titles.
    #[frb(sync)]
    pub fn set_accept_language(&self, accept_language: Option<String>) {
        *self
            .accept_language
            .write()
            .unwrap_or_else(|e| e.into_inner()) = accept_language;
    }

    // Instance and session

    /// `GET /api/v1/instance`, also without a session.
    pub async fn instance(&self) -> Result<InstanceDto, ClientError> {
        self.get("/api/v1/instance".into()).await
    }

    /// `POST /api/v1/login`. On success, the client sends the returned token from now on.
    pub async fn login(&self, request: LoginRequest) -> Result<LoginResponse, ClientError> {
        let response: LoginResponse = self.post("/api/v1/login".into(), &request).await?;
        self.set_token(Some(response.token.clone()));
        Ok(response)
    }

    /// `POST /api/v1/logout`: ends the session on the server. On success, the client forgets
    /// the token.
    pub async fn logout(&self) -> Result<(), ClientError> {
        self.post_empty("/api/v1/logout".into()).await?;
        self.set_token(None);
        Ok(())
    }

    // The user's own account

    /// `GET /api/v1/me`, also while a password change is required.
    pub async fn me(&self) -> Result<UserDto, ClientError> {
        self.get("/api/v1/me".into()).await
    }

    /// `POST /api/v1/change-password`, also while a password change is required.
    pub async fn change_password(&self, request: ChangePasswordRequest) -> Result<(), ClientError> {
        self.post_unit("/api/v1/change-password".into(), &request)
            .await
    }

    /// `POST /api/v1/me/default-model`.
    pub async fn set_my_default_model(
        &self,
        request: SetMyDefaultModelRequest,
    ) -> Result<(), ClientError> {
        self.post_unit("/api/v1/me/default-model".into(), &request)
            .await
    }

    /// `POST /api/v1/me/locale`.
    pub async fn set_locale(&self, request: SetLocaleRequest) -> Result<(), ClientError> {
        self.post_unit("/api/v1/me/locale".into(), &request).await
    }

    /// `POST /api/v1/me/auto-commit`.
    pub async fn set_my_auto_commit(
        &self,
        request: SetAutoCommitRequest,
    ) -> Result<(), ClientError> {
        self.post_unit("/api/v1/me/auto-commit".into(), &request)
            .await
    }

    /// `POST /api/v1/me/profile`.
    pub async fn update_profile(&self, request: UpdateProfileRequest) -> Result<(), ClientError> {
        self.post_unit("/api/v1/me/profile".into(), &request).await
    }

    /// `POST /api/v1/me/identity`.
    pub async fn update_identity(
        &self,
        request: UpdateIdentityRequest,
    ) -> Result<UserDto, ClientError> {
        self.post("/api/v1/me/identity".into(), &request).await
    }

    /// `GET /api/v1/models`: the models users can choose.
    pub async fn list_models(&self) -> Result<Vec<ModelDto>, ClientError> {
        self.get("/api/v1/models".into()).await
    }

    // Chats and messages

    /// `GET /api/v1/chats`, newest first. Pass the page's `next_cursor` as `cursor` for the next.
    pub async fn list_chats(
        &self,
        limit: Option<i64>,
        cursor: Option<String>,
    ) -> Result<ChatPageDto, ClientError> {
        let query = query(&ListChatsQuery { limit, cursor })?;
        self.get(format!("/api/v1/chats{query}")).await
    }

    /// `POST /api/v1/chats`: creates a chat with its first message and starts the answer.
    pub async fn create_chat(
        &self,
        request: CreateChatRequest,
    ) -> Result<ChatDetailDto, ClientError> {
        self.post("/api/v1/chats".into(), &request).await
    }

    /// `GET /api/v1/chats/{id}`, with its messages.
    pub async fn get_chat(&self, id: Uuid) -> Result<ChatDetailDto, ClientError> {
        self.get(format!("/api/v1/chats/{id}")).await
    }

    /// `POST /api/v1/chats/{id}/update`.
    pub async fn update_chat(
        &self,
        id: Uuid,
        request: UpdateChatRequest,
    ) -> Result<ChatDto, ClientError> {
        self.post(format!("/api/v1/chats/{id}/update"), &request)
            .await
    }

    /// `POST /api/v1/chats/{id}/delete`.
    pub async fn delete_chat(&self, id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!("/api/v1/chats/{id}/delete")).await
    }

    /// `POST /api/v1/chats/{id}/messages`: the user message and the answer being generated.
    pub async fn send_message(
        &self,
        chat_id: Uuid,
        request: SendMessageRequest,
    ) -> Result<Vec<MessageDto>, ClientError> {
        self.post(format!("/api/v1/chats/{chat_id}/messages"), &request)
            .await
    }

    /// `POST /api/v1/chats/{id}/messages/{message_id}/cancel`.
    pub async fn cancel_message(&self, chat_id: Uuid, message_id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!(
            "/api/v1/chats/{chat_id}/messages/{message_id}/cancel"
        ))
        .await
    }

    /// `GET /api/v1/chats/{id}/messages/{message_id}/stream`: the events of a message, usually
    /// an answer being generated (see [`MessageEvent`]). In Dart a `Future<Stream>`, which
    /// completes once the server accepted the request; an error before that (e.g. `NOT_FOUND`)
    /// is thrown, one after it is the stream's last event, [`MessageEvent::Error`] (FRB would
    /// only pass a stream error as a string).
    ///
    /// The stream ends by itself after `Done`. To stop it earlier, cancel `cancel`: dropping
    /// the Dart subscription is only noticed with the next event.
    #[frb(stream_dart_await)]
    pub async fn stream_message(
        &self,
        chat_id: Uuid,
        message_id: Uuid,
        cancel: &CancellationToken,
        sink: StreamSink<MessageEvent>,
    ) -> Result<(), ClientError> {
        let cancel = cancel.inner();
        let events = tokio::select! {
            biased;
            () = cancel.cancelled() => return Ok(()),
            events = self.message_events(chat_id, message_id) => events?,
        };
        // On the crate's runtime, so it runs on after Dart got the stream.
        runtime::runtime().spawn(forward(events, cancel, move |event| {
            sink.add(event).is_ok()
        }));
        Ok(())
    }

    /// Like [`Client::stream_message`], as a Rust stream: dropping it ends the request.
    #[frb(ignore)]
    pub async fn message_events(
        &self,
        chat_id: Uuid,
        message_id: Uuid,
    ) -> Result<MessageEvents, ClientError> {
        let path = format!("/api/v1/chats/{chat_id}/messages/{message_id}/stream");
        let mut headers = self.headers(None)?;
        headers.insert(ACCEPT, HeaderValue::from_static("text/event-stream"));
        let response = self
            .transport
            .request_stream(Method::GET, &path, headers, Bytes::new())
            .await?;
        Ok(MessageEvents::new(response.status, response.body))
    }

    /// `POST /api/v1/chats/{id}/messages/{message_id}/retry`: the new answer being generated.
    pub async fn retry_message(
        &self,
        chat_id: Uuid,
        message_id: Uuid,
    ) -> Result<MessageDto, ClientError> {
        let path = format!("/api/v1/chats/{chat_id}/messages/{message_id}/retry");
        self.post_json(path, empty_object()).await?.json()
    }

    /// `GET /api/v1/chats/{id}/tool-calls/{tool_call_id}`, with its output.
    pub async fn get_tool_call(
        &self,
        chat_id: Uuid,
        tool_call_id: Uuid,
    ) -> Result<ToolCallDto, ClientError> {
        self.get(tool_call_path(chat_id, tool_call_id, "")).await
    }

    /// `GET .../tool-calls/{tool_call_id}/file`: the file `present_file_to_user` presented, as it
    /// is at the call's commit.
    pub async fn get_presented_file(
        &self,
        chat_id: Uuid,
        tool_call_id: Uuid,
    ) -> Result<FileDownload, ClientError> {
        self.get_file(tool_call_path(chat_id, tool_call_id, "/file"))
            .await
    }

    /// `GET .../tool-calls/{tool_call_id}/proposed-commit`: the change a tool call proposed.
    pub async fn get_proposed_commit(
        &self,
        chat_id: Uuid,
        tool_call_id: Uuid,
    ) -> Result<ProposedCommitDto, ClientError> {
        self.get(tool_call_path(chat_id, tool_call_id, "/proposed-commit"))
            .await
    }

    /// `GET .../tool-calls/{tool_call_id}/diff`: the proposed commit as it is shown, the diff of
    /// its file with the changed words marked, or its moves.
    pub async fn get_proposed_commit_diff(
        &self,
        chat_id: Uuid,
        tool_call_id: Uuid,
    ) -> Result<FileDiffDto, ClientError> {
        self.get(tool_call_path(chat_id, tool_call_id, "/diff"))
            .await
    }

    /// `GET .../tool-calls/{tool_call_id}/proposed-commit/file`: the file as the change proposes it.
    pub async fn get_proposed_commit_file(
        &self,
        chat_id: Uuid,
        tool_call_id: Uuid,
    ) -> Result<FileDownload, ClientError> {
        self.get_file(tool_call_path(
            chat_id,
            tool_call_id,
            "/proposed-commit/file",
        ))
        .await
    }

    /// `POST .../tool-calls/{tool_call_id}/commit`: pushes the proposed change to the branch.
    pub async fn commit_proposed_commit(
        &self,
        chat_id: Uuid,
        tool_call_id: Uuid,
    ) -> Result<ProposedCommitDto, ClientError> {
        let path = tool_call_path(chat_id, tool_call_id, "/commit");
        self.post_json(path, empty_object()).await?.json()
    }

    /// `POST /api/v1/attachments`: uploads a file to send with the next message
    /// (`attachment_id`). `content_type` is the type the platform reports, if any.
    pub async fn upload_attachment(
        &self,
        file_name: String,
        content_type: Option<String>,
        content: Vec<u8>,
    ) -> Result<AttachmentDto, ClientError> {
        let query = query(&UploadAttachmentQuery {
            file_name,
            content_type,
        })?;
        let path = format!("/api/v1/attachments{query}");
        self.send(Method::POST, path, Some(OCTET_STREAM), content.into())
            .await?
            .json()
    }

    /// `GET /api/v1/attachments/{id}`, with its file name.
    pub async fn download_attachment(&self, id: Uuid) -> Result<FileDownload, ClientError> {
        self.get_file(format!("/api/v1/attachments/{id}")).await
    }

    // Repositories

    /// `GET /api/v1/repositories`: owned and shared ones.
    pub async fn list_repositories(&self) -> Result<Vec<RepositoryDto>, ClientError> {
        self.get("/api/v1/repositories".into()).await
    }

    /// `POST /api/v1/repositories`. Checks the remote before it returns.
    pub async fn create_repository(
        &self,
        request: CreateRepositoryRequest,
    ) -> Result<RepositoryDto, ClientError> {
        self.post("/api/v1/repositories".into(), &request).await
    }

    /// `GET /api/v1/repositories/{id}`.
    pub async fn get_repository(&self, id: Uuid) -> Result<RepositoryDto, ClientError> {
        self.get(format!("/api/v1/repositories/{id}")).await
    }

    /// `POST /api/v1/repositories/{id}/update`.
    pub async fn update_repository(
        &self,
        id: Uuid,
        request: UpdateRepositoryRequest,
    ) -> Result<RepositoryDto, ClientError> {
        self.post(format!("/api/v1/repositories/{id}/update"), &request)
            .await
    }

    /// `POST /api/v1/repositories/{id}/delete`.
    pub async fn delete_repository(&self, id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!("/api/v1/repositories/{id}/delete"))
            .await
    }

    /// `POST /api/v1/repositories/{id}/sync`: syncs it as soon as possible.
    pub async fn sync_repository(&self, id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!("/api/v1/repositories/{id}/sync"))
            .await
    }

    /// `GET /api/v1/repositories/{id}/documents`: its documents and their conversion.
    pub async fn list_repository_documents(
        &self,
        id: Uuid,
    ) -> Result<RepositoryDocumentsDto, ClientError> {
        self.get(format!("/api/v1/repositories/{id}/documents"))
            .await
    }

    /// `GET /api/v1/repositories/{id}/users`: the users it is shared with.
    pub async fn list_repository_users(
        &self,
        id: Uuid,
    ) -> Result<Vec<RepositoryUserDto>, ClientError> {
        self.get(format!("/api/v1/repositories/{id}/users")).await
    }

    /// `POST /api/v1/repositories/{id}/users`: shares it with a user.
    pub async fn add_repository_user(
        &self,
        id: Uuid,
        request: AddRepositoryUserRequest,
    ) -> Result<(), ClientError> {
        self.post_unit(format!("/api/v1/repositories/{id}/users"), &request)
            .await
    }

    /// `POST /api/v1/repositories/{id}/users/{user_id}/update`.
    pub async fn update_repository_user(
        &self,
        id: Uuid,
        user_id: Uuid,
        request: UpdateRepositoryUserRequest,
    ) -> Result<(), ClientError> {
        let path = format!("/api/v1/repositories/{id}/users/{user_id}/update");
        self.post_unit(path, &request).await
    }

    /// `POST /api/v1/repositories/{id}/users/{user_id}/delete`: stops sharing it with the user,
    /// or leaves it (the user's own id).
    pub async fn remove_repository_user(&self, id: Uuid, user_id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!("/api/v1/repositories/{id}/users/{user_id}/delete"))
            .await
    }

    // Users (admins)

    /// `GET /api/v1/users`.
    pub async fn list_users(&self) -> Result<Vec<UserDto>, ClientError> {
        self.get("/api/v1/users".into()).await
    }

    /// `POST /api/v1/register`: creates a user.
    pub async fn register_user(&self, request: RegisterRequest) -> Result<UserDto, ClientError> {
        self.post("/api/v1/register".into(), &request).await
    }

    /// `POST /api/v1/users/{id}/update`.
    pub async fn update_user(
        &self,
        id: Uuid,
        request: UpdateUserRequest,
    ) -> Result<UserDto, ClientError> {
        self.post(format!("/api/v1/users/{id}/update"), &request)
            .await
    }

    /// `POST /api/v1/users/{id}/password`: sets another user's password and signs them out.
    pub async fn reset_password(
        &self,
        id: Uuid,
        request: ResetPasswordRequest,
    ) -> Result<UserDto, ClientError> {
        self.post(format!("/api/v1/users/{id}/password"), &request)
            .await
    }

    /// `POST /api/v1/delete-user`.
    pub async fn delete_user(&self, request: DeleteUserRequest) -> Result<(), ClientError> {
        self.post_unit("/api/v1/delete-user".into(), &request).await
    }

    // LLM providers and models (admins)

    /// `GET /api/v1/llm-providers`, with their models.
    pub async fn list_llm_providers(&self) -> Result<Vec<LlmProviderDto>, ClientError> {
        self.get("/api/v1/llm-providers".into()).await
    }

    /// `POST /api/v1/llm-providers`.
    pub async fn create_llm_provider(
        &self,
        request: CreateLlmProviderRequest,
    ) -> Result<LlmProviderDto, ClientError> {
        self.post("/api/v1/llm-providers".into(), &request).await
    }

    /// `POST /api/v1/llm-providers/{id}/update`.
    pub async fn update_llm_provider(
        &self,
        id: Uuid,
        request: UpdateLlmProviderRequest,
    ) -> Result<LlmProviderDto, ClientError> {
        self.post(format!("/api/v1/llm-providers/{id}/update"), &request)
            .await
    }

    /// `POST /api/v1/llm-providers/{id}/delete`, with its models.
    pub async fn delete_llm_provider(&self, id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!("/api/v1/llm-providers/{id}/delete"))
            .await
    }

    /// `GET /api/v1/llm-providers/{id}/remote-models`: the models the provider's server offers.
    pub async fn list_remote_models(
        &self,
        provider_id: Uuid,
    ) -> Result<Vec<RemoteModelDto>, ClientError> {
        self.get(format!("/api/v1/llm-providers/{provider_id}/remote-models"))
            .await
    }

    /// `POST /api/v1/llm-providers/{id}/models`.
    pub async fn create_llm_model(
        &self,
        provider_id: Uuid,
        request: LlmModelRequest,
    ) -> Result<LlmModelDto, ClientError> {
        self.post(
            format!("/api/v1/llm-providers/{provider_id}/models"),
            &request,
        )
        .await
    }

    /// `POST /api/v1/models/{id}/update`.
    pub async fn update_llm_model(
        &self,
        id: Uuid,
        request: LlmModelRequest,
    ) -> Result<LlmModelDto, ClientError> {
        self.post(format!("/api/v1/models/{id}/update"), &request)
            .await
    }

    /// `POST /api/v1/models/{id}/delete`.
    pub async fn delete_llm_model(&self, id: Uuid) -> Result<(), ClientError> {
        self.post_empty(format!("/api/v1/models/{id}/delete")).await
    }

    /// `POST /api/v1/default-model`: the model of users who did not choose one.
    pub async fn set_default_model(
        &self,
        request: SetDefaultModelRequest,
    ) -> Result<(), ClientError> {
        self.post_unit("/api/v1/default-model".into(), &request)
            .await
    }

    // Configuration (admins)

    /// `GET /api/v1/config`: every setting, sorted by key.
    pub async fn get_config(&self) -> Result<Vec<ConfigEntryDto>, ClientError> {
        self.get("/api/v1/config".into()).await
    }

    /// `POST /api/v1/config`: replaces all overrides (keys left out fall back to the
    /// environment) and returns the settings.
    pub async fn set_config(
        &self,
        overrides: HashMap<String, String>,
    ) -> Result<Vec<ConfigEntryDto>, ClientError> {
        self.post("/api/v1/config".into(), &overrides).await
    }

    // Server (admins)

    /// `GET /api/v1/server`.
    pub async fn get_server(&self) -> Result<ServerDto, ClientError> {
        self.get("/api/v1/server".into()).await
    }

    // Document extraction (admins)

    /// `GET /api/v1/document-extraction`.
    pub async fn get_extraction_overview(&self) -> Result<ExtractionOverviewDto, ClientError> {
        self.get("/api/v1/document-extraction".into()).await
    }

    /// `GET /api/v1/document-extraction/documents`.
    pub async fn list_extraction_documents(
        &self,
        filter: Option<DocumentFilter>,
        offset: Option<i64>,
        limit: Option<i64>,
    ) -> Result<ExtractionDocumentPageDto, ClientError> {
        let query = query(&ListExtractionDocumentsQuery {
            filter,
            offset,
            limit,
        })?;
        self.get(format!("/api/v1/document-extraction/documents{query}"))
            .await
    }

    /// `POST /api/v1/document-extraction/retry`: converts a document again.
    pub async fn retry_document_extraction(
        &self,
        request: RetryDocumentRequest,
    ) -> Result<(), ClientError> {
        self.post_unit("/api/v1/document-extraction/retry".into(), &request)
            .await
    }

    // Helpers

    async fn get<T: DeserializeOwned>(&self, path: String) -> Result<T, ClientError> {
        self.send(Method::GET, path, None, Bytes::new())
            .await?
            .json()
    }

    async fn post<B: Serialize, T: DeserializeOwned>(
        &self,
        path: String,
        body: &B,
    ) -> Result<T, ClientError> {
        self.post_json(path, to_json(body)?).await?.json()
    }

    /// A POST whose response has no body.
    async fn post_unit<B: Serialize>(&self, path: String, body: &B) -> Result<(), ClientError> {
        self.post_json(path, to_json(body)?).await?;
        Ok(())
    }

    /// A POST without a request or a response body. It is sent as `{}`, since the API takes only
    /// JSON (or uploads) in POSTs.
    async fn post_empty(&self, path: String) -> Result<(), ClientError> {
        self.post_json(path, empty_object()).await?;
        Ok(())
    }

    /// A POST with a JSON body.
    async fn post_json(&self, path: String, body: Bytes) -> Result<Response, ClientError> {
        self.send(Method::POST, path, Some(JSON), body).await
    }

    async fn get_file(&self, path: String) -> Result<FileDownload, ClientError> {
        let response = self.send(Method::GET, path, None, Bytes::new()).await?;
        let header = |name| {
            response
                .headers
                .get(name)
                .and_then(|value: &HeaderValue| value.to_str().ok())
        };
        Ok(FileDownload {
            content_type: header(CONTENT_TYPE).map(str::to_owned),
            file_name: header(CONTENT_DISPOSITION).and_then(disposition_file_name),
            content: response.body.into(),
        })
    }

    async fn send(
        &self,
        method: Method,
        path: String,
        content_type: Option<&'static str>,
        body: Bytes,
    ) -> Result<Response, ClientError> {
        let headers = self.headers(content_type)?;
        self.transport.request(method, &path, headers, body).await
    }

    /// The headers of every request: the session token, the language and the `content_type`
    /// of the body.
    fn headers(&self, content_type: Option<&'static str>) -> Result<HeaderMap, ClientError> {
        let mut headers = HeaderMap::new();
        if let Some(token) = self.token() {
            let mut value = HeaderValue::try_from(format!("Bearer {token}")).map_err(|_| {
                ClientError::Transport {
                    message: "Invalid session token".into(),
                }
            })?;
            value.set_sensitive(true);
            headers.insert(AUTHORIZATION, value);
        }
        let accept_language = self
            .accept_language
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        if let Some(value) = accept_language.and_then(|l| HeaderValue::try_from(l).ok()) {
            headers.insert(ACCEPT_LANGUAGE, value);
        }
        if let Some(content_type) = content_type {
            headers.insert(CONTENT_TYPE, HeaderValue::from_static(content_type));
        }
        Ok(headers)
    }
}

fn tool_call_path(chat_id: Uuid, tool_call_id: Uuid, suffix: &str) -> String {
    format!("/api/v1/chats/{chat_id}/tool-calls/{tool_call_id}{suffix}")
}

fn empty_object() -> Bytes {
    Bytes::from_static(b"{}")
}

fn to_json<B: Serialize>(body: &B) -> Result<Bytes, ClientError> {
    serde_json::to_vec(body)
        .map(Bytes::from)
        .map_err(|error| ClientError::Transport {
            message: format!("Invalid request body: {error}"),
        })
}

/// The query string for `params` (`?a=1&b=2`, fields that are `None` left out), empty if there
/// are none.
fn query<Q: Serialize>(params: &Q) -> Result<String, ClientError> {
    let query = serde_urlencoded::to_string(params).map_err(|error| ClientError::Transport {
        message: format!("Invalid query: {error}"),
    })?;
    Ok(if query.is_empty() {
        query
    } else {
        format!("?{query}")
    })
}

/// The file name of a `Content-Disposition` header such as
/// `attachment; filename="a_b.pdf"; filename*=UTF-8''a%C3%A4b.pdf`, preferring the UTF-8 one.
fn disposition_file_name(header: &str) -> Option<String> {
    let mut plain = None;
    for param in header.split(';').map(str::trim) {
        let Some((name, value)) = param.split_once('=') else {
            continue;
        };
        let name = name.trim().to_ascii_lowercase();
        let value = value.trim();
        if name == "filename*" {
            if let Some(decoded) = decode_ext_value(value) {
                return Some(decoded);
            }
        } else if name == "filename" {
            plain = Some(value.trim_matches('"').to_owned());
        }
    }
    plain
}

/// An RFC 5987 value in UTF-8 (`UTF-8'language'percent-encoded`).
fn decode_ext_value(value: &str) -> Option<String> {
    let (charset, rest) = value.split_once('\'')?;
    let (_language, encoded) = rest.split_once('\'')?;
    if !charset.eq_ignore_ascii_case("utf-8") {
        return None;
    }
    let decoded = percent_encoding::percent_decode_str(encoded)
        .decode_utf8()
        .ok()?;
    Some(decoded.into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_queries() {
        let empty = query(&ListChatsQuery {
            limit: None,
            cursor: None,
        });
        assert_eq!(empty.unwrap(), "");
        let query = query(&UploadAttachmentQuery {
            file_name: "Rechnung März & Co.pdf".into(),
            content_type: Some("application/pdf".into()),
        });
        assert_eq!(
            query.unwrap(),
            "?file_name=Rechnung+M%C3%A4rz+%26+Co.pdf&content_type=application%2Fpdf"
        );
        let filter = super::query(&ListExtractionDocumentsQuery {
            filter: Some(DocumentFilter::Failed),
            offset: Some(20),
            limit: None,
        });
        assert_eq!(filter.unwrap(), "?filter=FAILED&offset=20");
    }

    #[test]
    fn reads_file_names() {
        assert_eq!(
            disposition_file_name(
                "attachment; filename=\"Rechnung M_rz.pdf\"; filename*=UTF-8''Rechnung%20M%C3%A4rz.pdf"
            )
            .as_deref(),
            Some("Rechnung März.pdf")
        );
        assert_eq!(
            disposition_file_name("attachment; filename=\"a.txt\"").as_deref(),
            Some("a.txt")
        );
        assert_eq!(disposition_file_name("inline"), None);
    }
}
