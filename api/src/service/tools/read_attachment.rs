//! [`READ_ATTACHMENT`]: a file attached to the chat, like [`READ_FILE`] reads one in a
//! repository. Documents are converted when they are uploaded (see
//! [`crate::service::extraction`]), so this waits for a conversion that is still running.

use super::read_file::{DEFAULT_READ_LINES, MAX_READ_LINES, format_lines};
use super::support::{
    MAX_READ_BYTES, Text, decode_text, document_text, format_size, image_output, parse_args,
};
use super::{
    Call, ChatAttachments, Invocation, READ_ATTACHMENT, READ_FILE, RepositoryTools, ToolError,
    ToolOutput,
};
use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::model::attachment::Attachment;
use crate::model::document_extraction::DocumentExtraction;
use crate::service::extraction;
use crate::service::image::{MAX_IMAGE_BYTES, is_image};
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
            reads one in a repository. PDFs are returned as Markdown converted from them, with the text of scanned pages \
            recognized by OCR. Images (PNG, JPEG, GIF, WebP) are returned as the image itself, \
            for you to look at. Other binary files can't be read."
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

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<ToolOutput, ToolError> {
    let attachments = invocation.attachments;
    let attachment = attachments.find(args.number)?;
    let name = &attachment.file_name;
    if is_image(name) {
        let content = read_content(attachments, attachment, MAX_IMAGE_BYTES).await?;
        return image_output(name, content).await;
    }
    let text = read_text(attachments, invocation.db, args.number).await?;
    format_lines(name, text, args.offset, args.limit).map(ToolOutput::text)
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
    let content = read_content(attachments, attachment, MAX_READ_BYTES).await?;
    decode_text(name, &content)
}

/// The content of `attachment`, an error for the model if it is larger than `max_size` bytes.
async fn read_content(
    attachments: &ChatAttachments,
    attachment: &Attachment,
    max_size: u64,
) -> Result<Vec<u8>, ToolError> {
    let size = attachment.size.max(0) as u64;
    if size > max_size {
        return Err(ToolError::Invalid(format!(
            "`{}` is too large to read ({}).",
            attachment.file_name,
            format_size(size)
        )));
    }
    Ok(attachments.store()?.read(attachment.id).await?)
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
