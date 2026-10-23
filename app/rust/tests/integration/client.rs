//! The client against a real Repolupe on a temporary SQLite file, through both transports, and
//! against a local instance as the app starts it. Nothing here reaches the network: answers
//! come from a mock LLM on 127.0.0.1, and no repository can be created without a git remote.

use std::collections::HashMap;

use axum::Router;
use axum::http::header::AUTHORIZATION;
use axum::http::{HeaderMap, Method};
use bytes::Bytes;
use futures_executor::block_on;
use futures_util::StreamExt;
use repolupe::dto::auth::LoginRequest;
use repolupe::dto::chat::{
    CreateChatRequest, MessageDto, MessageStatus, SendMessageRequest, ToolCallStatus,
    UpdateChatRequest,
};
use repolupe::dto::error::ErrorCode;
use repolupe::dto::extraction::{DocumentFilter, RetryDocumentRequest};
use repolupe::dto::llm::{
    ApiKeyChange, CreateLlmProviderRequest, LlmApiFormat, LlmModelRequest, SetDefaultModelRequest,
    UpdateLlmProviderRequest,
};
use repolupe::dto::repository::{
    AddRepositoryUserRequest, CreateRepositoryRequest, RemoteSettings, RemoteSettingsChange,
    TokenChange, UpdateRepositoryRequest, UpdateRepositoryUserRequest,
};
use repolupe::dto::user::{
    ChangePasswordRequest, DeleteUserRequest, RegisterRequest, ResetPasswordRequest,
    SetAutoCommitRequest, SetLocaleRequest, SetMyDefaultModelRequest, UpdateIdentityRequest,
    UpdateProfileRequest, UpdateUserRequest,
};
use repolupe::{
    Config, DEFAULT_INITIAL_ADMIN_PASSWORD, DEFAULT_SESSION_IDLE_TIMEOUT, DatabaseConfig,
    INITIAL_ADMIN_USER_NAME, Repolupe, RuntimeConfig,
};
use serde_json::json;
use tempfile::TempDir;
use uuid::Uuid;

use repolupe_ffi::api::client::Client;
use repolupe_ffi::api::error::ClientError;
use repolupe_ffi::api::local::{LocalConfig, generate_secret, local_admin_user_name, start_local};
use repolupe_ffi::api::stream::MessageEvent;
use repolupe_ffi::runtime::runtime;
use repolupe_ffi::transport::Transport;

use crate::stream::{MOCK_MODEL, MockLlm, MockResponse, anthropic};

pub(crate) const PASSWORD: &str = "client-tests-password";

/// A Repolupe without background tasks in a temporary directory.
pub(crate) struct Local {
    repolupe: Option<Repolupe>,
    _dir: TempDir,
}

impl Local {
    pub(crate) fn start() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let config = Config {
            token_encryption_key: "client-tests-secret-0123456789abcdef".into(),
            repos_dir: dir.path().join("repos"),
            attachments_dir: dir.path().join("attachments"),
            frontend_dir: None,
            initial_admin_password: None,
            initial_admin_must_change_password: true,
            session_idle_timeout: Some(DEFAULT_SESSION_IDLE_TIMEOUT),
            run_migrations: true,
            background_tasks: false,
            debug_api: false,
            ocr_api_key_mistral: None,
            runtime: RuntimeConfig::default(),
        };
        let database = DatabaseConfig {
            url: format!("sqlite://{}", dir.path().join("rp.db").display()),
        };
        // On the crate's runtime, like the requests, since the pool and Repolupe spawn tasks.
        let repolupe = runtime()
            .block_on(async { Repolupe::new(config, database.connect().await?).await })
            .unwrap();
        Local {
            repolupe: Some(repolupe),
            _dir: dir,
        }
    }

    pub(crate) fn router(&self) -> Router {
        self.repolupe.as_ref().unwrap().router()
    }
}

impl Drop for Local {
    fn drop(&mut self) {
        if let Some(repolupe) = self.repolupe.take() {
            runtime().block_on(repolupe.shutdown());
        }
    }
}

/// The router served on 127.0.0.1, as a server would.
pub(crate) fn serve(router: Router) -> String {
    let address = runtime().block_on(async {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        address
    });
    format!("http://{address}")
}

/// The DTOs don't implement `Debug`.
fn api_code<T>(result: Result<T, ClientError>) -> ErrorCode {
    match result {
        Err(ClientError::Api { code, .. }) => code,
        Err(error) => panic!("expected an API error, got {error:?}"),
        Ok(_) => panic!("expected an API error, got a response"),
    }
}

fn login(client: &Client, user_name: &str, password: &str) -> Result<(), ClientError> {
    block_on(client.login(LoginRequest {
        user_name_or_email: user_name.into(),
        password: password.into(),
    }))
    .map(|_| ())
}

/// Calls of every kind (GET, POST with and without a body, upload, download, query, path
/// ids, errors) with the typed DTOs, so a mismatch with the API shows up here.
fn exercise(transport: Transport) {
    let client = &Client::new(transport.clone(), None);
    // Without a session.
    assert_eq!(block_on(client.instance()).unwrap().name, "Repolupe");
    assert_eq!(api_code(block_on(client.me())), ErrorCode::Unauthorized);
    assert_eq!(
        api_code(login(client, INITIAL_ADMIN_USER_NAME, "wrong password")),
        ErrorCode::Unauthorized
    );
    assert_eq!(client.token(), None);

    // The initial admin logs in and has to change the password first.
    let response = block_on(client.login(LoginRequest {
        user_name_or_email: INITIAL_ADMIN_USER_NAME.into(),
        password: DEFAULT_INITIAL_ADMIN_PASSWORD.into(),
    }))
    .unwrap();
    assert!(response.user.must_change_password);
    assert_eq!(client.token().as_deref(), Some(response.token.as_str()));
    assert_eq!(
        api_code(block_on(client.list_chats(None, None))),
        ErrorCode::PasswordChangeRequired
    );
    block_on(client.change_password(ChangePasswordRequest {
        current_password: DEFAULT_INITIAL_ADMIN_PASSWORD.into(),
        new_password: PASSWORD.into(),
    }))
    .unwrap();
    let me = block_on(client.me()).unwrap();
    assert_eq!(me.user_name, INITIAL_ADMIN_USER_NAME);
    assert!(!me.must_change_password);

    // Chats and repositories, without creating any (which would reach the network).
    let page = block_on(client.list_chats(Some(10), None)).unwrap();
    assert!(page.items.is_empty());
    assert!(page.next_cursor.is_none());
    assert_eq!(
        api_code(block_on(client.get_chat(Uuid::now_v7()))),
        ErrorCode::NotFound
    );
    assert!(block_on(client.list_repositories()).unwrap().is_empty());
    // Not found only after the body was parsed, so `TokenChange` serializes as the API expects.
    let update = UpdateRepositoryRequest {
        name: "docs".into(),
        description: None,
        remote: Some(RemoteSettingsChange {
            url: "https://example.com/docs.git".into(),
            branch: "main".into(),
            poll_interval_seconds: 3600,
            token: TokenChange::Set {
                value: "secret".into(),
            },
        }),
        allow_commits: false,
    };
    assert_eq!(
        api_code(block_on(client.update_repository(Uuid::now_v7(), update))),
        ErrorCode::NotFound
    );

    // Users.
    let user = block_on(client.register_user(RegisterRequest {
        user_name: "alice".into(),
        email: Some("alice@example.com".into()),
        password: PASSWORD.into(),
        must_change_password: false,
    }))
    .unwrap();
    let users = block_on(client.list_users()).unwrap();
    assert!(users.iter().any(|u| u.id == user.id));

    // LLM providers and models, with decimal strings and the `ApiKeyChange` enum.
    let provider = block_on(client.create_llm_provider(CreateLlmProviderRequest {
        name: "Anthropic".into(),
        api_format: LlmApiFormat::Anthropic,
        base_url: None,
        api_key: Some("sk-ant-0123456789".into()),
        currency: Some("USD".into()),
    }))
    .unwrap();
    assert!(provider.api_key.is_some());
    let model = block_on(client.create_llm_model(
        provider.id,
        LlmModelRequest {
            api_name: "claude-opus-5-5".into(),
            display_name: Some("Claude Opus 5.5".into()),
            max_output_tokens: None,
            input_price: Some("5".into()),
            output_price: Some("25.50".into()),
            cache_read_price: None,
            cache_write_price: None,
        },
    ))
    .unwrap();
    assert_eq!(model.output_price.as_deref(), Some("25.50"));
    block_on(client.set_default_model(SetDefaultModelRequest { model_id: model.id })).unwrap();
    let models = block_on(client.list_models()).unwrap();
    assert_eq!(models.len(), 1);
    assert!(models[0].is_default);
    let provider = block_on(client.update_llm_provider(
        provider.id,
        UpdateLlmProviderRequest {
            name: "Claude".into(),
            api_format: LlmApiFormat::Anthropic,
            base_url: None,
            api_key: ApiKeyChange::Keep,
            currency: Some("USD".into()),
        },
    ))
    .unwrap();
    assert_eq!(provider.name, "Claude");
    let providers = block_on(client.list_llm_providers()).unwrap();
    assert_eq!(providers[0].models.len(), 1);

    // An upload and its download, with a file name that needs encoding.
    let file_name = "Notiz März & Co.txt";
    let attachment = block_on(client.upload_attachment(
        file_name.into(),
        Some("text/plain".into()),
        b"hello".to_vec(),
    ))
    .unwrap();
    assert_eq!(attachment.file_name, file_name);
    assert_eq!(attachment.size, 5);
    let download = block_on(client.download_attachment(attachment.id)).unwrap();
    assert_eq!(download.content, b"hello");
    assert_eq!(download.file_name.as_deref(), Some(file_name));
    assert!(download.content_type.unwrap().starts_with("text/plain"));

    // Configuration and document extraction.
    let overrides = HashMap::from([("INSTANCE_NAME".to_string(), "Local".to_string())]);
    let entries = block_on(client.set_config(overrides)).unwrap();
    let name = entries.iter().find(|e| e.key == "INSTANCE_NAME").unwrap();
    assert_eq!(name.override_value.as_deref(), Some("Local"));
    assert!(name.runtime);
    assert_eq!(block_on(client.instance()).unwrap().name, "Local");
    assert_eq!(block_on(client.get_config()).unwrap().len(), entries.len());
    let overview = block_on(client.get_extraction_overview()).unwrap();
    assert_eq!(overview.totals.documents, 0);
    let page =
        block_on(client.list_extraction_documents(Some(DocumentFilter::Failed), Some(0), Some(5)))
            .unwrap();
    assert_eq!(page.total, 0);

    // Another user's session, and logging out.
    let other = Client::new(transport, None);
    login(&other, "alice", PASSWORD).unwrap();
    assert_eq!(api_code(block_on(other.list_users())), ErrorCode::Forbidden);
    let token = client.token();
    block_on(client.logout()).unwrap();
    assert_eq!(client.token(), None);
    assert_eq!(api_code(block_on(client.me())), ErrorCode::Unauthorized);
    client.set_token(token);
    assert_eq!(api_code(block_on(client.me())), ErrorCode::Unauthorized);
    assert_eq!(block_on(other.me()).unwrap().user_name, "alice");
}

#[test]
fn local_transport() {
    let local = Local::start();
    exercise(Transport::local(local.router()));
}

#[test]
fn remote_transport() {
    let local = Local::start();
    let base_url = serve(local.router());
    let client = Client::remote(base_url.clone(), None).unwrap();
    assert_eq!(block_on(client.instance()).unwrap().name, "Repolupe");
    exercise(Transport::remote(&base_url).unwrap());
}

#[test]
fn restores_the_token() {
    let local = Local::start();
    let client = Client::new(Transport::local(local.router()), None);
    login(
        &client,
        INITIAL_ADMIN_USER_NAME,
        DEFAULT_INITIAL_ADMIN_PASSWORD,
    )
    .unwrap();
    let restored = Client::new(Transport::local(local.router()), client.token());
    assert!(block_on(restored.me()).unwrap().must_change_password);
}

#[test]
fn rejects_invalid_base_urls() {
    assert!(matches!(
        Client::remote("example.com".into(), None),
        Err(ClientError::Transport { .. })
    ));
}

/// The methods that need data this module doesn't create (ids in the path, a git remote), each
/// with the error of its handler, e.g. `NOT_FOUND` for ids that don't exist (deletes are
/// idempotent and succeed). Such an error means the route, the method and the body matched: a
/// path or method the API doesn't have gets a 404 or 405 without an `ErrorDto`
/// (`InvalidResponse`, checked first), and a body it can't parse is rejected before the handler.
#[test]
fn every_method_reaches_its_route() {
    let local = Local::start();
    let transport = Transport::local(local.router());
    let client = &Client::new(transport.clone(), None);
    login(
        client,
        INITIAL_ADMIN_USER_NAME,
        DEFAULT_INITIAL_ADMIN_PASSWORD,
    )
    .unwrap();
    block_on(client.change_password(ChangePasswordRequest {
        current_password: DEFAULT_INITIAL_ADMIN_PASSWORD.into(),
        new_password: PASSWORD.into(),
    }))
    .unwrap();
    let mut headers = HeaderMap::new();
    let bearer = format!("Bearer {}", client.token().unwrap());
    headers.insert(AUTHORIZATION, bearer.parse().unwrap());
    for (method, path, status) in [
        (Method::GET, "/api/v1/chat", 404),
        (Method::GET, "/api/v1/chats/1/tool-call/2", 404),
        (Method::GET, "/api/v1/logout", 405),
    ] {
        let result = block_on(transport.request(method, path, headers.clone(), Bytes::new()));
        match result {
            Err(ClientError::InvalidResponse { status: s, .. }) => assert_eq!(s, status, "{path}"),
            Err(error) => panic!("{path}: expected an invalid response, got {error:?}"),
            Ok(_) => panic!("{path}: expected an invalid response, got a response"),
        }
    }

    let id = Uuid::now_v7;
    let model = || LlmModelRequest {
        api_name: "model".into(),
        display_name: None,
        max_output_tokens: None,
        input_price: None,
        output_price: None,
        cache_read_price: None,
        cache_write_price: None,
    };
    let codes = [
        // Chats and messages.
        (
            "update_chat",
            api_code(block_on(client.update_chat(
                id(),
                UpdateChatRequest {
                    title: "Title".into(),
                    model_id: None,
                },
            ))),
        ),
        (
            "send_message",
            api_code(block_on(client.send_message(
                id(),
                SendMessageRequest {
                    content: "Hello".into(),
                    attachment_id: None,
                },
            ))),
        ),
        (
            "cancel_message",
            api_code(block_on(client.cancel_message(id(), id()))),
        ),
        (
            "retry_message",
            api_code(block_on(client.retry_message(id(), id()))),
        ),
        (
            "message_events",
            api_code(block_on(client.message_events(id(), id()))),
        ),
        (
            "get_tool_call",
            api_code(block_on(client.get_tool_call(id(), id()))),
        ),
        (
            "get_presented_file",
            api_code(block_on(client.get_presented_file(id(), id()))),
        ),
        (
            "get_proposed_commit",
            api_code(block_on(client.get_proposed_commit(id(), id()))),
        ),
        (
            "get_proposed_commit_diff",
            api_code(block_on(client.get_proposed_commit_diff(id(), id()))),
        ),
        (
            "get_proposed_commit_file",
            api_code(block_on(client.get_proposed_commit_file(id(), id()))),
        ),
        (
            "commit_proposed_commit",
            api_code(block_on(client.commit_proposed_commit(id(), id()))),
        ),
        (
            "download_attachment",
            api_code(block_on(client.download_attachment(id()))),
        ),
        // Repositories.
        (
            "get_repository",
            api_code(block_on(client.get_repository(id()))),
        ),
        (
            "sync_repository",
            api_code(block_on(client.sync_repository(id()))),
        ),
        (
            "list_repository_documents",
            api_code(block_on(client.list_repository_documents(id()))),
        ),
        (
            "list_repository_users",
            api_code(block_on(client.list_repository_users(id()))),
        ),
        (
            "add_repository_user",
            api_code(block_on(client.add_repository_user(
                id(),
                AddRepositoryUserRequest {
                    user_name_or_email: INITIAL_ADMIN_USER_NAME.into(),
                },
            ))),
        ),
        (
            "update_repository_user",
            api_code(block_on(client.update_repository_user(
                id(),
                id(),
                UpdateRepositoryUserRequest { can_commit: true },
            ))),
        ),
        (
            "remove_repository_user",
            api_code(block_on(client.remove_repository_user(id(), id()))),
        ),
        // Users.
        (
            "update_user",
            api_code(block_on(client.update_user(
                id(),
                UpdateUserRequest {
                    user_name: "bob".into(),
                    email: None,
                    can_login: true,
                    can_manage_repositories: true,
                    can_change_identity: true,
                    must_change_password: false,
                },
            ))),
        ),
        (
            "reset_password",
            api_code(block_on(client.reset_password(
                id(),
                ResetPasswordRequest {
                    password: PASSWORD.into(),
                    must_change_password: false,
                },
            ))),
        ),
        (
            "delete_user",
            api_code(block_on(
                client.delete_user(DeleteUserRequest { user_id: id() }),
            )),
        ),
        // LLM providers and models.
        (
            "list_remote_models",
            api_code(block_on(client.list_remote_models(id()))),
        ),
        (
            "create_llm_model",
            api_code(block_on(client.create_llm_model(id(), model()))),
        ),
        (
            "update_llm_model",
            api_code(block_on(client.update_llm_model(id(), model()))),
        ),
        // Document extraction.
        (
            "retry_document_extraction",
            api_code(block_on(client.retry_document_extraction(
                RetryDocumentRequest {
                    blob_oid: "0123456789abcdef0123456789abcdef01234567".into(),
                },
            ))),
        ),
    ];
    for (method, code) in codes {
        assert_eq!(code, ErrorCode::NotFound, "{method}");
    }
    let code = api_code(block_on(
        client.set_default_model(SetDefaultModelRequest { model_id: id() }),
    ));
    assert_eq!(code, ErrorCode::UnknownModel);
    let code = api_code(block_on(client.set_my_default_model(
        SetMyDefaultModelRequest {
            model_id: Some(id()),
        },
    )));
    assert_eq!(code, ErrorCode::UnknownModel);
    // Deleting is idempotent.
    block_on(client.delete_chat(id())).unwrap();
    block_on(client.delete_repository(id())).unwrap();
    block_on(client.delete_llm_provider(id())).unwrap();
    block_on(client.delete_llm_model(id())).unwrap();

    // Admins may use http and private hosts, so this fails only when connecting to the remote.
    let code = api_code(block_on(client.create_repository(
        CreateRepositoryRequest {
            name: "docs".into(),
            description: None,
            remote: Some(RemoteSettings {
                url: "http://127.0.0.1:1/docs.git".into(),
                branch: "main".into(),
                poll_interval_seconds: 3600,
                token: None,
            }),
            allow_commits: false,
        },
    )));
    assert_eq!(code, ErrorCode::RemoteUnreachable);
}

/// Collects the events of a message until `done` and returns its final state.
fn wait_for_answer(client: &Client, chat_id: Uuid, message_id: Uuid) -> MessageDto {
    let events = block_on(client.message_events(chat_id, message_id)).unwrap();
    let events: Vec<MessageEvent> = block_on(events.collect());
    match events.into_iter().last() {
        Some(MessageEvent::Done { message }) => message,
        Some(MessageEvent::Error { error }) => panic!("the stream failed: {error:?}"),
        _ => panic!("the stream ended without done"),
    }
}

/// What the app does for a local account: [`start_local`], [`Client::local`], the login of the
/// local admin, and the features that work without a git remote, with answers from a mock LLM.
#[test]
fn local_instance() {
    let dir = tempfile::tempdir().unwrap();
    let password = generate_secret();
    let local = block_on(start_local(LocalConfig {
        data_dir: dir.path().join("data").to_str().unwrap().into(),
        token_encryption_key: generate_secret(),
        admin_password: password.clone(),
    }))
    .unwrap();
    let client = &Client::local(&local, None);
    client.set_accept_language(Some("de-CH, en;q=0.8".into()));
    let response = block_on(client.login(LoginRequest {
        user_name_or_email: local_admin_user_name(),
        password: password.clone(),
    }))
    .unwrap();
    assert!(!response.user.must_change_password);

    // The own account.
    block_on(client.set_locale(SetLocaleRequest {
        locale: Some("de-CH".into()),
    }))
    .unwrap();
    block_on(client.update_profile(UpdateProfileRequest {
        full_name: Some("Ada Lovelace".into()),
        first_name: Some("Ada".into()),
        about: None,
    }))
    .unwrap();
    block_on(client.set_my_auto_commit(SetAutoCommitRequest { auto_commit: true })).unwrap();
    let me = block_on(client.update_identity(UpdateIdentityRequest {
        user_name: "ada".into(),
        email: Some("ada@example.com".into()),
    }))
    .unwrap();
    assert_eq!(me.user_name, "ada");
    assert_eq!(me.locale.as_deref(), Some("de-CH"));
    assert_eq!(me.first_name.as_deref(), Some("Ada"));
    assert!(me.auto_commit);
    // The app has to log in with the new name from now on.
    let renamed = Client::local(&local, None);
    login(&renamed, "ada", &password).unwrap();
    let name = local_admin_user_name();
    assert_eq!(
        api_code(login(&renamed, &name, &password)),
        ErrorCode::Unauthorized
    );

    // A provider on the mock LLM, with a model from its list.
    let llm = MockLlm::start(vec![
        MockResponse {
            sse: anthropic(
                None,
                Some(("toolu_1", "read_attachment", json!({"attachment": 1}))),
                false,
            ),
            gate: None,
            stall: false,
        },
        MockResponse {
            sse: anthropic(Some("It says hello."), None, false),
            gate: None,
            stall: false,
        },
        MockResponse {
            sse: anthropic(Some("Let me"), None, true),
            gate: None,
            stall: true,
        },
        MockResponse {
            sse: anthropic(Some("Nothing else."), None, false),
            gate: None,
            stall: false,
        },
    ]);
    let provider = block_on(client.create_llm_provider(CreateLlmProviderRequest {
        name: "Mock".into(),
        api_format: LlmApiFormat::Anthropic,
        base_url: Some(llm.base_url.clone()),
        api_key: None,
        currency: Some("EUR".into()),
    }))
    .unwrap();
    let remote = block_on(client.list_remote_models(provider.id)).unwrap();
    assert_eq!(remote.len(), 1);
    assert_eq!(remote[0].api_name, MOCK_MODEL);
    assert_eq!(remote[0].display_name.as_deref(), Some("Mock Model"));
    let request = |price: Option<&str>| LlmModelRequest {
        api_name: remote[0].api_name.clone(),
        display_name: remote[0].display_name.clone(),
        max_output_tokens: None,
        input_price: price.map(str::to_owned),
        output_price: price.map(str::to_owned),
        cache_read_price: None,
        cache_write_price: None,
    };
    let model = block_on(client.create_llm_model(provider.id, request(None))).unwrap();
    let model = block_on(client.update_llm_model(model.id, request(Some("1.5")))).unwrap();
    assert_eq!(model.input_price.as_deref(), Some("1.5"));
    block_on(client.set_my_default_model(SetMyDefaultModelRequest {
        model_id: Some(model.id),
    }))
    .unwrap();
    assert_eq!(
        block_on(client.me()).unwrap().default_model_id,
        Some(model.id)
    );

    // A chat whose answer reads an attachment, and a second answer, cancelled and retried.
    let attachment = block_on(client.upload_attachment(
        "notes.txt".into(),
        Some("text/plain".into()),
        b"hello\n".to_vec(),
    ))
    .unwrap();
    let chat = block_on(client.create_chat(CreateChatRequest {
        content: "What do my notes say?".into(),
        attachment_id: Some(attachment.id),
        all_repositories: true,
        repository_ids: None,
        title: None,
        model_id: None,
        temporary: false,
    }))
    .unwrap();
    let chat_id = chat.chat.id;
    assert_eq!(chat.chat.title, "What do my notes say?");
    let answer = wait_for_answer(client, chat_id, chat.messages[1].id);
    assert_eq!(answer.status, MessageStatus::Completed);
    assert_eq!(answer.content, "It says hello.");
    assert_eq!(answer.model_id, Some(model.id));
    assert_eq!(answer.cost.as_ref().unwrap().currency, "EUR");
    let tool_call = block_on(client.get_tool_call(chat_id, answer.tool_calls[0].id)).unwrap();
    assert_eq!(tool_call.summary.name, "read_attachment");
    assert!(matches!(
        tool_call.summary.status,
        ToolCallStatus::Completed
    ));
    assert_eq!(tool_call.summary.input, r#"{"attachment":1}"#);
    assert!(tool_call.output.unwrap().contains("hello"));

    let messages = block_on(client.send_message(
        chat_id,
        SendMessageRequest {
            content: "Anything else?".into(),
            attachment_id: None,
        },
    ))
    .unwrap();
    // Cancelled once the model started answering, so the retry gets the next response.
    let mut events = block_on(client.message_events(chat_id, messages[1].id)).unwrap();
    loop {
        match block_on(events.next()) {
            Some(MessageEvent::ContentDelta { .. }) => break,
            Some(MessageEvent::Snapshot { message }) if !message.content.is_empty() => break,
            Some(MessageEvent::Snapshot { .. }) => {}
            _ => panic!("expected the answer to start"),
        }
    }
    block_on(client.cancel_message(chat_id, messages[1].id)).unwrap();
    let answer = match block_on(events.collect::<Vec<_>>()).pop() {
        Some(MessageEvent::Done { message }) => message,
        _ => panic!("the stream ended without done"),
    };
    assert_eq!(answer.status, MessageStatus::Cancelled);
    assert_eq!(answer.content, "Let me");
    let retried = block_on(client.retry_message(chat_id, answer.id)).unwrap();
    assert_eq!(retried.status, MessageStatus::Generating);
    let answer = wait_for_answer(client, chat_id, retried.id);
    assert_eq!(answer.content, "Nothing else.");

    let updated = block_on(client.update_chat(
        chat_id,
        UpdateChatRequest {
            title: "Notes".into(),
            model_id: Some(model.id),
        },
    ))
    .unwrap();
    assert_eq!(updated.model_id, Some(model.id));
    let chat = block_on(client.get_chat(chat_id)).unwrap();
    assert_eq!(chat.chat.title, "Notes");
    assert_eq!(chat.messages.len(), 4);
    let page = block_on(client.list_chats(None, None)).unwrap();
    assert_eq!(page.items.len(), 1);
    block_on(client.delete_chat(chat_id)).unwrap();
    assert_eq!(
        api_code(block_on(client.get_chat(chat_id))),
        ErrorCode::NotFound
    );

    // Repositories need a git remote, so there are none.
    assert!(block_on(client.list_repositories()).unwrap().is_empty());

    // Users: created, changed, given a new password, and deleted.
    let bob = block_on(client.register_user(RegisterRequest {
        user_name: "bob".into(),
        email: None,
        password: PASSWORD.into(),
        must_change_password: false,
    }))
    .unwrap();
    let bob = block_on(client.update_user(
        bob.id,
        UpdateUserRequest {
            user_name: "robert".into(),
            email: Some("robert@example.com".into()),
            can_login: true,
            can_manage_repositories: false,
            can_change_identity: false,
            must_change_password: false,
        },
    ))
    .unwrap();
    assert!(!bob.can_manage_repositories);
    let bob = block_on(client.reset_password(
        bob.id,
        ResetPasswordRequest {
            password: "a new password".into(),
            must_change_password: true,
        },
    ))
    .unwrap();
    assert!(bob.must_change_password);
    let other = Client::local(&local, None);
    let response = block_on(other.login(LoginRequest {
        user_name_or_email: "robert@example.com".into(),
        password: "a new password".into(),
    }))
    .unwrap();
    assert!(response.user.must_change_password);
    block_on(client.delete_user(DeleteUserRequest { user_id: bob.id })).unwrap();
    assert_eq!(api_code(block_on(other.me())), ErrorCode::Unauthorized);
    assert_eq!(block_on(client.list_users()).unwrap().len(), 1);

    // The model and the provider.
    block_on(client.delete_llm_model(model.id)).unwrap();
    assert!(block_on(client.list_models()).unwrap().is_empty());
    block_on(client.delete_llm_provider(provider.id)).unwrap();
    assert!(block_on(client.list_llm_providers()).unwrap().is_empty());

    block_on(local.shutdown());
}
