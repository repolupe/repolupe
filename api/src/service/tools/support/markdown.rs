//! Finds the headings of a Markdown document, following CommonMark closely enough for an
//! outline: ATX (`# Title`) and setext (`Title` underlined with `===` or `---`) headings,
//! skipping fenced and indented code blocks and YAML front matter.

#[derive(Debug, PartialEq, Eq)]
pub(crate) struct Heading {
    /// 1 to 6.
    pub(crate) level: usize,
    pub(crate) text: String,
    /// 1-based, the line of the text for setext headings.
    pub(crate) line: usize,
}

pub(crate) fn headings(content: &str) -> Vec<Heading> {
    let lines: Vec<&str> = content.lines().collect();
    let mut headings = Vec::new();
    let mut start = 0;
    if lines.first().is_some_and(|line| line.trim_end() == "---")
        && let Some(end) = lines[1..]
            .iter()
            .position(|line| matches!(line.trim_end(), "---" | "..."))
    {
        start = end + 2;
    }

    // The fence character and length of the open code block.
    let mut fence: Option<(char, usize)> = None;
    // Whether the previous line is paragraph text, which a setext underline makes a heading.
    let mut in_paragraph = false;
    for (i, line) in lines.iter().enumerate().skip(start) {
        let (indent, rest) = split_indent(line);
        if let Some((fence_char, fence_len)) = fence {
            if indent < 4 && closes_fence(rest, fence_char, fence_len) {
                fence = None;
            }
            continue;
        }
        if rest.trim().is_empty() {
            in_paragraph = false;
            continue;
        }
        if indent >= 4 {
            // Continues a paragraph, otherwise an indented code block.
            continue;
        }
        if let Some(open) = opens_fence(rest) {
            fence = Some(open);
            in_paragraph = false;
            continue;
        }
        if let Some((level, text)) = atx_heading(rest) {
            headings.push(Heading {
                level,
                text,
                line: i + 1,
            });
            in_paragraph = false;
            continue;
        }
        if in_paragraph && let Some(level) = setext_level(rest) {
            headings.push(Heading {
                level,
                text: lines[i - 1].trim().to_string(),
                line: i,
            });
            in_paragraph = false;
            continue;
        }
        in_paragraph = !starts_block(rest);
    }
    headings
}

/// Leading spaces, counting a tab as 4, and the rest of the line.
fn split_indent(line: &str) -> (usize, &str) {
    let mut indent = 0;
    for (i, c) in line.char_indices() {
        match c {
            ' ' => indent += 1,
            '\t' => indent += 4,
            _ => return (indent, &line[i..]),
        }
    }
    (indent, "")
}

fn opens_fence(rest: &str) -> Option<(char, usize)> {
    let fence_char = rest.chars().next().filter(|&c| c == '`' || c == '~')?;
    let len = rest.chars().take_while(|&c| c == fence_char).count();
    // The info string of a backtick fence must not contain backticks.
    (len >= 3 && !(fence_char == '`' && rest[len..].contains('`'))).then_some((fence_char, len))
}

fn closes_fence(rest: &str, fence_char: char, fence_len: usize) -> bool {
    let len = rest.chars().take_while(|&c| c == fence_char).count();
    len >= fence_len && rest[len * fence_char.len_utf8()..].trim().is_empty()
}

fn atx_heading(rest: &str) -> Option<(usize, String)> {
    let level = rest.chars().take_while(|&c| c == '#').count();
    if !(1..=6).contains(&level) {
        return None;
    }
    let text = &rest[level..];
    if !(text.is_empty() || text.starts_with([' ', '\t'])) {
        return None;
    }
    let text = text.trim();
    // An optional closing sequence of `#`, after a space.
    let without_closing = text.trim_end_matches('#');
    let text = if without_closing.is_empty() {
        ""
    } else if without_closing.ends_with([' ', '\t']) {
        without_closing.trim_end()
    } else {
        text
    };
    Some((level, text.to_string()))
}

fn setext_level(rest: &str) -> Option<usize> {
    let underline = rest.trim_end();
    if !underline.is_empty() && underline.chars().all(|c| c == '=') {
        Some(1)
    } else if !underline.is_empty() && underline.chars().all(|c| c == '-') {
        Some(2)
    } else {
        None
    }
}

/// Whether the line starts a block that is not a paragraph, so it cannot be a setext heading's
/// text: a quote, a list item, a thematic break or an HTML block.
fn starts_block(rest: &str) -> bool {
    if rest.starts_with(['>', '<']) {
        return true;
    }
    if let Some(after) = rest.strip_prefix(['-', '*', '+'])
        && (after.is_empty() || after.starts_with([' ', '\t']))
    {
        return true;
    }
    let digits = rest.chars().take_while(char::is_ascii_digit).count();
    if (1..=9).contains(&digits) {
        let after = &rest[digits..];
        if let Some(after) = after.strip_prefix(['.', ')'])
            && (after.is_empty() || after.starts_with([' ', '\t']))
        {
            return true;
        }
    }
    let compact: String = rest.chars().filter(|c| !c.is_whitespace()).collect();
    compact.len() >= 3
        && ['*', '_', '-']
            .iter()
            .any(|&c| compact.chars().all(|x| x == c))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Formatted as `## Text :line`.
    fn outline(content: &str) -> Vec<String> {
        headings(content)
            .into_iter()
            .map(|h| format!("{} {} :{}", "#".repeat(h.level), h.text, h.line))
            .collect()
    }

    #[test]
    fn finds_atx_headings() {
        let content = "# Title\n\nText\n\n## Install ##\n### \n#### Not # closed\n####### Too deep\n#NoSpace\n   ## Indented\n";
        assert_eq!(
            outline(content),
            vec![
                "# Title :1",
                "## Install :5",
                "###  :6",
                "#### Not # closed :7",
                "## Indented :10",
            ]
        );
    }

    #[test]
    fn finds_setext_headings() {
        let content = "Title\n=====\n\nSection\n---\n\n- item\n---\n\n---\n\nText\n***\n";
        assert_eq!(outline(content), vec!["# Title :1", "## Section :4"]);
    }

    #[test]
    fn skips_code_and_front_matter() {
        let content = "---\ntitle: Doc\n# not a heading\n---\n# Real\n```bash\n# comment\n```\n~~~~\n# also code\n~~~\nstill code?\n~~~~\n    # indented code\n## After\n";
        assert_eq!(outline(content), vec!["# Real :5", "## After :15"]);
    }

    #[test]
    fn indented_lines_continue_paragraphs() {
        let content = "Text\n    # continuation\nMore\n===\n";
        assert_eq!(outline(content), vec!["# More :3"]);
    }

    #[test]
    fn handles_crlf_and_unclosed_fences() {
        assert_eq!(outline("# A\r\n## B\r\n"), vec!["# A :1", "## B :2"]);
        assert_eq!(outline("# A\n```\n# B\n"), vec!["# A :1"]);
    }
}
