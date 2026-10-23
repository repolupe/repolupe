//! The instance as everyone sees it, see `GET /api/v1/instance`.

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct InstanceDto {
    /// `INSTANCE_NAME`, `Repolupe` unless renamed, see [`crate::RuntimeConfig`].
    pub name: String,
}
