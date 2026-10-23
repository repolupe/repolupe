//! The generic transport every client request goes through: a Repolupe server over HTTP, or the
//! router of a local instance in-process. Both take the same request (method, path, headers,
//! body) and produce the same response, so typed endpoint wrappers are thin layers over
//! [`Transport::request`] and [`Transport::request_stream`] and the two paths can't diverge.

use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::task::{Context, Poll};
use std::time::Duration;

use axum::Router;
use axum::body::Body;
use axum::http::{HeaderMap, Method, Request, StatusCode};
use bytes::{Bytes, BytesMut};
use futures_util::stream::{BoxStream, Stream, StreamExt, TryStreamExt};
use serde::de::DeserializeOwned;
use tokio::sync::mpsc;
use tower::ServiceExt;

use crate::api::error::ClientError;
use crate::runtime;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);

/// The error of a request to a local instance that was shut down.
pub const STOPPED: &str = "The local instance was shut down.";

/// Chunks of a streaming response read ahead of the consumer.
const STREAM_BUFFER: usize = 16;

/// A builder for the HTTP client. HTTPS uses rustls with the platform's certificate verifier,
/// except on Android, where it would have to be initialized through JNI: there, the Mozilla
/// roots of `webpki-root-certs` are used instead, like in the `repolupe` crate.
fn client_builder() -> reqwest::ClientBuilder {
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

type BodyStream = BoxStream<'static, Result<Bytes, ClientError>>;

/// Where requests go. Cheap to clone (both variants are reference-counted).
#[derive(Clone, Debug)]
pub enum Transport {
    /// A Repolupe server, e.g. `https://repolupe.example.com` (without `/api/v1`).
    Remote {
        base_url: String,
        client: reqwest::Client,
    },
    /// The router of a local instance (`Repolupe::router()`). Requests run through all of its
    /// middleware, exactly as on a server. Once `stopped` is set (the instance was shut down),
    /// requests fail like those to an unreachable server.
    Local {
        router: Router,
        stopped: Arc<AtomicBool>,
    },
}

/// A complete response with a successful status.
#[derive(Clone, Debug)]
pub struct Response {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: Bytes,
}

/// A response with a successful status whose body is read while it arrives (SSE).
#[derive(Debug)]
pub struct StreamResponse {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: ByteStream,
}

/// The body chunks of a [`StreamResponse`]. It can be polled on any executor; dropping it
/// cancels the request. After an error, it ends.
#[derive(Debug)]
pub struct ByteStream {
    receiver: mpsc::Receiver<Result<Bytes, ClientError>>,
}

impl Stream for ByteStream {
    type Item = Result<Bytes, ClientError>;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.receiver.poll_recv(cx)
    }
}

impl ByteStream {
    /// A stream of `chunks` that ends after them.
    #[cfg(test)]
    pub(crate) fn from_chunks(chunks: Vec<Result<Bytes, ClientError>>) -> Self {
        let (sender, receiver) = mpsc::channel(chunks.len().max(1));
        for chunk in chunks {
            sender.try_send(chunk).unwrap();
        }
        ByteStream { receiver }
    }
}

impl Response {
    /// The body parsed as JSON.
    pub fn json<T: DeserializeOwned>(&self) -> Result<T, ClientError> {
        serde_json::from_slice(&self.body).map_err(|error| ClientError::InvalidResponse {
            status: self.status.as_u16(),
            message: format!("Invalid response body: {error}"),
        })
    }
}

impl Transport {
    /// A transport to the server at `base_url` (http or https, may have a path prefix). HTTPS
    /// uses rustls, see `client_builder`.
    pub fn remote(base_url: &str) -> Result<Self, ClientError> {
        let invalid = || ClientError::Transport {
            message: format!("Invalid server URL: {base_url}"),
        };
        let url = reqwest::Url::parse(base_url).map_err(|_| invalid())?;
        if !matches!(url.scheme(), "http" | "https")
            || url.host().is_none()
            || url.query().is_some()
            || url.fragment().is_some()
        {
            return Err(invalid());
        }
        let client = client_builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .user_agent(concat!("repolupe-app/", env!("CARGO_PKG_VERSION")))
            .build()
            .map_err(|error| ClientError::transport(&error))?;
        Ok(Transport::Remote {
            base_url: url.as_str().trim_end_matches('/').to_owned(),
            client,
        })
    }

    /// A transport to a local instance's router.
    pub fn local(router: Router) -> Self {
        Self::stoppable_local(router, Arc::default())
    }

    /// A transport to a local instance's router whose requests fail with
    /// [`ClientError::Transport`] once `stopped` is set, e.g. by `LocalHandle::shutdown`.
    pub fn stoppable_local(router: Router, stopped: Arc<AtomicBool>) -> Self {
        Transport::Local { router, stopped }
    }

    /// Sends a request and reads the whole response. `path` starts with `/` and may have a
    /// query (`/api/v1/chats?limit=20`). An unsuccessful status becomes [`ClientError::Api`]
    /// (or [`ClientError::InvalidResponse`] if the body is not an `ErrorDto`).
    ///
    /// Runs on the crate's runtime, so it can be awaited on any executor; dropping the future
    /// cancels the request.
    pub async fn request(
        &self,
        method: Method,
        path: &str,
        headers: HeaderMap,
        body: Bytes,
    ) -> Result<Response, ClientError> {
        let transport = self.clone();
        let path = path.to_owned();
        runtime::run(async move {
            let (status, headers, body) = transport.send(method, &path, headers, body).await?;
            let body = collect(body).await?;
            if !status.is_success() {
                return Err(ClientError::from_error_response(status, &body));
            }
            Ok(Response {
                status,
                headers,
                body,
            })
        })
        .await
    }

    /// Like [`Transport::request`], but returns once the response head arrived, with the body as
    /// a stream of chunks (for SSE). An unsuccessful status is read completely and returned as
    /// an error, like in `request`.
    pub async fn request_stream(
        &self,
        method: Method,
        path: &str,
        headers: HeaderMap,
        body: Bytes,
    ) -> Result<StreamResponse, ClientError> {
        let transport = self.clone();
        let path = path.to_owned();
        runtime::run(async move {
            let (status, headers, body) = transport.send(method, &path, headers, body).await?;
            if !status.is_success() {
                let body = collect(body).await?;
                return Err(ClientError::from_error_response(status, &body));
            }
            // The body is polled on the runtime too (reqwest's timers, axum's SSE keep-alive),
            // and handed over through a channel, which works on any executor.
            let (sender, receiver) = mpsc::channel(STREAM_BUFFER);
            tokio::spawn(forward(body, sender));
            Ok(StreamResponse {
                status,
                headers,
                body: ByteStream { receiver },
            })
        })
        .await
    }

    /// Sends the request and returns the response head with its body unread. Must run on the
    /// crate's runtime.
    async fn send(
        &self,
        method: Method,
        path: &str,
        headers: HeaderMap,
        body: Bytes,
    ) -> Result<(StatusCode, HeaderMap, BodyStream), ClientError> {
        if !path.starts_with('/') {
            return Err(ClientError::Transport {
                message: format!("Invalid path: {path}"),
            });
        }
        match self {
            Transport::Remote { base_url, client } => {
                let response = client
                    .request(method, format!("{base_url}{path}"))
                    .headers(headers)
                    .body(body)
                    .send()
                    .await
                    .map_err(|error| ClientError::transport(&error))?;
                let status = response.status();
                let headers = response.headers().clone();
                let body = response
                    .bytes_stream()
                    .map_err(|error| ClientError::transport(&error));
                Ok((status, headers, body.boxed()))
            }
            Transport::Local { router, stopped } => {
                if stopped.load(Ordering::Acquire) {
                    return Err(ClientError::Transport {
                        message: STOPPED.to_owned(),
                    });
                }
                let mut request = Request::builder()
                    .method(method)
                    .uri(path)
                    .body(Body::from(body))
                    .map_err(|error| ClientError::transport(&error))?;
                *request.headers_mut() = headers;
                let response = match router.clone().oneshot(request).await {
                    Ok(response) => response,
                    Err(never) => match never {},
                };
                let (parts, body) = response.into_parts();
                let body = body
                    .into_data_stream()
                    .map_err(|error| ClientError::transport(&error));
                Ok((parts.status, parts.headers, body.boxed()))
            }
        }
    }
}

async fn collect(mut body: BodyStream) -> Result<Bytes, ClientError> {
    let mut buffer = BytesMut::new();
    while let Some(chunk) = body.next().await {
        buffer.extend_from_slice(&chunk?);
    }
    Ok(buffer.freeze())
}

/// Hands the chunks of `body` to `sender` until either ends. Stops as soon as the receiver is
/// dropped, even while the body is idle, which drops the body and so cancels the request.
async fn forward(mut body: BodyStream, sender: mpsc::Sender<Result<Bytes, ClientError>>) {
    loop {
        let chunk = tokio::select! {
            () = sender.closed() => return,
            chunk = body.next() => chunk,
        };
        let Some(chunk) = chunk else { return };
        if matches!(&chunk, Ok(bytes) if bytes.is_empty()) {
            continue;
        }
        let failed = chunk.is_err();
        if sender.send(chunk).await.is_err() || failed {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;
    use std::sync::mpsc as std_mpsc;

    use axum::http::Uri;
    use axum::http::header::{CONTENT_TYPE, HeaderValue};
    use axum::response::IntoResponse;
    use axum::routing::{any, get};
    use futures_executor::block_on;
    use futures_util::stream;
    use repolupe::dto::error::{ErrorCode, ErrorDto};

    use super::*;

    fn app(dropped: Option<std_mpsc::Sender<()>>) -> Router {
        Router::new()
            .route("/echo", any(echo))
            .route("/error", get(error))
            .route("/proxy-error", get(proxy_error))
            .route("/panic", get(panic))
            .route("/stream", get(chunks))
            .route("/endless", get(move || endless(dropped.clone())))
    }

    async fn echo(method: Method, uri: Uri, headers: HeaderMap, body: Bytes) -> impl IntoResponse {
        let header = headers.get("x-test").and_then(|value| value.to_str().ok());
        let text = format!(
            "{method} {uri} {} {}",
            header.unwrap_or("-"),
            String::from_utf8_lossy(&body)
        );
        ([("x-echo", "yes")], text)
    }

    async fn error() -> impl IntoResponse {
        let body = serde_json::to_string(&ErrorDto {
            code: ErrorCode::NotFound,
            message: "Chat not found.".into(),
        })
        .unwrap();
        (
            StatusCode::NOT_FOUND,
            [(CONTENT_TYPE, "application/json")],
            body,
        )
    }

    async fn proxy_error() -> impl IntoResponse {
        (StatusCode::BAD_GATEWAY, "<html>Bad Gateway</html>")
    }

    async fn panic() -> &'static str {
        panic!("handler panicked on purpose");
    }

    /// Three chunks with pauses, which need the runtime's timer.
    async fn chunks() -> Body {
        Body::from_stream(stream::iter(["a", "b", "c"]).then(|chunk| async move {
            tokio::time::sleep(Duration::from_millis(20)).await;
            Ok::<_, Infallible>(chunk)
        }))
    }

    /// One chunk, then nothing; reports through `dropped` when the body is dropped.
    async fn endless(dropped: Option<std_mpsc::Sender<()>>) -> Body {
        struct Guard(Option<std_mpsc::Sender<()>>);
        impl Drop for Guard {
            fn drop(&mut self) {
                if let Some(sender) = &self.0 {
                    let _ = sender.send(());
                }
            }
        }
        let guard = Guard(dropped);
        let first = stream::once(async { Ok::<_, Infallible>("first") });
        let rest = stream::pending().map(move |()| {
            let _ = &guard;
            Ok("never")
        });
        Body::from_stream(first.chain(rest))
    }

    /// The same router behind both transports.
    fn transports(dropped: Option<std_mpsc::Sender<()>>) -> Vec<Transport> {
        let router = app(dropped);
        let local = Transport::local(router.clone());
        let address = runtime::runtime().block_on(async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
            address
        });
        let remote = Transport::remote(&format!("http://{address}/")).unwrap();
        vec![local, remote]
    }

    // The tests block on a futures executor, not tokio, as FRB does.

    #[test]
    fn sends_method_path_headers_and_body() {
        for transport in transports(None) {
            let mut headers = HeaderMap::new();
            headers.insert("x-test", HeaderValue::from_static("1"));
            let response = block_on(transport.request(
                Method::POST,
                "/echo?a=b",
                headers,
                Bytes::from_static(b"hello"),
            ))
            .unwrap();
            assert_eq!(response.status, StatusCode::OK);
            assert_eq!(response.headers["x-echo"], "yes");
            assert_eq!(response.body, "POST /echo?a=b 1 hello");
        }
    }

    #[test]
    fn parses_api_errors() {
        for transport in transports(None) {
            let error =
                block_on(transport.request(Method::GET, "/error", HeaderMap::new(), Bytes::new()));
            assert_eq!(
                error.unwrap_err(),
                ClientError::Api {
                    status: 404,
                    code: ErrorCode::NotFound,
                    message: "Chat not found.".into(),
                }
            );
        }
    }

    #[test]
    fn other_errors_are_invalid_responses() {
        for transport in transports(None) {
            for path in ["/proxy-error", "/missing"] {
                let error =
                    block_on(transport.request(Method::GET, path, HeaderMap::new(), Bytes::new()));
                assert!(
                    matches!(
                        error,
                        Err(ClientError::InvalidResponse {
                            status: 502 | 404,
                            ..
                        })
                    ),
                    "{path}: {error:?}"
                );
            }
        }
    }

    #[test]
    fn panics_and_bad_paths_are_transport_errors() {
        for transport in transports(None) {
            let error =
                block_on(transport.request(Method::GET, "/panic", HeaderMap::new(), Bytes::new()));
            assert!(
                matches!(error, Err(ClientError::Transport { .. })),
                "{error:?}"
            );
            let error =
                block_on(transport.request(Method::GET, "echo", HeaderMap::new(), Bytes::new()));
            assert!(
                matches!(error, Err(ClientError::Transport { .. })),
                "{error:?}"
            );
        }
    }

    #[test]
    fn unreachable_servers_are_transport_errors() {
        // Port 1 is reserved, nothing listens there.
        let transport = Transport::remote("http://127.0.0.1:1").unwrap();
        let error =
            block_on(transport.request(Method::GET, "/echo", HeaderMap::new(), Bytes::new()));
        assert!(
            matches!(error, Err(ClientError::Transport { .. })),
            "{error:?}"
        );
    }

    #[test]
    fn validates_the_base_url() {
        let Transport::Remote { base_url, .. } =
            Transport::remote("https://example.com/repolupe/").unwrap()
        else {
            unreachable!()
        };
        assert_eq!(base_url, "https://example.com/repolupe");
        for url in [
            "example.com",
            "ftp://example.com",
            "https://example.com/?a=b",
            "unix:/run/socket",
        ] {
            assert!(Transport::remote(url).is_err(), "{url}");
        }
    }

    #[test]
    fn json_parses_the_body() {
        let response = Response {
            status: StatusCode::OK,
            headers: HeaderMap::new(),
            body: Bytes::from_static(br#"{"code":"CONFLICT","message":"m"}"#),
        };
        let dto: ErrorDto = response.json().unwrap();
        assert_eq!(dto.code, ErrorCode::Conflict);
        let error = response.json::<Vec<String>>().unwrap_err();
        assert!(
            matches!(error, ClientError::InvalidResponse { status: 200, .. }),
            "{error:?}"
        );
    }

    #[test]
    fn streams_the_body() {
        for transport in transports(None) {
            let response = block_on(transport.request_stream(
                Method::GET,
                "/stream",
                HeaderMap::new(),
                Bytes::new(),
            ))
            .unwrap();
            assert_eq!(response.status, StatusCode::OK);
            let chunks: Vec<Bytes> = block_on(response.body.try_collect()).unwrap();
            assert_eq!(chunks.concat(), b"abc");
        }
    }

    #[test]
    fn streaming_errors_are_read_completely() {
        for transport in transports(None) {
            let error = block_on(transport.request_stream(
                Method::GET,
                "/error",
                HeaderMap::new(),
                Bytes::new(),
            ));
            assert!(
                matches!(
                    error,
                    Err(ClientError::Api {
                        code: ErrorCode::NotFound,
                        ..
                    })
                ),
                "{error:?}"
            );
        }
    }

    #[test]
    fn dropping_the_stream_cancels_the_request() {
        let (sender, dropped) = std_mpsc::channel();
        for transport in transports(Some(sender)) {
            let mut response = block_on(transport.request_stream(
                Method::GET,
                "/endless",
                HeaderMap::new(),
                Bytes::new(),
            ))
            .unwrap();
            let first = block_on(response.body.next()).unwrap().unwrap();
            assert_eq!(first, "first");
            drop(response);
            dropped
                .recv_timeout(Duration::from_secs(5))
                .expect("the body was not dropped");
        }
    }
}
