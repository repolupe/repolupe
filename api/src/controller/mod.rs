//! The handlers, grouped like the routes, and the conversions of the models to the DTOs in
//! [`crate::dto`].

pub(crate) mod attachment;
pub(crate) mod auth;
pub(crate) mod chat;
pub(crate) mod config;
pub(crate) mod debug;
pub(crate) mod extraction;
pub(crate) mod instance;
pub(crate) mod llm;
pub(crate) mod repository;
pub(crate) mod server;
pub(crate) mod user;

use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::attachment::AttachmentDto;
use crate::dto::chat::{
    ChatDto, CostDto, FileMoveDto, MessageDto, ProposedCommitDto, ToolCallDto, ToolCallStatus,
    ToolCallSummaryDto, UsageDto,
};
use crate::dto::extraction::{
    DocumentConversionDto, DocumentConversionStatus, DocumentExtractionDto, ExtractionTotalsDto,
    RepositoryDocumentDto, RepositoryDocumentsDto, RepositoryLabelDto,
};
use crate::dto::llm::{ApiKeyDto, LlmModelDto, LlmProviderDto, ModelDto, RemoteModelDto};
use crate::dto::repository::{
    RemoteSettingsDto, RepositoryDto, RepositoryTokenDto, RepositoryUserDto,
};
use crate::dto::user::UserDto;
use crate::middleware::auth::AuthenticatedUser;
use crate::model;
use crate::model::tool_call::ToolCallSummary;
use crate::repository::repository::StoredToken;
use crate::service;
use crate::service::extraction::{Conversion, ExtractionStatus};
use crate::service::llm::RemoteModel;
use uuid::Uuid;

/// Tokens shorter than this get no hint, since 4 characters would reveal too much of them.
const MIN_TOKEN_LENGTH_FOR_HINT: usize = 16;
const TOKEN_HINT_LENGTH: usize = 4;

/// Encrypts a repository token or an LLM API key, bound to the row `owner_id`.
pub(crate) fn encrypt_token(
    state: &AppState,
    owner_id: Uuid,
    token: &str,
) -> Result<StoredToken, AppError> {
    let encrypted = state
        .token_cipher
        .encrypt(owner_id, token)
        .map_err(|e| AppError::InternalServerError(format!("Failed to encrypt token: {e}")))?;
    let hint = (token.len() >= MIN_TOKEN_LENGTH_FOR_HINT)
        .then(|| token[token.len() - TOKEN_HINT_LENGTH..].to_string());
    Ok(StoredToken { encrypted, hint })
}

impl From<model::user::User> for UserDto {
    fn from(user: model::user::User) -> Self {
        UserDto {
            id: user.id,
            role: user.role,
            user_name: user.user_name,
            email: user.email,
            can_login: user.can_login,
            can_manage_repositories: user.can_manage_repositories,
            can_change_identity: user.can_change_identity,
            must_change_password: user.must_change_password,
            default_model_id: user.default_model_id,
            locale: user.locale,
            auto_commit: user.auto_commit,
            full_name: user.full_name,
            first_name: user.first_name,
            about: user.about,
            created_at: user.created_at,
        }
    }
}

impl RepositoryDto {
    /// As seen by `viewer`, whom it was read for.
    pub(crate) fn new(
        repository: model::repository::Repository,
        viewer: &AuthenticatedUser,
    ) -> Self {
        let is_owner = repository.user_id == viewer.user_id;
        let can_commit = service::commit::can_commit(viewer.can_manage_repositories, &repository);
        let remote = repository.remote().map(|remote| RemoteSettingsDto {
            url: remote.url.to_string(),
            branch: repository.branch.clone(),
            poll_interval_seconds: remote.poll_interval_seconds,
            token: remote
                .token_encrypted
                .is_some()
                .then(|| RepositoryTokenDto {
                    hint: repository.token_hint.clone().filter(|_| is_owner),
                }),
        });
        RepositoryDto {
            id: repository.id,
            owner_id: repository.user_id,
            name: repository.name,
            description: repository.description,
            remote,
            allow_commits: repository.allow_commits,
            can_commit,
            sync_status: repository.sync_status,
            sync_started_at: repository.sync_started_at,
            head_commit_sha: repository.head_commit_sha,
            last_synced_at: repository.last_synced_at,
            git_size: repository.git_size,
            lfs_size: repository.lfs_size,
            last_error: repository.last_error,
            next_sync_at: repository.next_sync_at,
            created_at: repository.created_at,
            updated_at: repository.updated_at,
        }
    }
}

impl From<model::repository::RepositoryUser> for RepositoryUserDto {
    fn from(user: model::repository::RepositoryUser) -> Self {
        RepositoryUserDto {
            user_id: user.user_id,
            user_name: user.user_name,
            email: user.email,
            can_commit: user.can_commit,
            created_at: user.created_at,
        }
    }
}

impl From<model::repository_document::ExtractionTotals> for ExtractionTotalsDto {
    fn from(totals: model::repository_document::ExtractionTotals) -> Self {
        ExtractionTotalsDto {
            documents: totals.documents,
            converted: totals.converted,
            failed: totals.failed,
            waiting: totals.documents - totals.converted - totals.failed - totals.skipped,
            skipped: totals.skipped,
        }
    }
}

impl From<model::repository::RepositoryLabel> for RepositoryLabelDto {
    fn from(label: model::repository::RepositoryLabel) -> Self {
        RepositoryLabelDto {
            id: label.id,
            name: label.name,
            owner_name: label.owner_name,
            readable: label.readable,
        }
    }
}

impl RepositoryDocumentsDto {
    pub(crate) fn new(
        documents: Vec<model::repository_document::ListedDocument>,
        status: &ExtractionStatus,
    ) -> Self {
        RepositoryDocumentsDto {
            documents: documents
                .into_iter()
                .map(|document| RepositoryDocumentDto::new(document, status))
                .collect(),
            paused_until: status.paused.as_ref().map(|pause| pause.until),
        }
    }
}

impl RepositoryDocumentDto {
    pub(crate) fn new(
        document: model::repository_document::ListedDocument,
        status: &ExtractionStatus,
    ) -> Self {
        let conversion = status
            .conversion(
                &document.blob_oid,
                document.extraction.as_ref().map(|e| e.extractor.as_str()),
            )
            .map(DocumentConversionDto::from);
        RepositoryDocumentDto {
            path: document.path,
            extraction: document.extraction.map(|e| DocumentExtractionDto {
                status: e.status,
                ocr: e.ocr,
                error: e.error,
                extracted_at: e.extracted_at,
            }),
            conversion,
        }
    }
}

impl From<Conversion> for DocumentConversionDto {
    fn from(conversion: Conversion) -> Self {
        let (status, started_at, skip_reason, retry_at) = match conversion {
            Conversion::Waiting => (DocumentConversionStatus::Waiting, None, None, None),
            Conversion::Converting { started_at } => (
                DocumentConversionStatus::Converting,
                Some(started_at),
                None,
                None,
            ),
            Conversion::Skipped { reason, until } => (
                DocumentConversionStatus::Skipped,
                None,
                Some(reason),
                Some(until),
            ),
        };
        DocumentConversionDto {
            status,
            started_at,
            skip_reason,
            retry_at,
        }
    }
}

impl LlmProviderDto {
    pub(crate) fn new(
        provider: model::llm_provider::LlmProvider,
        models: Vec<LlmModelDto>,
    ) -> Self {
        let api_key = provider.api_key_encrypted.is_some().then_some(ApiKeyDto {
            hint: provider.api_key_hint,
        });
        LlmProviderDto {
            id: provider.id,
            name: provider.name,
            api_format: provider.api_format,
            base_url: provider.base_url,
            api_key,
            currency: provider.currency,
            models,
            created_at: provider.created_at,
            updated_at: provider.updated_at,
        }
    }
}

impl From<model::llm_model::LlmModel> for LlmModelDto {
    fn from(model: model::llm_model::LlmModel) -> Self {
        LlmModelDto {
            id: model.id,
            provider_id: model.provider_id,
            api_name: model.api_name,
            display_name: model.display_name,
            max_output_tokens: model.max_output_tokens,
            input_price: model.input_price.map(|price| price.0.to_string()),
            output_price: model.output_price.map(|price| price.0.to_string()),
            cache_read_price: model.cache_read_price.map(|price| price.0.to_string()),
            cache_write_price: model.cache_write_price.map(|price| price.0.to_string()),
            is_default: model.is_default,
            created_at: model.created_at,
            updated_at: model.updated_at,
        }
    }
}

impl From<model::llm_model::AvailableModel> for ModelDto {
    fn from(model: model::llm_model::AvailableModel) -> Self {
        ModelDto {
            id: model.id,
            display_name: model.display_name,
            provider_id: model.provider_id,
            provider_name: model.provider_name,
            is_default: model.is_default,
        }
    }
}

impl From<RemoteModel> for RemoteModelDto {
    fn from(model: RemoteModel) -> Self {
        RemoteModelDto {
            api_name: model.api_name,
            display_name: model.display_name,
        }
    }
}

impl From<model::chat::Chat> for ChatDto {
    fn from(chat: model::chat::Chat) -> Self {
        ChatDto {
            id: chat.id,
            title: chat.title,
            all_repositories: chat.all_repositories,
            repository_ids: chat.repository_ids.0,
            model_id: chat.model_id,
            temporary: chat.temporary,
            created_at: chat.created_at,
            updated_at: chat.updated_at,
        }
    }
}

impl From<model::attachment::Attachment> for AttachmentDto {
    fn from(attachment: model::attachment::Attachment) -> Self {
        Self {
            id: attachment.id,
            number: attachment.number,
            file_name: attachment.file_name,
            content_type: attachment.content_type,
            size: attachment.size,
            created_at: attachment.created_at,
        }
    }
}

impl MessageDto {
    pub(crate) fn new(message: model::message::Message, tool_calls: Vec<ToolCallSummary>) -> Self {
        let usage = match (
            message.input_tokens,
            message.output_tokens,
            message.cache_read_tokens,
            message.cache_write_tokens,
        ) {
            (Some(input), Some(output), Some(cache_read), Some(cache_write)) => Some(UsageDto {
                input_tokens: input,
                output_tokens: output,
                cache_read_tokens: cache_read,
                cache_write_tokens: cache_write,
            }),
            _ => None,
        };
        let cost = message
            .cost
            .zip(message.cost_currency)
            .map(|(amount, currency)| CostDto {
                amount: amount.0.to_string(),
                currency,
            });
        MessageDto {
            id: message.id,
            role: message.role,
            content: message.content,
            status: message.status,
            error: message.error,
            model_id: message.model_id,
            tool_calls: tool_calls.into_iter().map(Into::into).collect(),
            created_at: message.created_at,
            finished_at: message.finished_at,
            usage,
            cost,
            attachment: None,
        }
    }

    pub(crate) fn with_attachment(
        mut self,
        attachment: Option<model::attachment::Attachment>,
    ) -> Self {
        self.attachment = attachment.map(Into::into);
        self
    }
}

impl ToolCallStatus {
    pub(crate) fn new(finished: bool, is_error: bool) -> Self {
        match (finished, is_error) {
            (false, _) => ToolCallStatus::Running,
            (true, false) => ToolCallStatus::Completed,
            (true, true) => ToolCallStatus::Failed,
        }
    }
}

impl From<ToolCallSummary> for ToolCallSummaryDto {
    fn from(tool_call: ToolCallSummary) -> Self {
        ToolCallSummaryDto {
            id: tool_call.id,
            name: tool_call.name,
            input: tool_call.input.to_string(),
            repository_id: tool_call.repository_id,
            commit_sha: tool_call.commit_sha,
            status: ToolCallStatus::new(tool_call.finished, tool_call.is_error),
            created_at: tool_call.created_at,
        }
    }
}

impl ProposedCommitDto {
    pub(crate) fn new(change: model::tool_call::ProposedCommit, can_commit: bool) -> Self {
        let (path, moves) = match change.changed {
            model::tool_call::ChangedPaths::File(path) => (Some(path), None),
            model::tool_call::ChangedPaths::Moves(moves) => (
                None,
                Some(
                    moves
                        .into_iter()
                        .map(|m| FileMoveDto {
                            from: m.from,
                            to: m.to,
                        })
                        .collect(),
                ),
            ),
        };
        Self {
            path,
            moves,
            proposed_commit: change.proposed_commit,
            status: change.status,
            pushed_commit: change.pushed_commit,
            pushed_branch: change.pushed_branch,
            error: change.error,
            committed_at: change.committed_at,
            can_commit,
        }
    }
}

impl From<model::tool_call::ToolCall> for ToolCallDto {
    fn from(tool_call: model::tool_call::ToolCall) -> Self {
        ToolCallDto {
            summary: ToolCallSummaryDto {
                id: tool_call.id,
                name: tool_call.name,
                input: tool_call.input.to_string(),
                repository_id: tool_call.repository_id,
                commit_sha: tool_call.commit_sha,
                status: ToolCallStatus::new(tool_call.output.is_some(), tool_call.is_error),
                created_at: tool_call.created_at,
            },
            output: tool_call.output,
        }
    }
}
