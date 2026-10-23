//! The files users drop into chats, stored as `<ATTACHMENTS_DIR>/<id>`. They are uploaded
//! before the message is sent, which gives them a number in the chat that the model refers to
//! them by (see [`crate::service::tools::SAVE_ATTACHMENT`]). Unsent ones and the files of
//! deleted chats are removed by [`AttachmentStore::remove_unused`]. Documents among them are
//! converted to Markdown right away, see [`extraction`].

use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::model::attachment::Attachment;
use crate::repository;
use crate::repository::attachment::NewAttachment;
use crate::service::{extraction, mirror};
use crate::util::validation::ValidationError;
use chrono::{TimeDelta, Utc};
use std::path::PathBuf;
use std::time::Duration;
use uuid::Uuid;

/// Larger uploads are rejected.
pub(crate) const MAX_ATTACHMENT_BYTES: usize = 50 * 1024 * 1024;
const MAX_FILE_NAME_CHARS: usize = 255;
const MAX_CONTENT_TYPE_CHARS: usize = 127;
const UNKNOWN_CONTENT_TYPE: &str = "application/octet-stream";
/// Attachments not sent within this time are removed.
const UNSENT_LIFETIME: TimeDelta = TimeDelta::days(1);
/// Files without a row are only removed when they are older, since an upload writes the file
/// before it inserts the row.
const ORPHAN_GRACE_PERIOD: Duration = Duration::from_hours(1);
/// Written first and renamed when complete, so a crash never leaves a partial file under an id.
const PARTIAL_SUFFIX: &str = ".part";

pub(crate) struct AttachmentStore {
    dir: PathBuf,
}

impl AttachmentStore {
    /// Stores attachments in `dir`, which must exist.
    pub(crate) fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    /// Stores `content` as an unsent attachment of the user. `content_type` is what the browser
    /// reported, if anything. If it is a document (see [`extraction::document_type`]), the
    /// caller wakes the extractor to convert it.
    pub(crate) async fn save(
        &self,
        db: &DatabasePool,
        user_id: Uuid,
        file_name: &str,
        content_type: Option<&str>,
        content: Vec<u8>,
    ) -> Result<Attachment, AppError> {
        let file_name = parse_file_name(file_name)?;
        let content_type = parse_content_type(&file_name, content_type);
        let size = content.len() as i64;
        let id = Uuid::now_v7();

        let path = self.path(id);
        let partial = self.dir.join(format!("{id}{PARTIAL_SUFFIX}"));
        let blob_oid = tokio::task::spawn_blocking(move || -> Result<String, AppError> {
            let blob_oid = mirror::blob_oid(&content)?;
            std::fs::write(&partial, &content)
                .and_then(|()| std::fs::rename(&partial, &path))
                .map_err(|e| {
                    let _ = std::fs::remove_file(&partial);
                    AppError::InternalServerError(format!("Failed to store attachment {id}: {e}"))
                })?;
            Ok(blob_oid)
        })
        .await
        .map_err(|e| {
            AppError::InternalServerError(format!("Storing attachment {id} failed: {e}"))
        })??;

        let now = Utc::now();
        let inserted = repository::attachment::insert_attachment(
            db,
            NewAttachment {
                id,
                user_id,
                file_name: &file_name,
                content_type: &content_type,
                size,
                blob_oid: &blob_oid,
                created_at: now,
            },
        )
        .await;
        if inserted.is_err() {
            let _ = tokio::fs::remove_file(self.path(id)).await;
        }
        inserted
    }

    /// The content of the attachment `id`.
    pub(crate) async fn read(&self, id: Uuid) -> Result<Vec<u8>, AppError> {
        tokio::fs::read(self.path(id)).await.map_err(|e| {
            AppError::InternalServerError(format!("Failed to read attachment {id}: {e}"))
        })
    }

    /// Deletes the attachments that were not sent in time with their files, and the files
    /// without an attachment, e.g. of deleted chats.
    pub(crate) async fn remove_unused(&self, db: &DatabasePool) -> Result<(), AppError> {
        let unsent =
            repository::attachment::delete_unsent(db, Utc::now() - UNSENT_LIFETIME).await?;
        for id in &unsent {
            if let Err(e) = tokio::fs::remove_file(self.path(*id)).await
                && e.kind() != std::io::ErrorKind::NotFound
            {
                tracing::error!("Failed to remove attachment {id}: {e}");
            }
        }
        if !unsent.is_empty() {
            tracing::info!("Removed {} attachments that were not sent", unsent.len());
        }

        // Listed before the files, so a file uploaded in between is too new to be removed.
        let ids = repository::attachment::list_attachment_ids(db).await?;
        let dir = self.dir.clone();
        let removed = tokio::task::spawn_blocking(move || -> std::io::Result<usize> {
            let mut removed = 0;
            for entry in std::fs::read_dir(&dir)? {
                let entry = entry?;
                let in_use = entry
                    .file_name()
                    .to_str()
                    .and_then(|name| name.parse::<Uuid>().ok())
                    .is_some_and(|id| ids.contains(&id));
                let recent = entry
                    .metadata()?
                    .modified()?
                    .elapsed()
                    .is_ok_and(|age| age < ORPHAN_GRACE_PERIOD);
                if !in_use && !recent && entry.file_type()?.is_file() {
                    std::fs::remove_file(entry.path())?;
                    removed += 1;
                }
            }
            Ok(removed)
        })
        .await
        .map_err(|e| AppError::InternalServerError(format!("Removing attachments failed: {e}")))?
        .map_err(|e| AppError::InternalServerError(format!("Failed to remove attachments: {e}")))?;
        if removed > 0 {
            tracing::info!("Removed {removed} files of deleted attachments");
        }
        Ok(())
    }

    fn path(&self, id: Uuid) -> PathBuf {
        self.dir.join(id.to_string())
    }
}

/// The last segment of `name`, in case a client sends a path.
fn parse_file_name(name: &str) -> Result<String, ValidationError> {
    let name = name.rsplit(['/', '\\']).next().unwrap_or_default().trim();
    if name.is_empty() || name == "." || name == ".." {
        return Err(ValidationError("`file_name` must not be empty".to_string()));
    }
    if name.chars().any(char::is_control) {
        return Err(ValidationError(
            "`file_name` must not contain control characters".to_string(),
        ));
    }
    if name.chars().count() > MAX_FILE_NAME_CHARS {
        return Err(ValidationError(format!(
            "`file_name` must be at most {MAX_FILE_NAME_CHARS} characters long"
        )));
    }
    Ok(name.to_string())
}

/// A media type like `application/pdf` without parameters, lowercase, or
/// [`UNKNOWN_CONTENT_TYPE`] if `content_type` is missing or not one. A file with the extension of
/// a document gets the document's type whatever the browser reported, so it is converted like
/// one in a repository.
fn parse_content_type(file_name: &str, content_type: Option<&str>) -> String {
    if let Some(mime_type) = extraction::mime_type(file_name) {
        return mime_type.to_string();
    }
    let token = |part: &str| {
        !part.is_empty()
            && part
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "!#$&-^_.+".contains(c))
    };
    content_type
        .and_then(|value| value.split(';').next())
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| {
            value.len() <= MAX_CONTENT_TYPE_CHARS
                && value
                    .split_once('/')
                    .is_some_and(|(kind, subtype)| token(kind) && token(subtype))
        })
        .unwrap_or_else(|| UNKNOWN_CONTENT_TYPE.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_file_names() {
        assert_eq!(parse_file_name(" report.pdf ").unwrap(), "report.pdf");
        assert_eq!(parse_file_name("C:\\Users\\me\\a.txt").unwrap(), "a.txt");
        assert_eq!(parse_file_name("docs/a.txt").unwrap(), "a.txt");
        for invalid in ["", "  ", "docs/", "..", "a\nb", &"x".repeat(256)] {
            assert!(parse_file_name(invalid).is_err(), "{invalid:?}");
        }
    }

    #[test]
    fn parses_content_types() {
        assert_eq!(
            parse_content_type("scan", Some("application/pdf")),
            "application/pdf"
        );
        assert_eq!(
            parse_content_type("a.txt", Some("Text/Plain; charset=utf-8")),
            "text/plain"
        );
        // By the extension of a document
        for reported in [None, Some("application/octet-stream"), Some("text/plain")] {
            assert_eq!(
                parse_content_type("Invoice.PDF", reported),
                "application/pdf",
                "{reported:?}"
            );
        }
        for unknown in [None, Some(""), Some("pdf"), Some("text/"), Some("a b/c")] {
            assert_eq!(
                parse_content_type("a.txt", unknown),
                UNKNOWN_CONTENT_TYPE,
                "{unknown:?}"
            );
        }
    }
}
