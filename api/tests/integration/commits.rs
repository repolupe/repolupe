use super::local_remote::{LocalRemote, wait_for_commit};
use super::mock_llm::{MockLlm, text_response, tool_result, tool_use_response};
use super::support::TestApp;
use super::support::{TestClient, git};
use axum::http::StatusCode;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::SqlitePool;

fn repository_request(remote: &LocalRemote, allow_commits: bool) -> Value {
    json!({
        "name": "internal",
        "remote": {
            "url": remote.url,
            "branch": "main",
            "poll_interval_seconds": 3600,
        },
        "allow_commits": allow_commits,
    })
}

#[sqlx::test]
async fn allowing_commits_needs_push_access(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let remote = LocalRemote::start().await;

    let (status, body) = admin
        .post("/api/v1/repositories", repository_request(&remote, true))
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "AUTH_FAILED", "{body}");

    let (status, body) = admin
        .post("/api/v1/repositories", repository_request(&remote, false))
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let update_url = format!(
        "/api/v1/repositories/{}/update",
        body["id"].as_str().unwrap()
    );
    let mut update = repository_request(&remote, true);
    update["remote"]["token"] = json!({"action": "KEEP"});
    let (status, body) = admin.post(&update_url, update.clone()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "AUTH_FAILED", "{body}");

    remote.allow_push(true);
    let (status, body) = admin.post(&update_url, update.clone()).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["allow_commits"], true);

    // Checked only when turned on.
    remote.allow_push(false);
    update["name"] = json!("renamed");
    let (status, body) = admin.post(&update_url, update).await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

#[sqlx::test]
async fn commits_proposed_changes(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    remote.allow_push(true);
    let readme = |heading: &str| {
        json!({
            "repository": "internal",
            "path": "README.md",
            "message": "Rename the heading",
            "edits": [{"old_string": "# Internal", "new_string": heading}],
        })
    };
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "change_file", readme("# Handbook")),
        text_response("Renamed."),
        tool_use_response("toolu_2", "change_file", readme("# Guide")),
        text_response("Renamed."),
        tool_use_response(
            "toolu_3",
            "change_file",
            json!({
                "repository": "internal",
                "path": "docs/new.md",
                "message": "Add docs",
                "content": "New\n",
            }),
        ),
        text_response("Added."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let (status, body) = app
        .admin()
        .post("/api/v1/repositories", repository_request(&remote, true))
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    // Everything on the instance that syncs, which also pushes, so they take turns.
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    wait_for_commit(&admin, &id, &remote.head()).await;

    let ask = async |client: &TestClient| {
        let (status, chat) = client
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Change it",
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
    // All based on the synced commit.
    let handbook = ask(&admin).await;
    let guide = ask(&admin).await;
    let docs = ask(&admin).await;

    let (status, change) = admin.get(&format!("{handbook}/proposed-commit")).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "PROPOSED");
    assert_eq!(change["path"], "README.md");
    assert_eq!(change["can_commit"], true);

    // The branch moved, but the file did not.
    let moved = remote.push_commit(&[("other.txt", "other")]);
    let (status, change) = admin.post(&format!("{handbook}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    assert_eq!(change["pushed_branch"], "main");
    assert_eq!(change["error"], Value::Null);
    let pushed = remote.head();
    assert_eq!(change["pushed_commit"], pushed);
    assert_ne!(change["proposed_commit"], pushed);
    assert_eq!(remote.read("README.md"), "# Handbook");
    assert_eq!(remote.read("other.txt"), "other");
    assert_eq!(
        git(&remote.repository, &["log", "-1", "--format=%P %s", "main"]).trim(),
        format!("{moved} Rename the heading")
    );
    // Written by the model, committed by the user, who has no email.
    assert_eq!(
        git(
            &remote.repository,
            &["log", "-1", "--format=%an <%ae>%n%cn <%ce>", "main"]
        ),
        "Repolupe+mock-model <noreply@repolupe.com>\nadmin <noreply@repolupe.com>\n"
    );

    // Committed once.
    let (status, again) = admin.post(&format!("{handbook}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{again}");
    assert_eq!(again["pushed_commit"], pushed);
    assert_eq!(remote.head(), pushed);

    // The other proposal for the file was based on the old version.
    let (status, change) = admin.post(&format!("{guide}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "CONFLICT", "{change}");
    assert!(
        change["error"]
            .as_str()
            .unwrap()
            .contains("`README.md` was changed on main"),
        "{change}"
    );
    assert_eq!(remote.head(), pushed);

    remote.allow_push(false);
    let (status, change) = admin.post(&format!("{docs}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "FAILED", "{change}");
    assert!(
        change["error"].as_str().unwrap().contains("write access"),
        "{change}"
    );
    assert_eq!(remote.head(), pushed);

    // Failures can be retried.
    remote.allow_push(true);
    let (status, change) = admin.post(&format!("{docs}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    assert_eq!(change["error"], Value::Null);
    assert_eq!(remote.read("docs/new.md"), "New\n");
    assert_eq!(remote.read("README.md"), "# Handbook");
    // The sync picks it up.
    wait_for_commit(&admin, &id, &remote.head()).await;

    // Only the user of the chat.
    let bob = app.user("bob@example.com").await;
    let (status, _) = bob.post(&format!("{docs}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = bob.get(&format!("{docs}/proposed-commit")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn commits_proposed_changes_automatically(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    remote.allow_push(true);
    let readme = |heading: &str| {
        json!({
            "repository": "internal",
            "path": "README.md",
            "message": "Rename the heading",
            "edits": [{"old_string": "# Internal", "new_string": heading}],
        })
    };
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "change_file", readme("# Handbook")),
        // Replaces the first one.
        tool_use_response("toolu_2", "change_file", readme("# Guide")),
        tool_use_response(
            "toolu_3",
            "change_file",
            json!({
                "repository": "internal",
                "path": "docs/new.md",
                "message": "Add docs",
                "content": "New\n",
            }),
        ),
        text_response("Changed."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let (status, body) = app
        .admin()
        .post("/api/v1/repositories", repository_request(&remote, true))
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    wait_for_commit(&admin, &id, &remote.head()).await;

    let (_, me) = admin.get("/api/v1/me").await;
    assert_eq!(me["auto_commit"], false);
    let (status, body) = admin
        .post("/api/v1/me/auto-commit", json!({"auto_commit": true}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (_, me) = admin.get("/api/v1/me").await;
    assert_eq!(me["auto_commit"], true);

    let (status, chat) = admin
        .post(
            "/api/v1/chats",
            json!({
                "content": "Change it",
                "all_repositories": false,
                "repository_ids": [id],
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let chat_id = chat["id"].as_str().unwrap();
    let answer = admin.wait_for_answer(chat_id).await;
    assert_eq!(answer["status"], "COMPLETED", "{answer}");
    let change = async |index: usize| {
        let tool_call = &answer["tool_calls"][index];
        let url = format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}/proposed-commit",
            tool_call["id"].as_str().unwrap()
        );
        let (status, change) = admin.get(&url).await;
        assert_eq!(status, StatusCode::OK, "{change}");
        change
    };
    assert_eq!(change(0).await["status"], "PROPOSED");
    assert_eq!(change(1).await["status"], "COMMITTED");
    let docs = change(2).await;
    assert_eq!(docs["status"], "COMMITTED");
    // One after the other, the second on top of the first.
    assert_eq!(docs["pushed_commit"], remote.head());
    assert_eq!(remote.read("README.md"), "# Guide");
    assert_eq!(remote.read("docs/new.md"), "New\n");
}

#[sqlx::test]
async fn shared_users_commit_if_the_owner_lets_them(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    remote.allow_push(true);
    let change = json!({
        "repository": "internal",
        "path": "README.md",
        "message": "Rename the heading",
        "edits": [{"old_string": "# Internal", "new_string": "# Handbook"}],
    });
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "change_file", change.clone()),
        text_response("I can't change it."),
        tool_use_response("toolu_2", "change_file", change),
        text_response("Renamed."),
    ])
    .await;
    app.configure_llm(&llm).await;
    // On localhost, which only the admin who owns it may push to, whoever commits.
    let (status, body) = app
        .admin()
        .post("/api/v1/repositories", repository_request(&remote, true))
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let users = format!("/api/v1/repositories/{id}/users");
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    let bob = app.user("bob@example.com").await.on(&tasks);
    let (status, body) = admin
        .post(&users, json!({"user_name_or_email": "bob"}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (_, body) = admin.get(&users).await;
    assert_eq!(body[0]["can_commit"], false);
    wait_for_commit(&bob, &id, &remote.head()).await;

    let ask = async || {
        let (status, chat) = bob
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Change it",
                    "all_repositories": false,
                    "repository_ids": [id],
                }),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let chat_id = chat["id"].as_str().unwrap();
        let answer = bob.wait_for_answer(chat_id).await;
        let tool_call = answer["tool_calls"][0].clone();
        let url = format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}",
            tool_call["id"].as_str().unwrap()
        );
        (tool_call, url)
    };
    let offers_change_file = |request: &Value| {
        request["tools"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tool| tool["name"] == "change_file")
    };

    // Shared to read only.
    let (tool_call, _) = ask().await;
    assert_eq!(tool_call["status"], "FAILED", "{tool_call}");
    assert!(!offers_change_file(&llm.requests()[0]));
    let (_, repository) = bob.get(&format!("/api/v1/repositories/{id}")).await;
    assert_eq!(repository["can_commit"], false, "{repository}");

    // Only the owner and admins let others commit.
    let bob_url = format!("{users}/{}/update", bob.user_id);
    let (status, body) = bob.post(&bob_url, json!({"can_commit": true})).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (status, _) = admin
        .post(
            &format!("{users}/{}/update", admin.user_id),
            json!({"can_commit": true}),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, body) = admin.post(&bob_url, json!({"can_commit": true})).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (_, body) = admin.get(&users).await;
    assert_eq!(body[0]["can_commit"], true);
    let (_, repository) = bob.get(&format!("/api/v1/repositories/{id}")).await;
    assert_eq!(repository["can_commit"], true, "{repository}");

    let (tool_call, url) = ask().await;
    assert_eq!(tool_call["status"], "COMPLETED", "{tool_call}");
    assert!(offers_change_file(&llm.requests()[2]));
    let (status, change) = bob.get(&format!("{url}/proposed-commit")).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["can_commit"], true);

    // Not anymore.
    let (status, _) = admin.post(&bob_url, json!({"can_commit": false})).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, change) = bob.get(&format!("{url}/proposed-commit")).await;
    assert_eq!(change["can_commit"], false);
    let (status, body) = bob.post(&format!("{url}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");

    admin.post(&bob_url, json!({"can_commit": true})).await;
    let (status, change) = bob.post(&format!("{url}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    assert_eq!(remote.read("README.md"), "# Handbook");
    // Committed by the user who asked, with the owner's token.
    assert_eq!(
        git(
            &remote.repository,
            &["log", "-1", "--format=%an <%ae>%n%cn <%ce>", "main"]
        ),
        "Repolupe+mock-model <noreply@repolupe.com>\nbob <bob@example.com>\n"
    );
    // The sync picks it up.
    wait_for_commit(&bob, &id, &remote.head()).await;
}

#[sqlx::test]
async fn commits_proposed_moves(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start().await;
    remote.push_commit(&[("guides/setup.md", "Setup"), ("guides/usage.md", "Usage")]);
    remote.allow_push(true);
    let moves =
        |moves: Value| json!({"repository": "internal", "moves": moves, "message": "Reorganize"});
    let llm = MockLlm::start(vec![
        tool_use_response(
            "toolu_1",
            "move_files",
            moves(json!([
                {"from": "guides", "to": "docs/guides"},
                {"from": "README.md", "to": "docs/README.md"},
            ])),
        ),
        text_response("Moved."),
        tool_use_response(
            "toolu_2",
            "move_files",
            moves(json!([{"from": "guides/setup.md", "to": "setup.md"}])),
        ),
        text_response("Moved."),
    ])
    .await;
    app.configure_llm(&llm).await;
    let (status, body) = app
        .admin()
        .post("/api/v1/repositories", repository_request(&remote, true))
        .await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    wait_for_commit(&admin, &id, &remote.head()).await;

    let ask = async || {
        let (status, chat) = admin
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Move it",
                    "all_repositories": false,
                    "repository_ids": [id],
                }),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let chat_id = chat["id"].as_str().unwrap();
        let answer = admin.wait_for_answer(chat_id).await;
        let tool_call = &answer["tool_calls"][0];
        assert_eq!(tool_call["status"], "COMPLETED", "{answer}");
        format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}",
            tool_call["id"].as_str().unwrap()
        )
    };
    let reorganize = ask().await;
    let setup = ask().await;

    let (status, change) = admin.get(&format!("{reorganize}/proposed-commit")).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "PROPOSED");
    assert_eq!(change["path"], Value::Null);
    assert_eq!(
        change["moves"],
        json!([
            {"from": "guides", "to": "docs/guides"},
            {"from": "README.md", "to": "docs/README.md"},
        ])
    );
    let (status, _, patch) = admin.get_raw(&format!("{reorganize}/patch")).await;
    assert_eq!(status, StatusCode::OK);
    let patch = String::from_utf8(patch).unwrap();
    assert!(
        patch.contains(
            "diff --git a/guides/setup.md b/docs/guides/setup.md\n\
            similarity index 100%\n\
            rename from guides/setup.md\n\
            rename to docs/guides/setup.md\n"
        ),
        "{patch}"
    );
    // A folder with the number of its files
    let (status, diff) = admin.get(&format!("{reorganize}/diff")).await;
    assert_eq!(status, StatusCode::OK, "{diff}");
    assert_eq!(
        diff,
        json!({
            "kind": "MODIFIED",
            "hunks": [],
            "moves": [
                {"from": "guides", "to": "docs/guides", "folder_files": 2},
                {"from": "README.md", "to": "docs/README.md", "folder_files": null},
            ],
        })
    );
    // There is no single file to show.
    let (status, _) = admin
        .get(&format!("{reorganize}/proposed-commit/file"))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // The branch moved, but not the files.
    let moved = remote.push_commit(&[("other.txt", "other")]);
    let (status, change) = admin.post(&format!("{reorganize}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    assert_eq!(change["pushed_commit"], remote.head());
    assert_eq!(
        git(&remote.repository, &["log", "-1", "--format=%P %s", "main"]).trim(),
        format!("{moved} Reorganize")
    );
    assert_eq!(
        git(
            &remote.repository,
            &["ls-tree", "-r", "--name-only", "main"]
        ),
        "docs/README.md\ndocs/guides/setup.md\ndocs/guides/usage.md\nother.txt\n"
    );

    // The other proposal moves a file that is gone now.
    let (status, change) = admin.post(&format!("{setup}/commit"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "CONFLICT", "{change}");
    assert!(
        change["error"]
            .as_str()
            .unwrap()
            .contains("Ask for the moves again"),
        "{change}"
    );
}

#[sqlx::test]
async fn commits_attachments_to_git_lfs(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let remote = LocalRemote::start_with_token(Some("secret")).await;
    remote.push_commit(&[(
        ".gitattributes",
        "*.png filter=lfs diff=lfs merge=lfs -text\n",
    )]);
    let save = json!({
        "repository": "internal",
        "attachment": 1,
        "path": "images/logo.png",
        "message": "Add the logo",
        "replace": true,
    });
    let llm = MockLlm::start(vec![
        tool_use_response("toolu_1", "save_attachment", save.clone()),
        text_response("Proposed."),
        tool_use_response("toolu_2", "save_attachment", save),
        text_response("It is there already."),
    ])
    .await;
    app.configure_llm(&llm).await;
    remote.allow_push(true);
    let mut request = repository_request(&remote, true);
    request["remote"]["token"] = json!("secret");
    let (status, body) = app.admin().post("/api/v1/repositories", request).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    let id = body["id"].as_str().unwrap().to_string();
    let tasks = app.start_background_tasks().await;
    let admin = app.admin().on(&tasks);
    wait_for_commit(&admin, &id, &remote.head()).await;

    let logo = b"\x89PNG\r\n\x1a\n\0logo";
    let store_logo = async || {
        let (status, attachment) = admin.upload("logo.png", logo).await;
        assert_eq!(status, StatusCode::CREATED, "{attachment}");
        let (status, chat) = admin
            .post(
                "/api/v1/chats",
                json!({
                    "content": "Store the logo",
                    "attachment_id": attachment["id"],
                    "all_repositories": false,
                    "repository_ids": [id],
                }),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{chat}");
        let chat_id = chat["id"].as_str().unwrap();
        let answer = admin.wait_for_answer(chat_id).await;
        assert_eq!(answer["status"], "COMPLETED", "{answer}");
        format!(
            "/api/v1/chats/{chat_id}/tool-calls/{}",
            answer["tool_calls"][0]["id"].as_str().unwrap()
        )
    };
    let tool_call_url = store_logo().await;

    // The upload is refused without push access, before anything is pushed.
    let head = remote.head();
    remote.allow_push(false);
    let (status, change) = admin
        .post(&format!("{tool_call_url}/commit"), json!({}))
        .await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "FAILED", "{change}");
    assert!(
        change["error"].as_str().unwrap().contains("Git LFS"),
        "{change}"
    );
    assert_eq!(remote.head(), head);

    remote.allow_push(true);
    let (status, change) = admin
        .post(&format!("{tool_call_url}/commit"), json!({}))
        .await;
    assert_eq!(status, StatusCode::OK, "{change}");
    assert_eq!(change["status"], "COMMITTED", "{change}");
    // The branch has the pointer, the LFS server the content.
    let oid = hex::encode(Sha256::digest(logo));
    assert_eq!(
        git(
            &remote.repository,
            &["cat-file", "blob", "main:images/logo.png"]
        ),
        format!(
            "version https://git-lfs.github.com/spec/v1\noid sha256:{oid}\nsize {}\n",
            logo.len()
        )
    );
    assert_eq!(remote.lfs_object(&oid).as_deref(), Some(&logo[..]));
    wait_for_commit(&admin, &id, &remote.head()).await;

    // The pointer is recognized as the attachment.
    store_logo().await;
    let requests = llm.requests();
    let result = tool_result(&requests[3]);
    assert_eq!(result["is_error"], true, "{result}");
    assert!(
        result["content"]
            .as_str()
            .unwrap()
            .contains("already has the content of attachment 1"),
        "{result}"
    );
}
