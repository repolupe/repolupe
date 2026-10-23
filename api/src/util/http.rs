use crate::util::validation;
use reqwest::header::{ACCEPT_LANGUAGE, HeaderMap, RETRY_AFTER};
use std::time::Duration;

/// A builder for every HTTP client. HTTPS uses rustls with the platform's certificate verifier,
/// except on Android, where it would have to be initialized through JNI by the embedding app:
/// there, the Mozilla roots of `webpki-root-certs` are used instead.
pub(crate) fn client_builder() -> reqwest::ClientBuilder {
    let builder = reqwest::Client::builder();
    #[cfg(target_os = "android")]
    let builder = builder.tls_certs_only(
        webpki_root_certs::TLS_SERVER_ROOT_CERTS
            .iter()
            // Only stores the bytes with rustls, so it never fails.
            .filter_map(|der| reqwest::Certificate::from_der(der).ok()),
    );
    builder
}

/// Only the seconds form, which is what the LLM and OCR APIs send.
pub(crate) fn retry_after(headers: &HeaderMap) -> Option<Duration> {
    let seconds: f64 = headers
        .get(RETRY_AFTER)?
        .to_str()
        .ok()?
        .trim()
        .parse()
        .ok()?;
    Duration::try_from_secs_f64(seconds).ok()
}

/// The first language of an `Accept-Language` header such as `de-DE,de;q=0.9,en;q=0.8`, which
/// browsers list by preference. `None` if the header is missing, `*` or not a valid tag.
pub(crate) fn preferred_locale(headers: &HeaderMap) -> Option<String> {
    let first = headers
        .get(ACCEPT_LANGUAGE)?
        .to_str()
        .ok()?
        .split(',')
        .next()?;
    let tag = first.split(';').next()?.trim();
    validation::validate_locale(tag).ok()?;
    Some(tag.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_retry_after_seconds() {
        let mut headers = HeaderMap::new();
        assert_eq!(retry_after(&headers), None);
        headers.insert(RETRY_AFTER, "2".parse().unwrap());
        assert_eq!(retry_after(&headers), Some(Duration::from_secs(2)));
        headers.insert(
            RETRY_AFTER,
            "Wed, 21 Oct 2026 07:28:00 GMT".parse().unwrap(),
        );
        assert_eq!(retry_after(&headers), None);
    }

    #[test]
    fn parses_the_preferred_locale() {
        let mut headers = HeaderMap::new();
        assert_eq!(preferred_locale(&headers), None);
        for (header, expected) in [
            ("de-DE,de;q=0.9,en;q=0.8", Some("de-DE")),
            ("fr", Some("fr")),
            (" en-US ;q=0.9, de", Some("en-US")),
            ("*", None),
            ("", None),
            ("en_US", None),
        ] {
            headers.insert(ACCEPT_LANGUAGE, header.parse().unwrap());
            assert_eq!(preferred_locale(&headers).as_deref(), expected, "{header}");
        }
    }
}
