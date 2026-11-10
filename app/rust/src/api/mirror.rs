//! Mirrors of the DTOs that FRB can't read from the `repolupe` crate itself: the fields of enum
//! variants there have no `pub`, which FRB requires of third-party types, so these copies tell
//! it their shape. They must match the originals, which the generated code converts from and to.

use flutter_rust_bridge::frb;
pub use repolupe::dto::chat::RawBlockDto;
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

#[frb(mirror(RawBlockDto))]
pub enum _RawBlockDto {
    Text {
        text: String,
    },
    Reasoning {
        text: String,
        redacted: bool,
    },
    ToolUse {
        id: String,
        name: String,
        input: String,
    },
    ToolResult {
        tool_use_id: String,
        content: String,
        is_error: bool,
    },
    Unknown,
}
