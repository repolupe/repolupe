//! [`RUN_SCRIPT`]: JavaScript the model writes to calculate, count or transform data, run by
//! QuickJS in the API process. QuickJS has no I/O of its own (no `std` or `os` modules), so the
//! script only sees what it is given: the files it asks for in `files`, read from the pinned
//! commit before it starts, and `console` to print. Each call gets its own runtime, limited in
//! memory, stack and time, so calls share no state.

use super::support::{
    MAX_OUTPUT_CHARS, file_path_schema, format_size, normalize_path, parse_args, read_text,
    repository_schema,
};
use super::{Call, Invocation, RUN_SCRIPT, RepositoryTools, ToolError};
use crate::config::error::AppError;
use crate::service::llm::ToolDefinition;
use rquickjs::allocator::{Allocator, RustAllocator};
use rquickjs::context::EvalOptions;
use rquickjs::promise::PromiseState;
use rquickjs::{CatchResultExt, CaughtError, Context, Ctx, Function, Object, Runtime, Value};
use serde::Deserialize;
use serde_json::{Value as Json, json};
use std::cell::{Cell, RefCell};
use std::ptr;
use std::rc::Rc;
use std::time::{Duration, Instant};

const MAX_DURATION: Duration = Duration::from_secs(5);
const MAX_MEMORY: usize = 64 * 1024 * 1024;
/// Below the 2 MiB of the threads of `spawn_blocking`, so deep recursion is a `RangeError`
/// instead of a stack overflow.
const MAX_STACK: usize = 512 * 1024;
const MAX_FILES: usize = 20;
/// Of all files of a call together, so they fit into [`MAX_MEMORY`] as UTF-16.
const MAX_FILES_BYTES: usize = 16 * 1024 * 1024;
const FILE_NAME: &str = "script.js";

/// Installs `console`, which writes with `print`, and returns the function that formats values
/// for it, which also formats the result and errors. Evaluated before the script, so the
/// script can't change it.
const PRELUDE: &str = r#"
(print) => {
  const name = (key) => /^[A-Za-z_$][\w$]*$/.test(key) ? key : JSON.stringify(key);
  const inspect = (value, nested = false, seen = new Set()) => {
    switch (typeof value) {
      case 'string': return nested ? JSON.stringify(value) : value;
      case 'bigint': return `${value}n`;
      case 'function': return `[Function ${value.name || 'anonymous'}]`;
      case 'symbol': return value.toString();
      case 'number': return Object.is(value, -0) ? '-0' : String(value);
      case 'undefined':
      case 'boolean': return String(value);
    }
    if (value === null) return 'null';
    if (seen.has(value)) return '[Circular]';
    seen.add(value);
    try {
      const inner = (v) => inspect(v, true, seen);
      if (value instanceof Error) {
        const stack = typeof value.stack === 'string' ? value.stack.trimEnd() : '';
        return stack ? `${value}\n${stack}` : String(value);
      }
      if (value instanceof Date) return isNaN(value) ? 'Invalid Date' : value.toISOString();
      if (value instanceof RegExp) return String(value);
      if (Array.isArray(value)) return `[${value.map(inner).join(', ')}]`;
      if (value instanceof Map) {
        const entries = [...value].map(([k, v]) => `${inner(k)} => ${inner(v)}`);
        return `Map(${value.size}) {${entries.join(', ')}}`;
      }
      if (value instanceof Set) return `Set(${value.size}) {${[...value].map(inner).join(', ')}}`;
      if (ArrayBuffer.isView(value)) return `${value.constructor.name} [${Array.from(value).map(inner).join(', ')}]`;
      if (value instanceof Promise) return 'Promise';
      const entries = Object.entries(value).map(([k, v]) => `${name(k)}: ${inner(v)}`);
      return entries.length ? `{ ${entries.join(', ')} }` : '{}';
    } finally {
      seen.delete(value);
    }
  };
  const log = (...args) => print(args.map((a) => inspect(a)).join(' '));
  globalThis.console = {
    log, info: log, debug: log, warn: log, error: log,
    table: (data) => print(inspect(data)),
  };
  return inspect;
}
"#;

pub(super) fn definition(tools: &RepositoryTools) -> ToolDefinition {
    let mut description = format!(
        "Run JavaScript (ES2023) to calculate, count, sort, or transform data, instead of \
        working it out in your head. Print results with `console.log`; the value of the last \
        expression is returned too. The script runs in a sandbox: there is no network, no \
        file system, no `require`, `import`, `fetch` or timers, and nothing carries over between \
        calls. It is stopped after {} s or {} of memory. Numbers are 64-bit floats, so use \
        BigInt for exact large integers and round amounts of money when printing them.",
        MAX_DURATION.as_secs(),
        format_size(MAX_MEMORY as u64),
    );
    let mut properties = json!({
        "code": {
            "type": "string",
            "description": "The script, e.g. `const prices = [19.99, 5.49]; \
                prices.reduce((a, b) => a + b, 0).toFixed(2)`.",
        },
    });
    if !tools.repositories.is_empty() {
        description.push_str(
            " To compute with files of a repository, e.g. sum up a column of a CSV file, list \
            them in `files`: their text is in the global object `files`, keyed by path, e.g. \
            `files['data/prices.csv']`. PDFs are passed as Markdown converted from them.",
        );
        properties["files"] = json!({
            "type": "array",
            "items": file_path_schema(),
            "maxItems": MAX_FILES,
            "description": "Files to pass to the script.",
        });
        properties["repository"] = repository_schema(tools);
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

#[derive(Deserialize)]
struct Input {
    code: String,
    #[serde(default)]
    files: Vec<String>,
    repository: Option<String>,
}

pub(super) struct Args {
    code: String,
    files: Vec<String>,
}

impl Args {
    /// Whether the call reads a repository, which then must be resolved.
    pub(super) fn reads_files(&self) -> bool {
        !self.files.is_empty()
    }
}

pub(super) fn parse(input: &Json) -> Result<(Option<String>, Call), String> {
    let input: Input = parse_args(RUN_SCRIPT, input)?;
    if input.code.trim().is_empty() {
        return Err("`code` must not be empty.".to_string());
    }
    if input.files.len() > MAX_FILES {
        return Err(format!(
            "Pass at most {MAX_FILES} files, not {}.",
            input.files.len()
        ));
    }
    let mut files = Vec::new();
    for path in &input.files {
        let path = normalize_path(path)?;
        if !files.contains(&path) {
            files.push(path);
        }
    }
    let args = Args {
        code: input.code,
        files,
    };
    Ok((input.repository, Call::RunScript(args)))
}

pub(super) async fn run(invocation: &Invocation<'_>, args: &Args) -> Result<String, ToolError> {
    let mut files = Vec::new();
    let mut notes = Vec::new();
    if args.reads_files() {
        let repository = invocation.target()?;
        let mut total = 0;
        for path in &args.files {
            let text = read_text(repository, invocation.db, path).await?;
            total += text.content.len();
            if total > MAX_FILES_BYTES {
                return Err(ToolError::Invalid(format!(
                    "The files are too large to pass to a script together, the limit is {}.",
                    format_size(MAX_FILES_BYTES as u64)
                )));
            }
            notes.extend(text.note);
            files.push((path.clone(), text.content));
        }
    }
    let code = args.code.clone();
    let output = tokio::task::spawn_blocking(move || execute(&code, &files))
        .await
        .map_err(|e| AppError::InternalServerError(format!("The script panicked: {e}")))??;
    notes.push(output);
    Ok(notes.join("\n\n"))
}

/// Refuses allocations beyond [`MAX_MEMORY`] and remembers it, since QuickJS may then not even
/// be able to create the error it throws. Replaces QuickJS's own limit, which only applies to
/// its default allocator.
struct LimitedAllocator {
    used: usize,
    out_of_memory: Rc<Cell<bool>>,
}

impl LimitedAllocator {
    /// Whether `size` more bytes fit, after `freed` bytes are freed.
    fn fits(&self, size: usize, freed: usize) -> bool {
        let fits = self.used - freed + size <= MAX_MEMORY;
        if !fits {
            self.out_of_memory.set(true);
        }
        fits
    }
}

// SAFETY: Delegates to `RustAllocator`, only refusing allocations by returning null, and keeps
// `realloc` and `free` of null and `realloc` to 0 bytes as in C.
unsafe impl Allocator for LimitedAllocator {
    fn alloc(&mut self, size: usize) -> *mut u8 {
        if !self.fits(size, 0) {
            return ptr::null_mut();
        }
        let allocation = RustAllocator.alloc(size);
        if !allocation.is_null() {
            // SAFETY: Allocated by `RustAllocator`.
            self.used += unsafe { RustAllocator::usable_size(allocation) };
        }
        allocation
    }

    fn calloc(&mut self, count: usize, size: usize) -> *mut u8 {
        let Some(total) = count.checked_mul(size) else {
            self.out_of_memory.set(true);
            return ptr::null_mut();
        };
        if !self.fits(total, 0) {
            return ptr::null_mut();
        }
        let allocation = RustAllocator.calloc(count, size);
        if !allocation.is_null() {
            // SAFETY: Allocated by `RustAllocator`.
            self.used += unsafe { RustAllocator::usable_size(allocation) };
        }
        allocation
    }

    unsafe fn dealloc(&mut self, allocation: *mut u8) {
        if allocation.is_null() {
            return;
        }
        // SAFETY: The caller passes an allocation of this allocator.
        unsafe {
            self.used -= RustAllocator::usable_size(allocation);
            RustAllocator.dealloc(allocation);
        }
    }

    unsafe fn realloc(&mut self, allocation: *mut u8, new_size: usize) -> *mut u8 {
        if allocation.is_null() {
            return self.alloc(new_size);
        }
        if new_size == 0 {
            // SAFETY: The caller passes an allocation of this allocator.
            unsafe { self.dealloc(allocation) };
            return ptr::null_mut();
        }
        // SAFETY: The caller passes an allocation of this allocator.
        let old_size = unsafe { RustAllocator::usable_size(allocation) };
        if !self.fits(new_size, old_size) {
            return ptr::null_mut();
        }
        // SAFETY: As above, and on failure the old allocation stays valid.
        unsafe {
            let reallocated = RustAllocator.realloc(allocation, new_size);
            if !reallocated.is_null() {
                self.used = self.used - old_size + RustAllocator::usable_size(reallocated);
            }
            reallocated
        }
    }

    unsafe fn usable_size(allocation: *mut u8) -> usize {
        // SAFETY: The caller passes an allocation of this allocator.
        unsafe { RustAllocator::usable_size(allocation) }
    }
}

/// What the script printed, at most [`MAX_OUTPUT_CHARS`].
#[derive(Default)]
struct Console {
    text: String,
    chars: usize,
    truncated: bool,
}

impl Console {
    fn print(&mut self, line: &str) {
        if self.truncated {
            return;
        }
        let separator = usize::from(!self.text.is_empty());
        let available = MAX_OUTPUT_CHARS.saturating_sub(self.chars + separator);
        let len = line.chars().count();
        if separator == 1 {
            self.text.push('\n');
        }
        if len <= available {
            self.text.push_str(line);
            self.chars += separator + len;
        } else {
            self.text.extend(line.chars().take(available));
            self.chars = MAX_OUTPUT_CHARS;
            self.truncated = true;
        }
    }

    /// The output, with `result` after it.
    fn finish(self, result: Result<Option<String>, String>) -> String {
        let mut parts = Vec::new();
        if !self.text.is_empty() {
            let mut text = self.text;
            if self.truncated {
                text.push_str(&format!(
                    "… [Output cut after {MAX_OUTPUT_CHARS} characters.]"
                ));
            }
            parts.push(text);
        }
        match result {
            Ok(Some(result)) => parts.push(format!("Result: {result}")),
            Ok(None) if parts.is_empty() => {
                parts.push("(no output, print results with console.log)".to_string());
            }
            Ok(None) => {}
            Err(error) => parts.push(error),
        }
        parts.join("\n\n")
    }
}

/// Runs `code` with `files` as the global `files`. Blocks for up to [`MAX_DURATION`].
fn execute(code: &str, files: &[(String, String)]) -> Result<String, ToolError> {
    let internal = |e: rquickjs::Error| {
        ToolError::Internal(AppError::InternalServerError(format!(
            "Could not set up the script runtime: {e}"
        )))
    };
    let out_of_memory = Rc::new(Cell::new(false));
    let allocator = LimitedAllocator {
        used: 0,
        out_of_memory: out_of_memory.clone(),
    };
    let runtime = Runtime::new_with_alloc(allocator).map_err(internal)?;
    runtime.set_max_stack_size(MAX_STACK);
    let context = Context::full(&runtime).map_err(internal)?;
    let console = Rc::new(RefCell::new(Console::default()));

    let inspect = context.with(|ctx| {
        let print = {
            let console = console.clone();
            Function::new(ctx.clone(), move |line: String| {
                console.borrow_mut().print(&line);
            })?
        };
        let install: Function = ctx.eval(PRELUDE)?;
        let inspect: Function = install.call((print,))?;
        if !files.is_empty() {
            let object = Object::new(ctx.clone())?;
            for (path, content) in files {
                object.set(path.as_str(), content.as_str())?;
            }
            ctx.globals().set("files", object)?;
        }
        Ok(rquickjs::Persistent::save(&ctx, inspect))
    });
    let inspect = inspect.map_err(internal)?;

    // The setup above is not counted against the time of the script.
    let deadline = Instant::now() + MAX_DURATION;
    runtime.set_interrupt_handler(Some(Box::new(move || Instant::now() >= deadline)));

    let result = context.with(|ctx| {
        let inspect = inspect.restore(&ctx).map_err(internal)?;
        let mut options = EvalOptions::default();
        options.strict = false;
        options.filename = Some(FILE_NAME.to_string());
        let result = ctx
            .eval_with_options::<Value, _>(code, options)
            .catch(&ctx)
            .and_then(|value| settle(&ctx, value, deadline));
        // The script may have started async functions it did not wait for.
        while Instant::now() < deadline && ctx.execute_pending_job() {}
        Ok::<_, ToolError>(match result {
            // Also if it caught the error, its result may be incomplete.
            _ if out_of_memory.get() => Err(format!(
                "The script ran out of memory, it may use at most {}.",
                format_size(MAX_MEMORY as u64)
            )),
            Ok(value) if value.is_undefined() => Ok(None),
            Ok(value) => {
                Ok(Some(inspect.call::<_, String>((value,)).unwrap_or_else(
                    |_| "(the result can't be shown)".to_string(),
                )))
            }
            Err(error) => Err(describe_error(&inspect, error, deadline)),
        })
    })?;
    let console = console.take();
    let failed = result.is_err();
    let output = console.finish(result);
    if failed {
        Err(ToolError::Invalid(output))
    } else {
        Ok(output)
    }
}

/// The value of a promise, e.g. from `main()` with `async function main()`, once the jobs it
/// waits for ran. The interrupt handler stops each job at the deadline, but not an endless
/// chain of short ones, so the loop checks it too.
fn settle<'js>(
    ctx: &Ctx<'js>,
    value: Value<'js>,
    deadline: Instant,
) -> Result<Value<'js>, CaughtError<'js>> {
    let Some(promise) = value.as_promise() else {
        return Ok(value);
    };
    while promise.state() == PromiseState::Pending
        && Instant::now() < deadline
        && ctx.execute_pending_job()
    {}
    match promise.result::<Value>() {
        Some(result) => result.catch(ctx),
        None if Instant::now() >= deadline => Err(CaughtError::Error(rquickjs::Error::Unknown)),
        // Waits for something that never happens, there are no timers or I/O.
        None => Ok(Value::new_undefined(ctx.clone())),
    }
}

fn describe_error<'js>(
    inspect: &Function<'js>,
    error: CaughtError<'js>,
    deadline: Instant,
) -> String {
    if Instant::now() >= deadline {
        return format!(
            "The script was stopped after {} s. Make it faster, e.g. with fewer iterations.",
            MAX_DURATION.as_secs()
        );
    }
    let thrown = match error {
        CaughtError::Exception(exception) => exception.into_value(),
        CaughtError::Value(value) => value,
        CaughtError::Error(e) => return format!("The script failed: {e}"),
    };
    let message = inspect
        .call::<_, String>((thrown,))
        .unwrap_or_else(|_| "unknown error".to_string());
    format!("Uncaught {message}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::llm::ToolUse;
    use crate::service::tools::support::fixture::{Fixture, identities};
    use crate::service::tools::{ToolOutput, unused_db};

    /// Runs a script in a chat without repositories.
    async fn script(code: &str) -> ToolOutput {
        let tools = RepositoryTools::new(Vec::new(), unused_db(), identities());
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
        let not_waited = format!("{chain} 1");
        let (waited, not_waited, endless) = tokio::join!(
            error(&waited),
            ok(&not_waited),
            error("console.log('start'); while (true) {}"),
        );
        assert_eq!(waited, stopped);
        assert_eq!(not_waited, "Result: 1");
        assert_eq!(endless, format!("start\n\n{stopped}"));
        assert_eq!(
            error("const a = []; while (true) a.push('x'.repeat(1000) + a.length);").await,
            "The script ran out of memory, it may use at most 64.0 MB."
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
                "The script ran out of memory, it may use at most 64.0 MB.",
                "{code}"
            );
        }
        assert_eq!(ok("new Array(1000).fill(1).length").await, "Result: 1000");
        let long = ok("for (let i = 0; i < 100000; i++) console.log('line ' + i)").await;
        assert!(long.ends_with(&format!(
            "… [Output cut after {MAX_OUTPUT_CHARS} characters.]"
        )));
        assert!(long.chars().count() < MAX_OUTPUT_CHARS + 100);
    }

    #[tokio::test]
    async fn passes_files() {
        let fixture = Fixture::new(&[
            ("data/prices.csv", b"item,price\napple,1.20\npear,0.85\n"),
            ("logo.png", b"\x89PNG\r\n\x1a\n\0\0\0"),
        ]);
        let sum = "files['data/prices.csv'].trim().split('\\n').slice(1)\
            .map((line) => Number(line.split(',')[1])).reduce((a, b) => a + b, 0).toFixed(2)";
        assert_eq!(
            fixture
                .ok(
                    RUN_SCRIPT,
                    json!({"code": sum, "files": ["./data/prices.csv"]})
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
                .error(RUN_SCRIPT, json!({"code": "files", "files": []}))
                .await,
            "Uncaught ReferenceError: files is not defined\n    at <eval> (script.js:1:1)"
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

        // Without repositories there are no files to pass.
        let definitions = tools.definitions();
        assert_eq!(definitions.len(), 1);
        assert!(definitions[0].input_schema["properties"]["files"].is_null());
    }
}
