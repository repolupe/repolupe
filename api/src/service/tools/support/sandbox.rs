//! The QuickJS sandbox that runs the scripts of [`RUN_SCRIPT`] in the API process. QuickJS has
//! no I/O of its own (no `std` or `os` modules), so a script only sees the [`Inputs`] it is
//! given and `console` to print. Each script gets its own runtime, limited in memory, stack and
//! time, so scripts share no state.
//!
//! [`RUN_SCRIPT`]: crate::service::tools::RUN_SCRIPT

use super::results::{StoredResult, dropped_message};
use super::{MAX_OUTPUT_CHARS, format_size};
use crate::config::error::AppError;
use crate::service::tools::ToolError;
use rquickjs::allocator::{Allocator, RustAllocator};
use rquickjs::context::EvalOptions;
use rquickjs::promise::PromiseState;
use rquickjs::{
    CatchResultExt, CaughtError, Context, Ctx, Exception, Function, Object, Runtime, Value,
};
use std::cell::{Cell, RefCell};
use std::ptr;
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};

const MAX_DURATION: Duration = Duration::from_secs(5);
const MAX_MEMORY: usize = 128 * 1024 * 1024;
/// Below the 2 MiB of the threads of `spawn_blocking`, so deep recursion is a `RangeError`
/// instead of a stack overflow.
const MAX_STACK: usize = 512 * 1024;
/// Of all files and attachments of a script together, so they fit into [`MAX_MEMORY`] as
/// UTF-16. Also the largest result stored for scripts, see [`super::results`].
pub(crate) const MAX_INPUT_BYTES: usize = 16 * 1024 * 1024;
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

/// Installs `$results`, with a getter for each stored result that loads it with `load` and
/// then replaces itself with the value, so a script only parses the results it reads. Dropped
/// results are left out of the keys, and their getters throw.
const RESULTS: &str = r#"
(load, kept) => {
  const results = {};
  kept.forEach((isKept, index) => {
    const key = String(index + 1);
    const set = (value) => Object.defineProperty(results, key, {
      value, writable: true, enumerable: true, configurable: true,
    });
    Object.defineProperty(results, key, {
      get() { const value = load(index + 1); set(value); return value; },
      set,
      enumerable: isKept,
      configurable: true,
    });
  });
  globalThis.$results = results;
}
"#;

/// What a script gets besides its code, see [`execute`].
#[derive(Default)]
pub(crate) struct Inputs {
    /// Repository files, by path.
    files: Vec<(String, String)>,
    /// Attachments, by number.
    attachments: Vec<(String, String)>,
    /// The stored results, by number from 1, `None` for those dropped. `None` without MCP
    /// tools, which then don't get `$results`.
    pub(crate) results: Option<Vec<Option<Arc<StoredResult>>>>,
    bytes: usize,
}

impl Inputs {
    pub(crate) fn add_file(&mut self, path: String, content: String) -> Result<(), ToolError> {
        self.count(&content)?;
        self.files.push((path, content));
        Ok(())
    }

    pub(crate) fn add_attachment(&mut self, number: i32, content: String) -> Result<(), ToolError> {
        self.count(&content)?;
        self.attachments.push((number.to_string(), content));
        Ok(())
    }

    /// Counts `content` against [`MAX_INPUT_BYTES`].
    fn count(&mut self, content: &str) -> Result<(), ToolError> {
        self.bytes += content.len();
        if self.bytes > MAX_INPUT_BYTES {
            return Err(ToolError::Invalid(format!(
                "The files are too large to pass to a script together, the limit is {}.",
                format_size(MAX_INPUT_BYTES as u64)
            )));
        }
        Ok(())
    }
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
            Ok(Some(result)) => parts.push(cut(format!("Result: {result}"), "Result")),
            Ok(None) if parts.is_empty() => {
                parts.push("(no output, print results with console.log)".to_string());
            }
            Ok(None) => {}
            Err(error) => parts.push(cut(error, "Error")),
        }
        parts.join("\n\n")
    }
}

/// `text`, cut to [`MAX_OUTPUT_CHARS`] on its own, so a long output doesn't hide it.
fn cut(mut text: String, what: &str) -> String {
    if let Some((index, _)) = text.char_indices().nth(MAX_OUTPUT_CHARS) {
        text.truncate(index);
        text.push_str(&format!(
            "… [{what} cut after {MAX_OUTPUT_CHARS} characters.]"
        ));
    }
    text
}

/// Runs `code` with the files, attachments and results of `inputs` as the globals `$files`,
/// `$attachments` and `$results`, the first two left out if empty. Blocks for up to
/// [`MAX_DURATION`].
pub(crate) fn execute(code: &str, inputs: &Inputs) -> Result<String, ToolError> {
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
        for (name, entries) in [
            ("$files", &inputs.files),
            ("$attachments", &inputs.attachments),
        ] {
            if !entries.is_empty() {
                let object = Object::new(ctx.clone())?;
                for (key, content) in entries {
                    object.set(key.as_str(), content.as_str())?;
                }
                ctx.globals().set(name, object)?;
            }
        }
        if let Some(results) = &inputs.results {
            let kept: Vec<bool> = results.iter().map(Option::is_some).collect();
            let install: Function = ctx.eval(RESULTS)?;
            install.call::<_, ()>((result_loader(&ctx, results.clone())?, kept))?;
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
        let settled = ctx
            .eval_with_options::<Value, _>(code, options)
            .catch(&ctx)
            .and_then(|value| settle(&ctx, value, deadline));
        // Also if it caught the error, its result may be incomplete.
        let memory_error = || {
            out_of_memory.get().then(|| {
                format!(
                    "The script ran out of memory, it may use at most {}.",
                    format_size(MAX_MEMORY as u64)
                )
            })
        };
        if let Some(message) = memory_error() {
            return Ok(Err(message));
        }
        // Described before the jobs below run, since they may use up the time left, which
        // would stop the formatting and make any error look like a timeout.
        let result = match settled {
            Ok(value) if value.is_undefined() => None,
            Ok(value) => Some(
                inspect
                    .call::<_, String>((value,))
                    .unwrap_or_else(|_| "(the result can't be shown)".to_string()),
            ),
            Err(error) => return Ok(Err(describe_error(&inspect, error, deadline))),
        };
        // The script may have started async functions it did not wait for.
        while Instant::now() < deadline && ctx.execute_pending_job() {}
        Ok::<_, ToolError>(memory_error().map_or(Ok(result), Err))
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

/// The function that loads a result for `$results`: a string for text, the value for JSON.
/// Throws for a dropped result, and returns `undefined` for unknown numbers.
fn result_loader<'js>(
    ctx: &Ctx<'js>,
    results: Vec<Option<Arc<StoredResult>>>,
) -> rquickjs::Result<Function<'js>> {
    Function::new(
        ctx.clone(),
        move |ctx: Ctx<'js>, number: usize| -> rquickjs::Result<Value<'js>> {
            let Some(result) = number.checked_sub(1).and_then(|i| results.get(i)) else {
                return Ok(Value::new_undefined(ctx));
            };
            match result.as_deref() {
                Some(StoredResult::Text(text)) => {
                    Ok(rquickjs::String::from_str(ctx, text)?.into_value())
                }
                Some(StoredResult::Json(json)) => ctx.json_parse(json.as_str()),
                None => Err(Exception::throw_message(&ctx, &dropped_message(number))),
            }
        },
    )
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

    #[test]
    fn throws_for_dropped_results() {
        let inputs = Inputs {
            results: Some(vec![
                None,
                Some(Arc::new(StoredResult::Text("b".to_string()))),
            ]),
            ..Inputs::default()
        };
        match execute("$results[1]", &inputs) {
            Err(ToolError::Invalid(message)) => assert!(
                message.starts_with(
                    "Uncaught Error: Result 1 is no longer stored, the results of this answer \
                    took more than 32.0 MB. Call the tool again."
                ),
                "{message}"
            ),
            _ => panic!("reading a dropped result should throw"),
        }
        match execute("[Object.keys($results), $results[2]]", &inputs) {
            Ok(output) => assert_eq!(output, "Result: [[\"2\"], \"b\"]"),
            _ => panic!("the other results should be readable"),
        }
    }

    #[test]
    fn loads_results_when_read() {
        // Within the bytes, but an array of numbers takes 16 bytes per item in QuickJS.
        let items = MAX_INPUT_BYTES / 2 - 1;
        let json = format!("[{}0]", "0,".repeat(items - 1));
        assert!(json.len() <= MAX_INPUT_BYTES);
        let inputs = Inputs {
            results: Some(vec![Some(Arc::new(StoredResult::Json(json)))]),
            ..Inputs::default()
        };
        // Not parsed unless the script reads it.
        match execute("1 + 1", &inputs) {
            Ok(output) => assert_eq!(output, "Result: 2"),
            _ => panic!("the result should not be loaded"),
        }
        match execute("$results[1].length", &inputs) {
            Err(ToolError::Invalid(message)) => assert_eq!(
                message,
                "The script ran out of memory, it may use at most 128.0 MB."
            ),
            _ => panic!("the result should not fit"),
        }
    }
}
