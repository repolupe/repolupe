//! Converts documents in synced commits to Markdown with xberg, so the tools can read them.
//! With an OCR engine configured, pages that look like scans are recognized with it, even when
//! the scanner stored its own (often poor) OCR text in them: Tesseract and PaddleOCR recognize
//! them within xberg, while with Mistral, xberg only finds them and documents with any are converted by
//! Mistral as a whole (see [`crate::service::mistral_ocr`]). Only PDFs are supported for now, see [`FORMATS`].
//!
//! Extractions are stored by git blob in `document_extractions`, so a document is extracted
//! once no matter how many commits and repositories contain it. For LFS files the blob is the
//! pointer file, which identifies the content as well. A sync records the documents in its
//! commit in `repository_documents` without converting them, so the commit can be used right
//! away. The documents there without an extraction made with the current settings (see
//! [`Settings::current`]) form the queue, which [`spawn_extraction_task`] works through one document
//! at a time, so each one can be read as soon as it is converted. Until then, the extraction made
//! with earlier settings, if any, is still read. Extractions no repository refers to are removed
//! by [`remove_unused`].
//!
//! Attachments of a supported type are converted too, as soon as they are uploaded and before
//! the documents of repositories, since someone is waiting for them in a chat. Their blob is the
//! one the file gets when the model saves it to a repository (see
//! [`crate::service::tools::SAVE_ATTACHMENT`]), so it is not converted again after the next
//! sync. On a path tracked with LFS, the repository has a pointer instead, whose blob differs:
//! before converting a document, the extraction of its content's blob is looked for and copied
//! if there is one.

mod convert;
mod queue;
mod settings;

pub(crate) use queue::{Conversion, ExtractionStatus, spawn_extraction_task};

use crate::config::error::AppError;
use crate::config::init::OcrConfig;
use crate::config::state::{AppState, DatabasePool};
use crate::model::repository_document::RepositoryDocument;
use crate::repository;
use crate::service::mirror::TreeBlob;
use crate::service::mistral_ocr::MistralOcr;
use chrono::Utc;
use queue::QueueState;
use settings::Settings;
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;
use tokio::sync::{Notify, Semaphore};

/// Extensions of the supported documents, with their MIME type.
const FORMATS: &[(&str, &str)] = &[("pdf", "application/pdf")];

/// Larger documents are not extracted.
const MAX_DOCUMENT_SIZE: u64 = 100 * 1024 * 1024;

/// Unused extractions are kept this long after they were made, so a document that is added
/// back soon, e.g. by a reverted commit, is not converted again.
const UNUSED_GRACE_PERIOD: Duration = Duration::from_hours(1);

/// A scanned invoice without text, recognized by [`check_ocr`].
const SAMPLE_SCAN: &[u8] = include_bytes!("sample_scan.pdf");
/// Text in [`SAMPLE_SCAN`], the invoice number.
const SAMPLE_SCAN_TEXT: &str = "7731";

/// Whether the file at `path` is a document that is converted to Markdown.
pub(crate) fn is_document(path: &str) -> bool {
    mime_type(path).is_some()
}

pub(crate) fn mime_type(path: &str) -> Option<&'static str> {
    let (_, extension) = path.rsplit_once('.')?;
    FORMATS
        .iter()
        .find(|(e, _)| e.eq_ignore_ascii_case(extension))
        .map(|(_, mime_type)| *mime_type)
}

/// `content_type` if it is the MIME type of a document that is converted to Markdown.
pub(crate) fn document_type(content_type: &str) -> Option<&'static str> {
    FORMATS
        .iter()
        .find(|(_, mime_type)| *mime_type == content_type)
        .map(|(_, mime_type)| *mime_type)
}

/// Recognizes [`SAMPLE_SCAN`] with `ocr`, which makes the engine download what it is missing
/// (see [`crate::prepare_ocr`]), and checks that its text was found.
pub(crate) async fn check_ocr(ocr: &OcrConfig) -> Result<(), String> {
    let document = RepositoryDocument {
        path: "sample_scan.pdf".to_string(),
        blob_oid: "0".repeat(40),
    };
    let extractor = DocumentExtractor::new(Some(ocr), None);
    let converted = extractor
        .extract(
            &extractor.settings(),
            &document,
            SAMPLE_SCAN.to_vec(),
            "application/pdf",
        )
        .await
        .map_err(|e| e.to_string())?
        .result
        // xberg only logs why OCR failed, e.g. a failed model download, and returns no text.
        .map_err(|e| format!("recognizing a sample scan failed: {e}"))?;
    let markdown = converted.markdown;
    if !markdown.contains(SAMPLE_SCAN_TEXT) {
        return Err(format!(
            "a sample scan was recognized as {markdown:?}, which lacks {SAMPLE_SCAN_TEXT:?}"
        ));
    }
    Ok(())
}

/// Removes the extractions no repository refers to anymore.
pub(crate) async fn remove_unused(db: &DatabasePool) -> Result<(), AppError> {
    let cutoff = Utc::now() - UNUSED_GRACE_PERIOD;
    let removed = repository::document::delete_unused_extractions(db, cutoff).await?;
    if removed > 0 {
        tracing::info!("Removed {removed} unused document extractions");
    }
    Ok(())
}

/// Converts the document with `blob_oid` again right away if it failed with the current
/// settings or was skipped (see [`queue::SKIP_DURATION`]). Returns whether it did.
pub(crate) async fn retry(state: &AppState, blob_oid: &str) -> Result<bool, AppError> {
    let settings = state.extractor.settings();
    let failed =
        repository::document::delete_failed_extraction(&state.db, blob_oid, &settings.current)
            .await?;
    let skipped = state.extractor.unskip(blob_oid);
    if failed || skipped {
        tracing::info!("Converting {blob_oid} again");
        state.extractor.notify_queued();
    }
    Ok(failed || skipped)
}

/// The documents among `blobs`, the blobs of a commit, which a finished sync records, see [`spawn_extraction_task`].
pub(crate) fn list_documents(blobs: &[TreeBlob]) -> Vec<RepositoryDocument> {
    blobs
        .iter()
        .filter(|blob| is_document(&blob.path))
        .map(|blob| RepositoryDocument {
            path: blob.path.clone(),
            blob_oid: blob.oid.clone(),
        })
        .collect()
}

/// Converts one document at a time with xberg, so share one instance. More would only compete
/// for the cores: xberg already spreads one document over them, and OCR is limited
/// process-wide anyway (PaddleOCR runs one inference at a time on all cores, Tesseract
/// recognizes several pages at once). Mistral is called after xberg's part, without the permit.
///
/// The conversion is implemented in [`convert`], the queue and its status in [`queue`].
pub(crate) struct DocumentExtractor {
    /// Held by a timed out conversion too, until it ends.
    permit: Arc<Semaphore>,
    /// Set with `OCR_API_KEY_MISTRAL`, which [`crate::config::init::OcrEngine::Mistral`] requires.
    mistral: Option<MistralOcr>,
    settings: RwLock<Arc<Settings>>,
    /// Wakes [`spawn_extraction_task`] when documents may have been queued.
    queued: Notify,
    /// Notified after each document [`spawn_extraction_task`] took from the queue, see
    /// [`Self::wait_for_extraction`].
    converted: Notify,
    /// Never held across an `await`.
    queue: Mutex<QueueState>,
}

impl DocumentExtractor {
    pub(crate) fn new(ocr: Option<&OcrConfig>, mistral: Option<MistralOcr>) -> Self {
        Self {
            permit: Arc::new(Semaphore::new(1)),
            mistral,
            settings: RwLock::new(Arc::new(Settings::new(ocr))),
            queued: Notify::new(),
            converted: Notify::new(),
            queue: Mutex::default(),
        }
    }

    fn settings(&self) -> Arc<Settings> {
        self.settings.read().unwrap().clone()
    }

    /// Used by the conversions started from now on. Queues every document converted with other
    /// settings.
    pub(crate) fn set_ocr(&self, ocr: Option<&OcrConfig>) {
        *self.settings.write().unwrap() = Arc::new(Settings::new(ocr));
        self.notify_queued();
    }

    /// Wakes the queue, e.g. after a sync recorded new documents.
    pub(crate) fn notify_queued(&self) {
        self.queued.notify_one();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::init::OcrEngine;

    pub(super) fn ocr(engine: OcrEngine, languages: &[&str]) -> OcrConfig {
        OcrConfig {
            engine,
            languages: languages.iter().map(|l| l.to_string()).collect(),
            scan_confidence: 0.5,
        }
    }

    #[test]
    fn matches_documents() {
        assert!(is_document("docs/manual.pdf"));
        assert!(is_document("Manual.PDF"));
        assert!(!is_document("pdf"));
        assert!(!is_document("docs/manual.pdf.txt"));
    }
}
