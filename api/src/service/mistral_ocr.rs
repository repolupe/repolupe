//! Text recognition (OCR) with Mistral's OCR API, which converts a whole PDF to Markdown. Used
//! for the documents with scanned pages when the OCR engine is [`OcrEngine::Mistral`].
//!
//! [`OcrEngine::Mistral`]: crate::config::init::OcrEngine::Mistral

use crate::util::http::{client_builder, retry_after};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use reqwest::StatusCode;
use serde::Deserialize;
use serde_json::json;
use std::time::Duration;

const URL: &str = "https://api.mistral.ai/v1/ocr";
/// Part of the stored extractor id, so documents are only converted again when it changes.
pub(crate) const MODEL: &str = "mistral-ocr-latest";

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// Mistral responds once the whole document is recognized.
const REQUEST_TIMEOUT: Duration = Duration::from_mins(5);
const MAX_ATTEMPTS: u32 = 3;
const RETRY_DELAY: Duration = Duration::from_secs(2);
const MAX_RETRY_DELAY: Duration = Duration::from_secs(30);
const MAX_ERROR_BODY_CHARS: usize = 500;

/// Holds a connection pool, so share one instance.
pub(crate) struct MistralOcr {
    http: reqwest::Client,
    url: String,
    api_key: String,
    /// Doubled after every attempt, unless Mistral sends `Retry-After`.
    retry_delay: Duration,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum MistralError {
    /// Mistral cannot convert the document, so trying again fails too.
    #[error("{0}")]
    Rejected(String),
    /// May work later, e.g. after a rate limit, an outage, or once the API key is fixed.
    #[error("{0}")]
    Unavailable(String),
}

#[derive(Deserialize)]
struct OcrResponse {
    pages: Vec<Page>,
}

#[derive(Deserialize)]
struct Page {
    index: u32,
    markdown: String,
}

impl MistralOcr {
    pub(crate) fn new(api_key: String) -> Result<Self, reqwest::Error> {
        Self::with_url(URL.to_string(), api_key, RETRY_DELAY)
    }

    fn with_url(
        url: String,
        api_key: String,
        retry_delay: Duration,
    ) -> Result<Self, reqwest::Error> {
        let http = client_builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .timeout(REQUEST_TIMEOUT)
            .build()?;
        Ok(Self {
            http,
            url,
            api_key,
            retry_delay,
        })
    }

    /// Converts `pdf` to Markdown, with the pages separated by blank lines.
    pub(crate) async fn recognize(&self, pdf: &[u8]) -> Result<String, MistralError> {
        let request = self
            .http
            .post(&self.url)
            .bearer_auth(&self.api_key)
            .json(&json!({
                "model": MODEL,
                "document": {
                    "type": "document_url",
                    "document_url": format!("data:application/pdf;base64,{}", BASE64.encode(pdf)),
                },
                // Only their placeholders are kept, see `without_images`.
                "include_image_base64": false,
            }));
        let response = self.send(request).await?;
        let mut response: OcrResponse = response
            .json()
            .await
            .map_err(|e| MistralError::Unavailable(format!("Invalid response: {e}")))?;
        response.pages.sort_by_key(|page| page.index);
        Ok(response
            .pages
            .iter()
            .map(|page| without_images(&page.markdown))
            .collect::<Vec<_>>()
            .join("\n\n"))
    }

    /// Sends the request, retrying errors that may be temporary.
    async fn send(
        &self,
        request: reqwest::RequestBuilder,
    ) -> Result<reqwest::Response, MistralError> {
        let mut attempt = 1;
        loop {
            // The body is a JSON buffer, so it can be cloned
            let result = request
                .try_clone()
                .expect("JSON requests can be cloned")
                .send()
                .await;
            let (error, retryable, retry_after) = match result {
                Ok(response) if response.status().is_success() => return Ok(response),
                Ok(response) => {
                    let status = response.status();
                    let retry_after = retry_after(response.headers());
                    let body = response.text().await.unwrap_or_default();
                    let body: String = body.chars().take(MAX_ERROR_BODY_CHARS).collect();
                    let message = format!("Mistral responded with {status}: {body}");
                    let error = match status {
                        // Not about the document
                        StatusCode::UNAUTHORIZED
                        | StatusCode::FORBIDDEN
                        | StatusCode::REQUEST_TIMEOUT
                        | StatusCode::TOO_MANY_REQUESTS => MistralError::Unavailable(message),
                        status if status.is_server_error() => MistralError::Unavailable(message),
                        _ => MistralError::Rejected(message),
                    };
                    let retryable = status == StatusCode::TOO_MANY_REQUESTS
                        || status == StatusCode::REQUEST_TIMEOUT
                        || status.is_server_error();
                    (error, retryable, retry_after)
                }
                Err(e) => (
                    MistralError::Unavailable(format!("Request to Mistral failed: {e}")),
                    true,
                    None,
                ),
            };
            if attempt >= MAX_ATTEMPTS || !retryable {
                return Err(error);
            }
            let delay = retry_after
                .unwrap_or(self.retry_delay * (1 << (attempt - 1)))
                .min(MAX_RETRY_DELAY);
            tracing::warn!(
                "Mistral OCR failed (attempt {attempt} of {MAX_ATTEMPTS}), retrying in {delay:?}: {error}"
            );
            tokio::time::sleep(delay).await;
            attempt += 1;
        }
    }
}

/// Removes the placeholders of the images, e.g. `![img-0.jpeg](img-0.jpeg)`, which are not
/// requested, and the blank line they leave.
fn without_images(markdown: &str) -> String {
    let mut lines: Vec<&str> = Vec::new();
    for line in markdown.lines() {
        if is_image_placeholder(line.trim()) {
            continue;
        }
        let blank = line.trim().is_empty();
        if blank && lines.last().is_some_and(|last| last.trim().is_empty()) {
            continue;
        }
        lines.push(line);
    }
    lines.join("\n").trim().to_string()
}

fn is_image_placeholder(line: &str) -> bool {
    line.strip_prefix("![")
        .and_then(|rest| rest.strip_suffix(')'))
        .and_then(|rest| rest.split_once("]("))
        .is_some_and(|(alt, target)| alt == target)
}

/// A local server standing in for Mistral's OCR API.
#[cfg(test)]
pub(crate) mod mock {
    use super::*;
    use axum::Json;
    use axum::extract::State;
    use axum::http::HeaderMap;
    use axum::routing::post;
    use serde_json::Value;
    use std::sync::{Arc, Mutex};

    pub(crate) const API_KEY: &str = "mistral-test-key";

    /// The requests received, with their `Authorization` header.
    pub(crate) type Requests = Arc<Mutex<Vec<(Option<String>, Value)>>>;

    /// Responds to every request with `status` and `body`, without delay between retries.
    pub(crate) async fn serve(status: StatusCode, body: Value) -> (MistralOcr, Requests) {
        let requests = Requests::default();
        let app = axum::Router::new()
            .route(
                "/v1/ocr",
                post(
                    move |State(requests): State<Requests>,
                          headers: HeaderMap,
                          Json(request): Json<Value>| async move {
                        let authorization = headers
                            .get("authorization")
                            .and_then(|value| value.to_str().ok())
                            .map(str::to_string);
                        requests.lock().unwrap().push((authorization, request));
                        (status, Json(body))
                    },
                ),
            )
            .with_state(requests.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/v1/ocr", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let client = MistralOcr::with_url(url, API_KEY.to_string(), Duration::ZERO).unwrap();
        (client, requests)
    }

    /// A response with one page per Markdown text.
    pub(crate) fn pages(pages: &[&str]) -> Value {
        let pages: Vec<Value> = pages
            .iter()
            .enumerate()
            .map(|(index, markdown)| json!({"index": index, "markdown": markdown, "images": []}))
            .collect();
        json!({"pages": pages, "model": MODEL, "usage_info": {"pages_processed": pages.len()}})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[tokio::test]
    async fn recognizes_documents() {
        let mut response =
            mock::pages(&["# Page 1\n\n![img-0.jpeg](img-0.jpeg)\n\nText", "Page 2"]);
        // In any order
        response["pages"].as_array_mut().unwrap().reverse();
        let (client, requests) = mock::serve(StatusCode::OK, response).await;

        let markdown = client.recognize(b"%PDF-1.7").await.unwrap();
        assert_eq!(markdown, "# Page 1\n\nText\n\nPage 2");

        let requests = requests.lock().unwrap();
        let [(authorization, request)] = &requests[..] else {
            panic!("expected one request, got {}", requests.len());
        };
        assert_eq!(authorization.as_deref(), Some("Bearer mistral-test-key"));
        assert_eq!(request["model"], MODEL);
        assert_eq!(
            request["document"],
            json!({"type": "document_url", "document_url": "data:application/pdf;base64,JVBERi0xLjc="})
        );
        assert_eq!(request["include_image_base64"], false);
    }

    #[tokio::test]
    async fn classifies_errors() {
        let error = json!({"object": "error", "message": "Rate limit exceeded", "code": "1300"});
        for (status, rejected, attempts) in [
            (StatusCode::UNPROCESSABLE_ENTITY, true, 1),
            (StatusCode::BAD_REQUEST, true, 1),
            (StatusCode::UNAUTHORIZED, false, 1),
            (StatusCode::TOO_MANY_REQUESTS, false, MAX_ATTEMPTS as usize),
            (StatusCode::BAD_GATEWAY, false, MAX_ATTEMPTS as usize),
        ] {
            let (client, requests) = mock::serve(status, error.clone()).await;
            let result = client.recognize(b"%PDF-1.7").await;
            assert_eq!(
                matches!(result, Err(MistralError::Rejected(_))),
                rejected,
                "{status}: {result:?}"
            );
            assert!(
                result
                    .unwrap_err()
                    .to_string()
                    .contains("Rate limit exceeded")
            );
            assert_eq!(requests.lock().unwrap().len(), attempts, "{status}");
        }
    }

    #[tokio::test]
    async fn rejects_invalid_responses() {
        let (client, _) = mock::serve(StatusCode::OK, Value::Null).await;
        let result = client.recognize(b"%PDF-1.7").await;
        assert!(
            matches!(result, Err(MistralError::Unavailable(_))),
            "{result:?}"
        );
    }

    #[test]
    fn removes_image_placeholders() {
        assert_eq!(
            without_images("Text\n\n![img-1.jpeg](img-1.jpeg)\n\nForm.Nr. 010303"),
            "Text\n\nForm.Nr. 010303"
        );
        assert_eq!(
            without_images("![img-2.jpeg](img-2.jpeg)\n\nText\n"),
            "Text"
        );
        // Only placeholders, not images with a description
        assert_eq!(without_images("![Seal](img-2.jpeg)"), "![Seal](img-2.jpeg)");
    }
}
