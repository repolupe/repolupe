//! [`CHANGE_FILE`]: proposes a commit that edits, writes or deletes one file, which the user
//! reviews and pushes, see [`crate::service::commit`].

use super::support::commit::{Identity, MAX_CHANGE_BYTES, parse_commit_message, parse_commit_path};
use super::support::{
    BINARY_CHECK_BYTES, MAX_OUTPUT_CHARS, file_path_schema, format_size, missing_path, parent_dirs,
    parse_args, patch, window, writable_repository_schema,
};
use super::{CHANGE_FILE, Call, Invocation, READ_FILE, RepositoryTools, ToolError, ToolRepository};
use crate::model::tool_call::{ChangedPaths, ProposedChange};
use crate::service::extraction;
use crate::service::llm::ToolDefinition;
use crate::service::mirror::{BlobMode, Content, PathEntry, Signature};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{Value, json};

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: CHANGE_FILE.to_string(),
        description: format!(
            "Propose a commit that changes one file: edit it, create or replace it, or \
            delete it. Nothing is committed yet: the change appears below your answer, \
            and the user decides whether to commit it. Each call starts from the \
            repository as you read it, and the other tools don't see the change, so \
            make all changes to a file in one call; calling it again for the same file \
            replaces the earlier proposal. Read the file with {READ_FILE} before editing \
            it. PDFs and binary files can only be deleted."
        ),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": writable_repository_schema(tools, "The repository to change."),
                "path": file_path_schema(),
                "message": {
                    "type": "string",
                    "description": "The commit message: a summary of at most about \
                        70 characters, e.g. `Fix the install steps for macOS`, \
                        optionally followed by an empty line and an explanation.",
                },
                "edits": {
                    "type": "array",
                    "minItems": 1,
                    "description": "Replacements in an existing file, applied in \
                        order. Use them for changes to parts of a file.",
                    "items": {
                        "type": "object",
                        "properties": {
                            "old_string": {
                                "type": "string",
                                "description": format!(
                                    "Text copied exactly from the file, without the \
                                    line numbers {READ_FILE} adds. Must occur exactly \
                                    once unless `replace_all` is set, so include \
                                    surrounding lines to make it unique."
                                ),
                            },
                            "new_string": {
                                "type": "string",
                                "description": "The text that replaces it.",
                            },
                            "replace_all": {
                                "type": "boolean",
                                "description": "Replace every occurrence, false by \
                                    default.",
                            },
                        },
                        "required": ["old_string", "new_string"],
                    },
                },
                "content": {
                    "type": "string",
                    "description": "The whole content of the file, to create it or \
                        to replace all of it.",
                },
                "delete": {
                    "type": "boolean",
                    "description": "true to delete the file.",
                },
            },
            "required": ["repository", "path", "message"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    path: String,
    message: String,
    edits: Option<Vec<Edit>>,
    content: Option<String>,
    delete: Option<bool>,
}

#[derive(Deserialize)]
struct Edit {
    old_string: String,
    new_string: String,
    #[serde(default)]
    replace_all: bool,
}

pub(super) struct Args {
    path: String,
    message: String,
    change: Change,
}

/// What the call does to its file.
enum Change {
    /// Replacements in an existing file, applied in order.
    Edit(Vec<Edit>),
    /// Creates the file or replaces its content.
    Write(String),
    Delete,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(CHANGE_FILE, input)?;
    let path = parse_commit_path(&input.path)?;
    let message = parse_commit_message(&input.message)?;
    let change = match (input.edits, input.content, input.delete.unwrap_or(false)) {
        (Some(edits), None, false) => {
            if edits.is_empty() {
                return Err("`edits` must not be empty.".to_string());
            }
            for edit in &edits {
                if edit.old_string.is_empty() {
                    return Err(
                        "`old_string` must not be empty. To create a file, pass `content`."
                            .to_string(),
                    );
                }
                if edit.old_string == edit.new_string {
                    return Err("`old_string` and `new_string` must differ.".to_string());
                }
            }
            Change::Edit(edits)
        }
        (None, Some(content), false) => {
            if content.len() as u64 > MAX_CHANGE_BYTES {
                return Err(format!(
                    "`content` must be at most {}.",
                    format_size(MAX_CHANGE_BYTES)
                ));
            }
            Change::Write(content)
        }
        (None, None, true) => Change::Delete,
        _ => {
            return Err("Pass exactly one of `edits`, `content`, or `delete: true`.".to_string());
        }
    };
    let args = Args {
        path,
        message,
        change,
    };
    Ok((input.repository, Call::ChangeFile(args)))
}

/// Writes the commit the model proposes, which the user reads with
/// [`read_proposed_commit_patch`](super::read_proposed_commit_patch). Returns the output for the model
/// with the diff.
pub(super) async fn run(
    invocation: &Invocation<'_>,
    args: &Args,
) -> Result<(String, ProposedChange), ToolError> {
    let repository = invocation.target()?;
    let identities = invocation.identities;
    let path = args.path.as_str();
    let change = &args.change;
    let snapshot = &repository.snapshot;
    let existing = match snapshot.entry(path).await? {
        PathEntry::Blob { oid, mode } => Some((oid, mode)),
        PathEntry::Missing => None,
        PathEntry::Tree => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is a directory, only files can be changed."
            )));
        }
        PathEntry::Other => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is not a file, e.g. a submodule, and can't be changed."
            )));
        }
    };
    if let Some((_, BlobMode::Link)) = existing {
        return Err(ToolError::Invalid(format!(
            "`{path}` is a symbolic link and can't be changed."
        )));
    }

    let (old, new) = match (change, &existing) {
        (Change::Delete, Some(_)) => (None, None),
        (Change::Delete | Change::Edit(_), None) => {
            let mut error = missing_path(repository, path).await?;
            if let (Change::Edit(_), ToolError::Invalid(message)) = (change, &mut error) {
                message.push_str(" To create a file, pass `content`.");
            }
            return Err(error);
        }
        (_, Some(_)) if extraction::is_document(path) => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is a PDF, which can only be deleted."
            )));
        }
        (Change::Write(content), None) => {
            for dir in parent_dirs(path) {
                if let PathEntry::Blob { .. } = snapshot.entry(dir).await? {
                    return Err(ToolError::Invalid(format!(
                        "`{dir}` is a file, so `{path}` can't be created."
                    )));
                }
            }
            (None, Some(content.clone()))
        }
        (Change::Write(_) | Change::Edit(_), Some((oid, _))) => {
            let old = read_changeable(repository, path, oid).await?;
            // Keeps Windows line endings, which the model does not see in read_file.
            let crlf = old.contains("\r\n");
            let with_line_endings = |text: &str| {
                if crlf && !text.contains('\r') {
                    text.replace('\n', "\r\n")
                } else {
                    text.to_string()
                }
            };
            let new = match change {
                Change::Write(content) => with_line_endings(content),
                Change::Edit(edits) => apply_edits(&old, edits, path, with_line_endings)?,
                Change::Delete => unreachable!("handled above"),
            };
            if new == old {
                return Err(ToolError::Invalid(format!(
                    "The change leaves `{path}` as it is."
                )));
            }
            (Some(old), Some(new))
        }
    };

    let content = new.clone().map(|new| {
        let mode = existing
            .as_ref()
            .map_or(BlobMode::Regular, |(_, mode)| *mode);
        (new.into_bytes(), mode)
    });
    let now = Utc::now();
    let signature = |identity: &Identity| Signature {
        name: identity.name.clone(),
        email: identity.email.clone(),
        time: now,
    };
    let commit = snapshot
        .commit_file(
            path,
            content,
            &args.message,
            &signature(&identities.author),
            &signature(&identities.committer),
        )
        .await?;

    let action = match (&existing, &new) {
        (None, _) => "creates",
        (Some(_), None) => "deletes",
        (Some(_), Some(_)) => "changes",
    };
    let mut output = format!(
        "Proposed a commit that {action} `{path}`. It is not committed yet: the user sees it \
        below your answer and decides whether to commit it. To revise it, call {CHANGE_FILE} \
        for `{path}` again with all changes."
    );
    if let Some(new) = &new {
        let diff = patch::hunks(old.as_deref().unwrap_or(""), new);
        let diff = window(&diff, 0, MAX_OUTPUT_CHARS);
        let _ = std::fmt::Write::write_fmt(&mut output, format_args!("\n\n```diff\n{diff}```"));
    }
    Ok((
        output,
        ProposedChange {
            changed: ChangedPaths::File(path.to_string()),
            proposed_commit: commit,
        },
    ))
}

/// The content of the text file `path` with blob `oid`, if it can be changed.
async fn read_changeable(
    repository: &ToolRepository,
    path: &str,
    oid: &str,
) -> Result<String, ToolError> {
    let content = match repository.snapshot.read(oid, MAX_CHANGE_BYTES).await? {
        Content::Bytes(content) => content,
        Content::TooLarge(size) => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is too large to change ({}).",
                format_size(size)
            )));
        }
        Content::Unavailable => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is stored outside the repository (Git LFS) and can only be deleted."
            )));
        }
    };
    if content[..content.len().min(BINARY_CHECK_BYTES)].contains(&0) {
        return Err(ToolError::Invalid(format!(
            "`{path}` is a binary file, which can only be deleted."
        )));
    }
    String::from_utf8(content).map_err(|_| {
        ToolError::Invalid(format!(
            "`{path}` is not UTF-8 text and can only be deleted."
        ))
    })
}

/// Applies `edits` to `content` in order, with `line_endings` applied to their strings.
fn apply_edits(
    content: &str,
    edits: &[Edit],
    path: &str,
    line_endings: impl Fn(&str) -> String,
) -> Result<String, ToolError> {
    let mut content = content.to_string();
    for (i, edit) in edits.iter().enumerate() {
        let which = if edits.len() > 1 {
            format!("Edit {}: ", i + 1)
        } else {
            String::new()
        };
        let old = line_endings(&edit.old_string);
        let new = line_endings(&edit.new_string);
        match content.matches(&old).count() {
            0 => {
                return Err(ToolError::Invalid(format!(
                    "{which}`old_string` does not occur in `{path}`{}. Copy it exactly from \
                    {READ_FILE}, without the line numbers.",
                    if i > 0 {
                        " after the earlier edits"
                    } else {
                        ""
                    }
                )));
            }
            1 => content = content.replacen(&old, &new, 1),
            _ if edit.replace_all => content = content.replace(&old, &new),
            count => {
                return Err(ToolError::Invalid(format!(
                    "{which}`old_string` occurs {count} times in `{path}`. Include surrounding \
                    lines to make it unique, or set `replace_all` to replace every occurrence."
                )));
            }
        }
    }
    Ok(content)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::llm::ToolUse;
    use crate::service::mirror::Snapshot;
    use crate::service::tools::support::fixture::{Fixture, docs, identities};
    use crate::service::tools::{read_proposed_commit_patch, unused_db};
    use uuid::Uuid;

    #[tokio::test]
    async fn proposes_edits() {
        let fixture = docs();
        let (output, change) = fixture
            .change(json!({
                "repository": "docs",
                "path": "./docs/guide.md",
                "message": "Use apt\n\nHomebrew is for macOS only.",
                "edits": [
                    {"old_string": "Use Homebrew.", "new_string": "Use apt."},
                    {"old_string": "API", "new_string": "REST API", "replace_all": true},
                ],
            }))
            .await;
        assert_eq!(
            output,
            "Proposed a commit that changes `docs/guide.md`. It is not committed yet: the user \
            sees it below your answer and decides whether to commit it. To revise it, call \
            change_file for `docs/guide.md` again with all changes.\n\n```diff\n\
            @@ -8,8 +8,8 @@\n \n ### macOS\n \n-Use Homebrew.\n+Use apt.\n \n ## Usage\n \n\
            -Call the API with your API key.\n+Call the REST API with your REST API key.\n```"
        );
        assert_eq!(
            change.changed,
            ChangedPaths::File("docs/guide.md".to_string())
        );

        // One commit on top of the snapshot that changes only the file.
        let base = fixture.git(&["rev-parse", "HEAD"]);
        let parent = fixture.git(&["rev-parse", &format!("{}^", change.proposed_commit)]);
        assert_eq!(parent, base);
        assert_eq!(
            fixture.git(&["diff", "--name-status", "HEAD", &change.proposed_commit]),
            "M\tdocs/guide.md\n"
        );
        assert_eq!(
            fixture.git(&[
                "log",
                "-1",
                "--format=%an <%ae>%n%cn <%ce>%n%B",
                &change.proposed_commit
            ]),
            "Repolupe+model <noreply@repolupe.com>\nAlice <alice@example.com>\n\
            Use apt\n\nHomebrew is for macOS only.\n\n"
        );

        // The patch applies to the snapshot.
        let repository = &fixture.tools.repositories()[0];
        let proposed = Snapshot::at(fixture.dir.join(".git"), change.proposed_commit.clone());
        let patch = read_proposed_commit_patch(repository, &proposed, &change.changed)
            .await
            .unwrap();
        assert!(
            patch.starts_with(&format!("From {} Mon Sep 17", change.proposed_commit)),
            "{patch}"
        );
        assert!(
            patch.contains("From: Repolupe+model <noreply@repolupe.com>\n"),
            "{patch}"
        );
        assert!(
            patch.contains("Subject: [PATCH] Use apt\n\nHomebrew is for macOS only.\n---\n"),
            "{patch}"
        );
        let patch_file = fixture.dir.join("change.patch");
        std::fs::write(&patch_file, &patch).unwrap();
        fixture.git(&["apply", "--check", patch_file.to_str().unwrap()]);
    }

    #[tokio::test]
    async fn proposes_new_and_deleted_files() {
        let fixture = docs();
        let (output, change) = fixture
            .change(json!({
                "path": "docs/new/notes.md",
                "message": "Add notes",
                "content": "# Notes\n",
            }))
            .await;
        assert!(
            output.starts_with("Proposed a commit that creates `docs/new/notes.md`."),
            "{output}"
        );
        assert!(output.ends_with("@@ -0,0 +1 @@\n+# Notes\n```"), "{output}");
        assert_eq!(
            fixture.git(&["diff", "--name-status", "HEAD", &change.proposed_commit]),
            "A\tdocs/new/notes.md\n"
        );

        // Also binary files and documents.
        for path in ["logo.png", "slides.pdf"] {
            let (output, change) = fixture
                .change(json!({"path": path, "message": "Remove it", "delete": true}))
                .await;
            assert!(
                output.starts_with(&format!("Proposed a commit that deletes `{path}`.")),
                "{output}"
            );
            assert!(!output.contains("```"));
            assert_eq!(
                fixture.git(&["diff", "--name-status", "HEAD", &change.proposed_commit]),
                format!("D\t{path}\n")
            );
        }
    }

    #[tokio::test]
    async fn keeps_modes_and_line_endings() {
        let fixture = Fixture::new(&[("run.sh", b"echo hi\n"), ("win.txt", b"a\r\nb\r\n")]);
        // Set the mode in the index, which works on file systems without one.
        fixture.git(&["update-index", "--chmod=+x", "run.sh"]);
        fixture.git(&["commit", "--quiet", "--message", "executable"]);
        let commit = fixture.git(&["rev-parse", "HEAD"]).trim().to_string();
        let tools = RepositoryTools::new(
            vec![ToolRepository {
                id: Uuid::now_v7(),
                name: "docs".to_string(),
                snapshot: Snapshot::at(fixture.dir.join(".git"), commit),
                can_commit: true,
            }],
            unused_db(),
            identities(),
        );
        let change = |input: Value| {
            let tools = &tools;
            async move {
                let tool_use = ToolUse {
                    id: "call".to_string(),
                    name: CHANGE_FILE.to_string(),
                    input,
                    native: None,
                };
                let output = tools.parse(&tool_use).ok().unwrap().run().await;
                assert!(!output.is_error, "{}", output.content);
                output.change.unwrap().proposed_commit
            }
        };

        let commit =
            change(json!({"path": "run.sh", "message": "Greet", "content": "echo hello\n"})).await;
        assert!(
            fixture
                .git(&["ls-tree", &commit, "run.sh"])
                .starts_with("100755 blob ")
        );
        let commit = change(json!({
            "path": "win.txt",
            "message": "Change b",
            "edits": [{"old_string": "a\nb", "new_string": "a\nc"}],
        }))
        .await;
        assert_eq!(
            fixture.git(&["show", &format!("{commit}:win.txt")]),
            "a\r\nc\r\n"
        );
    }

    #[tokio::test]
    async fn explains_rejected_changes() {
        let fixture = docs();
        let error = |input: Value| fixture.error(CHANGE_FILE, input);
        let edit = |path: &str, old: &str| json!({"path": path, "message": "m", "edits": [{"old_string": old, "new_string": "new"}]});
        assert_eq!(
            error(edit("README.md", "Missing")).await,
            "`old_string` does not occur in `README.md`. Copy it exactly from read_file, without \
            the line numbers."
        );
        assert_eq!(
            error(json!({"path": "docs/guide.md", "message": "m", "edits": [
                {"old_string": "Intro", "new_string": "Overview"},
                {"old_string": "API", "new_string": "REST API"},
            ]}))
            .await,
            "Edit 2: `old_string` occurs 2 times in `docs/guide.md`. Include surrounding lines \
            to make it unique, or set `replace_all` to replace every occurrence."
        );
        assert_eq!(
            error(edit("docs/install.md", "x")).await,
            "File or directory not found: `docs/install.md`. Use list_files to see the files. \
            To create a file, pass `content`."
        );
        assert_eq!(
            error(edit("docs", "x")).await,
            "`docs` is a directory, only files can be changed."
        );
        assert_eq!(
            error(edit("logo.png", "PNG")).await,
            "`logo.png` is a binary file, which can only be deleted."
        );
        assert_eq!(
            error(edit("slides.pdf", "x")).await,
            "`slides.pdf` is a PDF, which can only be deleted."
        );
        assert_eq!(
            error(edit("demo.mp4", "x")).await,
            "`demo.mp4` is stored outside the repository (Git LFS) and can only be deleted."
        );
        assert_eq!(
            error(json!({"path": "README.md/notes.md", "message": "m", "content": "x"})).await,
            "`README.md` is a file, so `README.md/notes.md` can't be created."
        );
        assert_eq!(
            error(json!({"path": "README.md", "message": "m", "content": "# Project\n\nSee docs/guide.md for the API key.\n"})).await,
            "The change leaves `README.md` as it is."
        );
        assert_eq!(
            error(json!({"path": "README.md", "message": "m", "content": "x", "delete": true}))
                .await,
            "Pass exactly one of `edits`, `content`, or `delete: true`."
        );
        assert_eq!(
            error(json!({"path": ".git/config", "message": "m", "content": "x"})).await,
            "Files in `.git` can't be changed."
        );
        assert_eq!(
            error(json!({"path": "README.md", "message": " ", "delete": true})).await,
            "`message` must not be empty."
        );
    }
}
