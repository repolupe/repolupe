use super::mock_llm::{MockLlm, text_response, tool_result, tool_use_response};
use super::support::{SeededExtraction, TestApp, TestClient};
use axum::http::StatusCode;
use chrono::{DateTime, TimeDelta, Utc};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::SqlitePool;
use std::time::{Duration, Instant};
use uuid::Uuid;

const TEXT_PDF: &[u8] = include_bytes!("../fixtures/text.pdf");

/// Longest wait for the queued documents to be converted.
const CONVERSION_TIMEOUT: Duration = Duration::from_secs(30);

#[sqlx::test]
async fn tools_read_the_markdown_of_documents(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        tool_use_response(
            "toolu_1",
            "outline",
            json!({"repository": "docs", "path": "manual.pdf"}),
        ),
        tool_use_response(
            "toolu_2",
            "read_file",
            json!({"repository": "docs", "path": "manual.pdf", "offset": 3}),
        ),
        tool_use_response(
            "toolu_3",
            "read_file",
            json!({"repository": "docs", "path": "scan.pdf"}),
        ),
        tool_use_response(
            "toolu_4",
            "read_file",
            json!({"repository": "docs", "path": "new.pdf"}),
        ),
        tool_use_response(
            "toolu_5",
            "read_file",
            json!({"repository": "docs", "path": "invoice.pdf"}),
        ),
        tool_use_response(
            "toolu_6",
            "grep",
            json!({"repository": "docs", "pattern": "42|7731"}),
        ),
        text_response("The limit is 42."),
    ])
    .await;
    app.configure_llm(&llm).await;
    // The tools only look at the blob, not at the content
    let repo = app
        .seed_repository(
            alice.user_id,
            "docs",
            &[
                ("manual.pdf", "%PDF-1.7 manual"),
                ("scan.pdf", "%PDF-1.7 scan"),
                ("new.pdf", "%PDF-1.7 new"),
                ("invoice.pdf", "%PDF-1.7 invoice"),
            ],
        )
        .await;
    app.seed_extraction(
        &repo,
        "manual.pdf",
        SeededExtraction::Completed {
            markdown: "# Manual\n\nIntro\n\n## Limits\n\nThe limit is 42 requests.\n",
            ocr: false,
        },
    )
    .await;
    app.seed_extraction(
        &repo,
        "scan.pdf",
        SeededExtraction::Failed {
            error: "The file could not be converted, it may be damaged or encrypted",
        },
    )
    .await;
    app.seed_extraction(
        &repo,
        "invoice.pdf",
        SeededExtraction::Completed {
            markdown: "Invoice 7731\n",
            ocr: true,
        },
    )
    .await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "What is the limit?",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");

    let requests = llm.requests();
    assert_eq!(requests.len(), 7);
    let outline = tool_result(&requests[1]);
    assert_eq!(outline["is_error"], true, "{outline}");
    assert_eq!(
        outline["content"],
        "outline does not support PDFs. Use read_file for `manual.pdf`."
    );
    let read = tool_result(&requests[2]);
    assert_eq!(read["is_error"], false, "{read}");
    assert_eq!(
        read["content"],
        "3\tIntro\n4\t\n5\t## Limits\n6\t\n7\tThe limit is 42 requests."
    );
    let failed = tool_result(&requests[3]);
    assert_eq!(failed["is_error"], true, "{failed}");
    assert_eq!(
        failed["content"],
        "`scan.pdf` could not be converted to text. The file could not be converted, it may be damaged or encrypted."
    );
    let missing = tool_result(&requests[4]);
    assert_eq!(missing["is_error"], true, "{missing}");
    assert_eq!(
        missing["content"],
        "The text of `new.pdf` is not available yet, the file is waiting to be converted."
    );
    let ocr = tool_result(&requests[5]);
    assert_eq!(ocr["is_error"], false, "{ocr}");
    assert_eq!(
        ocr["content"],
        "[Scanned pages of `invoice.pdf` were recognized with OCR, their text may contain \
        errors.]\n\n1\tInvoice 7731"
    );
    // Line numbers as in read_file. Documents without text are counted.
    let grep = tool_result(&requests[6]);
    assert_eq!(grep["is_error"], false, "{grep}");
    assert_eq!(
        grep["content"],
        "2 matching lines in 2 files:\n\ninvoice.pdf\n1:Invoice 7731\n\nmanual.pdf\n\
        7:The limit is 42 requests.\n\n[Scanned pages of `invoice.pdf` were recognized with \
        OCR, their text may contain errors.]\n\n[2 documents not searched, they were not \
        converted to text (yet). read_file tells why.]"
    );
}

#[sqlx::test]
async fn converts_queued_documents(db: SqlitePool) {
    let app = TestApp::new(db.clone()).await;
    let alice = app.user("alice@example.com").await;
    let repo = app
        .seed_repository(
            alice.user_id,
            "docs",
            &[
                ("manual.pdf", TEXT_PDF),
                ("broken.pdf", b"%PDF-1.4\nnot really".as_slice()),
            ],
        )
        .await;
    // Converted with other settings, so it is converted again
    app.seed_extraction(
        &repo,
        "manual.pdf",
        SeededExtraction::Completed {
            markdown: "Old text",
            ocr: false,
        },
    )
    .await;
    // Not converted yet
    app.seed_document(&repo, "broken.pdf").await;

    let _tasks = app.start_background_tasks().await;
    let started = Instant::now();
    let rows = loop {
        let rows = sqlx::query!(
            r#"SELECT d.path, e.status, e.markdown, e.error
               FROM repository_documents d
                        JOIN document_extractions e ON e.blob_oid = d.blob_oid
               WHERE d.repository_id = $1 AND e.extractor <> 'seeded'
               ORDER BY d.path"#,
            repo.id,
        )
        .fetch_all(&db)
        .await
        .unwrap();
        if rows.len() == 2 {
            break rows;
        }
        assert!(
            started.elapsed() < CONVERSION_TIMEOUT,
            "documents were not converted"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    };

    let [broken, manual] = &rows[..] else {
        unreachable!()
    };
    assert_eq!(broken.path, "broken.pdf");
    assert_eq!(broken.status, "FAILED");
    assert_eq!(
        broken.error.as_deref(),
        Some("The file could not be converted, it may be damaged or encrypted")
    );
    assert_eq!(manual.path, "manual.pdf");
    assert_eq!(manual.status, "COMPLETED");
    let markdown = manual.markdown.as_deref().unwrap();
    assert!(markdown.contains("42 requests"), "{markdown}");

    let (status, body) = alice
        .get(&format!("/api/v1/repositories/{}/documents", repo.id))
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let documents = &body["documents"];
    assert_eq!(documents[0]["path"], "broken.pdf");
    assert_eq!(documents[0]["extraction"]["status"], "FAILED");
    assert_eq!(
        documents[0]["extraction"]["error"],
        "The file could not be converted, it may be damaged or encrypted"
    );
    assert_eq!(documents[0]["conversion"], Value::Null);
    assert_eq!(documents[1]["path"], "manual.pdf");
    assert_eq!(documents[1]["extraction"]["status"], "COMPLETED");
    assert_eq!(documents[1]["extraction"]["ocr"], false);
    assert_eq!(documents[1]["conversion"], Value::Null);
}

#[sqlx::test]
async fn converts_attachments_when_uploaded(db: SqlitePool) {
    let app = TestApp::new(db.clone()).await;
    let tasks = app.start_background_tasks().await;
    // The upload wakes the queue of its instance
    let alice = app.user("alice@example.com").await.on(&tasks);
    let (status, notes) = alice.upload("notes.txt", b"Notes").await;
    assert_eq!(status, StatusCode::CREATED, "{notes}");
    let (status, manual) = alice.upload("manual.pdf", TEXT_PDF).await;
    assert_eq!(status, StatusCode::CREATED, "{manual}");
    // By its extension, whatever the browser reported
    assert_eq!(manual["content_type"], "application/pdf");

    let blob = attachment_blob(&db, &manual).await;
    let (status, markdown) = wait_for_extraction(&db, &blob).await;
    assert_eq!(status, "COMPLETED");
    let markdown = markdown.unwrap();
    assert!(markdown.contains("42 requests"), "{markdown}");
    // Only documents are converted
    let notes_blob = attachment_blob(&db, &notes).await;
    let notes_extraction = sqlx::query_scalar!(
        r#"SELECT COUNT(*) AS "count!" FROM document_extractions WHERE blob_oid = $1"#,
        notes_blob,
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(notes_extraction, 0);
}

#[sqlx::test]
async fn reuses_the_extractions_of_attachments_saved_to_lfs(db: SqlitePool) {
    let app = TestApp::new(db.clone()).await;
    let alice = app.user("alice@example.com").await;
    let extractor = current_extractor(&app.admin()).await;
    // Not converted, since this instance has no background tasks
    let (status, attachment) = alice.upload("manual.pdf", TEXT_PDF).await;
    assert_eq!(status, StatusCode::CREATED, "{attachment}");
    let content_blob = attachment_blob(&db, &attachment).await;
    store_extraction(
        &db,
        &content_blob,
        "From the attachment",
        &extractor,
        Utc::now(),
    )
    .await;

    // The attachment, as `save_attachment` stores it on a path tracked with LFS
    let oid = hex::encode(Sha256::digest(TEXT_PDF));
    let pointer = format!(
        "version https://git-lfs.github.com/spec/v1\noid sha256:{oid}\nsize {}\n",
        TEXT_PDF.len()
    );
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("manual.pdf", pointer)])
        .await;
    let objects = app
        .repos_dir()
        .join(repo.id.to_string())
        .join("lfs/objects")
        .join(&oid[0..2])
        .join(&oid[2..4]);
    std::fs::create_dir_all(&objects).unwrap();
    std::fs::write(objects.join(&oid), TEXT_PDF).unwrap();
    let pointer_blob = app.seed_document(&repo, "manual.pdf").await;
    assert_ne!(pointer_blob, content_blob);

    let _tasks = app.start_background_tasks().await;
    let (status, markdown) = wait_for_extraction(&db, &pointer_blob).await;
    assert_eq!(status, "COMPLETED");
    // Copied, not converted again
    assert_eq!(markdown.as_deref(), Some("From the attachment"));
}

#[sqlx::test]
async fn keeps_the_extractions_of_attachments(db: SqlitePool) {
    let app = TestApp::new(db.clone()).await;
    let alice = app.user("alice@example.com").await;
    let extractor = current_extractor(&app.admin()).await;
    let (status, attachment) = alice.upload("manual.pdf", TEXT_PDF).await;
    assert_eq!(status, StatusCode::CREATED, "{attachment}");
    let blob = attachment_blob(&db, &attachment).await;
    let old = Utc::now() - TimeDelta::days(2);
    store_extraction(&db, &blob, "From the attachment", &extractor, old).await;
    let unused = "0".repeat(40);
    store_extraction(&db, &unused, "Unused", &extractor, old).await;

    // Cleans up right away
    let _tasks = app.start_background_tasks().await;
    let started = Instant::now();
    loop {
        let blobs =
            sqlx::query_scalar!("SELECT blob_oid FROM document_extractions ORDER BY blob_oid")
                .fetch_all(&db)
                .await
                .unwrap();
        if blobs == [blob.clone()] {
            break;
        }
        assert!(
            started.elapsed() < CONVERSION_TIMEOUT,
            "unused extractions were not removed: {blobs:?}"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

/// The blob of the uploaded `attachment`.
async fn attachment_blob(db: &SqlitePool, attachment: &Value) -> String {
    let id: Uuid = attachment["id"].as_str().unwrap().parse().unwrap();
    sqlx::query_scalar!("SELECT blob_oid FROM attachments WHERE id = $1", id)
        .fetch_one(db)
        .await
        .unwrap()
}

/// Identifies the current settings, see `GET /api/v1/document-extraction`.
async fn current_extractor(admin: &TestClient) -> String {
    let (status, overview) = admin.get("/api/v1/document-extraction").await;
    assert_eq!(status, StatusCode::OK, "{overview}");
    overview["extractor"].as_str().unwrap().to_string()
}

/// Stores a completed extraction of `blob_oid`, as if `extractor` made it at `extracted_at`.
async fn store_extraction(
    db: &SqlitePool,
    blob_oid: &str,
    markdown: &str,
    extractor: &str,
    extracted_at: DateTime<Utc>,
) {
    sqlx::query!(
        r#"INSERT INTO document_extractions (blob_oid, status, markdown, ocr, extractor, extracted_at)
           VALUES ($1, 'COMPLETED', $2, false, $3, $4)"#,
        blob_oid,
        markdown,
        extractor,
        extracted_at,
    )
    .execute(db)
    .await
    .unwrap();
}

/// Waits for an extraction of `blob_oid` and returns its status and Markdown.
async fn wait_for_extraction(db: &SqlitePool, blob_oid: &str) -> (String, Option<String>) {
    let started = Instant::now();
    loop {
        let row = sqlx::query!(
            "SELECT status, markdown FROM document_extractions WHERE blob_oid = $1",
            blob_oid,
        )
        .fetch_optional(db)
        .await
        .unwrap();
        if let Some(row) = row {
            return (row.status, row.markdown);
        }
        assert!(
            started.elapsed() < CONVERSION_TIMEOUT,
            "{blob_oid} was not converted"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

#[sqlx::test]
async fn lists_documents_with_their_conversion(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let repo = app
        .seed_repository(
            alice.user_id,
            "docs",
            &[
                ("manual.pdf", "%PDF-1.7 manual"),
                ("new.pdf", "%PDF-1.7 new"),
                ("README.md", "# Docs"),
            ],
        )
        .await;
    // Made with other settings, so it is converted again
    app.seed_extraction(
        &repo,
        "manual.pdf",
        SeededExtraction::Completed {
            markdown: "Old text",
            ocr: true,
        },
    )
    .await;
    app.seed_document(&repo, "new.pdf").await;
    let path = format!("/api/v1/repositories/{}/documents", repo.id);

    let (status, body) = alice.get(&path).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["paused_until"], Value::Null);
    let documents = body["documents"].as_array().unwrap();
    assert_eq!(documents.len(), 2, "{body}");
    assert_eq!(documents[0]["path"], "manual.pdf");
    assert_eq!(documents[0]["extraction"]["status"], "COMPLETED");
    assert_eq!(documents[0]["extraction"]["ocr"], true);
    assert_eq!(documents[0]["extraction"]["error"], Value::Null);
    assert_eq!(documents[0]["conversion"]["status"], "WAITING");
    assert_eq!(documents[1]["path"], "new.pdf");
    assert_eq!(documents[1]["extraction"], Value::Null);
    assert_eq!(documents[1]["conversion"]["status"], "WAITING");

    let (status, body) = bob.get(&path).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    let (status, body) = alice
        .post(
            &format!("/api/v1/repositories/{}/users", repo.id),
            json!({"user_name_or_email": "bob@example.com"}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (status, body) = bob.get(&path).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["documents"].as_array().unwrap().len(), 2);
}

#[sqlx::test]
async fn skips_documents_whose_lfs_object_is_missing(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let pointer = format!(
        "version https://git-lfs.github.com/spec/v1\noid sha256:{}\nsize 1234\n",
        "a".repeat(64)
    );
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("large.pdf", pointer)])
        .await;
    app.seed_document(&repo, "large.pdf").await;
    let path = format!("/api/v1/repositories/{}/documents", repo.id);

    let tasks = app.start_background_tasks().await;
    // The queue is only known to the instance converting the documents
    let alice = alice.on(&tasks);
    let started = Instant::now();
    let conversion = loop {
        let (status, body) = alice.get(&path).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        let conversion = &body["documents"][0]["conversion"];
        if conversion["status"] == "SKIPPED" {
            break conversion.clone();
        }
        assert!(
            started.elapsed() < CONVERSION_TIMEOUT,
            "document was not skipped: {body}"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    };
    assert_eq!(conversion["skip_reason"], "LFS_OBJECT_MISSING");
    assert!(conversion["retry_at"].is_string(), "{conversion}");

    let admin = app.admin().on(&tasks);
    let (status, overview) = admin.get("/api/v1/document-extraction").await;
    assert_eq!(status, StatusCode::OK, "{overview}");
    assert_eq!(overview["totals"]["skipped"], 1, "{overview}");
    assert_eq!(overview["totals"]["waiting"], 0, "{overview}");
    let (status, page) = admin
        .get("/api/v1/document-extraction/documents?filter=PENDING")
        .await;
    assert_eq!(status, StatusCode::OK, "{page}");
    assert_eq!(page["total"], 1, "{page}");
    let document = &page["items"][0];
    assert_eq!(document["conversion"]["status"], "SKIPPED", "{page}");
    let (status, body) = admin
        .post(
            "/api/v1/document-extraction/retry",
            json!({"blob_oid": document["blob_oid"]}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
}

#[sqlx::test]
async fn admins_see_the_documents_of_all_repositories(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;
    let handbooks = app
        .seed_repository(
            alice.user_id,
            "handbooks",
            &[
                ("done.pdf", "%PDF-1.7 done"),
                ("broken.pdf", "%PDF-1.7 broken"),
                ("new.pdf", "%PDF-1.7 new"),
            ],
        )
        .await;
    app.seed_extraction(
        &handbooks,
        "done.pdf",
        SeededExtraction::Completed {
            markdown: "Done",
            ocr: false,
        },
    )
    .await;
    app.seed_extraction(
        &handbooks,
        "broken.pdf",
        SeededExtraction::Failed { error: "Broken" },
    )
    .await;
    app.seed_document(&handbooks, "new.pdf").await;
    let docs = app
        .seed_repository(admin.user_id, "docs", &[("scan.pdf", "%PDF-1.7 scan")])
        .await;
    app.seed_extraction(
        &docs,
        "scan.pdf",
        SeededExtraction::Failed { error: "Broken" },
    )
    .await;

    let (status, overview) = admin.get("/api/v1/document-extraction").await;
    assert_eq!(status, StatusCode::OK, "{overview}");
    app.set_extractor(overview["extractor"].as_str().unwrap())
        .await;

    let (status, overview) = admin.get("/api/v1/document-extraction").await;
    assert_eq!(status, StatusCode::OK, "{overview}");
    assert_eq!(overview["converting"], Value::Null);
    assert_eq!(overview["paused"], Value::Null);
    assert_eq!(
        overview["totals"],
        json!({"documents": 4, "converted": 1, "failed": 2, "waiting": 1, "skipped": 0})
    );

    // By repository name and path
    let (status, page) = admin.get("/api/v1/document-extraction/documents").await;
    assert_eq!(status, StatusCode::OK, "{page}");
    assert_eq!(page["total"], 4);
    let documents: Vec<(&str, &str)> = page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|d| {
            (
                d["repository"]["name"].as_str().unwrap(),
                d["path"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        documents,
        [
            ("docs", "scan.pdf"),
            ("handbooks", "broken.pdf"),
            ("handbooks", "done.pdf"),
            ("handbooks", "new.pdf"),
        ]
    );
    assert_eq!(
        page["items"][0]["repository"],
        json!({"id": docs.id, "name": "docs", "owner_name": "admin", "readable": true})
    );
    assert_eq!(
        page["items"][1]["repository"],
        json!({"id": handbooks.id, "name": "handbooks", "owner_name": "alice", "readable": false})
    );
    assert_eq!(page["items"][1]["extraction"]["error"], "Broken");
    assert_eq!(page["items"][1]["conversion"], Value::Null);
    assert_eq!(page["items"][3]["conversion"]["status"], "WAITING");

    let (_, page) = admin
        .get("/api/v1/document-extraction/documents?filter=FAILED&offset=1&limit=1")
        .await;
    assert_eq!(page["total"], 2, "{page}");
    assert_eq!(page["items"].as_array().unwrap().len(), 1, "{page}");
    assert_eq!(page["items"][0]["path"], "broken.pdf", "{page}");
    let (_, page) = admin
        .get("/api/v1/document-extraction/documents?filter=CONVERTED")
        .await;
    assert_eq!(page["total"], 1, "{page}");
    assert_eq!(page["items"][0]["path"], "done.pdf", "{page}");
    let (_, page) = admin
        .get("/api/v1/document-extraction/documents?filter=PENDING")
        .await;
    assert_eq!(page["total"], 1, "{page}");
    assert_eq!(page["items"][0]["path"], "new.pdf", "{page}");
    let (status, body) = admin
        .get("/api/v1/document-extraction/documents?limit=0")
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");

    let broken = page_blob(&admin, "FAILED", "broken.pdf").await;
    let (status, body) = admin
        .post(
            "/api/v1/document-extraction/retry",
            json!({"blob_oid": broken}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (_, overview) = admin.get("/api/v1/document-extraction").await;
    assert_eq!(overview["totals"]["failed"], 1, "{overview}");
    assert_eq!(overview["totals"]["waiting"], 2, "{overview}");

    let (status, body) = admin
        .post(
            "/api/v1/document-extraction/retry",
            json!({"blob_oid": "0".repeat(40)}),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");

    let (status, body) = alice.get("/api/v1/document-extraction").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (status, body) = alice.get("/api/v1/document-extraction/documents").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (status, body) = alice
        .post(
            "/api/v1/document-extraction/retry",
            json!({"blob_oid": broken}),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
}

/// The blob of the document at `path` among those matching `filter`.
async fn page_blob(admin: &TestClient, filter: &str, path: &str) -> String {
    let (status, page) = admin
        .get(&format!(
            "/api/v1/document-extraction/documents?filter={filter}"
        ))
        .await;
    assert_eq!(status, StatusCode::OK, "{page}");
    page["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["path"] == path)
        .unwrap_or_else(|| panic!("{path} not in {page}"))["blob_oid"]
        .as_str()
        .unwrap()
        .to_string()
}
