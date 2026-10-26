//! The server as admins see it, see `GET /api/v1/server`.

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct ServerDto {
    /// The version of the `repolupe` crate the server was built from.
    pub version: String,
}
