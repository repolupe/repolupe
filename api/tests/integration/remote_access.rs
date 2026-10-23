use super::local_remote::{LocalRemote, wait_for_commit};
use super::mock_llm::{MockLlm, text_response, tool_result, tool_use_response};
use super::support::{TestApp, TestClient};
use axum::http::StatusCode;
use chrono::{DateTime, TimeDelta, Utc};
use serde_json::{Value, json};
use sqlx::SqlitePool;
use std::time::{Duration, Instant};

async fn create_repository(client: &TestClient, remote_url: &str) -> (StatusCode, Value) {
    client
        .post(
            "/api/v1/repositories",
            json!({
                "name": "internal",
                "remote": {
                    "url": remote_url,
                    "branch": "main",
                    "poll_interval_seconds": 3600,
                },
            }),
        )
        .await
}

/// Waits until the sync loop has left `PENDING` and returns the repository.
async fn wait_for_sync(client: &TestClient, id: &str) -> Value {
    let started = Instant::now();
    loop {
        let (status, body) = client.get(&format!("/api/v1/repositories/{id}")).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        if body["sync_status"] != "PENDING" && body["sync_status"] != "SYNCING" {
            return body;
        }
        assert!(
            started.elapsed() < Duration::from_secs(30),
            "repository was not synced"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

fn timestamp(value: &Value) -> DateTime<Utc> {
    value.as_str().unwrap().parse().unwrap()
}

#[sqlx::test]
async fn admin_can_use_private_http_remote(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;

    let (status, body) = create_repository(&app.admin(), &remote.url).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["remote"]["url"], remote.url);
    assert_eq!(body["remote"]["branch"], "main");
    assert_eq!(body["remote"]["poll_interval_seconds"], 3600);
    assert_eq!(body["remote"]["token"], Value::Null);
    assert_eq!(body["sync_status"], "PENDING");
    assert!(remote.requests() > 0);
}

#[sqlx::test]
async fn user_cannot_use_private_remote(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let remote = LocalRemote::start().await;

    let (status, body) = create_repository(&alice, &remote.url).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["message"], "Remote URL must use https://");

    let https = remote.url.replacen("http://", "https://", 1);
    let (status, body) = create_repository(&alice, &https).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(
        body["message"],
        "Remote URL must not point to a private or reserved address"
    );

    assert_eq!(remote.requests(), 0);
}

#[sqlx::test]
async fn sync_records_the_commit_and_schedules_the_next_one(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    let (status, body) = create_repository(&app.admin(), &remote.url).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();

    let tasks = app.start_background_tasks().await;
    let body = wait_for_sync(&app.admin().on(&tasks), &id).await;
    assert_eq!(body["sync_status"], "READY", "{body}");
    assert_eq!(body["head_commit_sha"], remote.head());
    assert_eq!(body["last_error"], Value::Null);
    let synced_at = timestamp(&body["last_synced_at"]);
    // After the poll interval, at millisecond precision
    let next_sync_at = timestamp(&body["next_sync_at"]);
    assert!(
        (next_sync_at - synced_at - TimeDelta::seconds(3600)).abs() < TimeDelta::milliseconds(1),
        "{body}"
    );
}

#[sqlx::test]
async fn failed_sync_is_retried_after_the_poll_interval(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    let (status, body) = create_repository(&app.admin(), &remote.url).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    drop(remote);

    let before = Utc::now();
    let tasks = app.start_background_tasks().await;
    let body = wait_for_sync(&app.admin().on(&tasks), &id).await;
    assert_eq!(body["sync_status"], "FAILED", "{body}");
    assert!(body["last_error"].is_string(), "{body}");
    assert_eq!(body["head_commit_sha"], Value::Null);
    let next_sync_at = timestamp(&body["next_sync_at"]);
    assert!(next_sync_at > before + TimeDelta::seconds(3599), "{body}");
    assert!(
        next_sync_at < Utc::now() + TimeDelta::seconds(3600),
        "{body}"
    );
}

#[sqlx::test]
async fn sync_fetches_new_and_rewritten_commits(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    let (status, body) = create_repository(&app.admin(), &remote.url).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    wait_for_commit(&admin, &id, &remote.head()).await;

    let pushed = remote.push_commit(&[("guide.md", "# Guide")]);
    let (status, body) = admin
        .post(&format!("/api/v1/repositories/{id}/sync"), json!({}))
        .await;
    assert_eq!(status, StatusCode::ACCEPTED, "{body}");
    wait_for_commit(&admin, &id, &pushed).await;

    // E.g. after a force push. Requested by the database, a second request is throttled.
    let replaced = remote.replace_branch(&[("other.md", "# Other")]);
    app.request_sync_now(&id).await;
    wait_for_commit(&admin, &id, &replaced).await;
}

#[sqlx::test]
async fn token_is_sent_to_the_remote(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start_with_token(Some("secret")).await;

    let (status, body) = create_repository(&app.admin(), &remote.url).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "AUTH_FAILED", "{body}");

    let (status, body) = app
        .admin()
        .post(
            "/api/v1/repositories",
            json!({
                "name": "internal",
                "remote": {
                    "url": remote.url,
                    "branch": "main",
                    "poll_interval_seconds": 3600,
                    "token": "secret",
                },
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let tasks = app.start_background_tasks().await;
    wait_for_commit(&app.admin().on(&tasks), &id, &remote.head()).await;
}

#[sqlx::test]
async fn missing_branch_is_rejected(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    let (status, body) = app
        .admin()
        .post(
            "/api/v1/repositories",
            json!({
                "name": "internal",
                "remote": {
                    "url": remote.url,
                    "branch": "mai",
                    "poll_interval_seconds": 3600,
                },
            }),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "BRANCH_NOT_FOUND", "{body}");

    let missing = remote.url.replace("repo.git", "missing.git");
    let (status, body) = create_repository(&app.admin(), &missing).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "REPO_NOT_FOUND", "{body}");
}

#[sqlx::test]
async fn tools_read_and_search_small_text_files_in_lfs(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    let notes = remote.add_lfs_object(b"= Rent\nThe rent is 900 EUR.\n");
    let photo = remote.add_lfs_object(b"\x89PNG\r\n\x1a\n\0photo");
    let large = remote.add_lfs_object(&vec![b'a'; 1024 * 1024 + 1]);
    let commit = remote.push_commit(&[
        ("notes.typ", &notes),
        ("photo.png", &photo),
        ("large.typ", &large),
    ]);
    let read = |id: &str, path: &str| {
        tool_use_response(
            id,
            "read_file",
            json!({"repository": "internal", "path": path}),
        )
    };
    let llm = MockLlm::start(vec![
        read("toolu_1", "notes.typ"),
        read("toolu_2", "photo.png"),
        read("toolu_3", "large.typ"),
        tool_use_response(
            "toolu_4",
            "grep",
            json!({"repository": "internal", "pattern": "rent|photo|aaa"}),
        ),
        text_response("The rent is 900 EUR."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let (status, body) = create_repository(&app.admin(), &remote.url).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    wait_for_commit(&admin, &id, &commit).await;

    let (status, chat) = admin
        .post(
            "/api/v1/chats",
            json!({
                "content": "How much is the rent?",
                "all_repositories": false,
                "repository_ids": [id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = admin.wait_for_answer(chat["id"].as_str().unwrap()).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");

    let results: Vec<Value> = llm.requests()[1..].iter().map(tool_result).collect();
    assert_eq!(results[0]["is_error"], false, "{}", results[0]);
    assert_eq!(results[0]["content"], "1\t= Rent\n2\tThe rent is 900 EUR.");
    for (result, path) in results[1..3].iter().zip(["photo.png", "large.typ"]) {
        assert_eq!(result["is_error"], true, "{result}");
        assert_eq!(
            result["content"],
            format!("`{path}` can't be shown, its content was not downloaded.")
        );
    }
    // The files that were not downloaded are skipped.
    assert_eq!(results[3]["is_error"], false, "{}", results[3]);
    assert_eq!(
        results[3]["content"],
        "1 matching line in 1 file:\n\nnotes.typ\n2:The rent is 900 EUR."
    );
}
