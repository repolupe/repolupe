//! An incremental parser for `text/event-stream` (server-sent events), as specified in
//! <https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation>.
//!
//! It takes the body in chunks as they arrive, split anywhere (also inside a line ending or a
//! UTF-8 sequence), and returns the complete events. Lines end with `\n`, `\r\n` or `\r`;
//! comments (`:`, e.g. keep-alives) and unknown fields are skipped; `id` and `retry` are
//! ignored, since the client does not reconnect by itself.

/// A dispatched event.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SseEvent {
    /// The `event` field, `message` if there was none.
    pub event: String,
    /// The `data` lines, joined with `\n`.
    pub data: String,
}

#[derive(Debug, Default)]
pub struct SseParser {
    /// The bytes of the line not yet terminated.
    line: Vec<u8>,
    /// The previous chunk ended with `\r`, so a `\n` at the start of the next one belongs to it.
    skip_lf: bool,
    /// Whether the first line was seen, which may start with a byte order mark.
    started: bool,
    event: String,
    data: String,
    /// Whether a `data` field was seen since the last dispatch (`data` may be empty).
    has_data: bool,
}

const BOM: &[u8] = "\u{feff}".as_bytes();

impl SseParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Parses the next chunk and returns the events it completed.
    pub fn push(&mut self, chunk: &[u8]) -> Vec<SseEvent> {
        let mut events = Vec::new();
        let mut rest = chunk;
        if self.skip_lf && !rest.is_empty() {
            self.skip_lf = false;
            if rest[0] == b'\n' {
                rest = &rest[1..];
            }
        }
        while let Some(end) = rest.iter().position(|&b| b == b'\n' || b == b'\r') {
            let is_cr = rest[end] == b'\r';
            let first = !std::mem::replace(&mut self.started, true);
            let line = if self.line.is_empty() {
                decode_line(&rest[..end], first)
            } else {
                self.line.extend_from_slice(&rest[..end]);
                let line = decode_line(&self.line, first);
                self.line.clear();
                line
            };
            if let Some(event) = self.process_line(&line) {
                events.push(event);
            }
            rest = &rest[end + 1..];
            if is_cr {
                match rest.first() {
                    Some(b'\n') => rest = &rest[1..],
                    Some(_) => {}
                    None => self.skip_lf = true,
                }
            }
        }
        self.line.extend_from_slice(rest);
        events
    }

    fn process_line(&mut self, line: &str) -> Option<SseEvent> {
        if line.is_empty() {
            return self.dispatch();
        }
        let (field, value) = match line.split_once(':') {
            Some(("", _)) => return None,
            Some((field, value)) => (field, value.strip_prefix(' ').unwrap_or(value)),
            None => (line, ""),
        };
        match field {
            "event" => value.clone_into(&mut self.event),
            "data" => {
                if self.has_data {
                    self.data.push('\n');
                }
                self.data.push_str(value);
                self.has_data = true;
            }
            _ => {}
        }
        None
    }

    fn dispatch(&mut self) -> Option<SseEvent> {
        let event = std::mem::take(&mut self.event);
        if !std::mem::take(&mut self.has_data) {
            return None;
        }
        Some(SseEvent {
            event: if event.is_empty() {
                "message".to_owned()
            } else {
                event
            },
            data: std::mem::take(&mut self.data),
        })
    }
}

/// A complete line as text, invalid UTF-8 replaced. The `first` line of the stream loses its
/// byte order mark.
fn decode_line(line: &[u8], first: bool) -> String {
    let line = if first {
        line.strip_prefix(BOM).unwrap_or(line)
    } else {
        line
    };
    String::from_utf8_lossy(line).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(event: &str, data: &str) -> SseEvent {
        SseEvent {
            event: event.into(),
            data: data.into(),
        }
    }

    fn parse(chunks: &[&[u8]]) -> Vec<SseEvent> {
        let mut parser = SseParser::new();
        chunks.iter().flat_map(|chunk| parser.push(chunk)).collect()
    }

    /// The events of `input` split into chunks at every position, and byte by byte.
    fn parse_split_everywhere(input: &[u8]) -> Vec<SseEvent> {
        let whole = parse(&[input]);
        for split in 0..=input.len() {
            let (a, b) = input.split_at(split);
            assert_eq!(parse(&[a, b]), whole, "split at {split}");
        }
        let bytes: Vec<&[u8]> = input.chunks(1).collect();
        assert_eq!(parse(&bytes), whole, "byte by byte");
        whole
    }

    #[test]
    fn parses_events() {
        let input = "event: snapshot\ndata: {\"a\":1}\n\nevent: done\ndata: {}\n\n";
        assert_eq!(
            parse_split_everywhere(input.as_bytes()),
            [event("snapshot", r#"{"a":1}"#), event("done", "{}")]
        );
    }

    #[test]
    fn joins_data_lines() {
        let input = "data: first\ndata:second\ndata:  third\ndata\n\n";
        assert_eq!(
            parse_split_everywhere(input.as_bytes()),
            [event("message", "first\nsecond\n third\n")]
        );
    }

    #[test]
    fn accepts_every_line_ending() {
        for input in [
            "event: a\r\ndata: 1\r\n\r\nevent: b\r\ndata: 2\r\n\r\n",
            "event: a\rdata: 1\r\revent: b\rdata: 2\r\r",
            "event: a\ndata: 1\r\n\revent: b\r\ndata: 2\n\n",
        ] {
            assert_eq!(
                parse_split_everywhere(input.as_bytes()),
                [event("a", "1"), event("b", "2")],
                "{input:?}"
            );
        }
    }

    #[test]
    fn skips_comments_and_other_fields() {
        let input =
            ": keep-alive\n\n:\nid: 7\nretry: 1000\nunknown: x\nevent: a\n: inside\ndata: 1\n\n";
        assert_eq!(parse_split_everywhere(input.as_bytes()), [event("a", "1")]);
    }

    #[test]
    fn events_without_data_are_not_dispatched() {
        // The type of an event without data does not carry over to the next one.
        let input = "event: a\n\ndata: 1\n\nevent: b\ndata\n\n";
        assert_eq!(
            parse_split_everywhere(input.as_bytes()),
            [event("message", "1"), event("b", "")]
        );
    }

    #[test]
    fn values_keep_colons_and_lose_one_space() {
        let input = "event:a\ndata:  x: y \n\n";
        assert_eq!(
            parse_split_everywhere(input.as_bytes()),
            [event("a", " x: y ")]
        );
    }

    #[test]
    fn decodes_utf8_split_across_chunks() {
        let input = "event: content_delta\ndata: {\"text\":\"März 😀 中文\"}\n\n";
        assert_eq!(
            parse_split_everywhere(input.as_bytes()),
            [event("content_delta", r#"{"text":"März 😀 中文"}"#)]
        );
    }

    #[test]
    fn replaces_invalid_utf8() {
        assert_eq!(
            parse(&[b"data: a\xffb\n\n"]),
            [event("message", "a\u{fffd}b")]
        );
    }

    #[test]
    fn strips_a_leading_byte_order_mark() {
        let input = "\u{feff}event: a\ndata: \u{feff}1\n\n";
        assert_eq!(
            parse_split_everywhere(input.as_bytes()),
            [event("a", "\u{feff}1")]
        );
        // Only at the start of the stream.
        assert_eq!(
            parse(&[b"data: 1\n\n", "\u{feff}data: 2\n\n".as_bytes()]),
            [event("message", "1")]
        );
    }

    #[test]
    fn incomplete_events_are_kept_until_completed() {
        let mut parser = SseParser::new();
        assert_eq!(parser.push(b"event: a\ndata: 1\n"), []);
        assert_eq!(parser.push(b""), []);
        assert_eq!(parser.push(b"\n"), [event("a", "1")]);
        // A `\r` at the end of a chunk ends the line, a `\n` right after it is part of it.
        assert_eq!(parser.push(b"data: 2\r"), []);
        assert_eq!(parser.push(b""), []);
        assert_eq!(parser.push(b"\n"), []);
        assert_eq!(parser.push(b"\r\n"), [event("message", "2")]);
    }
}
