//! The admins' view of the configuration, see `/api/v1/config`.

use serde::{Deserialize, Serialize};

/// A row of `GET /api/v1/config`, values in the text form of the environment variables.
#[derive(Serialize, Deserialize)]
pub struct ConfigEntryDto {
    pub key: String,
    /// What the server was started with: the environment variable, or built in. `None` if
    /// unset, `******` for secrets.
    pub env: Option<String>,
    /// Set by an admin with `POST /api/v1/config`, in effect instead of `env`.
    #[serde(rename = "override")]
    pub override_value: Option<String>,
    /// Whether it can be overridden, see [`crate::RuntimeConfig`]. Everything else needs a
    /// restart.
    pub runtime: bool,
}
