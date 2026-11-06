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

#[sqlx::test]
async fn searches_chats(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let llm = MockLlm::start(vec![
        text_response("Sync mirrors 1000 repositories."),
        text_response("Tokens are 100% encrypted."),
        text_response("Sync is not listed."),
        text_response("Sync belongs to Bob."),
    ])
    .await;
    app.configure_llm(&llm).await;

    let mut ids = Vec::new();
    for (user, content, temporary) in [
        (&alice, "How does sync work?", false),
        (&alice, "Where are tokens stored?", false),
        (&alice, "Temporary sync?", true),
        (&bob, "Bob's sync?", false),
    ] {
        let (status, chat) = user
            .post(
                "/api/v1/chats",
                json!({"content": content, "all_repositories": true, "temporary": temporary}),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let id = chat["id"].as_str().unwrap().to_string();
        user.wait_for_answer(&id).await;
        ids.push(id);
    }
    let (sync, tokens) = (&ids[0], &ids[1]);
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{tokens}/update"),
            json!({"title": "Secrets"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let search = async |query: &str| -> Vec<String> {
        let (status, page) = alice.get(&format!("/api/v1/chats/search?{query}")).await;
        assert_eq!(status, StatusCode::OK, "{page}");
        page["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|chat| chat["id"].as_str().unwrap().to_string())
            .collect()
    };
    // In the first message, ignoring case, but not in temporary or other users' chats
    assert_eq!(search("query=SYNC").await, vec![sync.clone()]);
    // In the title
    assert_eq!(search("query=secrets").await, vec![tokens.clone()]);
    // Every word, in any message
    assert_eq!(search("query=+mirrors%20work+").await, vec![sync.clone()]);
    assert!(search("query=sync+secrets").await.is_empty());
    // Wildcards are matched literally
    assert_eq!(search("query=100%25").await, vec![tokens.clone()]);
    assert!(search("query=1_00").await.is_empty());

    // Newest first, one page at a time
    let (status, page) = alice.get("/api/v1/chats/search?query=re&limit=1").await;
    assert_eq!(status, StatusCode::OK, "{page}");
    assert_eq!(page["items"][0]["id"], tokens.as_str());
    let cursor = page["next_cursor"].as_str().unwrap();
    let (status, page) = alice
        .get(&format!(
            "/api/v1/chats/search?query=re&limit=1&cursor={cursor}"
        ))
        .await;
    assert_eq!(status, StatusCode::OK, "{page}");
    assert_eq!(page["items"][0]["id"], sync.as_str());
    assert!(page["next_cursor"].is_null(), "{page}");

    for query in ["query=+", "query=", ""] {
        let (status, body) = alice.get(&format!("/api/v1/chats/search?{query}")).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{query}: {body}");
    }
}
