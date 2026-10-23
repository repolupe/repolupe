//! The documents of repositories and their conversion to Markdown.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize, sqlx::Type)]
#[sqlx(rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DocumentExtractionStatus {
    Completed,
    Failed,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// Why a queued document is left out for a while before it is tried again, see
/// `service/extraction.rs`.
#[derive(Clone, Copy, Eq, PartialEq, Debug, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DocumentSkipReason {
    /// The file is stored with Git LFS, and its object was not downloaded by the sync.
    LfsObjectMissing,
    /// The file could not be read, or the result not stored. The details are only logged.
    Error,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

#[derive(Serialize, Deserialize)]
pub struct RepositoryDocumentsDto {
    /// By path.
    pub documents: Vec<RepositoryDocumentDto>,
    /// Set while the conversions wait for the OCR service, which is unavailable.
    pub paused_until: Option<DateTime<Utc>>,
}

#[derive(Serialize, Deserialize)]
pub struct RepositoryDocumentDto {
    pub path: String,
    /// What the model reads, `null` until the document is converted for the first time.
    pub extraction: Option<DocumentExtractionDto>,
    /// `null` once the document is converted with the current settings. Until then, the
    /// model reads `extraction`, if any, which was made with earlier settings.
    pub conversion: Option<DocumentConversionDto>,
}

#[derive(Serialize, Deserialize)]
pub struct DocumentExtractionDto {
    pub status: DocumentExtractionStatus,
    /// Whether pages were recognized with OCR, so the text may contain errors. For `COMPLETED`.
    pub ocr: Option<bool>,
    /// Why the document could not be converted, as the model sees it. For `FAILED`.
    pub error: Option<String>,
    pub extracted_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct DocumentConversionDto {
    pub status: DocumentConversionStatus,
    /// For `CONVERTING`.
    pub started_at: Option<DateTime<Utc>>,
    /// For `SKIPPED`.
    pub skip_reason: Option<DocumentSkipReason>,
    /// When a `SKIPPED` document is tried again.
    pub retry_at: Option<DateTime<Utc>>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DocumentConversionStatus {
    Waiting,
    Converting,
    /// Left out for a while, see `skip_reason`.
    Skipped,
    /// A value this version does not know, from a newer server. Never sent by the server.
    #[serde(other)]
    Unknown,
}

/// What the document conversion is doing across all repositories. Only for admins.
#[derive(Serialize, Deserialize)]
pub struct ExtractionOverviewDto {
    /// Identifies the current settings. Documents converted with others are converted again.
    pub extractor: String,
    pub converting: Option<ConvertingDocumentDto>,
    pub paused: Option<ExtractionPauseDto>,
    pub totals: ExtractionTotalsDto,
}

#[derive(Serialize, Deserialize)]
pub struct ConvertingDocumentDto {
    /// `null` for an attachment, or if the repository was deleted meanwhile.
    pub repository: Option<RepositoryLabelDto>,
    /// For an attachment, its file name.
    pub path: String,
    /// Whether it is a file attached to a chat, not one in a repository.
    pub attachment: bool,
    pub started_at: DateTime<Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct ExtractionPauseDto {
    pub until: DateTime<Utc>,
    /// The error of the OCR service.
    pub reason: String,
}

/// A blob counts once for each repository and path containing it.
#[derive(Serialize, Deserialize)]
pub struct ExtractionTotalsDto {
    pub documents: i64,
    /// The counts below add up to `documents`. With the current settings.
    pub converted: i64,
    /// With the current settings.
    pub failed: i64,
    /// Waiting to be converted with the current settings, or being converted.
    pub waiting: i64,
    /// Left out for a while, e.g. since the LFS object was not downloaded.
    pub skipped: i64,
}

/// A repository of any user, in admin views.
#[derive(Serialize, Deserialize)]
pub struct RepositoryLabelDto {
    pub id: Uuid,
    pub name: String,
    pub owner_name: String,
    /// Whether the admin owns the repository or it is shared with them, so they can open it.
    pub readable: bool,
}

#[derive(Serialize, Deserialize)]
pub struct ExtractionDocumentPageDto {
    pub items: Vec<ExtractionDocumentDto>,
    /// Of all pages.
    pub total: i64,
}

/// A document of any repository, for admins.
#[derive(Serialize, Deserialize)]
pub struct ExtractionDocumentDto {
    pub repository: RepositoryLabelDto,
    /// Identifies the content, see `POST /api/v1/document-extraction/retry`.
    pub blob_oid: String,
    #[serde(flatten)]
    pub document: RepositoryDocumentDto,
}

/// Which documents to list, by their extraction with the current settings.
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DocumentFilter {
    All,
    Converted,
    Failed,
    /// Not converted with the current settings yet.
    Pending,
}

impl DocumentFilter {
    /// As compared in SQL.
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Self::All => "ALL",
            Self::Converted => "CONVERTED",
            Self::Failed => "FAILED",
            Self::Pending => "PENDING",
        }
    }
}

#[derive(Serialize, Deserialize)]
pub struct ListExtractionDocumentsQuery {
    pub filter: Option<DocumentFilter>,
    pub offset: Option<i64>,
    pub limit: Option<i64>,
}

#[derive(Serialize, Deserialize)]
pub struct RetryDocumentRequest {
    pub blob_oid: String,
}
