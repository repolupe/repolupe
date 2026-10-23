use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::service;
use axum::Json;
use axum::extract::State;
use serde::Serialize;

/// Unauthenticated, only routed if [`crate::Config::debug_api`] is set.
pub(crate) async fn create_dummy_data(
    State(state): State<AppState>,
) -> Result<Json<DummyDataDto>, AppError> {
    let chats = service::debug::create_dummy_chats(&state).await?;
    Ok(Json(DummyDataDto { chats }))
}

#[derive(Serialize)]
pub struct DummyDataDto {
    /// The number of chats created.
    pub chats: usize,
}
