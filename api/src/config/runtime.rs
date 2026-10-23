use crate::config::env::{
    INSTANCE_NAME, OCR_API_KEY_MISTRAL, OCR_ENGINE, OCR_LANGUAGES, OCR_SCAN_CONFIDENCE,
};
use crate::config::init::{OcrConfig, OcrEngine};
use crate::util::validation;
use std::collections::BTreeMap;

/// Settings that can change while the server runs. The ones in [`crate::Config::runtime`] are
/// the defaults, admins override them by key with `POST /api/v1/config`. The keys are named
/// like the environment variables read by [`Self::from_env`], see [`Self::KEYS`].
#[derive(Clone, Debug, PartialEq)]
pub struct RuntimeConfig {
    /// `INSTANCE_NAME`: shown to users, e.g. the name of the organization running this instance.
    pub instance_name: String,
    /// `OCR_ENGINE` (`none`, `tesseract`, `paddle` or `mistral`): recognizes the text of scanned pages in
    /// documents. Without it, documents only yield the text stored in them, which for scans is
    /// at most the scanner's own OCR, if any. `tesseract` and `paddle` need the `local-ocr`
    /// feature, `mistral` needs [`crate::Config::ocr_api_key_mistral`],
    /// see [`Self::validate_ocr_engine`]. Changing it or the languages converts the documents
    /// again, one at a time; until then, their earlier text is used.
    pub ocr_engine: Option<OcrEngine>,
    /// `OCR_LANGUAGES` (comma-separated): Tesseract language codes, e.g. `eng` or `deu`, which
    /// are mapped to PaddleOCR's models. Not used by `mistral`, see [`OcrConfig::languages`].
    pub ocr_languages: Vec<String>,
    /// `OCR_SCAN_CONFIDENCE` (0 to 1): how likely a page must be a scan to be recognized with
    /// OCR, as scored by xberg. A page that is a single full-page image scores 0.5, which
    /// rises to 0.85 when its text is invisible (a scanner's own OCR) or no more than a header.
    /// 0.5 also catches scans whose OCR text is drawn visibly, e.g. by Office Lens, but
    /// recognizes text documents with a full-page background image too; 0 recognizes every
    /// page. Changing it converts the documents again, see [`Self::ocr_engine`].
    pub ocr_scan_confidence: f64,
}

/// Without OCR.
impl Default for RuntimeConfig {
    fn default() -> Self {
        Self {
            instance_name: "Repolupe".to_string(),
            ocr_engine: None,
            ocr_languages: vec!["eng".to_string()],
            ocr_scan_confidence: 0.5,
        }
    }
}

/// A value [`RuntimeConfig::set`] does not accept.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub struct InvalidConfigValue(String);

impl RuntimeConfig {
    pub const KEYS: [&str; 4] = [
        INSTANCE_NAME,
        OCR_ENGINE,
        OCR_LANGUAGES,
        OCR_SCAN_CONFIDENCE,
    ];

    pub fn ocr(&self) -> Option<OcrConfig> {
        self.ocr_engine.map(|engine| OcrConfig {
            engine,
            languages: self.ocr_languages.clone(),
            scan_confidence: self.ocr_scan_confidence,
        })
    }

    /// Sets the field of `key` from its text form, as in an environment variable.
    pub fn set(&mut self, key: &str, value: &str) -> Result<(), InvalidConfigValue> {
        let value = value.trim();
        match key {
            INSTANCE_NAME => {
                validation::validate_name(value)
                    .map_err(|e| InvalidConfigValue(format!("{INSTANCE_NAME}: {e}")))?;
                self.instance_name = value.to_string();
            }
            OCR_ENGINE => {
                let engine = match value {
                    "none" => None,
                    "tesseract" => Some(OcrEngine::Tesseract),
                    "paddle" => Some(OcrEngine::Paddle),
                    "mistral" => Some(OcrEngine::Mistral),
                    _ => {
                        return Err(InvalidConfigValue(format!(
                            "{OCR_ENGINE}: expected none, tesseract, paddle or mistral"
                        )));
                    }
                };
                validate_ocr_engine_built(engine)?;
                self.ocr_engine = engine;
            }
            OCR_LANGUAGES => {
                let languages: Vec<String> = value
                    .split(',')
                    .map(|language| language.trim().to_string())
                    .collect();
                validate_ocr_languages(&languages)?;
                self.ocr_languages = languages;
            }
            OCR_SCAN_CONFIDENCE => {
                self.ocr_scan_confidence = value
                    .parse()
                    .ok()
                    .filter(|confidence| (0.0..=1.0).contains(confidence))
                    .ok_or_else(|| {
                        InvalidConfigValue(format!(
                            "{OCR_SCAN_CONFIDENCE}: expected a number from 0 to 1"
                        ))
                    })?;
            }
            _ => {
                return Err(InvalidConfigValue(format!(
                    "Unknown config key {key:?}, expected one of {}",
                    Self::KEYS.join(", ")
                )));
            }
        }
        Ok(())
    }

    /// The fields by key in their text form, the inverse of [`Self::set`].
    pub fn to_map(&self) -> BTreeMap<String, String> {
        BTreeMap::from([
            (INSTANCE_NAME.to_string(), self.instance_name.clone()),
            (
                OCR_ENGINE.to_string(),
                ocr_engine_name(self.ocr_engine).to_string(),
            ),
            (OCR_LANGUAGES.to_string(), self.ocr_languages.join(",")),
            (
                OCR_SCAN_CONFIDENCE.to_string(),
                self.ocr_scan_confidence.to_string(),
            ),
        ])
    }

    /// Checks the fields that were not set with [`Self::set`].
    pub(crate) fn validate(&self) -> Result<(), InvalidConfigValue> {
        validation::validate_name(&self.instance_name)
            .map_err(|e| InvalidConfigValue(format!("{INSTANCE_NAME}: {e}")))?;
        validate_ocr_engine_built(self.ocr_engine)?;
        validate_ocr_languages(&self.ocr_languages)
    }

    /// Checks that the OCR engine can be used, since [`OcrEngine::Mistral`] needs
    /// `OCR_API_KEY_MISTRAL`, which is not a runtime setting.
    pub(crate) fn validate_ocr_engine(
        &self,
        has_ocr_api_key_mistral: bool,
    ) -> Result<(), InvalidConfigValue> {
        if self.ocr_engine == Some(OcrEngine::Mistral) && !has_ocr_api_key_mistral {
            return Err(InvalidConfigValue(format!(
                "{OCR_ENGINE}: mistral needs {OCR_API_KEY_MISTRAL} to be set"
            )));
        }
        Ok(())
    }

    /// `self` with all of `overrides` applied, failing on the first invalid one.
    pub(crate) fn with_overrides(
        &self,
        overrides: &BTreeMap<String, String>,
    ) -> Result<Self, InvalidConfigValue> {
        let mut config = self.clone();
        for (key, value) in overrides {
            config.set(key, value)?;
        }
        Ok(config)
    }
}

fn ocr_engine_name(engine: Option<OcrEngine>) -> &'static str {
    match engine {
        None => "none",
        Some(OcrEngine::Tesseract) => "tesseract",
        Some(OcrEngine::Paddle) => "paddle",
        Some(OcrEngine::Mistral) => "mistral",
    }
}

/// Tesseract and PaddleOCR are only built with the `local-ocr` feature.
pub(crate) fn validate_ocr_engine_built(
    engine: Option<OcrEngine>,
) -> Result<(), InvalidConfigValue> {
    let local = matches!(engine, Some(OcrEngine::Tesseract | OcrEngine::Paddle));
    if local && !cfg!(feature = "local-ocr") {
        return Err(InvalidConfigValue(format!(
            "{OCR_ENGINE}: {} is not available, Repolupe was built without the local-ocr feature",
            ocr_engine_name(engine)
        )));
    }
    Ok(())
}

/// The languages are part of file names (Tesseract's language data), so only codes like
/// `eng` or `chi_sim` are accepted.
pub(crate) fn validate_ocr_languages(languages: &[String]) -> Result<(), InvalidConfigValue> {
    if languages.is_empty() {
        return Err(InvalidConfigValue(format!(
            "{OCR_LANGUAGES}: at least one language is required"
        )));
    }
    for language in languages {
        let valid =
            !language.is_empty() && language.chars().all(|c| c.is_ascii_lowercase() || c == '_');
        if !valid {
            return Err(InvalidConfigValue(format!(
                "{OCR_LANGUAGES}: expected Tesseract language codes like eng or deu"
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::env::REPOS_DIR;

    #[test]
    fn sets_fields_from_text() {
        let mut config = RuntimeConfig::default();
        config.set(INSTANCE_NAME, " Acme ").unwrap();
        config.set(OCR_ENGINE, "mistral").unwrap();
        config.set(OCR_LANGUAGES, "deu, eng").unwrap();
        config.set(OCR_SCAN_CONFIDENCE, " 0.75").unwrap();
        assert_eq!(
            config,
            RuntimeConfig {
                instance_name: "Acme".to_string(),
                ocr_engine: Some(OcrEngine::Mistral),
                ocr_languages: vec!["deu".to_string(), "eng".to_string()],
                ocr_scan_confidence: 0.75,
            }
        );
        assert_eq!(config.with_overrides(&config.to_map()).unwrap(), config);

        #[cfg(feature = "local-ocr")]
        for (value, engine) in [
            ("tesseract", OcrEngine::Tesseract),
            ("paddle", OcrEngine::Paddle),
        ] {
            config.set(OCR_ENGINE, value).unwrap();
            assert_eq!(config.ocr_engine, Some(engine));
            assert_eq!(config.with_overrides(&config.to_map()).unwrap(), config);
        }
    }

    #[cfg(not(feature = "local-ocr"))]
    #[test]
    fn rejects_local_ocr_engines_without_feature() {
        let mut config = RuntimeConfig::default();
        assert_eq!(
            config.set(OCR_ENGINE, "paddle").unwrap_err().to_string(),
            "OCR_ENGINE: paddle is not available, Repolupe was built without the local-ocr feature"
        );
        assert!(config.set(OCR_ENGINE, "tesseract").is_err());
        assert_eq!(config, RuntimeConfig::default());

        config.ocr_engine = Some(OcrEngine::Tesseract);
        assert!(config.validate().is_err());
    }

    #[test]
    fn requires_ocr_api_key_mistral() {
        let mut config = RuntimeConfig::default();
        config.validate_ocr_engine(false).unwrap();
        config.set(OCR_ENGINE, "mistral").unwrap();
        config.validate_ocr_engine(true).unwrap();
        assert_eq!(
            config.validate_ocr_engine(false).unwrap_err().to_string(),
            "OCR_ENGINE: mistral needs OCR_API_KEY_MISTRAL to be set"
        );
    }

    #[test]
    fn rejects_invalid_values() {
        let mut config = RuntimeConfig::default();
        for (key, value) in [
            (REPOS_DIR, "/tmp"),
            ("instance_name", "Acme"),
            (INSTANCE_NAME, " "),
            (OCR_ENGINE, "Paddle"),
            (OCR_LANGUAGES, ""),
            (OCR_LANGUAGES, "eng,"),
            (OCR_LANGUAGES, "../eng"),
            (OCR_SCAN_CONFIDENCE, "1.1"),
            (OCR_SCAN_CONFIDENCE, "-0.1"),
            (OCR_SCAN_CONFIDENCE, "NaN"),
            (OCR_SCAN_CONFIDENCE, "high"),
        ] {
            assert!(config.set(key, value).is_err(), "{key}={value}");
        }
        assert_eq!(config, RuntimeConfig::default());
    }
}
