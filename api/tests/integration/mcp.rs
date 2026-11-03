use super::mock_llm::{MockLlm, text_response, tool_result, tool_use_response};
use super::mock_mcp::{FORBIDDEN, HOLD, INSUFFICIENT_SCOPE, LOSE_RESULT, McpAuth, MockMcp, TOKEN};
use super::support::{TestApp, TestClient};
use axum::http::StatusCode;
use serde_json::{Value, json};
use sqlx::SqlitePool;
use url::Url;

const REDIRECT_URI: &str = "https://repolupe.example.com/settings/mcp-servers/callback";

async fn create(client: &TestClient, name: &str, url: &str, token: Option<&str>) -> Value {
    let (status, server) = client
        .post(
            "/api/v1/mcp-servers",
            json!({"name": name, "url": url, "token": token}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{server}");
    server
}

fn tool_names(server: &Value) -> Vec<&str> {
    server["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|tool| tool["name"].as_str().unwrap())
        .collect()
}

/// Asks in a new chat without repositories and returns the answer.
async fn ask(client: &TestClient, question: &str) -> Value {
    let (status, chat) = client
        .post(
            "/api/v1/chats",
            json!({"content": question, "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    client.wait_for_answer(chat["id"].as_str().unwrap()).await
}

/// Signs in to the server `id` with OAuth and returns it.
async fn sign_in(client: &TestClient, mcp: &MockMcp, id: &str) -> Value {
    let (status, body) = client
        .post(
            &format!("/api/v1/mcp-servers/{id}/authorize"),
            json!({"redirect_uri": REDIRECT_URI}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let authorization_url = body["authorization_url"].as_str().unwrap();
    let state = Url::parse(authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(key, _)| key == "state")
        .unwrap()
        .1
        .into_owned();
    let code = mcp.approve(authorization_url);
    let (status, server) = client
        .post(
            "/api/v1/mcp-servers/authorize/callback",
            json!({"state": state, "code": code, "iss": null}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    server
}

/// The names of the tools the model got in `request`.
fn offered(request: &Value) -> Vec<String> {
    request["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|tool| tool["name"].as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test]
async fn adds_servers_and_lists_their_tools(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::None).await;

    let server = create(&admin, "Echo Server", &mcp.url, None).await;
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(server["auth"], "NONE");
    assert_eq!(server["enabled"], true);
    assert_eq!(server["disabled_tools"], json!([]));
    assert_eq!(server["url"], mcp.url);
    assert_eq!(tool_names(&server), ["echo"]);
    assert_eq!(server["tools"][0]["description"], "Echoes the text.");

    let (status, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1);

    let (status, error) = admin
        .post(
            "/api/v1/mcp-servers",
            json!({"name": "echo server", "url": mcp.url}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{error}");
    assert_eq!(error["code"], "NAME_TAKEN");

    // Not an MCP server: the mock LLM's port answers 404.
    let llm = MockLlm::start(vec![]).await;
    let (status, error) = admin
        .post(
            "/api/v1/mcp-servers",
            json!({"name": "LLM", "url": format!("{}/mcp", llm.base_url)}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_GATEWAY, "{error}");
    assert_eq!(error["code"], "REMOTE_UNREACHABLE");

    // Others neither see nor change it.
    let alice = app.user("alice@example.com").await;
    let (_, list) = alice.get("/api/v1/mcp-servers").await;
    assert_eq!(list, json!([]));
    let id = server["id"].as_str().unwrap();
    for action in ["refresh", "delete"] {
        let (status, _) = alice
            .post(&format!("/api/v1/mcp-servers/{id}/{action}"), json!({}))
            .await;
        let expected = if action == "delete" {
            StatusCode::NO_CONTENT
        } else {
            StatusCode::NOT_FOUND
        };
        assert_eq!(status, expected, "{action}");
    }
    let (_, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(list.as_array().unwrap().len(), 1);

    let (status, _) = admin
        .post(&format!("/api/v1/mcp-servers/{id}/delete"), json!({}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(list, json!([]));
}

#[sqlx::test]
async fn keeps_users_off_internal_addresses(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let mcp = MockMcp::start(McpAuth::None).await;

    let (status, error) = alice
        .post(
            "/api/v1/mcp-servers",
            json!({"name": "Echo", "url": mcp.url}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{error}");
    assert_eq!(error["message"], "URL must use https://");

    let url = mcp.url.replace("http://", "https://");
    let (status, error) = alice
        .post("/api/v1/mcp-servers", json!({"name": "Echo", "url": url}))
        .await;
    assert_eq!(status, StatusCode::BAD_GATEWAY, "{error}");
    assert_eq!(error["message"], "The server's address is not public");

    // A name is only found out when resolving it.
    let url = url.replace("127.0.0.1", "localhost");
    let (status, error) = alice
        .post("/api/v1/mcp-servers", json!({"name": "Echo", "url": url}))
        .await;
    assert_eq!(status, StatusCode::BAD_GATEWAY, "{error}");
    assert_eq!(error["message"], "The server's address is not public");
}

#[sqlx::test]
async fn takes_rejections_without_a_challenge_as_such(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::TokenWithoutChallenge).await;

    // 401 without a token.
    let server = create(&admin, "Tokens", &mcp.url, None).await;
    assert_eq!(server["status"], "AUTHORIZATION_REQUIRED", "{server}");

    // 403 with a wrong one.
    let (status, error) = admin
        .post(
            "/api/v1/mcp-servers",
            json!({"name": "Wrong", "url": mcp.url, "token": "wrong-token-12345"}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{error}");
    assert_eq!(error["code"], "AUTH_FAILED");

    let server = create(&admin, "Right", &mcp.url, Some(TOKEN)).await;
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(tool_names(&server), ["echo"]);
}

#[sqlx::test]
async fn authenticates_with_a_token(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::Token).await;

    // Without one, it is saved to sign in to later.
    let server = create(&admin, "Tokens", &mcp.url, None).await;
    assert_eq!(server["status"], "AUTHORIZATION_REQUIRED", "{server}");
    assert_eq!(tool_names(&server), Vec::<&str>::new());
    let id = server["id"].as_str().unwrap();

    // It does not support OAuth.
    let (status, error) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/authorize"),
            json!({"redirect_uri": REDIRECT_URI}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{error}");
    assert_eq!(error["code"], "AUTH_FAILED");

    let (status, error) = admin
        .post(
            "/api/v1/mcp-servers",
            json!({"name": "Wrong", "url": mcp.url, "token": "wrong-token-12345"}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{error}");
    assert_eq!(error["code"], "AUTH_FAILED");

    let server = create(&admin, "Right", &mcp.url, Some(TOKEN)).await;
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(server["auth"], "TOKEN");
    assert_eq!(server["token_hint"], &TOKEN[TOKEN.len() - 4..]);
    assert_eq!(tool_names(&server), ["echo"]);

    let id = server["id"].as_str().unwrap();
    let (status, server) = admin
        .post(&format!("/api/v1/mcp-servers/{id}/refresh"), json!({}))
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    assert_eq!(server["status"], "READY", "{server}");
}

#[sqlx::test]
async fn changes_only_the_name_enabled_and_disabled_tools(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::Token).await;
    let other = MockMcp::start(McpAuth::None).await;
    let server = create(&admin, "Tokens", &mcp.url, Some(TOKEN)).await;
    let id = server["id"].as_str().unwrap();
    create(&admin, "Taken", &other.url, None).await;

    // A server that is down can still be renamed, it is not connected to.
    drop(mcp);
    let (_, failed) = admin
        .post(&format!("/api/v1/mcp-servers/{id}/refresh"), json!({}))
        .await;
    assert_eq!(failed["status"], "FAILED", "{failed}");
    let (status, renamed) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/update"),
            json!({
                "name": "Renamed",
                "enabled": false,
                "disabled_tools": ["echo", "gone", "echo"],
                "url": other.url,
                "token": null,
            }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{renamed}");
    assert_eq!(renamed["name"], "Renamed");
    assert_eq!(renamed["enabled"], false);
    // Sorted and without duplicates, also names the server doesn't list.
    assert_eq!(renamed["disabled_tools"], json!(["echo", "gone"]));
    // The rest stays, other fields are ignored.
    for field in ["url", "auth", "token_hint", "status", "checked_at", "tools"] {
        assert_eq!(renamed[field], failed[field], "{field}");
    }

    let (status, error) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/update"),
            json!({"name": "taken", "enabled": true, "disabled_tools": []}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{error}");
    assert_eq!(error["code"], "NAME_TAKEN");

    let (status, error) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/update"),
            json!({"name": "Renamed", "enabled": true, "disabled_tools": [""]}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{error}");
    assert_eq!(error["code"], "VALIDATION_ERROR");
}

#[sqlx::test]
async fn answers_with_the_tools_of_enabled_servers(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::Token).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "mcp__echo_server__echo", json!({"text": "hi"})),
        text_response("It said hi."),
        text_response("No tools."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let server = create(&admin, "Echo Server", &mcp.url, Some(TOKEN)).await;

    let answer = ask(&admin, "What does echo say?").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["content"], "It said hi.");
    let tool_call = &answer["tool_calls"][0];
    assert_eq!(tool_call["name"], "mcp__echo_server__echo");
    assert_eq!(tool_call["status"], "COMPLETED");
    assert_eq!(tool_call["repository_id"], json!(null));
    assert_eq!(mcp.calls(), [json!({"text": "hi"})]);

    let requests = llm.requests();
    assert_eq!(
        offered(&requests[0]),
        ["run_script", "mcp__echo_server__echo"]
    );
    let echo = &requests[0]["tools"][1];
    assert_eq!(echo["input_schema"]["required"], json!(["text"]));
    let system = requests[0]["system"].to_string();
    assert!(
        system.contains("(MCP servers): \\\"Echo Server\\\""),
        "{system}"
    );
    let result = tool_result(&requests[1]);
    assert_eq!(result["content"], "echo: hi");
    assert_eq!(result["is_error"], false);

    // Disabled, the model doesn't get them.
    let id = server["id"].as_str().unwrap();
    let (status, server) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/update"),
            json!({"name": "Echo Server", "enabled": false, "disabled_tools": []}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    assert_eq!(server["enabled"], false);
    let answer = ask(&admin, "Anything?").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(offered(&llm.requests()[2]), ["run_script"]);
}

#[sqlx::test]
async fn leaves_out_the_tools_the_user_turned_off(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::None).await;
    let llm = MockLlm::start(vec![text_response("No echo."), text_response("Echo.")]).await;
    app.configure_llm(&llm).await;
    let server = create(&admin, "Echo Server", &mcp.url, None).await;
    let id = server["id"].as_str().unwrap();
    let client = &admin;
    let update = |disabled_tools: Value| {
        let route = format!("/api/v1/mcp-servers/{id}/update");
        let payload =
            json!({"name": "Echo Server", "enabled": true, "disabled_tools": disabled_tools});
        async move { client.post(&route, payload).await }
    };

    let (status, server) = update(json!(["echo", "gone"])).await;
    assert_eq!(status, StatusCode::OK, "{server}");
    // Connecting again lists the tool, and it stays off.
    let (_, server) = admin
        .post(&format!("/api/v1/mcp-servers/{id}/refresh"), json!({}))
        .await;
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(tool_names(&server), ["echo"]);
    assert_eq!(server["disabled_tools"], json!(["echo", "gone"]));

    // Without tools, the server isn't mentioned either.
    let answer = ask(&admin, "What does echo say?").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let request = &llm.requests()[0];
    assert_eq!(offered(request), ["run_script"]);
    let system = request["system"].to_string();
    assert!(!system.contains("MCP servers"), "{system}");

    let (status, _) = update(json!(["gone"])).await;
    assert_eq!(status, StatusCode::OK);
    let answer = ask(&admin, "And now?").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(
        offered(&llm.requests()[1]),
        ["run_script", "mcp__echo_server__echo"]
    );
}

#[sqlx::test]
async fn reports_failed_tool_calls(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::None).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "mcp__echo__echo", json!({})),
        text_response("It failed."),
    ])
    .await;
    app.configure_llm(&llm).await;
    create(&admin, "Echo", &mcp.url, None).await;

    let answer = ask(&admin, "Echo nothing").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    assert_eq!(answer["tool_calls"][0]["status"], "FAILED");
    let result = tool_result(&llm.requests()[1]);
    assert_eq!(result["content"], "text is missing");
    assert_eq!(result["is_error"], true);
}

#[sqlx::test]
async fn fails_only_the_calls_the_server_refuses(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::Token).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "mcp__echo__echo", json!({"text": FORBIDDEN})),
        tool_use_response(
            "toolu_2",
            "mcp__echo__echo",
            json!({"text": INSUFFICIENT_SCOPE}),
        ),
        tool_use_response("toolu_3", "mcp__echo__echo", json!({"text": "hi"})),
        text_response("Two were refused."),
        text_response("Still there."),
    ])
    .await;
    app.configure_llm(&llm).await;
    create(&admin, "Echo", &mcp.url, Some(TOKEN)).await;

    let answer = ask(&admin, "Echo three times").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let statuses: Vec<&str> = answer["tool_calls"]
        .as_array()
        .unwrap()
        .iter()
        .map(|call| call["status"].as_str().unwrap())
        .collect();
    assert_eq!(statuses, ["FAILED", "FAILED", "COMPLETED"], "{answer}");
    let requests = llm.requests();
    let refused = tool_result(&requests[1]);
    assert_eq!(refused["is_error"], true, "{refused}");
    assert_eq!(
        refused["content"],
        "The MCP server \"Echo\" refused the request (HTTP 403 Forbidden). The credentials may \
        lack a permission for it."
    );
    let refused = tool_result(&requests[2]);
    assert_eq!(refused["is_error"], true, "{refused}");
    assert!(
        refused["content"].as_str().unwrap().contains("OAuth scope"),
        "{refused}"
    );
    // The session is still usable.
    assert_eq!(tool_result(&requests[3])["content"], "echo: hi");
    assert_eq!(mcp.calls(), [json!({"text": "hi"})]);

    // The server stays as it was, with its tools.
    let (_, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(list[0]["status"], "READY", "{list}");
    assert_eq!(tool_names(&list[0]), ["echo"]);
    ask(&admin, "Anything?").await;
    assert_eq!(
        offered(&llm.requests()[4]),
        ["run_script", "mcp__echo__echo"]
    );
}

#[sqlx::test]
async fn tells_the_model_when_a_call_was_lost(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::Token).await;
    let echo =
        |id: &str, text: &str| tool_use_response(id, "mcp__echo__echo", json!({"text": text}));
    let llm = MockLlm::start(vec![
        echo("toolu_1", LOSE_RESULT),
        echo("toolu_2", "after the loss"),
        text_response("Done."),
    ])
    .await;
    app.configure_llm(&llm).await;
    create(&admin, "Echo", &mcp.url, Some(TOKEN)).await;

    let answer = ask(&admin, "Echo twice").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let statuses: Vec<&str> = answer["tool_calls"]
        .as_array()
        .unwrap()
        .iter()
        .map(|call| call["status"].as_str().unwrap())
        .collect();
    assert_eq!(statuses, ["FAILED", "COMPLETED"], "{answer}");
    let requests = llm.requests();
    let lost = tool_result(&requests[1]);
    assert_eq!(lost["is_error"], true, "{lost}");
    assert_eq!(
        lost["content"],
        "The connection to the MCP server \"Echo\" was lost during the call. The tool may or \
        may not have run, so check that before calling it again."
    );
    assert_eq!(tool_result(&requests[2])["content"], "echo: after the loss");
    // It may have run, so it was not sent again.
    let expected = [
        json!({"text": LOSE_RESULT}),
        json!({"text": "after the loss"}),
    ];
    assert_eq!(mcp.calls(), expected);
}

#[sqlx::test]
async fn signs_in_with_oauth(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::OAuth).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "mcp__oauth__echo", json!({"text": "signed in"})),
        text_response("Done."),
        tool_use_response("toolu_2", "mcp__oauth__echo", json!({"text": "revoked"})),
        text_response("It failed."),
        text_response("No tools."),
    ])
    .await;
    app.configure_llm(&llm).await;

    let server = create(&admin, "OAuth", &mcp.url, None).await;
    assert_eq!(server["status"], "AUTHORIZATION_REQUIRED", "{server}");
    let id = server["id"].as_str().unwrap();

    let (status, body) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/authorize"),
            json!({"redirect_uri": REDIRECT_URI}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let authorization_url = body["authorization_url"].as_str().unwrap();
    let parsed = Url::parse(authorization_url).unwrap();
    assert_eq!(parsed.path(), "/authorize");
    let param = |name: &str| {
        parsed
            .query_pairs()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.into_owned())
    };
    assert_eq!(param("redirect_uri").as_deref(), Some(REDIRECT_URI));
    assert_eq!(param("client_id").as_deref(), Some("client-1"));
    let registration = &mcp.registrations()[0];
    assert_eq!(registration["client_name"], "Repolupe");
    assert_eq!(registration["application_type"], "web");
    assert_eq!(registration["redirect_uris"], json!([REDIRECT_URI]));
    let state = param("state").unwrap();
    let code = mcp.approve(authorization_url);

    // The state is the user's only.
    let alice = app.user("alice@example.com").await;
    let callback = json!({"state": state, "code": code, "iss": null});
    let (status, _) = alice
        .post("/api/v1/mcp-servers/authorize/callback", callback.clone())
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, server) = admin
        .post("/api/v1/mcp-servers/authorize/callback", callback.clone())
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(server["auth"], "OAUTH");
    assert_eq!(tool_names(&server), ["echo"]);
    // The access tokens expire right away, so listing the tools refreshed it.
    assert!(mcp.refreshes() >= 1);

    // Used once.
    let (status, _) = admin
        .post("/api/v1/mcp-servers/authorize/callback", callback)
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let refreshes = mcp.refreshes();
    let answer = ask(&admin, "Echo something").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let result = tool_result(&llm.requests()[1]);
    assert_eq!(result["content"], "echo: signed in", "{result}");
    assert!(mcp.refreshes() > refreshes);

    // Revoked, the server needs a new sign-in, and its tools are withdrawn until then.
    mcp.revoke();
    let answer = ask(&admin, "Echo again").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let result = tool_result(&llm.requests()[3]);
    assert_eq!(result["is_error"], true, "{result}");
    assert!(
        result["content"]
            .as_str()
            .unwrap()
            .contains("has to sign in to it again"),
        "{result}"
    );
    let (_, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(list[0]["status"], "AUTHORIZATION_REQUIRED", "{list}");
    assert_eq!(list[0]["auth"], "OAUTH");
    ask(&admin, "Anything?").await;
    assert_eq!(offered(&llm.requests()[4]), ["run_script"]);
}

#[sqlx::test]
async fn keeps_the_server_when_replaced_credentials_are_rejected(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::TokenOrOAuth).await;
    let echo =
        |id: &str, text: &str| tool_use_response(id, "mcp__echo__echo", json!({"text": text}));
    let llm = MockLlm::start(vec![
        echo("toolu_1", HOLD),
        echo("toolu_2", "with the old token"),
        text_response("The second one failed."),
        text_response("Still there."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let server = create(&admin, "Echo", &mcp.url, Some(TOKEN)).await;
    assert_eq!(server["status"], "READY", "{server}");
    let id = server["id"].as_str().unwrap();

    // While an answer uses the token, the user revokes it and signs in with OAuth instead.
    let (status, chat) = admin
        .post(
            "/api/v1/chats",
            json!({"content": "Echo twice", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    mcp.wait_for_held().await;
    mcp.reject_token();
    let server = sign_in(&admin, &mcp, id).await;
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(server["auth"], "OAUTH");

    // The answer's next call is rejected with the old token. It fails, but the server stays.
    mcp.release();
    let answer = admin.wait_for_answer(chat["id"].as_str().unwrap()).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let statuses: Vec<&str> = answer["tool_calls"]
        .as_array()
        .unwrap()
        .iter()
        .map(|call| call["status"].as_str().unwrap())
        .collect();
    assert_eq!(statuses, ["COMPLETED", "FAILED"], "{answer}");
    let result = tool_result(&llm.requests()[2]);
    assert_eq!(result["is_error"], true, "{result}");
    assert!(
        result["content"]
            .as_str()
            .unwrap()
            .contains("rejected the credentials"),
        "{result}"
    );
    assert_eq!(mcp.calls(), [json!({"text": HOLD})]);

    let (_, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(list[0]["status"], "READY", "{list}");
    assert_eq!(tool_names(&list[0]), ["echo"]);
    ask(&admin, "Anything?").await;
    assert_eq!(
        offered(&llm.requests()[3]),
        ["run_script", "mcp__echo__echo"]
    );
}

#[sqlx::test]
async fn refreshes_tokens_with_the_client_secret(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::ConfidentialOAuth).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "mcp__oauth__echo", json!({"text": "refreshed"})),
        text_response("Done."),
    ])
    .await;
    app.configure_llm(&llm).await;

    let server = create(&admin, "OAuth", &mcp.url, None).await;
    let id = server["id"].as_str().unwrap();
    let (status, body) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/authorize"),
            json!({"redirect_uri": REDIRECT_URI}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let authorization_url = body["authorization_url"].as_str().unwrap();
    let state = Url::parse(authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(key, _)| key == "state")
        .unwrap()
        .1
        .into_owned();
    // Asked for a public client, the server registered a confidential one.
    assert_eq!(mcp.registrations()[0]["token_endpoint_auth_method"], "none");
    let code = mcp.approve(authorization_url);

    // The access tokens expire right away, so listing the tools and calling one refresh them,
    // which the server allows only with the secret it registered the client with.
    let (status, server) = admin
        .post(
            "/api/v1/mcp-servers/authorize/callback",
            json!({"state": state, "code": code, "iss": null}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    assert_eq!(server["status"], "READY", "{server}");
    let refreshes = mcp.refreshes();
    assert!(refreshes >= 1);

    let answer = ask(&admin, "Echo something").await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let result = tool_result(&llm.requests()[1]);
    assert_eq!(result["content"], "echo: refreshed", "{result}");
    assert!(mcp.refreshes() > refreshes);
}

#[sqlx::test]
async fn requires_a_sign_in_when_the_client_is_rejected(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::OAuth).await;
    let server = create(&admin, "OAuth", &mcp.url, None).await;
    let id = server["id"].as_str().unwrap();
    let server = sign_in(&admin, &mcp, id).await;
    assert_eq!(server["status"], "READY", "{server}");

    // The access tokens expire right away, so connecting refreshes them, which the
    // authorization server rejects with `invalid_client`.
    mcp.forget_clients();
    let (status, server) = admin
        .post(&format!("/api/v1/mcp-servers/{id}/refresh"), json!({}))
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    assert_eq!(server["status"], "AUTHORIZATION_REQUIRED", "{server}");

    // Signing in again registers another client.
    let server = sign_in(&admin, &mcp, id).await;
    assert_eq!(server["status"], "READY", "{server}");
    assert_eq!(mcp.registrations().len(), 2);
}

#[sqlx::test]
async fn refreshes_tokens_one_connection_at_a_time(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let mcp = MockMcp::start(McpAuth::OAuth).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "mcp__oauth__echo", json!({"text": "together"})),
        tool_use_response("toolu_2", "mcp__oauth__echo", json!({"text": "together"})),
        text_response("Done."),
        text_response("Done."),
    ])
    .await;
    app.configure_llm(&llm).await;

    let server = create(&admin, "OAuth", &mcp.url, None).await;
    let id = server["id"].as_str().unwrap();
    let (status, body) = admin
        .post(
            &format!("/api/v1/mcp-servers/{id}/authorize"),
            json!({"redirect_uri": REDIRECT_URI}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let authorization_url = body["authorization_url"].as_str().unwrap();
    let state = Url::parse(authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(key, _)| key == "state")
        .unwrap()
        .1
        .into_owned();
    let code = mcp.approve(authorization_url);
    let (status, server) = admin
        .post(
            "/api/v1/mcp-servers/authorize/callback",
            json!({"state": state, "code": code, "iss": null}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{server}");
    assert_eq!(server["status"], "READY", "{server}");

    // After a restart, two answers connect at the same time, each with an OAuth client of its
    // own, and both have to refresh the expired tokens. The server rotates the refresh token,
    // so a second refresh with the same one would be rejected.
    let restarted = app.start_background_tasks().await;
    let admin = admin.on(&restarted);
    mcp.slow_down();
    let (first, second) = tokio::join!(ask(&admin, "Echo"), ask(&admin, "Echo too"));
    for answer in [first, second] {
        assert_eq!(answer["status"], "COMPLETED", "{answer}");
    }
    for request in &llm.requests()[2..] {
        let result = tool_result(request);
        assert_eq!(result["content"], "echo: together", "{result}");
    }
    assert_eq!(mcp.rejected_refreshes(), 0);
    let (_, list) = admin.get("/api/v1/mcp-servers").await;
    assert_eq!(list[0]["status"], "READY", "{list}");
}
