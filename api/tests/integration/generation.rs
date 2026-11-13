use super::mock_llm::{
    MODELS, MockLlm, error_response, gated, stalled_response, text_and_tool_use_response,
    text_response, tool_result, tool_use_response,
};
use super::support::{TestApp, png, read_events};
use axum::http::StatusCode;
use serde_json::{Value, json};
use sqlx::SqlitePool;

#[sqlx::test]
async fn answers_with_tool_call_on_seeded_repository(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        text_and_tool_use_response(
            "Let me look at main.",
            "toolu_1",
            "read_file",
            json!({"repository": "demo", "path": "src/main.rs"}),
        ),
        text_response("It prints hello."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(
            alice.user_id,
            "demo",
            &[("src/main.rs", "fn main() {\n    println!(\"hello\");\n}\n")],
        )
        .await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "What does main print?",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;

    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["content"], "It prints hello.");
    let timestamp = |key: &str| {
        serde_json::from_value::<chrono::DateTime<chrono::Utc>>(answer[key].clone()).unwrap()
    };
    assert!(
        timestamp("finished_at") >= timestamp("created_at"),
        "{answer}"
    );
    let tool_calls = answer["tool_calls"].as_array().unwrap();
    assert_eq!(tool_calls.len(), 1);
    assert_eq!(tool_calls[0]["name"], "read_file");
    assert_eq!(tool_calls[0]["status"], "COMPLETED");
    assert_eq!(tool_calls[0]["repository_id"], json!(repo.id));
    assert_eq!(tool_calls[0]["commit_sha"], repo.commit_sha);
    assert!(tool_calls[0]["duration_ms"].is_u64(), "{answer}");

    // The second request carries the file, read from the seeded commit, after the preamble
    // that was dropped from the answer
    let requests = llm.requests();
    assert_eq!(requests.len(), 2);
    let messages = requests[1]["messages"].as_array().unwrap();
    let preamble = &messages[messages.len() - 2]["content"][0];
    assert_eq!(preamble["type"], "text");
    assert_eq!(preamble["text"], "Let me look at main.");
    let result = tool_result(&requests[1]);
    assert_eq!(result["tool_use_id"], "toolu_1");
    assert_eq!(result["is_error"], false);
    assert!(
        result["content"]
            .as_str()
            .unwrap()
            .contains(r#"println!("hello");"#),
        "{result}"
    );
}

#[sqlx::test]
async fn failing_llm_fails_the_answer(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    // Nothing scripted, every request is rejected
    let llm = MockLlm::start(vec![]).await;
    app.configure_llm(&llm).await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;

    assert_eq!(answer["status"], "FAILED", "{answer}");
    assert!(answer["error"].is_string());

    // Another message can be sent afterwards, the generation was released
    let id = chat["id"].as_str().unwrap();
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Still there?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(alice.wait_for_answer(id).await["status"], "FAILED");
}

#[sqlx::test]
async fn rejected_messages_do_not_count_as_generations(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![text_response("Hi.")]).await;
    app.configure_llm(&llm).await;

    // More than a user may have generated at the same time
    for _ in 0..5 {
        let (status, body) = alice
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Hello?",
                    "all_repositories": true,
                    "attachment_id": "0193a5e0-0000-7000-8000-000000000000",
                }),
            )
            .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
        assert_eq!(body["code"], "UNKNOWN_ATTACHMENT");
    }

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
}

#[sqlx::test]
async fn retries_errors_before_the_first_text(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        error_response("overloaded_error", ""),
        text_response("Hello!"),
        // After text was shown, the error fails the answer
        error_response("overloaded_error", "Hel"),
        text_response("Not requested"),
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
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["content"], "Hello!");
    assert_eq!(llm.requests().len(), 2);

    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Again?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["status"], "FAILED", "{answer}");
    assert_eq!(answer["content"], "Hel");
    assert_eq!(llm.requests().len(), 3);
}

#[sqlx::test]
async fn foreign_delete_does_not_stop_the_answer(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let llm = MockLlm::start(vec![stalled_response()]).await;
    app.configure_llm(&llm).await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let delete = format!("/api/v1/chats/{id}/delete");
    llm.wait_for_stalled(1).await;

    let (status, _) = bob.post(&delete, json!({})).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(llm.stalled(), 1);
    let (status, body) = alice.get(&format!("/api/v1/chats/{id}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["messages"][1]["status"], "GENERATING", "{body}");

    // The owner's delete still stops it
    let (status, _) = alice.post(&delete, json!({})).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    llm.wait_for_stalled(0).await;
}

#[sqlx::test]
async fn chat_model_overrides_the_users_model(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![text_response("First."), text_response("Second.")]).await;
    let configured = app.configure_llm(&llm).await;
    let default_model = configured.model_id;
    let (status, other) = admin
        .post(
            &format!("/api/v1/llm-providers/{}/models", configured.provider_id),
            json!({"api_name": "other-model", "display_name": "Other Model"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{other}");
    let other_model = other["id"].as_str().unwrap();
    let (status, body) = alice
        .post("/api/v1/me/default-model", json!({"model_id": other_model}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");

    // Chosen for the chat, so it wins over the user's model
    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true, "model_id": default_model}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    assert_eq!(chat["model_id"], json!(default_model));
    let id = chat["id"].as_str().unwrap();
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["model_id"], json!(default_model));
    assert_eq!(answer["model_name"], "Mock Model");

    // Without a model of its own, the chat uses the user's model
    let update = format!("/api/v1/chats/{id}/update");
    let (status, updated) = alice.post(&update, json!({"title": "Hello"})).await;
    assert_eq!(status, StatusCode::OK, "{updated}");
    assert_eq!(updated["model_id"], json!(null));
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Again?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body[0]["model_id"], json!(null));
    assert_eq!(body[0]["model_name"], json!(null));
    assert_eq!(body[1]["model_id"], json!(other_model));
    assert_eq!(body[1]["model_name"], "Other Model");
    assert_eq!(alice.wait_for_answer(id).await["status"], "COMPLETED");

    let requests = llm.requests();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0]["model"], "mock-model");
    assert_eq!(requests[1]["model"], "other-model");

    // Unknown models are rejected
    let unknown = uuid::Uuid::now_v7();
    let (status, body) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true, "model_id": unknown}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "UNKNOWN_MODEL");
    let (status, body) = alice
        .post(
            &update,
            json!({"title": "Hello", "all_repositories": true, "model_id": unknown}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "UNKNOWN_MODEL");

    // Deleting a model clears it from the chat and the answers it wrote, which keep its name
    let (status, body) = alice
        .post(
            &update,
            json!({"title": "Hello", "all_repositories": true, "model_id": other_model}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, _) = admin
        .post(&format!("/api/v1/models/{other_model}/delete"), json!({}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, body) = alice.get(&format!("/api/v1/chats/{id}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["model_id"], json!(null));
    let model_ids: Vec<_> = body["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["model_id"].clone())
        .collect();
    assert_eq!(
        model_ids,
        vec![json!(null), json!(default_model), json!(null), json!(null)]
    );
    let model_names: Vec<_> = body["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["model_name"].clone())
        .collect();
    assert_eq!(
        model_names,
        vec![
            json!(null),
            json!("Mock Model"),
            json!(null),
            json!("Other Model")
        ]
    );
}

#[sqlx::test]
async fn records_usage_and_cost_of_all_rounds(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    // Each response uses 1 input and 1 output token
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "unknown_tool", json!({})),
        text_response("Done."),
        text_response("Free."),
    ])
    .await;
    let configured = app.configure_llm(&llm).await;
    let (status, model) = app
        .admin()
        .post(
            &format!("/api/v1/models/{}/update", configured.model_id),
            json!({"api_name": "mock-model", "display_name": "Mock Model", "input_price": "3", "output_price": "15.50"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{model}");
    assert_eq!(model["input_price"], "3");
    assert_eq!(model["output_price"], "15.50");
    assert_eq!(model["cache_read_price"], json!(null));

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let answer = alice.wait_for_answer(id).await;

    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(
        answer["usage"],
        json!({"input_tokens": 2, "output_tokens": 2, "cache_read_tokens": 0, "cache_write_tokens": 0})
    );
    assert!(answer["response_ms"].is_u64(), "{answer}");
    // (2 * 3 + 2 * 15.50) / 1M, the cache charged at the input price
    assert_eq!(
        answer["cost"],
        json!({
            "amount": "0.000037",
            "currency": "EUR",
            "prices": {"input": "3", "output": "15.50", "cache_read": "3", "cache_write": "3"},
        })
    );

    // Without prices, the usage is still recorded but there is no cost
    let (status, model) = app
        .admin()
        .post(
            &format!("/api/v1/models/{}/update", configured.model_id),
            json!({"api_name": "mock-model", "display_name": "Mock Model"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{model}");
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Again?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body[1]["usage"], json!(null));
    assert_eq!(body[1]["response_ms"], json!(null));
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["usage"]["input_tokens"], 1, "{answer}");
    assert_eq!(answer["cost"], json!(null));
}

#[sqlx::test]
async fn streams_the_usage_after_each_round(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    // Held back, so the stream is open before the first round ends
    let (first, gate) = gated(tool_use_response("toolu_1", "unknown_tool", json!({})));
    let llm = MockLlm::start(vec![first, text_response("Done.")]).await;
    let configured = app.configure_llm(&llm).await;
    let (status, model) = app
        .admin()
        .post(
            &format!("/api/v1/models/{}/update", configured.model_id),
            json!({"api_name": "mock-model", "display_name": "Mock Model", "input_price": "3", "output_price": "15.50"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{model}");

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hello?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let message_id = chat["messages"][1]["id"].as_str().unwrap();
    let stream = alice.open_stream(id, message_id).await;
    gate.notify_one();
    let events = read_events(stream).await;

    let (name, snapshot) = &events[0];
    assert_eq!(name, "snapshot");
    assert_eq!(snapshot["usage"], json!(null), "{snapshot}");
    assert_eq!(snapshot["cost"], json!(null), "{snapshot}");
    assert_eq!(snapshot["response_ms"], json!(null), "{snapshot}");
    // Each response uses 1 input and 1 output token, the totals so far are sent after each
    let mut updates: Vec<Value> = events
        .iter()
        .filter(|(name, _)| name == "usage")
        .map(|(_, data)| data.clone())
        .collect();
    // The time of the responses so far, which only grows
    let response_ms: Vec<u64> = updates
        .iter_mut()
        .map(|update| {
            let ms = update.as_object_mut().unwrap().remove("response_ms");
            ms.and_then(|ms| ms.as_u64()).expect("response_ms")
        })
        .collect();
    assert!(response_ms[0] <= response_ms[1], "{response_ms:?}");
    let prices = json!({"input": "3", "output": "15.50", "cache_read": "3", "cache_write": "3"});
    assert_eq!(
        updates,
        [
            json!({
                "usage": {"input_tokens": 1, "output_tokens": 1, "cache_read_tokens": 0, "cache_write_tokens": 0},
                "cost": {"amount": "0.0000185", "currency": "EUR", "prices": prices},
            }),
            json!({
                "usage": {"input_tokens": 2, "output_tokens": 2, "cache_read_tokens": 0, "cache_write_tokens": 0},
                "cost": {"amount": "0.000037", "currency": "EUR", "prices": prices},
            }),
        ],
        "{events:?}"
    );
    // The last one matches the final message
    let (name, done) = events.last().unwrap();
    assert_eq!(name, "done");
    assert_eq!(done["status"], "COMPLETED", "{done}");
    assert_eq!(done["usage"], updates[1]["usage"]);
    assert_eq!(done["cost"], updates[1]["cost"]);
    assert_eq!(done["response_ms"], response_ms[1]);
}

#[sqlx::test]
async fn snapshot_has_the_usage_so_far(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "unknown_tool", json!({})),
        stalled_response(),
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
    let message_id = chat["messages"][1]["id"].as_str().unwrap();
    // The first round is done once the second request is stalled
    llm.wait_for_stalled(1).await;
    let stream = alice.open_stream(id, message_id).await;
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages/{message_id}/cancel"),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let events = read_events(stream).await;

    let names: Vec<&str> = events.iter().map(|(name, _)| name.as_str()).collect();
    assert_eq!(names, ["snapshot", "done"], "{events:?}");
    let usage = json!({"input_tokens": 1, "output_tokens": 1, "cache_read_tokens": 0, "cache_write_tokens": 0});
    let (snapshot, done) = (&events[0].1, &events[1].1);
    assert_eq!(snapshot["status"], "GENERATING", "{snapshot}");
    assert_eq!(snapshot["model_name"], "Mock Model", "{snapshot}");
    assert_eq!(snapshot["usage"], usage, "{snapshot}");
    assert!(snapshot["response_ms"].is_u64(), "{snapshot}");
    // No prices, so no cost
    assert_eq!(snapshot["cost"], json!(null), "{snapshot}");
    // The response that was cut off reports no tokens
    assert_eq!(done["status"], "CANCELLED", "{done}");
    assert_eq!(done["usage"], usage, "{done}");
    // Nor its time
    assert_eq!(done["response_ms"], snapshot["response_ms"], "{done}");
}

#[sqlx::test]
async fn model_names_must_be_unique(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let llm = MockLlm::start(vec![]).await;
    let configured = app.configure_llm(&llm).await;
    let route = format!("/api/v1/llm-providers/{}/models", configured.provider_id);

    // The display name is unique among all models, ignoring case
    let (status, body) = admin
        .post(
            &route,
            json!({"api_name": "other-model", "display_name": "mock model"}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "NAME_TAKEN");

    // The API name only per provider
    let (status, body) = admin
        .post(
            &route,
            json!({"api_name": "mock-model", "display_name": "Other Model"}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "NAME_TAKEN");

    // Without a display name, users see the API name, which then must be unique as well
    let (status, body) = admin
        .post(
            &route,
            json!({"api_name": "other-model", "display_name": " "}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["display_name"], json!(null));
    let (status, models) = admin.get("/api/v1/models").await;
    assert_eq!(status, StatusCode::OK, "{models}");
    let names: Vec<_> = models
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["display_name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Mock Model", "other-model"]);

    // A display name that is the API name is not stored
    let (status, body) = admin
        .post(
            &format!("/api/v1/models/{}/update", body["id"].as_str().unwrap()),
            json!({"api_name": "other-model", "display_name": " other-model "}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["display_name"], json!(null));
    let (status, body) = admin
        .post(
            &route,
            json!({"api_name": "third-model", "display_name": "Other-Model"}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "NAME_TAKEN");
}

#[sqlx::test]
async fn default_model_moves_but_cannot_be_unset(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let llm = MockLlm::start(vec![]).await;
    let configured = app.configure_llm(&llm).await;
    let (status, other) = admin
        .post(
            &format!("/api/v1/llm-providers/{}/models", configured.provider_id),
            json!({"api_name": "other-model"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{other}");
    assert_eq!(other["is_default"], false);
    let other_model = other["id"].as_str().unwrap();
    let defaults = || async {
        let (status, models) = admin.get("/api/v1/models").await;
        assert_eq!(status, StatusCode::OK, "{models}");
        models
            .as_array()
            .unwrap()
            .iter()
            .filter(|m| m["is_default"] == true)
            .map(|m| m["id"].as_str().unwrap().to_string())
            .collect::<Vec<_>>()
    };

    // Making another model the default clears the flag of the previous one
    let (status, body) = admin
        .post("/api/v1/default-model", json!({"model_id": other_model}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    assert_eq!(defaults().await, [other_model]);

    // Setting it again changes nothing
    let (status, body) = admin
        .post("/api/v1/default-model", json!({"model_id": other_model}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    assert_eq!(defaults().await, [other_model]);

    let (status, body) = admin
        .post("/api/v1/default-model", json!({"model_id": null}))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    let (status, body) = admin
        .post(
            "/api/v1/default-model",
            json!({"model_id": "00000000-0000-7000-8000-000000000000"}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "UNKNOWN_MODEL");
    assert_eq!(defaults().await, [other_model]);
}

#[sqlx::test]
async fn model_prices_need_a_currency(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let llm = MockLlm::start(vec![]).await;
    let configured = app.configure_llm(&llm).await;
    let provider_route = format!("/api/v1/llm-providers/{}/update", configured.provider_id);
    let model_route = format!("/api/v1/models/{}/update", configured.model_id);
    let provider = |currency: Value| {
        json!({
            "name": "Mock",
            "api_format": "ANTHROPIC",
            "base_url": llm.base_url,
            "api_key": {"action": "KEEP"},
            "currency": currency,
        })
    };
    let priced = json!({"api_name": "mock-model", "input_price": "3", "output_price": "15"});

    // Without prices, the currency can be cleared
    let (status, body) = admin.post(&provider_route, provider(json!(" "))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["currency"], json!(null));

    let (status, body) = admin.post(&model_route, priced.clone()).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    let (status, body) = admin
        .post(
            &format!("/api/v1/llm-providers/{}/models", configured.provider_id),
            json!({"api_name": "other-model", "input_price": "3", "output_price": "15"}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");

    // With prices, it cannot
    let (status, body) = admin.post(&provider_route, provider(json!("usd"))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["currency"], "USD");
    let (status, body) = admin.post(&model_route, priced).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = admin.post(&provider_route, provider(json!(null))).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
}

#[sqlx::test]
async fn lists_the_models_of_the_provider(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let llm = MockLlm::start(vec![]).await;
    let configured = app.configure_llm(&llm).await;
    let route = format!(
        "/api/v1/llm-providers/{}/remote-models",
        configured.provider_id
    );

    // All pages, sorted by id
    let (status, body) = admin.get(&route).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let expected: Vec<Value> = MODELS
        .iter()
        .map(|(api_name, display_name)| json!({"api_name": api_name, "display_name": display_name}))
        .collect();
    assert_eq!(body, json!(expected));

    let alice = app.user("alice@example.com").await;
    let (status, body) = alice.get(&route).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");

    // A server that does not list its models
    let (status, body) = admin
        .post(
            &format!("/api/v1/llm-providers/{}/update", configured.provider_id),
            json!({
                "name": "Mock",
                "api_format": "OPENAI",
                "base_url": llm.base_url,
                "api_key": {"action": "KEEP"},
                "currency": null,
            }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = admin.get(&route).await;
    assert_eq!(status, StatusCode::BAD_GATEWAY, "{body}");
    assert_eq!(body["code"], "REMOTE_UNREACHABLE");

    let (status, body) = admin
        .get("/api/v1/llm-providers/00000000-0000-0000-0000-000000000000/remote-models")
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
}

#[sqlx::test]
async fn shows_presented_files(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        tool_use_response(
            "toolu_1",
            "present_file_to_user",
            json!({"repository": "demo", "path": "docs/guide.md"}),
        ),
        tool_use_response(
            "toolu_2",
            "present_file_to_user",
            json!({"repository": "demo", "path": "docs/report.pdf"}),
        ),
        tool_use_response(
            "toolu_3",
            "present_file_to_user",
            json!({"repository": "demo", "path": "docs/photo.png"}),
        ),
        text_response("Here are the guide, the report and the photo."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let pdf = "%PDF-1.4\n%%EOF\n";
    let photo = png(3, 2);
    let repo = app
        .seed_repository(
            alice.user_id,
            "demo",
            &[
                ("docs/guide.md", "# Guide\n".as_bytes()),
                ("docs/report.pdf", pdf.as_bytes()),
                ("docs/photo.png", &photo),
            ],
        )
        .await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "Show me the guide, the report and the photo",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let chat_id = chat["id"].as_str().unwrap();
    let answer = alice.wait_for_answer(chat_id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    // Presented before the answer, as the system prompt asks
    assert_eq!(
        answer["content"],
        "Here are the guide, the report and the photo."
    );
    let tool_calls = answer["tool_calls"].as_array().unwrap();
    assert_eq!(tool_calls.len(), 3);
    let file_url = |tool_call: &Value| {
        assert_eq!(tool_call["name"], "present_file_to_user");
        assert_eq!(tool_call["status"], "COMPLETED", "{tool_call}");
        format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}/file",
            tool_call["id"].as_str().unwrap()
        )
    };

    let guide_url = file_url(&tool_calls[0]);
    let (status, content_type, body) = alice.get_raw(&guide_url).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        content_type.as_deref(),
        Some("text/markdown; charset=utf-8")
    );
    assert_eq!(body, b"# Guide\n");

    // The original PDF, even though it was never converted
    let (status, content_type, body) = alice.get_raw(&file_url(&tool_calls[1])).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content_type.as_deref(), Some("application/pdf"));
    assert_eq!(body, pdf.as_bytes());

    // The image as it is
    let (status, content_type, body) = alice.get_raw(&file_url(&tool_calls[2])).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content_type.as_deref(), Some("image/png"));
    assert_eq!(body, photo);

    // Only the user of the chat sees it
    let bob = app.user("bob@example.com").await;
    let (status, _) = bob.get(&guide_url).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn keeps_the_answer_written_with_presented_files(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        text_and_tool_use_response(
            "Let me read the guide.",
            "toolu_1",
            "read_file",
            json!({"repository": "demo", "path": "docs/guide.md"}),
        ),
        text_and_tool_use_response(
            "The guide has one heading.",
            "toolu_2",
            "present_file_to_user",
            json!({"repository": "demo", "path": "docs/guide.md"}),
        ),
        text_response("It is attached."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(alice.user_id, "demo", &[("docs/guide.md", "# Guide\n")])
        .await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "Summarize the guide",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;

    // The preamble of the lookup is dropped, the answer written with the file is kept
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(
        answer["content"],
        "The guide has one heading.\n\nIt is attached."
    );
}

#[sqlx::test]
async fn proposes_changes_where_commits_are_allowed(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let change = json!({
        "repository": "demo",
        "path": "docs/guide.md",
        "message": "Rename the guide",
        "edits": [{"old_string": "# Guide", "new_string": "# Handbook"}],
    });
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "change_file", change.clone()),
        text_response("I can't change it."),
        tool_use_response("toolu_2", "change_file", change),
        text_response("I renamed the heading."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(alice.user_id, "demo", &[("docs/guide.md", "# Guide\n")])
        .await;
    let ask = async || {
        let (status, chat) = alice
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Rename the guide to handbook",
                    "all_repositories": false,
                    "repository_ids": [repo.id],
                }),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let chat_id = chat["id"].as_str().unwrap().to_string();
        let answer = alice.wait_for_answer(&chat_id).await;
        assert_eq!(answer["status"], "COMPLETED", "{answer}");
        let tool_call = answer["tool_calls"][0].clone();
        assert_eq!(tool_call["name"], "change_file");
        let patch_url = format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}/patch",
            tool_call["id"].as_str().unwrap()
        );
        (tool_call, patch_url)
    };
    let tool_names = |request: &Value| -> Vec<String> {
        request["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|tool| tool["name"].as_str().unwrap().to_string())
            .collect()
    };

    // Off by default, so the model gets no such tool.
    let (tool_call, patch_url) = ask().await;
    assert_eq!(tool_call["status"], "FAILED", "{tool_call}");
    assert!(!tool_names(&llm.requests()[0]).contains(&"change_file".to_string()));
    let (status, _) = alice.get(&patch_url).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let diff_url = patch_url.replace("/patch", "/diff");
    let (status, _) = alice.get(&diff_url).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    app.allow_commits(&repo).await;

    let (tool_call, patch_url) = ask().await;
    assert_eq!(tool_call["status"], "COMPLETED", "{tool_call}");
    assert!(tool_names(&llm.requests()[2]).contains(&"change_file".to_string()));
    let (status, content_type, body) = alice.get_raw(&patch_url).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content_type.as_deref(), Some("text/x-patch; charset=utf-8"));
    let patch = String::from_utf8(body).unwrap();
    assert!(
        patch.contains("From: Repolupe+mock-model <noreply@repolupe.com>\n"),
        "{patch}"
    );
    assert!(
        patch.contains("Subject: [PATCH] Rename the guide\n"),
        "{patch}"
    );
    assert!(
        patch.contains(
            "--- a/docs/guide.md\n+++ b/docs/guide.md\n@@ -1 +1 @@\n-# Guide\n+# Handbook\n"
        ),
        "{patch}"
    );
    // The same diff, as the clients show it; the heading is mostly rewritten, so no words are
    // marked
    let diff_url = patch_url.replace("/patch", "/diff");
    let (status, diff) = alice.get(&diff_url).await;
    assert_eq!(status, StatusCode::OK, "{diff}");
    assert_eq!(
        diff,
        json!({
            "kind": "MODIFIED",
            "hunks": [{
                "skipped": false,
                "lines": [
                    {"kind": "REMOVED", "parts": [{"text": "# Guide", "changed": false}]},
                    {"kind": "ADDED", "parts": [{"text": "# Handbook", "changed": false}]},
                ],
            }],
            "moves": null,
        })
    );

    // Only the user of the chat sees it
    let bob = app.user("bob@example.com").await;
    let (status, _) = bob.get(&patch_url).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = bob.get(&diff_url).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn runs_scripts_with_and_without_repositories(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let sum = "$files['prices.csv'].trim().split('\\n').slice(1)\
        .map((line) => Number(line.split(',')[1])).reduce((a, b) => a + b, 0).toFixed(2)";
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "run_script", json!({"code": "6 * 7"})),
        text_response("It is 42."),
        tool_use_response(
            "toolu_2",
            "run_script",
            json!({"code": sum, "files": ["prices.csv"]}),
        ),
        text_response("They cost 2.05."),
    ])
    .await;
    app.configure_llm(&llm).await;

    // Without repositories, the script is the only tool.
    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "What is 6 times 7?", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["content"], "It is 42.");
    let tool_call = &answer["tool_calls"][0];
    assert_eq!(tool_call["name"], "run_script");
    assert_eq!(tool_call["status"], "COMPLETED");
    assert_eq!(tool_call["repository_id"], json!(null));
    let requests = llm.requests();
    let tools = requests[0]["tools"].as_array().unwrap();
    assert_eq!(tools.len(), 1, "{tools:?}");
    assert_eq!(tools[0]["name"], "run_script");
    assert_eq!(tool_result(&requests[1])["content"], "Result: 42");

    // With one, it reads its files from the pinned commit.
    let repo = app
        .seed_repository(
            alice.user_id,
            "shop",
            &[("prices.csv", "item,price\napple,1.20\npear,0.85\n")],
        )
        .await;
    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "What do all items cost together?",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let answer = alice.wait_for_answer(chat["id"].as_str().unwrap()).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let tool_call = &answer["tool_calls"][0];
    assert_eq!(tool_call["repository_id"], json!(repo.id));
    assert_eq!(tool_call["commit_sha"], repo.commit_sha);
    let result = tool_result(&llm.requests()[3]);
    assert_eq!(result["is_error"], false, "{result}");
    assert_eq!(result["content"], "Result: 2.05");
}

#[sqlx::test]
async fn stores_what_the_model_got_and_returned(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let input = json!({"repository": "demo", "path": "src/main.rs"});
    let llm = MockLlm::start(vec![
        text_and_tool_use_response(
            "Let me look at main.",
            "toolu_1",
            "read_file",
            input.clone(),
        ),
        text_response("It prints hello."),
        text_response("Nothing else."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(
            alice.user_id,
            "demo",
            &[("src/main.rs", "fn main() {\n    println!(\"hello\");\n}\n")],
        )
        .await;

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "What does main print?",
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let id = chat["id"].as_str().unwrap();
    let question_id = chat["messages"][0]["id"].as_str().unwrap();
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let raw_path = |message_id: &str| format!("/api/v1/chats/{id}/messages/{message_id}/raw");
    let (status, raw) = alice.get(&raw_path(answer["id"].as_str().unwrap())).await;
    assert_eq!(status, StatusCode::OK, "{raw}");

    assert!(
        raw["system"].as_str().unwrap().contains("- `demo`\n"),
        "{raw}"
    );
    let names = |tools: &Value| -> Vec<String> {
        let tools = tools.as_array().unwrap();
        tools.iter().map(|t| t["name"].to_string()).collect()
    };
    assert_eq!(names(&raw["tools"]), names(&llm.requests()[0]["tools"]));
    assert!(raw["tools"][0]["input_schema"].is_object(), "{raw}");

    // The preamble dropped from the answer, the call and its result, then the answer
    let messages = raw["messages"].as_array().unwrap();
    let roles: Vec<&str> = messages
        .iter()
        .map(|m| m["role"].as_str().unwrap())
        .collect();
    assert_eq!(roles, ["USER", "ASSISTANT", "USER", "ASSISTANT"], "{raw}");
    let question = messages[0]["content"][0]["text"].as_str().unwrap();
    assert!(question.ends_with("]\nWhat does main print?"), "{question}");
    assert_eq!(
        messages[1]["content"],
        json!([
            {"type": "TEXT", "text": "Let me look at main."},
            {"type": "TOOL_USE", "id": "toolu_1", "name": "read_file", "input": input},
        ])
    );
    let result = &messages[2]["content"][0];
    assert_eq!(result["type"], "TOOL_RESULT", "{result}");
    assert_eq!(result["tool_use_id"], "toolu_1");
    assert_eq!(result["is_error"], false);
    assert!(
        result["content"]
            .as_str()
            .unwrap()
            .contains(r#"println!("hello");"#),
        "{result}"
    );
    assert_eq!(
        messages[3]["content"],
        json!([{"type": "TEXT", "text": "It prints hello."}])
    );

    // The next answer gets the earlier one without its tool calls
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{id}/messages"),
            json!({"content": "Anything else?"}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let answer = alice.wait_for_answer(id).await;
    let (status, raw) = alice.get(&raw_path(answer["id"].as_str().unwrap())).await;
    assert_eq!(status, StatusCode::OK, "{raw}");
    let messages = raw["messages"].as_array().unwrap();
    let texts: Vec<&str> = messages
        .iter()
        .map(|m| m["content"][0]["text"].as_str().unwrap())
        .collect();
    assert_eq!(texts.len(), 4, "{raw}");
    assert!(texts[0].ends_with("\nWhat does main print?"), "{raw}");
    assert_eq!(texts[1], "It prints hello.");
    assert!(texts[2].ends_with("\nAnything else?"), "{raw}");
    assert_eq!(texts[3], "Nothing else.");

    // Not for questions, nor for other users
    let (status, body) = alice.get(&raw_path(question_id)).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    let (status, body) = bob.get(&raw_path(answer["id"].as_str().unwrap())).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
}

#[sqlx::test]
async fn raw_answer_ends_with_the_response_that_was_cut_off(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let (failing, gate) = gated(error_response("overloaded_error", "It is"));
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "unknown_tool", json!({})),
        failing,
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
    let raw_path = format!(
        "/api/v1/chats/{id}/messages/{}/raw",
        chat["messages"][1]["id"].as_str().unwrap()
    );
    // Stored once the answer is finished
    let (status, body) = alice.get(&raw_path).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    gate.notify_one();
    let answer = alice.wait_for_answer(id).await;
    assert_eq!(answer["status"], "FAILED", "{answer}");

    let (status, raw) = alice.get(&raw_path).await;
    assert_eq!(status, StatusCode::OK, "{raw}");
    let messages = raw["messages"].as_array().unwrap();
    let blocks: Vec<(&str, &str)> = messages
        .iter()
        .map(|m| {
            let role = m["role"].as_str().unwrap();
            (role, m["content"][0]["type"].as_str().unwrap())
        })
        .collect();
    assert_eq!(
        blocks,
        [
            ("USER", "TEXT"),
            ("ASSISTANT", "TOOL_USE"),
            ("USER", "TOOL_RESULT"),
            ("ASSISTANT", "TEXT"),
        ],
        "{raw}"
    );
    assert_eq!(messages[2]["content"][0]["is_error"], true, "{raw}");
    assert_eq!(messages[3]["content"][0]["text"], "It is", "{raw}");
}
