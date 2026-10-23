//! Mirrors of the DTOs that FRB can't read from the `repolupe` crate itself: the fields of enum
//! variants there have no `pub`, which FRB requires of third-party types, so these copies tell
//! it their shape. They must match the originals, which the generated code converts from and to.

use flutter_rust_bridge::frb;
pub use repolupe::dto::llm::ApiKeyChange;
pub use repolupe::dto::repository::TokenChange;

#[frb(mirror(TokenChange))]
pub enum _TokenChange {
    Keep,
    Remove,
    Set { value: String },
}

#[frb(mirror(ApiKeyChange))]
pub enum _ApiKeyChange {
    Keep,
    Remove,
    Set { value: String },
}
