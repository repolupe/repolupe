//! Logging in.

use crate::dto::user::UserDto;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct LoginRequest {
    pub user_name_or_email: String,
    pub password: String,
}

#[derive(Serialize, Deserialize)]
pub struct LoginResponse {
    /// For mobile clients (`Authorization: Bearer`). Browsers use the HttpOnly cookie instead.
    pub token: String,
    pub user: UserDto,
}
