//! Tests of the client against a real Repolupe, run by `cargo test` (only these with
//! `cargo test --test integration`). They use only the public API of the crate.
//!
//! - [`client`]: every client method through both transports, and a local instance.
//! - [`stream`]: the message stream, with a mock Anthropic API.

mod client;
mod stream;
