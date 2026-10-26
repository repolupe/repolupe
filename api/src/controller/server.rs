use crate::dto::server::ServerDto;
use axum::Json;

/// Admins only, since the version tells attackers which vulnerabilities apply.
pub(crate) async fn get_server() -> Json<ServerDto> {
    Json(ServerDto {
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}
