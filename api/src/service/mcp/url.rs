//! Hiding the parts of a server's URL from the users it is shared with: some servers take a key
//! in the path or the query, which is the owner's.

use url::Url;

/// What replaces the parts of a server's URL that users it is shared with must not see.
const HIDDEN: &str = "[hidden]";
/// Stands in for the URL's origin while its parts are hidden, which could otherwise match in
/// it (the path `/mcp` in `https://mcp.example.com`). URLs never contain it.
const ORIGIN: &str = "\u{0}";
/// Path segments and query values shorter than this are not hidden on their own: keys are
/// longer, and hiding words like `mcp` everywhere would garble the messages.
const MIN_HIDDEN_PART: usize = 8;

/// The scheme, host and port of a server's URL. Users it is shared with see only this.
pub(crate) fn url_origin(url: &str) -> String {
    Url::parse(url)
        .map(|url| url.origin().ascii_serialization())
        .unwrap_or_default()
}

/// `message` without the path and the query of the server's `url` (the URL itself as its
/// origin), for users the server is shared with, see [`url_origin`]. Also the longer path
/// segments and query values on their own, and wherever they appear, e.g. in the URLs of the
/// OAuth discovery, which contain the server's path.
pub(crate) fn hide_url(message: &str, url: &str) -> String {
    let Ok(parsed) = Url::parse(url) else {
        return message.to_string();
    };
    let origin = parsed.origin().ascii_serialization();
    let mut message = message
        .replace(url, ORIGIN)
        .replace(parsed.as_str(), ORIGIN)
        .replace(&origin, ORIGIN);
    let query = parsed.query().filter(|query| !query.is_empty());
    let path = Some(parsed.path()).filter(|path| *path != "/");
    let segments = parsed.path().split('/');
    let values = query
        .into_iter()
        .flat_map(|query| query.split('&'))
        .map(|pair| pair.split_once('=').map_or(pair, |(_, value)| value));
    let parts = query.into_iter().chain(path).chain(
        segments
            .chain(values)
            .filter(|part| part.len() >= MIN_HIDDEN_PART),
    );
    for part in parts {
        message = message.replace(part, HIDDEN);
    }
    message.replace(ORIGIN, &origin)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hides_a_key_in_the_path() {
        let url = "https://mcp.example.com/s/k3y-in-the-path/mcp";
        assert_eq!(url_origin(url), "https://mcp.example.com");
        assert_eq!(
            hide_url(&format!("error sending request for url ({url})"), url),
            "error sending request for url (https://mcp.example.com)"
        );
        assert_eq!(
            hide_url("Unknown key k3y-in-the-path", url),
            "Unknown key [hidden]"
        );
        assert_eq!(
            hide_url("HTTP 404 for /s/x/mcp", url),
            "HTTP 404 for /s/x/mcp"
        );
    }

    #[test]
    fn hides_a_key_in_the_query() {
        let url = "https://mcp.example.com:8443/mcp?api_key=sk-live-123456&v=2";
        assert_eq!(url_origin(url), "https://mcp.example.com:8443");
        assert_eq!(
            hide_url(&format!("failed: {url}"), url),
            "failed: https://mcp.example.com:8443"
        );
        assert_eq!(
            hide_url("Invalid query api_key=sk-live-123456&v=2", url),
            "Invalid query [hidden]"
        );
        assert_eq!(
            hide_url("Invalid key sk-live-123456", url),
            "Invalid key [hidden]"
        );
        // Short values on their own stay.
        assert_eq!(hide_url("Version 2 failed", url), "Version 2 failed");
    }

    #[test]
    fn hides_the_path_in_discovery_urls() {
        let url = "https://mcp.example.com/s/k3y-in-the-path/mcp";
        assert_eq!(
            hide_url(
                "Metadata error: https://mcp.example.com/.well-known/oauth-protected-resource/s/\
                k3y-in-the-path/mcp returned 404",
                url
            ),
            "Metadata error: https://mcp.example.com/.well-known/oauth-protected-resource[hidden] \
            returned 404"
        );
        // The path also matches in the host, which stays.
        assert_eq!(
            hide_url(
                "https://mcp.example.com/.well-known/oauth-protected-resource/mcp",
                "https://mcp.example.com/mcp"
            ),
            "https://mcp.example.com/.well-known/oauth-protected-resource[hidden]"
        );
    }

    #[test]
    fn keeps_messages_of_urls_without_path_and_query() {
        let url = "https://mcp.example.com/";
        assert_eq!(url_origin(url), "https://mcp.example.com");
        assert_eq!(hide_url("HTTP 500 at /", url), "HTTP 500 at /");
        assert_eq!(
            hide_url("failed: https://mcp.example.com/", url),
            "failed: https://mcp.example.com"
        );
    }
}
