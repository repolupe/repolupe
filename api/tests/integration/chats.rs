use super::mock_llm::{MockLlm, error_response, stalled_response, text_response};
use super::support::TestApp;
use axum::http::StatusCode;
use serde_json::{Value, json};
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

#[sqlx::test]
async fn resends_a_message_without_the_ones_after_it(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let llm = MockLlm::start(vec![
        text_response("One"),
        text_response("Two"),
        text_response("Three"),
        text_response("Four"),
        stalled_response(),
    ])
    .await;
    app.configure_llm(&llm).await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "First?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let first = chat["messages"][0].clone();
    let first_id = first["id"].as_str().unwrap();
    let first_answer_id = chat["messages"][1]["id"].as_str().unwrap();
    alice.wait_for_answer(id).await;
    let (status, sent) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Second?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{sent}");
    alice.wait_for_answer(id).await;
    let resend = format!("/api/v1/chats/{id}/messages/{first_id}/resend");

    // Only the owner, only user messages, and not with a blank text
    let (status, body) = bob.post(&resend, json!({})).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages/{first_answer_id}/resend"),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    let (status, body) = alice.post(&resend, json!({"content": " "})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    let (_, unchanged) = alice.get(&format!("/api/v1/chats/{id}")).await;
    assert_eq!(unchanged["messages"].as_array().unwrap().len(), 4);

    // With a new text: the same message, sent now, and a new answer instead of all after it
    let (status, resent) = alice.post(&resend, json!({"content": "Edited?"})).await;
    assert_eq!(status, StatusCode::CREATED, "{resent}");
    assert_eq!(resent[0]["id"], first["id"]);
    assert_eq!(resent[0]["content"], "Edited?");
    assert_ne!(resent[0]["created_at"], first["created_at"]);
    assert_eq!(resent[1]["status"], "GENERATING");
    assert_eq!(alice.wait_for_answer(id).await["content"], "Three");
    let (_, chat) = alice.get(&format!("/api/v1/chats/{id}")).await;
    let ids: Vec<&Value> = chat["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|message| &message["id"])
        .collect();
    assert_eq!(ids, [&resent[0]["id"], &resent[1]["id"]]);
    let request = llm.requests()[2]["messages"].to_string();
    assert!(request.contains("Edited?"), "{request}");
    for removed in ["First?", "One", "Second?", "Two"] {
        assert!(!request.contains(removed), "{removed}: {request}");
    }

    // Without one: the text stays
    let (status, resent) = alice.post(&resend, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{resent}");
    assert_eq!(resent[0]["content"], "Edited?");
    assert_eq!(alice.wait_for_answer(id).await["content"], "Four");
    let request = llm.requests()[3]["messages"].to_string();
    assert!(request.contains("Edited?"), "{request}");
    assert!(!request.contains("Three"), "{request}");

    // Not while an answer is generated, which would be removed
    let (status, sent) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Third?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{sent}");
    llm.wait_for_stalled(1).await;
    let (status, body) = alice.post(&resend, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "GENERATION_IN_PROGRESS");
    let (_, chat) = alice.get(&format!("/api/v1/chats/{id}")).await;
    assert_eq!(chat["messages"].as_array().unwrap().len(), 4);
    let answer_id = sent[1]["id"].as_str().unwrap();
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages/{answer_id}/cancel"),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
}

#[sqlx::test]
async fn failed_answer_is_retried_by_resending_its_question(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        error_response("overloaded_error", "Partial"),
        text_response("Hello!"),
    ])
    .await;
    app.configure_llm(&llm).await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let question_id = chat["messages"][0]["id"].as_str().unwrap();
    let failed = alice.wait_for_answer(id).await;
    assert_eq!(failed["status"], "FAILED", "{failed}");

    let (status, resent) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages/{question_id}/resend"),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{resent}");
    assert_eq!(resent[0]["id"], question_id);
    assert_eq!(resent[0]["content"], "Hello?");
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["content"], "Hello!");

    // The new answer replaces the failed one, which the model does not see
    let (_, chat) = alice.get(&format!("/api/v1/chats/{id}")).await;
    let ids: Vec<&Value> = chat["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|message| &message["id"])
        .collect();
    assert_eq!(ids, [&resent[0]["id"], &resent[1]["id"]]);
    let request = llm.requests()[1]["messages"].to_string();
    assert!(!request.contains("Partial"), "{request}");
}

#[sqlx::test]
async fn resent_message_keeps_its_attachment(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        text_response("One"),
        text_response("Two"),
        text_response("Three"),
        text_response("Four"),
    ])
    .await;
    app.configure_llm(&llm).await;

    let (_, first) = alice.upload("first.txt", b"1").await;
    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Read it", "attachment_id": first["id"], "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let message_id = chat["messages"][0]["id"].as_str().unwrap();
    alice.wait_for_answer(id).await;
    let (_, second) = alice.upload("second.txt", b"2").await;
    let (status, sent) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "", "attachment_id": second["id"]}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{sent}");
    assert_eq!(sent[0]["attachment"]["number"], 2);
    alice.wait_for_answer(id).await;

    // The text may be removed, since the attachment stays
    let (status, resent) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages/{message_id}/resend"),
            json!({"content": ""}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{resent}");
    assert_eq!(resent[0]["content"], "");
    assert_eq!(resent[0]["attachment"]["id"], first["id"]);
    assert_eq!(resent[0]["attachment"]["number"], 1);
    alice.wait_for_answer(id).await;
    let request = llm.requests()[2]["messages"].to_string();
    assert!(request.contains("attachment 1, `first.txt`"), "{request}");
    assert!(!request.contains("second.txt"), "{request}");

    // The attachment of the removed message is gone, and its number is free again
    let second_id = second["id"].as_str().unwrap();
    let (status, _, _) = alice
        .get_raw(&format!("/api/v1/attachments/{second_id}"))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, third) = alice.upload("third.txt", b"3").await;
    let (status, sent) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "", "attachment_id": third["id"]}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{sent}");
    assert_eq!(sent[0]["attachment"]["number"], 2);
    alice.wait_for_answer(id).await;
}
