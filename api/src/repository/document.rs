use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::dto::extraction::{DocumentExtractionStatus, DocumentFilter};
use crate::model::document_extraction::{DocumentExtraction, ExtractedMarkdown};
use crate::model::repository::RepositoryLabel;
use crate::model::repository_document::{
    DocumentSource, ExtractionSummary, ExtractionTotals, ListedDocument, QueuedDocument,
    RepositoryListedDocument,
};
use chrono::{DateTime, Utc};
use sqlx::types::Json;
use uuid::Uuid;

/// The next document without an extraction made by `extractor`, from the repository after
/// `after` (by id, starting over after the last one), so the repositories take turns. Blobs in
/// `skip` are left out.
pub(crate) async fn next_queued(
    db: &DatabasePool,
    extractor: &str,
    after: Option<Uuid>,
    skip: &[String],
) -> Result<Option<QueuedDocument>, AppError> {
    let skip = Json(skip);
    let row = sqlx::query!(
        r#"SELECT d.repository_id AS "repository_id: Uuid", d.path, d.blob_oid
           FROM repository_documents d
                    LEFT JOIN document_extractions e ON e.blob_oid = d.blob_oid AND e.extractor = $1
           WHERE e.blob_oid IS NULL
             AND d.blob_oid NOT IN (SELECT value FROM json_each($3))
           ORDER BY COALESCE(d.repository_id <= $2, FALSE), d.repository_id, d.path
           LIMIT 1"#,
        extractor,
        after,
        skip,
    )
    .fetch_optional(db)
    .await?;
    Ok(row.map(|row| QueuedDocument {
        source: DocumentSource::Repository {
            repository_id: row.repository_id,
            path: row.path,
        },
        blob_oid: row.blob_oid,
    }))
}

/// The oldest attachment of a type in `content_types` without an extraction made by
/// `extractor`, sent or not. Blobs in `skip` are left out.
pub(crate) async fn next_queued_attachment(
    db: &DatabasePool,
    extractor: &str,
    content_types: &[&str],
    skip: &[String],
) -> Result<Option<QueuedDocument>, AppError> {
    let content_types = Json(content_types);
    let skip = Json(skip);
    let row = sqlx::query!(
        r#"SELECT a.id AS "id: Uuid", a.file_name, a.content_type, a.blob_oid
           FROM attachments a
                    LEFT JOIN document_extractions e ON e.blob_oid = a.blob_oid AND e.extractor = $1
           WHERE e.blob_oid IS NULL
             AND a.content_type IN (SELECT value FROM json_each($2))
             AND a.blob_oid NOT IN (SELECT value FROM json_each($3))
           ORDER BY a.created_at, a.id
           LIMIT 1"#,
        extractor,
        content_types,
        skip,
    )
    .fetch_optional(db)
    .await?;
    Ok(row.map(|row| QueuedDocument {
        source: DocumentSource::Attachment {
            attachment_id: row.id,
            file_name: row.file_name,
            content_type: row.content_type,
        },
        blob_oid: row.blob_oid,
    }))
}

/// The documents in the synced commit of `repository_id` by path, with their extractions.
pub(crate) async fn list_documents(
    db: &DatabasePool,
    repository_id: Uuid,
) -> Result<Vec<ListedDocument>, AppError> {
    let rows = sqlx::query!(
        r#"SELECT d.path,
                  d.blob_oid,
                  e.status       AS "status?: DocumentExtractionStatus",
                  e.ocr          AS "ocr?",
                  e.error        AS "error?",
                  e.extractor    AS "extractor?",
                  e.extracted_at AS "extracted_at?: DateTime<Utc>"
           FROM repository_documents d
                    LEFT JOIN document_extractions e ON e.blob_oid = d.blob_oid
           WHERE d.repository_id = $1
           ORDER BY d.path"#,
        repository_id,
    )
    .fetch_all(db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|row| ListedDocument {
            path: row.path,
            blob_oid: row.blob_oid,
            extraction: match (row.status, row.extractor, row.extracted_at) {
                (Some(status), Some(extractor), Some(extracted_at)) => Some(ExtractionSummary {
                    status,
                    ocr: row.ocr,
                    error: row.error,
                    extractor,
                    extracted_at,
                }),
                _ => None,
            },
        })
        .collect())
}

/// Counts all documents by their extraction with `extractor`. `skipped` are the blobs left out
/// for now. Not scoped to a user, only for admins.
pub(crate) async fn count_extractions(
    db: &DatabasePool,
    extractor: &str,
    skipped: &[String],
) -> Result<ExtractionTotals, AppError> {
    let skipped = Json(skipped);
    let row = sqlx::query!(
        r#"SELECT COUNT(*) AS "documents!",
                  COUNT(*) FILTER (WHERE e.extractor = $1 AND e.status = 'COMPLETED') AS "converted!",
                  COUNT(*) FILTER (WHERE e.extractor = $1 AND e.status = 'FAILED') AS "failed!",
                  COUNT(*) FILTER (WHERE e.extractor IS DISTINCT FROM $1
                                     AND d.blob_oid IN (SELECT value FROM json_each($2))) AS "skipped!"
           FROM repository_documents d
                    LEFT JOIN document_extractions e ON e.blob_oid = d.blob_oid"#,
        extractor,
        skipped,
    )
    .fetch_one(db)
    .await?;
    Ok(ExtractionTotals {
        documents: row.documents,
        converted: row.converted,
        failed: row.failed,
        skipped: row.skipped,
    })
}

/// The documents of all repositories matching `filter` with `extractor`, by repository name and
/// path. `viewer_id` decides `readable`. Not scoped to a user, only for admins.
pub(crate) async fn list_all_documents(
    db: &DatabasePool,
    extractor: &str,
    filter: DocumentFilter,
    viewer_id: Uuid,
    offset: i64,
    limit: i64,
) -> Result<Vec<RepositoryListedDocument>, AppError> {
    let filter = filter.as_str();
    let rows = sqlx::query!(
        r#"SELECT r.id AS "repository_id: Uuid",
                  r.name AS repository_name,
                  u.user_name AS owner_name,
                  (r.user_id = $3 OR EXISTS (SELECT 1
                                             FROM repository_users ru
                                             WHERE ru.repository_id = r.id AND ru.user_id = $3)) AS "readable!: bool",
                  d.path,
                  d.blob_oid,
                  e.status       AS "status?: DocumentExtractionStatus",
                  e.ocr          AS "ocr?",
                  e.error        AS "error?",
                  e.extractor    AS "extractor?",
                  e.extracted_at AS "extracted_at?: DateTime<Utc>"
           FROM repository_documents d
                    JOIN repositories r ON r.id = d.repository_id
                    JOIN users u ON u.id = r.user_id
                    LEFT JOIN document_extractions e ON e.blob_oid = d.blob_oid
           WHERE CASE $2
                     WHEN 'CONVERTED' THEN e.extractor = $1 AND e.status = 'COMPLETED'
                     WHEN 'FAILED' THEN e.extractor = $1 AND e.status = 'FAILED'
                     WHEN 'PENDING' THEN e.extractor IS DISTINCT FROM $1
                     ELSE TRUE
                     END
           ORDER BY r.name, r.id, d.path
           LIMIT $5 OFFSET $4"#,
        extractor,
        filter,
        viewer_id,
        offset,
        limit,
    )
    .fetch_all(db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|row| RepositoryListedDocument {
            repository: RepositoryLabel {
                id: row.repository_id,
                name: row.repository_name,
                owner_name: row.owner_name,
                readable: row.readable,
            },
            document: ListedDocument {
                path: row.path,
                blob_oid: row.blob_oid,
                extraction: match (row.status, row.extractor, row.extracted_at) {
                    (Some(status), Some(extractor), Some(extracted_at)) => {
                        Some(ExtractionSummary {
                            status,
                            ocr: row.ocr,
                            error: row.error,
                            extractor,
                            extracted_at,
                        })
                    }
                    _ => None,
                },
            },
        })
        .collect())
}

/// How many documents [`list_all_documents`] lists in all.
pub(crate) async fn count_all_documents(
    db: &DatabasePool,
    extractor: &str,
    filter: DocumentFilter,
) -> Result<i64, AppError> {
    let filter = filter.as_str();
    let count = sqlx::query_scalar!(
        r#"SELECT COUNT(*) AS "count!"
           FROM repository_documents d
                    LEFT JOIN document_extractions e ON e.blob_oid = d.blob_oid
           WHERE CASE $2
                     WHEN 'CONVERTED' THEN e.extractor = $1 AND e.status = 'COMPLETED'
                     WHEN 'FAILED' THEN e.extractor = $1 AND e.status = 'FAILED'
                     WHEN 'PENDING' THEN e.extractor IS DISTINCT FROM $1
                     ELSE TRUE
                     END"#,
        extractor,
        filter,
    )
    .fetch_one(db)
    .await?;
    Ok(count)
}

/// Whether any repository contains a document with `blob_oid`.
pub(crate) async fn document_exists(db: &DatabasePool, blob_oid: &str) -> Result<bool, AppError> {
    let exists = sqlx::query_scalar!(
        r#"SELECT EXISTS (SELECT 1 FROM repository_documents WHERE blob_oid = $1) AS "exists!: bool""#,
        blob_oid,
    )
    .fetch_one(db)
    .await?;
    Ok(exists)
}

/// Deletes the extraction of `blob_oid` if it was made with `extractor` and failed, so it is
/// converted again. Returns whether it did.
pub(crate) async fn delete_failed_extraction(
    db: &DatabasePool,
    blob_oid: &str,
    extractor: &str,
) -> Result<bool, AppError> {
    let result = sqlx::query!(
        "DELETE FROM document_extractions WHERE blob_oid = $1 AND extractor = $2 AND status = 'FAILED'",
        blob_oid,
        extractor,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Stores the extraction of a blob, replacing an older one.
pub(crate) async fn save_extraction(
    db: &DatabasePool,
    blob_oid: &str,
    extraction: &DocumentExtraction,
    extractor: &str,
) -> Result<(), AppError> {
    let (status, markdown, ocr, error) = match extraction {
        DocumentExtraction::Completed { markdown, ocr } => (
            DocumentExtractionStatus::Completed,
            Some(markdown),
            Some(*ocr),
            None,
        ),
        DocumentExtraction::Failed { error } => {
            (DocumentExtractionStatus::Failed, None, None, Some(error))
        }
    };
    let now = Utc::now();
    sqlx::query!(
        r#"INSERT INTO document_extractions (blob_oid, status, markdown, ocr, error, extractor, extracted_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (blob_oid) DO UPDATE
               SET status       = excluded.status,
                   markdown     = excluded.markdown,
                   ocr          = excluded.ocr,
                   error        = excluded.error,
                   extractor    = excluded.extractor,
                   extracted_at = excluded.extracted_at"#,
        blob_oid,
        status,
        markdown,
        ocr,
        error,
        extractor,
        now,
    )
    .execute(db)
    .await?;
    Ok(())
}

/// Stores the extraction of `from` made by `extractor` as the extraction of `to` too, replacing
/// an older one. Returns whether there was one.
pub(crate) async fn copy_extraction(
    db: &DatabasePool,
    from: &str,
    to: &str,
    extractor: &str,
) -> Result<bool, AppError> {
    let now = Utc::now();
    let result = sqlx::query!(
        r#"INSERT INTO document_extractions (blob_oid, status, markdown, ocr, error, extractor, extracted_at)
           SELECT $2, status, markdown, ocr, error, extractor, $4
           FROM document_extractions
           WHERE blob_oid = $1 AND extractor = $3
           ON CONFLICT (blob_oid) DO UPDATE
               SET status       = excluded.status,
                   markdown     = excluded.markdown,
                   ocr          = excluded.ocr,
                   error        = excluded.error,
                   extractor    = excluded.extractor,
                   extracted_at = excluded.extracted_at"#,
        from,
        to,
        extractor,
        now,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected() > 0)
}

pub(crate) async fn get_extraction(
    db: &DatabasePool,
    blob_oid: &str,
) -> Result<Option<DocumentExtraction>, AppError> {
    let row = sqlx::query!(
        r#"SELECT status AS "status: DocumentExtractionStatus", markdown, ocr, error
           FROM document_extractions
           WHERE blob_oid = $1"#,
        blob_oid,
    )
    .fetch_optional(db)
    .await?;
    Ok(row.and_then(|row| match row.status {
        DocumentExtractionStatus::Completed => Some(DocumentExtraction::Completed {
            markdown: row.markdown?,
            ocr: row.ocr?,
        }),
        DocumentExtractionStatus::Failed => Some(DocumentExtraction::Failed { error: row.error? }),
        // Only for clients, the column's CHECK rules it out.
        DocumentExtractionStatus::Unknown => None,
    }))
}

/// The Markdown of the completed extractions of `blob_oids`. Blobs without one are left out.
pub(crate) async fn get_markdowns(
    db: &DatabasePool,
    blob_oids: &[&str],
) -> Result<Vec<ExtractedMarkdown>, AppError> {
    let blob_oids = Json(blob_oids);
    let rows = sqlx::query_as!(
        ExtractedMarkdown,
        r#"SELECT blob_oid, markdown AS "markdown!", ocr AS "ocr!"
           FROM document_extractions
           WHERE status = 'COMPLETED'
             AND blob_oid IN (SELECT value FROM json_each($1))"#,
        blob_oids,
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Removes the extractions no repository or attachment refers to that were made before
/// `extracted_before`, so a document that is added back soon, e.g. by a reverted commit, is not
/// converted again.
pub(crate) async fn delete_unused_extractions(
    db: &DatabasePool,
    extracted_before: DateTime<Utc>,
) -> Result<u64, AppError> {
    // SQLite runs one write at a time, so no sync stores a reference while this deletes.
    let result = sqlx::query!(
        r#"DELETE FROM document_extractions
           WHERE extracted_at < $1
             AND NOT EXISTS (SELECT 1 FROM repository_documents r WHERE r.blob_oid = document_extractions.blob_oid)
             AND NOT EXISTS (SELECT 1 FROM attachments a WHERE a.blob_oid = document_extractions.blob_oid)"#,
        extracted_before,
    )
    .execute(db)
    .await?;
    Ok(result.rows_affected())
}
