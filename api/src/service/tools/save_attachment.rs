//! [`SAVE_ATTACHMENT`]: proposes a commit that stores a file attached to the chat in a
//! repository, like [`CHANGE_FILE`](super::CHANGE_FILE).

use super::support::commit::{Identity, parse_commit_message, parse_commit_path};
use super::support::{parent_dirs, parse_args, writable_repository_schema};
use super::{
    Call, Invocation, LIST_FILES, READ_ATTACHMENT, RepositoryTools, SAVE_ATTACHMENT, ToolError,
};
use crate::model::tool_call::{ChangedPaths, ProposedChange};
use crate::service::llm::ToolDefinition;
use crate::service::mirror::{BlobMode, PathEntry, Signature};
use chrono::Utc;
use serde::Deserialize;
use serde_json::{Value, json};

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    let numbers: Vec<i32> = tools
        .attachments
        .sent
        .iter()
        .filter_map(|a| a.number)
        .collect();
    ToolDefinition {
        name: SAVE_ATTACHMENT.to_string(),
        description: format!(
            "Propose a commit that stores a file the user attached to the chat in a \
            repository. {} Use the place the user named. Otherwise choose the path like the files already there: look with {LIST_FILES} \
            where similar files are kept, e.g. with a glob for its extension, and follow \
            their naming. If the file name doesn't tell what the file is, read it with \
            {READ_ATTACHMENT} first. Calling it again for the same attachment replaces the earlier \
            proposal, e.g. when the user wants it stored elsewhere.",
            tools.proposal_outcome()
        ),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": writable_repository_schema(tools, "The repository to store it in."),
                "attachment": {
                    "type": "integer",
                    "enum": numbers,
                    "description": "The number of the attachment, e.g. 1 for \
                        attachment 1.",
                },
                "path": {
                    "type": "string",
                    "description": "Path of the file to create, relative to the \
                        repository root, including the file name, e.g. \
                        `invoices/2026/2026-10-acme.pdf`.",
                },
                "message": {
                    "type": "string",
                    "description": "The commit message: a summary of at most about \
                        70 characters, e.g. `Add the ACME invoice of October 2026`.",
                },
                "replace": {
                    "type": "boolean",
                    "description": "Replace the file if `path` exists, false by \
                        default. Only when the user wants to replace it.",
                },
            },
            "required": ["repository", "attachment", "path", "message"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    attachment: i32,
    path: String,
    message: String,
    replace: Option<bool>,
}

pub(super) struct Args {
    number: i32,
    path: String,
    message: String,
    /// Whether an existing file may be replaced.
    replace: bool,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(SAVE_ATTACHMENT, input)?;
    let args = Args {
        number: input.attachment,
        path: parse_commit_path(&input.path)?,
        message: parse_commit_message(&input.message)?,
        replace: input.replace.unwrap_or(false),
    };
    Ok((input.repository, Call::SaveAttachment(args)))
}

/// Proposes a commit that stores attachment `number` at `path`, which must not exist unless
/// `replace` is set.
pub(super) async fn run(
    invocation: &Invocation<'_>,
    args: &Args,
) -> Result<(String, ProposedChange), ToolError> {
    let identities = invocation.identities;
    let attachments = invocation.attachments;
    let number = args.number;
    let path = args.path.as_str();
    let attachment = attachments.find(number)?;
    let content = attachments.store()?.read(attachment.id).await?;
    let snapshot = &invocation.target()?.snapshot;
    let replaced = match snapshot.entry(path).await? {
        PathEntry::Missing => {
            for dir in parent_dirs(path) {
                if let PathEntry::Blob { .. } = snapshot.entry(dir).await? {
                    return Err(ToolError::Invalid(format!(
                        "`{dir}` is a file, so `{path}` can't be created."
                    )));
                }
            }
            None
        }
        PathEntry::Blob {
            mode: BlobMode::Link,
            ..
        } => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is a symbolic link and can't be replaced."
            )));
        }
        PathEntry::Blob { oid, .. }
            if snapshot
                .has_content(&oid, &attachment.blob_oid, &content)
                .await? =>
        {
            return Err(ToolError::Invalid(format!(
                "`{path}` already has the content of attachment {number}, it is stored there."
            )));
        }
        PathEntry::Blob { mode, .. } if args.replace => Some(mode),
        PathEntry::Blob { .. } => {
            return Err(ToolError::Invalid(format!(
                "`{path}` already exists. Choose another path, or set `replace` if the user \
                wants to replace it."
            )));
        }
        PathEntry::Tree => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is a directory. Pass the path of the file, including its name."
            )));
        }
        PathEntry::Other => {
            return Err(ToolError::Invalid(format!(
                "`{path}` is not a file, e.g. a submodule, and can't be replaced."
            )));
        }
    };

    let now = Utc::now();
    let signature = |identity: &Identity| Signature {
        name: identity.name.clone(),
        email: identity.email.clone(),
        time: now,
    };
    let commit = snapshot
        .commit_file(
            path,
            Some((content, replaced.unwrap_or(BlobMode::Regular))),
            &args.message,
            &signature(&identities.author),
            &signature(&identities.committer),
        )
        .await?;

    let action = if replaced.is_some() {
        "replaces"
    } else {
        "creates"
    };
    let output = format!(
        "Proposed a commit that {action} `{path}` with attachment {number} (`{}`). {} To store \
        it elsewhere, call {SAVE_ATTACHMENT} for attachment {number} again.",
        attachment.file_name,
        invocation.proposal_outcome()
    );
    Ok((
        output,
        ProposedChange {
            changed: ChangedPaths::File(path.to_string()),
            proposed_commit: commit,
        },
    ))
}
