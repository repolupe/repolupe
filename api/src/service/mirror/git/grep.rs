//! Searching blobs line by line, like `git grep -P -I`.

use super::{TreeBlob, blocking, failed, parse_oid};
use crate::config::error::AppError;
use fancy_regex::{Regex, RegexBuilder};
use gix::ThreadSafeRepository;
use std::borrow::Cow;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const TIMEOUT: Duration = Duration::from_secs(60);
const MAX_THREADS: usize = 8;
/// Bytes checked for NUL to detect binary files, like git does.
const BINARY_CHECK_BYTES: usize = 8000;
/// Counted per line on top of its text, for the line number and separators.
const LINE_OVERHEAD: usize = 16;

pub(crate) struct GrepOptions<'a> {
    /// A Perl-like regular expression, see [`fancy_regex`].
    pub(crate) pattern: &'a str,
    pub(crate) ignore_case: bool,
    /// Lines shown before and after each match.
    pub(crate) context: u32,
}

pub(crate) enum GrepOutput {
    /// Consecutive lines with matches and their context, in the order of the blobs. Only
    /// whole lines are kept if `truncated`.
    Groups {
        groups: Vec<GrepGroup>,
        truncated: bool,
    },
    /// The pattern is invalid or too complex, with the reason.
    Rejected(String),
}

/// A file to search.
pub(crate) enum GrepFile {
    /// A blob of the repository, with its content as the [`Resolve`] of [`grep`] returns it.
    Blob(TreeBlob),
    /// Text from elsewhere, e.g. the Markdown converted from a document.
    Text { path: String, text: Arc<str> },
}

/// Consecutive lines in one file.
pub(crate) struct GrepGroup {
    pub(crate) path: String,
    pub(crate) lines: Vec<GrepLine>,
}

pub(crate) struct GrepLine {
    /// 1-based.
    pub(crate) number: usize,
    /// The 1-based byte offset of the first match in `text`, `None` for context lines.
    pub(crate) column: Option<usize>,
    pub(crate) text: String,
}

impl GrepGroup {
    pub(crate) fn matches(&self) -> usize {
        self.lines.iter().filter(|l| l.column.is_some()).count()
    }
}

/// The content to search for a blob of the repository at the path, e.g. the file an LFS pointer
/// refers to, `None` to skip it. Called on the threads of [`grep`], so it may block.
pub(crate) type Resolve = for<'a> fn(&Path, &'a [u8]) -> Option<Cow<'a, [u8]>>;

/// Searches `files`, blobs with their content as `resolve` returns it, skipping binary ones.
/// Returns the matches in the order of `files`. Stops after about `max_output` bytes of matching
/// lines.
pub(crate) async fn grep(
    git_dir: &Path,
    files: Vec<GrepFile>,
    options: &GrepOptions<'_>,
    resolve: Resolve,
    max_output: usize,
) -> Result<GrepOutput, AppError> {
    let regex = match RegexBuilder::new(options.pattern)
        .case_insensitive(options.ignore_case)
        .build()
    {
        Ok(regex) => regex,
        Err(e) => return Ok(GrepOutput::Rejected(e.to_string())),
    };
    let context = options.context as usize;
    let git_dir = git_dir.to_path_buf();
    blocking(move || {
        let repo = ThreadSafeRepository::open_opts(&git_dir, gix::open::Options::isolated())
            .map_err(|e| failed("grep", e))?;
        let deadline = Instant::now() + TIMEOUT;
        let next = AtomicUsize::new(0);
        let output = AtomicUsize::new(0);
        let stop = AtomicBool::new(false);
        // By file, `None` until searched.
        let results: Vec<Mutex<Option<SearchResult>>> =
            files.iter().map(|_| Mutex::new(None)).collect();

        let threads = std::thread::available_parallelism()
            .map_or(1, |n| n.get())
            .min(MAX_THREADS)
            .min(files.len());
        std::thread::scope(|scope| {
            for _ in 0..threads {
                scope.spawn(|| {
                    let repo = repo.to_thread_local();
                    // Files are taken in order and each one taken is searched, so once the
                    // output is full, the files before the last one taken are all searched.
                    while !stop.load(Ordering::Relaxed) {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        let Some(file) = files.get(i) else {
                            break;
                        };
                        let result = if Instant::now() > deadline {
                            Err(GrepError::TimedOut)
                        } else {
                            search(&repo, &git_dir, file, &regex, context, resolve)
                        };
                        match &result {
                            Ok(groups) => {
                                let size: usize = groups.iter().map(output_size).sum();
                                if output.fetch_add(size, Ordering::Relaxed) + size > max_output {
                                    stop.store(true, Ordering::Relaxed);
                                }
                            }
                            Err(_) => stop.store(true, Ordering::Relaxed),
                        }
                        *results[i].lock().unwrap_or_else(|e| e.into_inner()) = Some(result);
                    }
                });
            }
        });

        let mut groups = Vec::new();
        let mut size = 0;
        for result in results {
            let Some(result) = result.into_inner().unwrap_or_else(|e| e.into_inner()) else {
                // Not searched, since the output is full.
                return Ok(GrepOutput::Groups {
                    groups,
                    truncated: true,
                });
            };
            let result = match result {
                Ok(groups) => groups,
                Err(GrepError::Pattern(message)) => return Ok(GrepOutput::Rejected(message)),
                Err(e) => return Err(e.into()),
            };
            for mut group in result {
                let fits = group
                    .lines
                    .iter()
                    .take_while(|line| {
                        size += line_size(line);
                        size <= max_output
                    })
                    .count();
                if fits < group.lines.len() {
                    group.lines.truncate(fits);
                    if !group.lines.is_empty() {
                        groups.push(group);
                    }
                    return Ok(GrepOutput::Groups {
                        groups,
                        truncated: true,
                    });
                }
                groups.push(group);
            }
        }
        Ok(GrepOutput::Groups {
            groups,
            truncated: false,
        })
    })
    .await
}

type SearchResult = Result<Vec<GrepGroup>, GrepError>;

enum GrepError {
    /// The pattern failed at runtime, e.g. too much backtracking.
    Pattern(String),
    TimedOut,
    Internal(AppError),
}

impl From<GrepError> for AppError {
    fn from(error: GrepError) -> Self {
        match error {
            GrepError::Pattern(message) => {
                AppError::InternalServerError(format!("git grep failed: {message}"))
            }
            GrepError::TimedOut => AppError::InternalServerError("git grep timed out".to_string()),
            GrepError::Internal(e) => e,
        }
    }
}

/// The lines of `file` matching `regex`, with `context` lines around them.
fn search(
    repo: &gix::Repository,
    git_dir: &Path,
    file: &GrepFile,
    regex: &Regex,
    context: usize,
    resolve: Resolve,
) -> SearchResult {
    let blob = match file {
        GrepFile::Blob(blob) => blob,
        GrepFile::Text { path, text } => return search_text(path, text, regex, context),
    };
    let id = parse_oid(&blob.oid).map_err(GrepError::Internal)?;
    let object = repo
        .find_object(id)
        .map_err(|e| GrepError::Internal(failed("grep", e)))?;
    let Some(data) = resolve(git_dir, &object.data) else {
        return Ok(Vec::new());
    };
    if data[..data.len().min(BINARY_CHECK_BYTES)].contains(&0) {
        return Ok(Vec::new());
    }
    search_text(&blob.path, &String::from_utf8_lossy(&data), regex, context)
}

/// The lines of `text`, the content of the file at `path`, matching `regex`, with `context`
/// lines around them.
fn search_text(path: &str, text: &str, regex: &Regex, context: usize) -> SearchResult {
    // Like `str::lines`, which drops a `\r` before the `\n`.
    let lines: Vec<&str> = text.lines().collect();

    let mut matches = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        match regex.find(line) {
            Ok(Some(m)) => matches.push((i, m.start() + 1)),
            Ok(None) => {}
            Err(e) => return Err(GrepError::Pattern(e.to_string())),
        }
    }

    let mut groups: Vec<GrepGroup> = Vec::new();
    // The end of the last group, exclusive.
    let mut end = 0;
    for &(i, _) in &matches {
        let start = i.saturating_sub(context);
        let group_end = (i + context + 1).min(lines.len());
        // Overlapping or adjacent groups are joined. Like git, only separated with context.
        if groups.is_empty() || (context > 0 && start > end) {
            groups.push(GrepGroup {
                path: path.to_string(),
                lines: Vec::new(),
            });
        }
        let group = groups.last_mut().expect("pushed above");
        let from = start.max(end);
        for (line, text) in lines.iter().enumerate().take(group_end).skip(from) {
            let column = matches
                .binary_search_by_key(&line, |&(m, _)| m)
                .ok()
                .map(|m| matches[m].1);
            group.lines.push(GrepLine {
                number: line + 1,
                column,
                text: text.to_string(),
            });
        }
        end = end.max(group_end);
    }
    Ok(groups)
}

fn output_size(group: &GrepGroup) -> usize {
    group.lines.iter().map(line_size).sum()
}

fn line_size(line: &GrepLine) -> usize {
    line.text.len() + LINE_OVERHEAD
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::mirror::git::list_blobs;
    use crate::service::mirror::git::tests::Fixture;

    async fn run(
        files: &[(&str, &[u8])],
        pattern: &str,
        context: u32,
        max_output: usize,
    ) -> GrepOutput {
        run_with(files, Vec::new(), pattern, context, max_output).await
    }

    /// Searches the blobs of a commit with `files`, followed by `texts`.
    async fn run_with(
        files: &[(&str, &[u8])],
        texts: Vec<GrepFile>,
        pattern: &str,
        context: u32,
        max_output: usize,
    ) -> GrepOutput {
        let fixture = Fixture::new();
        let commit = fixture.commit(files);
        let git_dir = fixture.git_dir();
        let blobs = list_blobs(&git_dir, &commit).await.unwrap();
        let files = blobs.into_iter().map(GrepFile::Blob).chain(texts).collect();
        let options = GrepOptions {
            pattern,
            ignore_case: false,
            context,
        };
        grep(
            &git_dir,
            files,
            &options,
            |_, blob| Some(blob.into()),
            max_output,
        )
        .await
        .unwrap()
    }

    /// Like `git grep`: `path:number:text` for matches, `-` for context lines.
    fn render(output: GrepOutput) -> (Vec<String>, bool) {
        let GrepOutput::Groups { groups, truncated } = output else {
            panic!("rejected");
        };
        let lines = groups
            .iter()
            .flat_map(|group| {
                let lines = group.lines.iter().map(|line| {
                    let separator = if line.column.is_some() { ':' } else { '-' };
                    format!(
                        "{}{separator}{}{separator}{}",
                        group.path, line.number, line.text
                    )
                });
                std::iter::once("--".to_string()).chain(lines)
            })
            .collect();
        (lines, truncated)
    }

    #[tokio::test]
    async fn joins_overlapping_and_adjacent_context() {
        let text = b"a\nmatch\nb\nc\nmatch\nd\ne\nf\nmatch\n";
        let (lines, truncated) = render(run(&[("f.txt", text)], "match", 1, 1000).await);
        assert!(!truncated);
        assert_eq!(
            lines,
            [
                "--",
                "f.txt-1-a",
                "f.txt:2:match",
                "f.txt-3-b",
                "f.txt-4-c",
                "f.txt:5:match",
                "f.txt-6-d",
                "--",
                "f.txt-8-f",
                "f.txt:9:match",
            ]
        );
    }

    #[tokio::test]
    async fn reports_the_column_and_skips_binary_files() {
        let files: &[(&str, &[u8])] = &[
            ("a.txt", b"x\r\nsome needle\r\n"),
            ("b.bin", b"needle\0"),
            ("c.txt", "ü needle".as_bytes()),
        ];
        let GrepOutput::Groups { groups, .. } = run(files, "needle$", 0, 1000).await else {
            panic!("rejected");
        };
        let found: Vec<_> = groups
            .iter()
            .map(|g| (g.path.as_str(), g.lines[0].number, g.lines[0].column))
            .collect();
        // The column is a byte offset, `ü` takes two.
        assert_eq!(found, [("a.txt", 2, Some(6)), ("c.txt", 1, Some(4))]);
        assert_eq!(groups[0].lines[0].text, "some needle");
    }

    #[tokio::test]
    async fn searches_texts_like_blobs() {
        let texts = vec![GrepFile::Text {
            path: "doc.pdf".to_string(),
            text: "# Doc\r\n\nThe limit is 42.\n".into(),
        }];
        let (lines, truncated) =
            render(run_with(&[("a.txt", b"no limit\n")], texts, "limit", 1, 1000).await);
        assert!(!truncated);
        assert_eq!(
            lines,
            [
                "--",
                "a.txt:1:no limit",
                "--",
                "doc.pdf-2-",
                "doc.pdf:3:The limit is 42.",
            ]
        );
    }

    #[tokio::test]
    async fn stops_after_the_output_limit() {
        let files: &[(&str, &[u8])] = &[
            ("a.txt", b"hit 1\nhit 2\n"),
            ("b.txt", b"hit 3\n"),
            ("c.txt", b"hit 4\n"),
        ];
        let (lines, truncated) = render(run(files, "hit", 0, 3 * (5 + LINE_OVERHEAD)).await);
        assert!(truncated);
        assert_eq!(
            lines,
            [
                "--",
                "a.txt:1:hit 1",
                "a.txt:2:hit 2",
                "--",
                "b.txt:1:hit 3"
            ]
        );

        let (lines, truncated) = render(run(files, "hit", 0, 1000).await);
        assert!(!truncated);
        assert_eq!(lines.len(), 7);
    }

    #[tokio::test]
    async fn rejects_invalid_and_too_complex_patterns() {
        let text = "a".repeat(40);
        let files: &[(&str, &[u8])] = &[("a.txt", text.as_bytes())];
        assert!(matches!(
            run(files, "foo(", 0, 1000).await,
            GrepOutput::Rejected(_)
        ));
        // Backtracks exponentially, which fancy-regex stops.
        assert!(matches!(
            run(files, r"^(a|a)*(?=b)\1", 0, 1000).await,
            GrepOutput::Rejected(_)
        ));
    }
}
