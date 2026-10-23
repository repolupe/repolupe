//! Glob patterns with the semantics of git's `:(glob)` pathspec magic, for the `glob` argument
//! of the tools in [`crate::service::tools`].

/// Patterns without `/` match file names at any depth, like in `.gitignore` or ripgrep.
pub(crate) fn anchored(pattern: &str) -> String {
    if pattern.contains('/') {
        pattern.trim_start_matches('/').to_string()
    } else {
        format!("**/{pattern}")
    }
}

/// Whether `path` matches `pattern`: `*` and `?` do not match `/`, `**/` matches any number
/// of directories, a trailing `/**` everything inside a directory.
pub(crate) fn matches(pattern: &str, path: &str) -> bool {
    let pattern: Vec<char> = pattern.chars().collect();
    let path: Vec<char> = path.chars().collect();
    match_at(&pattern, 0, &path)
}

fn match_at(pattern: &[char], p: usize, path: &[char]) -> bool {
    let Some(&c) = pattern.get(p) else {
        return path.is_empty();
    };
    let segment_start = p == 0 || pattern[p - 1] == '/';
    match c {
        '*' if segment_start && pattern.get(p + 1) == Some(&'*') => {
            match pattern.get(p + 2) {
                // `**` at the end matches everything left.
                None => !path.is_empty(),
                // `**/` matches zero or more whole directories.
                Some('/') => {
                    match_at(pattern, p + 3, path)
                        || path
                            .iter()
                            .enumerate()
                            .any(|(i, &c)| c == '/' && match_at(pattern, p + 3, &path[i + 1..]))
                }
                // Otherwise it is a plain `*`.
                Some(_) => match_star(pattern, p + 2, path),
            }
        }
        '*' => {
            let mut next = p + 1;
            while pattern.get(next) == Some(&'*') {
                next += 1;
            }
            match_star(pattern, next, path)
        }
        '?' => matches!(path.first(), Some(&c) if c != '/') && match_at(pattern, p + 1, &path[1..]),
        '[' => match match_class(pattern, p, path.first().copied()) {
            Some((true, next)) => match_at(pattern, next, &path[1..]),
            Some((false, _)) => false,
            // Without a closing `]` it is a literal.
            None => path.first() == Some(&'[') && match_at(pattern, p + 1, &path[1..]),
        },
        '\\' if p + 1 < pattern.len() => {
            path.first() == Some(&pattern[p + 1]) && match_at(pattern, p + 2, &path[1..])
        }
        c => path.first() == Some(&c) && match_at(pattern, p + 1, &path[1..]),
    }
}

/// A `*` before `pattern[next..]`, matching anything up to the next `/`.
fn match_star(pattern: &[char], next: usize, path: &[char]) -> bool {
    let segment_end = path.iter().position(|&c| c == '/').unwrap_or(path.len());
    (0..=segment_end).any(|i| match_at(pattern, next, &path[i..]))
}

/// Matches `c` against the class starting at `pattern[p] == '['`. Returns whether it matched
/// and the index after the class, or `None` if the class is not closed.
fn match_class(pattern: &[char], p: usize, c: Option<char>) -> Option<(bool, usize)> {
    let mut i = p + 1;
    let negated = matches!(pattern.get(i), Some('!' | '^'));
    if negated {
        i += 1;
    }
    let mut matched = false;
    let mut first = true;
    loop {
        let start = *pattern.get(i)?;
        if start == ']' && !first {
            break;
        }
        first = false;
        let (start, len) = match start {
            '\\' => (*pattern.get(i + 1)?, 2),
            start => (start, 1),
        };
        i += len;
        let end = if pattern.get(i) == Some(&'-') && pattern.get(i + 1).is_some_and(|&c| c != ']') {
            let (end, len) = match pattern[i + 1] {
                '\\' => (*pattern.get(i + 2)?, 3),
                end => (end, 2),
            };
            i += len;
            end
        } else {
            start
        };
        if let Some(c) = c {
            matched |= (start..=end).contains(&c);
        }
    }
    let matched = c.is_some_and(|c| c != '/' && matched != negated);
    Some((matched, i + 1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anchors_patterns_without_slash() {
        assert_eq!(anchored("*.md"), "**/*.md");
        assert_eq!(anchored("docs/*.md"), "docs/*.md");
        assert_eq!(anchored("/docs/*.md"), "docs/*.md");
    }

    #[test]
    fn star_stays_within_a_directory() {
        assert!(matches("*.md", "README.md"));
        assert!(!matches("*.md", "docs/README.md"));
        assert!(matches("docs/*.md", "docs/a.md"));
        assert!(!matches("docs/*.md", "docs/sub/a.md"));
        assert!(matches("a*b*c", "abxbc"));
        assert!(!matches("a?c", "a/c"));
        assert!(matches("a?c", "abc"));
    }

    #[test]
    fn double_star_matches_directories() {
        assert!(matches("**/*.md", "README.md"));
        assert!(matches("**/*.md", "docs/sub/a.md"));
        assert!(!matches("**/*.md", "docs/a.txt"));
        assert!(matches("docs/**/a.md", "docs/a.md"));
        assert!(matches("docs/**/a.md", "docs/x/y/a.md"));
        assert!(!matches("docs/**/a.md", "other/docs/a.md"));
        assert!(matches("docs/**", "docs/x/a.md"));
        assert!(!matches("docs/**", "docsx/a.md"));
        // Not at a segment boundary, so a plain `*`.
        assert!(matches("a**.md", "ab.md"));
        assert!(!matches("a**.md", "a/b.md"));
    }

    #[test]
    fn matches_classes_and_escapes() {
        assert!(matches("[abc].md", "b.md"));
        assert!(!matches("[abc].md", "d.md"));
        assert!(matches("[a-c].md", "b.md"));
        assert!(matches("[!a-c].md", "d.md"));
        assert!(!matches("[!a-c].md", "b.md"));
        assert!(matches("[]].md", "].md"));
        assert!(matches("[.md", "[.md"));
        assert!(matches(r"\*.md", "*.md"));
        assert!(!matches(r"\*.md", "a.md"));
    }
}
