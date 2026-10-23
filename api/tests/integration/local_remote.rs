//! A git remote served by `git http-backend`, with a Git LFS server, for the tests that fetch
//! and push.

use super::support::{TestClient, create_bare_repository, git};
use axum::Router;
use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, Method, StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{post, put};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tempfile::TempDir;
use tokio::io::AsyncWriteExt;
use tokio::task::JoinHandle;

/// A git remote on localhost over http, a private address only admins may use. Serves a bare
/// repository with git's smart HTTP protocol via `git http-backend`, which refuses pushes until
/// [`LocalRemote::allow_push`], and the Git LFS batch API with the basic transfer, whose
/// objects are kept in memory. Stops when dropped.
pub struct LocalRemote {
    pub url: String,
    pub repository: PathBuf,
    state: Arc<RemoteState>,
    server: JoinHandle<()>,
    dir: TempDir,
}

struct RemoteState {
    root: PathBuf,
    /// Required as the password of basic auth, if set.
    token: Option<String>,
    requests: AtomicUsize,
    push_allowed: AtomicBool,
    /// Where the server is, for the URLs of the LFS objects.
    origin: String,
    /// By sha256.
    lfs_objects: Mutex<HashMap<String, Vec<u8>>>,
}

impl LocalRemote {
    pub async fn start() -> Self {
        Self::start_with_token(None).await
    }

    pub async fn start_with_token(token: Option<&str>) -> Self {
        let dir = TempDir::new().unwrap();
        let repository = dir.path().join("repo.git");
        create_bare_repository(&repository, &[("README.md", "# Internal")]);

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let origin = format!("http://{}", listener.local_addr().unwrap());
        let url = format!("{origin}/repo.git");
        let state = Arc::new(RemoteState {
            root: dir.path().to_path_buf(),
            token: token.map(str::to_string),
            requests: AtomicUsize::new(0),
            push_allowed: AtomicBool::new(false),
            origin,
            lfs_objects: Mutex::default(),
        });
        let router = Router::new()
            .route("/repo.git/info/lfs/objects/batch", post(lfs_batch))
            .route("/lfs/objects/{oid}", put(lfs_upload).get(lfs_download))
            .route("/lfs/verify", post(lfs_verify))
            .fallback(serve_git)
            .with_state(state.clone());
        let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        Self {
            url,
            repository,
            state,
            server,
            dir,
        }
    }

    /// The commit the branch points at.
    pub fn head(&self) -> String {
        git(&self.repository, &["rev-parse", "main"])
            .trim()
            .to_string()
    }

    pub fn requests(&self) -> usize {
        self.state.requests.load(Ordering::SeqCst)
    }

    /// Lets clients push, like `http.receivepack` does.
    pub fn allow_push(&self, allowed: bool) {
        self.state.push_allowed.store(allowed, Ordering::SeqCst);
    }

    /// The content of `path` on the branch.
    pub fn read(&self, path: &str) -> String {
        git(&self.repository, &["show", &format!("main:{path}")])
    }

    /// The LFS object with sha256 `oid`, if it was uploaded.
    pub fn lfs_object(&self, oid: &str) -> Option<Vec<u8>> {
        self.state.lfs_objects.lock().unwrap().get(oid).cloned()
    }

    /// Stores `content` on the LFS server and returns its pointer file, for [`Self::push_commit`].
    pub fn add_lfs_object(&self, content: &[u8]) -> String {
        let oid = hex::encode(Sha256::digest(content));
        let pointer = format!(
            "version https://git-lfs.github.com/spec/v1\noid sha256:{oid}\nsize {}\n",
            content.len()
        );
        self.state
            .lfs_objects
            .lock()
            .unwrap()
            .insert(oid, content.to_vec());
        pointer
    }

    /// Commits `files` on top of the branch and returns the commit.
    pub fn push_commit(&self, files: &[(&str, &str)]) -> String {
        let work = TempDir::new().unwrap();
        git(
            work.path(),
            &["clone", "--quiet", self.repository.to_str().unwrap(), "."],
        );
        for (path, content) in files {
            let path = work.path().join(path);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, content).unwrap();
        }
        git(work.path(), &["add", "--all"]);
        git(work.path(), &["commit", "--quiet", "--message", "update"]);
        git(work.path(), &["push", "--quiet", "origin", "main"]);
        git(work.path(), &["rev-parse", "HEAD"]).trim().to_string()
    }

    /// Replaces the branch with a commit of `files` that shares no history with it.
    pub fn replace_branch(&self, files: &[(&str, &str)]) -> String {
        let replacement = self.dir.path().join("replacement.git");
        let commit = create_bare_repository(&replacement, files);
        git(
            &self.repository,
            &[
                "fetch",
                "--quiet",
                replacement.to_str().unwrap(),
                "+main:main",
            ],
        );
        commit
    }
}

impl Drop for LocalRemote {
    fn drop(&mut self) {
        self.server.abort();
    }
}

/// Counts the request, and checks the token if one is required.
fn authorized(state: &RemoteState, headers: &HeaderMap) -> bool {
    state.requests.fetch_add(1, Ordering::SeqCst);
    let Some(token) = &state.token else {
        return true;
    };
    let expected = format!("Basic {}", BASE64.encode(format!("x-access-token:{token}")));
    headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        == Some(&expected)
}

fn unauthorized() -> Response {
    (
        StatusCode::UNAUTHORIZED,
        [(header::WWW_AUTHENTICATE, "Basic realm=\"git\"")],
    )
        .into_response()
}

/// The batch API: uploads need push access, like they do on forges.
async fn lfs_batch(
    State(state): State<Arc<RemoteState>>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let request: Value = serde_json::from_slice(&body).unwrap();
    let upload = match request["operation"].as_str().unwrap() {
        "upload" => true,
        "download" => false,
        operation => panic!("unknown LFS operation {operation}"),
    };
    if upload && !state.push_allowed.load(Ordering::SeqCst) {
        return StatusCode::FORBIDDEN.into_response();
    }
    let stored = state.lfs_objects.lock().unwrap();
    let objects: Vec<Value> = request["objects"]
        .as_array()
        .unwrap()
        .iter()
        .map(|object| {
            let oid = object["oid"].as_str().unwrap();
            let href = format!("{}/lfs/objects/{oid}", state.origin);
            let actions = match (upload, stored.contains_key(oid)) {
                (true, true) => None,
                (true, false) => Some(json!({
                    "upload": {"href": href},
                    "verify": {"href": format!("{}/lfs/verify", state.origin)},
                })),
                (false, true) => Some(json!({"download": {"href": href}})),
                (false, false) => {
                    return json!({
                        "oid": oid,
                        "size": object["size"],
                        "error": {"code": 404, "message": "Object does not exist"},
                    });
                }
            };
            json!({"oid": oid, "size": object["size"], "actions": actions})
        })
        .collect();
    (
        [(header::CONTENT_TYPE, "application/vnd.git-lfs+json")],
        json!({"transfer": "basic", "objects": objects}).to_string(),
    )
        .into_response()
}

async fn lfs_upload(
    State(state): State<Arc<RemoteState>>,
    Path(oid): Path<String>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    if hex::encode(Sha256::digest(&body)) != oid {
        return StatusCode::BAD_REQUEST.into_response();
    }
    state.lfs_objects.lock().unwrap().insert(oid, body.to_vec());
    StatusCode::OK.into_response()
}

async fn lfs_download(
    State(state): State<Arc<RemoteState>>,
    Path(oid): Path<String>,
    headers: HeaderMap,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    match state.lfs_objects.lock().unwrap().get(&oid) {
        Some(content) => content.clone().into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn lfs_verify(
    State(state): State<Arc<RemoteState>>,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let object: Value = serde_json::from_slice(&body).unwrap();
    let stored = state.lfs_objects.lock().unwrap();
    match stored.get(object["oid"].as_str().unwrap()) {
        Some(content) if object["size"] == content.len() => StatusCode::OK,
        _ => StatusCode::NOT_FOUND,
    }
    .into_response()
}

/// Runs `git http-backend` as a CGI script.
async fn serve_git(
    State(state): State<Arc<RemoteState>>,
    method: Method,
    uri: Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    if !authorized(&state, &headers) {
        return unauthorized();
    }
    let header = |name: header::HeaderName| {
        headers
            .get(name)
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .to_string()
    };
    let mut child = tokio::process::Command::new("git")
        .arg("http-backend")
        .env("GIT_PROJECT_ROOT", &state.root)
        .env("GIT_HTTP_EXPORT_ALL", "1")
        .env("PATH_INFO", uri.path())
        .env("QUERY_STRING", uri.query().unwrap_or_default())
        .env("REQUEST_METHOD", method.as_str())
        .env("CONTENT_TYPE", header(header::CONTENT_TYPE))
        .env("CONTENT_LENGTH", body.len().to_string())
        .env(
            "GIT_PROTOCOL",
            header(header::HeaderName::from_static("git-protocol")),
        )
        .env("REMOTE_ADDR", "127.0.0.1")
        .env("GIT_CONFIG_COUNT", "1")
        .env("GIT_CONFIG_KEY_0", "http.receivepack")
        .env(
            "GIT_CONFIG_VALUE_0",
            state.push_allowed.load(Ordering::SeqCst).to_string(),
        )
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        // E.g. that the repository of a test for a missing one does not exist.
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    tokio::spawn(async move { stdin.write_all(&body).await });
    let output = child.wait_with_output().await.unwrap();

    // CGI headers, a blank line, then the body.
    let stdout = output.stdout;
    let end = stdout
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .expect("git http-backend sent headers");
    let mut response = Response::builder();
    for line in std::str::from_utf8(&stdout[..end]).unwrap().split("\r\n") {
        let (name, value) = line.split_once(": ").unwrap();
        if name.eq_ignore_ascii_case("status") {
            response = response.status(value[..3].parse::<u16>().unwrap());
        } else {
            response = response.header(name, value);
        }
    }
    response.body(stdout[end + 4..].to_vec().into()).unwrap()
}

/// Waits until the repository was synced at `commit`.
pub async fn wait_for_commit(client: &TestClient, id: &str, commit: &str) {
    let started = Instant::now();
    loop {
        let (status, body) = client.get(&format!("/api/v1/repositories/{id}")).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert_eq!(body["last_error"], Value::Null, "{body}");
        if body["head_commit_sha"] == commit {
            assert_eq!(body["sync_status"], "READY", "{body}");
            return;
        }
        assert!(
            started.elapsed() < Duration::from_secs(30),
            "repository was not synced at {commit}: {body}"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}
