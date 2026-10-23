use crate::dto::extraction::DocumentExtractionStatus;
use crate::model::repository::RepositoryLabel;
use chrono::{DateTime, Utc};
use uuid::Uuid;

/// A document in the synced commit of a repository, see `service/extraction.rs`.
pub(crate) struct RepositoryDocument {
    pub(crate) path: String,
    pub(crate) blob_oid: String,
}

/// A document waiting to be converted.
pub(crate) struct QueuedDocument {
    pub(crate) source: DocumentSource,
    pub(crate) blob_oid: String,
}

/// Where a queued document is read from.
#[derive(Clone)]
pub(crate) enum DocumentSource {
    /// One of the repositories that contain it.
    Repository { repository_id: Uuid, path: String },
    /// A file attached to a chat, or about to be.
    Attachment {
        attachment_id: Uuid,
        file_name: String,
        /// One of the supported types, see `service/extraction.rs`.
        content_type: String,
    },
}

/// A document in the synced commit of a repository, with the extraction the tools read, if any.
pub(crate) struct ListedDocument {
    pub(crate) path: String,
    pub(crate) blob_oid: String,
    pub(crate) extraction: Option<ExtractionSummary>,
}

/// A stored extraction without its Markdown.
pub(crate) struct ExtractionSummary {
    pub(crate) status: DocumentExtractionStatus,
    /// For `COMPLETED`.
    pub(crate) ocr: Option<bool>,
    /// For `FAILED`.
    pub(crate) error: Option<String>,
    /// See `extractor_id` in `service/extraction.rs`.
    pub(crate) extractor: String,
    pub(crate) extracted_at: DateTime<Utc>,
}

/// How far the conversion of all documents is, see `service/extraction.rs`. A blob counts
/// once for each repository and path containing it.
pub(crate) struct ExtractionTotals {
    pub(crate) documents: i64,
    /// With the current settings.
    pub(crate) converted: i64,
    /// With the current settings.
    pub(crate) failed: i64,
    /// Not converted with the current settings and left out for now.
    pub(crate) skipped: i64,
}

/// A document in any repository, see [`ListedDocument`].
pub(crate) struct RepositoryListedDocument {
    pub(crate) repository: RepositoryLabel,
    pub(crate) document: ListedDocument,
}
