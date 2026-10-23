use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::extraction::{
    ConvertingDocumentDto, DocumentFilter, ExtractionDocumentDto, ExtractionDocumentPageDto,
    ExtractionOverviewDto, ExtractionPauseDto, ListExtractionDocumentsQuery, RepositoryDocumentDto,
    RetryDocumentRequest,
};
use crate::middleware::auth::AuthenticatedUser;
use crate::model::repository_document::DocumentSource;
use crate::repository;
use crate::service;
use crate::util::extract::{JsonBody, QueryParams};
use crate::util::validation::ValidationError;
use axum::extract::State;
use axum::http::StatusCode;
use axum::{Extension, Json};

const DEFAULT_PAGE_SIZE: i64 = 25;
const MAX_PAGE_SIZE: i64 = 100;

/// What the document conversion is doing, and how far it is.
pub(crate) async fn get_extraction_overview(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
) -> Result<Json<ExtractionOverviewDto>, AppError> {
    // Before the extractions, so a document converted in between is not counted as waiting.
    let status = state.extractor.status();
    let totals = repository::document::count_extractions(
        &state.db,
        &status.extractor,
        &status.skipped_blobs(),
    )
    .await?;
    let converting = match status.converting {
        Some(converting) => Some(match converting.source {
            DocumentSource::Repository {
                repository_id,
                path,
            } => ConvertingDocumentDto {
                repository: repository::repository::get_repository_label(
                    &state.db,
                    repository_id,
                    auth.user_id,
                )
                .await?
                .map(Into::into),
                path,
                attachment: false,
                started_at: converting.started_at,
            },
            DocumentSource::Attachment { file_name, .. } => ConvertingDocumentDto {
                repository: None,
                path: file_name,
                attachment: true,
                started_at: converting.started_at,
            },
        }),
        None => None,
    };
    Ok(Json(ExtractionOverviewDto {
        extractor: status.extractor,
        converting,
        paused: status.paused.map(|pause| ExtractionPauseDto {
            until: pause.until,
            reason: pause.reason,
        }),
        totals: totals.into(),
    }))
}

/// The documents of all repositories, by repository name and path.
pub(crate) async fn list_extraction_documents(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    QueryParams(query): QueryParams<ListExtractionDocumentsQuery>,
) -> Result<Json<ExtractionDocumentPageDto>, AppError> {
    let filter = query.filter.unwrap_or(DocumentFilter::All);
    let offset = query.offset.unwrap_or(0);
    let limit = query.limit.unwrap_or(DEFAULT_PAGE_SIZE);
    if offset < 0 {
        return Err(ValidationError("`offset` must not be negative".to_string()).into());
    }
    if !(1..=MAX_PAGE_SIZE).contains(&limit) {
        return Err(
            ValidationError(format!("`limit` must be between 1 and {MAX_PAGE_SIZE}")).into(),
        );
    }

    // Before the extractions, so a document converted in between is not shown as waiting.
    let status = state.extractor.status();
    let documents = repository::document::list_all_documents(
        &state.db,
        &status.extractor,
        filter,
        auth.user_id,
        offset,
        limit,
    )
    .await?;
    let total =
        repository::document::count_all_documents(&state.db, &status.extractor, filter).await?;
    Ok(Json(ExtractionDocumentPageDto {
        items: documents
            .into_iter()
            .map(|d| ExtractionDocumentDto {
                repository: d.repository.into(),
                blob_oid: d.document.blob_oid.clone(),
                document: RepositoryDocumentDto::new(d.document, &status),
            })
            .collect(),
        total,
    }))
}

/// Converts the document again if it failed or was skipped, else does nothing.
pub(crate) async fn retry_document(
    State(state): State<AppState>,
    JsonBody(payload): JsonBody<RetryDocumentRequest>,
) -> Result<StatusCode, AppError> {
    if !repository::document::document_exists(&state.db, &payload.blob_oid).await? {
        return Err(AppError::NotFound);
    }
    service::extraction::retry(&state, &payload.blob_oid).await?;
    Ok(StatusCode::NO_CONTENT)
}
