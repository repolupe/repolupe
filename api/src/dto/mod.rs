//! The requests and responses of the API, as JSON. Clients use them too, which is why they
//! derive both `Serialize` and `Deserialize` and hold only plain data: decimals are strings and
//! JSON values their text, so code generators such as flutter_rust_bridge can mirror them. The
//! conversions from the models are in `controller/`.
//!
//! `ErrorCode` and the status enums of responses have an `Unknown` variant (`#[serde(other)]`),
//! so a client still parses the responses of a newer server with more values. The server never
//! sends it. Enums that requests contain (e.g. `LlmApiFormat`) have none, so an unknown value
//! stays a validation error.

pub mod attachment;
pub mod auth;
pub mod chat;
pub mod config;
pub mod error;
pub mod extraction;
pub mod instance;
pub mod llm;
pub mod repository;
pub mod user;
