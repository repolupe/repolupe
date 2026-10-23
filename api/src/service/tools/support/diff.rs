//! The changes proposed with [`CHANGE_FILE`](crate::service::tools::CHANGE_FILE) and the other
//! tools that propose commits as the user reviews them: the hunks of the diff, the same as in
//! the patch, with the words that changed within a line marked.

use super::patch::{CONTEXT_LINES, is_binary};
use crate::dto::chat::{DiffFileKind, DiffHunkDto, DiffLineDto, DiffLineKind, DiffPartDto};
use similar::{Algorithm, ChangeTag, TextDiff};

/// What a change does to a file, and its hunks.
pub(crate) struct FileDiff {
    pub(crate) kind: DiffFileKind,
    /// Empty if either side is binary or nothing changed in the content.
    pub(crate) hunks: Vec<DiffHunkDto>,
}

/// The diff of a file from `old` to `new` (`None` where the file does not exist).
pub(crate) fn file_diff(old: Option<&[u8]>, new: Option<&[u8]>) -> FileDiff {
    let kind = match (old, new) {
        (None, Some(_)) => DiffFileKind::Added,
        (Some(_), None) => DiffFileKind::Deleted,
        _ => DiffFileKind::Modified,
    };
    if old.is_some_and(is_binary) || new.is_some_and(is_binary) {
        return FileDiff {
            kind,
            hunks: vec![],
        };
    }
    let text = |side: Option<&[u8]>| String::from_utf8_lossy(side.unwrap_or_default()).into_owned();
    FileDiff {
        kind,
        hunks: hunks(&text(old), &text(new)),
    }
}

/// The hunks of the diff from `old` to `new`, like [`super::patch::hunks`] writes them.
fn hunks(old: &str, new: &str) -> Vec<DiffHunkDto> {
    let diff = TextDiff::configure()
        .algorithm(Algorithm::Myers)
        .diff_lines(old, new);
    let mut hunks = Vec::new();
    for ops in diff.grouped_ops(CONTEXT_LINES) {
        let Some(first) = ops.first() else {
            continue;
        };
        let skipped =
            !hunks.is_empty() || first.old_range().start > 0 || first.new_range().start > 0;
        let lines: Vec<(DiffLineKind, &str)> = ops
            .iter()
            .flat_map(|op| diff.iter_changes(op))
            .map(|change| {
                let kind = match change.tag() {
                    ChangeTag::Equal => DiffLineKind::Context,
                    ChangeTag::Delete => DiffLineKind::Removed,
                    ChangeTag::Insert => DiffLineKind::Added,
                };
                let text = change.value();
                let text = text.strip_suffix('\n').unwrap_or(text);
                (kind, text.strip_suffix('\r').unwrap_or(text))
            })
            .collect();
        hunks.push(DiffHunkDto {
            skipped,
            lines: mark_changed_words(&lines),
        });
    }
    hunks
}

/// Pairs the removed and added lines of each change in order and marks the words that differ
/// between them.
fn mark_changed_words(lines: &[(DiffLineKind, &str)]) -> Vec<DiffLineDto> {
    let mut marked: Vec<DiffLineDto> = lines
        .iter()
        .map(|&(kind, text)| DiffLineDto {
            kind,
            parts: unchanged(text),
        })
        .collect();
    let mut i = 0;
    while i < lines.len() {
        let removed_end = i + lines[i..]
            .iter()
            .take_while(|(kind, _)| *kind == DiffLineKind::Removed)
            .count();
        let added_end = removed_end
            + lines[removed_end..]
                .iter()
                .take_while(|(kind, _)| *kind == DiffLineKind::Added)
                .count();
        for k in 0..(removed_end - i).min(added_end - removed_end) {
            let (removed, added) = word_diff(lines[i + k].1, lines[removed_end + k].1);
            marked[i + k].parts = removed;
            marked[removed_end + k].parts = added;
        }
        i = added_end.max(i + 1);
    }
    marked
}

fn unchanged(text: &str) -> Vec<DiffPartDto> {
    vec![DiffPartDto {
        text: text.to_string(),
        changed: false,
    }]
}

/// Marks what lies between the words both lines start and end with, if they have enough in
/// common.
fn word_diff(before: &str, after: &str) -> (Vec<DiffPartDto>, Vec<DiffPartDto>) {
    let a = tokens(before);
    let b = tokens(after);
    let prefix = a.iter().zip(&b).take_while(|(a, b)| a == b).count();
    let suffix = a[prefix..]
        .iter()
        .rev()
        .zip(b[prefix..].iter().rev())
        .take_while(|(a, b)| a == b)
        .count();
    let common: usize = a[..prefix]
        .iter()
        .chain(&a[a.len() - suffix..])
        .map(|token| token.chars().count())
        .sum();
    if common * 2 < before.chars().count().max(after.chars().count()) {
        // Mostly rewritten: marking nearly every word would only add noise.
        return (unchanged(before), unchanged(after));
    }
    let split = |tokens: &[&str]| -> Vec<DiffPartDto> {
        [
            (&tokens[..prefix], false),
            (&tokens[prefix..tokens.len() - suffix], true),
            (&tokens[tokens.len() - suffix..], false),
        ]
        .into_iter()
        .map(|(tokens, changed)| DiffPartDto {
            text: tokens.concat(),
            changed,
        })
        .filter(|part| !part.text.is_empty())
        .collect()
    };
    (split(&a), split(&b))
}

#[derive(Clone, Copy, PartialEq)]
enum CharClass {
    Word,
    Space,
    Other,
}

/// `text` split into words, runs of whitespace and single other characters.
fn tokens(text: &str) -> Vec<&str> {
    let class = |c: char| {
        if c.is_alphanumeric() || c == '_' {
            CharClass::Word
        } else if c.is_whitespace() {
            CharClass::Space
        } else {
            CharClass::Other
        }
    };
    let mut tokens = Vec::new();
    let mut start = 0;
    let mut previous = None;
    for (i, c) in text.char_indices() {
        let current = class(c);
        if i > start && (previous != Some(current) || current == CharClass::Other) {
            tokens.push(&text[start..i]);
            start = i;
        }
        previous = Some(current);
    }
    if start < text.len() {
        tokens.push(&text[start..]);
    }
    tokens
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parts(line: &DiffLineDto) -> Vec<(&str, bool)> {
        line.parts
            .iter()
            .map(|part| (part.text.as_str(), part.changed))
            .collect()
    }

    fn kinds(hunk: &DiffHunkDto) -> Vec<DiffLineKind> {
        hunk.lines.iter().map(|line| line.kind).collect()
    }

    #[test]
    fn marks_changed_words() {
        let diff = file_diff(
            Some(b"| Name | Born       |\n| Papa | 10.06.1959 |\n"),
            Some(b"| Name | Born       |\n| Papa | 10.06.1958 |\n"),
        );
        assert_eq!(diff.kind, DiffFileKind::Modified);
        let [hunk] = diff.hunks.as_slice() else {
            panic!("one hunk expected");
        };
        assert!(!hunk.skipped);
        assert_eq!(
            kinds(hunk),
            [
                DiffLineKind::Context,
                DiffLineKind::Removed,
                DiffLineKind::Added
            ]
        );
        assert_eq!(
            parts(&hunk.lines[1]),
            [("| Papa | 10.06.", false), ("1959", true), (" |", false)]
        );
        assert_eq!(
            parts(&hunk.lines[2]),
            [("| Papa | 10.06.", false), ("1958", true), (" |", false)]
        );
    }

    #[test]
    fn leaves_rewritten_lines_unmarked_and_tells_skipped_lines() {
        let old: String = (1..=30).map(|i| format!("line {i}\r\n")).collect();
        let new = old
            .replace("line 5\r\n", "a lazy dog sleeps\r\n")
            .replace("line 20\r\n", "line 2x\r\n");
        let diff = file_diff(Some(old.as_bytes()), Some(new.as_bytes()));
        let [first, second] = diff.hunks.as_slice() else {
            panic!("two hunks expected");
        };
        assert!(first.skipped);
        assert_eq!(first.lines.len(), 8);
        assert_eq!(parts(&first.lines[0]), [("line 2", false)]);
        assert_eq!(parts(&first.lines[3]), [("line 5", false)]);
        assert_eq!(parts(&first.lines[4]), [("a lazy dog sleeps", false)]);
        assert!(second.skipped);
        assert_eq!(parts(&second.lines[4]), [("line ", false), ("2x", true)]);
    }

    #[test]
    fn tells_new_deleted_and_binary_files() {
        let added = file_diff(None, Some(b"Notes"));
        assert_eq!(added.kind, DiffFileKind::Added);
        let [hunk] = added.hunks.as_slice() else {
            panic!("one hunk expected");
        };
        assert!(!hunk.skipped);
        assert_eq!(kinds(hunk), [DiffLineKind::Added]);
        assert_eq!(parts(&hunk.lines[0]), [("Notes", false)]);

        let deleted = file_diff(Some(b"\x89PNG\0"), None);
        assert_eq!(deleted.kind, DiffFileKind::Deleted);
        assert!(deleted.hunks.is_empty());

        assert!(file_diff(Some(b"same\n"), Some(b"same\n")).hunks.is_empty());
    }

    #[test]
    fn splits_words() {
        assert_eq!(
            tokens("fn  größe_2(a)"),
            ["fn", "  ", "größe_2", "(", "a", ")"]
        );
        assert_eq!(tokens("--"), ["-", "-"]);
        assert!(tokens("").is_empty());
    }
}
