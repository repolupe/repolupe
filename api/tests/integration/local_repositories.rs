use super::local_remote::wait_for_commit;
use super::mock_llm::{MockLlm, text_response, tool_use_response};
use super::support::{TestApp, TestClient, git};
use axum::http::StatusCode;
use serde_json::{Value, json};
use sqlx::SqlitePool;
use std::time::{Duration, Instant};

fn local_request() -> Value {
    json!({
        "name": "notes",
        "allow_commits": true,
    })
}

/// Waits until the first sync of repository `id` created it, and returns its initial commit.
async fn wait_for_creation(client: &TestClient, id: &str) -> String {
    let started = Instant::now();
    loop {
        let (status, body) = client.get(&format!("/api/v1/repositories/{id}")).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert_eq!(body["last_error"], Value::Null, "{body}");
        if body["sync_status"] == "READY" {
            return body["head_commit_sha"].as_str().unwrap().to_string();
        }
        assert!(
            started.elapsed() < Duration::from_secs(30),
            "repository was not created: {body}"
        );
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

#[sqlx::test]
async fn creates_and_updates_local_repositories(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();

    // Nothing to contact, so it is created right away and synced by the background tasks.
    let (status, body) = admin.post("/api/v1/repositories", local_request()).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["remote"], Value::Null);
    assert_eq!(body["sync_status"], "PENDING");
    assert_eq!(body["can_commit"], true);
    assert!(body["next_sync_at"].is_string(), "{body}");
    let update_url = format!(
        "/api/v1/repositories/{}/update",
        body["id"].as_str().unwrap()
    );

    // A remote has all its settings.
    let mut incomplete = local_request();
    incomplete["remote"] = json!({"url": "https://example.com/notes.git", "branch": "main"});
    let (status, body) = admin.post("/api/v1/repositories", incomplete).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");

    // Stays local.
    let mut with_remote = local_request();
    with_remote["remote"] = json!({
        "url": "https://example.com/notes.git",
        "branch": "main",
        "poll_interval_seconds": 3600,
        "token": {"action": "KEEP"},
    });
    let (status, body) = admin.post(&update_url, with_remote).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    let mut renamed = local_request();
    renamed["name"] = json!("journal");
    let (status, body) = admin.post(&update_url, renamed).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["name"], "journal");
    assert_eq!(body["remote"], Value::Null);

    // And one with a remote keeps it.
    let seeded = app
        .seed_repository(admin.user_id, "seeded", &[("a.md", "a")])
        .await;
    let (status, body) = admin
        .post(
            &format!("/api/v1/repositories/{}/update", seeded.id),
            local_request(),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
}

#[sqlx::test]
async fn commits_to_local_repositories(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let create = |path: &str, content: &str| {
        json!({
            "repository": "notes",
            "path": path,
            "message": format!("Add {path}"),
            "content": content,
        })
    };
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "change_file", create("README.md", "# Notes\n")),
        text_response("Added."),
        tool_use_response("toolu_2", "change_file", create("README.md", "# Other\n")),
        text_response("Added."),
        tool_use_response("toolu_3", "change_file", create("docs/a.md", "A\n")),
        text_response("Added."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let (status, body) = app
        .admin()
        .post("/api/v1/repositories", local_request())
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    // Everything on the instance that syncs, which also commits, so they take turns.
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    let initial = wait_for_creation(&admin, &id).await;

    let mirror = app.repos_dir().join(&id);
    assert_eq!(
        git(&mirror, &["log", "--format=%an <%ae>|%s", "main"]),
        "Repolupe <noreply@repolupe.com>|Initial commit\n"
    );
    assert_eq!(git(&mirror, &["ls-tree", "-r", "main"]), "");
    let (_, body) = admin.get(&format!("/api/v1/repositories/{id}")).await;
    // Synced only when it changes.
    assert_eq!(body["next_sync_at"], Value::Null, "{body}");
    assert!(body["git_size"].as_i64().unwrap() > 0, "{body}");
    assert_eq!(body["lfs_size"], 0);

    let ask = async |client: &TestClient| {
        let (status, chat) = client
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Add it",
                    "all_repositories": false,
                    "repository_ids": [id],
                }),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let chat_id = chat["id"].as_str().unwrap();
        let answer = client.wait_for_answer(chat_id).await;
        let tool_call = &answer["tool_calls"][0];
        assert_eq!(tool_call["status"], "COMPLETED", "{answer}");
        format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}",
            tool_call["id"].as_str().unwrap()
        )
    };
    // All based on the initial commit.
    let notes = ask(&admin).await;
    let other = ask(&admin).await;
    let docs = ask(&admin).await;

    let (status, change) = admin.post(&format!("{notes}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    assert_eq!(change["pushed_branch"], "main");
    let committed = change["pushed_commit"].as_str().unwrap().to_string();
    // Nothing else moved the branch.
    assert_eq!(change["proposed_commit"], committed);
    assert_eq!(git(&mirror, &["rev-parse", "main"]).trim(), committed);
    assert_eq!(git(&mirror, &["show", "main:README.md"]), "# Notes\n");

    // The other proposal for the file was based on the initial commit, without it.
    let (status, change) = admin.post(&format!("{other}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "CONFLICT", "{change}");
    assert_eq!(git(&mirror, &["rev-parse", "main"]).trim(), committed);

    // Made again on top of the branch, since another file changed.
    let (status, change) = admin.post(&format!("{docs}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    let head = change["pushed_commit"].as_str().unwrap().to_string();
    assert_ne!(change["proposed_commit"], head);
    assert_eq!(
        git(&mirror, &["log", "--format=%s", "main"]),
        "Add docs/a.md\nAdd README.md\nInitial commit\n"
    );
    assert_eq!(git(&mirror, &["rev-parse", "main^^"]).trim(), initial);
    assert_eq!(git(&mirror, &["show", "main:docs/a.md"]), "A\n");
    assert_eq!(git(&mirror, &["show", "main:README.md"]), "# Notes\n");
    git(
        &mirror,
        &["fsck", "--strict", "--no-dangling", "--connectivity-only"],
    );

    // The sync picks it up.
    wait_for_commit(&admin, &id, &head).await;
    let (_, body) = admin.get(&format!("/api/v1/repositories/{id}")).await;
    assert_eq!(body["next_sync_at"], Value::Null, "{body}");
}
