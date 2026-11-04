//! The results of tool calls, stored for [`RUN_SCRIPT`] so the model processes them with
//! scripts instead of reading them. The MCP tools store all their results. Scripts get them in
//! `$results`, keyed by number from 1. The model sees short results in full, of the others
//! only what they are. They are kept for the answer, dropping the oldest beyond
//! [`MAX_STORED_BYTES`].

use super::format_size;
use crate::config::error::AppError;
use crate::service::tools::run_script::MAX_INPUT_BYTES;
use crate::service::tools::{RUN_SCRIPT, ToolError};
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

/// Of all results of an answer together. A single result may have at most
/// [`MAX_INPUT_BYTES`], like the inputs of a script.
const MAX_STORED_BYTES: usize = 2 * MAX_INPUT_BYTES;
/// Texts of at most this many characters are shown to the model in full, since a script to
/// read them would cost more.
const MAX_SHOWN_TEXT_CHARS: usize = 16_000;
/// Like [`MAX_SHOWN_TEXT_CHARS`], for JSON, serialized. Lower, since scripts help most with
/// JSON (filtering, counting), while the model reads most texts in full anyway.
const MAX_SHOWN_JSON_CHARS: usize = 8_000;
/// Longer types are described with fewer levels of objects, see [`type_of`].
const MAX_TYPE_LEN: usize = 2_000;
/// Levels of objects described at most, deeper ones are `{ … }`.
const MAX_TYPE_DEPTH: usize = 6;
/// Keys described of each object, the others are only counted.
const MAX_TYPE_KEYS: usize = 30;

/// What a tool returned, to store.
pub(crate) enum ResultValue {
    Text(String),
    Json(Value),
}

/// A stored result, as scripts get it.
pub(crate) enum StoredResult {
    Text(String),
    /// Serialized, since a [`Value`] takes several times the memory.
    Json(String),
}

impl StoredResult {
    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Text(text) | Self::Json(text) => text.len(),
        }
    }
}

/// The results of an answer.
#[derive(Default)]
pub(crate) struct StoredResults(Mutex<Results>);

#[derive(Default)]
struct Results {
    /// By number, from 1, `None` once dropped.
    kept: Vec<Option<Arc<StoredResult>>>,
    bytes: usize,
}

impl StoredResults {
    /// Stores `value` and returns what the model gets instead: its number and what it is, or
    /// all of it if it is short. The size is checked first, since describing a result walks
    /// all of it.
    pub(crate) fn store(&self, value: ResultValue) -> Result<String, ToolError> {
        let (stored, about) = match value {
            ResultValue::Text(text) => {
                if text.len() > MAX_INPUT_BYTES {
                    return Ok(too_large(text.len()));
                }
                let about = if is_short(&text, MAX_SHOWN_TEXT_CHARS) {
                    About::All("a string", text.clone())
                } else {
                    About::Kind(format!(
                        "a string of {} in {}.",
                        count(text.chars().count(), "character"),
                        count(text.lines().count(), "line")
                    ))
                };
                (StoredResult::Text(text), about)
            }
            ResultValue::Json(value) => {
                let json = serde_json::to_string(&value).map_err(|e| {
                    AppError::InternalServerError(format!("Could not serialize a result: {e}"))
                })?;
                if json.len() > MAX_INPUT_BYTES {
                    return Ok(too_large(json.len()));
                }
                let about = if is_short(&json, MAX_SHOWN_JSON_CHARS) {
                    About::All("parsed JSON", json.clone())
                } else {
                    let length = match &value {
                        Value::Array(items) => {
                            format!(", an array of {}", count(items.len(), "item"))
                        }
                        _ => String::new(),
                    };
                    About::Kind(format!(
                        "parsed from JSON ({}{length}), of this TypeScript type:\n{}",
                        format_size(json.len() as u64),
                        type_of(&value)
                    ))
                };
                (StoredResult::Json(json), about)
            }
        };
        let number = self.0.lock().unwrap().add(stored);
        Ok(match about {
            About::All(kind, value) => format!(
                "Stored in `$results[{number}]` for {RUN_SCRIPT} as {kind}. Here is all of \
                it:\n{value}"
            ),
            About::Kind(about) => format!(
                "Stored in `$results[{number}]`. You don't see it: read or process it with \
                {RUN_SCRIPT}. It is {about}"
            ),
        })
    }

    /// The results stored so far, by number from 1, `None` for those dropped.
    pub(crate) fn snapshot(&self) -> Vec<Option<Arc<StoredResult>>> {
        self.0.lock().unwrap().kept.clone()
    }
}

/// What the model gets of a result.
enum About {
    /// Its kind and all of it, since it is short.
    All(&'static str, String),
    /// What it is.
    Kind(String),
}

/// What the model gets of a result of `bytes` beyond [`MAX_INPUT_BYTES`]. Not an error, since
/// the call succeeded: a model told it failed might repeat a call that changed something.
fn too_large(bytes: usize) -> String {
    format!(
        "The tool ran, but its result is too large to store ({}), the limit is {}. If the tool \
        only reads, call it again and ask for less, e.g. with a filter or smaller pages.",
        format_size(bytes as u64),
        format_size(MAX_INPUT_BYTES as u64)
    )
}

/// Whether `text` has at most `max` characters.
fn is_short(text: &str, max: usize) -> bool {
    text.chars().nth(max).is_none()
}

/// What a script that reads the dropped result `number` throws.
pub(crate) fn dropped_message(number: usize) -> String {
    format!(
        "Result {number} is no longer stored, the results of this answer took more than {}. \
        Call the tool again.",
        format_size(MAX_STORED_BYTES as u64)
    )
}

impl Results {
    /// Adds `result` and returns its number, dropping the oldest results beyond
    /// [`MAX_STORED_BYTES`].
    fn add(&mut self, result: StoredResult) -> usize {
        self.bytes += result.len();
        self.kept.push(Some(Arc::new(result)));
        for kept in &mut self.kept {
            if self.bytes <= MAX_STORED_BYTES {
                break;
            }
            if let Some(dropped) = kept.take() {
                self.bytes -= dropped.len();
            }
        }
        self.kept.len()
    }
}

/// `n` `things`, e.g. `1 line` or `2 lines`.
fn count(n: usize, thing: &str) -> String {
    match n {
        1 => format!("1 {thing}"),
        _ => format!("{n} {thing}s"),
    }
}

/// A TypeScript type of `value`, with the items of arrays described together. With as many
/// levels of objects as fit into [`MAX_TYPE_LEN`], cut if not even one does.
fn type_of(value: &Value) -> String {
    let mut shape = Shape::default();
    shape.add(value);
    let mut out = String::new();
    for depth in (1..=MAX_TYPE_DEPTH).rev() {
        out.clear();
        shape.write(depth, &mut out);
        if out.len() <= MAX_TYPE_LEN {
            return out;
        }
    }
    let end = out.floor_char_boundary(MAX_TYPE_LEN);
    format!("{} …", &out[..end])
}

/// The types of the values at one place of a JSON value, e.g. of all items of an array.
#[derive(Default)]
struct Shape {
    null: bool,
    boolean: bool,
    number: bool,
    string: bool,
    /// Of the items of all arrays here.
    array: Option<Box<Shape>>,
    object: Option<Box<ObjectShape>>,
}

/// The keys of all objects at one place of a JSON value.
#[derive(Default)]
struct ObjectShape {
    /// Of objects, to tell which keys are optional.
    count: usize,
    /// In the order first seen.
    fields: Vec<Field>,
    /// The index of each key in `fields`.
    index: HashMap<String, usize>,
}

struct Field {
    key: String,
    /// Of objects that have it.
    count: usize,
    shape: Shape,
}

impl Shape {
    fn add(&mut self, value: &Value) {
        match value {
            Value::Null => self.null = true,
            Value::Bool(_) => self.boolean = true,
            Value::Number(_) => self.number = true,
            Value::String(_) => self.string = true,
            Value::Array(items) => {
                let shape = self.array.get_or_insert_default();
                for item in items {
                    shape.add(item);
                }
            }
            Value::Object(map) => self.object.get_or_insert_default().add(map),
        }
    }

    /// How many types it is a union of.
    fn alternatives(&self) -> usize {
        [self.null, self.boolean, self.number, self.string]
            .into_iter()
            .filter(|&b| b)
            .count()
            + usize::from(self.array.is_some())
            + usize::from(self.object.is_some())
    }

    /// Writes the type with `depth` levels of objects. Stops early once `out` is longer than
    /// [`MAX_TYPE_LEN`], since it is then described with fewer levels.
    fn write(&self, depth: usize, out: &mut String) {
        let mut first = true;
        let mut separate = |out: &mut String| {
            if !std::mem::take(&mut first) {
                out.push_str(" | ");
            }
        };
        if let Some(object) = &self.object {
            separate(out);
            object.write(depth, out);
        }
        if let Some(items) = &self.array {
            separate(out);
            match items.alternatives() {
                // Only empty arrays.
                0 => out.push_str("[]"),
                1 => {
                    items.write(depth, out);
                    out.push_str("[]");
                }
                _ => {
                    out.push('(');
                    items.write(depth, out);
                    out.push_str(")[]");
                }
            }
        }
        for (present, name) in [
            (self.string, "string"),
            (self.number, "number"),
            (self.boolean, "boolean"),
            (self.null, "null"),
        ] {
            if present {
                separate(out);
                out.push_str(name);
            }
        }
    }
}

impl ObjectShape {
    fn add(&mut self, map: &Map<String, Value>) {
        self.count += 1;
        for (key, value) in map {
            let index = match self.index.get(key) {
                Some(&index) => index,
                None => {
                    self.index.insert(key.clone(), self.fields.len());
                    self.fields.push(Field {
                        key: key.clone(),
                        count: 0,
                        shape: Shape::default(),
                    });
                    self.fields.len() - 1
                }
            };
            let field = &mut self.fields[index];
            field.count += 1;
            field.shape.add(value);
        }
    }

    fn write(&self, depth: usize, out: &mut String) {
        if self.fields.is_empty() {
            out.push_str("{}");
            return;
        }
        if depth == 0 {
            out.push_str("{ … }");
            return;
        }
        out.push_str("{ ");
        for (i, field) in self.fields.iter().take(MAX_TYPE_KEYS).enumerate() {
            if out.len() > MAX_TYPE_LEN {
                return;
            }
            if i > 0 {
                out.push_str(", ");
            }
            if is_identifier(&field.key) {
                out.push_str(&field.key);
            } else {
                out.push_str(&Value::String(field.key.clone()).to_string());
            }
            if field.count < self.count {
                out.push('?');
            }
            out.push_str(": ");
            field.shape.write(depth - 1, out);
        }
        if let Some(more) = self.fields.len().checked_sub(MAX_TYPE_KEYS)
            && more > 0
        {
            out.push_str(&format!(", /* {} */", count(more, "more key")));
        }
        out.push_str(" }");
    }
}

/// Whether `key` needs no quotes as a property name.
fn is_identifier(key: &str) -> bool {
    let mut chars = key.chars();
    chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_' || c == '$')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '$')
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn json_type(value: Value) -> String {
        type_of(&value)
    }

    #[test]
    fn describes_types() {
        assert_eq!(json_type(json!("a")), "string");
        assert_eq!(json_type(json!([])), "[]");
        assert_eq!(json_type(json!({})), "{}");
        assert_eq!(
            json_type(json!([1, "a", null])),
            "(string | number | null)[]"
        );
        assert_eq!(
            json_type(json!({
                "issues": [
                    {"assignee": {"login": "a"}, "id": 1, "labels": ["bug"]},
                    {"assignee": null, "closed at": "2026-01-01", "id": 2, "labels": []},
                ],
                "total": 2,
            })),
            "{ issues: { assignee: { login: string } | null, id: number, labels: string[], \
            \"closed at\"?: string }[], total: number }"
        );
        // Mixed arrays and objects.
        assert_eq!(
            json_type(json!([[1], {"a": true}, [[]]])),
            "({ a: boolean } | ([] | number)[])[]"
        );
    }

    #[test]
    fn shortens_long_types() {
        let wide: Map<String, Value> = (0..40).map(|i| (format!("k{i:02}"), json!(i))).collect();
        let described = json_type(Value::Object(wide));
        assert!(
            described.starts_with("{ k00: number, k01: number, "),
            "{described}"
        );
        assert!(
            described.ends_with(", k29: number, /* 10 more keys */ }"),
            "{described}"
        );

        // Too long with all levels, so the deeper ones are left out.
        let long_key = "x".repeat(100);
        let mut deep = json!({"leaf": 1});
        for _ in 0..5 {
            let level: Map<String, Value> = (0..5)
                .map(|i| (format!("{long_key}{i}"), deep.clone()))
                .collect();
            deep = Value::Object(level);
        }
        let described = json_type(deep);
        assert!(described.len() <= MAX_TYPE_LEN, "{described}");
        assert!(described.contains("{ … }"), "{described}");

        // Cut if not even one level fits.
        let wide: Map<String, Value> = (0..30)
            .map(|i| (format!("{i}{long_key}"), json!(i)))
            .collect();
        let described = json_type(Value::Object(wide));
        assert!(described.ends_with(" …"), "{described}");
        assert!(described.len() <= MAX_TYPE_LEN + " …".len());
    }

    #[test]
    fn stores_results() {
        let results = StoredResults::default();
        assert!(results.snapshot().is_empty());
        let store = |value| match results.store(value) {
            Ok(stored) => stored,
            Err(_) => panic!("not stored"),
        };

        // Short results are shown in full.
        assert_eq!(
            store(ResultValue::Text("OK".to_string())),
            "Stored in `$results[1]` for run_script as a string. Here is all of it:\nOK"
        );
        assert_eq!(
            store(ResultValue::Json(json!({"ok": true}))),
            "Stored in `$results[2]` for run_script as parsed JSON. Here is all of \
            it:\n{\"ok\":true}"
        );
        // Texts up to more characters than JSON.
        let text = |chars| format!("one\n{}", "é".repeat(chars - 4));
        let stored = store(ResultValue::Text(text(MAX_SHOWN_TEXT_CHARS)));
        assert!(stored.ends_with(&text(MAX_SHOWN_TEXT_CHARS)), "{stored}");
        // Serialized with the quotes.
        let json = Value::String("é".repeat(MAX_SHOWN_JSON_CHARS - 2));
        let stored = store(ResultValue::Json(json.clone()));
        assert!(stored.ends_with(&json.to_string()), "{stored}");

        // Longer ones are only described.
        assert_eq!(
            store(ResultValue::Text(text(MAX_SHOWN_TEXT_CHARS + 1))),
            "Stored in `$results[5]`. You don't see it: read or process it with run_script. It \
            is a string of 16001 characters in 2 lines."
        );
        // 8001 characters.
        assert_eq!(
            store(ResultValue::Json(Value::Array(vec![json!({"a": 1}); 1000]))),
            "Stored in `$results[6]`. You don't see it: read or process it with run_script. It \
            is parsed from JSON (7.8 KB, an array of 1000 items), of this TypeScript type:\n\
            { a: number }[]"
        );

        let snapshot = results.snapshot();
        assert_eq!(snapshot.len(), 6);
        assert!(matches!(snapshot[0].as_deref(), Some(StoredResult::Text(text)) if text == "OK"));
        assert!(
            matches!(snapshot[1].as_deref(), Some(StoredResult::Json(json)) if json == "{\"ok\":true}")
        );
    }

    #[test]
    fn drops_the_oldest_results() {
        let results = StoredResults::default();
        let large = || ResultValue::Text("x".repeat(MAX_INPUT_BYTES - 10));
        for _ in 0..3 {
            assert!(results.store(large()).is_ok());
        }
        let kept: Vec<bool> = results.snapshot().iter().map(Option::is_some).collect();
        assert_eq!(kept, [false, true, true]);
        assert_eq!(
            dropped_message(1),
            "Result 1 is no longer stored, the results of this answer took more than 32.0 MB. \
            Call the tool again."
        );
    }

    #[test]
    fn refuses_too_large_results() {
        let results = StoredResults::default();
        let expected = "The tool ran, but its result is too large to store (17.0 MB), the limit \
            is 16.0 MB. If the tool only reads, call it again and ask for less, e.g. with a \
            filter or smaller pages.";
        let text = "x".repeat(MAX_INPUT_BYTES + 1024 * 1024);
        // Not an error, since the call succeeded.
        match results.store(ResultValue::Text(text.clone())) {
            Ok(message) => assert_eq!(message, expected),
            Err(_) => panic!("not an error"),
        }
        // JSON by its serialized size, with the quotes.
        let json = ResultValue::Json(Value::String(text[2..].to_string()));
        match results.store(json) {
            Ok(message) => assert_eq!(message, expected),
            Err(_) => panic!("not an error"),
        }
        assert!(results.snapshot().is_empty());
    }
}
