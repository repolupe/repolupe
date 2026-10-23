//! [`GREP`]: searches the text files of a repository with a regular expression, see
//! [`Snapshot::grep`](crate::service::mirror::Snapshot::grep).

use super::support::{
    Output, glob, glob_schema, missing_path, non_empty, normalize_path, parse_args, plural,
    repository_schema, window,
};
use super::{Call, GREP, Invocation, READ_FILE, RepositoryTools, ToolError};
use crate::repository;
use crate::service::extraction;
use crate::service::llm::ToolDefinition;
use crate::service::mirror::{GrepFile, GrepOptions, GrepOutput, PathEntry, TreeBlob};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

const MAX_GREP_MATCHES: usize = 200;
const MAX_GREP_CONTEXT: u32 = 10;
/// Lines in grep results are cut to this many characters around the match.
const MAX_GREP_LINE_CHARS: usize = 300;
/// Matching lines collected at most. Matches after them are not counted.
const MAX_GREP_OUTPUT_BYTES: usize = 4 * 1024 * 1024;

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: GREP.to_string(),
        description: format!(
            "Search the contents of the text files in a repository with a regular \
            expression. Returns the matching lines with line numbers, grouped by \
            file, at most {MAX_GREP_MATCHES}. Use it to find where a topic is covered, \
            then read the surrounding section with {READ_FILE}. PDFs are searched \
            in the text converted from them, with the same line numbers as in \
            {READ_FILE}."
        ),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": repository_schema(tools),
                "pattern": {
                    "type": "string",
                    "description": "Perl-compatible regular expression, e.g. \
                        `rate.?limit` or `\\bAPI key\\b`.",
                },
                "path": {
                    "type": "string",
                    "description": "File or directory to search, relative to the \
                        repository root. Searches the whole repository by default.",
                },
                "glob": glob_schema(),
                "ignore_case": {
                    "type": "boolean",
                    "description": "Match case-insensitively, false by default.",
                },
                "context": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": MAX_GREP_CONTEXT,
                    "description": "Lines to show before and after each match, \
                        0 by default.",
                },
            },
            "required": ["repository", "pattern"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    pattern: String,
    path: Option<String>,
    glob: Option<String>,
    ignore_case: Option<bool>,
    context: Option<u32>,
}

pub(super) struct Args {
    pattern: String,
    path: String,
    glob: Option<String>,
    ignore_case: bool,
    context: u32,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(GREP, input)?;
    if input.pattern.is_empty() {
        return Err("`pattern` must not be empty.".to_string());
    }
    let args = Args {
        pattern: input.pattern,
        path: normalize_path(input.path.as_deref().unwrap_or(""))?,
        glob: non_empty(input.glob),
        ignore_case: input.ignore_case.unwrap_or(false),
        context: input.context.unwrap_or(0).min(MAX_GREP_CONTEXT),
    };
    Ok((input.repository, Call::Grep(args)))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let repository = invocation.target()?;
    let path = args.path.as_str();
    let blobs = repository.snapshot.files().await?;
    let pattern_glob = args.glob.as_deref().map(glob::anchored);
    // `path` is a file or a directory, `glob` relative to it, like in `list_files`.
    let candidates: Vec<TreeBlob> = blobs
        .into_iter()
        .filter(|blob| {
            let relative = if path.is_empty() {
                Some(blob.path.as_str())
            } else if blob.path == path {
                blob.path.rsplit('/').next()
            } else {
                blob.path
                    .strip_prefix(path)
                    .and_then(|rest| rest.strip_prefix('/'))
            };
            relative.is_some_and(|relative| {
                pattern_glob
                    .as_deref()
                    .is_none_or(|pattern| glob::matches(pattern, relative))
            })
        })
        .collect();

    // Documents are searched in the Markdown converted from them, which `read_file` reads.
    let document_oids: Vec<&str> = candidates
        .iter()
        .filter(|blob| extraction::is_document(&blob.path))
        .map(|blob| blob.oid.as_str())
        .collect();
    let markdowns: HashMap<String, (Arc<str>, bool)> = if document_oids.is_empty() {
        HashMap::new()
    } else {
        repository::document::get_markdowns(invocation.db, &document_oids)
            .await?
            .into_iter()
            .map(|e| (e.blob_oid, (e.markdown.into(), e.ocr)))
            .collect()
    };
    // Documents not converted (yet), and those recognized with OCR.
    let mut unconverted = 0;
    let mut ocr = BTreeSet::new();
    let files: Vec<GrepFile> = candidates
        .into_iter()
        .filter_map(|blob| {
            if !extraction::is_document(&blob.path) {
                return Some(GrepFile::Blob(blob));
            }
            let Some((markdown, recognized)) = markdowns.get(&blob.oid) else {
                unconverted += 1;
                return None;
            };
            if *recognized {
                ocr.insert(blob.path.clone());
            }
            Some(GrepFile::Text {
                path: blob.path,
                text: markdown.clone(),
            })
        })
        .collect();
    let unconverted_note = (unconverted > 0).then(|| {
        format!(
            "[{} not searched, {} not converted to text (yet). {READ_FILE} tells why.]",
            plural(unconverted, "document"),
            if unconverted == 1 {
                "it was"
            } else {
                "they were"
            }
        )
    });

    let options = GrepOptions {
        pattern: &args.pattern,
        ignore_case: args.ignore_case,
        context: args.context,
    };
    let (groups, truncated) = match repository
        .snapshot
        .grep(files, &options, MAX_GREP_OUTPUT_BYTES)
        .await?
    {
        GrepOutput::Groups { groups, truncated } => (groups, truncated),
        GrepOutput::Rejected(message) => {
            return Err(ToolError::Invalid(format!("Invalid search: {message}")));
        }
    };

    if groups.is_empty() {
        if !path.is_empty() && matches!(repository.snapshot.entry(path).await?, PathEntry::Missing)
        {
            return Err(missing_path(repository, path).await?);
        }
        return Ok(match unconverted_note {
            Some(note) => format!("No matches.\n\n{note}"),
            None => "No matches.".to_string(),
        });
    }

    let total: usize = groups.iter().map(|g| g.matches()).sum();
    let files = groups
        .iter()
        .map(|g| &g.path)
        .collect::<BTreeSet<_>>()
        .len();
    let mut output = Output::default();
    output.line(&format!(
        "{}{} in {}:",
        if truncated { "More than " } else { "" },
        plural(total, "matching line"),
        plural(files, "file")
    ));
    let mut shown = 0;
    let mut previous_path = None;
    'groups: for group in &groups {
        if shown >= MAX_GREP_MATCHES {
            break;
        }
        if previous_path == Some(&group.path) {
            output.line("--");
        } else {
            output.line("");
            output.line(&group.path);
            previous_path = Some(&group.path);
        }
        for line in &group.lines {
            let text = match line.column {
                Some(column) => {
                    // The column is a 1-based byte offset.
                    let byte = (column - 1).min(line.text.len());
                    let byte = (0..=byte)
                        .rev()
                        .find(|&b| line.text.is_char_boundary(b))
                        .unwrap_or(0);
                    let char = line.text[..byte].chars().count();
                    let start = char.saturating_sub(MAX_GREP_LINE_CHARS / 3);
                    window(&line.text, start, MAX_GREP_LINE_CHARS)
                }
                None => window(&line.text, 0, MAX_GREP_LINE_CHARS),
            };
            let separator = if line.column.is_some() { ':' } else { '-' };
            if !output.line(&format!("{}{separator}{text}", line.number)) {
                break 'groups;
            }
            if line.column.is_some() {
                shown += 1;
            }
        }
    }
    if shown < total || truncated || output.truncated {
        output.note(&format!(
            "[Showing {shown} matching lines. Narrow down with a more specific `pattern`, \
            `path` or `glob`.]"
        ));
    }
    let recognized: BTreeSet<_> = groups
        .iter()
        .filter(|g| ocr.contains(&g.path))
        .map(|g| format!("`{}`", g.path))
        .collect();
    if !recognized.is_empty() {
        output.note(&format!(
            "[Scanned pages of {} were recognized with OCR, their text may contain errors.]",
            recognized.into_iter().collect::<Vec<_>>().join(", ")
        ));
    }
    if let Some(note) = unconverted_note {
        output.note(&note);
    }
    Ok(output.text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::document_extraction::DocumentExtraction;
    use crate::service::tools::support::fixture::{Fixture, docs};

    #[tokio::test]
    async fn greps() {
        let fixture = docs();
        // `slides.pdf` has no extraction.
        let unconverted = "\n\n[1 document not searched, it was not converted to text (yet). read_file tells why.]";
        let output = fixture
            .ok(
                GREP,
                json!({"repository": "docs", "pattern": "API key", "ignore_case": true}),
            )
            .await;
        assert_eq!(
            output,
            format!(
                "2 matching lines in 2 files:\n\nREADME.md\n3:See docs/guide.md for the API key.\n\ndocs/guide.md\n15:Call the API with your API key.{unconverted}"
            )
        );
        let markdown = fixture
            .ok(
                GREP,
                json!({"pattern": "\\bapi\\b", "path": "docs", "glob": "*.md", "context": 1}),
            )
            .await;
        assert_eq!(
            markdown,
            "1 matching line in 1 file:\n\ndocs/faq/limits.md\n3-\n4:The api allows 10 requests."
        );
        let groups = fixture
            .ok(GREP, json!({"pattern": "^#+ ", "path": "docs/guide.md"}))
            .await;
        assert_eq!(
            groups,
            "4 matching lines in 1 file:\n\ndocs/guide.md\n1:# Guide\n5:## Install\n9:### macOS\n13:## Usage"
        );
        let separated = fixture
            .ok(
                GREP,
                json!({"pattern": "Install|Usage", "path": "docs/guide.md", "context": 1}),
            )
            .await;
        assert_eq!(
            separated,
            "2 matching lines in 1 file:\n\ndocs/guide.md\n4-\n5:## Install\n6-\n--\n12-\n13:## Usage\n14-"
        );
        assert_eq!(
            fixture.ok(GREP, json!({"pattern": "nothing here"})).await,
            format!("No matches.{unconverted}")
        );
        // LFS pointers are not the files' content, which was not downloaded.
        assert_eq!(
            fixture.ok(GREP, json!({"pattern": "sha256"})).await,
            format!("No matches.{unconverted}")
        );
        assert_eq!(
            fixture
                .error(GREP, json!({"pattern": "x", "path": "nope"}))
                .await,
            "File or directory not found: `nope`. Use list_files to see the files."
        );
        let invalid = fixture.error(GREP, json!({"pattern": "foo("})).await;
        assert!(invalid.starts_with("Invalid search: "), "{invalid}");
    }

    #[tokio::test]
    async fn greps_the_markdown_of_documents() {
        let fixture = Fixture::new(&[
            ("a.md", b"The limit is 10.\n"),
            ("failed.pdf", b"%PDF-1.7 failed"),
            ("manual.pdf", b"%PDF-1.7 manual"),
            ("new.pdf", b"%PDF-1.7 new"),
            ("scan.pdf", b"%PDF-1.7 scan"),
            ("z.md", b"No limit here.\n"),
        ]);
        let markdown = "# Manual\n\n## Limits\n\nThe limit is 42 requests.\n".to_string();
        fixture
            .extract(
                "manual.pdf",
                DocumentExtraction::Completed {
                    markdown,
                    ocr: false,
                },
            )
            .await;
        fixture
            .extract(
                "scan.pdf",
                DocumentExtraction::Completed {
                    markdown: "Limit: 7\n".to_string(),
                    ocr: true,
                },
            )
            .await;
        let error = "The file could not be converted".to_string();
        fixture
            .extract("failed.pdf", DocumentExtraction::Failed { error })
            .await;

        let output = fixture
            .ok(GREP, json!({"pattern": "limit", "ignore_case": true}))
            .await;
        assert_eq!(
            output,
            "5 matching lines in 4 files:\n\na.md\n1:The limit is 10.\n\nmanual.pdf\n\
            3:## Limits\n5:The limit is 42 requests.\n\nscan.pdf\n1:Limit: 7\n\nz.md\n\
            1:No limit here.\n\n[Scanned pages of `scan.pdf` were recognized with OCR, their \
            text may contain errors.]\n\n[2 documents not searched, they were not converted \
            to text (yet). read_file tells why.]"
        );
        // Only documents among the files searched count.
        assert_eq!(
            fixture
                .ok(GREP, json!({"pattern": "42", "path": "manual.pdf"}))
                .await,
            "1 matching line in 1 file:\n\nmanual.pdf\n5:The limit is 42 requests."
        );
        assert_eq!(
            fixture
                .ok(GREP, json!({"pattern": "42", "glob": "*.md"}))
                .await,
            "No matches."
        );
        assert_eq!(
            fixture
                .ok(GREP, json!({"pattern": "x", "path": "new.pdf"}))
                .await,
            "No matches.\n\n[1 document not searched, it was not converted to text (yet). \
            read_file tells why.]"
        );
    }

    #[tokio::test]
    async fn cuts_long_grep_lines_around_the_match() {
        let line = format!("{}needle{}\n", "a".repeat(1000), "b".repeat(1000));
        let fixture = Fixture::new(&[("long.md", line.as_bytes())]);
        let output = fixture.ok(GREP, json!({"pattern": "needle"})).await;
        let shown = output.lines().last().unwrap();
        assert!(shown.starts_with("1:…a"), "{shown}");
        assert!(shown.contains("needle"));
        assert!(shown.ends_with("b…"));
        assert_eq!(shown.chars().count(), "1:".len() + MAX_GREP_LINE_CHARS + 2);
    }
}
