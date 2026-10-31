use super::mock_llm::{MockLlm, text_response, tool_result, tool_use_response};
use super::support::TestApp;
use axum::body::Body;
use axum::http::{Method, StatusCode, header};
use serde_json::{Value, json};
use sqlx::SqlitePool;
use std::time::Duration;

const TEXT_PDF: &[u8] = include_bytes!("../fixtures/text.pdf");

/// The text of the first message in `request`, the user's.
/// Without the time each message starts with.
fn first_message(request: &Value) -> String {
    request["messages"][0]["content"]
        .as_array()
        .unwrap()
        .iter()
        .map(|block| block["text"].as_str().unwrap().split_once('\n').unwrap().1)
        .collect::<Vec<_>>()
        .join("\n")
}

fn tool_names(request: &Value) -> Vec<&str> {
    request["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|tool| tool["name"].as_str().unwrap())
        .collect()
}

#[sqlx::test]
async fn proposes_to_store_attachments(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let save = |path: &str, replace: bool| {
        json!({
            "repository": "demo",
            "attachment": 1,
            "path": path,
            "message": "Add the notes",
            "replace": replace,
        })
    };
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "save_attachment", save("notes/guide.md", false)),
        tool_use_response(
            "toolu_2",
            "save_attachment",
            save("notes/meeting.md", false),
        ),
        text_response("I propose to store it in `notes/meeting.md`."),
        // The second message with attachment 2
        tool_use_response("toolu_3", "save_attachment", save("notes/guide.md", true)),
        text_response("Replaced."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(alice.user_id, "demo", &[("notes/guide.md", "# Guide\n")])
        .await;
    app.allow_commits(&repo).await;

    let (status, attachment) = alice.upload("meeting.md", b"# Meeting\n").await;
    assert_eq!(status, StatusCode::CREATED, "{attachment}");
    assert_eq!(attachment["file_name"], "meeting.md");
    assert_eq!(attachment["content_type"], "text/plain");
    assert_eq!(attachment["size"], 10);
    assert_eq!(attachment["number"], Value::Null);
    let attachment_id = attachment["id"].as_str().unwrap().to_string();

    // Only the attachment, without text
    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": " ",
                "attachment_id": attachment_id,
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    assert_eq!(chat["title"], "meeting.md");
    assert_eq!(chat["messages"][0]["attachment"]["number"], 1);
    let chat_id = chat["id"].as_str().unwrap().to_string();
    let answer = alice.wait_for_answer(&chat_id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");

    let requests = llm.requests();
    assert_eq!(
        first_message(&requests[0]),
        "[The user attached a file: attachment 1, `meeting.md` (text/plain, 10 B). Read it with \
         read_attachment.]"
    );
    assert!(tool_names(&requests[0]).contains(&"save_attachment"));
    assert!(
        requests[0]["system"]
            .to_string()
            .contains("save_attachment"),
        "{}",
        requests[0]["system"]
    );
    // The path exists, so the model tries another one
    let result = tool_result(&requests[1]);
    assert_eq!(result["is_error"], true, "{result}");
    assert!(
        result["content"]
            .as_str()
            .unwrap()
            .contains("`notes/guide.md` already exists"),
        "{result}"
    );
    let result = tool_result(&requests[2]);
    assert_eq!(result["is_error"], false, "{result}");

    let tool_call = &answer["tool_calls"][1];
    assert_eq!(tool_call["name"], "save_attachment");
    assert_eq!(tool_call["status"], "COMPLETED", "{answer}");
    let tool_call_url = format!(
        "/api/v1/chats/{chat_id}/tool-calls/{}",
        tool_call["id"].as_str().unwrap()
    );
    let (status, change) = alice.get(&format!("{tool_call_url}/proposed-commit")).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "PROPOSED");
    assert_eq!(change["path"], "notes/meeting.md");
    let (status, _, patch) = alice.get_raw(&format!("{tool_call_url}/patch")).await;
    assert_eq!(status, StatusCode::OK);
    let patch = String::from_utf8(patch).unwrap();
    assert!(
        patch.contains("new file mode 100644\n") && patch.contains("+# Meeting\n"),
        "{patch}"
    );
    let (status, diff) = alice.get(&format!("{tool_call_url}/diff")).await;
    assert_eq!(status, StatusCode::OK, "{diff}");
    assert_eq!(diff["kind"], "ADDED");
    assert_eq!(
        diff["hunks"][0]["lines"][0],
        json!({"kind": "ADDED", "parts": [{"text": "# Meeting", "changed": false}]})
    );

    // Sent once only
    let (status, body) = alice
        .post(
            &format!("/api/v1/chats/{chat_id}/messages"),
            json!({"content": "Again", "attachment_id": attachment_id}),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "UNKNOWN_ATTACHMENT");

    // The next one gets the next number, and the model sees both
    let (_, second) = alice.upload("guide.md", b"# Guide v2\n").await;
    let (status, messages) = alice
        .post(
            &format!("/api/v1/chats/{chat_id}/messages"),
            json!({"content": "Replace the guide", "attachment_id": second["id"]}),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{messages}");
    assert_eq!(messages[0]["attachment"]["number"], 2);
    let answer = alice.wait_for_answer(&chat_id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let requests = llm.requests();
    let last_question =
        requests[3]["messages"].as_array().unwrap().last().unwrap()["content"].to_string();
    assert!(
        last_question.contains("Replace the guide\\n\\n[The user attached a file: attachment 2"),
        "{last_question}"
    );
    // Attachment 1 again, with `replace`
    assert_eq!(tool_result(&requests[4])["is_error"], false);

    let (status, chat) = alice.get(&format!("/api/v1/chats/{chat_id}")).await;
    assert_eq!(status, StatusCode::OK);
    let attachments: Vec<&Value> = chat["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|message| &message["attachment"])
        .collect();
    assert_eq!(attachments[0]["file_name"], "meeting.md");
    assert_eq!(attachments[1], &Value::Null);
    assert_eq!(attachments[2]["file_name"], "guide.md");

    // Downloaded with its name, only by its owner
    let download_url = format!("/api/v1/attachments/{attachment_id}");
    let request = alice
        .request(Method::GET, &download_url)
        .body(Body::empty())
        .unwrap();
    let response = alice.response(request).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response.headers()[header::CONTENT_DISPOSITION],
        "attachment; filename=\"meeting.md\"; filename*=UTF-8''meeting.md"
    );
    let (status, content_type, content) = alice.get_raw(&download_url).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content_type.as_deref(), Some("text/plain"));
    assert_eq!(content, b"# Meeting\n");
    let bob = app.user("bob@example.com").await;
    let (status, _) = bob.get(&download_url).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn reads_attachments(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "read_attachment", json!({"attachment": 1})),
        text_response("The limit is 42."),
        tool_use_response(
            "toolu_2",
            "read_attachment",
            json!({"attachment": 2, "offset": 2}),
        ),
        text_response("Noted."),
        tool_use_response("toolu_3", "read_attachment", json!({"attachment": 3})),
        text_response("It is an image."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let tasks = app.start_background_tasks().await;
    // The instance that converts the documents, which the answer waits for
    let alice = app.user("alice@example.com").await.on(&tasks);

    let send = async |chat_id: Option<&str>, file_name: &str, content: &[u8]| {
        let (status, attachment) = alice.upload(file_name, content).await;
        assert_eq!(status, StatusCode::CREATED, "{attachment}");
        let (status, body) = match chat_id {
            // Without repositories, the user has none
            None => {
                alice
                    .post(
                        "/api/v1/chats",
                        json!({
                            "content": "Read it",
                            "attachment_id": attachment["id"],
                            "all_repositories": true,
                        }),
                    )
                    .await
            }
            Some(chat_id) => {
                alice
                    .post(
                        &format!("/api/v1/chats/{chat_id}/messages"),
                        json!({"content": "Read it", "attachment_id": attachment["id"]}),
                    )
                    .await
            }
        };
        assert_eq!(status, StatusCode::CREATED, "{body}");
        let chat_id = chat_id.map_or_else(|| body["id"].as_str().unwrap().to_string(), Into::into);
        let answer = alice.wait_for_answer(&chat_id).await;
        assert_eq!(answer["status"], "COMPLETED", "{answer}");
        chat_id
    };

    // Probably still converting when the model reads it
    let chat_id = send(None, "manual.pdf", TEXT_PDF).await;
    send(Some(&chat_id), "notes.md", b"# Notes\n\nSecond line\n").await;
    send(Some(&chat_id), "logo.png", b"\x89PNG\r\n\x1a\n\0logo").await;

    let requests = llm.requests();
    assert_eq!(tool_names(&requests[0]), ["read_attachment", "run_script"]);
    let manual = tool_result(&requests[1]);
    assert_eq!(manual["is_error"], false, "{manual}");
    let markdown = manual["content"].as_str().unwrap();
    assert!(markdown.contains("42 requests"), "{markdown}");
    let notes = tool_result(&requests[3]);
    assert_eq!(notes["is_error"], false, "{notes}");
    assert_eq!(notes["content"], "2\t\n3\tSecond line");
    let logo = tool_result(&requests[5]);
    assert_eq!(logo["is_error"], true, "{logo}");
    assert_eq!(
        logo["content"],
        "`logo.png` is a binary file and can't be shown."
    );
}

#[sqlx::test]
async fn passes_attachments_to_scripts(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let sum = "attachments[1].trim().split('\\n').slice(1)\
        .map((line) => Number(line.split(',')[1])).reduce((a, b) => a + b, 0).toFixed(2)";
    let llm = MockLlm::start(vec![
        tool_use_response(
            "toolu_1",
            "run_script",
            json!({"code": sum, "attachments": [1]}),
        ),
        text_response("The total is 2.05."),
        tool_use_response(
            "toolu_2",
            "run_script",
            json!({"code": "attachments[2].includes('42 requests')", "attachments": [2]}),
        ),
        text_response("It mentions the limit."),
        tool_use_response(
            "toolu_3",
            "run_script",
            json!({"code": "1", "attachments": [3]}),
        ),
        tool_use_response(
            "toolu_4",
            "run_script",
            json!({"code": "1", "attachments": [9]}),
        ),
        text_response("It is an image."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let tasks = app.start_background_tasks().await;
    let alice = app.user("alice@example.com").await.on(&tasks);

    let send = async |chat_id: Option<&str>, file_name: &str, content: &[u8]| {
        let (status, attachment) = alice.upload(file_name, content).await;
        assert_eq!(status, StatusCode::CREATED, "{attachment}");
        let (status, body) = match chat_id {
            // Without repositories, the user has none
            None => {
                alice
                    .post(
                        "/api/v1/chats",
                        json!({
                            "content": "Calculate",
                            "attachment_id": attachment["id"],
                            "all_repositories": true,
                        }),
                    )
                    .await
            }
            Some(chat_id) => {
                alice
                    .post(
                        &format!("/api/v1/chats/{chat_id}/messages"),
                        json!({"content": "Calculate", "attachment_id": attachment["id"]}),
                    )
                    .await
            }
        };
        assert_eq!(status, StatusCode::CREATED, "{body}");
        let chat_id = chat_id.map_or_else(|| body["id"].as_str().unwrap().to_string(), Into::into);
        let answer = alice.wait_for_answer(&chat_id).await;
        assert_eq!(answer["status"], "COMPLETED", "{answer}");
        chat_id
    };

    let chat_id = send(None, "prices.csv", b"item,price\napple,1.20\npear,0.85\n").await;
    // Probably still converting when the script is called, which waits for it
    send(Some(&chat_id), "manual.pdf", TEXT_PDF).await;
    send(Some(&chat_id), "logo.png", b"\x89PNG\r\n\x1a\n\0logo").await;

    let requests = llm.requests();
    let run_script = requests[0]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .find(|tool| tool["name"] == "run_script")
        .unwrap();
    assert_eq!(
        run_script["input_schema"]["properties"]["attachments"]["items"]["enum"],
        json!([1])
    );
    let sum = tool_result(&requests[1]);
    assert_eq!(sum["is_error"], false, "{sum}");
    assert_eq!(sum["content"], "Result: 2.05");
    let manual = tool_result(&requests[3]);
    assert_eq!(manual["is_error"], false, "{manual}");
    assert_eq!(manual["content"], "Result: true");
    let logo = tool_result(&requests[5]);
    assert_eq!(logo["is_error"], true, "{logo}");
    assert_eq!(
        logo["content"],
        "`logo.png` is a binary file and can't be shown."
    );
    let missing = tool_result(&requests[6]);
    assert_eq!(missing["is_error"], true, "{missing}");
    assert_eq!(
        missing["content"],
        "There is no attachment 9. Attachments: 1 (`prices.csv`), 2 (`manual.pdf`), \
        3 (`logo.png`)."
    );
}

#[sqlx::test]
async fn serves_proposed_documents(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        tool_use_response(
            "toolu_1",
            "save_attachment",
            json!({
                "repository": "demo",
                "attachment": 1,
                "path": "docs/scan.pdf",
                "message": "Add the scan",
            }),
        ),
        text_response("Stored."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(alice.user_id, "demo", &[("README.md", "# Demo\n")])
        .await;
    app.allow_commits(&repo).await;
    let pdf = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<<>>\nendobj\n";
    let (_, attachment) = alice.upload("scan.pdf", pdf).await;
    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "Store the scan",
                "attachment_id": attachment["id"],
                "all_repositories": false,
                "repository_ids": [repo.id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let chat_id = chat["id"].as_str().unwrap().to_string();
    let answer = alice.wait_for_answer(&chat_id).await;
    assert_eq!(answer["tool_calls"][0]["status"], "COMPLETED", "{answer}");
    let tool_call_url = format!(
        "/api/v1/chats/{chat_id}/tool-calls/{}",
        answer["tool_calls"][0]["id"].as_str().unwrap()
    );

    // The patch has no diff of it, the file is served as it is
    let (_, _, patch) = alice.get_raw(&format!("{tool_call_url}/patch")).await;
    let patch = String::from_utf8(patch).unwrap();
    assert!(
        patch.contains("Binary files /dev/null and b/docs/scan.pdf differ\n"),
        "{patch}"
    );
    let (_, diff) = alice.get(&format!("{tool_call_url}/diff")).await;
    assert_eq!(diff, json!({"kind": "ADDED", "hunks": [], "moves": null}));
    let (status, content_type, content) = alice
        .get_raw(&format!("{tool_call_url}/proposed-commit/file"))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content_type.as_deref(), Some("application/pdf"));
    assert_eq!(content, pdf);

    // Only for the user's own chats
    let bob = app.user("bob@example.com").await;
    let (status, _) = bob
        .get(&format!("{tool_call_url}/proposed-commit/file"))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn validates_uploads(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    // Never asked, the messages are rejected before
    let llm = MockLlm::start(vec![]).await;
    app.configure_llm(&llm).await;

    // Forms can be sent cross-site without a preflight
    let request = alice
        .request(Method::POST, "/api/v1/attachments?file_name=a.txt")
        .header(header::CONTENT_TYPE, "multipart/form-data; boundary=x")
        .body(Body::from("a"))
        .unwrap();
    let (status, body) = alice.send(request).await;
    assert_eq!(status, StatusCode::UNSUPPORTED_MEDIA_TYPE, "{body}");

    let (status, body) = alice.upload("%20", b"a").await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");

    let (status, attachment) = alice.upload("a.txt", b"a").await;
    assert_eq!(status, StatusCode::CREATED, "{attachment}");
    let (status, body) = bob
        .post(
            "/api/v1/chats",
            json!({
                "content": "Mine?",
                "attachment_id": attachment["id"],
                "all_repositories": true,
            }),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "UNKNOWN_ATTACHMENT");

    // Text is required without an attachment
    let (status, body) = alice
        .post(
            "/api/v1/chats",
            json!({"content": " ", "all_repositories": true}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
}

#[sqlx::test]
async fn removes_unsent_attachments(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let (_, unsent) = alice.upload("old.txt", b"old").await;
    let (_, recent) = alice.upload("new.txt", b"new").await;
    let unsent_id = unsent["id"].as_str().unwrap();
    app.age_attachment(unsent_id).await;

    let _tasks = app.start_background_tasks().await;
    let removed = async {
        while app.attachments_dir().join(unsent_id).exists() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    };
    tokio::time::timeout(Duration::from_secs(10), removed)
        .await
        .expect("the unsent attachment was not removed");

    let (status, _) = alice.get(&format!("/api/v1/attachments/{unsent_id}")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, content) = alice
        .get_raw(&format!(
            "/api/v1/attachments/{}",
            recent["id"].as_str().unwrap()
        ))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content, b"new");
}
