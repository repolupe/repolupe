//! [`READ_FILE`]: a text file with line numbers, or the Markdown converted from a document.

use super::support::{
    Output, Text, file_path_schema, normalize_path, parse_args, read_text, repository_schema,
};
use super::{Call, Invocation, OUTLINE, READ_FILE, RepositoryTools, ToolError};
use crate::service::llm::ToolDefinition;
use serde::Deserialize;
use serde_json::{Value, json};

pub(super) const DEFAULT_READ_LINES: usize = 500;
pub(super) const MAX_READ_LINES: usize = 2_000;
/// Longer lines are cut.
const MAX_LINE_CHARS: usize = 2_000;

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: READ_FILE.to_string(),
        description: format!(
            "Read a text file, with line numbers. Returns up to {DEFAULT_READ_LINES} \
            lines by default. PDFs are returned as Markdown converted from them, with \
            the text of scanned pages recognized by OCR. For long Markdown files, call \
            {OUTLINE} first and read only the sections you need."
        ),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": repository_schema(tools),
                "path": file_path_schema(),
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
            "required": ["repository", "path"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    path: String,
    offset: Option<usize>,
    limit: Option<usize>,
}

pub(super) struct Args {
    path: String,
    offset: Option<usize>,
    limit: Option<usize>,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(READ_FILE, input)?;
    let args = Args {
        path: normalize_path(&input.path)?,
        offset: input.offset,
        limit: input.limit,
    };
    Ok((input.repository, Call::ReadFile(args)))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let path = args.path.as_str();
    let text = read_text(invocation.target()?, invocation.db, path).await?;
    format_lines(path, text, args.offset, args.limit)
}

/// Lines `offset` (from 1) to `offset + limit` of `text`, the content of the file `name`, with
/// line numbers.
pub(super) fn format_lines(
    name: &str,
    Text { content, note }: Text,
    offset: Option<usize>,
    limit: Option<usize>,
) -> Result<String, ToolError> {
    let lines: Vec<&str> = content.lines().collect();
    if lines.is_empty() {
        return Ok("(empty file)".to_string());
    }
    let total = lines.len();
    let offset = offset.unwrap_or(1).max(1);
    if offset > total {
        return Err(ToolError::Invalid(format!(
            "`offset` {offset} is past the end of `{name}`, which has {total} lines."
        )));
    }
    let limit = limit.unwrap_or(DEFAULT_READ_LINES).clamp(1, MAX_READ_LINES);
    let end = (offset - 1 + limit).min(total);
    let width = end.to_string().len();

    let mut output = Output::default();
    let mut last = offset - 1;
    for (i, line) in lines[offset - 1..end].iter().enumerate() {
        let number = offset + i;
        let chars = line.chars().count();
        let line = if chars > MAX_LINE_CHARS {
            let start: String = line.chars().take(MAX_LINE_CHARS).collect();
            format!("{start}… [line cut, {chars} characters]")
        } else {
            line.to_string()
        };
        if !output.line(&format!("{number:>width$}\t{line}")) {
            break;
        }
        last = number;
    }
    if last < total {
        output.note(&format!(
            "[Lines {offset}-{last} of {total}. Continue with offset={}.]",
            last + 1
        ));
    }
    Ok(match note {
        Some(note) => format!("{note}\n\n{}", output.text),
        None => output.text,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::tools::support::fixture::docs;

    #[tokio::test]
    async fn reads_files() {
        let fixture = docs();
        let readme = fixture
            .ok(
                READ_FILE,
                json!({"repository": "docs", "path": "README.md"}),
            )
            .await;
        assert_eq!(
            readme,
            "1\t# Project\n2\t\n3\tSee docs/guide.md for the API key."
        );
        let part = fixture
            .ok(
                READ_FILE,
                json!({"repository": "docs", "path": "docs/guide.md", "offset": 9, "limit": 3}),
            )
            .await;
        assert_eq!(
            part,
            " 9\t### macOS\n10\t\n11\tUse Homebrew.\n\n[Lines 9-11 of 15. Continue with offset=12.]"
        );
        let past_end = fixture
            .error(
                READ_FILE,
                json!({"repository": "docs", "path": "README.md", "offset": 4}),
            )
            .await;
        assert_eq!(
            past_end,
            "`offset` 4 is past the end of `README.md`, which has 3 lines."
        );
    }

    #[tokio::test]
    async fn explains_unreadable_paths() {
        let fixture = docs();
        let read = |path: &'static str| fixture.error(READ_FILE, json!({"path": path}));
        assert_eq!(
            read("docs").await,
            "`docs` is a directory. Use list_files to see its files."
        );
        assert_eq!(
            read("logo.png").await,
            "`logo.png` is a binary file and can't be shown."
        );
        // The sync downloads no LFS objects of binary files like videos.
        assert_eq!(
            read("demo.mp4").await,
            "`demo.mp4` can't be shown, its content was not downloaded."
        );
        assert_eq!(
            read("docs/install.md").await,
            "File or directory not found: `docs/install.md`. Use list_files to see the files."
        );
        assert_eq!(
            read("docs/Guide").await,
            "File or directory not found: `docs/Guide`. Similar paths: `docs/guide.md`."
        );
        assert_eq!(read("../etc/passwd").await, "Paths must not contain `..`.");
    }
}
