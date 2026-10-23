use crate::config::state::AppState;
use crate::dto::instance::InstanceDto;
use axum::Json;
use axum::extract::State;

/// Public, so the login page can show it too.
pub(crate) async fn get_instance(State(state): State<AppState>) -> Json<InstanceDto> {
    Json(InstanceDto {
        name: state.runtime_config.current().instance_name.clone(),
    })
}
