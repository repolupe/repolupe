use super::mock_llm::MockLlm;
use axum::Router;
use axum::body::Body;
use axum::http::{Method, Request, StatusCode, header, request};
use chrono::{TimeDelta, Utc};
use repolupe::{
    Config, DEFAULT_INITIAL_ADMIN_PASSWORD, DEFAULT_SESSION_IDLE_TIMEOUT, INITIAL_ADMIN_USER_NAME,
    Repolupe, RuntimeConfig,
};
use serde_json::{Value, json};
use sqlx::SqlitePool;
use std::path::Path;
use std::process::Command;
use std::time::Duration;
use tempfile::TempDir;
use tower::ServiceExt;
use uuid::Uuid;

/// Longest wait for a generation to finish, see [`TestClient::wait_for_answer`].
const ANSWER_TIMEOUT: Duration = Duration::from_secs(10);

const PASSWORD: &str = "integration-tests-password";

pub const INSTANCE_NAME: &str = "Test Instance";

/// An extraction stored by [`TestApp::seed_extraction`].
pub enum SeededExtraction<'a> {
    Completed { markdown: &'a str, ocr: bool },
    Failed { error: &'a str },
}

/// The app on the database of one test, with its initial admin logged in (with the password
/// changed to the one [`TestApp::user`] registers users with).
///
/// The background tasks are not started, see [`TestApp::start_background_tasks`].
pub struct TestApp {
    db: SqlitePool,
    admin: TestClient,
    repos_dir: TempDir,
    attachments_dir: TempDir,
    _repolupe: Repolupe,
}

/// The provider and model registered by [`TestApp::configure_llm`].
pub struct ConfiguredLlm {
    pub provider_id: String,
    pub model_id: String,
}

/// A repository as a finished sync leaves it.
pub struct SeededRepository {
    pub id: Uuid,
    pub commit_sha: String,
}

impl TestApp {
    pub async fn new(db: SqlitePool) -> Self {
        let repos_dir = TempDir::new().unwrap();
        let attachments_dir = TempDir::new().unwrap();
        let repolupe = Repolupe::new(
            config(repos_dir.path(), attachments_dir.path(), false),
            db.clone(),
        )
        .await
        .unwrap();
        let admin = login_initial_admin(repolupe.router()).await;
        Self {
            db,
            admin,
            repos_dir,
            attachments_dir,
            _repolupe: repolupe,
        }
    }

    /// Starts a second instance on the same database and repositories with the background
    /// tasks, which stop when it is dropped. It converts the queued documents right away. Its
    /// sync loop does not fetch the seeded repositories, which are not due for an hour, see
    /// [`Self::seed_repository`], but cleans up right away, e.g. unsent attachments.
    pub async fn start_background_tasks(&self) -> Repolupe {
        Repolupe::new(
            config(self.repos_dir.path(), self.attachments_dir.path(), true),
            self.db.clone(),
        )
        .await
        .unwrap()
    }

    pub fn admin(&self) -> TestClient {
        self.admin.clone()
    }

    pub fn repos_dir(&self) -> &Path {
        self.repos_dir.path()
    }

    pub fn attachments_dir(&self) -> &Path {
        self.attachments_dir.path()
    }

    /// Makes the attachment `id` look uploaded two days ago, so the cleanup removes it if it
    /// was not sent.
    pub async fn age_attachment(&self, id: &str) {
        let id: Uuid = id.parse().unwrap();
        let created_at = Utc::now() - TimeDelta::days(2);
        sqlx::query!(
            "UPDATE attachments SET created_at = $2 WHERE id = $1",
            id,
            created_at
        )
        .execute(&self.db)
        .await
        .unwrap();
    }

    /// Makes the last message of the chat `id` look sent two days ago, so the cleanup deletes
    /// it if it is temporary.
    pub async fn age_chat(&self, id: &str) {
        let id: Uuid = id.parse().unwrap();
        let updated_at = Utc::now() - TimeDelta::days(2);
        sqlx::query!(
            "UPDATE chats SET updated_at = $2 WHERE id = $1",
            id,
            updated_at
        )
        .execute(&self.db)
        .await
        .unwrap();
    }

    /// Registers the user through the admin, with the part of `email` before the `@` as the
    /// user name, and logs in.
    pub async fn user(&self, email: &str) -> TestClient {
        let user_name = email.split_once('@').unwrap().0;
        let (status, body) = self
            .admin
            .post(
                "/api/v1/register",
                json!({"user_name": user_name, "email": email, "password": PASSWORD}),
            )
            .await;
        assert_eq!(status, StatusCode::OK, "{body}");
        login(self.admin.router.clone(), email, PASSWORD).await
    }

    /// Logs in again as a user registered by [`Self::user`], by user name or email.
    pub async fn login(&self, user_name_or_email: &str) -> TestClient {
        login(self.admin.router.clone(), user_name_or_email, PASSWORD).await
    }

    /// Like [`Self::login`], but returns the response instead of asserting success.
    pub async fn try_login(&self, user_name_or_email: &str) -> (StatusCode, Value) {
        try_login(&self.admin.router, user_name_or_email, PASSWORD).await
    }

    /// Logs in with a password other than the one [`Self::user`] registers users with.
    pub async fn login_with_password(
        &self,
        user_name_or_email: &str,
        password: &str,
    ) -> TestClient {
        login(self.admin.router.clone(), user_name_or_email, password).await
    }

    /// Registers `llm` as a provider with one model, `mock-model`, which becomes the default.
    pub async fn configure_llm(&self, llm: &MockLlm) -> ConfiguredLlm {
        let (status, provider) = self
            .admin
            .post(
                "/api/v1/llm-providers",
                json!({
                    "name": "Mock",
                    "api_format": "ANTHROPIC",
                    "base_url": llm.base_url,
                    "currency": "EUR",
                }),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{provider}");
        let provider_id = provider["id"].as_str().unwrap();
        let (status, model) = self
            .admin
            .post(
                &format!("/api/v1/llm-providers/{provider_id}/models"),
                json!({"api_name": "mock-model", "display_name": "Mock Model"}),
            )
            .await;
        assert_eq!(status, StatusCode::CREATED, "{model}");
        assert_eq!(model["is_default"], true);
        ConfiguredLlm {
            provider_id: provider_id.to_string(),
            model_id: model["id"].as_str().unwrap().to_string(),
        }
    }

    /// Creates a repository of `user_id` with `files` committed on `main`, in the state a
    /// successful sync leaves: a bare repository in its directory, and the row `READY` at
    /// that commit. Nothing is fetched, the remote URL is a placeholder.
    ///
    /// The row is inserted directly, since creating a repository through the API checks
    /// that the remote is reachable.
    pub async fn seed_repository(
        &self,
        user_id: Uuid,
        name: &str,
        files: &[(&str, impl AsRef<[u8]>)],
    ) -> SeededRepository {
        let id = Uuid::now_v7();
        let commit_sha = create_bare_repository(&self.repos_dir.path().join(id.to_string()), files);

        let now = Utc::now();
        let next_sync_at = now + TimeDelta::hours(1);
        sqlx::query!(
            r#"INSERT INTO repositories (id, user_id, name, remote_url, branch, poll_interval_seconds,
                                         allow_commits, sync_status, head_commit_sha, last_synced_at,
                                         next_sync_at, created_at, updated_at)
               VALUES ($1, $2, $3, 'https://example.com/seeded.git', 'main', 3600,
                       false, 'READY', $4, $5, $6, $5, $5)"#,
            id,
            user_id,
            name,
            commit_sha,
            now,
            next_sync_at,
        )
        .execute(&self.db)
        .await
        .unwrap();

        SeededRepository { id, commit_sha }
    }

    /// Lets the model propose commits to `repository`. The API would first check that the
    /// remote takes pushes, which a seeded repository has none of.
    pub async fn allow_commits(&self, repository: &SeededRepository) {
        sqlx::query!(
            "UPDATE repositories SET allow_commits = true WHERE id = $1",
            repository.id
        )
        .execute(&self.db)
        .await
        .unwrap();
    }

    /// Makes the repository due for a sync, like `POST .../sync` without its throttle.
    pub async fn request_sync_now(&self, id: &str) {
        let id: Uuid = id.parse().unwrap();
        let now = Utc::now();
        sqlx::query!(
            "UPDATE repositories SET next_sync_at = $2 WHERE id = $1",
            id,
            now
        )
        .execute(&self.db)
        .await
        .unwrap();
    }

    /// Records the document at `path` in `repository` as a sync would, which queues it for
    /// conversion, and returns its blob.
    pub async fn seed_document(&self, repository: &SeededRepository, path: &str) -> String {
        let git_dir = self.repos_dir.path().join(repository.id.to_string());
        let blob_oid = git(
            &git_dir,
            &["rev-parse", &format!("{}:{path}", repository.commit_sha)],
        )
        .trim()
        .to_string();
        sqlx::query!(
            "INSERT INTO repository_documents (repository_id, path, blob_oid) VALUES ($1, $2, $3)",
            repository.id,
            path,
            blob_oid,
        )
        .execute(&self.db)
        .await
        .unwrap();
        blob_oid
    }

    /// Records the document at `path` in `repository` with an extraction, made with the
    /// extractor `seeded`, not the current one, which the background tasks would replace.
    pub async fn seed_extraction(
        &self,
        repository: &SeededRepository,
        path: &str,
        extraction: SeededExtraction<'_>,
    ) {
        let blob_oid = self.seed_document(repository, path).await;
        let (markdown, ocr, error) = match extraction {
            SeededExtraction::Completed { markdown, ocr } => (Some(markdown), Some(ocr), None),
            SeededExtraction::Failed { error } => (None, None, Some(error)),
        };
        let now = Utc::now();
        sqlx::query!(
            r#"INSERT INTO document_extractions (blob_oid, status, markdown, ocr, error, extractor, extracted_at)
               VALUES ($1, CASE WHEN $2 IS NULL THEN 'FAILED' ELSE 'COMPLETED' END, $2, $3, $4, 'seeded', $5)"#,
            blob_oid,
            markdown,
            ocr,
            error,
            now,
        )
        .execute(&self.db)
        .await
        .unwrap();
    }

    /// Marks every extraction as made with `extractor`, e.g. the current one from
    /// `GET /api/v1/document-extraction`, so they are not converted again.
    pub async fn set_extractor(&self, extractor: &str) {
        sqlx::query!("UPDATE document_extractions SET extractor = $1", extractor)
            .execute(&self.db)
            .await
            .unwrap();
    }
}

/// The config of [`TestApp`], for tests that start a [`Repolupe`] themselves.
pub fn config(repos_dir: &Path, attachments_dir: &Path, background_tasks: bool) -> Config {
    Config {
        token_encryption_key: "integration-tests-secret-0123456789".to_string(),
        repos_dir: repos_dir.to_path_buf(),
        attachments_dir: attachments_dir.to_path_buf(),
        frontend_dir: None,
        initial_admin_password: None,
        initial_admin_must_change_password: true,
        session_idle_timeout: Some(DEFAULT_SESSION_IDLE_TIMEOUT),
        // Applied by `#[sqlx::test]`
        run_migrations: false,
        background_tasks,
        debug_api: false,
        ocr_api_key_mistral: None,
        runtime: RuntimeConfig {
            instance_name: INSTANCE_NAME.to_string(),
            ..RuntimeConfig::default()
        },
    }
}

/// Logs in the initial admin and changes its default password to [`PASSWORD`], which it has to
/// do first. On a database it was already changed on, logs in with [`PASSWORD`].
async fn login_initial_admin(router: Router) -> TestClient {
    let (status, _) = try_login(
        &router,
        INITIAL_ADMIN_USER_NAME,
        DEFAULT_INITIAL_ADMIN_PASSWORD,
    )
    .await;
    if status == StatusCode::UNAUTHORIZED {
        return login(router, INITIAL_ADMIN_USER_NAME, PASSWORD).await;
    }

    let admin = login(
        router,
        INITIAL_ADMIN_USER_NAME,
        DEFAULT_INITIAL_ADMIN_PASSWORD,
    )
    .await;
    let (_, body) = admin.get("/api/v1/chats").await;
    assert_eq!(body["code"], "PASSWORD_CHANGE_REQUIRED");
    let (status, body) = admin
        .post(
            "/api/v1/change-password",
            json!({"current_password": DEFAULT_INITIAL_ADMIN_PASSWORD, "new_password": PASSWORD}),
        )
        .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    admin
}

pub async fn login(router: Router, user_name_or_email: &str, password: &str) -> TestClient {
    let (status, body) = try_login(&router, user_name_or_email, password).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    TestClient {
        router,
        user_id: body["user"]["id"].as_str().unwrap().parse().unwrap(),
        token: body["token"].as_str().unwrap().to_string(),
    }
}

pub async fn try_login(
    router: &Router,
    user_name_or_email: &str,
    password: &str,
) -> (StatusCode, Value) {
    let request = Request::builder()
        .method(Method::POST)
        .uri("/api/v1/login")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(
            json!({"user_name_or_email": user_name_or_email, "password": password}).to_string(),
        ))
        .unwrap();
    send(router, request).await
}

/// Creates a bare repository at `target` with `files` committed on `main`, and returns the commit.
pub fn create_bare_repository(target: &Path, files: &[(&str, impl AsRef<[u8]>)]) -> String {
    let work = TempDir::new().unwrap();
    for (path, content) in files {
        let path = work.path().join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, content).unwrap();
    }
    git(work.path(), &["init", "--quiet", "--initial-branch=main"]);
    git(work.path(), &["add", "--all"]);
    git(work.path(), &["commit", "--quiet", "--message", "init"]);
    let commit_sha = git(work.path(), &["rev-parse", "HEAD"]).trim().to_string();
    git(
        work.path(),
        &["clone", "--bare", "--quiet", ".", target.to_str().unwrap()],
    );
    commit_sha
}

/// Runs git in `dir` and returns its stdout.
pub fn git(dir: &Path, args: &[&str]) -> String {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["-c", "user.name=Test", "-c", "user.email=test@example.com"])
        .args(args)
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}

/// Sends requests to the app in-process, authenticated as one user with `Authorization: Bearer`.
#[derive(Clone)]
pub struct TestClient {
    router: Router,
    pub user_id: Uuid,
    pub token: String,
}

impl TestClient {
    /// The same user on `instance`, e.g. the one of [`TestApp::start_background_tasks`], whose
    /// in-memory state the other instance does not see. Sessions are stored in the database.
    pub fn on(&self, instance: &Repolupe) -> TestClient {
        TestClient {
            router: instance.router(),
            ..self.clone()
        }
    }

    pub async fn get(&self, path: &str) -> (StatusCode, Value) {
        let request = self.request(Method::GET, path).body(Body::empty()).unwrap();
        self.send(request).await
    }

    pub async fn post(&self, path: &str, body: Value) -> (StatusCode, Value) {
        let request = self
            .request(Method::POST, path)
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(body.to_string()))
            .unwrap();
        self.send(request).await
    }

    /// Uploads `content` as an attachment, like the browser does.
    pub async fn upload(&self, file_name: &str, content: &[u8]) -> (StatusCode, Value) {
        let request = self
            .request(
                Method::POST,
                &format!("/api/v1/attachments?file_name={file_name}&content_type=text/plain"),
            )
            .header(header::CONTENT_TYPE, "application/octet-stream")
            .body(Body::from(content.to_vec()))
            .unwrap();
        self.send(request).await
    }

    /// A request with the bearer token, for tests that need other headers.
    pub fn request(&self, method: Method, path: &str) -> request::Builder {
        Request::builder()
            .method(method)
            .uri(path)
            .header(header::AUTHORIZATION, format!("Bearer {}", self.token))
    }

    /// For responses that are not JSON, returns the content type and the body.
    pub async fn get_raw(&self, path: &str) -> (StatusCode, Option<String>, Vec<u8>) {
        let request = self.request(Method::GET, path).body(Body::empty()).unwrap();
        let response = self.router.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let content_type = response
            .headers()
            .get(header::CONTENT_TYPE)
            .map(|v| v.to_str().unwrap().to_string());
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        (status, content_type, bytes.to_vec())
    }

    /// The response as it is, e.g. to check its headers.
    pub async fn response(&self, request: Request<Body>) -> axum::response::Response {
        self.router.clone().oneshot(request).await.unwrap()
    }

    /// Returns the body as JSON, `null` if empty.
    pub async fn send(&self, request: Request<Body>) -> (StatusCode, Value) {
        send(&self.router, request).await
    }

    /// Polls the chat until its last message is no longer `GENERATING`, and returns it.
    pub async fn wait_for_answer(&self, chat_id: &str) -> Value {
        let path = format!("/api/v1/chats/{chat_id}");
        let poll = async {
            loop {
                let (status, body) = self.get(&path).await;
                assert_eq!(status, StatusCode::OK, "{body}");
                let last = body["messages"].as_array().unwrap().last().unwrap().clone();
                if last["status"] != "GENERATING" {
                    return last;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        };
        tokio::time::timeout(ANSWER_TIMEOUT, poll)
            .await
            .expect("answer did not finish in time")
    }
}

async fn send(router: &Router, request: Request<Body>) -> (StatusCode, Value) {
    let response = router.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes)
            .unwrap_or_else(|e| panic!("{status}: {e}: {}", String::from_utf8_lossy(&bytes)))
    };
    (status, body)
}
