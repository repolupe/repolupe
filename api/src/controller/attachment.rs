use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::dto::attachment::{AttachmentDto, UploadAttachmentQuery};
use crate::middleware::auth::AuthenticatedUser;
use crate::repository;
use crate::service::attachment::MAX_ATTACHMENT_BYTES;
use crate::service::extraction;
use crate::util::extract::{PathParam, QueryParams};
use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Json};
use std::fmt::Write;
use uuid::Uuid;

/// Stores the request body, sent as `application/octet-stream`, as an attachment to send with
/// the next message (`attachment_id`). Attachments not sent within a day are removed.
pub(crate) async fn upload_attachment(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    QueryParams(query): QueryParams<UploadAttachmentQuery>,
    headers: HeaderMap,
    body: Body,
) -> Result<(StatusCode, Json<AttachmentDto>), AppError> {
    let too_large = || {
        AppError::BadRequest(format!(
            "The file must be at most {} MB",
            MAX_ATTACHMENT_BYTES / 1024 / 1024
        ))
    };
    let declared = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.parse::<usize>().ok());
    if declared.is_some_and(|length| length > MAX_ATTACHMENT_BYTES) {
        return Err(too_large());
    }
    let content = axum::body::to_bytes(body, MAX_ATTACHMENT_BYTES)
        .await
        .map_err(|_| too_large())?;

    let attachment = state
        .attachments
        .save(
            &state.db,
            auth.user_id,
            &query.file_name,
            query.content_type.as_deref(),
            content.to_vec(),
        )
        .await?;
    if extraction::document_type(&attachment.content_type).is_some() {
        state.extractor.notify_queued();
    }
    Ok((StatusCode::CREATED, Json(attachment.into())))
}

/// The file of an attachment of the user, as a download.
pub(crate) async fn download_attachment(
    State(state): State<AppState>,
    Extension(auth): Extension<AuthenticatedUser>,
    PathParam(id): PathParam<Uuid>,
) -> Result<Response, AppError> {
    let attachment = repository::attachment::get_attachment(&state.db, auth.user_id, id)
        .await?
        .ok_or(AppError::NotFound)?;
    let content = state.attachments.read(attachment.id).await?;
    let content_type = HeaderValue::from_str(&attachment.content_type)
        .unwrap_or(HeaderValue::from_static("application/octet-stream"));
    let disposition = HeaderValue::from_str(&content_disposition(&attachment.file_name))
        .map_err(|e| AppError::InternalServerError(format!("Invalid file name header: {e}")))?;
    let headers = [
        (header::CONTENT_TYPE, content_type),
        // Uploaded by the user, so it is only downloaded, never shown as a page of this site.
        (header::CONTENT_DISPOSITION, disposition),
        (
            header::X_CONTENT_TYPE_OPTIONS,
            HeaderValue::from_static("nosniff"),
        ),
        (
            header::CONTENT_SECURITY_POLICY,
            HeaderValue::from_static("sandbox"),
        ),
    ];
    Ok((headers, content).into_response())
}

/// `attachment` with `file_name`, as ASCII for old clients and encoded per RFC 5987.
fn content_disposition(file_name: &str) -> String {
    let ascii: String = file_name
        .chars()
        .map(|c| {
            if c.is_ascii_graphic() && c != '"' && c != '\\' || c == ' ' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let mut encoded = String::new();
    for byte in file_name.bytes() {
        if byte.is_ascii_alphanumeric() || b"!#$&+-.^_`|~".contains(&byte) {
            encoded.push(byte as char);
        } else {
            let _ = write!(encoded, "%{byte:02X}");
        }
    }
    format!("attachment; filename=\"{ascii}\"; filename*=UTF-8''{encoded}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_file_names() {
        assert_eq!(
            content_disposition("Rechnung März \"2026\".pdf"),
            "attachment; filename=\"Rechnung M_rz _2026_.pdf\"; \
             filename*=UTF-8''Rechnung%20M%C3%A4rz%20%222026%22.pdf"
        );
    }
}
