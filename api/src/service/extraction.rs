//! Converts documents in synced commits to Markdown with xberg, so the tools can read them.
//! With an OCR engine configured, pages that look like scans are recognized with it, even when
//! the scanner stored its own (often poor) OCR text in them: Tesseract and PaddleOCR recognize
//! them within xberg, while with Mistral, xberg only finds them and documents with any are converted by
//! Mistral as a whole (see [`mistral_ocr`]). Only PDFs are supported for now, see [`FORMATS`].
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

use crate::config::error::AppError;
use crate::config::init::{OcrConfig, OcrEngine};
use crate::config::state::{AppState, DatabasePool};
use crate::dto::extraction::DocumentSkipReason;
use crate::model::document_extraction::DocumentExtraction;
use crate::model::repository_document::{DocumentSource, QueuedDocument, RepositoryDocument};
use crate::repository;
use crate::service::mirror::{self, Content, TreeBlob};
use crate::service::mistral_ocr::{self, MistralError, MistralOcr};
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};
use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// Identifies how the stored extractions were made, together with the OCR settings (see
/// [`extractor_id`]). The xberg version is the one pinned in `Cargo.toml` (see `build.rs`).
/// Append a revision (e.g. `/config-2`) when [`extraction_config`] changes, so the documents are
/// extracted again.
const EXTRACTOR: &str = concat!("xberg-", env!("XBERG_VERSION"));

/// Identifies the extractions Mistral made. They depend neither on xberg nor on the other OCR
/// settings, so they are kept while Mistral is the OCR engine (see [`Settings::current`]), and
/// a new xberg version only converts the documents again that xberg converted.
const MISTRAL_EXTRACTOR: &str = mistral_ocr::MODEL;

/// Extensions of the supported documents, with their MIME type.
const FORMATS: &[(&str, &str)] = &[("pdf", "application/pdf")];

/// Larger documents are not extracted.
const MAX_DOCUMENT_SIZE: u64 = 100 * 1024 * 1024;

const EXTRACTION_TIMEOUT: Duration = Duration::from_mins(10);

/// Shown to the model when a document cannot be converted, the details are only logged.
const FAILED: &str = "The file could not be converted, it may be damaged or encrypted";
/// Shown to the model when a document has no text, e.g. a scan without OCR.
const NO_TEXT: &str = "The file contains no text";
const NO_TEXT_WITHOUT_OCR: &str =
    "The file contains no text. It may be a scan, and text recognition (OCR) is turned off";
/// Unused extractions are kept this long after they were made, so a document that is added
/// back soon, e.g. by a reverted commit, is not converted again.
const UNUSED_GRACE_PERIOD: Duration = Duration::from_hours(1);

/// How often the queue is checked without being notified, e.g. for skipped documents.
const QUEUE_POLL_INTERVAL: Duration = Duration::from_mins(1);
/// How long a document is skipped when it cannot be read, e.g. its content was not downloaded,
/// which the next sync may do.
const SKIP_DURATION: Duration = Duration::from_mins(10);
/// How long conversions wait when Mistral is unavailable, see [`OcrUnavailable`].
const OCR_UNAVAILABLE_PAUSE: Duration = Duration::from_mins(5);

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
/// settings or was skipped (see [`SKIP_DURATION`]). Returns whether it did.
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

/// Converts the queued documents one at a time in the background until `shutdown` is
/// cancelled. Waits for [`DocumentExtractor::notify_queued`] when the queue is empty.
pub(crate) fn spawn_extraction_task(
    state: AppState,
    shutdown: CancellationToken,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut queue = Queue::default();
        loop {
            // A conversion that is cut off is converted again after a restart.
            let wait = tokio::select! {
                wait = queue.step(&state) => wait,
                _ = shutdown.cancelled() => break,
            };
            let Some(wait) = wait else {
                continue;
            };
            tokio::select! {
                _ = state.extractor.queued.notified() => {}
                _ = tokio::time::sleep(wait) => {}
                _ = shutdown.cancelled() => break,
            }
        }
    })
}

/// What [`spawn_extraction_task`] keeps between documents, besides the [`QueueState`] the API
/// shows.
#[derive(Default)]
struct Queue {
    /// The repository of the last document, so the repositories take turns.
    last_repository: Option<Uuid>,
}

/// What [`spawn_extraction_task`] is doing, kept in [`DocumentExtractor`] so the API can show it
/// (see [`DocumentExtractor::status`]). Only in memory, since the queue is derived from the
/// stored documents and extractions.
#[derive(Default)]
struct QueueState {
    converting: Option<ConvertingDocument>,
    /// Blobs left out until the given time, see [`SKIP_DURATION`].
    skipped: HashMap<String, (Instant, DocumentSkipReason)>,
    paused: Option<Pause>,
}

/// The document [`spawn_extraction_task`] is converting.
#[derive(Clone)]
pub(crate) struct ConvertingDocument {
    /// Where it was queued from, for a repository one of those containing the blob.
    pub(crate) source: DocumentSource,
    pub(crate) blob_oid: String,
    pub(crate) started_at: DateTime<Utc>,
}

/// Conversions wait for Mistral, see [`OcrUnavailable`].
struct Pause {
    until: Instant,
    /// The extractor that needs Mistral, so other settings do not wait.
    extractor: String,
    /// See [`ExtractionPause::reason`].
    reason: String,
}

impl QueueState {
    /// The pause of conversions with `extractor`, with how long it still lasts.
    fn pause(&self, extractor: &str, now: Instant) -> Option<(&Pause, Duration)> {
        let pause = self.paused.as_ref()?;
        (pause.extractor == extractor && pause.until > now).then(|| (pause, pause.until - now))
    }
}

/// Why a queued document was not converted now.
enum Deferred {
    /// It could not be read, see [`SKIP_DURATION`].
    Skip(DocumentSkipReason),
    /// See [`OcrUnavailable`], with its message.
    OcrUnavailable(String),
}

impl Queue {
    /// Converts the next queued document and returns how long to wait before the next one,
    /// `None` to go on right away.
    async fn step(&mut self, state: &AppState) -> Option<Duration> {
        let settings = state.extractor.settings();
        let skipped: Vec<String> = {
            let mut queue = state.extractor.queue.lock().unwrap();
            let now = Instant::now();
            queue.skipped.retain(|_, (until, _)| *until > now);
            if let Some((_, wait)) = queue.pause(&settings.extractor, now) {
                return Some(wait);
            }
            queue.paused = None;
            queue.skipped.keys().cloned().collect()
        };

        let content_types: Vec<&str> = FORMATS.iter().map(|(_, mime_type)| *mime_type).collect();
        // Attachments first, since someone is waiting for them in a chat.
        let queued = match repository::document::next_queued_attachment(
            &state.db,
            &settings.current,
            &content_types,
            &skipped,
        )
        .await
        {
            Ok(None) => {
                repository::document::next_queued(
                    &state.db,
                    &settings.current,
                    self.last_repository,
                    &skipped,
                )
                .await
            }
            queued => queued,
        };
        let document = match queued {
            Ok(Some(document)) => document,
            Ok(None) => return Some(QUEUE_POLL_INTERVAL),
            Err(e) => {
                tracing::error!("Failed to find queued documents: {e}");
                return Some(QUEUE_POLL_INTERVAL);
            }
        };
        if let DocumentSource::Repository { repository_id, .. } = &document.source {
            self.last_repository = Some(*repository_id);
        }

        state.extractor.queue.lock().unwrap().converting = Some(ConvertingDocument {
            source: document.source.clone(),
            blob_oid: document.blob_oid.clone(),
            started_at: Utc::now(),
        });
        let result = convert_queued(state, &settings, &document).await;
        let mut queue = state.extractor.queue.lock().unwrap();
        queue.converting = None;
        let wait = match result {
            Ok(()) => None,
            Err(Deferred::Skip(reason)) => {
                queue
                    .skipped
                    .insert(document.blob_oid, (Instant::now() + SKIP_DURATION, reason));
                None
            }
            Err(Deferred::OcrUnavailable(reason)) => {
                queue.paused = Some(Pause {
                    until: Instant::now() + OCR_UNAVAILABLE_PAUSE,
                    extractor: settings.extractor.clone(),
                    reason,
                });
                Some(OCR_UNAVAILABLE_PAUSE)
            }
        };
        drop(queue);
        state.extractor.converted.notify_waiters();
        wait
    }
}

/// Converts `document` with `settings` and stores the result.
async fn convert_queued(
    state: &AppState,
    settings: &Settings,
    document: &QueuedDocument,
) -> Result<(), Deferred> {
    let (content, mime_type, name) = match &document.source {
        DocumentSource::Repository {
            repository_id,
            path,
        } => {
            // Only documents are recorded, unless the supported formats changed since.
            let mime_type = mime_type(path).ok_or(Deferred::Skip(DocumentSkipReason::Error))?;
            // Every repository containing the blob has its content, so any of them will do.
            let content = state
                .mirrors
                .read(*repository_id, &document.blob_oid, MAX_DOCUMENT_SIZE)
                .await
                .map_err(|e| {
                    tracing::warn!(
                        "Failed to read {path} ({}) of repository {repository_id}: {e}",
                        document.blob_oid,
                    );
                    Deferred::Skip(DocumentSkipReason::Error)
                })?;
            (content, mime_type, path.clone())
        }
        DocumentSource::Attachment {
            attachment_id,
            file_name,
            content_type,
        } => {
            // Only documents are queued, unless the supported formats changed since.
            let mime_type =
                document_type(content_type).ok_or(Deferred::Skip(DocumentSkipReason::Error))?;
            // Smaller than `MAX_DOCUMENT_SIZE`, see `MAX_ATTACHMENT_BYTES`.
            let content = state.attachments.read(*attachment_id).await.map_err(|e| {
                tracing::warn!("Failed to read attachment {attachment_id}: {e}");
                Deferred::Skip(DocumentSkipReason::Error)
            })?;
            (
                Content::Bytes(content),
                mime_type,
                format!("attachment {file_name}"),
            )
        }
    };
    let file = RepositoryDocument {
        path: name,
        blob_oid: document.blob_oid.clone(),
    };

    let (extraction, converter) = match content {
        Content::Bytes(content) => {
            let Some(content) = reuse_content_extraction(state, settings, &file, content).await?
            else {
                return Ok(());
            };
            match state
                .extractor
                .extract(settings, &file, content, mime_type)
                .await
            {
                Ok(Extracted { result, converter }) => {
                    let extraction = match result {
                        Ok(Converted { markdown, ocr }) => {
                            DocumentExtraction::Completed { markdown, ocr }
                        }
                        Err(error) => DocumentExtraction::Failed { error },
                    };
                    (extraction, converter)
                }
                Err(OcrUnavailable(reason)) => {
                    tracing::warn!(
                        "Pausing document conversion for {:?}",
                        OCR_UNAVAILABLE_PAUSE
                    );
                    return Err(Deferred::OcrUnavailable(reason));
                }
            }
        }
        Content::TooLarge(_) => {
            tracing::warn!(
                "Did not convert {} ({}), it is larger than {} MB",
                file.path,
                file.blob_oid,
                MAX_DOCUMENT_SIZE / 1024 / 1024
            );
            let extraction = DocumentExtraction::Failed {
                error: format!(
                    "The file is larger than {} MB, the limit for converting it",
                    MAX_DOCUMENT_SIZE / 1024 / 1024
                ),
            };
            (extraction, Converter::Xberg)
        }
        Content::Unavailable => {
            tracing::debug!(
                "Did not convert {} ({}), its content was not downloaded",
                file.path,
                file.blob_oid
            );
            return Err(Deferred::Skip(DocumentSkipReason::LfsObjectMissing));
        }
    };
    repository::document::save_extraction(
        &state.db,
        &file.blob_oid,
        &extraction,
        settings.extractor_of(converter),
    )
    .await
    .map_err(|e| {
        tracing::error!("Failed to store the extraction of {}: {e}", file.blob_oid);
        Deferred::Skip(DocumentSkipReason::Error)
    })
}

/// Stores the extraction of `content` made with `settings` as the one of `document` if its blob
/// is not the content's, i.e. an LFS pointer, and the content was converted under its own blob,
/// e.g. as an attachment the model saved to the repository. Returns the content if not.
async fn reuse_content_extraction(
    state: &AppState,
    settings: &Settings,
    document: &RepositoryDocument,
    content: Vec<u8>,
) -> Result<Option<Vec<u8>>, Deferred> {
    let hashed = tokio::task::spawn_blocking(move || {
        let oid = mirror::blob_oid(&content);
        (content, oid)
    })
    .await;
    let (content, content_oid) = match hashed {
        Ok((content, Ok(content_oid))) => (content, content_oid),
        Ok((_, Err(e))) => {
            tracing::error!(
                "Failed to hash {} ({}): {e}",
                document.path,
                document.blob_oid
            );
            return Err(Deferred::Skip(DocumentSkipReason::Error));
        }
        Err(e) => {
            tracing::error!(
                "Hashing {} ({}) failed: {e}",
                document.path,
                document.blob_oid
            );
            return Err(Deferred::Skip(DocumentSkipReason::Error));
        }
    };
    if content_oid == document.blob_oid {
        return Ok(Some(content));
    }
    let copied = repository::document::copy_extraction(
        &state.db,
        &content_oid,
        &document.blob_oid,
        &settings.current,
    )
    .await
    .map_err(|e| {
        tracing::error!("Failed to copy the extraction of {content_oid}: {e}");
        Deferred::Skip(DocumentSkipReason::Error)
    })?;
    if !copied {
        return Ok(Some(content));
    }
    tracing::info!(
        "Reused the extraction of {content_oid} for {} ({})",
        document.path,
        document.blob_oid
    );
    Ok(None)
}

/// Converts one document at a time with xberg, so share one instance. More would only compete
/// for the cores: xberg already spreads one document over them, and OCR is limited
/// process-wide anyway (PaddleOCR runs one inference at a time on all cores, Tesseract
/// recognizes several pages at once). Mistral is called after xberg's part, without the permit.
pub(crate) struct DocumentExtractor {
    /// Held by a timed out conversion too, until it ends.
    permit: Arc<Semaphore>,
    /// Set with `OCR_API_KEY_MISTRAL`, which [`OcrEngine::Mistral`] requires.
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

/// A snapshot of what [`spawn_extraction_task`] is doing, see [`DocumentExtractor::status`].
pub(crate) struct ExtractionStatus {
    /// Of the current settings, see [`extractor_id`].
    pub(crate) extractor: String,
    /// See [`Settings::current`].
    pub(crate) current_extractors: Vec<String>,
    pub(crate) converting: Option<ConvertingDocument>,
    skipped: HashMap<String, (DateTime<Utc>, DocumentSkipReason)>,
    pub(crate) paused: Option<ExtractionPause>,
}

/// The conversions wait for the OCR service, see [`OcrUnavailable`].
pub(crate) struct ExtractionPause {
    pub(crate) until: DateTime<Utc>,
    /// The error of the OCR service. Only for admins, since it may contain details of the
    /// service's response.
    pub(crate) reason: String,
}

/// Where a document waiting to be converted is.
pub(crate) enum Conversion {
    Waiting,
    Converting {
        started_at: DateTime<Utc>,
    },
    /// Left out until `until`, see [`SKIP_DURATION`].
    Skipped {
        reason: DocumentSkipReason,
        until: DateTime<Utc>,
    },
}

impl ExtractionStatus {
    /// Where the document with `blob_oid` is, given the extractor of its stored extraction.
    /// `None` if it was converted with the current settings.
    pub(crate) fn conversion(&self, blob_oid: &str, extractor: Option<&str>) -> Option<Conversion> {
        if extractor.is_some_and(|extractor| self.current_extractors.iter().any(|e| e == extractor))
        {
            return None;
        }
        if let Some(converting) = &self.converting
            && converting.blob_oid == blob_oid
        {
            return Some(Conversion::Converting {
                started_at: converting.started_at,
            });
        }
        if let Some((until, reason)) = self.skipped.get(blob_oid) {
            return Some(Conversion::Skipped {
                reason: *reason,
                until: *until,
            });
        }
        Some(Conversion::Waiting)
    }

    /// The blobs left out for now, see [`SKIP_DURATION`].
    pub(crate) fn skipped_blobs(&self) -> Vec<String> {
        self.skipped.keys().cloned().collect()
    }
}

/// Derived from the OCR settings, replaced as a whole when they change.
struct Settings {
    config: Arc<xberg::ExtractionConfig>,
    ocr: Option<OcrConfig>,
    /// Stored with the extractions xberg made, see [`extractor_id`].
    extractor: String,
    /// The extractors whose extractions are up to date, so they are not converted again:
    /// `extractor`, and [`MISTRAL_EXTRACTOR`] while Mistral is the OCR engine.
    current: Vec<String>,
}

impl Settings {
    fn new(ocr: Option<&OcrConfig>) -> Self {
        let extractor = extractor_id(ocr);
        let mut current = vec![extractor.clone()];
        if ocr.is_some_and(|ocr| ocr.engine == OcrEngine::Mistral) {
            current.push(MISTRAL_EXTRACTOR.to_string());
        }
        Self {
            config: Arc::new(extraction_config(ocr)),
            ocr: ocr.cloned(),
            extractor,
            current,
        }
    }

    /// Stored with the extractions `converter` made.
    fn extractor_of(&self, converter: Converter) -> &str {
        match converter {
            Converter::Xberg => &self.extractor,
            Converter::Mistral => MISTRAL_EXTRACTOR,
        }
    }
}

/// Mistral could not be reached, or refused the API key, so the document is converted later.
#[derive(Debug, thiserror::Error)]
#[error("Mistral OCR is unavailable: {0}")]
struct OcrUnavailable(String);

/// The outcome of [`DocumentExtractor::extract`]. The error is stored and shown to the model,
/// details are only logged.
#[derive(Debug)]
struct Extracted {
    result: Result<Converted, String>,
    converter: Converter,
}

/// What made an extraction, which decides the extractor it is stored with (see
/// [`Settings::extractor_of`]).
#[derive(Debug, Clone, Copy, PartialEq)]
enum Converter {
    Xberg,
    Mistral,
}

/// A document converted to Markdown.
#[derive(Debug)]
struct Converted {
    markdown: String,
    /// Whether pages were recognized with OCR.
    ocr: bool,
}

/// What xberg made of a document.
struct Native {
    markdown: String,
    /// Whether xberg recognized pages with OCR.
    ocr: bool,
    /// How much the most scan-like page looks like a scan, from 0 to 1, see
    /// [`crate::RuntimeConfig::ocr_scan_confidence`]. Scored without OCR.
    scan_confidence: Option<f32>,
    /// Whether xberg could not read the text of pages from the file, e.g. for lack of a
    /// character mapping, and made it up.
    made_up_text: bool,
}

impl Native {
    /// Whether a page looks like a scan by `min_confidence`, or has made-up text, as xberg's
    /// `OcrStrategy::ScannedPages` would select pages.
    fn has_scanned_pages(&self, min_confidence: f64) -> bool {
        // Like xberg, which selects the pages scoring at least the threshold as `f32`
        self.made_up_text
            || self
                .scan_confidence
                .is_some_and(|confidence| confidence >= min_confidence as f32)
    }
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

    /// What [`spawn_extraction_task`] is doing. A document finished after this call is not
    /// reported as converting, so read it before the stored extractions.
    pub(crate) fn status(&self) -> ExtractionStatus {
        let settings = self.settings();
        let extractor = settings.extractor.clone();
        let queue = self.queue.lock().unwrap();
        let now = Instant::now();
        let utc_now = Utc::now();
        let after = |wait: Duration| utc_now + chrono::Duration::from_std(wait).unwrap_or_default();
        ExtractionStatus {
            current_extractors: settings.current.clone(),
            converting: queue.converting.clone(),
            skipped: queue
                .skipped
                .iter()
                .filter(|(_, (until, _))| *until > now)
                .map(|(blob, (until, reason))| (blob.clone(), (after(*until - now), *reason)))
                .collect(),
            paused: queue
                .pause(&extractor, now)
                .map(|(pause, wait)| ExtractionPause {
                    until: after(wait),
                    reason: pause.reason.clone(),
                }),
            extractor,
        }
    }

    /// The extraction of `blob_oid`, waiting up to `timeout` while it is queued, e.g. for an
    /// attachment that was just uploaded. `None` if there is none by then, or right away if the
    /// document was skipped or the conversions are paused.
    pub(crate) async fn wait_for_extraction(
        &self,
        db: &DatabasePool,
        blob_oid: &str,
        timeout: Duration,
    ) -> Result<Option<DocumentExtraction>, AppError> {
        let deadline = tokio::time::Instant::now() + timeout;
        loop {
            // Listening before the extraction is looked up, so none stored in between is missed.
            let converted = self.converted.notified();
            tokio::pin!(converted);
            converted.as_mut().enable();
            if let Some(extraction) = repository::document::get_extraction(db, blob_oid).await? {
                return Ok(Some(extraction));
            }
            let extractor = self.settings().extractor.clone();
            let deferred = {
                let queue = self.queue.lock().unwrap();
                let now = Instant::now();
                queue
                    .skipped
                    .get(blob_oid)
                    .is_some_and(|(until, _)| *until > now)
                    || queue.pause(&extractor, now).is_some()
            };
            if deferred {
                return Ok(None);
            }
            tokio::select! {
                _ = converted => {}
                _ = tokio::time::sleep_until(deadline) => return Ok(None),
            }
        }
    }

    /// Tries `blob_oid` again on the next conversion. Returns whether it was skipped.
    fn unskip(&self, blob_oid: &str) -> bool {
        let mut queue = self.queue.lock().unwrap();
        queue
            .skipped
            .remove(blob_oid)
            .is_some_and(|(until, _)| until > Instant::now())
    }

    fn settings(&self) -> Arc<Settings> {
        self.settings.read().unwrap().clone()
    }

    /// Waits until no other conversion is running.
    async fn permit(&self) -> OwnedSemaphorePermit {
        self.permit
            .clone()
            .acquire_owned()
            .await
            .expect("the semaphore is never closed")
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

    /// Converts `content`, the content of `document`, to Markdown and logs the outcome. The
    /// error means the document could not be converted now.
    async fn extract(
        &self,
        settings: &Settings,
        document: &RepositoryDocument,
        content: Vec<u8>,
        mime_type: &str,
    ) -> Result<Extracted, OcrUnavailable> {
        let permit = self.permit().await;
        // After waiting for the permit, so only the conversion is timed.
        let started = Instant::now();
        let result = self.convert(settings, permit, content, mime_type).await;
        match result.as_ref().map(|extracted| &extracted.result) {
            Ok(Ok(_)) => tracing::info!(
                "Converted {} ({}) in {:?}",
                document.path,
                document.blob_oid,
                started.elapsed()
            ),
            Ok(Err(error)) => tracing::info!(
                "Could not convert {} ({}) in {:?}: {error}",
                document.path,
                document.blob_oid,
                started.elapsed()
            ),
            Err(error) => tracing::warn!(
                "Did not convert {} ({}), trying again later: {error}",
                document.path,
                document.blob_oid,
            ),
        }
        result
    }

    /// See [`Self::extract`].
    async fn convert(
        &self,
        settings: &Settings,
        permit: OwnedSemaphorePermit,
        content: Vec<u8>,
        mime_type: &str,
    ) -> Result<Extracted, OcrUnavailable> {
        let mistral = settings
            .ocr
            .as_ref()
            .filter(|ocr| ocr.engine == OcrEngine::Mistral);
        // Only needed again if xberg finds scanned pages.
        let original = mistral.map(|_| content.clone());
        let by_xberg = |result| Extracted {
            result,
            converter: Converter::Xberg,
        };
        let native = match convert_natively(&settings.config, permit, content, mime_type).await {
            Ok(native) => native,
            Err(error) => return Ok(by_xberg(Err(error))),
        };
        if let (Some(ocr), Some(original)) = (mistral, original)
            && native.has_scanned_pages(ocr.scan_confidence)
        {
            let result = self.recognize_with_mistral(&original).await?;
            return Ok(Extracted {
                result,
                converter: Converter::Mistral,
            });
        }
        if native.markdown.trim().is_empty() {
            let error = match settings.ocr {
                None => NO_TEXT_WITHOUT_OCR,
                Some(_) => NO_TEXT,
            };
            return Ok(by_xberg(Err(error.to_string())));
        }
        Ok(by_xberg(Ok(Converted {
            markdown: native.markdown,
            ocr: native.ocr,
        })))
    }

    async fn recognize_with_mistral(
        &self,
        content: &[u8],
    ) -> Result<Result<Converted, String>, OcrUnavailable> {
        let Some(mistral) = &self.mistral else {
            // Prevented by `RuntimeConfig::validate_ocr_engine`.
            return Err(OcrUnavailable(
                "OCR_ENGINE is mistral, but OCR_API_KEY_MISTRAL is not set".to_string(),
            ));
        };
        match mistral.recognize(content).await {
            Ok(markdown) if markdown.trim().is_empty() => Ok(Err(NO_TEXT.to_string())),
            Ok(markdown) => Ok(Ok(Converted {
                markdown,
                ocr: true,
            })),
            Err(MistralError::Rejected(error)) => {
                tracing::warn!("Mistral could not convert a document: {error}");
                Ok(Err(FAILED.to_string()))
            }
            Err(MistralError::Unavailable(error)) => Err(OcrUnavailable(error)),
        }
    }
}

/// Converts `content` to Markdown with xberg. The permit is moved into the task, so a timed
/// out conversion keeps it until it ends.
async fn convert_natively(
    config: &Arc<xberg::ExtractionConfig>,
    permit: OwnedSemaphorePermit,
    content: Vec<u8>,
    mime_type: &str,
) -> Result<Native, String> {
    let task_config = config.clone();
    let input = xberg::ExtractInput::from_bytes(content, mime_type, None);
    let runtime = tokio::runtime::Handle::current();
    // On a blocking thread, in case xberg does CPU-bound work on the async one, and so a
    // panic only fails this document.
    let task = tokio::task::spawn_blocking(move || {
        let _permit = permit;
        runtime.block_on(xberg::extract(input, &task_config))
    });

    let result = match tokio::time::timeout(EXTRACTION_TIMEOUT, task).await {
        Ok(Ok(result)) => result,
        Ok(Err(e)) => {
            tracing::error!("Document extraction panicked: {e}");
            return Err(FAILED.to_string());
        }
        Err(_) => {
            return Err(format!(
                "Converting the file took longer than {} minutes",
                EXTRACTION_TIMEOUT.as_secs() / 60
            ));
        }
    };
    let mut result = result.map_err(|e| {
        tracing::warn!("Document extraction failed: {e}");
        FAILED.to_string()
    })?;
    if let Some(error) = result.errors.first() {
        tracing::warn!("Document extraction failed: {}", error.message);
        return Err(FAILED.to_string());
    }
    match result.results.pop() {
        Some(document) => {
            let pdf = match &document.metadata.format {
                Some(xberg::FormatMetadata::Pdf(pdf)) => Some(pdf),
                _ => None,
            };
            Ok(Native {
                // xberg reports `Mixed` when OCR replaced the text of the scanned pages, even
                // if that was every page, so `Ocr` and `Mixed` are not told apart.
                ocr: document
                    .extraction_method
                    .is_some_and(xberg::ExtractionMethod::used_ocr),
                scan_confidence: pdf.and_then(|pdf| pdf.scanned_confidence),
                made_up_text: pdf
                    .and_then(|pdf| pdf.fabricated_text_pages.as_ref())
                    .is_some_and(|pages| !pages.is_empty()),
                markdown: document.content,
            })
        }
        None => {
            tracing::warn!("Document extraction returned no document");
            Err(FAILED.to_string())
        }
    }
}

/// Identifies [`EXTRACTOR`] with the OCR settings, so changing them extracts the documents
/// again, except those Mistral converted (see [`MISTRAL_EXTRACTOR`]).
fn extractor_id(ocr: Option<&OcrConfig>) -> String {
    match ocr {
        Some(ocr) => match xberg_backend(ocr.engine) {
            Some(backend) => format!(
                "{EXTRACTOR}/{backend}:{}/scan-{}",
                ocr.languages.join("+"),
                ocr.scan_confidence
            ),
            // Mistral detects the languages itself.
            None => format!(
                "{EXTRACTOR}/{}/scan-{}",
                mistral_ocr::MODEL,
                ocr.scan_confidence
            ),
        },
        None => format!("{EXTRACTOR}/no-ocr"),
    }
}

/// The OCR backend of xberg, `None` for Mistral, which xberg does not call.
fn xberg_backend(engine: OcrEngine) -> Option<&'static str> {
    match engine {
        OcrEngine::Tesseract => Some("tesseract"),
        OcrEngine::Paddle => Some("paddle-ocr"),
        OcrEngine::Mistral => None,
    }
}

fn extraction_config(ocr: Option<&OcrConfig>) -> xberg::ExtractionConfig {
    // xberg only scores the pages for Mistral, see `Native::has_scanned_pages`.
    let local = ocr.and_then(|ocr| Some((ocr, xberg_backend(ocr.engine)?)));
    let ocr_strategy = match local {
        // xberg's default only recognizes pages whose text fails its quality check, which
        // a scanner's OCR text passes however poor it is.
        Some((ocr, _)) => xberg::OcrStrategy::ScannedPages {
            min_confidence: ocr.scan_confidence,
        },
        None => xberg::OcrStrategy::Auto,
    };
    xberg::ExtractionConfig {
        // The results are stored in the database.
        use_cache: false,
        output_format: xberg::OutputFormat::Markdown,
        // Only read by the model, which does not need CommonMark escapes.
        escape_markdown: false,
        disable_ocr: local.is_none(),
        ocr: local.map(|(ocr, backend)| xberg::OcrConfig {
            backend: backend.to_string(),
            language: ocr.languages.clone(),
            // Tesseract caches its results in the user's cache directory otherwise, without a
            // limit. The results are stored in the database.
            backend_options: (ocr.engine == OcrEngine::Tesseract)
                .then(|| serde_json::json!({ "use_cache": false })),
            ..Default::default()
        }),
        ocr_strategy,
        extraction_timeout_secs: Some(EXTRACTION_TIMEOUT.as_secs()),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::mistral_ocr::mock;
    use axum::http::StatusCode;
    use serde_json::json;

    const PDF: &str = "application/pdf";
    const TEXT_PDF: &[u8] = include_bytes!("../../tests/fixtures/text.pdf");

    /// The extracted document, only used for logging.
    fn document() -> RepositoryDocument {
        RepositoryDocument {
            path: "test.pdf".to_string(),
            blob_oid: "0".repeat(40),
        }
    }

    #[test]
    fn matches_documents() {
        assert!(is_document("docs/manual.pdf"));
        assert!(is_document("Manual.PDF"));
        assert!(!is_document("pdf"));
        assert!(!is_document("docs/manual.pdf.txt"));
    }

    fn ocr(engine: OcrEngine, languages: &[&str]) -> OcrConfig {
        OcrConfig {
            engine,
            languages: languages.iter().map(|l| l.to_string()).collect(),
            scan_confidence: 0.5,
        }
    }

    async fn extract_with(
        extractor: &DocumentExtractor,
        pdf: &[u8],
    ) -> Result<Extracted, OcrUnavailable> {
        extractor
            .extract(&extractor.settings(), &document(), pdf.to_vec(), PDF)
            .await
    }

    async fn extract(ocr: Option<&OcrConfig>, pdf: &[u8]) -> Result<Converted, String> {
        let extracted = extract_with(&DocumentExtractor::new(ocr, None), pdf)
            .await
            .unwrap();
        assert_eq!(extracted.converter, Converter::Xberg);
        extracted.result
    }

    /// Extracts with [`OcrEngine::Mistral`], which responds with `status` and `body`, and
    /// returns how often it was called.
    async fn extract_with_mistral(
        status: StatusCode,
        body: serde_json::Value,
        pdf: &[u8],
    ) -> (Result<Extracted, OcrUnavailable>, usize) {
        let (mistral, requests) = mock::serve(status, body).await;
        let ocr = ocr(OcrEngine::Mistral, &["eng"]);
        let extractor = DocumentExtractor::new(Some(&ocr), Some(mistral));
        let result = extract_with(&extractor, pdf).await;
        let calls = requests.lock().unwrap().len();
        (result, calls)
    }

    #[test]
    fn replaces_ocr_settings() {
        let extractor = DocumentExtractor::new(None, None);
        let previous = extractor.settings();
        extractor.set_ocr(Some(&ocr(OcrEngine::Paddle, &["deu"])));
        assert_eq!(previous.extractor, format!("{EXTRACTOR}/no-ocr"));
        assert_eq!(previous.current, [format!("{EXTRACTOR}/no-ocr")]);
        assert!(previous.config.disable_ocr);
        let current = extractor.settings();
        assert_eq!(
            current.extractor,
            format!("{EXTRACTOR}/paddle-ocr:deu/scan-0.5")
        );
        assert_eq!(current.current, std::slice::from_ref(&current.extractor));
        assert_eq!(current.extractor_of(Converter::Xberg), current.extractor);
        assert!(!current.config.disable_ocr);

        // xberg only finds the scans for Mistral
        extractor.set_ocr(Some(&ocr(OcrEngine::Mistral, &["deu"])));
        let current = extractor.settings();
        assert_eq!(
            current.extractor,
            format!("{EXTRACTOR}/mistral-ocr-latest/scan-0.5")
        );
        assert!(current.config.disable_ocr);
        assert_eq!(current.config.ocr_strategy, xberg::OcrStrategy::Auto);
        // Without the xberg version, so Mistral's extractions are kept when it changes
        assert_eq!(
            current.extractor_of(Converter::Mistral),
            "mistral-ocr-latest"
        );
        assert_eq!(
            current.current,
            [current.extractor.clone(), "mistral-ocr-latest".to_string()]
        );
    }

    #[test]
    fn identifies_ocr_settings() {
        assert_eq!(extractor_id(None), format!("{EXTRACTOR}/no-ocr"));
        assert_eq!(
            extractor_id(Some(&ocr(OcrEngine::Tesseract, &["deu", "eng"]))),
            format!("{EXTRACTOR}/tesseract:deu+eng/scan-0.5")
        );
        let ocr = OcrConfig {
            scan_confidence: 0.85,
            ..ocr(OcrEngine::Paddle, &["deu"])
        };
        assert_eq!(
            extractor_id(Some(&ocr)),
            format!("{EXTRACTOR}/paddle-ocr:deu/scan-0.85")
        );
        // Without the languages, which Mistral does not use
        let ocr = OcrConfig {
            engine: OcrEngine::Mistral,
            ..ocr
        };
        assert_eq!(
            extractor_id(Some(&ocr)),
            format!("{EXTRACTOR}/mistral-ocr-latest/scan-0.85")
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn extracts_text() {
        let Converted { markdown, ocr } = extract(None, TEXT_PDF).await.unwrap();
        assert!(markdown.contains("Repolupe PDF test"), "{markdown}");
        assert!(markdown.contains("42 requests"), "{markdown}");
        assert!(!ocr);
    }

    #[cfg(feature = "local-ocr")]
    #[tokio::test(flavor = "multi_thread")]
    async fn extracts_text_without_ocr_when_enabled() {
        let ocr = ocr(OcrEngine::Tesseract, &["eng"]);
        let Converted { markdown, ocr } = extract(Some(&ocr), TEXT_PDF).await.unwrap();
        assert!(markdown.contains("42 requests"), "{markdown}");
        assert!(!ocr);
    }

    #[cfg(feature = "local-ocr")]
    #[tokio::test(flavor = "multi_thread")]
    async fn recognizes_scans() {
        let pdf = SAMPLE_SCAN;
        let ocr = ocr(OcrEngine::Tesseract, &["eng"]);
        let Converted { markdown, ocr } = extract(Some(&ocr), pdf).await.unwrap();
        assert!(markdown.contains("invoice 7731"), "{markdown}");
        assert!(markdown.contains("125 USD"), "{markdown}");
        assert!(ocr);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn recognizes_scans_with_mistral() {
        let response = mock::pages(&["# Invoice 7731", "![img-0.jpeg](img-0.jpeg)\n\n125 USD"]);
        let (result, calls) = extract_with_mistral(StatusCode::OK, response, SAMPLE_SCAN).await;
        let extracted = result.unwrap();
        assert_eq!(extracted.converter, Converter::Mistral);
        let Converted { markdown, ocr } = extracted.result.unwrap();
        assert_eq!(markdown, "# Invoice 7731\n\n125 USD");
        assert!(ocr);
        assert_eq!(calls, 1);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn sends_only_scans_to_mistral() {
        let response = mock::pages(&["Recognized"]);
        let (result, calls) = extract_with_mistral(StatusCode::OK, response, TEXT_PDF).await;
        let extracted = result.unwrap();
        assert_eq!(extracted.converter, Converter::Xberg);
        let Converted { markdown, ocr } = extracted.result.unwrap();
        assert!(markdown.contains("42 requests"), "{markdown}");
        assert!(!ocr);
        assert_eq!(calls, 0);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn stores_documents_mistral_rejects() {
        let error = json!({"object": "error", "message": "Invalid document"});
        let (result, _) =
            extract_with_mistral(StatusCode::UNPROCESSABLE_ENTITY, error, SAMPLE_SCAN).await;
        let extracted = result.unwrap();
        assert_eq!(extracted.converter, Converter::Mistral);
        assert_eq!(
            extracted.result.unwrap_err(),
            "The file could not be converted, it may be damaged or encrypted"
        );

        let (result, _) =
            extract_with_mistral(StatusCode::OK, mock::pages(&[" "]), SAMPLE_SCAN).await;
        let extracted = result.unwrap();
        assert_eq!(extracted.converter, Converter::Mistral);
        assert_eq!(extracted.result.unwrap_err(), "The file contains no text");
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn defers_documents_when_mistral_is_unavailable() {
        let error = json!({"object": "error", "message": "Rate limit exceeded", "code": "1300"});
        let (result, _) =
            extract_with_mistral(StatusCode::TOO_MANY_REQUESTS, error, SAMPLE_SCAN).await;
        let Err(OcrUnavailable(message)) = result else {
            panic!("expected Mistral to be unavailable, got {result:?}");
        };
        assert!(message.contains("Rate limit exceeded"), "{message}");
    }

    #[cfg(feature = "local-ocr")]
    #[tokio::test(flavor = "multi_thread")]
    #[ignore = "downloads the PaddleOCR models"]
    async fn recognizes_scans_with_paddle() {
        let pdf = SAMPLE_SCAN;
        let ocr = ocr(OcrEngine::Paddle, &["eng"]);
        let Converted { markdown, ocr } = extract(Some(&ocr), pdf).await.unwrap();
        assert!(markdown.contains("invoice 7731"), "{markdown}");
        assert!(markdown.contains("125 USD"), "{markdown}");
        assert!(ocr);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn skips_scans_without_ocr() {
        let pdf = SAMPLE_SCAN;
        assert_eq!(
            extract(None, pdf).await.unwrap_err(),
            "The file contains no text. It may be a scan, and text recognition (OCR) is turned off"
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn rejects_damaged_files() {
        let result = extract(None, b"%PDF-1.4\nnot really").await;
        assert_eq!(
            result.unwrap_err(),
            "The file could not be converted, it may be damaged or encrypted"
        );
    }
}
