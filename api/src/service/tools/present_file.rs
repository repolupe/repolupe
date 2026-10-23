//! [`PRESENT_FILE`]: shows a file to the user, as a button below the answer that opens it with
//! [`read_presented_file`].

use super::support::{
    file_path_schema, is_markdown, normalize_path, parse_args, read_text, repository_schema,
};
use super::{Call, Invocation, PRESENT_FILE, RepositoryTools, ToolError, ToolRepository};
use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::error::ErrorCode;
use crate::service::extraction;
use crate::service::llm::ToolDefinition;
use crate::service::mirror::{Content, PathEntry};
use serde::Deserialize;
use serde_json::{Value, json};

/// Larger documents are not shown to the user.
const MAX_PRESENT_BYTES: u64 = 100 * 1024 * 1024;

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: PRESENT_FILE.to_string(),
        description: "Show a file to the user. It appears below your answer as a button \
            that opens the file, so you don't need to copy its content into the answer. \
            Use it when the user wants to see or get a file, or when a file is what they \
            are looking for. Call it before writing your answer. Text files and PDFs can \
            be shown."
            .to_string(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": repository_schema(tools),
                "path": file_path_schema(),
            },
            "required": ["repository", "path"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    path: String,
}

pub(super) struct Args {
    path: String,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(PRESENT_FILE, input)?;
    let args = Args {
        path: normalize_path(&input.path)?,
    };
    Ok((input.repository, Call::PresentFile(args)))
}

/// Checks that the file can be shown, the user reads it with [`read_presented_file`].
pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let path = args.path.as_str();
    load_presented_file(invocation.target()?, invocation.db, path).await?;
    Ok(format!(
        "`{path}` is shown to the user as a button below your answer that opens the file."
    ))
}

/// A file the model showed to the user with [`PRESENT_FILE`], or the file a change proposes, as
/// it is in the repository.
pub(crate) struct PresentedFile {
    pub(crate) content: Vec<u8>,
    pub(crate) content_type: &'static str,
}

/// Reads a file to show to the user, at the commit of `repository`: the commit the answer read
/// for [`PRESENT_FILE`], the proposed one for a change.
pub(crate) async fn read_presented_file(
    repository: &ToolRepository,
    db: &DatabasePool,
    path: &str,
) -> Result<PresentedFile, AppError> {
    let path = normalize_path(path).map_err(|_| AppError::NotFound)?;
    match load_presented_file(repository, db, &path).await {
        Ok(file) => Ok(file),
        // The messages are meant for the model, but tell the user just as well why.
        Err(ToolError::Invalid(message)) => Err(AppError::Unprocessable(
            ErrorCode::FileUnavailable,
            format!("The file can't be shown: {message}"),
        )),
        Err(ToolError::Internal(e)) => Err(e),
    }
}

/// Documents are the original files, not the Markdown converted from them, so they can be
/// shown even if they could not be converted.
async fn load_presented_file(
    repository: &ToolRepository,
    db: &DatabasePool,
    path: &str,
) -> Result<PresentedFile, ToolError> {
    if let Some(mime_type) = extraction::mime_type(path)
        && let PathEntry::Blob { oid, .. } = repository.snapshot.entry(path).await?
    {
        return match repository.snapshot.read(&oid, MAX_PRESENT_BYTES).await? {
            Content::Bytes(content) => Ok(PresentedFile {
                content,
                content_type: mime_type,
            }),
            Content::TooLarge(_) => Err(ToolError::Invalid(format!(
                "`{path}` is too large to show."
            ))),
            // The sync downloads documents, unless they could not be downloaded yet.
            Content::Unavailable => Err(ToolError::Invalid(format!(
                "`{path}` is not available yet."
            ))),
        };
    }
    // Text files, and the errors for paths that are not files.
    let content = read_text(repository, db, path).await?.content;
    let content_type = if is_markdown(path) {
        "text/markdown; charset=utf-8"
    } else {
        "text/plain; charset=utf-8"
    };
    Ok(PresentedFile {
        content: content.into_bytes(),
        content_type,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::tools::support::fixture::{Fixture, GUIDE, docs};

    #[tokio::test]
    async fn presents_files() {
        let fixture = docs();
        assert_eq!(
            fixture
                .ok(PRESENT_FILE, json!({"path": "./docs/guide.md"}))
                .await,
            "`docs/guide.md` is shown to the user as a button below your answer that opens the file."
        );
        assert_eq!(
            fixture
                .error(PRESENT_FILE, json!({"path": "logo.png"}))
                .await,
            "`logo.png` is a binary file and can't be shown."
        );

        // Its LFS object was not downloaded.
        assert_eq!(
            fixture
                .error(PRESENT_FILE, json!({"path": "slides.pdf"}))
                .await,
            "`slides.pdf` is not available yet."
        );

        let repository = &fixture.tools.repositories()[0];
        let file = read_presented_file(repository, &fixture.tools.db, "docs/guide.md")
            .await
            .unwrap();
        assert_eq!(file.content, GUIDE.as_bytes());
        assert_eq!(file.content_type, "text/markdown; charset=utf-8");
        let file = read_presented_file(repository, &fixture.tools.db, "src/main.rs")
            .await
            .unwrap();
        assert_eq!(file.content_type, "text/plain; charset=utf-8");
        assert!(matches!(
            read_presented_file(repository, &fixture.tools.db, "docs").await,
            Err(AppError::Unprocessable(ErrorCode::FileUnavailable, _))
        ));

        // Documents are the original files, not the converted Markdown.
        let pdf = b"%PDF-1.4\n%%EOF\n";
        let fixture = Fixture::new(&[("report.pdf", pdf)]);
        let repository = &fixture.tools.repositories()[0];
        let file = read_presented_file(repository, &fixture.tools.db, "report.pdf")
            .await
            .unwrap();
        assert_eq!(file.content, pdf);
        assert_eq!(file.content_type, "application/pdf");
    }
}
