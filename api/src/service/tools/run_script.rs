//! [`RUN_SCRIPT`]: JavaScript the model writes to calculate, count or transform data, run in
//! the sandbox of [`super::support::sandbox`]. The script only sees what it is given: the files
//! it asks for in `files`, read from the pinned commit before it starts, as `$files`, the
//! attachments it asks for in `attachments` as `$attachments`, the stored results of tool calls
//! as `$results` (see [`super::support::results`]), loaded when the script first reads them,
//! and `console` to print. The globals start with `$`, so they don't collide with the script's
//! own variables. At most [`MAX_SCRIPTS`] scripts run at once.

use super::support::sandbox::{self, Inputs};
use super::support::{file_path_schema, normalize_path, parse_args, read_text, repository_schema};
use super::{
    Call, Invocation, READ_ATTACHMENT, RUN_SCRIPT, RepositoryTools, ToolError, ToolOutput,
    read_attachment,
};
use crate::config::error::AppError;
use crate::service::llm::ToolDefinition;
use serde::Deserialize;
use serde_json::{Value as Json, json};
use tokio::sync::Semaphore;

/// Files and attachments of a call together.
const MAX_INPUTS: usize = 20;
/// Scripts running at once in this process. Each may use the memory the sandbox allows plus its
/// files, so without a limit many calls in one round, or several chats at once, could run the
/// server or the local instance out of memory.
const MAX_SCRIPTS: usize = 2;
static SCRIPT_SLOTS: Semaphore = Semaphore::const_new(MAX_SCRIPTS);

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    let mut description = String::from(
        "Run JavaScript (ES2023) to calculate, count, sort, or transform data. Print results \
        with `console.log`; the value of the last expression is returned too. The script runs \
        in a sandbox: there is no network, no file system, no `require`, `import`, `fetch` or \
        timers, and nothing carries over between calls. Numbers are 64-bit floats, so use \
        BigInt for exact large integers and round amounts of money when printing them.",
    );
    let mut properties = json!({
        "code": {
            "type": "string",
            "description": "The script, e.g. `const prices = [19.99, 5.49]; \
                prices.reduce((a, b) => a + b, 0).toFixed(2)`.",
        },
    });
    let has_files = !tools.repositories.is_empty();
    let has_attachments = tools.can_read_attachments();
    if has_files {
        description.push_str(
            " To compute with files of a repository, e.g. sum up a column of a CSV file, list \
            them in `files`: their text is in the global object `$files`, keyed by path, e.g. \
            `$files['data/prices.csv']`.",
        );
        properties["files"] = json!({
            "type": "array",
            "items": file_path_schema(),
            "maxItems": MAX_INPUTS,
            "description": "Files to pass to the script.",
        });
        properties["repository"] = repository_schema(tools);
    }
    if has_attachments {
        description.push_str(&format!(
            " To compute with files the user attached to the chat, list their numbers in \
            `attachments` instead of reading them with {READ_ATTACHMENT} and copying the data \
            into the script: their text is in the global object `$attachments`, keyed by \
            number, e.g. `$attachments[1]`."
        ));
        properties["attachments"] = json!({
            "type": "array",
            "items": {"type": "integer", "enum": tools.attachments.numbers()},
            "maxItems": MAX_INPUTS,
            "description": "Numbers of the attachments to pass to the script.",
        });
    }
    if has_files || has_attachments {
        description.push_str(" PDFs are passed as Markdown converted from them.");
    }
    if tools.mcp.has_tools() {
        description.push_str(
            " The results of the `mcp__` tools are in the global object `$results`, keyed by \
            number, e.g. `$results[1]`, as text, or parsed if they are JSON: process long ones \
            here and print only what you need. A result is stored once its call is complete, so \
            use it in a later response than the call.",
        );
    }
    ToolDefinition {
        name: RUN_SCRIPT.to_string(),
        description,
        input_schema: json!({
            "type": "object",
            "properties": properties,
            "required": ["code"],
        }),
    }
}

/// The lists are optional, models sometimes pass `null` for them.
#[derive(Deserialize)]
struct Input {
    code: String,
    files: Option<Vec<String>>,
    attachments: Option<Vec<i32>>,
}

pub(super) struct Args {
    code: String,
    files: Vec<String>,
    /// Numbers of attachments.
    attachments: Vec<i32>,
}

impl Args {
    /// Whether the call reads a repository, which then must be resolved.
    pub(super) fn reads_files(&self) -> bool {
        !self.files.is_empty()
    }
}

pub(super) fn parse(input: &Json) -> Result<Call, String> {
    let input: Input = parse_args(RUN_SCRIPT, input)?;
    if input.code.trim().is_empty() {
        return Err("`code` must not be empty.".to_string());
    }
    let input_files = input.files.unwrap_or_default();
    let input_attachments = input.attachments.unwrap_or_default();
    let count = input_files.len() + input_attachments.len();
    if count > MAX_INPUTS {
        return Err(format!(
            "Pass at most {MAX_INPUTS} files and attachments together, not {count}."
        ));
    }
    let mut files = Vec::new();
    for path in input_files {
        // The paths are the keys in `$files`, so they must be written as the script reads them.
        let normalized = normalize_path(&path)?;
        if normalized.is_empty() {
            return Err(format!("`files` takes paths of files, not `{path}`."));
        }
        if normalized != path {
            return Err(format!(
                "`files` takes paths relative to the repository root, write `{normalized}` \
                instead of `{path}`."
            ));
        }
        if !files.contains(&path) {
            files.push(path);
        }
    }
    let mut attachments = Vec::new();
    for number in input_attachments {
        if !attachments.contains(&number) {
            attachments.push(number);
        }
    }
    let args = Args {
        code: input.code,
        files,
        attachments,
    };
    Ok(Call::RunScript(args))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<ToolOutput, ToolError> {
    let attachments = invocation.attachments;
    // Before a slot is taken, so a call waiting for a document doesn't keep others from running.
    for &number in &args.attachments {
        read_attachment::wait_for_conversion(attachments, invocation.db, number).await?;
    }
    // Before the files are read, so calls that wait don't hold them.
    let permit = SCRIPT_SLOTS.acquire().await.map_err(|_| {
        AppError::InternalServerError("The script semaphore is closed.".to_string())
    })?;
    let mut inputs = Inputs::default();
    // What the model should know about them, e.g. that they were recognized with OCR.
    let mut notes = Vec::new();
    if args.reads_files() {
        let repository = invocation.target()?;
        for path in &args.files {
            let text = read_text(repository, invocation.db, path).await?;
            inputs.add_file(path.clone(), text.content)?;
            notes.extend(text.note);
        }
    }
    for &number in &args.attachments {
        let text = read_attachment::read_text(attachments, invocation.db, number).await?;
        inputs.add_attachment(number, text.content)?;
        notes.extend(text.note);
    }
    if invocation.mcp.has_tools() {
        inputs.results = Some(invocation.results.snapshot());
    }
    let code = args.code.clone();
    // The permit moves into the thread, which keeps running until the deadline even if the
    // generation is cancelled and this future dropped.
    let output = tokio::task::spawn_blocking(move || {
        let _permit = permit;
        #[cfg(test)]
        let _running = tests::Running::start();
        sandbox::execute(&code, &inputs)
    })
    .await
    .map_err(|e| AppError::InternalServerError(format!("The script panicked: {e}")))??;
    notes.push(output);
    Ok(ToolOutput::text(notes.join("\n\n")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::llm::ToolUse;
    use crate::service::tools::mcp::McpTools;
    use crate::service::tools::support::MAX_OUTPUT_CHARS;
    use crate::service::tools::support::fixture::{Fixture, identities};
    use crate::service::tools::support::results::ResultValue;
    use crate::service::tools::{ToolOutput, unused_db};
    use std::sync::atomic::{AtomicUsize, Ordering};

    static RUNNING: AtomicUsize = AtomicUsize::new(0);
    static PEAK: AtomicUsize = AtomicUsize::new(0);

    /// Counts the scripts running at once, across all tests.
    pub(super) struct Running;

    impl Running {
        pub(super) fn start() -> Self {
            let running = RUNNING.fetch_add(1, Ordering::SeqCst) + 1;
            PEAK.fetch_max(running, Ordering::SeqCst);
            Running
        }
    }

    impl Drop for Running {
        fn drop(&mut self) {
            RUNNING.fetch_sub(1, Ordering::SeqCst);
        }
    }

    /// Runs a script in a chat without repositories.
    async fn script(code: &str) -> ToolOutput {
        let tools = RepositoryTools::new(Vec::new(), unused_db(), identities());
        script_with(&tools, code).await
    }

    async fn script_with(tools: &RepositoryTools, code: &str) -> ToolOutput {
        let tool_use = ToolUse {
            id: "call".to_string(),
            name: RUN_SCRIPT.to_string(),
            input: json!({"code": code}),
            native: None,
        };
        match tools.parse(&tool_use) {
            Ok(invocation) => invocation.run().await,
            Err(content) => ToolOutput::error(content),
        }
    }

    async fn ok(code: &str) -> String {
        let output = script(code).await;
        assert!(!output.is_error, "{}", output.content);
        output.content
    }

    async fn error(code: &str) -> String {
        let output = script(code).await;
        assert!(output.is_error, "{}", output.content);
        output.content
    }

    #[tokio::test]
    async fn returns_output_and_result() {
        assert_eq!(ok("1 + 2").await, "Result: 3");
        assert_eq!(
            ok("const total = [19.99, 5.49].reduce((a, b) => a + b, 0);\n\
                console.log('Total:', total.toFixed(2));\ntotal > 20")
            .await,
            "Total: 25.48\n\nResult: true"
        );
        assert_eq!(
            ok("console.log({a: [1, 'b', null], 'c d': new Map([[1, 2n]])}, new Set([1]))").await,
            "{ a: [1, \"b\", null], \"c d\": Map(1) {1 => 2n} } Set(1) {1}"
        );
        assert_eq!(
            ok("2n ** 100n").await,
            "Result: 1267650600228229401496703205376n"
        );
        assert_eq!(
            ok("const o = {}; o.self = o; o").await,
            "Result: { self: [Circular] }"
        );
        assert_eq!(
            ok("let x = 1").await,
            "(no output, print results with console.log)"
        );
    }

    #[tokio::test]
    async fn waits_for_promises() {
        assert_eq!(
            ok("async function main() { await null; console.log('done'); return 42; }\nmain()")
                .await,
            "done\n\nResult: 42"
        );
        assert_eq!(
            error("(async () => { throw new TypeError('nope'); })()").await,
            "Uncaught TypeError: nope\n    at <anonymous> (script.js:1:26)\n    at <eval> (script.js:1:44)"
        );
        assert_eq!(
            ok("new Promise(() => {})").await,
            "(no output, print results with console.log)"
        );
    }

    #[tokio::test]
    async fn reports_errors() {
        assert_eq!(
            error("console.log('before');\nundefinedFunction()").await,
            "before\n\nUncaught ReferenceError: undefinedFunction is not defined\n    at <eval> (script.js:2:1)"
        );
        assert_eq!(error("throw 'plain'").await, "Uncaught plain");
        assert!(
            error("const = 1")
                .await
                .starts_with("Uncaught SyntaxError:")
        );
        assert!(
            error("const f = (n) => f(n + 1); f(0)")
                .await
                .contains("Maximum call stack size exceeded")
        );
    }

    #[tokio::test]
    async fn has_no_io() {
        for code in [
            "require('fs')",
            "fetch('https://example.com')",
            "setTimeout(() => {}, 1)",
            "std.loadFile('/etc/passwd')",
            "os.exec(['ls'])",
        ] {
            assert!(
                error(code).await.contains("is not defined"),
                "{code} should not be available"
            );
        }
        assert!(error("import('fs')").await.contains("fs"));
    }

    #[tokio::test]
    async fn limits_resources() {
        let stopped =
            "The script was stopped after 5 s. Make it faster, e.g. with fewer iterations.";
        // Endless chains of short jobs, waited for or not. Concurrently, since each takes 5 s.
        let chain = "const f = () => { Promise.resolve().then(f); }; f();";
        let waited = format!("{chain} new Promise(() => {{}})");
        // Its result is large enough that the interrupt handler would stop formatting it.
        let not_waited = format!("{chain} new Array(5000).fill(0)");
        let (waited, not_waited, endless) = tokio::join!(
            error(&waited),
            ok(&not_waited),
            error("console.log('start'); while (true) {}"),
        );
        assert_eq!(waited, stopped);
        assert!(not_waited.starts_with("Result: [0, 0, "), "{not_waited}");
        assert_eq!(endless, format!("start\n\n{stopped}"));
        // An error is not a timeout, even if the jobs the script did not wait for are endless.
        assert_eq!(
            error(&format!("{chain}\nundefinedFunction()")).await,
            "Uncaught ReferenceError: undefinedFunction is not defined\n    at <eval> (script.js:2:1)"
        );
        assert_eq!(
            error("const a = []; while (true) a.push('x'.repeat(1000) + a.length);").await,
            "The script ran out of memory, it may use at most 128.0 MB."
        );
        // Also when the memory is freed before the error is reported, and when QuickJS can
        // still create the error.
        for code in [
            "(() => { const a = []; while (true) a.push(new Array(1000).fill(a.length)); })()",
            "try { 'x'.repeat(2 ** 29) } catch { 'caught' }",
            "const f = () => Promise.resolve().then(f); f()",
            "'x'.repeat(2 ** 29)",
            "new ArrayBuffer(2 ** 30)",
        ] {
            assert_eq!(
                error(code).await,
                "The script ran out of memory, it may use at most 128.0 MB.",
                "{code}"
            );
        }
        assert_eq!(ok("new Array(1000).fill(1).length").await, "Result: 1000");
        let long = ok("for (let i = 0; i < 100000; i++) console.log('line ' + i)").await;
        assert!(long.ends_with(&format!(
            "… [Output cut after {MAX_OUTPUT_CHARS} characters.]"
        )));
        assert!(long.chars().count() < MAX_OUTPUT_CHARS + 100);
        // The result and errors are cut too, on their own.
        for (output, what) in [
            (
                ok("console.log('x'.repeat(1e5)); 'y'.repeat(1e5)").await,
                "Result",
            ),
            (error("throw 'y'.repeat(1e5)").await, "Error"),
        ] {
            let note = format!("… [{what} cut after {MAX_OUTPUT_CHARS} characters.]");
            assert!(output.ends_with(&format!("yyy{note}")), "{what}");
            assert!(
                output.chars().count() < 2 * MAX_OUTPUT_CHARS + 200,
                "{what}"
            );
        }
    }

    #[tokio::test]
    async fn limits_concurrent_scripts() {
        let busy = "const end = Date.now() + 300; while (Date.now() < end);";
        let scripts = (0..MAX_SCRIPTS * 2).map(|_| ok(busy));
        futures_util::future::join_all(scripts).await;
        assert!(PEAK.load(Ordering::SeqCst) <= MAX_SCRIPTS);
    }

    #[tokio::test]
    async fn passes_files() {
        let fixture = Fixture::new(&[
            ("data/prices.csv", b"item,price\napple,1.20\npear,0.85\n"),
            ("logo.png", b"\x89PNG\r\n\x1a\n\0\0\0"),
        ]);
        let sum = "$files['data/prices.csv'].trim().split('\\n').slice(1)\
            .map((line) => Number(line.split(',')[1])).reduce((a, b) => a + b, 0).toFixed(2)";
        assert_eq!(
            fixture
                .ok(
                    RUN_SCRIPT,
                    json!({"code": sum, "files": ["data/prices.csv"]})
                )
                .await,
            "Result: 2.05"
        );
        assert_eq!(
            fixture
                .error(RUN_SCRIPT, json!({"code": "1", "files": ["logo.png"]}))
                .await,
            "`logo.png` is a binary file and can't be shown."
        );
        assert_eq!(
            fixture
                .error(
                    RUN_SCRIPT,
                    json!({"code": "1", "files": ["data/missing.csv"]})
                )
                .await,
            "File or directory not found: `data/missing.csv`. Use list_files to see the files."
        );
        assert_eq!(
            fixture
                .error(RUN_SCRIPT, json!({"code": "$files", "files": []}))
                .await,
            "Uncaught ReferenceError: $files is not defined\n    at <eval> (script.js:1:1)"
        );
    }

    #[tokio::test]
    async fn passes_results() {
        let mut tools = RepositoryTools::new(Vec::new(), unused_db(), identities());
        // Without MCP tools there are no results.
        assert_eq!(
            script_with(&tools, "$results").await.content,
            "Uncaught ReferenceError: $results is not defined\n    at <eval> (script.js:1:1)"
        );
        assert!(!tools.definitions()[0].description.contains("$results"));

        tools.mcp = McpTools::unconnected("Docs", &["search"]);
        let definitions = tools.definitions();
        let definition = definitions.iter().find(|d| d.name == RUN_SCRIPT).unwrap();
        assert!(definition.description.contains("`$results[1]`"));
        assert!(definition.input_schema["properties"]["results"].is_null());
        // Also before a tool stored one.
        let ok = async |code: &str| {
            let output = script_with(&tools, code).await;
            assert!(!output.is_error, "{}", output.content);
            output.content
        };
        assert_eq!(ok("Object.keys($results)").await, "Result: []");

        let text = ResultValue::Text("one\ntwo".to_string());
        assert!(tools.results.store(text).is_ok());
        let json = ResultValue::Json(json!({"items": [{"price": 1.5}, {"price": 2}]}));
        assert!(tools.results.store(json).is_ok());
        let sum = "$results[1].split('\\n').length \
            + $results[2].items.reduce((sum, item) => sum + item.price, 0)";
        assert_eq!(ok(sum).await, "Result: 5.5");
        assert_eq!(ok("Object.keys($results)").await, "Result: [\"1\", \"2\"]");
        assert_eq!(
            ok("$results[3]").await,
            "(no output, print results with console.log)"
        );
        // Loaded once, and the script may change them or use the names itself.
        assert_eq!(
            ok("$results[2].items.pop(); $results[2].items.length").await,
            "Result: 1"
        );
        assert_eq!(ok("$results[1] = 'x'; $results[1]").await, "Result: x");
        assert_eq!(
            ok("const $results = [1]; $results.length").await,
            "Result: 1"
        );
    }

    #[tokio::test]
    async fn validates_input() {
        let tools = RepositoryTools::new(Vec::new(), unused_db(), identities());
        let parse = |input: Json| {
            tools
                .parse(&ToolUse {
                    id: String::new(),
                    name: RUN_SCRIPT.to_string(),
                    input,
                    native: None,
                })
                .err()
        };
        assert_eq!(
            parse(json!({"code": " "})).unwrap(),
            "`code` must not be empty."
        );
        assert_eq!(
            parse(json!({"code": "1", "files": ["a.csv"]})).unwrap(),
            "No repositories are available in this chat."
        );
        assert!(parse(json!({"code": "1"})).is_none());
        // Models sometimes pass `null` for lists they don't need.
        assert!(parse(json!({"code": "1", "files": null, "attachments": null})).is_none());
        // Attachments need no repository, unknown numbers are reported when the call runs.
        assert!(parse(json!({"code": "1", "attachments": [1, 1]})).is_none());
        let paths: Vec<String> = (0..15).map(|i| format!("{i}.csv")).collect();
        assert_eq!(
            parse(json!({"code": "1", "files": paths, "attachments": [1, 2, 3, 4, 5, 6]})).unwrap(),
            "Pass at most 20 files and attachments together, not 21."
        );
        for (path, error) in [
            (
                "./data/prices.csv",
                "`files` takes paths relative to the repository root, write `data/prices.csv` \
                instead of `./data/prices.csv`.",
            ),
            (
                "/data//prices.csv ",
                "`files` takes paths relative to the repository root, write `data/prices.csv` \
                instead of `/data//prices.csv `.",
            ),
            ("/", "`files` takes paths of files, not `/`."),
            ("data/../a.csv", "Paths must not contain `..`."),
        ] {
            assert_eq!(
                parse(json!({"code": "1", "files": [path]})).unwrap(),
                error,
                "{path}"
            );
        }

        // Without repositories there are no files to pass.
        let definitions = tools.definitions();
        assert_eq!(definitions.len(), 1);
        assert!(definitions[0].input_schema["properties"]["files"].is_null());
        assert!(definitions[0].input_schema["properties"]["attachments"].is_null());
        assert!(!definitions[0].description.contains("PDFs"));
    }
}
