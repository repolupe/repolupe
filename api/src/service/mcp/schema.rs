//! The tools of a server as stored: limited in number and size, with argument schemas the LLM
//! APIs accept.

use crate::model::mcp_server::McpTool;
use crate::service::tools::{MAX_DEFINITION_BYTES, definition_bytes};
use rmcp::model::Tool;
use serde_json::{Map, Value};
use uuid::Uuid;

/// Tools of a server beyond this are left out, so they don't crowd the prompt.
const MAX_TOOLS: usize = 100;
/// Longer descriptions of tools are cut.
const MAX_DESCRIPTION_CHARS: usize = 2_000;
/// Tools with larger argument schemas are left out.
const MAX_SCHEMA_BYTES: usize = 64 * 1024;
/// Tools of a server beyond this many bytes of definitions together are left out, so each
/// answer parses at most this much of each server. Four times what an answer gets of all
/// servers together, so turning off tools still leaves others to fill that, and far below
/// [`MAX_TOOLS`] times [`MAX_SCHEMA_BYTES`].
const MAX_SERVER_DEFINITION_BYTES: usize = 4 * MAX_DEFINITION_BYTES;

/// The tools as stored: at most [`MAX_TOOLS`], with definitions of at most
/// [`MAX_SERVER_DEFINITION_BYTES`] together. A tool too large for the bytes left is left out,
/// the following ones may still fit.
pub(super) fn stored_tools(tools: Vec<Tool>, server_id: Uuid) -> Vec<McpTool> {
    let mut bytes = 0;
    tools
        .into_iter()
        .filter_map(|tool| stored_tool(tool, server_id))
        .filter(|tool| {
            let size = tool.definition_bytes;
            if bytes + size > MAX_SERVER_DEFINITION_BYTES {
                tracing::info!(
                    "Leaving out the tool {} of MCP server {server_id}, too many bytes of \
                    definitions altogether",
                    tool.name
                );
                return false;
            }
            bytes += size;
            true
        })
        .take(MAX_TOOLS)
        .collect()
}

/// The tool as stored, `None` for tools the model cannot get.
fn stored_tool(tool: Tool, server_id: Uuid) -> Option<McpTool> {
    let Some(input_schema) = object_schema((*tool.input_schema).clone()) else {
        tracing::info!(
            "Leaving out the tool {} of MCP server {server_id}, its arguments are no object",
            tool.name
        );
        return None;
    };
    let size = serde_json::to_vec(&input_schema).map_or(usize::MAX, |json| json.len());
    if size > MAX_SCHEMA_BYTES {
        tracing::info!(
            "Leaving out the tool {} of MCP server {server_id}, its schema has {size} bytes",
            tool.name
        );
        return None;
    }
    let description = tool.description.map(|description| {
        let description = description.trim();
        match description.char_indices().nth(MAX_DESCRIPTION_CHARS) {
            Some((end, _)) => format!("{}…", &description[..end]),
            None => description.to_string(),
        }
    });
    let title = tool
        .title
        .or_else(|| tool.annotations.and_then(|annotations| annotations.title));
    let mut tool = McpTool {
        name: tool.name.into_owned(),
        title,
        description,
        input_schema,
        definition_bytes: 0,
    };
    tool.definition_bytes = definition_bytes(&tool, size);
    Some(tool)
}

/// `schema` as the LLM APIs accept it: of type `object`, without `allOf`, `anyOf` or `oneOf`
/// at the top. Their variants are merged into the schema, so the model sees all arguments,
/// and the server checks how they combine. `None` for a schema of another type.
fn object_schema(mut schema: Map<String, Value>) -> Option<Map<String, Value>> {
    match schema.get("type") {
        None => {}
        Some(Value::String(t)) if t == "object" => {}
        // Such as ["object", "null"]: the arguments are always sent as an object.
        Some(Value::Array(types)) if types.iter().any(|t| t == "object") => {}
        Some(_) => return None,
    }
    schema.insert("type".to_string(), Value::from("object"));
    for (keyword, all) in [("allOf", true), ("anyOf", false), ("oneOf", false)] {
        if let Some(Value::Array(variants)) = schema.remove(keyword) {
            merge_variants(&mut schema, &variants, all);
        }
    }
    Some(schema)
}

/// Adds the properties of the `variants` to those of `schema`, which keeps its own. A property
/// several variants define differently gets those definitions as `allOf` if `all` variants
/// apply, as `anyOf` otherwise. Required are the properties that any variant requires if `all`
/// apply, otherwise those that every variant requires.
fn merge_variants(schema: &mut Map<String, Value>, variants: &[Value], all: bool) {
    let mut definitions: Vec<(&String, Vec<&Value>)> = Vec::new();
    let mut required: Option<Vec<&str>> = None;
    for variant in variants {
        // A variant that is no inline object schema (such as a `$ref`) adds no properties,
        // but may let all of them be left out.
        let variant = variant.as_object();
        if let Some(Value::Object(properties)) = variant.and_then(|v| v.get("properties")) {
            for (name, definition) in properties {
                match definitions.iter_mut().find(|(n, _)| *n == name) {
                    Some((_, list)) if list.contains(&definition) => {}
                    Some((_, list)) => list.push(definition),
                    None => definitions.push((name, vec![definition])),
                }
            }
        }
        let names = variant.map(required_names).unwrap_or_default();
        required = Some(match required {
            None => names,
            Some(mut merged) if all => {
                for name in names {
                    if !merged.contains(&name) {
                        merged.push(name);
                    }
                }
                merged
            }
            Some(mut merged) => {
                merged.retain(|n| names.contains(n));
                merged
            }
        });
    }
    let mut merged_required: Vec<Value> = required
        .unwrap_or_default()
        .into_iter()
        .map(Value::from)
        .collect();
    let mut properties = match schema.remove("properties") {
        Some(Value::Object(properties)) => properties,
        _ => Map::new(),
    };
    for (name, list) in definitions {
        if properties.contains_key(name) {
            continue;
        }
        let definition = match list.as_slice() {
            [definition] => (*definition).clone(),
            list => {
                let keyword = if all { "allOf" } else { "anyOf" };
                let list = list.iter().map(|d| (*d).clone()).collect();
                Value::Object(Map::from_iter([(keyword.to_string(), Value::Array(list))]))
            }
        };
        properties.insert(name.clone(), definition);
    }
    if !properties.is_empty() {
        schema.insert("properties".to_string(), Value::Object(properties));
    }
    if let Some(Value::Array(own)) = schema.get("required") {
        merged_required.retain(|n| !own.contains(n));
        merged_required.splice(0..0, own.iter().cloned());
    }
    if !merged_required.is_empty() {
        schema.insert("required".to_string(), Value::Array(merged_required));
    }
}

fn required_names(schema: &Map<String, Value>) -> Vec<&str> {
    match schema.get("required") {
        Some(Value::Array(names)) => names.iter().filter_map(Value::as_str).collect(),
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Arc;

    fn normalized(schema: Value) -> Option<Value> {
        object_schema(schema.as_object().unwrap().clone()).map(Value::Object)
    }

    #[test]
    fn caps_the_definitions_of_a_server() {
        let tool = |name: String, padding: usize| {
            let schema = json!({"type": "object", "description": "x".repeat(padding)});
            Tool::new(
                name,
                "Does things.",
                Arc::new(schema.as_object().unwrap().clone()),
            )
        };
        // Of some 60 KiB each, of which 8 fit.
        let mut tools: Vec<Tool> = (0..9)
            .map(|n| tool(format!("large{n}"), 60 * 1024))
            .collect();
        tools.push(tool("small".to_string(), 0));
        let stored = stored_tools(tools, Uuid::now_v7());
        let names: Vec<&str> = stored.iter().map(|t| t.name.as_str()).collect();
        let mut expected: Vec<String> = (0..8).map(|n| format!("large{n}")).collect();
        expected.push("small".to_string());
        assert_eq!(names, expected);
        let total: usize = stored.iter().map(|t| t.definition_bytes).sum();
        assert!(total <= MAX_SERVER_DEFINITION_BYTES);
        // As the answers would measure it.
        let schema = serde_json::to_vec(&stored[0].input_schema).unwrap().len();
        assert_eq!(
            stored[0].definition_bytes,
            definition_bytes(&stored[0], schema)
        );
        assert!(schema > 60 * 1024);
    }

    #[test]
    fn keeps_object_schemas() {
        let schema = json!({
            "type": "object",
            "properties": {"q": {"type": "string"}},
            "required": ["q"],
        });
        assert_eq!(normalized(schema.clone()), Some(schema));
        assert_eq!(normalized(json!({})), Some(json!({"type": "object"})));
        assert_eq!(
            normalized(json!({"type": ["object", "null"]})),
            Some(json!({"type": "object"}))
        );
    }

    #[test]
    fn leaves_out_other_types() {
        assert_eq!(normalized(json!({"type": "string"})), None);
        assert_eq!(normalized(json!({"type": ["array", "null"]})), None);
    }

    #[test]
    fn merges_alternatives() {
        let schema = json!({
            "type": "object",
            "properties": {"dry_run": {"type": "boolean"}},
            "anyOf": [
                {
                    "type": "object",
                    "properties": {"kind": {"const": "id"}, "id": {"type": "integer"}},
                    "required": ["kind", "id"],
                    "additionalProperties": false,
                },
                {
                    "type": "object",
                    "properties": {"kind": {"const": "url"}, "url": {"type": "string"}},
                    "required": ["kind", "url"],
                },
            ],
        });
        assert_eq!(
            normalized(schema),
            Some(json!({
                "type": "object",
                "properties": {
                    "dry_run": {"type": "boolean"},
                    "kind": {"anyOf": [{"const": "id"}, {"const": "url"}]},
                    "id": {"type": "integer"},
                    "url": {"type": "string"},
                },
                "required": ["kind"],
            }))
        );
    }

    #[test]
    fn requires_nothing_of_alternatives_by_reference() {
        let schema = json!({
            "oneOf": [
                {"properties": {"id": {"type": "integer"}}, "required": ["id"]},
                {"$ref": "#/$defs/ByUrl"},
            ],
            "$defs": {"ByUrl": {"type": "object"}},
        });
        assert_eq!(
            normalized(schema),
            Some(json!({
                "type": "object",
                "properties": {"id": {"type": "integer"}},
                "$defs": {"ByUrl": {"type": "object"}},
            }))
        );
    }

    #[test]
    fn merges_all_parts() {
        let schema = json!({
            "type": "object",
            "required": ["a"],
            "allOf": [
                {"properties": {"a": {"type": "string"}, "b": {"minimum": 0}}, "required": ["a"]},
                {"properties": {"b": {"maximum": 9}}, "required": ["b"]},
            ],
        });
        assert_eq!(
            normalized(schema),
            Some(json!({
                "type": "object",
                "properties": {
                    "a": {"type": "string"},
                    "b": {"allOf": [{"minimum": 0}, {"maximum": 9}]},
                },
                "required": ["a", "b"],
            }))
        );
    }
}
