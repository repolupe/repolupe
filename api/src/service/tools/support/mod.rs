//! What the tools in [`super`] share: their common arguments, reading files, paths, and the
//! limits of their output.

pub(super) mod commit;
pub(super) mod diff;
#[cfg(test)]
pub(super) mod fixture;
pub(super) mod glob;
pub(super) mod markdown;
pub(super) mod patch;
pub(super) mod results;

use super::{LIST_FILES, RepositoryTools, ToolError, ToolOutput, ToolRepository};
use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::model::document_extraction::DocumentExtraction;
use crate::repository;
use crate::service::extraction::{self, MAX_DOCUMENT_SIZE, page_marker};
use crate::service::image::{self, MAX_IMAGE_BYTES};
use crate::service::mirror::{Content, PathEntry};
use crate::service::pdf;
use crate::util::path::has_extension;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use std::collections::BTreeSet;

/// Longer outputs are cut, roughly 10k tokens.
pub(super) const MAX_OUTPUT_CHARS: usize = 40_000;
/// Larger files are not read.
pub(super) const MAX_READ_BYTES: u64 = 10 * 1024 * 1024;
/// Bytes checked for NUL to detect binary files, like git does.
pub(super) const BINARY_CHECK_BYTES: usize = 8000;
const MAX_SUGGESTIONS: usize = 5;
const MARKDOWN_EXTENSIONS: &[&str] = &["md", "markdown", "mdx", "mdown", "mkd", "mkdn"];

/// The `repository` argument of the tools that read, one of the repositories in scope.
pub(super) fn repository_schema(tools: &RepositoryTools) -> Value {
    let names: Vec<&str> = tools.repositories.iter().map(|r| r.name.as_str()).collect();
    json!({
        "type": "string",
        "enum": names,
        "description": "The repository to read.",
    })
}

/// The `repository` argument of the tools that propose commits, one of the repositories the
/// model may change.
pub(super) fn writable_repository_schema(tools: &RepositoryTools, description: &str) -> Value {
    let names: Vec<&str> = tools
        .repositories
        .iter()
        .filter(|r| r.can_commit)
        .map(|r| r.name.as_str())
        .collect();
    json!({
        "type": "string",
        "enum": names,
        "description": description,
    })
}

pub(super) fn glob_schema() -> Value {
    json!({
        "type": "string",
        "description": "Only include files matching this glob, relative to `path`, e.g. \
            `*.md` or `guides/**/*.md`. Without `/` it matches file names at any depth.",
    })
}

pub(super) fn file_path_schema() -> Value {
    json!({
        "type": "string",
        "description": "Path of the file, relative to the repository root.",
    })
}

/// The `page` argument of the tools that read, which shows a page of a PDF instead of its
/// text.
pub(super) fn page_schema() -> Value {
    json!({
        "type": "integer",
        "minimum": 1,
        "description": "Only for PDFs: the number of a page to return as an image for you to \
            look at, instead of the text. One page per call.",
    })
}

/// For the descriptions of the tools that read: what they return for PDFs.
pub(super) fn pdf_description() -> String {
    format!(
        "PDFs are returned as Markdown converted from them, with the text of scanned pages \
        recognized by OCR and a `{}` line where each page starts. When the text is not \
        enough, e.g. for a figure, a form or a table it garbles, or to check recognized text, \
        pass `page` to look at that page instead.",
        page_marker("N")
    )
}

/// The `page` argument as the number of a page.
pub(super) fn parse_page(page: Option<usize>) -> Result<Option<usize>, String> {
    match page {
        Some(0) => Err("`page` starts at 1.".to_string()),
        page => Ok(page),
    }
}

pub(super) fn parse_args<T: DeserializeOwned>(tool: &str, input: &Value) -> Result<T, String> {
    T::deserialize(input).map_err(|e| format!("Invalid arguments for {tool}: {e}"))
}

pub(super) fn non_empty(value: Option<String>) -> Option<String> {
    value
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// Relative to the repository root and without `.` or empty segments, empty for the root.
pub(super) fn normalize_path(path: &str) -> Result<String, String> {
    if path.contains(['\n', '\0']) {
        return Err("Paths must not contain line breaks.".to_string());
    }
    let mut segments = Vec::new();
    for segment in path.trim().split('/') {
        match segment {
            "" | "." => {}
            ".." => return Err("Paths must not contain `..`.".to_string()),
            segment => segments.push(segment),
        }
    }
    Ok(segments.join("/"))
}

pub(super) fn is_markdown(path: &str) -> bool {
    has_extension(path, MARKDOWN_EXTENSIONS)
}

/// A text file, or the Markdown converted from a document.
pub(super) struct Text {
    pub(super) content: String,
    /// What the model should know about the content, e.g. that it was recognized with OCR.
    pub(super) note: Option<String>,
}

/// Reads the text file at `path`, or the Markdown converted from the document at `path`.
/// Binary files and missing paths are errors for the model.
pub(super) async fn read_text(
    repository: &ToolRepository,
    db: &DatabasePool,
    path: &str,
) -> Result<Text, ToolError> {
    let oid = file_oid(repository, path).await?;
    if extraction::is_document(path) {
        return read_document(db, path, &oid).await;
    }
    let content = read_blob(repository, path, &oid, MAX_READ_BYTES).await?;
    decode_text(path, &content)
}

/// Reads the image at `path` for the model to look at, see [`image::is_image`]. Missing paths
/// and files that are no images are errors for the model.
pub(super) async fn read_image(
    repository: &ToolRepository,
    path: &str,
) -> Result<ToolOutput, ToolError> {
    let oid = file_oid(repository, path).await?;
    let content = read_blob(repository, path, &oid, MAX_IMAGE_BYTES).await?;
    image_output(path, content).await
}

/// `content` of the image file `name` for the model to look at.
pub(super) async fn image_output(name: &str, content: Vec<u8>) -> Result<ToolOutput, ToolError> {
    // Decoding and scaling a photo takes a while
    let prepared = tokio::task::spawn_blocking(move || image::prepare(&content))
        .await
        .map_err(|e| AppError::InternalServerError(format!("Preparing an image failed: {e}")))?;
    match prepared {
        Ok(prepared) => Ok(ToolOutput {
            image: Some(prepared.image),
            ..ToolOutput::text(format!("`{name}`: {}.", prepared.description))
        }),
        Err(e) => Err(ToolError::Invalid(format!("`{name}` can't be shown. {e}."))),
    }
}

/// Renders page `page` of the PDF at `path` for the model to look at. Missing paths and files
/// that are no PDFs are errors for the model.
pub(super) async fn read_page(
    repository: &ToolRepository,
    path: &str,
    page: usize,
) -> Result<ToolOutput, ToolError> {
    let oid = file_oid(repository, path).await?;
    if extraction::mime_type(path) != Some(pdf::MIME_TYPE) {
        return Err(not_a_pdf(path));
    }
    let content = read_blob(repository, path, &oid, MAX_DOCUMENT_SIZE).await?;
    page_output(path, content, page).await
}

/// Page `page` of `content`, the PDF file `name`, for the model to look at.
pub(super) async fn page_output(
    name: &str,
    content: Vec<u8>,
    page: usize,
) -> Result<ToolOutput, ToolError> {
    match pdf::render_page(content, page).await {
        Ok(rendered) => Ok(ToolOutput {
            image: Some(rendered.image),
            ..ToolOutput::text(format!("`{name}`: page {page} of {}.", rendered.pages))
        }),
        Err(e) => Err(ToolError::Invalid(format!(
            "Page {page} of `{name}` can't be shown. {e}."
        ))),
    }
}

/// The error for a `page` of the file `name`, which is not a PDF.
pub(super) fn not_a_pdf(name: &str) -> ToolError {
    ToolError::Invalid(format!(
        "`{name}` is not a PDF, so it has no pages to show. Read it without `page`."
    ))
}

/// The blob of the file at `path`. Directories and missing paths are errors for the model.
async fn file_oid(repository: &ToolRepository, path: &str) -> Result<String, ToolError> {
    if path.is_empty() {
        return Err(ToolError::Invalid(format!(
            "`path` must be a file. Use {LIST_FILES} to see the files."
        )));
    }
    match repository.snapshot.entry(path).await? {
        PathEntry::Blob { oid, .. } => Ok(oid),
        PathEntry::Tree => Err(ToolError::Invalid(format!(
            "`{path}` is a directory. Use {LIST_FILES} to see its files."
        ))),
        PathEntry::Other => Err(ToolError::Invalid(format!(
            "`{path}` is not a file, e.g. a submodule."
        ))),
        PathEntry::Missing => Err(missing_path(repository, path).await?),
    }
}

/// The content of the file at `path`, whose blob is `oid`. Files larger than `max_size` bytes
/// and files that were not downloaded are errors for the model.
async fn read_blob(
    repository: &ToolRepository,
    path: &str,
    oid: &str,
    max_size: u64,
) -> Result<Vec<u8>, ToolError> {
    match repository.snapshot.read(oid, max_size).await? {
        Content::Bytes(content) => Ok(content),
        Content::TooLarge(size) => Err(ToolError::Invalid(format!(
            "`{path}` is too large to read ({}).",
            format_size(size)
        ))),
        // Large and binary LFS files are not downloaded.
        Content::Unavailable => Err(ToolError::Invalid(format!(
            "`{path}` can't be shown, its content was not downloaded."
        ))),
    }
}

/// `content` of the file `name` as text, an error for the model if it is binary.
pub(super) fn decode_text(name: &str, content: &[u8]) -> Result<Text, ToolError> {
    if content[..content.len().min(BINARY_CHECK_BYTES)].contains(&0) {
        return Err(ToolError::Invalid(format!(
            "`{name}` is a binary file and can't be shown."
        )));
    }
    Ok(Text {
        content: String::from_utf8_lossy(content).into_owned(),
        note: None,
    })
}

/// The Markdown converted from the document at `path`, see [`extraction`].
async fn read_document(db: &DatabasePool, path: &str, oid: &str) -> Result<Text, ToolError> {
    match repository::document::get_extraction(db, oid).await? {
        Some(extraction) => document_text(path, extraction),
        // Queued, or its content could not be downloaded.
        None => Err(ToolError::Invalid(format!(
            "The text of `{path}` is not available yet, the file is waiting to be converted."
        ))),
    }
}

/// The Markdown of `extraction`, of the document `name`, or the reason there is none.
pub(super) fn document_text(name: &str, extraction: DocumentExtraction) -> Result<Text, ToolError> {
    match extraction {
        DocumentExtraction::Completed { markdown, ocr } => {
            if markdown.len() as u64 > MAX_READ_BYTES {
                return Err(ToolError::Invalid(format!(
                    "The text of `{name}` is too large to read ({}).",
                    format_size(markdown.len() as u64)
                )));
            }
            let note = ocr.then(|| {
                format!(
                    "[Scanned pages of `{name}` were recognized with OCR, their text may \
                    contain errors.]"
                )
            });
            Ok(Text {
                content: markdown,
                note,
            })
        }
        DocumentExtraction::Failed { error } => Err(ToolError::Invalid(format!(
            "`{name}` could not be converted to text. {error}."
        ))),
    }
}

/// The error for a file or directory that does not exist, with similar paths.
pub(super) async fn missing_path(
    repository: &ToolRepository,
    path: &str,
) -> Result<ToolError, AppError> {
    let blobs = repository.snapshot.files().await?;
    let paths: BTreeSet<&str> = blobs
        .iter()
        .flat_map(|blob| parent_dirs(&blob.path).chain([blob.path.as_str()]))
        .collect();
    Ok(not_found("File or directory", path, paths.into_iter()))
}

pub(super) fn not_found<'a>(
    kind: &str,
    path: &str,
    candidates: impl Iterator<Item = &'a str>,
) -> ToolError {
    let suggestions = similar_paths(path, candidates);
    let hint = if suggestions.is_empty() {
        format!("Use {LIST_FILES} to see the files.")
    } else {
        let suggestions: Vec<String> = suggestions.iter().map(|s| format!("`{s}`")).collect();
        format!("Similar paths: {}.", suggestions.join(", "))
    };
    ToolError::Invalid(format!("{kind} not found: `{path}`. {hint}"))
}

/// Paths with the same name, ignoring case and extension, or that `path` ends with, e.g. when
/// the model put the repository name in front.
fn similar_paths<'a>(path: &str, candidates: impl Iterator<Item = &'a str>) -> Vec<&'a str> {
    let path = path.to_lowercase();
    let stem = |path: &str| {
        let name = path.rsplit('/').next().unwrap_or(path);
        name.split_once('.')
            .map_or(name, |(stem, _)| stem)
            .to_string()
    };
    let wanted = stem(&path);
    candidates
        .filter(|candidate| {
            let candidate = candidate.to_lowercase();
            stem(&candidate) == wanted || path.ends_with(&format!("/{candidate}"))
        })
        .take(MAX_SUGGESTIONS)
        .collect()
}

/// `a/b/c.md` → `a`, `a/b`.
pub(super) fn parent_dirs(path: &str) -> impl Iterator<Item = &str> {
    path.match_indices('/').map(|(i, _)| &path[..i])
}

pub(super) fn plural(count: usize, noun: &str) -> String {
    if count == 1 {
        format!("1 {noun}")
    } else {
        format!("{count} {noun}s")
    }
}

pub(super) fn format_size(bytes: u64) -> String {
    match bytes {
        0..1024 => format!("{bytes} B"),
        1024..1_048_576 => format!("{:.1} KB", bytes as f64 / 1024.0),
        _ => format!("{:.1} MB", bytes as f64 / 1_048_576.0),
    }
}

/// At most `max` characters of `text` from character `start`, with `…` where it is cut.
pub(super) fn window(text: &str, start: usize, max: usize) -> String {
    let count = text.chars().count();
    if count <= max {
        return text.to_string();
    }
    let start = start.min(count - max);
    let mut window: String = text.chars().skip(start).take(max).collect();
    if start > 0 {
        window.insert(0, '…');
    }
    if start + max < count {
        window.push('…');
    }
    window
}

/// Tool output, limited to [`MAX_OUTPUT_CHARS`] by default.
pub(super) struct Output {
    pub(super) text: String,
    /// Of the lines, the notes don't count.
    pub(super) chars: usize,
    max_chars: usize,
    pub(super) truncated: bool,
}

impl Default for Output {
    fn default() -> Self {
        Self::with_limit(MAX_OUTPUT_CHARS)
    }
}

impl Output {
    /// For a part of the output, limited to `max_chars`.
    pub(super) fn with_limit(max_chars: usize) -> Self {
        Self {
            text: String::new(),
            chars: 0,
            max_chars,
            truncated: false,
        }
    }

    /// Appends a line, or returns `false` if it does not fit.
    pub(super) fn line(&mut self, line: &str) -> bool {
        let len = line.chars().count() + 1;
        if self.truncated || self.chars + len > self.max_chars {
            self.truncated = true;
            return false;
        }
        if !self.text.is_empty() {
            self.text.push('\n');
        }
        self.text.push_str(line);
        self.chars += len;
        true
    }

    /// Appends a line beyond the limit, to explain how the output was cut.
    pub(super) fn note(&mut self, note: &str) {
        self.text.push_str("\n\n");
        self.text.push_str(note);
    }
}
