use super::support::{INSTANCE_NAME, TestApp};
use axum::body::Body;
use axum::http::{Method, Request, StatusCode, header};
use serde_json::json;
use sqlx::SqlitePool;

#[sqlx::test]
async fn foreign_repository_is_not_found(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let repo = app
        .seed_repository(alice.user_id, "docs", &[("README.md", "# Docs")])
        .await;
    let path = format!("/api/v1/repositories/{}", repo.id);

    let (status, body) = bob.get(&path).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "NOT_FOUND");

    // Deletes are idempotent, so this succeeds without deleting anything
    let (status, _) = bob.post(&format!("{path}/delete"), json!({})).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, body) = alice.get(&path).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["sync_status"], "READY");
    assert_eq!(body["head_commit_sha"], repo.commit_sha);
}

#[sqlx::test]
async fn post_without_json_content_type_is_rejected(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;

    // What a cross-site form could send with the session cookie
    let request = alice
        .request(Method::POST, "/api/v1/chats")
        .header(header::CONTENT_TYPE, "text/plain")
        .body(Body::from(r#"{"content": "Hi", "all_repositories": true}"#))
        .unwrap();
    let (status, body) = alice.send(request).await;
    assert_eq!(status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    assert_eq!(body["code"], "UNSUPPORTED_MEDIA_TYPE");

    let (_, body) = alice.get("/api/v1/chats").await;
    assert_eq!(body["items"], json!([]));
}

#[sqlx::test]
async fn admin_routes_require_admin(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;

    let (status, body) = alice.get("/api/v1/users").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["code"], "FORBIDDEN");

    let (status, body) = admin.get("/api/v1/users").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 2);
}

#[sqlx::test]
async fn provider_suggestions_are_for_admins(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;

    let (status, _) = alice.get("/api/v1/llm-providers/suggestions").await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, body) = app.admin().get("/api/v1/llm-providers/suggestions").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body[0],
        json!({
            "name": "Anthropic",
            "api_format": "ANTHROPIC",
            "base_url": "https://api.anthropic.com",
            "currency": "USD",
            "country_code": "US",
            "runs_inference": true,
            "model_brand": "Claude",
        })
    );
}

#[sqlx::test]
async fn instance_is_public(db: SqlitePool) {
    let app = TestApp::new(db).await;

    let request = Request::builder()
        .uri("/api/v1/instance")
        .body(Body::empty())
        .unwrap();
    let (status, body) = app.admin().send(request).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, json!({"name": INSTANCE_NAME}));
}

#[sqlx::test]
async fn unknown_routes_are_not_found_for_everyone(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;

    for client in [&admin, &alice] {
        let (status, _) = client.get("/api/v1/unknown").await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        let (status, _) = client.post("/api/v1/chats/unknown/route", json!({})).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
    }
    let request = Request::builder()
        .uri("/api/v1/unknown")
        .body(Body::empty())
        .unwrap();
    let (status, _) = alice.send(request).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Known routes still require a session.
    let request = Request::builder()
        .uri("/api/v1/chats")
        .body(Body::empty())
        .unwrap();
    let (status, body) = alice.send(request).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["code"], "UNAUTHORIZED");
}
