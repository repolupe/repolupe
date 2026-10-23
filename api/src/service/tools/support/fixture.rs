//! A git repository to run the tools on in tests.

use super::commit::CommitIdentities;
use crate::model::document_extraction::DocumentExtraction;
use crate::model::tool_call::ProposedChange;
use crate::repository;
use crate::service::llm::ToolUse;
use crate::service::mirror::Snapshot;
use crate::service::tools::{CHANGE_FILE, RepositoryTools, ToolOutput, ToolRepository, test_db};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;
use uuid::Uuid;

/// A git repository with `files` committed, removed when dropped.
pub(crate) struct Fixture {
    pub(crate) dir: PathBuf,
    pub(crate) tools: RepositoryTools,
}

pub(crate) fn identities() -> CommitIdentities {
    CommitIdentities::new(
        "model",
        "Alice".to_string(),
        Some("alice@example.com".to_string()),
    )
}

fn git(dir: &Path, args: &[&str]) -> String {
    let output = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["-c", "user.name=Test", "-c", "user.email=test@example.com"])
        .args(["-c", "core.autocrlf=false"])
        .args(args)
        .output()
        .unwrap();
    assert!(output.status.success(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}

impl Fixture {
    pub(crate) fn new(files: &[(&str, &[u8])]) -> Self {
        let dir = std::env::temp_dir().join(format!("repolupe-tools-{}", Uuid::now_v7()));
        for (path, content) in files {
            let path = dir.join(path);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, content).unwrap();
        }
        git(&dir, &["init", "--quiet"]);
        git(&dir, &["add", "--all"]);
        git(&dir, &["commit", "--quiet", "--message", "init"]);
        let commit = git(&dir, &["rev-parse", "HEAD"]).trim().to_string();
        let tools = RepositoryTools::new(
            vec![ToolRepository {
                id: Uuid::now_v7(),
                name: "docs".to_string(),
                snapshot: Snapshot::at(dir.join(".git"), commit),
                can_commit: true,
            }],
            test_db(),
            identities(),
        );
        Self { dir, tools }
    }

    pub(crate) fn git(&self, args: &[&str]) -> String {
        git(&self.dir, args)
    }

    /// Stores `extraction` as the extraction of the document at `path`.
    pub(crate) async fn extract(&self, path: &str, extraction: DocumentExtraction) {
        let oid = self.git(&["rev-parse", &format!("HEAD:{path}")]);
        repository::document::save_extraction(&self.tools.db, oid.trim(), &extraction, "test")
            .await
            .unwrap();
    }

    /// Proposes a change and returns the output and the proposed commit.
    pub(crate) async fn change(&self, input: Value) -> (String, ProposedChange) {
        let output = self.run(CHANGE_FILE, input).await;
        assert!(!output.is_error, "{}", output.content);
        (output.content, output.change.unwrap())
    }

    pub(crate) async fn run(&self, name: &str, input: Value) -> ToolOutput {
        let tool_use = ToolUse {
            id: "call".to_string(),
            name: name.to_string(),
            input,
            native: None,
        };
        match self.tools.parse(&tool_use) {
            Ok(invocation) => invocation.run().await,
            Err(content) => ToolOutput::error(content),
        }
    }

    pub(crate) async fn ok(&self, name: &str, input: Value) -> String {
        let output = self.run(name, input).await;
        assert!(!output.is_error, "{}", output.content);
        output.content
    }

    pub(crate) async fn error(&self, name: &str, input: Value) -> String {
        let output = self.run(name, input).await;
        assert!(output.is_error, "{}", output.content);
        output.content
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

pub(crate) const LFS_POINTER: &[u8] = b"version https://git-lfs.github.com/spec/v1\noid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393\nsize 12345\n";

pub(crate) const GUIDE: &str = "# Guide\n\nIntro\n\n## Install\n\nRun `make install`.\n\n### macOS\n\nUse Homebrew.\n\n## Usage\n\nCall the API with your API key.\n";

pub(crate) fn docs() -> Fixture {
    Fixture::new(&[
        (
            "README.md",
            b"# Project\n\nSee docs/guide.md for the API key.\n",
        ),
        ("docs/guide.md", GUIDE.as_bytes()),
        (
            "docs/faq/limits.md",
            b"Rate limits\n===========\n\nThe api allows 10 requests.\n",
        ),
        ("src/main.rs", b"fn main() { let api_key = 1; }\n"),
        ("logo.png", b"\x89PNG\r\n\x1a\n\0\0\0"),
        ("slides.pdf", LFS_POINTER),
        ("demo.mp4", LFS_POINTER),
    ])
}
