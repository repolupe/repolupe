use super::support::{INSTANCE_NAME, TestApp};
use axum::http::StatusCode;
use serde_json::{Value, json};
use sqlx::SqlitePool;

/// `GET /api/v1/config` as `{key: override}`, only the overridden keys.
fn overrides(body: &Value) -> Value {
    body.as_array()
        .unwrap()
        .iter()
        .filter(|entry| !entry["override"].is_null())
        .map(|entry| {
            (
                entry["key"].as_str().unwrap().to_string(),
                entry["override"].clone(),
            )
        })
        .collect::<serde_json::Map<_, _>>()
        .into()
}

#[sqlx::test]
async fn admin_overrides_runtime_config(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();

    let entry = |key: &str, env: Option<&str>, runtime: bool| json!({"key": key, "env": env, "override": null, "runtime": runtime});
    let repos_dir = app.repos_dir().display().to_string();
    let attachments_dir = app.attachments_dir().display().to_string();
    let (status, body) = admin.get("/api/v1/config").await;
    assert_eq!(status, StatusCode::OK);
    // Every key, unset ones as null and secrets masked
    assert_eq!(
        body,
        json!([
            entry("ADMIN_PASSWORD", None, false),
            entry("ATTACHMENTS_DIR", Some(&attachments_dir), false),
            entry("DATABASE_URL", Some("******"), false),
            entry("DEBUG_API", Some("false"), false),
            entry("FRONTEND_DIR", None, false),
            entry("INSTANCE_NAME", Some(INSTANCE_NAME), true),
            entry("OCR_API_KEY_MISTRAL", None, false),
            entry("OCR_ENGINE", Some("none"), true),
            entry("OCR_LANGUAGES", Some("eng"), true),
            entry("OCR_SCAN_CONFIDENCE", Some("0.5"), true),
            entry("REPOS_DIR", Some(&repos_dir), false),
            entry("TOKEN_ENCRYPTION_KEY", Some("******"), false),
        ])
    );

    let (status, body) = admin
        .post(
            "/api/v1/config",
            json!({"INSTANCE_NAME": "Acme", "OCR_LANGUAGES": "deu,eng", "OCR_SCAN_CONFIDENCE": "0.7"}),
        )
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        overrides(&body),
        json!({"INSTANCE_NAME": "Acme", "OCR_LANGUAGES": "deu,eng", "OCR_SCAN_CONFIDENCE": "0.7"})
    );
    assert_eq!(body[5]["env"], INSTANCE_NAME);
    let (_, fetched) = admin.get("/api/v1/config").await;
    assert_eq!(fetched, body);
    // Applied without a restart
    let (_, body) = admin.get("/api/v1/instance").await;
    assert_eq!(body, json!({"name": "Acme"}));

    // The whole map is replaced, so OCR_LANGUAGES falls back to its default
    let (status, body) = admin
        .post("/api/v1/config", json!({"INSTANCE_NAME": "Acme Corp"}))
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(overrides(&body), json!({"INSTANCE_NAME": "Acme Corp"}));

    let (status, body) = admin.post("/api/v1/config", json!({})).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(overrides(&body), json!({}));
    let (_, body) = admin.get("/api/v1/instance").await;
    assert_eq!(body, json!({"name": INSTANCE_NAME}));
}

#[sqlx::test]
async fn stored_config_is_applied_on_startup(db: SqlitePool) {
    let app = TestApp::new(db.clone()).await;
    let (status, _) = app
        .admin()
        .post("/api/v1/config", json!({"INSTANCE_NAME": "Acme"}))
        .await;
    assert_eq!(status, StatusCode::OK);
    // Stored with SQL, or before OCR_API_KEY_MISTRAL was removed
    sqlx::query!(
        "INSERT INTO config (key, value) VALUES ('OCR_ENGINE', 'mistral'), ('REPOS_DIR', '/tmp')"
    )
    .execute(&db)
    .await
    .unwrap();
    drop(app);

    let app = TestApp::new(db).await;
    // The invalid ones are skipped
    let (_, body) = app.admin().get("/api/v1/config").await;
    assert_eq!(overrides(&body), json!({"INSTANCE_NAME": "Acme"}));
    let (_, body) = app.admin().get("/api/v1/instance").await;
    assert_eq!(body, json!({"name": "Acme"}));
}

#[sqlx::test]
async fn invalid_config_is_rejected(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let admin = app.admin();
    admin
        .post("/api/v1/config", json!({"INSTANCE_NAME": "Acme"}))
        .await;

    for body in [
        json!({"REPOS_DIR": "/tmp"}),
        json!({"instance_name": "Acme"}),
        json!({"INSTANCE_NAME": " "}),
        json!({"OCR_ENGINE": "magic"}),
        // Without OCR_API_KEY_MISTRAL
        json!({"OCR_ENGINE": "mistral"}),
        json!({"OCR_LANGUAGES": "../eng"}),
        json!({"DEBUG_API": true}),
        json!(["INSTANCE_NAME"]),
    ] {
        let (status, response) = admin.post("/api/v1/config", body.clone()).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
        assert_eq!(response["code"], "VALIDATION_ERROR");
    }

    let (_, body) = admin.get("/api/v1/config").await;
    assert_eq!(overrides(&body), json!({"INSTANCE_NAME": "Acme"}));
}

#[sqlx::test]
async fn only_admins_access_config(db: SqlitePool) {
    let app = TestApp::new(db).await;
    let alice = app.user("alice@example.com").await;

    let (status, _) = alice.get("/api/v1/config").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = alice
        .post("/api/v1/config", json!({"INSTANCE_NAME": "Mine"}))
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
