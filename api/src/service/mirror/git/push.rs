//! Pushing over smart HTTP (`git-receive-pack`), which gitoxide cannot do yet. gitoxide's
//! transport lists the refs, then the ref update and a pack are posted like `git push` does,
//! and git's `report-status` is read back.

use super::http::GitHttp;
use gix::ObjectId;
use gix::bstr::ByteSlice;
use gix::protocol::transport::Service;
use gix::protocol::transport::client::blocking_io::http::Transport;
use gix::protocol::transport::client::blocking_io::{ReadlineBufRead, Transport as _};
use gix::protocol::transport::client::{MessageKind, WriteMode};
use std::io::Write;

/// The outcome of a push, other than an error.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum PushResult {
    Pushed,
    /// The branch is no longer at the expected commit.
    Moved,
    /// The remote refused the update, e.g. of a protected branch, for this reason.
    Rejected(String),
}

/// What the remote lists for a push.
pub(super) struct Advertisement {
    /// The commit of the branch, `None` if it is missing.
    pub(super) head: Option<ObjectId>,
    /// The capabilities to request.
    capabilities: String,
}

/// Lists the refs for a push, which servers refuse without write access, and finds
/// `branch_ref`.
pub(super) fn advertise(
    transport: &mut Transport<GitHttp>,
    branch_ref: &str,
) -> gix::error::Result<Advertisement> {
    let handshake = gix::protocol::handshake(
        &mut *transport,
        Service::ReceivePack,
        super::remote::no_credentials,
        Vec::new(),
        &mut gix::progress::Discard,
    )?;
    let capabilities = &handshake.capabilities;
    // Without it, the remote would not tell whether it updated the branch.
    if !capabilities.contains("report-status") {
        return Err(gix::error::Error::from_error(std::io::Error::other(
            "the remote does not report the status of pushes",
        )));
    }
    let mut requested = "report-status".to_string();
    if capabilities.contains("agent") {
        requested.push_str(concat!(" agent=repolupe/", env!("CARGO_PKG_VERSION")));
    }
    let head = handshake.refs.iter().flatten().find_map(|r| {
        let (name, target, _) = r.unpack();
        (name == branch_ref.as_bytes()).then(|| target.map(ToOwned::to_owned))?
    });
    Ok(Advertisement {
        head,
        capabilities: requested,
    })
}

/// Updates `branch_ref` from `expected` to `commit` with `pack`, which holds the objects the
/// remote is missing. Needs [`advertise`] first.
pub(super) fn send(
    transport: &mut Transport<GitHttp>,
    advertisement: &Advertisement,
    branch_ref: &str,
    expected: ObjectId,
    commit: ObjectId,
    pack: &[u8],
) -> gix::error::Result<PushResult> {
    let request = transport
        .request(WriteMode::Binary, MessageKind::Flush, false)
        .map_err(gix::error::Error::from_error)?;
    // Written as is: the command as a packet line, then a flush and the pack, which is not
    // split into packet lines.
    let (mut body, mut response) = request.into_parts();
    let command = format!(
        "{expected} {commit} {branch_ref}\0{}",
        advertisement.capabilities
    );
    body.write_all(&packet_line(command.as_bytes()))
        .and_then(|()| body.write_all(b"0000"))
        .and_then(|()| body.write_all(pack))
        .map_err(gix::error::Error::from_error)?;
    drop(body);

    let mut report = Vec::new();
    while let Some(line) = response.readline() {
        let line = line
            .map_err(gix::error::Error::from_error)?
            .map_err(gix::error::Error::from_error)?;
        match line.as_bstr() {
            Some(text) => report.push(text.trim_end().to_str_lossy().into_owned()),
            None => break,
        }
    }
    parse_report(&report, branch_ref)
}

fn packet_line(data: &[u8]) -> Vec<u8> {
    let mut line = format!("{:04x}", data.len() + 4).into_bytes();
    line.extend_from_slice(data);
    line
}

/// Reads git's `report-status`: `unpack ok`, then `ok <ref>` or `ng <ref> <reason>`.
fn parse_report(lines: &[String], branch_ref: &str) -> gix::error::Result<PushResult> {
    let invalid = || {
        gix::error::Error::from_error(std::io::Error::other(format!(
            "unexpected push report: {lines:?}"
        )))
    };
    let unpack = lines
        .first()
        .and_then(|line| line.strip_prefix("unpack "))
        .ok_or_else(invalid)?;
    if unpack != "ok" {
        return Ok(PushResult::Rejected(format!(
            "the remote could not store the commit ({unpack})"
        )));
    }
    for line in &lines[1..] {
        if line.strip_prefix("ok ") == Some(branch_ref) {
            return Ok(PushResult::Pushed);
        }
        if let Some(reason) = line
            .strip_prefix("ng ")
            .and_then(|rest| rest.strip_prefix(branch_ref))
            .and_then(|rest| rest.strip_prefix(' '))
        {
            return Ok(PushResult::Rejected(reason.to_string()));
        }
    }
    Err(invalid())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn report(lines: &[&str]) -> gix::error::Result<PushResult> {
        let lines: Vec<String> = lines.iter().map(|l| l.to_string()).collect();
        parse_report(&lines, "refs/heads/main")
    }

    #[test]
    fn parses_reports() {
        assert_eq!(
            report(&["unpack ok", "ok refs/heads/main"]).unwrap(),
            PushResult::Pushed
        );
        assert_eq!(
            report(&[
                "unpack ok",
                "ng refs/heads/main protected branch hook declined"
            ])
            .unwrap(),
            PushResult::Rejected("protected branch hook declined".to_string())
        );
        assert_eq!(
            report(&[
                "unpack index-pack failed",
                "ng refs/heads/main unpacker error"
            ])
            .unwrap(),
            PushResult::Rejected(
                "the remote could not store the commit (index-pack failed)".to_string()
            )
        );
        assert!(report(&["unpack ok", "ok refs/heads/other"]).is_err());
        assert!(report(&[]).is_err());
    }

    #[test]
    fn writes_packet_lines() {
        assert_eq!(packet_line(b"a\n"), b"0006a\n");
    }
}
