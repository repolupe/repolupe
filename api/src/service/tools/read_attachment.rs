//! [`READ_ATTACHMENT`]: a file attached to the chat, like [`READ_FILE`] reads one in a
//! repository. Documents are converted when they are uploaded (see
//! [`crate::service::extraction`]), so this waits for a conversion that is still running.

use super::read_file::{DEFAULT_READ_LINES, MAX_READ_LINES, format_lines};
use super::support::{MAX_READ_BYTES, Text, decode_text, document_text, format_size, parse_args};
use super::{
    Call, ChatAttachments, Invocation, READ_ATTACHMENT, READ_FILE, RepositoryTools, ToolError,
};
use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::model::attachment::Attachment;
use crate::model::document_extraction::DocumentExtraction;
use crate::service::extraction;
use crate::service::llm::ToolDefinition;
use serde::Deserialize;
use serde_json::{Value, json};
use std::time::Duration;

/// How long a call waits for a document that is still being converted.
const MAX_CONVERSION_WAIT: Duration = Duration::from_mins(2);

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: READ_ATTACHMENT.to_string(),
        description: format!(
            "Read a file the user attached to the chat, with line numbers, like {READ_FILE} \
            reads one in a repository. Returns up to {DEFAULT_READ_LINES} lines by default. \
            PDFs are returned as Markdown converted from them, with the text of scanned pages \
            recognized by OCR. Binary files, e.g. images, can't be read."
        ),
        input_schema: json!({
            "type": "object",
            "properties": {
                "attachment": {
                    "type": "integer",
                    "enum": tools.attachments.numbers(),
                    "description": "The number of the attachment, e.g. 1 for \
                        attachment 1.",
                },
                "offset": {
                    "type": "integer",
                    "minimum": 1,
                    "description": "Line to start at, 1 by default.",
                },
                "limit": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": MAX_READ_LINES,
                    "description": format!(
                        "Number of lines to read, {DEFAULT_READ_LINES} by default."
                    ),
                },
            },
            "required": ["attachment"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    attachment: i32,
    offset: Option<usize>,
    limit: Option<usize>,
}

pub(super) struct Args {
    number: i32,
    offset: Option<usize>,
    limit: Option<usize>,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(READ_ATTACHMENT, input)?;
    let args = Args {
        number: input.attachment,
        offset: input.offset,
        limit: input.limit,
    };
    Ok((None, Call::ReadAttachment(args)))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let attachments = invocation.attachments;
    let name = &attachments.find(args.number)?.file_name;
    let text = read_text(attachments, invocation.db, args.number).await?;
    format_lines(name, text, args.offset, args.limit)
}

/// Waits until the text of attachment `number` can be read with [`read_text`], i.e. until it is
/// converted if it is a document, which may still be running.
pub(super) async fn wait_for_conversion(
    attachments: &ChatAttachments,
    db: &DatabasePool,
    number: i32,
) -> Result<(), ToolError> {
    let attachment = attachments.find(number)?;
    if extraction::document_type(&attachment.content_type).is_some() {
        converted(attachments, db, attachment).await?;
    }
    Ok(())
}

/// The text of attachment `number`, the Markdown converted from it if it is a document.
/// Binary files are errors for the model.
pub(super) async fn read_text(
    attachments: &ChatAttachments,
    db: &DatabasePool,
    number: i32,
) -> Result<Text, ToolError> {
    let attachment = attachments.find(number)?;
    let name = attachment.file_name.as_str();
    if extraction::document_type(&attachment.content_type).is_some() {
        return document_text(name, converted(attachments, db, attachment).await?);
    }
    let size = attachment.size.max(0) as u64;
    if size > MAX_READ_BYTES {
        return Err(ToolError::Invalid(format!(
            "`{name}` is too large to read ({}).",
            format_size(size)
        )));
    }
    let content = attachments.store()?.read(attachment.id).await?;
    decode_text(name, &content)
}

/// The conversion of the document `attachment`, waiting for it if it is still running.
async fn converted(
    attachments: &ChatAttachments,
    db: &DatabasePool,
    attachment: &Attachment,
) -> Result<DocumentExtraction, ToolError> {
    let extractor = attachments.extractor.as_ref().ok_or_else(|| {
        AppError::InternalServerError("Attachments without the extractor".to_string())
    })?;
    extractor
        .wait_for_extraction(db, &attachment.blob_oid, MAX_CONVERSION_WAIT)
        .await?
        .ok_or_else(|| {
            ToolError::Invalid(format!(
                "The text of `{}` is not available yet, the file is still waiting to be \
                converted. Try again later.",
                attachment.file_name
            ))
        })
}
