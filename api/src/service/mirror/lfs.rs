//! Downloads and uploads Git LFS objects via the batch API, see
//! https://github.com/git-lfs/git-lfs/blob/main/docs/api/batch.md
//!
//! Implemented here instead of running `git lfs`, so every connection, including the ones to
//! transfer URLs chosen by the LFS server, only reaches public addresses like git does
//! (unless the repository has [`RemoteAccess::Unrestricted`]).

use super::git::{self, TreeBlob};
use crate::config::error::AppError;
use crate::dto::error::ErrorCode;
use crate::model::remote_access::RemoteAccess;
use crate::util::http::client_builder;
use crate::util::ip::{NotPublic, PublicResolver, has_public_host, is_not_public};
use futures_util::{StreamExt, TryStreamExt, stream};
use reqwest::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderName, HeaderValue};
use reqwest::redirect::{Attempt, Policy};
use reqwest::{Method, RequestBuilder, Response, StatusCode};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::borrow::Cow;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use url::Url;
use uuid::Uuid;

/// Pointer files are small, larger blobs are never pointers.
pub(super) const MAX_POINTER_SIZE: u64 = 1024;
/// Larger objects are skipped.
pub(super) const MAX_OBJECT_SIZE: u64 = 100 * 1024 * 1024;

/// Objects per batch request, like git-lfs.
const BATCH_SIZE: usize = 100;
const MAX_BATCH_RESPONSE_SIZE: usize = 4 * 1024 * 1024;
const CONCURRENT_DOWNLOADS: usize = 4;
const MAX_REDIRECTS: usize = 5;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const READ_TIMEOUT: Duration = Duration::from_secs(60);
const BATCH_TIMEOUT: Duration = Duration::from_secs(60);
const TRANSFER_TIMEOUT: Duration = Duration::from_mins(10);

const MEDIA_TYPE: &str = "application/vnd.git-lfs+json";
const POINTER_VERSION: &str = "version https://git-lfs.github.com/spec/v1";

/// Holds connection pools, so share one instance.
pub(super) struct LfsClient {
    public: Clients,
    unrestricted: Clients,
}

struct Clients {
    /// For the batch API of the remote.
    api: reqwest::Client,
    /// For the download and upload URLs returned by the batch API.
    transfer: reqwest::Client,
}

impl Clients {
    fn new(access: RemoteAccess) -> Result<Self, reqwest::Error> {
        let builder = || {
            let builder = client_builder()
                // Like git, which runs without the proxy environment variables.
                .no_proxy()
                .connect_timeout(CONNECT_TIMEOUT)
                .read_timeout(READ_TIMEOUT)
                .user_agent(concat!("repolupe/", env!("CARGO_PKG_VERSION")));
            match access {
                RemoteAccess::Public => builder.https_only(true).dns_resolver(PublicResolver),
                RemoteAccess::Unrestricted => builder,
            }
        };
        // Object storage often redirects to signed URLs. reqwest drops the
        // `Authorization` header when a redirect leaves the host.
        let redirect = match access {
            RemoteAccess::Public => Policy::custom(check_redirect),
            RemoteAccess::Unrestricted => Policy::limited(MAX_REDIRECTS),
        };
        Ok(Self {
            // Like git, which runs with `http.followRedirects=false`.
            api: builder().redirect(Policy::none()).build()?,
            transfer: builder().redirect(redirect).build()?,
        })
    }
}

impl LfsClient {
    pub(super) fn new() -> Result<Self, reqwest::Error> {
        Ok(Self {
            public: Clients::new(RemoteAccess::Public)?,
            unrestricted: Clients::new(RemoteAccess::Unrestricted)?,
        })
    }

    fn clients(&self, access: RemoteAccess) -> &Clients {
        match access {
            RemoteAccess::Public => &self.public,
            RemoteAccess::Unrestricted => &self.unrestricted,
        }
    }

    /// Downloads the LFS objects among `blobs`, the blobs of a commit, that `download` accepts
    /// by the path of the file and the size of the object, and that are not stored yet. The
    /// other files stay pointers. They are stored like git-lfs does, see [`object_path`].
    #[allow(clippy::too_many_arguments)]
    pub(super) async fn fetch_objects(
        &self,
        git_dir: &Path,
        remote: &Url,
        branch: &str,
        blobs: &[TreeBlob],
        download: fn(&str, u64) -> bool,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        let pointers = find_pointers(git_dir, blobs).await?;
        let mut seen = HashSet::new();
        let mut missing = Vec::new();
        for blob in blobs {
            let Some(pointer) = pointers.get(&blob.oid) else {
                continue;
            };
            if !download(&blob.path, pointer.size) || !seen.insert(&pointer.oid) {
                continue;
            }
            if pointer.size > MAX_OBJECT_SIZE {
                tracing::warn!(
                    "Skipped Git LFS object {} of {} bytes, the limit is {MAX_OBJECT_SIZE}",
                    pointer.oid,
                    pointer.size
                );
                continue;
            }
            let stored = tokio::fs::try_exists(object_path(git_dir, &pointer.oid))
                .await
                .unwrap_or(false);
            if !stored {
                missing.push(pointer.clone());
            }
        }
        if missing.is_empty() {
            return Ok(());
        }

        // Leftovers of interrupted downloads. No other sync of this repository is running.
        let tmp_dir = git_dir.join("lfs").join("tmp");
        let _ = tokio::fs::remove_dir_all(&tmp_dir).await;
        tokio::fs::create_dir_all(&tmp_dir)
            .await
            .map_err(|e| io_error("create", &tmp_dir, e))?;

        let endpoint = batch_url(remote);
        for pointers in missing.chunks(BATCH_SIZE) {
            let downloads = self
                .request_downloads(&endpoint, branch, pointers, token, access)
                .await?;
            stream::iter(downloads)
                .map(Ok)
                .try_for_each_concurrent(CONCURRENT_DOWNLOADS, |download| {
                    self.download(git_dir, &tmp_dir, &endpoint, download, token, access)
                })
                .await?;
        }
        Ok(())
    }

    /// Uploads the objects of `pointers`, stored in the mirror, that the remote does not have
    /// yet, like git-lfs does before `branch` is pushed.
    #[allow(clippy::too_many_arguments)]
    pub(super) async fn upload_objects(
        &self,
        git_dir: &Path,
        remote: &Url,
        branch: &str,
        pointers: &[Pointer],
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        let endpoint = batch_url(remote);
        for pointers in pointers.chunks(BATCH_SIZE) {
            let objects = self
                .batch(&endpoint, "upload", branch, pointers, token, access)
                .await?;
            stream::iter(objects)
                .map(Ok)
                .try_for_each_concurrent(CONCURRENT_DOWNLOADS, |(pointer, object)| {
                    self.upload(git_dir, &endpoint, pointer, object, token, access)
                })
                .await?;
        }
        Ok(())
    }

    /// Asks the batch API where to download `pointers` from. Objects the server
    /// reports an error for are skipped.
    async fn request_downloads(
        &self,
        endpoint: &Url,
        branch: &str,
        pointers: &[Pointer],
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<Vec<Download>, AppError> {
        let mut downloads = Vec::new();
        for (pointer, object) in self
            .batch(endpoint, "download", branch, pointers, token, access)
            .await?
        {
            if let Some(error) = object.error {
                tracing::warn!(
                    "Skipped Git LFS object {}, the server reported {}: {}",
                    pointer.oid,
                    error.code,
                    error.message
                );
                continue;
            }
            let Some(action) = object.actions.and_then(|a| a.download) else {
                tracing::warn!(
                    "Skipped Git LFS object {}, the server returned no download",
                    pointer.oid
                );
                continue;
            };
            downloads.push(Download { pointer, action });
        }
        Ok(downloads)
    }

    /// Requests `operation` (`download` or `upload`) of `pointers` from the batch API, and
    /// returns what it responded for each of them.
    async fn batch(
        &self,
        endpoint: &Url,
        operation: &str,
        branch: &str,
        pointers: &[Pointer],
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<Vec<(Pointer, BatchObject)>, AppError> {
        check_url(endpoint, access)?;
        let body = serde_json::json!({
            "operation": operation,
            "transfers": ["basic"],
            "ref": { "name": format!("refs/heads/{branch}") },
            "objects": pointers
                .iter()
                .map(|p| serde_json::json!({ "oid": p.oid, "size": p.size }))
                .collect::<Vec<_>>(),
            "hash_algo": "sha256",
        });
        let mut request = self
            .clients(access)
            .api
            .post(endpoint.clone())
            .header(ACCEPT, MEDIA_TYPE)
            .header(CONTENT_TYPE, MEDIA_TYPE)
            .timeout(BATCH_TIMEOUT)
            .body(body.to_string());
        if let Some(token) = token {
            request = request.basic_auth(git::TOKEN_USERNAME, Some(token));
        }

        let response = request
            .send()
            .await
            .map_err(|e| request_failed(e, "batch request"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(batch_failed(status));
        }
        let body = read_limited(response, MAX_BATCH_RESPONSE_SIZE).await?;
        let batch: BatchResponse = serde_json::from_slice(&body).map_err(|e| {
            tracing::warn!("Git LFS batch response is invalid: {e}");
            invalid_response()
        })?;

        let requested: HashMap<&str, &Pointer> =
            pointers.iter().map(|p| (p.oid.as_str(), p)).collect();
        Ok(batch
            .objects
            .into_iter()
            .filter_map(|object| {
                let pointer = (*requested.get(object.oid.as_str())?).clone();
                Some((pointer, object))
            })
            .collect())
    }

    /// Uploads one object as the batch API responded to `upload` for it, nothing if the remote
    /// has it already.
    async fn upload(
        &self,
        git_dir: &Path,
        endpoint: &Url,
        pointer: Pointer,
        object: BatchObject,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        if let Some(error) = object.error {
            return Err(remote_unreachable(&format!(
                "The Git LFS server refused to store object {} ({}: {})",
                pointer.oid, error.code, error.message
            )));
        }
        let Some(Actions {
            upload: Some(upload),
            verify,
            ..
        }) = object.actions
        else {
            return Ok(());
        };
        let content = read_object(git_dir, &pointer.oid).await?.ok_or_else(|| {
            AppError::InternalServerError(format!("Git LFS object {} is missing", pointer.oid))
        })?;

        let octet_stream = [(CONTENT_TYPE, "application/octet-stream")];
        let response = self
            .action_request(Method::PUT, &upload, &octet_stream, endpoint, token, access)?
            .body(content)
            .send()
            .await
            .map_err(|e| request_failed(e, "upload"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(remote_unreachable(&format!(
                "Failed to upload a Git LFS object, the server responded with {status}"
            )));
        }

        let Some(verify) = verify else {
            return Ok(());
        };
        let json = [(ACCEPT, MEDIA_TYPE), (CONTENT_TYPE, MEDIA_TYPE)];
        let body = serde_json::json!({ "oid": pointer.oid, "size": pointer.size });
        let response = self
            .action_request(Method::POST, &verify, &json, endpoint, token, access)?
            .body(body.to_string())
            .send()
            .await
            .map_err(|e| request_failed(e, "verification"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(remote_unreachable(&format!(
                "The Git LFS server did not verify an uploaded object, it responded with {status}"
            )));
        }
        Ok(())
    }

    /// A request to the URL of `action`, which the batch API returned, with its headers, which
    /// override `defaults`.
    fn action_request(
        &self,
        method: Method,
        action: &Action,
        defaults: &[(HeaderName, &'static str)],
        endpoint: &Url,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<RequestBuilder, AppError> {
        let href = Url::parse(&action.href).map_err(|_| invalid_response())?;
        check_url(&href, access)?;
        let mut headers = HeaderMap::new();
        for (name, value) in defaults {
            headers.insert(name, HeaderValue::from_static(value));
        }
        for (name, value) in &action.header {
            let name = HeaderName::from_bytes(name.as_bytes()).map_err(|_| invalid_response())?;
            let value = HeaderValue::from_str(value).map_err(|_| invalid_response())?;
            headers.insert(name, value);
        }
        let authorized = headers.contains_key(AUTHORIZATION);
        let mut request = self
            .clients(access)
            .transfer
            .request(method, href.clone())
            .headers(headers)
            .timeout(TRANSFER_TIMEOUT);
        // Like git-lfs, the token is only sent to the host of the remote.
        if let Some(token) = token
            && !authorized
            && same_origin(&href, endpoint)
        {
            request = request.basic_auth(git::TOKEN_USERNAME, Some(token));
        }
        Ok(request)
    }

    /// Downloads one object and moves it into place once its size and hash are verified.
    async fn download(
        &self,
        git_dir: &Path,
        tmp_dir: &Path,
        endpoint: &Url,
        download: Download,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        let Download { pointer, action } = download;
        let response = self
            .action_request(Method::GET, &action, &[], endpoint, token, access)?
            .send()
            .await
            .map_err(|e| request_failed(e, "download"))?;
        let status = response.status();
        if !status.is_success() {
            return Err(remote_unreachable(&format!(
                "Failed to download a Git LFS object, the server responded with {status}"
            )));
        }

        let tmp_path = tmp_dir.join(Uuid::now_v7().to_string());
        if let Err(e) = write_object(response, &tmp_path, &pointer).await {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(e);
        }
        let path = object_path(git_dir, &pointer.oid);
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|e| io_error("create", parent, e))?;
        }
        tokio::fs::rename(&tmp_path, &path)
            .await
            .map_err(|e| io_error("move into place", &path, e))?;
        Ok(())
    }
}

/// The content of the file whose blob in the repository at `git_dir` is `blob`: the blob
/// itself, or the LFS object if it is a pointer, `None` if that was not downloaded. Blocking,
/// for [`git::grep`].
pub(super) fn resolve_pointer<'a>(git_dir: &Path, blob: &'a [u8]) -> Option<Cow<'a, [u8]>> {
    let Some(pointer) = parse_pointer(blob) else {
        return Some(Cow::Borrowed(blob));
    };
    let path = object_path(git_dir, &pointer.oid);
    match std::fs::read(&path) {
        Ok(content) => Some(Cow::Owned(content)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(e) => {
            tracing::warn!("Skipped {} in grep: {}", path.display(), e);
            None
        }
    }
}

/// The content of the LFS object `oid`, `None` if it was not downloaded.
pub(super) async fn read_object(git_dir: &Path, oid: &str) -> Result<Option<Vec<u8>>, AppError> {
    let path = object_path(git_dir, oid);
    match tokio::fs::read(&path).await {
        Ok(content) => Ok(Some(content)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(io_error("read", &path, e)),
    }
}

/// Stores `content` as an LFS object, like git-lfs does when a file is added, and returns its
/// pointer.
pub(super) async fn store_object(git_dir: &Path, content: Vec<u8>) -> Result<Pointer, AppError> {
    let git_dir = git_dir.to_path_buf();
    // Hashed and written on a blocking thread, since it may be large.
    tokio::task::spawn_blocking(move || {
        let pointer = Pointer::of(&content);
        let path = object_path(&git_dir, &pointer.oid);
        if path.exists() {
            return Ok(pointer);
        }
        let dir = path.parent().unwrap_or(&git_dir);
        std::fs::create_dir_all(dir).map_err(|e| io_error("create", dir, e))?;
        // Next to the object instead of in `lfs/tmp`, which a sync may clear meanwhile.
        let tmp_path = dir.join(format!("{}.tmp", Uuid::now_v7()));
        std::fs::write(&tmp_path, &content)
            .and_then(|()| std::fs::rename(&tmp_path, &path))
            .map_err(|e| {
                let _ = std::fs::remove_file(&tmp_path);
                io_error("store", &path, e)
            })?;
        Ok(pointer)
    })
    .await
    .map_err(|e| AppError::InternalServerError(format!("Storing a Git LFS object failed: {e}")))?
}

/// Whether `pointer` points to `content`.
pub(super) async fn points_to(pointer: &Pointer, content: &[u8]) -> Result<bool, AppError> {
    if pointer.size != content.len() as u64 {
        return Ok(false);
    }
    // Copied, to be hashed on a blocking thread, since it may be large.
    let content = content.to_vec();
    let oid = tokio::task::spawn_blocking(move || Pointer::of(&content).oid)
        .await
        .map_err(|e| AppError::InternalServerError(format!("Hashing failed: {e}")))?;
    Ok(oid == pointer.oid)
}

/// Where the content of the LFS object `oid` is stored, the same path git-lfs uses.
/// `oid` must be a valid sha256 hex string, see [`parse_pointer`].
fn object_path(git_dir: &Path, oid: &str) -> PathBuf {
    git_dir
        .join("lfs")
        .join("objects")
        .join(&oid[0..2])
        .join(&oid[2..4])
        .join(oid)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Pointer {
    /// sha256 of the content, as lowercase hex.
    pub(super) oid: String,
    pub(super) size: u64,
}

impl Pointer {
    /// The pointer to `content`.
    pub(super) fn of(content: &[u8]) -> Self {
        Self {
            oid: hex::encode(Sha256::digest(content)),
            size: content.len() as u64,
        }
    }

    /// The pointer file, as git-lfs writes it.
    pub(super) fn to_file(&self) -> Vec<u8> {
        format!(
            "{POINTER_VERSION}\noid sha256:{}\nsize {}\n",
            self.oid, self.size
        )
        .into_bytes()
    }
}

struct Download {
    pointer: Pointer,
    action: Action,
}

#[derive(Deserialize)]
struct BatchResponse {
    objects: Vec<BatchObject>,
}

#[derive(Deserialize)]
struct BatchObject {
    oid: String,
    actions: Option<Actions>,
    error: Option<ObjectError>,
}

#[derive(Deserialize)]
struct Actions {
    download: Option<Action>,
    /// Missing if the remote has the object already.
    upload: Option<Action>,
    verify: Option<Action>,
}

#[derive(Deserialize)]
struct Action {
    href: String,
    #[serde(default)]
    header: HashMap<String, String>,
}

#[derive(Deserialize)]
struct ObjectError {
    code: i64,
    message: String,
}

/// The bytes of the LFS objects among `blobs`, the blobs of a commit, whether they were
/// downloaded or not. Each object is counted once.
pub(super) async fn total_size(git_dir: &Path, blobs: &[TreeBlob]) -> Result<u64, AppError> {
    let mut seen = HashSet::new();
    Ok(find_pointers(git_dir, blobs)
        .await?
        .into_values()
        .filter(|pointer| seen.insert(pointer.oid.clone()))
        .map(|pointer| pointer.size)
        .sum())
}

/// The LFS pointers among `blobs`, by the oid of the pointer's blob.
async fn find_pointers(
    git_dir: &Path,
    blobs: &[TreeBlob],
) -> Result<HashMap<String, Pointer>, AppError> {
    let candidates: HashSet<&str> = blobs
        .iter()
        .filter(|blob| blob.size <= MAX_POINTER_SIZE)
        .map(|blob| blob.oid.as_str())
        .collect();
    if candidates.is_empty() {
        return Ok(HashMap::new());
    }

    let candidates: Vec<String> = candidates.into_iter().map(str::to_string).collect();
    Ok(git::read_blobs(git_dir, &candidates)
        .await?
        .into_iter()
        .filter_map(|(oid, content)| Some((oid, parse_pointer(&content)?)))
        .collect())
}

/// Parses a pointer file, see https://github.com/git-lfs/git-lfs/blob/main/docs/spec.md
pub(super) fn parse_pointer(content: &[u8]) -> Option<Pointer> {
    if content.len() as u64 > MAX_POINTER_SIZE {
        return None;
    }
    let text = std::str::from_utf8(content).ok()?;
    let mut lines = text.lines();
    if lines.next()? != POINTER_VERSION {
        return None;
    }
    let mut oid = None;
    let mut size = None;
    for line in lines {
        match line.split_once(' ')? {
            ("oid", value) => oid = Some(value.strip_prefix("sha256:")?),
            ("size", value) => size = Some(value.parse().ok()?),
            _ => {}
        }
    }
    // Checked strictly, since the oid becomes part of a path.
    let oid = oid?;
    if oid.len() != 64 || !oid.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return None;
    }
    Some(Pointer {
        oid: oid.to_string(),
        size: size?,
    })
}

/// The batch API of `remote`, at the default location git-lfs derives from the remote URL.
fn batch_url(remote: &Url) -> Url {
    let path = remote.path().trim_end_matches('/');
    let repository = if path.ends_with(".git") {
        path.to_string()
    } else {
        format!("{path}.git")
    };
    let mut url = remote.clone();
    url.set_path(&format!("{repository}/info/lfs/objects/batch"));
    url
}

fn same_origin(a: &Url, b: &Url) -> bool {
    a.scheme() == b.scheme()
        && a.host_str() == b.host_str()
        && a.port_or_known_default() == b.port_or_known_default()
}

/// Checks what [`PublicResolver`] cannot: IP addresses in the URL are never resolved.
fn check_url(url: &Url, access: RemoteAccess) -> Result<(), AppError> {
    match access {
        RemoteAccess::Public => {
            if url.scheme() != "https" {
                return Err(AppError::BadRequest(
                    "Git LFS URLs must use https://".to_string(),
                ));
            }
            if !has_public_host(url) {
                return Err(not_public());
            }
        }
        RemoteAccess::Unrestricted => {
            if !matches!(url.scheme(), "https" | "http") {
                return Err(AppError::BadRequest(
                    "Git LFS URLs must use https:// or http://".to_string(),
                ));
            }
        }
    }
    Ok(())
}

fn check_redirect(attempt: Attempt) -> reqwest::redirect::Action {
    if attempt.previous().len() >= MAX_REDIRECTS {
        attempt.error("too many redirects")
    } else if !has_public_host(attempt.url()) {
        attempt.error(NotPublic)
    } else {
        attempt.follow()
    }
}

async fn write_object(
    mut response: Response,
    path: &Path,
    pointer: &Pointer,
) -> Result<(), AppError> {
    let mut file = tokio::fs::File::create(path)
        .await
        .map_err(|e| io_error("create", path, e))?;
    let mut hasher = Sha256::new();
    let mut written: u64 = 0;
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|e| request_failed(e, "download"))?
    {
        written += chunk.len() as u64;
        if written > pointer.size {
            return Err(object_mismatch(pointer));
        }
        hasher.update(&chunk);
        file.write_all(&chunk)
            .await
            .map_err(|e| io_error("write", path, e))?;
    }
    if written != pointer.size || hex::encode(hasher.finalize()) != pointer.oid {
        return Err(object_mismatch(pointer));
    }
    file.flush().await.map_err(|e| io_error("write", path, e))?;
    Ok(())
}

async fn read_limited(mut response: Response, limit: usize) -> Result<Vec<u8>, AppError> {
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|e| request_failed(e, "batch request"))?
    {
        if body.len() + chunk.len() > limit {
            return Err(invalid_response());
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

fn request_failed(error: reqwest::Error, name: &str) -> AppError {
    if is_not_public(&error) {
        return not_public();
    }
    if error.is_timeout() {
        return remote_unreachable(&format!("Git LFS {name} timed out"));
    }
    // Without the URL, since download URLs may be signed.
    tracing::warn!("Git LFS {name} failed: {}", error.without_url());
    remote_unreachable("The Git LFS server could not be reached")
}

fn batch_failed(status: StatusCode) -> AppError {
    match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The remote rejected the credentials for Git LFS or requires a token".to_string(),
        ),
        StatusCode::NOT_FOUND => remote_unreachable("The remote does not serve Git LFS objects"),
        status if status.is_redirection() => {
            remote_unreachable("The remote redirected the Git LFS request, which is not supported")
        }
        status => remote_unreachable(&format!(
            "Git LFS batch request failed, the server responded with {status}"
        )),
    }
}

fn object_mismatch(pointer: &Pointer) -> AppError {
    remote_unreachable(&format!(
        "The Git LFS server sent wrong content for object {}",
        pointer.oid
    ))
}

fn invalid_response() -> AppError {
    remote_unreachable("The Git LFS server sent an invalid response")
}

fn not_public() -> AppError {
    AppError::BadRequest("Git LFS URLs must not point to a private or reserved address".to_string())
}

fn remote_unreachable(message: &str) -> AppError {
    AppError::BadGateway(ErrorCode::RemoteUnreachable, message.to_string())
}

fn io_error(action: &str, path: &Path, error: std::io::Error) -> AppError {
    AppError::InternalServerError(format!("Failed to {action} {}: {error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const OID: &str = "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393";

    #[test]
    fn parses_pointer() {
        let content = format!("{POINTER_VERSION}\noid sha256:{OID}\nsize 12345\n");
        assert_eq!(
            parse_pointer(content.as_bytes()),
            Some(Pointer {
                oid: OID.to_string(),
                size: 12345
            })
        );
    }

    #[test]
    fn writes_pointers() {
        let pointer = Pointer::of(b"hello\n");
        assert_eq!(
            String::from_utf8(pointer.to_file()).unwrap(),
            "version https://git-lfs.github.com/spec/v1\n\
            oid sha256:5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03\n\
            size 6\n"
        );
        assert_eq!(parse_pointer(&pointer.to_file()), Some(pointer));
    }

    #[test]
    fn rejects_invalid_pointers() {
        for content in [
            "%PDF-1.7".to_string(),
            format!("oid sha256:{OID}\nsize 1\n"),
            format!("{POINTER_VERSION}\nsize 1\n"),
            format!("{POINTER_VERSION}\noid sha256:{OID}\n"),
            format!("{POINTER_VERSION}\noid md5:{OID}\nsize 1\n"),
            format!(
                "{POINTER_VERSION}\noid sha256:../../{}\nsize 1\n",
                &OID[6..]
            ),
            format!(
                "{POINTER_VERSION}\noid sha256:{}\nsize 1\n",
                OID.to_uppercase()
            ),
            format!("{POINTER_VERSION}\noid sha256:{OID}\nsize -1\n"),
        ] {
            assert_eq!(parse_pointer(content.as_bytes()), None, "{content}");
        }
    }

    #[test]
    fn derives_batch_url() {
        for remote in [
            "https://github.com/owner/repo",
            "https://github.com/owner/repo/",
            "https://github.com/owner/repo.git",
        ] {
            assert_eq!(
                batch_url(&Url::parse(remote).unwrap()).as_str(),
                "https://github.com/owner/repo.git/info/lfs/objects/batch"
            );
        }
    }

    #[test]
    fn stores_objects_like_git_lfs() {
        assert_eq!(
            object_path(Path::new("/repos/x"), OID),
            Path::new("/repos/x/lfs/objects/4d/7a").join(OID)
        );
    }
}
