//! Which settings the extractions are made with, and how they are identified when stored.

use super::convert::EXTRACTION_TIMEOUT;
use crate::config::init::{OcrConfig, OcrEngine};
use crate::service::mistral_ocr;
use std::sync::Arc;

/// Identifies how the stored extractions were made, together with the OCR settings (see
/// [`extractor_id`]). The xberg version is the one pinned in `Cargo.toml` (see `build.rs`).
/// Append a revision (e.g. `/config-2`) when [`extraction_config`] changes, so the documents are
/// extracted again.
const EXTRACTOR: &str = concat!("xberg-", env!("XBERG_VERSION"));

/// Identifies the extractions Mistral made. They depend neither on xberg nor on the other OCR
/// settings, so they are kept while Mistral is the OCR engine (see [`Settings::current`]), and
/// a new xberg version only converts the documents again that xberg converted.
const MISTRAL_EXTRACTOR: &str = mistral_ocr::MODEL;

/// Derived from the OCR settings, replaced as a whole when they change.
pub(super) struct Settings {
    pub(super) config: Arc<xberg::ExtractionConfig>,
    pub(super) ocr: Option<OcrConfig>,
    /// Stored with the extractions xberg made, see [`extractor_id`].
    pub(super) extractor: String,
    /// The extractors whose extractions are up to date, so they are not converted again:
    /// `extractor`, and [`MISTRAL_EXTRACTOR`] while Mistral is the OCR engine.
    pub(super) current: Vec<String>,
}

impl Settings {
    pub(super) fn new(ocr: Option<&OcrConfig>) -> Self {
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
    pub(super) fn extractor_of(&self, converter: Converter) -> &str {
        match converter {
            Converter::Xberg => &self.extractor,
            Converter::Mistral => MISTRAL_EXTRACTOR,
        }
    }
}

/// What made an extraction, which decides the extractor it is stored with (see
/// [`Settings::extractor_of`]).
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum Converter {
    Xberg,
    Mistral,
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
    use crate::service::extraction::DocumentExtractor;
    use crate::service::extraction::tests::ocr;

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
}
