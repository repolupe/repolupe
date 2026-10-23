//! Listing and fetching branches of remotes over smart HTTP, see [`super::http`].

use super::http::{self, Failure, GitHttp};
use super::push::{self, PushResult};
use super::{blocking, failed, open, pack_file_commit, parse_oid, repack};
use crate::config::error::AppError;
use crate::dto::error::ErrorCode;
use crate::model::remote_access::RemoteAccess;
use crate::util::http::client_builder;
use crate::util::ip::{PublicResolver, is_public_ip};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use gix::bstr::ByteSlice;
use gix::protocol::transport::client::blocking_io::http::Transport;
use gix::protocol::transport::{Protocol, Service};
use gix::refs::Target;
use gix::refs::transaction::{Change, LogChange, PreviousValue, RefEdit};
use reqwest::header::HeaderValue;
use reqwest::redirect::Policy;
use std::net::IpAddr;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::time::Instant;
use tokio_util::sync::CancellationToken;
use url::{Host, Url};

const RESOLVE_TIMEOUT: Duration = Duration::from_secs(5);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
/// Also bounds stalls while fetching, which the timeouts below allow to take long.
const READ_TIMEOUT: Duration = Duration::from_secs(60);
const LS_REMOTE_TIMEOUT: Duration = Duration::from_secs(30);
/// Generous, since the first fetch downloads the whole history.
const FETCH_TIMEOUT: Duration = Duration::from_mins(30);
/// Pushes send one commit, but the remote may run hooks.
const PUSH_TIMEOUT: Duration = Duration::from_mins(2);

/// Username sent with the token. GitHub, GitLab and Gitea ignore it for personal access tokens.
pub(crate) const TOKEN_USERNAME: &str = "x-access-token";

/// Talks to remotes. Holds connection pools, so share one instance.
pub(crate) struct GitClient {
    public: reqwest::Client,
    unrestricted: reqwest::Client,
}

impl GitClient {
    pub(crate) fn new() -> Result<Self, reqwest::Error> {
        let builder = || {
            client_builder()
                // Ignores the proxy environment variables, like the Git LFS client.
                .no_proxy()
                .connect_timeout(CONNECT_TIMEOUT)
                .read_timeout(READ_TIMEOUT)
                // A redirect could point at an internal host that was never checked.
                .redirect(Policy::none())
        };
        Ok(Self {
            public: builder()
                .https_only(true)
                .dns_resolver(PublicResolver)
                .build()?,
            unrestricted: builder().build()?,
        })
    }

    /// Verifies that `url` is reachable with `token` and has `branch`, like `git ls-remote`.
    pub(crate) async fn check_remote(
        &self,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        let connection = self
            .connect(url, token, access, LS_REMOTE_TIMEOUT, Protocol::V2)
            .await?;
        let branch_ref = format!("refs/heads/{branch}");
        let Connection {
            mut transport,
            failure,
            interrupt: _interrupt,
        } = connection;
        blocking(move || {
            let mut progress = gix::progress::Discard;
            let refs = (|| {
                let mut handshake = gix::protocol::handshake(
                    &mut transport,
                    Service::UploadPack,
                    no_credentials,
                    Vec::new(),
                    &mut progress,
                )?;
                // Version 1 lists the refs in the handshake, version 2 on request.
                if let Some(refs) = handshake.refs.take() {
                    return Ok(refs);
                }
                let mut prefixes = gix::protocol::ls_refs::RefPrefixes::new();
                prefixes.extend([branch_ref.clone().into()]);
                gix::protocol::LsRefsCommand::new(Some(prefixes), &handshake.capabilities, agent())
                    .invoke_blocking(&mut transport, &mut progress, false)
            })()
            .map_err(|e| remote_failed("ls-remote", &failure, e))?;
            // The prefix also matches longer names, so check for the exact ref.
            if refs.iter().any(|r| r.unpack().0 == branch_ref.as_bytes()) {
                Ok(())
            } else {
                Err(branch_not_found())
            }
        })
        .await
    }

    /// Fetches `branch` from `url` into the bare repository at `git_dir`, where it is kept as
    /// the branch of the same name and as `HEAD`. Returns the fetched commit.
    pub(crate) async fn fetch_branch(
        &self,
        git_dir: &Path,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<String, AppError> {
        let Connection {
            transport,
            failure,
            interrupt,
        } = self
            .connect(url, token, access, FETCH_TIMEOUT, Protocol::V2)
            .await?;
        let git_dir = git_dir.to_path_buf();
        let url = url.clone();
        let branch_ref = format!("refs/heads/{branch}");
        let should_interrupt = interrupt.flag.clone();
        blocking(move || {
            let repo = open(&git_dir)?;
            // Forced, since the remote branch may have been rewritten.
            let refspec = format!("+{branch_ref}:{branch_ref}");
            let remote = repo
                .remote_at_without_url_rewrite(url.as_str())
                .map_err(|e| failed("fetch", e))?
                .with_fetch_tags(gix::remote::fetch::Tags::None)
                .with_refspecs([refspec.as_str()], gix::remote::Direction::Fetch)
                .map_err(|e| failed("fetch", e))?;
            let prepare = remote
                .to_connection_with_transport(transport)
                .with_credentials(no_credentials)
                .prepare_fetch(gix::progress::Discard, Default::default())
                .map_err(|e| remote_failed("fetch", &failure, e))?;
            let found = prepare
                .ref_map()
                .mappings
                .iter()
                .any(|m| m.remote.as_name() == Some(branch_ref.as_bytes().as_bstr()));
            if !found {
                return Err(branch_not_found());
            }
            prepare
                .receive(gix::progress::Discard, &should_interrupt)
                .map_err(|e| remote_failed("fetch", &failure, e))?;

            repo.edit_reference(RefEdit {
                change: Change::Update {
                    log: LogChange::default(),
                    expected: PreviousValue::Any,
                    new: Target::Symbolic(
                        branch_ref
                            .as_str()
                            .try_into()
                            .map_err(|e| failed("fetch", e))?,
                    ),
                },
                name: "HEAD".try_into().map_err(|e| failed("fetch", e))?,
                deref: false,
            })
            .map_err(|e| failed("symbolic-ref", e))?;
            let commit = repo
                .find_reference(branch_ref.as_str())
                .map_err(|e| failed("rev-parse", e))?
                .peel_to_commit()
                .map_err(|e| failed("rev-parse", e))?
                .id;

            // gitoxide writes a pack per fetch and never repacks on its own.
            repack::consolidate_packs(&git_dir, repack::MAX_PACKS, &should_interrupt)?;
            Ok(commit.to_string())
        })
        .await
    }

    /// Verifies that `url` accepts pushes to `branch` with `token`. Servers check write access
    /// when they list the refs for a push, e.g. GitHub refuses tokens that can only read.
    pub(crate) async fn check_push(
        &self,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
    ) -> Result<(), AppError> {
        let Connection {
            mut transport,
            failure,
            interrupt: _interrupt,
        } = self
            .connect(url, token, access, LS_REMOTE_TIMEOUT, Protocol::V1)
            .await?;
        let branch_ref = format!("refs/heads/{branch}");
        blocking(move || {
            let advertisement = push::advertise(&mut transport, &branch_ref)
                .map_err(|e| push_failed(&failure, e))?;
            match advertisement.head {
                Some(_) => Ok(()),
                None => Err(branch_not_found()),
            }
        })
        .await
    }

    /// Updates `branch` of `url` from `expected` to `commit`, a commit in the repository at
    /// `git_dir` with parent `expected` that only changes the entries at `paths`. Sends only
    /// the objects of that change, and only if the branch is still at `expected`; the remote
    /// checks that again when it updates the branch.
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn push_file_commit(
        &self,
        git_dir: &Path,
        url: &Url,
        branch: &str,
        token: Option<&str>,
        access: RemoteAccess,
        expected: &str,
        commit: &str,
        paths: &[String],
    ) -> Result<PushResult, AppError> {
        let Connection {
            mut transport,
            failure,
            interrupt: _interrupt,
        } = self
            .connect(url, token, access, PUSH_TIMEOUT, Protocol::V1)
            .await?;
        let git_dir = git_dir.to_path_buf();
        let branch_ref = format!("refs/heads/{branch}");
        let expected = parse_oid(expected)?;
        let commit = parse_oid(commit)?;
        let paths = paths.to_vec();
        blocking(move || {
            let advertisement = push::advertise(&mut transport, &branch_ref)
                .map_err(|e| push_failed(&failure, e))?;
            match advertisement.head {
                None => return Err(branch_not_found()),
                Some(head) if head != expected => return Ok(PushResult::Moved),
                Some(_) => {}
            }
            let pack = pack_file_commit(&open(&git_dir)?, commit, &paths)?;
            push::send(
                &mut transport,
                &advertisement,
                &branch_ref,
                expected,
                commit,
                &pack,
            )
            .map_err(|e| push_failed(&failure, e))
        })
        .await
    }

    /// A transport for `url`. With [`RemoteAccess::Public`], restricted to https and to public
    /// addresses. The token is sent as a header, so it never shows up in a URL or error.
    async fn connect(
        &self,
        url: &Url,
        token: Option<&str>,
        access: RemoteAccess,
        timeout: Duration,
        protocol: Protocol,
    ) -> Result<Connection, AppError> {
        let host = url
            .host()
            .ok_or_else(|| AppError::BadRequest("Remote URL must have a host".to_string()))?;
        let client = match access {
            RemoteAccess::Public => {
                // Also checked by the resolver, but this tells the user why it failed.
                let port = url.port_or_known_default().unwrap_or(443);
                resolve_public(&host, port).await?;
                &self.public
            }
            RemoteAccess::Unrestricted => &self.unrestricted,
        };
        let authorization = token
            .map(|token| {
                let credentials = BASE64.encode(format!("{TOKEN_USERNAME}:{token}"));
                let mut value = HeaderValue::try_from(format!("Basic {credentials}"))
                    .map_err(|_| AppError::BadRequest("Invalid token".to_string()))?;
                value.set_sensitive(true);
                Ok::<_, AppError>(value)
            })
            .transpose()?;
        let git_url = gix::url::parse(url.as_str().as_bytes().as_bstr())
            .map_err(|e| AppError::BadRequest(format!("Remote URL is not a valid git URL: {e}")))?;

        let interrupt = Interrupt::default();
        let failure = Arc::new(Mutex::new(None));
        let http = GitHttp::new(
            client.clone(),
            tokio::runtime::Handle::current(),
            Instant::now() + timeout,
            interrupt.cancel.clone(),
            authorization,
            failure.clone(),
        );
        Ok(Connection {
            transport: http::connect(http, git_url, protocol),
            failure,
            interrupt,
        })
    }
}

struct Connection {
    transport: Transport<GitHttp>,
    /// Why a request failed, see [`remote_failed`].
    failure: Arc<Mutex<Option<Failure>>>,
    interrupt: Interrupt,
}

/// Stops the transfer when dropped, e.g. when the task waiting for it is aborted on shutdown,
/// since the blocking thread doing it cannot be aborted.
#[derive(Default)]
struct Interrupt {
    cancel: CancellationToken,
    /// For gitoxide, which checks it while receiving a pack.
    flag: Arc<AtomicBool>,
}

impl Drop for Interrupt {
    fn drop(&mut self) {
        self.cancel.cancel();
        self.flag.store(true, Ordering::Relaxed);
    }
}

/// Credentials are sent as a header by [`GitHttp`], gitoxide must not ask for others, e.g.
/// from a credential helper or a terminal prompt.
pub(super) fn no_credentials(
    _: gix::credentials::helper::Action,
) -> gix::error::Result<Option<gix::credentials::protocol::Outcome>> {
    Ok(None)
}

fn agent() -> gix::protocol::command::Feature {
    (
        "agent",
        Some(concat!("repolupe/", env!("CARGO_PKG_VERSION")).to_string()),
    )
}

/// Resolves `host` and fails unless every address is public.
async fn resolve_public(host: &Host<&str>, port: u16) -> Result<(), AppError> {
    let addresses: Vec<IpAddr> = match host {
        Host::Ipv4(ip) => vec![IpAddr::V4(*ip)],
        Host::Ipv6(ip) => vec![IpAddr::V6(*ip)],
        Host::Domain(domain) => {
            let lookup = tokio::net::lookup_host((*domain, port));
            match tokio::time::timeout(RESOLVE_TIMEOUT, lookup).await {
                Ok(Ok(addresses)) => addresses.map(|a| a.ip()).collect(),
                Ok(Err(_)) => {
                    return Err(AppError::Unprocessable(
                        ErrorCode::RepoNotFound,
                        "Remote host could not be resolved".to_string(),
                    ));
                }
                Err(_) => {
                    return Err(remote_unreachable(
                        "Timed out while resolving the remote host",
                    ));
                }
            }
        }
    };

    if addresses.is_empty() || !addresses.iter().copied().all(is_public_ip) {
        return Err(not_public());
    }
    Ok(())
}

/// The error for a failed `operation` with a remote, from the failure of the request if any.
fn remote_failed(
    operation: &str,
    failure: &Mutex<Option<Failure>>,
    error: gix::error::Error,
) -> AppError {
    let failure = failure.lock().unwrap_or_else(|e| e.into_inner()).clone();
    match failure {
        Some(Failure::Status(status)) if matches!(status.as_u16(), 401 | 403) => {
            AppError::Unprocessable(
                ErrorCode::AuthFailed,
                "The remote rejected the credentials or requires a token".to_string(),
            )
        }
        Some(Failure::Status(status)) if status.is_redirection() => AppError::Unprocessable(
            ErrorCode::RepoNotFound,
            "Repository not found (the remote redirected the request; if it moved, use its new URL)".to_string(),
        ),
        Some(Failure::Status(status)) if status.as_u16() == 404 => AppError::Unprocessable(
            ErrorCode::RepoNotFound,
            "Repository not found".to_string(),
        ),
        Some(Failure::NotSmartGit) => AppError::Unprocessable(
            ErrorCode::RepoNotFound,
            "Repository not found (the remote is no git server, or one that only supports the dumb HTTP protocol)".to_string(),
        ),
        Some(Failure::NotPublic) => not_public(),
        Some(Failure::TimedOut) => remote_unreachable("Timed out while contacting the remote"),
        Some(Failure::Cancelled) => {
            AppError::InternalServerError(format!("git {operation} was cancelled"))
        }
        failure => {
            // Never contains the token: it is only sent as a header.
            tracing::warn!("git {operation} failed: {error:?} ({failure:?})");
            remote_unreachable("The remote could not be reached")
        }
    }
}

/// Like [`remote_failed`], but credentials the remote refuses may well be fine for reading.
fn push_failed(failure: &Mutex<Option<Failure>>, error: gix::error::Error) -> AppError {
    match remote_failed("push", failure, error) {
        AppError::Unprocessable(ErrorCode::AuthFailed, _) => AppError::Unprocessable(
            ErrorCode::AuthFailed,
            "The remote does not accept pushes with the token, which needs write access"
                .to_string(),
        ),
        other => other,
    }
}

fn branch_not_found() -> AppError {
    AppError::Unprocessable(ErrorCode::BranchNotFound, "Branch not found".to_string())
}

fn not_public() -> AppError {
    AppError::BadRequest("Remote URL must not point to a private or reserved address".to_string())
}

fn remote_unreachable(message: &str) -> AppError {
    AppError::BadGateway(ErrorCode::RemoteUnreachable, message.to_string())
}
