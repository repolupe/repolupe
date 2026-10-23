//! [`OUTLINE`]: the headings of a Markdown file with the line range of each section.

use super::support::{
    Output, file_path_schema, is_markdown, markdown, normalize_path, parse_args, read_text,
    repository_schema, window,
};
use super::{Call, GREP, Invocation, OUTLINE, READ_FILE, RepositoryTools, ToolError};
use crate::service::extraction;
use crate::service::llm::ToolDefinition;
use serde::Deserialize;
use serde_json::{Value, json};

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: OUTLINE.to_string(),
        description: format!(
            "List the headings of a Markdown file with the line range of each \
            section, to read only the relevant sections with {READ_FILE}. PDFs are not \
            supported, read them with {READ_FILE}."
        ),
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
    let input: Input = parse_args(OUTLINE, input)?;
    let args = Args {
        path: normalize_path(&input.path)?,
    };
    Ok((input.repository, Call::Outline(args)))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let path = args.path.as_str();
    // Headings in Markdown converted from PDFs are mostly noise, e.g. numbers of a form.
    if extraction::is_document(path) {
        return Err(ToolError::Invalid(format!(
            "{OUTLINE} does not support PDFs. Use {READ_FILE} for `{path}`."
        )));
    }
    if !is_markdown(path) {
        return Err(ToolError::Invalid(format!(
            "{OUTLINE} only supports Markdown files (.md, .markdown, .mdx). Use {READ_FILE} or \
            {GREP} for `{path}`."
        )));
    }
    let content = read_text(invocation.target()?, invocation.db, path)
        .await?
        .content;
    let total = content.lines().count();
    let headings = markdown::headings(&content);
    if headings.is_empty() {
        return Ok(format!(
            "`{path}` has no headings ({total} lines). Use {READ_FILE} to read it."
        ));
    }

    let width = total.to_string().len();
    let mut output = Output::default();
    output.line(&format!("`{path}`, {total} lines:"));
    for (i, heading) in headings.iter().enumerate() {
        // Up to the next heading of the same or a higher level.
        let end = headings[i + 1..]
            .iter()
            .find(|next| next.level <= heading.level)
            .map_or(total, |next| next.line - 1);
        let range = format!("{}-{}", heading.line, end);
        let line = format!(
            "{range:>width$}  {} {}",
            "#".repeat(heading.level),
            window(&heading.text, 0, 200),
            width = width * 2 + 1
        );
        if !output.line(&line) {
            output.note(&format!(
                "[Output cut, {} headings in total.]",
                headings.len()
            ));
            break;
        }
    }
    Ok(output.text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::tools::support::fixture::docs;

    #[tokio::test]
    async fn outlines_markdown() {
        let fixture = docs();
        let output = fixture.ok(OUTLINE, json!({"path": "docs/guide.md"})).await;
        assert_eq!(
            output,
            "`docs/guide.md`, 15 lines:\n 1-15  # Guide\n 5-12  ## Install\n 9-12  ### macOS\n13-15  ## Usage"
        );
        let setext = fixture
            .ok(OUTLINE, json!({"path": "docs/faq/limits.md"}))
            .await;
        assert_eq!(setext, "`docs/faq/limits.md`, 4 lines:\n1-4  # Rate limits");
        let not_markdown = fixture.error(OUTLINE, json!({"path": "src/main.rs"})).await;
        assert_eq!(
            not_markdown,
            "outline only supports Markdown files (.md, .markdown, .mdx). Use read_file or grep for `src/main.rs`."
        );
        let pdf = fixture
            .error(OUTLINE, json!({"path": "docs/report.pdf"}))
            .await;
        assert_eq!(
            pdf,
            "outline does not support PDFs. Use read_file for `docs/report.pdf`."
        );
    }
}
