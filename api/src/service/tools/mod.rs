//! The tools the model uses to look into the repositories in scope of a chat, and to propose
//! commits to the ones the user lets it change ([`CHANGE_FILE`], [`MOVE_FILES`], and
//! [`SAVE_ATTACHMENT`] for the files attached to the chat). They read the git objects of
//! one commit per repository, so all tool calls of an answer see the same version, even while
//! the repository is synced. [`READ_ATTACHMENT`] reads the files attached to the chat, so it is
//! bound to no repository and also offered in chats without one, like [`RUN_SCRIPT`], which
//! runs JavaScript the model writes to calculate, and only reads a repository for the files it
//! passes to the script.
//!
//! Each tool is a module of its own, with its `definition` for the model, `parse`, which turns
//! the model's input into a [`Call`], and `run`. What several tools need is in [`support`]. A
//! new tool also needs a name below, a variant of [`Call`], and an arm in
//! [`RepositoryTools::definitions`], [`RepositoryTools::parse`] and [`Invocation::run`]. The
//! answer drops the text before calls that look things up, see `answer.rs`; tools that
//! don't must be listed there.

mod change_file;
mod grep;
mod list_files;
mod move_files;
mod outline;
mod present_file;
mod read_attachment;
mod read_file;
mod run_script;
mod save_attachment;
mod support;

use crate::config::error::AppError;
use crate::config::state::DatabasePool;
use crate::model::attachment::Attachment;
use crate::model::tool_call::ProposedChange;
use crate::service::attachment::AttachmentStore;
use crate::service::extraction::DocumentExtractor;
use crate::service::llm::{ToolDefinition, ToolUse};
use crate::service::mirror::Snapshot;
use serde_json::Value;
use std::collections::BTreeSet;
use std::sync::Arc;
use support::format_size;
use uuid::Uuid;

pub(crate) use present_file::{PresentedFile, read_presented_file};
pub(crate) use support::commit::{
    CommitIdentities, read_proposed_commit_diff, read_proposed_commit_patch,
};

pub(crate) const LIST_FILES: &str = "list_files";
pub(crate) const READ_FILE: &str = "read_file";
pub(crate) const GREP: &str = "grep";
pub(crate) const OUTLINE: &str = "outline";
pub(crate) const PRESENT_FILE: &str = "present_file_to_user";
pub(crate) const CHANGE_FILE: &str = "change_file";
pub(crate) const MOVE_FILES: &str = "move_files";
pub(crate) const SAVE_ATTACHMENT: &str = "save_attachment";
pub(crate) const READ_ATTACHMENT: &str = "read_attachment";
pub(crate) const RUN_SCRIPT: &str = "run_script";

/// A repository the tools can read, at the commit the answer refers to.
pub(crate) struct ToolRepository {
    pub(crate) id: Uuid,
    /// How the model refers to it, unique among the repositories in scope.
    pub(crate) name: String,
    pub(crate) snapshot: Snapshot,
    /// Whether the model may propose commits to it with [`CHANGE_FILE`] and [`MOVE_FILES`].
    pub(crate) can_commit: bool,
}

/// The tools for a set of repositories. Without repositories, the model only gets the tools
/// bound to no repository.
pub(crate) struct RepositoryTools {
    repositories: Vec<ToolRepository>,
    /// For the Markdown converted from documents, see [`crate::service::extraction`].
    db: DatabasePool,
    identities: CommitIdentities,
    attachments: ChatAttachments,
    /// Whether the proposed commits are committed once the answer is complete, see
    /// [`Self::with_auto_commit`].
    auto_commit: bool,
}

/// The files sent in the chat, which [`READ_ATTACHMENT`] reads and [`SAVE_ATTACHMENT`] stores
/// in a repository.
#[derive(Default)]
struct ChatAttachments {
    store: Option<Arc<AttachmentStore>>,
    /// For the Markdown converted from documents, which may still be converting.
    extractor: Option<Arc<DocumentExtractor>>,
    /// Sent, so each has a number.
    sent: Vec<Attachment>,
}

impl ChatAttachments {
    /// Attachment `number`, an error for the model that lists the others if there is none.
    fn find(&self, number: i32) -> Result<&Attachment, ToolError> {
        self.sent
            .iter()
            .find(|a| a.number == Some(number))
            .ok_or_else(|| {
                let available = self
                    .sent
                    .iter()
                    .filter_map(|a| Some(format!("{} (`{}`)", a.number?, a.file_name)))
                    .collect::<Vec<_>>()
                    .join(", ");
                ToolError::Invalid(format!(
                    "There is no attachment {number}. Attachments: {available}."
                ))
            })
    }

    fn store(&self) -> Result<&AttachmentStore, AppError> {
        self.store.as_deref().ok_or_else(|| {
            AppError::InternalServerError("Attachments without their store".to_string())
        })
    }
}

/// A tool call that passed validation, see [`RepositoryTools::parse`].
pub(crate) struct Invocation<'a> {
    /// `None` for the tools bound to no repository, see [`Self::target`].
    repository: Option<&'a ToolRepository>,
    db: &'a DatabasePool,
    identities: &'a CommitIdentities,
    attachments: &'a ChatAttachments,
    auto_commit: bool,
    call: Call,
}

/// The arguments of a call, validated by the tool's `parse`.
enum Call {
    ListFiles(list_files::Args),
    ReadFile(read_file::Args),
    Grep(grep::Args),
    Outline(outline::Args),
    PresentFile(present_file::Args),
    ChangeFile(change_file::Args),
    MoveFiles(move_files::Args),
    SaveAttachment(save_attachment::Args),
    ReadAttachment(read_attachment::Args),
    RunScript(run_script::Args),
}

/// The result to send back to the model.
#[derive(Debug)]
pub(crate) struct ToolOutput {
    pub(crate) content: String,
    pub(crate) is_error: bool,
    /// The commit a successful [`CHANGE_FILE`], [`MOVE_FILES`] or [`SAVE_ATTACHMENT`] call
    /// proposed, to store with the call.
    pub(crate) change: Option<ProposedChange>,
}

impl ToolOutput {
    pub(crate) fn error(content: String) -> Self {
        Self {
            content,
            is_error: true,
            change: None,
        }
    }
}

enum ToolError {
    /// Caused by the arguments, the message tells the model what to change.
    Invalid(String),
    Internal(AppError),
}

impl From<AppError> for ToolError {
    fn from(error: AppError) -> Self {
        Self::Internal(error)
    }
}

impl RepositoryTools {
    /// Names that only differ in case get a suffix, so the model can tell them apart.
    pub(crate) fn new(
        mut repositories: Vec<ToolRepository>,
        db: DatabasePool,
        identities: CommitIdentities,
    ) -> Self {
        let mut taken = BTreeSet::new();
        for repository in &mut repositories {
            let mut name = repository.name.clone();
            let mut n = 2;
            while !taken.insert(name.to_lowercase()) {
                name = format!("{} ({n})", repository.name);
                n += 1;
            }
            repository.name = name;
        }
        Self {
            repositories,
            db,
            identities,
            attachments: ChatAttachments::default(),
            auto_commit: false,
        }
    }

    /// Tells the model that the commits it proposes are committed once the answer is complete,
    /// for a user who turned on `auto_commit`, instead of that the user decides.
    pub(crate) fn with_auto_commit(mut self, auto_commit: bool) -> Self {
        self.auto_commit = auto_commit;
        self
    }

    /// Lets the model read the attachments sent in the chat with [`READ_ATTACHMENT`] and store
    /// them with [`SAVE_ATTACHMENT`], read from `store`, documents as converted by `extractor`.
    /// Those not sent yet are left out.
    pub(crate) fn with_attachments(
        mut self,
        store: Arc<AttachmentStore>,
        extractor: Arc<DocumentExtractor>,
        attachments: Vec<Attachment>,
    ) -> Self {
        self.attachments = ChatAttachments {
            store: Some(store),
            extractor: Some(extractor),
            sent: attachments
                .into_iter()
                .filter(|attachment| attachment.number.is_some())
                .collect(),
        };
        self
    }

    pub(crate) fn repositories(&self) -> &[ToolRepository] {
        &self.repositories
    }

    /// Whether the model gets [`CHANGE_FILE`] and [`MOVE_FILES`]: there is a repository it can
    /// propose commits to.
    fn can_change_files(&self) -> bool {
        self.repositories.iter().any(|r| r.can_commit)
    }

    /// Whether the model gets [`SAVE_ATTACHMENT`]: there are attachments and a repository it
    /// can propose commits to.
    pub(crate) fn can_save_attachments(&self) -> bool {
        self.can_read_attachments() && self.can_change_files()
    }

    /// Whether the model gets [`READ_ATTACHMENT`]: there are attachments, with or without
    /// repositories.
    fn can_read_attachments(&self) -> bool {
        !self.attachments.sent.is_empty()
    }

    /// What happens to a proposed commit, for the descriptions of the tools that propose them.
    fn proposal_outcome(&self) -> &'static str {
        if self.auto_commit {
            "The proposal appears below your answer and is committed automatically once your \
            answer is complete."
        } else {
            "Nothing is committed yet: the proposal appears below your answer, and the user \
            decides whether to commit it."
        }
    }

    pub(crate) fn definitions(&self) -> Vec<ToolDefinition> {
        let mut definitions = Vec::new();
        if !self.repositories.is_empty() {
            definitions.extend([
                list_files::definition(self),
                read_file::definition(self),
                grep::definition(self),
                outline::definition(self),
                present_file::definition(self),
            ]);
            if self.can_change_files() {
                definitions.push(change_file::definition(self));
                definitions.push(move_files::definition(self));
            }
            if self.can_save_attachments() {
                definitions.push(save_attachment::definition(self));
            }
        }
        if self.can_read_attachments() {
            definitions.push(read_attachment::definition(self));
        }
        definitions.push(run_script::definition(self));
        definitions
    }

    /// Validates a tool call of the model. An error is the result to send back, the call
    /// should still be recorded as a failed tool call.
    pub(crate) fn parse(&self, tool_use: &ToolUse) -> Result<Invocation<'_>, String> {
        if let Value::String(raw) = &tool_use.input {
            return Err(format!("The arguments are not valid JSON: {raw}"));
        }
        let input = &tool_use.input;
        let (repository, call) = match tool_use.name.as_str() {
            LIST_FILES => list_files::parse(input)?,
            READ_FILE => read_file::parse(input)?,
            GREP => grep::parse(input)?,
            OUTLINE => outline::parse(input)?,
            PRESENT_FILE => present_file::parse(input)?,
            CHANGE_FILE if self.can_change_files() => change_file::parse(input)?,
            MOVE_FILES if self.can_change_files() => move_files::parse(input)?,
            SAVE_ATTACHMENT if self.can_save_attachments() => save_attachment::parse(input)?,
            READ_ATTACHMENT if self.can_read_attachments() => read_attachment::parse(input)?,
            RUN_SCRIPT => run_script::parse(input)?,
            name => return Err(format!("There is no tool named `{name}`.")),
        };
        let repository = match call {
            Call::ReadAttachment(_) => None,
            Call::RunScript(ref args) if !args.reads_files() => None,
            _ => Some(self.repository(repository.as_deref())?),
        };
        if let Some(repository) = repository
            && matches!(
                call,
                Call::ChangeFile(_) | Call::MoveFiles(_) | Call::SaveAttachment(_)
            )
            && !repository.can_commit
        {
            return Err(format!(
                "You can't change `{}`, the user did not allow it.",
                repository.name
            ));
        }
        Ok(Invocation {
            repository,
            db: &self.db,
            identities: &self.identities,
            attachments: &self.attachments,
            auto_commit: self.auto_commit,
            call,
        })
    }

    /// Optional while there is only one repository, since it is unambiguous.
    fn repository(&self, name: Option<&str>) -> Result<&ToolRepository, String> {
        let available = || {
            self.repositories
                .iter()
                .map(|r| format!("`{}`", r.name))
                .collect::<Vec<_>>()
                .join(", ")
        };
        match name.map(str::trim) {
            Some(name) => {
                let lower = name.to_lowercase();
                self.repositories
                    .iter()
                    .find(|r| r.name.to_lowercase() == lower)
                    .ok_or_else(|| {
                        format!(
                            "Unknown repository `{name}`. Available repositories: {}.",
                            available()
                        )
                    })
            }
            None if self.repositories.len() == 1 => Ok(&self.repositories[0]),
            None if self.repositories.is_empty() => {
                Err("No repositories are available in this chat.".to_string())
            }
            None => Err(format!(
                "`repository` is required. Available repositories: {}.",
                available()
            )),
        }
    }
}

impl Invocation<'_> {
    /// The repository the call reads, to record with the tool call, `None` for the tools bound
    /// to no repository.
    pub(crate) fn repository(&self) -> Option<&ToolRepository> {
        self.repository
    }

    /// The repository of a tool that reads one, which [`RepositoryTools::parse`] resolved.
    fn target(&self) -> Result<&ToolRepository, ToolError> {
        self.repository.ok_or_else(|| {
            AppError::InternalServerError("A repository tool without its repository".to_string())
                .into()
        })
    }

    pub(crate) async fn run(&self) -> ToolOutput {
        let result = match &self.call {
            Call::ListFiles(args) => list_files::run(self, args).await,
            Call::ReadFile(args) => read_file::run(self, args).await,
            Call::Grep(args) => grep::run(self, args).await,
            Call::Outline(args) => outline::run(self, args).await,
            Call::PresentFile(args) => present_file::run(self, args).await,
            Call::ChangeFile(args) => return self.proposal(change_file::run(self, args).await),
            Call::MoveFiles(args) => return self.proposal(move_files::run(self, args).await),
            Call::SaveAttachment(args) => {
                return self.proposal(save_attachment::run(self, args).await);
            }
            Call::ReadAttachment(args) => read_attachment::run(self, args).await,
            Call::RunScript(args) => run_script::run(self, args).await,
        };
        match result {
            Ok(content) => ToolOutput {
                content,
                is_error: false,
                change: None,
            },
            Err(e) => self.error_output(e),
        }
    }

    /// What happens to the commit the call proposed, for its output.
    fn proposal_outcome(&self) -> &'static str {
        if self.auto_commit {
            "It appears below your answer and is committed automatically once your answer is \
            complete."
        } else {
            "It is not committed yet: the user sees it below your answer and decides whether to \
            commit it."
        }
    }

    /// The output of a call that proposes a commit, which is stored with the call.
    fn proposal(&self, result: Result<(String, ProposedChange), ToolError>) -> ToolOutput {
        match result {
            Ok((content, change)) => ToolOutput {
                content,
                is_error: false,
                change: Some(change),
            },
            Err(e) => self.error_output(e),
        }
    }

    fn error_output(&self, error: ToolError) -> ToolOutput {
        match error {
            ToolError::Invalid(content) => ToolOutput::error(content),
            ToolError::Internal(e) => {
                match self.repository {
                    Some(repository) => {
                        tracing::error!("Tool call on repository {} failed: {e}", repository.id)
                    }
                    None => tracing::error!("Tool call failed: {e}"),
                }
                ToolOutput::error("The tool failed because of an internal error.".to_string())
            }
        }
    }
}

/// How an attachment appears in the user's message, so the model can refer to it.
pub(crate) fn describe_attachment(attachment: &Attachment) -> String {
    format!(
        "[The user attached a file: attachment {}, `{}` ({}, {}). Read it with {READ_ATTACHMENT}.]",
        attachment.number.unwrap_or_default(),
        attachment.file_name,
        attachment.content_type,
        format_size(attachment.size.max(0) as u64)
    )
}

/// A pool that never connects, for tests of tools that do not read documents.
#[cfg(test)]
pub(crate) fn unused_db() -> DatabasePool {
    // Without them the pool spawns no maintenance tasks, which would need a runtime.
    sqlx::sqlite::SqlitePoolOptions::new()
        .max_lifetime(None)
        .idle_timeout(None)
        .connect_lazy("sqlite::memory:")
        .unwrap()
}

/// An in-memory database with the schema, for tests of tools that read documents.
#[cfg(test)]
pub(crate) fn test_db() -> DatabasePool {
    // One connection that is never closed, since each one has its own in-memory database.
    sqlx::sqlite::SqlitePoolOptions::new()
        .max_connections(1)
        .max_lifetime(None)
        .idle_timeout(None)
        .after_connect(|connection, _| {
            Box::pin(async move {
                crate::config::init::MIGRATOR
                    .run_direct(connection)
                    .await
                    .map_err(|e| sqlx::Error::Migrate(Box::new(e)))
            })
        })
        .connect_lazy("sqlite::memory:")
        .unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::path::PathBuf;
    use support::fixture::{docs, identities};

    #[tokio::test]
    async fn validates_calls() {
        let fixture = docs();
        assert_eq!(
            fixture
                .error(READ_FILE, json!({"repository": "other", "path": "a"}))
                .await,
            "Unknown repository `other`. Available repositories: `docs`."
        );
        assert_eq!(
            fixture
                .error(READ_FILE, json!({"repository": "docs"}))
                .await,
            "Invalid arguments for read_file: missing field `path`"
        );
        assert_eq!(
            fixture
                .error(READ_FILE, Value::String("{\"path\":".to_string()))
                .await,
            "The arguments are not valid JSON: {\"path\":"
        );
        assert_eq!(
            fixture.error("write_file", json!({})).await,
            "There is no tool named `write_file`."
        );
        // Case-insensitive, like repository names.
        fixture
            .ok(
                READ_FILE,
                json!({"repository": "DOCS", "path": "README.md"}),
            )
            .await;
    }

    #[test]
    fn disambiguates_names() {
        let repository = |name: &str| ToolRepository {
            id: Uuid::now_v7(),
            name: name.to_string(),
            snapshot: Snapshot::at(PathBuf::new(), String::new()),
            can_commit: false,
        };
        let tools = RepositoryTools::new(
            vec![repository("Docs"), repository("docs"), repository("api")],
            unused_db(),
            identities(),
        );
        let names: Vec<&str> = tools
            .repositories()
            .iter()
            .map(|r| r.name.as_str())
            .collect();
        assert_eq!(names, ["Docs", "docs (2)", "api"]);
        assert!(
            tools
                .parse(&ToolUse {
                    id: String::new(),
                    name: LIST_FILES.to_string(),
                    input: json!({}),
                    native: None,
                })
                .is_err()
        );
        assert_eq!(tools.definitions().len(), 6);
        // Only the tools bound to no repository.
        let names: Vec<String> = RepositoryTools::new(Vec::new(), unused_db(), identities())
            .definitions()
            .into_iter()
            .map(|d| d.name)
            .collect();
        assert_eq!(names, [RUN_SCRIPT]);
    }

    #[test]
    fn offers_changes_only_where_allowed() {
        let repository = |name: &str, can_commit: bool| ToolRepository {
            id: Uuid::now_v7(),
            name: name.to_string(),
            snapshot: Snapshot::at(PathBuf::new(), String::new()),
            can_commit,
        };
        let call = |repository: &str| ToolUse {
            id: String::new(),
            name: CHANGE_FILE.to_string(),
            input: json!({"repository": repository, "path": "a.md", "message": "m", "delete": true}),
            native: None,
        };
        let read_only =
            RepositoryTools::new(vec![repository("docs", false)], unused_db(), identities());
        assert_eq!(read_only.definitions().len(), 6);
        assert_eq!(
            read_only.parse(&call("docs")).err().unwrap(),
            "There is no tool named `change_file`."
        );

        let mixed = RepositoryTools::new(
            vec![repository("docs", false), repository("wiki", true)],
            unused_db(),
            identities(),
        );
        let definitions = mixed.definitions();
        assert_eq!(definitions.len(), 8);
        assert_eq!(
            definitions[5].input_schema["properties"]["repository"]["enum"],
            json!(["wiki"])
        );
        assert_eq!(
            mixed.parse(&call("docs")).err().unwrap(),
            "You can't change `docs`, the user did not allow it."
        );
        assert!(mixed.parse(&call("wiki")).is_ok());

        let manual = &definitions[5].description;
        assert!(manual.contains("the user decides whether to commit it"));
        let auto_commit = mixed.with_auto_commit(true).definitions();
        for definition in &auto_commit[5..7] {
            assert!(
                definition
                    .description
                    .contains("is committed automatically once your answer is complete"),
                "{}",
                definition.name
            );
            assert!(!definition.description.contains("Nothing is committed yet"));
        }
    }
}
