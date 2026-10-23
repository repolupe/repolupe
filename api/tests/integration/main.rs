//! Tests of the whole app against real SQLite databases, run by `cargo test` (only these
//! with `cargo test --test integration`).
//!
//! Every `#[sqlx::test]` gets its own database file under `target/sqlx/test-dbs` with the
//! migrations applied, which is replaced on the next run, so tests run in parallel and need
//! no cleanup.
//!
//! - [`support`]: the app on such a database, with clients for users and seeded repositories.
//!   Uses only the public API of the crate, apart from inserting seeded repositories.
//! - [`mock_llm`]: a local server answering in the Anthropic format with scripted responses.
//! - [`local_remote`]: a git remote on localhost, served by `git http-backend`.

mod local_remote;
mod mock_llm;
mod support;

mod access;
mod attachments;
mod chats;
mod commits;
mod config;
mod documents;
mod generation;
mod local_repositories;
mod remote_access;
mod sharing;
mod user;
