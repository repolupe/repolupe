//! The HTTP client of gitoxide's smart HTTP transport, implemented with our `reqwest` client,
//! so connections go through [`PublicResolver`](crate::util::ip::PublicResolver) like the ones
//! of Git LFS. gitoxide's transport is blocking, so this runs on a blocking thread and waits
//! for the async client with [`Handle::block_on`].

use crate::util::ip::is_not_public;
use bytes::Bytes;
use gix::protocol::transport::client::blocking_io::http::{
    self, GetResponse, Http, PostBodyDataKind, PostResponse,
};
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE, HeaderName, HeaderValue};
use reqwest::{RequestBuilder, Response, StatusCode};
use std::any::Any;
use std::io::{self, BufRead, Read, Write};
use std::sync::{Arc, Mutex};
use tokio::runtime::Handle;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;

/// Why a request failed, kept to tell the user, since gitoxide's errors are meant for
/// developers.
#[derive(Clone, Debug)]
pub(super) enum Failure {
    Status(StatusCode),
    /// The server is reachable, but is no git server, or only supports the dumb protocol.
    NotSmartGit,
    NotPublic,
    TimedOut,
    Cancelled,
    Request(String),
}

/// Sends gitoxide's requests with `client` until `deadline` or until `cancel` is cancelled.
pub(super) struct GitHttp {
    context: Arc<Context>,
}

struct Context {
    client: reqwest::Client,
    runtime: Handle,
    deadline: Instant,
    cancel: CancellationToken,
    authorization: Option<HeaderValue>,
    /// The first failure.
    failure: Arc<Mutex<Option<Failure>>>,
}

impl GitHttp {
    /// `failure` receives the first failure of a request.
    pub(super) fn new(
        client: reqwest::Client,
        runtime: Handle,
        deadline: Instant,
        cancel: CancellationToken,
        authorization: Option<HeaderValue>,
        failure: Arc<Mutex<Option<Failure>>>,
    ) -> Self {
        Self {
            context: Arc::new(Context {
                client,
                runtime,
                deadline,
                cancel,
                authorization,
                failure,
            }),
        }
    }

    fn exchange(
        &self,
        request: RequestBuilder,
        headers: impl IntoIterator<Item = impl AsRef<str>>,
        post: bool,
    ) -> Shared {
        let mut request = request;
        for header in headers {
            // `Name: value` lines, as gitoxide passes them.
            if let Some((name, value)) = header.as_ref().split_once(':')
                && let Ok(name) = HeaderName::try_from(name.trim())
                && let Ok(value) = HeaderValue::try_from(value.trim())
            {
                request = request.header(name, value);
            }
        }
        if let Some(authorization) = &self.context.authorization {
            request = request.header(AUTHORIZATION, authorization.clone());
        }
        Arc::new(Mutex::new(Exchange {
            context: self.context.clone(),
            request: Some(request),
            body: post.then(Vec::new),
            response: None,
        }))
    }
}

impl Http for GitHttp {
    type Headers = Headers;
    type ResponseBody = Body;
    type PostBody = PostBody;

    fn get(
        &mut self,
        url: &str,
        _base_url: &str,
        headers: impl IntoIterator<Item = impl AsRef<str>>,
    ) -> gix::error::Result<GetResponse<Headers, Body>> {
        let exchange = self.exchange(self.context.client.get(url), headers, false);
        // Sent right away, so a failure is reported by the handshake.
        lock(&exchange)
            .send()
            .map_err(gix::error::Error::from_error)?;
        // Smart servers answer the advertisement with their own content type.
        if let Some(Ok(response)) = &lock(&exchange).response
            && !response
                .headers()
                .get(CONTENT_TYPE)
                .is_some_and(|value| value.as_bytes().starts_with(b"application/x-git-"))
        {
            self.context.fail(Failure::NotSmartGit);
        }
        Ok(GetResponse {
            headers: Headers::new(exchange.clone()),
            body: Body::new(exchange),
        })
    }

    fn post(
        &mut self,
        url: &str,
        _base_url: &str,
        headers: impl IntoIterator<Item = impl AsRef<str>>,
        _body: PostBodyDataKind,
    ) -> gix::error::Result<PostResponse<Headers, Body, PostBody>> {
        let exchange = self.exchange(self.context.client.post(url), headers, true);
        Ok(PostResponse {
            post_body: PostBody(exchange.clone()),
            headers: Headers::new(exchange.clone()),
            body: Body::new(exchange),
        })
    }

    /// The options from the git config are ignored, our client is configured already.
    fn configure(&mut self, _config: &dyn Any) -> gix::error::Result {
        Ok(())
    }
}

impl Context {
    /// Waits for `future` on the runtime, up to the deadline.
    fn wait<F: Future>(&self, future: F) -> Result<F::Output, Failure> {
        if self.cancel.is_cancelled() {
            return Err(Failure::Cancelled);
        }
        self.runtime.block_on(async {
            tokio::select! {
                _ = self.cancel.cancelled() => Err(Failure::Cancelled),
                output = tokio::time::timeout_at(self.deadline, future) => {
                    output.map_err(|_| Failure::TimedOut)
                }
            }
        })
    }

    fn send(&self, request: RequestBuilder) -> io::Result<Response> {
        let failure = match self.wait(request.send()) {
            Ok(Ok(response)) if response.status().is_success() => return Ok(response),
            Ok(Ok(response)) => Failure::Status(response.status()),
            Ok(Err(e)) => self.request_failure(&e),
            Err(failure) => failure,
        };
        Err(self.fail(failure))
    }

    fn chunk(&self, response: &mut Response) -> io::Result<Option<Bytes>> {
        match self.wait(response.chunk()) {
            Ok(Ok(chunk)) => Ok(chunk),
            Ok(Err(e)) => Err(self.fail(self.request_failure(&e))),
            Err(failure) => Err(self.fail(failure)),
        }
    }

    fn request_failure(&self, error: &reqwest::Error) -> Failure {
        if is_not_public(error) {
            Failure::NotPublic
        } else if error.is_timeout() {
            Failure::TimedOut
        } else {
            Failure::Request(error_chain(error))
        }
    }

    /// Records `failure` if it is the first, and returns the error for gitoxide.
    fn fail(&self, failure: Failure) -> io::Error {
        let error = match &failure {
            // gitoxide asks for credentials on `PermissionDenied`.
            Failure::Status(StatusCode::UNAUTHORIZED) => io::Error::new(
                io::ErrorKind::PermissionDenied,
                "the remote requires authentication",
            ),
            Failure::Status(status) => {
                io::Error::other(format!("the remote responded with {status}"))
            }
            Failure::NotSmartGit => io::Error::other("the remote is no smart git server"),
            Failure::NotPublic => io::Error::other("the remote is not public"),
            Failure::TimedOut => io::Error::new(io::ErrorKind::TimedOut, "timed out"),
            Failure::Cancelled => io::Error::new(io::ErrorKind::Interrupted, "cancelled"),
            Failure::Request(message) => io::Error::other(message.clone()),
        };
        lock(&self.failure).get_or_insert(failure);
        error
    }
}

/// `error` and its sources, e.g. `error sending request: client error (Connect): ...`.
fn error_chain(error: &dyn std::error::Error) -> String {
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(e) = source {
        message.push_str(": ");
        message.push_str(&e.to_string());
        source = e.source();
    }
    message
}

type Shared = Arc<Mutex<Exchange>>;

/// A request, sent when its response is first read, after gitoxide wrote the body of a POST.
struct Exchange {
    context: Arc<Context>,
    /// Until sent.
    request: Option<RequestBuilder>,
    /// The body to POST, `None` for a GET.
    body: Option<Vec<u8>>,
    /// Once sent. The error is kept to return it again to the next reader.
    response: Option<Result<Response, (io::ErrorKind, String)>>,
}

impl Exchange {
    fn send(&mut self) -> io::Result<()> {
        if let Some(mut request) = self.request.take() {
            if let Some(body) = self.body.take() {
                request = request.body(body);
            }
            self.response = Some(
                self.context
                    .send(request)
                    .map_err(|e| (e.kind(), e.to_string())),
            );
        }
        match &self.response {
            Some(Err((kind, message))) => Err(io::Error::new(*kind, message.clone())),
            _ => Ok(()),
        }
    }
}

fn lock<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|e| e.into_inner())
}

/// Collects the body of a POST.
pub(super) struct PostBody(Shared);

impl Write for PostBody {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match &mut lock(&self.0).body {
            Some(body) => body.extend_from_slice(buf),
            None => return Err(io::Error::other("the request was sent already")),
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// The response headers as `name:value` lines, which gitoxide reads before the body.
pub(super) struct Headers {
    exchange: Shared,
    lines: Option<io::Cursor<Vec<u8>>>,
}

impl Headers {
    fn new(exchange: Shared) -> Self {
        Self {
            exchange,
            lines: None,
        }
    }
}

impl Read for Headers {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let available = self.fill_buf()?;
        let len = available.len().min(buf.len());
        buf[..len].copy_from_slice(&available[..len]);
        self.consume(len);
        Ok(len)
    }
}

impl BufRead for Headers {
    fn fill_buf(&mut self) -> io::Result<&[u8]> {
        if self.lines.is_none() {
            let mut exchange = lock(&self.exchange);
            exchange.send()?;
            let mut lines = Vec::new();
            if let Some(Ok(response)) = &exchange.response {
                for (name, value) in response.headers() {
                    lines.extend_from_slice(name.as_str().as_bytes());
                    lines.push(b':');
                    lines.extend_from_slice(value.as_bytes());
                    lines.push(b'\n');
                }
            }
            self.lines = Some(io::Cursor::new(lines));
        }
        self.lines.as_mut().expect("set above").fill_buf()
    }

    fn consume(&mut self, amount: usize) {
        if let Some(lines) = &mut self.lines {
            lines.consume(amount);
        }
    }
}

/// The response body, streamed.
pub(super) struct Body {
    exchange: Shared,
    state: BodyState,
}

enum BodyState {
    Unsent,
    Reading {
        response: Response,
        chunk: Bytes,
        context: Arc<Context>,
    },
    Done,
}

impl Body {
    fn new(exchange: Shared) -> Self {
        Self {
            exchange,
            state: BodyState::Unsent,
        }
    }
}

impl Read for Body {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let available = self.fill_buf()?;
        let len = available.len().min(buf.len());
        buf[..len].copy_from_slice(&available[..len]);
        self.consume(len);
        Ok(len)
    }
}

impl BufRead for Body {
    fn fill_buf(&mut self) -> io::Result<&[u8]> {
        if let BodyState::Unsent = self.state {
            let mut exchange = lock(&self.exchange);
            exchange.send()?;
            self.state = match exchange.response.take() {
                Some(Ok(response)) => BodyState::Reading {
                    response,
                    chunk: Bytes::new(),
                    context: exchange.context.clone(),
                },
                _ => BodyState::Done,
            };
        }
        if let BodyState::Reading {
            response,
            chunk,
            context,
        } = &mut self.state
        {
            while chunk.is_empty() {
                match context.chunk(response)? {
                    Some(next) => *chunk = next,
                    None => break,
                }
            }
            if chunk.is_empty() {
                self.state = BodyState::Done;
            }
        }
        match &self.state {
            BodyState::Reading { chunk, .. } => Ok(chunk),
            _ => Ok(&[]),
        }
    }

    fn consume(&mut self, amount: usize) {
        if let BodyState::Reading { chunk, .. } = &mut self.state {
            let _ = chunk.split_to(amount.min(chunk.len()));
        }
    }
}

/// Connects to `url` over smart HTTP with `protocol`, which the server may downgrade. Pushes
/// only support version 1.
pub(super) fn connect(
    http: GitHttp,
    url: gix::Url,
    protocol: gix::protocol::transport::Protocol,
) -> http::Transport<GitHttp> {
    http::Transport::new_http(http, url, protocol, false)
}
