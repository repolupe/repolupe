use crate::model::llm_model::ModelPrices;
use crate::model::remote_access::RemoteAccess;
use chrono::FixedOffset;
use rust_decimal::Decimal;
use url::Url;

const MIN_PASSWORD_LENGTH: usize = 8;
const MAX_PASSWORD_LENGTH: usize = 128;
const MAX_EMAIL_LENGTH: usize = 254;
const MAX_USER_NAME_LENGTH: usize = 64;
const MAX_NAME_LENGTH: usize = 100;
const MAX_DESCRIPTION_LENGTH: usize = 2000;
const MAX_REMOTE_URL_LENGTH: usize = 2048;
const MAX_BRANCH_LENGTH: usize = 255;
const MAX_TOKEN_LENGTH: usize = 1024;
const MAX_MODEL_API_NAME_LENGTH: usize = 200;
pub(crate) const MIN_POLL_INTERVAL_SECONDS: i32 = 60;
const MAX_CHAT_TITLE_LENGTH: usize = 200;
const MAX_MESSAGE_LENGTH: usize = 32_000;
const MAX_REPOSITORIES_PER_CHAT: usize = 100;
const MAX_LOCALE_LENGTH: usize = 35;
/// The largest offsets in use are UTC−12:00 and UTC+14:00.
const MAX_UTC_OFFSET_MINUTES: i32 = 14 * 60;
const MAX_FULL_NAME_LENGTH: usize = 100;
const MAX_FIRST_NAME_LENGTH: usize = 100;
const MAX_ABOUT_LENGTH: usize = 1000;
/// Per million tokens, well above any real price but small enough to rule out typos in the scale.
const MAX_PRICE: i64 = 100_000;
const MAX_PRICE_DECIMALS: u32 = 6;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{0}")]
pub(crate) struct ValidationError(pub(crate) String);

pub(crate) fn validate_email(email: &str) -> Result<(), ValidationError> {
    let email = email.trim();
    if email.is_empty() || email.len() > MAX_EMAIL_LENGTH {
        return Err(ValidationError("Invalid email".to_string()));
    }

    let Some((local, domain)) = email.split_once('@') else {
        return Err(ValidationError("Invalid email".to_string()));
    };

    if local.is_empty()
        || domain.is_empty()
        || !domain.contains('.')
        || domain.starts_with('.')
        || domain.ends_with('.')
        || email.chars().any(char::is_whitespace)
    {
        return Err(ValidationError("Invalid email".to_string()));
    }

    Ok(())
}

/// Letters, digits, `.`, `_` and `-`. Without `@`, a user name is never mistaken for an
/// email when logging in.
pub(crate) fn validate_user_name(user_name: &str) -> Result<(), ValidationError> {
    if user_name.is_empty()
        || user_name.len() > MAX_USER_NAME_LENGTH
        || !user_name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
    {
        return Err(ValidationError(format!(
            "User name must be 1 to {MAX_USER_NAME_LENGTH} letters, digits, '.', '_' or '-'"
        )));
    }
    Ok(())
}

pub(crate) fn validate_password(password: &str) -> Result<(), ValidationError> {
    if password.len() < MIN_PASSWORD_LENGTH {
        return Err(ValidationError(format!(
            "Password must be at least {MIN_PASSWORD_LENGTH} characters long"
        )));
    }
    if password.len() > MAX_PASSWORD_LENGTH {
        return Err(ValidationError(format!(
            "Password must be at most {MAX_PASSWORD_LENGTH} characters long"
        )));
    }
    Ok(())
}

/// Names of repositories and LLM providers, display names of LLM models.
pub(crate) fn validate_name(name: &str) -> Result<(), ValidationError> {
    if name.is_empty() || name.chars().count() > MAX_NAME_LENGTH {
        return Err(ValidationError(format!(
            "Name must be 1 to {MAX_NAME_LENGTH} characters long"
        )));
    }
    if name.chars().any(char::is_control) {
        return Err(ValidationError(
            "Name must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

pub(crate) fn validate_description(description: &str) -> Result<(), ValidationError> {
    if description.chars().count() > MAX_DESCRIPTION_LENGTH {
        return Err(ValidationError(format!(
            "Description must be at most {MAX_DESCRIPTION_LENGTH} characters long"
        )));
    }
    Ok(())
}

/// Checks the syntax only. Whether the host resolves to a public address is checked by
/// [`crate::service::mirror`] right before contacting it.
/// Unrestricted access also allows http. Whether the host is public is checked when it is resolved.
pub(crate) fn parse_remote_url(
    remote_url: &str,
    access: RemoteAccess,
) -> Result<Url, ValidationError> {
    let invalid = |msg: &str| ValidationError(msg.to_string());

    if remote_url.len() > MAX_REMOTE_URL_LENGTH {
        return Err(invalid("Remote URL is too long"));
    }
    let url = Url::parse(remote_url).map_err(|_| invalid("Remote URL is not a valid URL"))?;
    match (access, url.scheme()) {
        (_, "https") | (RemoteAccess::Unrestricted, "http") => {}
        (RemoteAccess::Public, _) => return Err(invalid("Remote URL must use https://")),
        (RemoteAccess::Unrestricted, _) => {
            return Err(invalid("Remote URL must use https:// or http://"));
        }
    }
    if url.host_str().is_none_or(str::is_empty) {
        return Err(invalid("Remote URL must have a host"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(invalid(
            "Remote URL must not contain credentials, set a token instead",
        ));
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(invalid("Remote URL must not contain a query or fragment"));
    }
    Ok(url)
}

/// A subset of `git check-ref-format` rules, strict enough to keep the name
/// from being interpreted as anything but a branch.
pub(crate) fn validate_branch(branch: &str) -> Result<(), ValidationError> {
    let invalid = || ValidationError("Invalid branch name".to_string());

    if branch.is_empty() || branch.len() > MAX_BRANCH_LENGTH {
        return Err(invalid());
    }
    if branch.starts_with(['-', '/', '.'])
        || branch.ends_with(['/', '.'])
        || branch.ends_with(".lock")
        || branch.contains("..")
        || branch.contains("//")
        || branch.contains("/.")
        || branch.contains("@{")
        || branch == "@"
        || branch
            .chars()
            .any(|c| c.is_ascii_control() || c.is_whitespace() || "~^:?*[\\".contains(c))
    {
        return Err(invalid());
    }
    Ok(())
}

pub(crate) fn validate_poll_interval(seconds: i32) -> Result<(), ValidationError> {
    if seconds < MIN_POLL_INTERVAL_SECONDS {
        return Err(ValidationError(format!(
            "Poll interval must be at least {MIN_POLL_INTERVAL_SECONDS} seconds"
        )));
    }
    Ok(())
}

/// Tokens end up in an HTTP header, so only visible ASCII is allowed.
pub(crate) fn validate_token(token: &str) -> Result<(), ValidationError> {
    if token.is_empty()
        || token.len() > MAX_TOKEN_LENGTH
        || !token.bytes().all(|b| b.is_ascii_graphic())
    {
        return Err(ValidationError("Invalid token".to_string()));
    }
    Ok(())
}

/// API keys end up in an HTTP header like tokens.
pub(crate) fn validate_api_key(api_key: &str) -> Result<(), ValidationError> {
    validate_token(api_key).map_err(|_| ValidationError("Invalid API key".to_string()))
}

/// The model id sent to the LLM API, e.g. `claude-opus-5-5` or `qwen/qwen3-32b`.
pub(crate) fn validate_model_api_name(api_name: &str) -> Result<(), ValidationError> {
    if api_name.is_empty() || api_name.chars().count() > MAX_MODEL_API_NAME_LENGTH {
        return Err(ValidationError(format!(
            "API name must be 1 to {MAX_MODEL_API_NAME_LENGTH} characters long"
        )));
    }
    if api_name.chars().any(char::is_control) {
        return Err(ValidationError(
            "API name must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

pub(crate) fn validate_max_output_tokens(tokens: i32) -> Result<(), ValidationError> {
    if tokens <= 0 {
        return Err(ValidationError(
            "Maximum output tokens must be positive".to_string(),
        ));
    }
    Ok(())
}

/// Returns the code in upper case. Only the syntax of an ISO 4217 code is checked, not
/// whether the currency exists.
pub(crate) fn parse_currency(currency: &str) -> Result<String, ValidationError> {
    let currency = currency.trim().to_ascii_uppercase();
    if currency.len() != 3 || !currency.bytes().all(|b| b.is_ascii_uppercase()) {
        return Err(ValidationError(
            "Invalid currency, expected a code like USD or EUR".to_string(),
        ));
    }
    Ok(currency)
}

pub(crate) fn validate_model_prices(prices: &ModelPrices) -> Result<(), ValidationError> {
    if prices.input.is_some() != prices.output.is_some() {
        return Err(ValidationError(
            "Input and output price must be set together".to_string(),
        ));
    }
    if prices.input.is_none() && (prices.cache_read.is_some() || prices.cache_write.is_some()) {
        return Err(ValidationError(
            "Cache prices require input and output prices".to_string(),
        ));
    }
    let all = [
        prices.input,
        prices.output,
        prices.cache_read,
        prices.cache_write,
    ];
    for price in all.into_iter().flatten() {
        if price.is_sign_negative() || price > Decimal::from(MAX_PRICE) {
            return Err(ValidationError(format!(
                "Prices must be between 0 and {MAX_PRICE} per million tokens"
            )));
        }
        if price.normalize().scale() > MAX_PRICE_DECIMALS {
            return Err(ValidationError(format!(
                "Prices must have at most {MAX_PRICE_DECIMALS} decimal places"
            )));
        }
    }
    Ok(())
}

/// Returns the URL without trailing slash. Unlike remote URLs, http and private addresses are
/// allowed, e.g. for a local Ollama: only admins set it.
pub(crate) fn parse_llm_base_url(base_url: &str) -> Result<String, ValidationError> {
    let invalid = |msg: &str| ValidationError(msg.to_string());

    if base_url.len() > MAX_REMOTE_URL_LENGTH {
        return Err(invalid("Base URL is too long"));
    }
    let url = Url::parse(base_url).map_err(|_| invalid("Base URL is not a valid URL"))?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(invalid("Base URL must use http:// or https://"));
    }
    if url.host_str().is_none_or(str::is_empty) {
        return Err(invalid("Base URL must have a host"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(invalid(
            "Base URL must not contain credentials, set an API key instead",
        ));
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(invalid("Base URL must not contain a query or fragment"));
    }
    Ok(base_url.trim_end_matches('/').to_string())
}

pub(crate) fn validate_chat_title(title: &str) -> Result<(), ValidationError> {
    if title.is_empty() {
        return Err(ValidationError("Title must not be empty".to_string()));
    }
    if title.chars().count() > MAX_CHAT_TITLE_LENGTH {
        return Err(ValidationError(format!(
            "Title must be at most {MAX_CHAT_TITLE_LENGTH} characters long"
        )));
    }
    if title.chars().any(char::is_control) {
        return Err(ValidationError(
            "Title must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

pub(crate) fn validate_message(content: &str) -> Result<(), ValidationError> {
    if content.trim().is_empty() {
        return Err(ValidationError("Message must not be empty".to_string()));
    }
    if content.chars().count() > MAX_MESSAGE_LENGTH {
        return Err(ValidationError(format!(
            "Message must be at most {MAX_MESSAGE_LENGTH} characters long"
        )));
    }
    Ok(())
}

pub(crate) fn validate_repository_selection(ids: &[uuid::Uuid]) -> Result<(), ValidationError> {
    if ids.len() > MAX_REPOSITORIES_PER_CHAT {
        return Err(ValidationError(format!(
            "At most {MAX_REPOSITORIES_PER_CHAT} repositories can be selected"
        )));
    }
    Ok(())
}

/// The syntax of a BCP 47 language tag such as `en`, `de-DE` or `zh-Hant-TW`: a 2 to 3 letter
/// language followed by subtags of 1 to 8 letters or digits. Whether the subtags exist is not checked.
pub(crate) fn validate_locale(locale: &str) -> Result<(), ValidationError> {
    let invalid = || ValidationError("Invalid locale, expected a tag like en or de-DE".to_string());

    if locale.len() > MAX_LOCALE_LENGTH {
        return Err(invalid());
    }
    let mut subtags = locale.split('-');
    let language = subtags.next().unwrap_or_default();
    if !(2..=3).contains(&language.len()) || !language.bytes().all(|b| b.is_ascii_alphabetic()) {
        return Err(invalid());
    }
    if !subtags.all(|s| (1..=8).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_alphanumeric()))
    {
        return Err(invalid());
    }
    Ok(())
}

/// Minutes east of UTC, e.g. 60 for UTC+01:00.
pub(crate) fn parse_utc_offset(minutes: i32) -> Result<FixedOffset, ValidationError> {
    if minutes.abs() > MAX_UTC_OFFSET_MINUTES {
        return Err(ValidationError(format!(
            "UTC offset must be between -{MAX_UTC_OFFSET_MINUTES} and {MAX_UTC_OFFSET_MINUTES} minutes"
        )));
    }
    FixedOffset::east_opt(minutes * 60)
        .ok_or_else(|| ValidationError("Invalid UTC offset".to_string()))
}

pub(crate) fn validate_full_name(full_name: &str) -> Result<(), ValidationError> {
    if full_name.chars().count() > MAX_FULL_NAME_LENGTH {
        return Err(ValidationError(format!(
            "Full name must be at most {MAX_FULL_NAME_LENGTH} characters long"
        )));
    }
    if full_name.chars().any(char::is_control) {
        return Err(ValidationError(
            "Full name must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

pub(crate) fn validate_first_name(first_name: &str) -> Result<(), ValidationError> {
    if first_name.chars().count() > MAX_FIRST_NAME_LENGTH {
        return Err(ValidationError(format!(
            "First name must be at most {MAX_FIRST_NAME_LENGTH} characters long"
        )));
    }
    if first_name.chars().any(char::is_control) {
        return Err(ValidationError(
            "First name must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

/// Free text over several lines.
pub(crate) fn validate_about(about: &str) -> Result<(), ValidationError> {
    if about.chars().count() > MAX_ABOUT_LENGTH {
        return Err(ValidationError(format!(
            "About must be at most {MAX_ABOUT_LENGTH} characters long"
        )));
    }
    if about
        .chars()
        .any(|c| c.is_control() && !matches!(c, '\n' | '\r' | '\t'))
    {
        return Err(ValidationError(
            "About must not contain control characters".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_valid_email() {
        assert!(validate_email("user@example.com").is_ok());
        assert!(validate_email("first.last+tag@sub.example.org").is_ok());
    }

    #[test]
    fn accepts_valid_user_name() {
        for user_name in ["admin", "Bob", "first.last", "user_1-2"] {
            assert!(
                validate_user_name(user_name).is_ok(),
                "{user_name} should be valid"
            );
        }
    }

    #[test]
    fn rejects_invalid_user_name() {
        for user_name in [
            "",
            "bob@example.com",
            "first last",
            "jürgen",
            &"a".repeat(65),
        ] {
            assert!(
                validate_user_name(user_name).is_err(),
                "{user_name} should be invalid"
            );
        }
    }

    #[test]
    fn rejects_invalid_email() {
        for email in [
            "",
            "user",
            "user@",
            "@example.com",
            "user@example",
            "us er@example.com",
            "user@.com",
        ] {
            assert!(validate_email(email).is_err(), "{email} should be invalid");
        }
    }

    #[test]
    fn validates_password_length() {
        assert!(validate_password("short").is_err());
        assert!(validate_password("longenough").is_ok());
        assert!(validate_password(&"x".repeat(129)).is_err());
    }

    #[test]
    fn validates_remote_url() {
        for access in [RemoteAccess::Public, RemoteAccess::Unrestricted] {
            assert!(parse_remote_url("https://github.com/owner/repo.git", access).is_ok());
            for url in [
                "git@github.com:owner/repo.git",
                "ssh://github.com/owner/repo",
                "file:///etc/passwd",
                "https://user:ghp_x@github.com/owner/repo",
                "https://github.com/owner/repo?x=1",
                "not a url",
            ] {
                assert!(
                    parse_remote_url(url, access).is_err(),
                    "{url} should be invalid"
                );
            }
        }
        let http = "http://git.internal/owner/repo";
        assert!(parse_remote_url(http, RemoteAccess::Public).is_err());
        assert!(parse_remote_url(http, RemoteAccess::Unrestricted).is_ok());
    }

    #[test]
    fn validates_branch() {
        for branch in ["main", "release/1.0", "feature/x-y_z"] {
            assert!(validate_branch(branch).is_ok(), "{branch} should be valid");
        }
        for branch in [
            "",
            "-main",
            "--upload-pack=x",
            "a..b",
            "a b",
            "a~1",
            "a^",
            "a:b",
            "a/",
            "a.lock",
            "/a",
            ".a",
            "a//b",
            "a@{1}",
            "@",
        ] {
            assert!(
                validate_branch(branch).is_err(),
                "{branch} should be invalid"
            );
        }
    }

    #[test]
    fn parses_llm_base_url() {
        assert_eq!(
            parse_llm_base_url("http://localhost:11434/v1/").unwrap(),
            "http://localhost:11434/v1"
        );
        assert_eq!(
            parse_llm_base_url("https://api.anthropic.com").unwrap(),
            "https://api.anthropic.com"
        );
        for url in [
            "localhost:11434",
            "ftp://example.com",
            "https://user:key@example.com",
            "https://example.com/v1?key=x",
            "not a url",
        ] {
            assert!(parse_llm_base_url(url).is_err(), "{url} should be invalid");
        }
    }

    #[test]
    fn validates_model_api_name() {
        assert!(validate_model_api_name("claude-opus-5-5").is_ok());
        assert!(validate_model_api_name("qwen/qwen3-32b:free").is_ok());
        assert!(validate_model_api_name("").is_err());
        assert!(validate_model_api_name("a\nb").is_err());
        assert!(validate_model_api_name(&"x".repeat(201)).is_err());
    }

    #[test]
    fn validates_token() {
        assert!(validate_token("ghp_abc123").is_ok());
        assert!(validate_token("").is_err());
        assert!(validate_token("abc\r\nX-Injected: 1").is_err());
        assert!(validate_token("with space").is_err());
    }

    #[test]
    fn validates_profile() {
        assert!(validate_full_name("Alice Doe").is_ok());
        assert!(validate_full_name("Alice\nDoe").is_err());
        assert!(validate_full_name(&"x".repeat(101)).is_err());
        assert!(validate_first_name("Alice").is_ok());
        assert!(validate_first_name("Ali\tce").is_err());
        assert!(validate_first_name(&"x".repeat(101)).is_err());
        assert!(validate_about("Married to Bob.\nMy documents are in /alice.").is_ok());
        assert!(validate_about("a\u{0}b").is_err());
        assert!(validate_about(&"x".repeat(1001)).is_err());
    }

    #[test]
    fn validates_locale() {
        for locale in ["en", "de-DE", "zh-Hant-TW", "es-419", "gsw"] {
            assert!(validate_locale(locale).is_ok(), "{locale} should be valid");
        }
        for locale in [
            "",
            "e",
            "english",
            "en_US",
            "en-",
            "-en",
            "en--US",
            "en-toolongsubtag",
            "de DE",
            "1n",
            &format!("en-{}", "a".repeat(40)),
        ] {
            assert!(
                validate_locale(locale).is_err(),
                "{locale} should be invalid"
            );
        }
    }

    #[test]
    fn parses_utc_offset() {
        assert_eq!(parse_utc_offset(60).unwrap().to_string(), "+01:00");
        assert_eq!(parse_utc_offset(-570).unwrap().to_string(), "-09:30");
        assert_eq!(parse_utc_offset(840).unwrap().to_string(), "+14:00");
        assert!(parse_utc_offset(841).is_err());
        assert!(parse_utc_offset(-841).is_err());
    }

    #[test]
    fn parses_currency() {
        assert_eq!(parse_currency(" usd ").unwrap(), "USD");
        assert_eq!(parse_currency("EUR").unwrap(), "EUR");
        for currency in ["", "$", "US", "USDT", "U5D", "€UR"] {
            assert!(
                parse_currency(currency).is_err(),
                "{currency} should be invalid"
            );
        }
    }

    #[test]
    fn validates_model_prices() {
        use std::str::FromStr;
        let price = |value: &str| Some(Decimal::from_str(value).unwrap());
        let prices = |input, output, cache_read, cache_write| ModelPrices {
            input,
            output,
            cache_read,
            cache_write,
        };

        assert!(validate_model_prices(&ModelPrices::default()).is_ok());
        assert!(validate_model_prices(&prices(price("3"), price("15"), None, None)).is_ok());
        assert!(
            validate_model_prices(&prices(
                price("3"),
                price("15"),
                price("0.3"),
                price("3.750000")
            ))
            .is_ok()
        );
        assert!(validate_model_prices(&prices(price("0"), price("0"), None, None)).is_ok());

        // only one of input and output
        assert!(validate_model_prices(&prices(price("3"), None, None, None)).is_err());
        assert!(validate_model_prices(&prices(None, price("15"), None, None)).is_err());
        // cache price without input and output
        assert!(validate_model_prices(&prices(None, None, price("0.3"), None)).is_err());
        // out of range or too precise
        assert!(validate_model_prices(&prices(price("-1"), price("15"), None, None)).is_err());
        assert!(validate_model_prices(&prices(price("3"), price("100001"), None, None)).is_err());
        assert!(
            validate_model_prices(&prices(price("3"), price("15"), price("0.0000001"), None))
                .is_err()
        );
    }
}
