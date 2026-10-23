use super::mock_llm::{MockLlm, text_response, tool_use_response};
use super::support::TestApp;
use axum::http::StatusCode;
use serde_json::json;
use sqlx::SqlitePool;

#[sqlx::test]
async fn shared_repository_is_readable_but_only_owner_manages_it(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;
    let path = format!("/api/v1/repositories/{}", repo.id);

    let (status, body) = alice
        .post(
            &format!("{path}/users"),
            json!({"user_name_or_email": "BOB@example.com"}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (status, users) = alice.get(&format!("{path}/users")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(users.as_array().unwrap().len(), 1);
    assert_eq!(users[0]["user_id"], json!(bob.user_id));
    assert_eq!(users[0]["email"], "bob@example.com");
    assert_eq!(users[0]["user_name"], "bob");

    let (status, body) = bob.get("/api/v1/repositories").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 1);
    assert_eq!(body[0]["id"], json!(repo.id));
    assert_eq!(body[0]["owner_id"], json!(alice.user_id));
    let (status, body) = bob.get(&path).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["head_commit_sha"], repo.commit_sha);

    let update = json!({
        "name": "mine",
        "remote": {
            "url": "https://example.com/seeded.git",
            "branch": "main",
            "poll_interval_seconds": 3600,
            "token": {"action": "KEEP"},
        },
    });
    for (path, body) in [
        (format!("{path}/update"), update),
        (format!("{path}/delete"), json!({})),
        (format!("{path}/sync"), json!({})),
        (
            format!("{path}/users"),
            json!({"user_name_or_email": "alice@example.com"}),
        ),
    ] {
        let (status, body) = bob.post(&path, body).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{path}: {body}");
        assert_eq!(body["code"], "FORBIDDEN");
    }
    let (status, _) = bob.get(&format!("{path}/users")).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, body) = alice.get(&path).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["name"], "docs");
}

#[sqlx::test]
async fn sharing_rejects_unknown_users_and_the_owner(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;
    let path = format!("/api/v1/repositories/{}/users", repo.id);

    let (status, body) = alice
        .post(&path, json!({"user_name_or_email": "nobody@example.com"}))
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["code"], "UNKNOWN_USER");

    let (status, body) = alice
        .post(&path, json!({"user_name_or_email": "alice"}))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "VALIDATION_ERROR");

    let (status, body) = alice
        .post(&path, json!({"user_name_or_email": "alice@example.com"}))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "VALIDATION_ERROR");

    let (_, users) = alice.get(&path).await;
    assert_eq!(users, json!([]));
}

#[sqlx::test]
async fn foreign_repository_cannot_be_shared(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;
    let path = format!("/api/v1/repositories/{}/users", repo.id);

    let (status, _) = bob
        .post(&path, json!({"user_name_or_email": "bob@example.com"}))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = bob.get(&path).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = bob.get(&format!("/api/v1/repositories/{}", repo.id)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn admin_can_share_any_repository(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;

    let (status, body) = app
        .admin()
        .post(
            &format!("/api/v1/repositories/{}/users", repo.id),
            json!({"user_name_or_email": "bob@example.com"}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");

    let (status, _) = bob.get(&format!("/api/v1/repositories/{}", repo.id)).await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test]
async fn shared_repository_is_used_in_chats_until_removed(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let llm = MockLlm::start(vec![
        tool_use_response(
            "toolu_1",
            "read_file",
            json!({"repository": "docs", "path": "README.md"}),
        ),
        text_response("It is about docs."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;
    let users = format!("/api/v1/repositories/{}/users", repo.id);
    let (status, _) = alice
        .post(&users, json!({"user_name_or_email": "bob@example.com"}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, chat) = bob
        .post(
            "/api/v1/chats",
            json!({
                "content": "What is the README about?",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let answer = bob.wait_for_answer(id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["tool_calls"][0]["repository_id"], json!(repo.id));
    assert_eq!(answer["tool_calls"][0]["status"], "COMPLETED");

    let (status, _) = alice
        .post(&format!("{users}/{}/delete", bob.user_id), json!({}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, _) = bob.get(&format!("/api/v1/repositories/{}", repo.id)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, chat) = bob.get(&format!("/api/v1/chats/{id}")).await;
    assert_eq!(chat["repository_ids"], json!([]));
    let (status, body) = bob
        .post(
            "/api/v1/chats",
            json!({"content": "Again?", "all_repositories": false, "repository_ids": [repo.id]}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["code"], "UNKNOWN_REPOSITORY");
}

#[sqlx::test]
async fn user_can_leave_shared_repository(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;
    let users = format!("/api/v1/repositories/{}/users", repo.id);
    let (status, _) = alice
        .post(&users, json!({"user_name_or_email": "bob@example.com"}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // Safe to retry
    for _ in 0..2 {
        let (status, _) = bob
            .post(&format!("{users}/{}/delete", bob.user_id), json!({}))
            .await;
        assert_eq!(status, StatusCode::NO_CONTENT);
    }
    let (_, body) = bob.get("/api/v1/repositories").await;
    assert_eq!(body, json!([]));

    // The owner cannot be removed
    let (status, _) = alice
        .post(&format!("{users}/{}/delete", alice.user_id), json!({}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = alice
        .get(&format!("/api/v1/repositories/{}", repo.id))
        .await;
    assert_eq!(status, StatusCode::OK);
}
