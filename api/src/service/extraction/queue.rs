//! The background task working through the queued documents, and what it reports to the API.

use super::convert::{Converted, Extracted, OcrUnavailable};
use super::settings::{Converter, Settings};
use super::{DocumentExtractor, FORMATS, MAX_DOCUMENT_SIZE, document_type, mime_type};
use crate::config::error::AppError;
use crate::config::state::{AppState, DatabasePool};
use crate::dto::extraction::DocumentSkipReason;
use crate::model::document_extraction::DocumentExtraction;
use crate::model::repository_document::{DocumentSource, QueuedDocument, RepositoryDocument};
use crate::repository;
use crate::service::mirror::{self, Content};
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use std::time::{Duration, Instant};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// How often the queue is checked without being notified, e.g. for skipped documents.
const QUEUE_POLL_INTERVAL: Duration = Duration::from_mins(1);
/// How long a document is skipped when it cannot be read, e.g. its content was not downloaded,
/// which the next sync may do.
pub(super) const SKIP_DURATION: Duration = Duration::from_mins(10);
/// How long conversions wait when Mistral is unavailable, see [`OcrUnavailable`].
const OCR_UNAVAILABLE_PAUSE: Duration = Duration::from_mins(5);

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
pub(super) struct QueueState {
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

/// A snapshot of what [`spawn_extraction_task`] is doing, see [`DocumentExtractor::status`].
pub(crate) struct ExtractionStatus {
    /// Of the current settings, see [`Settings::extractor`].
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

impl DocumentExtractor {
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
    pub(super) fn unskip(&self, blob_oid: &str) -> bool {
        let mut queue = self.queue.lock().unwrap();
        queue
            .skipped
            .remove(blob_oid)
            .is_some_and(|(until, _)| until > Instant::now())
    }
}
