use super::mock_llm::{MockLlm, text_response};
use super::support::{self, TestApp};
use axum::body::Body;
use axum::http::{Method, StatusCode, header};
use chrono::{DateTime, FixedOffset, Utc};
use repolupe::{DEFAULT_INITIAL_ADMIN_PASSWORD, INITIAL_ADMIN_USER_NAME, Repolupe};
use serde_json::json;
use sqlx::SqlitePool;
use tempfile::TempDir;

#[sqlx::test]
async fn user_logs_in_by_user_name_or_email(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();

    let (_, me) = admin.get("/api/v1/me").await;
    assert_eq!(me["user_name"], "admin");
    assert_eq!(me["email"], json!(null));

    // The email is optional, and both are unique ignoring case
    let (status, body) = admin
        .post(
            "/api/v1/register",
            json!({"user_name": "Alice", "email": "", "password": "password123"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["user_name"], "Alice");
    assert_eq!(body["email"], json!(null));
    let bob = app.user("bob@example.com").await;
    for (user_name, email, code) in [
        ("ALICE", None, "USER_NAME_TAKEN"),
        ("carol", Some("BOB@example.com"), "EMAIL_TAKEN"),
        ("carol@example.com", None, "VALIDATION_ERROR"),
        ("carol doe", None, "VALIDATION_ERROR"),
        ("carol", Some("carol"), "VALIDATION_ERROR"),
    ] {
        let (_, body) = admin
            .post(
                "/api/v1/register",
                json!({"user_name": user_name, "email": email, "password": "password123"}),
            )
            .await;
        assert_eq!(body["code"], code, "{user_name}");
    }

    for login in ["bob", "BOB", "bob@example.com", " Bob@Example.com "] {
        let client = app.login(login).await;
        assert_eq!(client.user_id, bob.user_id, "{login}");
    }
    let (status, _) = app.try_login("nobody").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // Wrong passwords by user name and by email count against the same limit
    for i in 0..10 {
        let login = if i % 2 == 0 { "bob" } else { "bob@example.com" };
        let (status, _) = admin
            .post(
                "/api/v1/login",
                json!({"user_name_or_email": login, "password": "wrong-password"}),
            )
            .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }
    let (status, body) = app.try_login("bob").await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS, "{body}");
}

#[sqlx::test]
async fn user_sets_and_clears_locale(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;

    let (_, body) = alice.get("/api/v1/me").await;
    assert_eq!(body["locale"], json!(null));

    let (status, _) = alice
        .post("/api/v1/me/locale", json!({"locale": "de-DE"}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, body) = alice.get("/api/v1/me").await;
    assert_eq!(body["locale"], "de-DE");

    let (status, body) = alice
        .post("/api/v1/me/locale", json!({"locale": "en_US"}))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "VALIDATION_ERROR");

    let (status, _) = alice
        .post("/api/v1/me/locale", json!({"locale": null}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, body) = alice.get("/api/v1/me").await;
    assert_eq!(body["locale"], json!(null));
}

#[sqlx::test]
async fn profile_tells_the_llm_who_is_asking(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![text_response("It is 123.")]).await;
    app.configure_llm(&llm).await;
    let repo = app
        .seed_repository(alice.user_id, "family", &[("README.md", "# Family")])
        .await;

    let (status, _) = alice
        .post(
            "/api/v1/me/profile",
            json!({"full_name": "  Alice Doe ", "first_name": " Alice ", "about": "Married to Bob Doe."}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["full_name"], "Alice Doe");
    assert_eq!(me["first_name"], "Alice");
    assert_eq!(me["about"], "Married to Bob Doe.");
    let (status, _) = alice
        .post("/api/v1/me/locale", json!({"locale": "de-DE"}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, chat) = alice
        .post(
            "/api/v1/chats",
            json!({
                "content": "What is my tax id?",
                "all_repositories": true,
                "utc_offset_minutes": 60,
            }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    alice.wait_for_answer(chat["id"].as_str().unwrap()).await;
    let sent_at: DateTime<Utc> = chat["messages"][0]["created_at"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    let sent_at = sent_at.with_timezone(&FixedOffset::east_opt(3600).unwrap());
    assert_eq!(
        llm.requests()[0]["messages"][0]["content"][0]["text"],
        format!(
            "{}\nWhat is my tax id?",
            sent_at.format("[%A, %Y-%m-%d %H:%M]")
        )
    );
    let (status, body) = alice
        .post(
            "/api/v1/chats",
            json!({"content": "Hi", "all_repositories": true, "utc_offset_minutes": 900}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "VALIDATION_ERROR");
    let commit = &repo.commit_sha[..12];
    assert_eq!(
        llm.requests()[0]["system"][0]["text"].as_str().unwrap(),
        format!(
            "\
You answer questions about the user's Git repositories.

The user asking is Alice Doe.
What the user says about themselves:
<about_user>
Married to Bob Doe.
</about_user>
\"I\", \"me\" and \"my\" in the questions refer to this user. The repositories may contain information about several people: answer with the information about this user, and if it is unclear whom something belongs to, say so instead of guessing.

The user's messages start with the date and time they were sent, in the user's local time (UTC+01:00). The last one is the current date and time.

Repositories you can read:
- `family` (branch `main`, commit {commit})

How to answer:
- Look things up with the tools instead of answering from memory. Search for the terms of the question with grep, which also searches the text converted from PDFs, or get an overview with list_files. For long Markdown files, use outline and read only the relevant sections with read_file. Read PDFs with read_file.
- Base your answer on what you read. If the repositories do not cover the question, say so instead of guessing.
- Name the files your answer is based on, e.g. `docs/setup.md`, with the repository if there are several.
- When the user wants to see a file, or a file is what they are looking for, show it with present_file_to_user instead of copying its content into the answer.
- For calculations, e.g. totals, percentages or date differences, run a script with run_script instead of working them out in your head, and pass it the files with the data.
- The user may not be technical and does not see your tool calls. Describe what you looked at in plain words, e.g. \"I searched all files\", without naming the tools or terms like grep, regular expression, Markdown or OCR.
- Answer in the language of the question, or in the language of the locale `de-DE` if that is unclear, and format it with Markdown.
"
        )
    );

    // Empty strings clear the fields, invalid ones are rejected
    let (status, body) = alice
        .post("/api/v1/me/profile", json!({"full_name": "Alice\nDoe"}))
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "VALIDATION_ERROR");
    let (status, _) = alice
        .post(
            "/api/v1/me/profile",
            json!({"full_name": "", "about": null}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["full_name"], json!(null));
    assert_eq!(me["first_name"], json!(null));
    assert_eq!(me["about"], json!(null));
}

#[sqlx::test]
async fn admin_disables_login(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;
    let path = format!("/api/v1/users/{}/update", alice.user_id);

    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["can_login"], true);
    assert_eq!(me["can_manage_repositories"], true);

    let (status, body) = alice
        .post(
            &path,
            json!({"user_name": "alice", "email": "alice@example.com", "can_login": true, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");

    let (status, body) = admin
        .post(
            &path,
            json!({"user_name": "alice", "email": "alice@example.com", "can_login": false, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["can_login"], false);

    // Signed out everywhere, and the correct password no longer logs in
    let (status, _) = alice.get("/api/v1/me").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, body) = app.try_login("alice@example.com").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "FORBIDDEN");

    // Enabling it again does not revive the old sessions
    let (status, _) = admin
        .post(
            &path,
            json!({"user_name": "alice", "email": "alice@example.com", "can_login": true, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = alice.get("/api/v1/me").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let alice = app.login("alice@example.com").await;
    let (status, _) = alice.get("/api/v1/me").await;
    assert_eq!(status, StatusCode::OK);

    // Admins cannot be restricted, unknown users are missing
    let (status, body) = admin
        .post(
            &format!("/api/v1/users/{}/update", admin.user_id),
            json!({"user_name": "admin", "email": null, "can_login": false, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (status, _) = admin
        .post(
            &format!("/api/v1/users/{}/update", uuid::Uuid::now_v7()),
            json!({"user_name": "nobody", "email": null, "can_login": true, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test]
async fn admin_changes_user_name_and_email(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;
    app.user("bob@example.com").await;
    let path = format!("/api/v1/users/{}/update", alice.user_id);
    let update = |user_name: &str, email: Option<&str>| json!({"user_name": user_name, "email": email, "can_login": true, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": false});

    let (status, body) = alice.post(&path, update("mallory", None)).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");

    let (status, body) = admin
        .post(&path, update(" alice2 ", Some(" alice@example.org ")))
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["user_name"], "alice2");
    assert_eq!(body["email"], "alice@example.org");

    // The session stays valid, and only the new names log in
    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["user_name"], "alice2");
    for login in ["alice2", "alice@example.org"] {
        assert_eq!(app.login(login).await.user_id, alice.user_id, "{login}");
    }
    for login in ["alice", "alice@example.com"] {
        let (status, _) = app.try_login(login).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{login}");
    }

    // An empty email removes it, a different case of the own name is no conflict
    let (status, body) = admin.post(&path, update("Alice2", Some(""))).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["user_name"], "Alice2");
    assert_eq!(body["email"], json!(null));

    for (user_name, email, code) in [
        ("BOB", None, "USER_NAME_TAKEN"),
        ("alice2", Some("Bob@example.com"), "EMAIL_TAKEN"),
        ("alice@example.com", None, "VALIDATION_ERROR"),
        ("", None, "VALIDATION_ERROR"),
        ("alice2", Some("alice"), "VALIDATION_ERROR"),
    ] {
        let (_, body) = admin.post(&path, update(user_name, email)).await;
        assert_eq!(body["code"], code, "{user_name}");
    }

    // Admins can be renamed, including themselves
    let (status, body) = admin
        .post(
            &format!("/api/v1/users/{}/update", admin.user_id),
            update("root", Some("root@example.com")),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, me) = admin.get("/api/v1/me").await;
    assert_eq!(me["user_name"], "root");
    assert_eq!(me["email"], "root@example.com");
}

#[sqlx::test]
async fn user_changes_own_user_name_and_email(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;
    app.user("bob@example.com").await;
    let update =
        |user_name: &str, email: Option<&str>| json!({"user_name": user_name, "email": email});

    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["can_change_identity"], true);

    let (status, body) = alice
        .post(
            "/api/v1/me/identity",
            update(" alice2 ", Some(" alice@example.org ")),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["user_name"], "alice2");
    assert_eq!(body["email"], "alice@example.org");

    // The session stays valid, and only the new names log in
    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["user_name"], "alice2");
    assert_eq!(app.login("alice@example.org").await.user_id, alice.user_id);
    let (status, _) = app.try_login("alice@example.com").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    for (user_name, email, code) in [
        ("BOB", None, "USER_NAME_TAKEN"),
        ("alice2", Some("Bob@example.com"), "EMAIL_TAKEN"),
        ("alice@example.com", None, "VALIDATION_ERROR"),
        ("alice2", Some("alice"), "VALIDATION_ERROR"),
    ] {
        let (_, body) = alice
            .post("/api/v1/me/identity", update(user_name, email))
            .await;
        assert_eq!(body["code"], code, "{user_name}");
    }

    // Without the permission, nothing changes, but admins still can
    let path = format!("/api/v1/users/{}/update", alice.user_id);
    let permissions = |can_change_identity: bool| json!({"user_name": "alice2", "email": null, "can_login": true, "can_manage_repositories": true, "can_change_identity": can_change_identity, "must_change_password": false});
    let (status, body) = admin.post(&path, permissions(false)).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["can_change_identity"], false);
    let (status, body) = alice
        .post("/api/v1/me/identity", update("mallory", None))
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["user_name"], "alice2");
    assert_eq!(me["email"], json!(null));

    // Admins cannot lose it
    let (status, body) = admin
        .post(
            &format!("/api/v1/users/{}/update", admin.user_id),
            json!({"user_name": "admin", "email": null, "can_login": true, "can_manage_repositories": true, "can_change_identity": false, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
}

#[sqlx::test]
async fn user_without_repository_permission_only_reads_shared_repositories(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let bob = app.user("bob@example.com").await;
    let shared = app
        .seed_repository(alice.user_id, "shared", &[("README.md", "# Shared")])
        .await;
    let own = app
        .seed_repository(bob.user_id, "own", &[("README.md", "# Own")])
        .await;
    let shared_path = format!("/api/v1/repositories/{}", shared.id);
    let own_path = format!("/api/v1/repositories/{}", own.id);
    let (status, _) = alice
        .post(
            &format!("{shared_path}/users"),
            json!({"user_name_or_email": "bob@example.com"}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, body) = app
        .admin()
        .post(
            &format!("/api/v1/users/{}/update", bob.user_id),
            json!({"user_name": "bob", "email": "bob@example.com", "can_login": true, "can_manage_repositories": false, "can_change_identity": true, "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, me) = bob.get("/api/v1/me").await;
    assert_eq!(me["can_manage_repositories"], false);

    let repository = json!({
        "name": "new",
        "remote": {
            "url": "https://example.com/seeded.git",
            "branch": "main",
            "poll_interval_seconds": 3600,
        },
    });
    let mut update = repository.clone();
    update["remote"]["token"] = json!({"action": "KEEP"});
    for (path, body) in [
        ("/api/v1/repositories".to_string(), repository),
        (format!("{own_path}/update"), update),
        (format!("{own_path}/delete"), json!({})),
        (format!("{own_path}/sync"), json!({})),
        (
            format!("{own_path}/users"),
            json!({"user_name_or_email": "alice@example.com"}),
        ),
    ] {
        let (status, body) = bob.post(&path, body).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{path}: {body}");
        assert_eq!(body["code"], "FORBIDDEN");
    }
    let (status, _) = bob.get(&format!("{own_path}/users")).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Reading and leaving still work
    let (status, body) = bob.get("/api/v1/repositories").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_array().unwrap().len(), 2);
    let (status, _) = bob.get(&shared_path).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = bob
        .post(
            &format!("{shared_path}/users/{}/delete", bob.user_id),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test]
async fn browser_language_is_the_fallback_without_a_locale(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;
    let llm = MockLlm::start(vec![
        text_response("Bonjour"),
        text_response("Hello"),
        text_response("Hallo"),
    ])
    .await;
    app.configure_llm(&llm).await;
    let language = |index: usize| {
        let system = llm.requests()[index]["system"][0]["text"].clone();
        system.as_str().unwrap().lines().last().unwrap().to_string()
    };

    let request = alice
        .request(Method::POST, "/api/v1/chats")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT_LANGUAGE, "fr-CH,fr;q=0.9,en;q=0.8")
        .body(Body::from(
            json!({"content": "Hi", "all_repositories": true}).to_string(),
        ))
        .unwrap();
    let (status, chat) = alice.send(request).await;
    assert_eq!(status, StatusCode::CREATED, "{chat}");
    let chat_id = chat["id"].as_str().unwrap();
    alice.wait_for_answer(chat_id).await;
    assert_eq!(
        language(0),
        "Answer in the language of the question, or in the language of the locale `fr-CH` \
        if that is unclear, and format it with Markdown."
    );

    // Without the header, e.g. from a script, only the question decides
    let messages = format!("/api/v1/chats/{chat_id}/messages");
    let (status, _) = alice.post(&messages, json!({"content": "Hi"})).await;
    assert_eq!(status, StatusCode::CREATED);
    alice.wait_for_answer(chat_id).await;
    assert_eq!(
        language(1),
        "Answer in the language of the question, and format it with Markdown."
    );

    // A chosen locale wins over the browser's
    let (status, _) = alice
        .post("/api/v1/me/locale", json!({"locale": "de-DE"}))
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let request = alice
        .request(Method::POST, &messages)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT_LANGUAGE, "fr-CH")
        .body(Body::from(json!({"content": "Hi"}).to_string()))
        .unwrap();
    let (status, _) = alice.send(request).await;
    assert_eq!(status, StatusCode::CREATED);
    alice.wait_for_answer(chat_id).await;
    assert_eq!(
        language(2),
        "Answer in the language of the question, or in the language of the locale `de-DE` \
        if that is unclear, and format it with Markdown."
    );
}

#[sqlx::test]
async fn admin_sets_password_and_requires_change(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    let alice = app.user("alice@example.com").await;
    let path = format!("/api/v1/users/{}/password", alice.user_id);

    let (status, body) = alice
        .post(
            &path,
            json!({"password": "admin-chosen", "must_change_password": true}),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    let (_, body) = admin
        .post(
            &path,
            json!({"password": "short", "must_change_password": true}),
        )
        .await;
    assert_eq!(body["code"], "VALIDATION_ERROR");
    let (status, body) = admin
        .post(
            &format!("/api/v1/users/{}/password", admin.user_id),
            json!({"password": "admin-chosen", "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    let (status, _) = admin
        .post(
            &format!("/api/v1/users/{}/password", uuid::Uuid::now_v7()),
            json!({"password": "admin-chosen", "must_change_password": false}),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, body) = admin
        .post(
            &path,
            json!({"password": "admin-chosen", "must_change_password": true}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["must_change_password"], true);

    // Signed out everywhere, and only the new password logs in
    let (status, _) = alice.get("/api/v1/me").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = app.try_login("alice@example.com").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let alice = app
        .login_with_password("alice@example.com", "admin-chosen")
        .await;

    // Nothing but changing the password works until it is changed
    let (status, me) = alice.get("/api/v1/me").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(me["must_change_password"], true);
    let (status, body) = alice.get("/api/v1/chats").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "PASSWORD_CHANGE_REQUIRED");

    let change =
        |current: &str, new: &str| json!({"current_password": current, "new_password": new});
    let (_, body) = alice
        .post(
            "/api/v1/change-password",
            change("admin-chosen", "admin-chosen"),
        )
        .await;
    assert_eq!(body["code"], "SAME_PASSWORD");
    let (status, body) = alice
        .post(
            "/api/v1/change-password",
            change("admin-chosen", "alice-chosen"),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");

    let (_, me) = alice.get("/api/v1/me").await;
    assert_eq!(me["must_change_password"], false);
    let (status, _) = alice.get("/api/v1/chats").await;
    assert_eq!(status, StatusCode::OK);

    // An admin can require a change without setting the password, also of other admins
    let (status, body) = admin
        .post(
            &format!("/api/v1/users/{}/update", alice.user_id),
            json!({"user_name": "alice", "email": "alice@example.com", "can_login": true, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": true}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, body) = alice.get("/api/v1/chats").await;
    assert_eq!(body["code"], "PASSWORD_CHANGE_REQUIRED");
    let (status, body) = admin
        .post(
            &format!("/api/v1/users/{}/update", admin.user_id),
            json!({"user_name": "admin", "email": null, "can_login": true, "can_manage_repositories": true, "can_change_identity": true, "must_change_password": true}),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, body) = admin.get("/api/v1/users").await;
    assert_eq!(body["code"], "PASSWORD_CHANGE_REQUIRED");
}

#[sqlx::test]
async fn initial_admin_without_password_change(db: SqlitePool) {
    // As an app starts its local instance, with a password it generated.
    let dir = TempDir::new().unwrap();
    let mut config = support::config(
        &dir.path().join("repos"),
        &dir.path().join("attachments"),
        false,
    );
    config.initial_admin_password = Some("generated-admin-password".to_string());
    config.initial_admin_must_change_password = false;
    let repolupe = Repolupe::new(config, db).await.unwrap();

    let router = repolupe.router();
    let (status, body) = support::try_login(
        &router,
        INITIAL_ADMIN_USER_NAME,
        DEFAULT_INITIAL_ADMIN_PASSWORD,
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
    let (status, body) =
        support::try_login(&router, INITIAL_ADMIN_USER_NAME, "generated-admin-password").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["user"]["must_change_password"], false);

    // Everything works right away.
    let admin = support::login(router, INITIAL_ADMIN_USER_NAME, "generated-admin-password").await;
    let (status, body) = admin.get("/api/v1/users").await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body[0]["role"], "ADMIN");
    assert_eq!(body[0]["must_change_password"], false);
}
