//! [`LIST_FILES`]: the files of a repository, or the first level of a directory with too many to
//! list.

use super::support::{
    Output, glob, glob_schema, non_empty, normalize_path, not_found, parent_dirs, parse_args,
    plural, repository_schema,
};
use super::{Call, Invocation, LIST_FILES, RepositoryTools, ToolError};
use crate::service::llm::ToolDefinition;
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

const MAX_LIST_FILES: usize = 500;

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    ToolDefinition {
        name: LIST_FILES.to_string(),
        description: "List the files in a repository. The paths are relative to the \
            repository root and can be passed to the other tools. Use it to get an \
            overview of a repository or to find files by name."
            .to_string(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "repository": repository_schema(tools),
                "path": {
                    "type": "string",
                    "description": "Directory to list, relative to the repository \
                        root. Lists the whole repository by default.",
                },
                "glob": glob_schema(),
            },
            "required": ["repository"],
        }),
    }
}

#[derive(Deserialize)]
struct Input {
    repository: Option<String>,
    path: Option<String>,
    glob: Option<String>,
}

pub(super) struct Args {
    path: String,
    glob: Option<String>,
}

pub(super) fn parse(input: &Value) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(LIST_FILES, input)?;
    let args = Args {
        path: normalize_path(input.path.as_deref().unwrap_or(""))?,
        glob: non_empty(input.glob),
    };
    Ok((input.repository, Call::ListFiles(args)))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let path = args.path.as_str();
    let glob = args.glob.as_deref();
    let blobs = invocation.target()?.snapshot.files().await?;
    let prefix = if path.is_empty() {
        String::new()
    } else {
        format!("{path}/")
    };
    let in_dir: Vec<_> = blobs
        .iter()
        .filter_map(|blob| Some((blob, blob.path.strip_prefix(&prefix)?)))
        .collect();
    if in_dir.is_empty() {
        if let Some(blob) = blobs.iter().find(|blob| blob.path == path) {
            return Ok(blob.path.clone());
        }
        let dirs = blobs
            .iter()
            .flat_map(|blob| parent_dirs(&blob.path))
            .collect::<BTreeSet<_>>();
        return Err(not_found("Directory", path, dirs.into_iter()));
    }

    let pattern = glob.map(glob::anchored);
    let files: Vec<_> = in_dir
        .into_iter()
        .filter(|(_, relative)| {
            pattern
                .as_deref()
                .is_none_or(|pattern| glob::matches(pattern, relative))
        })
        .collect();
    let location = if path.is_empty() {
        "the repository".to_string()
    } else {
        format!("`{path}`")
    };
    if files.is_empty() {
        return Ok(format!(
            "No files in {location} match `{}`.",
            glob.unwrap_or_default()
        ));
    }

    let mut output = Output::default();
    if files.len() <= MAX_LIST_FILES {
        for (blob, _) in &files {
            if !output.line(&blob.path) {
                break;
            }
        }
        if output.truncated {
            output.note(&format!(
                "[Output cut, {} files in total. Narrow down with `path` or `glob`.]",
                files.len()
            ));
        }
        return Ok(output.text);
    }

    // Too many to list, so summarize the first level instead.
    let mut entries: BTreeMap<String, (usize, bool)> = BTreeMap::new();
    for (blob, relative) in &files {
        let (name, is_dir) = match relative.split_once('/') {
            Some((dir, _)) => (format!("{prefix}{dir}/"), true),
            None => (blob.path.clone(), false),
        };
        entries.entry(name).or_insert((0, is_dir)).0 += 1;
    }
    output.line(&format!(
        "{} files match in {location}, too many to list. Narrow down with `path` or `glob`. \
        The entries of {location}:",
        files.len()
    ));
    for (name, (count, is_dir)) in &entries {
        let line = if *is_dir {
            format!("{name} ({})", plural(*count, "file"))
        } else {
            name.clone()
        };
        if !output.line(&line) {
            output.note("[Output cut.]");
            break;
        }
    }
    Ok(output.text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::tools::support::fixture::{Fixture, docs};

    #[tokio::test]
    async fn lists_files() {
        let fixture = docs();
        let all = fixture.ok(LIST_FILES, json!({"repository": "docs"})).await;
        assert_eq!(
            all,
            "README.md\ndemo.mp4\ndocs/faq/limits.md\ndocs/guide.md\nlogo.png\nslides.pdf\nsrc/main.rs"
        );
        let markdown = fixture
            .ok(LIST_FILES, json!({"repository": "docs", "glob": "*.md"}))
            .await;
        assert_eq!(markdown, "README.md\ndocs/faq/limits.md\ndocs/guide.md");
        let in_docs = fixture
            .ok(
                LIST_FILES,
                json!({"repository": "docs", "path": "./docs/", "glob": "*/*.md"}),
            )
            .await;
        assert_eq!(in_docs, "docs/faq/limits.md");
        let none = fixture
            .ok(LIST_FILES, json!({"repository": "docs", "glob": "*.txt"}))
            .await;
        assert_eq!(none, "No files in the repository match `*.txt`.");
        let missing = fixture
            .error(
                LIST_FILES,
                json!({"repository": "docs", "path": "project/faq"}),
            )
            .await;
        assert_eq!(
            missing,
            "Directory not found: `project/faq`. Similar paths: `docs/faq`."
        );
    }

    #[tokio::test]
    async fn summarizes_too_many_files() {
        let names: Vec<String> = (0..=MAX_LIST_FILES)
            .map(|i| format!("many/{i}.md"))
            .collect();
        let mut files: Vec<(&str, &[u8])> = names.iter().map(|n| (n.as_str(), &b"x"[..])).collect();
        files.push(("README.md", b"readme"));
        let fixture = Fixture::new(&files);
        let output = fixture.ok(LIST_FILES, json!({})).await;
        assert_eq!(
            output,
            "502 files match in the repository, too many to list. Narrow down with `path` or `glob`. The entries of the repository:\nREADME.md\nmany/ (501 files)"
        );
    }
}
