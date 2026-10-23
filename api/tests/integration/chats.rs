use super::mock_llm::{MockLlm, text_response};
use super::support::TestApp;
use axum::http::StatusCode;
use serde_json::json;
use sqlx::SqlitePool;
use std::time::Duration;

#[sqlx::test]
async fn temporary_chats_are_not_listed(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![text_response("Hi!"), text_response("Hello!")]).await;
    app.configure_llm(&llm).await;

    let (status, temporary) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hi?", "all_repositories": true, "temporary": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{temporary}");
    assert_eq!(temporary["temporary"], true);
    let temporary_id = temporary["id"].as_str().unwrap();
    alice.wait_for_answer(temporary_id).await;
    let (status, regular) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{regular}");
    assert_eq!(regular["temporary"], false);
    alice.wait_for_answer(regular["id"].as_str().unwrap()).await;

    let (status, page) = alice.get("/api/v1/chats").await;
    assert_eq!(status, StatusCode::OK, "{page}");
    let ids: Vec<_> = page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|chat| chat["id"].clone())
        .collect();
    assert_eq!(ids, vec![regular["id"].clone()]);

    // Still readable by its id
    let (status, chat) = alice.get(&format!("/api/v1/chats/{temporary_id}")).await;
    assert_eq!(status, StatusCode::OK, "{chat}");
    assert_eq!(chat["temporary"], true);
    assert_eq!(chat["messages"].as_array().unwrap().len(), 2);
}

#[sqlx::test]
async fn removes_expired_temporary_chats(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        text_response("Expired"),
        text_response("Recent"),
        text_response("Kept"),
    ])
    .await;
    app.configure_llm(&llm).await;

    let mut ids = Vec::new();
    for (content, temporary) in [("Expired?", true), ("Recent?", true), ("Kept?", false)] {
        let (status, chat) = alice
            .post(
                "/api/v1/chats",
                json!({"content": content, "all_repositories": true, "temporary": temporary}),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let id = chat["id"].as_str().unwrap().to_string();
        alice.wait_for_answer(&id).await;
        ids.push(id);
    }
    let [expired, recent, kept] = &ids[..] else {
        unreachable!()
    };
    app.age_chat(expired).await;
    app.age_chat(kept).await;

    let _tasks = app.start_background_tasks().await;
    let removed = async {
        while alice.get(&format!("/api/v1/chats/{expired}")).await.0 != StatusCode::NOT_FOUND {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    };
    tokio::time::timeout(Duration::from_secs(10), removed)
        .await
        .expect("the expired temporary chat was not removed");

    for id in [recent, kept] {
        let (status, body) = alice.get(&format!("/api/v1/chats/{id}")).await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }
}
