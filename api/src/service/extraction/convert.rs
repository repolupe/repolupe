//! Converts one document to Markdown with xberg, and with Mistral if it is the OCR engine and
//! xberg finds scanned pages.

use super::DocumentExtractor;
use super::settings::{Converter, Settings};
use crate::config::init::OcrEngine;
use crate::model::repository_document::RepositoryDocument;
use crate::service::mistral_ocr::MistralError;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::OwnedSemaphorePermit;

pub(super) const EXTRACTION_TIMEOUT: Duration = Duration::from_mins(10);

/// Shown to the model when a document cannot be converted, the details are only logged.
const FAILED: &str = "The file could not be converted, it may be damaged or encrypted";
/// Shown to the model when a document has no text, e.g. a scan without OCR.
const NO_TEXT: &str = "The file contains no text";
const NO_TEXT_WITHOUT_OCR: &str =
    "The file contains no text. It may be a scan, and text recognition (OCR) is turned off";

/// Mistral could not be reached, or refused the API key, so the document is converted later.
#[derive(Debug, thiserror::Error)]
#[error("Mistral OCR is unavailable: {0}")]
pub(super) struct OcrUnavailable(pub(super) String);

/// The outcome of [`DocumentExtractor::extract`]. The error is stored and shown to the model,
/// details are only logged.
#[derive(Debug)]
pub(super) struct Extracted {
    pub(super) result: Result<Converted, String>,
    pub(super) converter: Converter,
}

/// A document converted to Markdown.
#[derive(Debug)]
pub(super) struct Converted {
    pub(super) markdown: String,
    /// Whether pages were recognized with OCR.
    pub(super) ocr: bool,
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
    /// Waits until no other conversion is running.
    async fn permit(&self) -> OwnedSemaphorePermit {
        self.permit
            .clone()
            .acquire_owned()
            .await
            .expect("the semaphore is never closed")
    }

    /// Converts `content`, the content of `document`, to Markdown and logs the outcome. The
    /// error means the document could not be converted now.
    pub(super) async fn extract(
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::init::OcrConfig;
    use crate::service::extraction::SAMPLE_SCAN;
    use crate::service::extraction::tests::ocr;
    use crate::service::mistral_ocr::mock;
    use axum::http::StatusCode;
    use serde_json::json;

    const PDF: &str = "application/pdf";
    const TEXT_PDF: &[u8] = include_bytes!("../../../tests/fixtures/text.pdf");

    /// The extracted document, only used for logging.
    fn document() -> RepositoryDocument {
        RepositoryDocument {
            path: "test.pdf".to_string(),
            blob_oid: "0".repeat(40),
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
