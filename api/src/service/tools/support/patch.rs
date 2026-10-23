//! The changes proposed with [`CHANGE_FILE`](crate::service::tools::CHANGE_FILE) and the other
//! tools that propose commits as diffs and patches.

use crate::service::mirror::{BlobMode, CommitInfo};
use similar::Algorithm;
use std::fmt::Write;

/// Lines of context around each change, like git.
pub(crate) const CONTEXT_LINES: usize = 3;
/// Bytes checked for NUL to detect binary files, like git does.
const BINARY_CHECK_BYTES: usize = 8000;
const NO_OID: &str = "0000000000000000000000000000000000000000";

/// A file on one side of a change.
pub(crate) struct Side<'a> {
    pub(crate) oid: &'a str,
    pub(crate) mode: BlobMode,
    pub(crate) content: &'a [u8],
}

/// Whether `content` has no text diff, like git decides it, or is not UTF-8.
pub(crate) fn is_binary(content: &[u8]) -> bool {
    content[..content.len().min(BINARY_CHECK_BYTES)].contains(&0)
        || std::str::from_utf8(content).is_err()
}

/// The hunks of a unified diff from `old` to `new`, like `git diff` without its headers.
pub(crate) fn hunks(old: &str, new: &str) -> String {
    similar::udiff::unified_diff(Algorithm::Myers, old, new, CONTEXT_LINES, None)
}

/// `diff`, the diffs of the files [`file_diff`] and [`rename_diff`] write, as a patch like
/// `git format-patch` writes it for `commit`, so `git am` applies it.
pub(crate) fn format_patch(commit: &str, info: &CommitInfo, diff: &str) -> String {
    let mut patch = String::new();
    let message = info.message.trim();
    let (subject, body) = message.split_once('\n').unwrap_or((message, ""));
    let _ = writeln!(patch, "From {commit} Mon Sep 17 00:00:00 2001");
    let _ = writeln!(patch, "From: {} <{}>", info.author.name, info.author.email);
    let _ = writeln!(patch, "Date: {}", info.author.time.to_rfc2822());
    let _ = writeln!(patch, "Subject: [PATCH] {}", subject.trim());
    patch.push('\n');
    let body = body.trim();
    if !body.is_empty() {
        let _ = writeln!(patch, "{body}");
    }
    patch.push_str("---\n");
    patch.push_str(diff);
    patch.push_str("-- \nrepolupe\n");
    patch
}

/// The diff of a file that was moved from `from` to `to` without changes, like `git diff -M`.
pub(crate) fn rename_diff(from: &str, to: &str) -> String {
    format!(
        "diff --git a/{from} b/{to}\nsimilarity index 100%\nrename from {from}\nrename to {to}\n"
    )
}

/// The diff of `path` from `old` to `new` (`None` where the file does not exist), like
/// `git diff`.
pub(crate) fn file_diff(path: &str, old: Option<Side<'_>>, new: Option<Side<'_>>) -> String {
    let mut patch = String::new();
    let _ = writeln!(patch, "diff --git a/{path} b/{path}");
    let (old_oid, new_oid) = (
        old.as_ref().map_or(NO_OID, |s| s.oid),
        new.as_ref().map_or(NO_OID, |s| s.oid),
    );
    match (&old, &new) {
        (None, Some(new)) => {
            let _ = writeln!(patch, "new file mode {}", new.mode.octal());
            let _ = writeln!(patch, "index {old_oid}..{new_oid}");
        }
        (Some(old), None) => {
            let _ = writeln!(patch, "deleted file mode {}", old.mode.octal());
            let _ = writeln!(patch, "index {old_oid}..{new_oid}");
        }
        (Some(old), Some(new)) if old.mode != new.mode => {
            let _ = writeln!(patch, "old mode {}", old.mode.octal());
            let _ = writeln!(patch, "new mode {}", new.mode.octal());
            let _ = writeln!(patch, "index {old_oid}..{new_oid}");
        }
        (Some(old), Some(_)) => {
            let _ = writeln!(patch, "index {old_oid}..{new_oid} {}", old.mode.octal());
        }
        (None, None) => {}
    }
    let (old_name, new_name) = (
        old.as_ref()
            .map_or("/dev/null".to_string(), |_| format!("a/{path}")),
        new.as_ref()
            .map_or("/dev/null".to_string(), |_| format!("b/{path}")),
    );
    let is_binary = |side: &Option<Side<'_>>| side.as_ref().is_some_and(|s| is_binary(s.content));
    if is_binary(&old) || is_binary(&new) {
        let _ = writeln!(patch, "Binary files {old_name} and {new_name} differ");
    } else {
        let text = |side: &Option<Side<'_>>| {
            side.as_ref()
                .map(|s| String::from_utf8_lossy(s.content).into_owned())
                .unwrap_or_default()
        };
        let hunks = hunks(&text(&old), &text(&new));
        if !hunks.is_empty() {
            let _ = writeln!(patch, "--- {old_name}");
            let _ = writeln!(patch, "+++ {new_name}");
            patch.push_str(&hunks);
        }
    }
    patch
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::mirror::Signature;
    use chrono::DateTime;

    fn info(message: &str) -> CommitInfo {
        CommitInfo {
            author: Signature {
                name: "Alice".to_string(),
                email: "alice@example.com".to_string(),
                time: DateTime::from_timestamp(1_790_000_000, 0).unwrap(),
            },
            message: message.to_string(),
        }
    }

    #[test]
    fn diffs_lines() {
        assert_eq!(
            hunks("a\nb\nc\n", "a\nB\nc\n"),
            "@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n"
        );
        assert_eq!(hunks("same\n", "same\n"), "");
    }

    #[test]
    fn formats_patches() {
        let old = Side {
            oid: "1111111111111111111111111111111111111111",
            mode: BlobMode::Executable,
            content: b"echo hi\n",
        };
        let new = Side {
            oid: "2222222222222222222222222222222222222222",
            mode: BlobMode::Executable,
            content: b"echo hello\n",
        };
        let patch = format_patch(
            "3333333333333333333333333333333333333333",
            &info("Greet louder\n\nHello is friendlier.\n"),
            &file_diff("run.sh", Some(old), Some(new)),
        );
        assert_eq!(
            patch,
            "From 3333333333333333333333333333333333333333 Mon Sep 17 00:00:00 2001\n\
            From: Alice <alice@example.com>\n\
            Date: Mon, 21 Sep 2026 14:13:20 +0000\n\
            Subject: [PATCH] Greet louder\n\
            \n\
            Hello is friendlier.\n\
            ---\n\
            diff --git a/run.sh b/run.sh\n\
            index 1111111111111111111111111111111111111111..2222222222222222222222222222222222222222 100755\n\
            --- a/run.sh\n\
            +++ b/run.sh\n\
            @@ -1 +1 @@\n\
            -echo hi\n\
            +echo hello\n\
            -- \n\
            repolupe\n"
        );

        let created = format_patch(
            "3333333333333333333333333333333333333333",
            &info("Add notes"),
            &file_diff(
                "notes.md",
                None,
                Some(Side {
                    oid: "2222222222222222222222222222222222222222",
                    mode: BlobMode::Regular,
                    content: b"Notes",
                }),
            ),
        );
        assert!(
            created.contains(
                "Subject: [PATCH] Add notes\n\n---\n\
                diff --git a/notes.md b/notes.md\n\
                new file mode 100644\n\
                index 0000000000000000000000000000000000000000..2222222222222222222222222222222222222222\n\
                --- /dev/null\n\
                +++ b/notes.md\n\
                @@ -0,0 +1 @@\n\
                +Notes\n\
                \\ No newline at end of file\n"
            ),
            "{created}"
        );

        let deleted = format_patch(
            "3333333333333333333333333333333333333333",
            &info("Remove the logo"),
            &file_diff(
                "logo.png",
                Some(Side {
                    oid: "1111111111111111111111111111111111111111",
                    mode: BlobMode::Regular,
                    content: b"\x89PNG\0",
                }),
                None,
            ),
        );
        assert!(
            deleted.contains(
                "deleted file mode 100644\n\
                index 1111111111111111111111111111111111111111..0000000000000000000000000000000000000000\n\
                Binary files a/logo.png and /dev/null differ\n"
            ),
            "{deleted}"
        );

        let moved = format_patch(
            "3333333333333333333333333333333333333333",
            &info("Archive the notes"),
            &(rename_diff("notes.md", "archive/notes.md") + &rename_diff("a b.md", "c d.md")),
        );
        assert!(
            moved.ends_with(
                "Subject: [PATCH] Archive the notes\n\n---\n\
                diff --git a/notes.md b/archive/notes.md\n\
                similarity index 100%\n\
                rename from notes.md\n\
                rename to archive/notes.md\n\
                diff --git a/a b.md b/c d.md\n\
                similarity index 100%\n\
                rename from a b.md\n\
                rename to c d.md\n\
                -- \n\
                repolupe\n"
            ),
            "{moved}"
        );
    }
}
