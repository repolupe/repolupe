use crate::model::remote_access::RemoteAccess;
use crate::util::ip::{NotPublic, PublicResolver, has_public_host};
use crate::util::validation;
use reqwest::header::{ACCEPT_LANGUAGE, HeaderMap, RETRY_AFTER};
use reqwest::redirect::{Action, Attempt, Policy};
use std::time::Duration;
use url::Url;

const MAX_REDIRECTS: usize = 5;

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

/// A builder for the clients that reach user-supplied URLs (remotes, Git LFS, MCP servers).
/// With [`RemoteAccess::Public`], only over https and at public addresses ([`PublicResolver`]).
/// Without the proxy environment variables, which would resolve the hosts instead of
/// [`PublicResolver`], like git, which runs without them.
pub(crate) fn remote_client_builder(access: RemoteAccess) -> reqwest::ClientBuilder {
    let builder = client_builder().no_proxy();
    match access {
        RemoteAccess::Public => builder.https_only(true).dns_resolver(PublicResolver),
        RemoteAccess::Unrestricted => builder,
    }
}

/// For clients of [`remote_client_builder`] that follow redirects: at most [`MAX_REDIRECTS`],
/// and with [`RemoteAccess::Public`] only to public hosts.
pub(crate) fn redirect_policy(access: RemoteAccess) -> Policy {
    match access {
        RemoteAccess::Public => Policy::custom(check_redirect),
        RemoteAccess::Unrestricted => Policy::limited(MAX_REDIRECTS),
    }
}

/// [`PublicResolver`] never sees IP addresses in redirects, so they are checked here.
fn check_redirect(attempt: Attempt) -> Action {
    if attempt.previous().len() >= MAX_REDIRECTS {
        attempt.error("too many redirects")
    } else if !has_public_host(attempt.url()) {
        attempt.error(NotPublic)
    } else {
        attempt.follow()
    }
}

/// Checks what [`PublicResolver`] cannot: IP addresses in the URL are never resolved. With
/// [`RemoteAccess::Public`], the URL must use https and its host must be a domain or a public
/// IP address.
pub(crate) fn check_public_url(url: &Url, access: RemoteAccess) -> Result<(), NotPublic> {
    if access == RemoteAccess::Public && (url.scheme() != "https" || !has_public_host(url)) {
        return Err(NotPublic);
    }
    Ok(())
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
    fn checks_public_urls() {
        let check = |url: &str, access| check_public_url(&Url::parse(url).unwrap(), access);
        for url in ["https://example.com/mcp", "https://140.82.121.3/x"] {
            assert!(check(url, RemoteAccess::Public).is_ok(), "{url}");
        }
        for url in [
            "http://example.com/mcp",
            "https://127.0.0.1/x",
            "https://[::1]/x",
            "https://169.254.169.254/latest",
        ] {
            assert!(check(url, RemoteAccess::Public).is_err(), "{url}");
            assert!(check(url, RemoteAccess::Unrestricted).is_ok(), "{url}");
        }
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
