//! Generates an answer with the LLM: the chat so far as history, the repositories in
//! scope as tools, and the loop that runs the tools the model asks for.

use crate::config::state::AppState;
use crate::dto::chat::MessageRole;
use crate::dto::chat::MessageStatus;
use crate::model::attachment::Attachment;
use crate::model::message::Message;
use crate::model::repository::ScopedRepository;
use crate::model::tool_call::{ChangedPaths, ProposedChange};
use crate::model::user::UserProfile;
use crate::repository;
use crate::service::commit;
use crate::service::generation::{Generation, GenerationError, PARAGRAPH_BREAK};
use crate::service::llm::{
    ChatMessage, ContentBlock, LlmConfig, LlmError, LlmEvent, LlmRequest, LlmResponse, Role,
    StopReason, ToolUse,
};
use crate::service::tools::{
    CHANGE_FILE, CommitIdentities, MOVE_FILES, PRESENT_FILE, RepositoryTools, SAVE_ATTACHMENT,
    ToolOutput, ToolRepository, describe_attachment,
};
use chrono::{DateTime, FixedOffset, Offset, Utc};
use futures_util::StreamExt;
use futures_util::future::join_all;
use std::fmt::Write;
use uuid::Uuid;

/// Model responses with tool calls per answer. The last one gets errors instead of results,
/// so the model answers with what it found so far.
const MAX_TOOL_ROUNDS: usize = 25;

const TOOL_LIMIT_REACHED: &str =
    "The limit of tool calls for this answer is reached. Answer with what you found so far.";

/// Appended to answers in the history that did not finish.
const INTERRUPTED_NOTE: &str = "[This answer was interrupted.]";

/// Generates the answer of `generation`. Stops as soon as the generation is cancelled, which
/// aborts the LLM request and running tools.
pub(crate) async fn generate(
    state: &AppState,
    generation: &Generation,
    llm: &LlmConfig,
) -> Result<(), GenerationError> {
    tokio::select! {
        _ = generation.cancelled() => Err(GenerationError::Stopped),
        result = run(state, generation, llm) => result,
    }
}

async fn run(
    state: &AppState,
    generation: &Generation,
    llm: &LlmConfig,
) -> Result<(), GenerationError> {
    let history = repository::message::list_messages(&state.db, generation.chat_id).await?;
    let attachments =
        repository::attachment::list_chat_attachments(&state.db, generation.chat_id).await?;
    let mut messages = history_messages(
        &history,
        &attachments,
        generation.message_id,
        generation.client.utc_offset,
    );
    if messages.last().map(|m| m.role) != Some(Role::User) {
        tracing::error!(
            "History of message {} does not end with a question",
            generation.message_id
        );
        return Err(GenerationError::Failed(
            "There is no question to answer".to_string(),
        ));
    }

    let scoped =
        repository::repository::list_scoped_repositories(&state.db, generation.chat_id).await?;
    let user = repository::user::get_user(&state.db, generation.user_id)
        .await?
        .ok_or_else(|| GenerationError::Failed("The user no longer exists".to_string()))?;
    let mut profile = repository::user::get_user_profile(&state.db, generation.user_id)
        .await?
        .unwrap_or_default();
    profile.locale = profile.locale.or_else(|| generation.client.locale.clone());
    let tools = RepositoryTools::new(
        scoped
            .iter()
            .filter_map(|repository| {
                Some(ToolRepository {
                    id: repository.id,
                    name: repository.name.clone(),
                    snapshot: state
                        .mirrors
                        .snapshot(repository.id, repository.head_commit_sha.clone()?),
                    can_commit: repository.can_commit,
                })
            })
            .collect(),
        state.db.clone(),
        CommitIdentities::new(&llm.model, user.user_name, user.email),
    )
    .with_attachments(
        state.attachments.clone(),
        state.extractor.clone(),
        attachments,
    )
    .with_auto_commit(profile.auto_commit);
    let system = system_prompt(&profile, generation.client.utc_offset, &scoped, &tools);
    let definitions = tools.definitions();

    // Whether the text of the next response starts a new paragraph.
    let mut new_paragraph = false;
    let mut proposals = Proposals::default();
    for round in 1.. {
        let request = LlmRequest {
            system: &system,
            messages: &messages,
            tools: &definitions,
        };
        let response = stream_response(state, generation, llm, &request, new_paragraph).await?;
        generation.add_usage(&response.usage)?;

        let tool_uses: Vec<ToolUse> = response.tool_uses().cloned().collect();
        match response.stop_reason {
            StopReason::ToolUse if !tool_uses.is_empty() => {}
            StopReason::ToolUse => {
                // The answer so far stands, but a call the model meant to make is lost.
                tracing::warn!(
                    "Message {} stopped for tool use without tool calls",
                    generation.message_id
                );
                break;
            }
            StopReason::EndTurn => break,
            StopReason::MaxTokens => {
                return Err(GenerationError::Failed(
                    "The answer was cut off because it reached the maximum length".to_string(),
                ));
            }
            StopReason::Refusal => {
                return Err(GenerationError::Failed(
                    "The language model declined to answer".to_string(),
                ));
            }
            StopReason::Other(reason) => {
                tracing::warn!(
                    "Message {} stopped with reason {reason}",
                    generation.message_id
                );
                return Err(GenerationError::Failed(format!(
                    "The language model stopped unexpectedly ({reason})"
                )));
            }
        }
        // The text before tool calls that look things up is usually a preamble like "Let me
        // look", so the answer is only the text after the last of them. The preambles stay
        // visible while generating and are dropped when the message is finished, and the
        // model still sees them in `messages`. Presenting files and proposing changes looks
        // nothing up, so the text with them is kept, it may already be the answer.
        if tool_uses.iter().any(|tool_use| {
            ![PRESENT_FILE, CHANGE_FILE, MOVE_FILES, SAVE_ATTACHMENT]
                .contains(&tool_use.name.as_str())
        }) {
            generation.mark_preamble()?;
        }
        new_paragraph = true;
        if round > MAX_TOOL_ROUNDS {
            return Err(GenerationError::Failed(
                "The answer needed too many tool calls".to_string(),
            ));
        }

        let results = if round == MAX_TOOL_ROUNDS {
            tool_uses
                .iter()
                .map(|tool_use| tool_result(tool_use, TOOL_LIMIT_REACHED.to_string(), true))
                .collect()
        } else {
            run_tools(state, generation, &tools, &tool_uses, &mut proposals).await?
        };
        messages.push(ChatMessage {
            role: Role::Assistant,
            content: response.content,
        });
        messages.push(ChatMessage {
            role: Role::User,
            content: results,
        });
    }

    if profile.auto_commit {
        commit_proposals(state, generation, user.can_manage_repositories, &proposals).await;
    }
    Ok(())
}

/// The changes proposed in an answer, in the order the user sees them. Like in the frontend, a
/// later call for the same file, the same attachment, or moves in the same repository replaces
/// an earlier one.
#[derive(Default)]
struct Proposals(Vec<(String, Uuid)>);

impl Proposals {
    fn add(&mut self, tool_use: &ToolUse, repository_id: Uuid, change: &ProposedChange, id: Uuid) {
        let key = match &change.changed {
            _ if tool_use.name == SAVE_ATTACHMENT => {
                format!("attachment:{}", tool_use.input["attachment"])
            }
            ChangedPaths::Moves(_) => format!("{repository_id}:moves"),
            ChangedPaths::File(path) => format!("{repository_id}:{path}"),
        };
        self.0.retain(|(k, _)| *k != key);
        self.0.push((key, id));
    }
}

/// Commits the proposed changes for a user who turned on `auto_commit`, one after the other,
/// since each one moves the branch the next is pushed to. A change that fails is stored as
/// `CONFLICT` or `FAILED`, like when the user commits it, so they can retry it.
async fn commit_proposals(
    state: &AppState,
    generation: &Generation,
    can_manage_repositories: bool,
    proposals: &Proposals,
) {
    for (_, tool_call_id) in &proposals.0 {
        let result = commit::commit(
            state,
            generation.user_id,
            can_manage_repositories,
            generation.chat_id,
            *tool_call_id,
        )
        .await;
        if let Err(e) = result {
            tracing::warn!("Failed to commit the change of tool call {tool_call_id}: {e}");
        }
    }
}

/// Streams one response and forwards its text, starting a new paragraph if `new_paragraph`.
async fn stream_response(
    state: &AppState,
    generation: &Generation,
    llm: &LlmConfig,
    request: &LlmRequest<'_>,
    mut new_paragraph: bool,
) -> Result<LlmResponse, GenerationError> {
    let stream = state.llm.stream(llm, request);
    tokio::pin!(stream);
    while let Some(event) = stream.next().await {
        match event.map_err(llm_failed)? {
            LlmEvent::TextDelta(text) if text.is_empty() => {}
            LlmEvent::TextDelta(text) => {
                if std::mem::take(&mut new_paragraph) && generation.has_content() {
                    generation.append_content(PARAGRAPH_BREAK)?;
                }
                generation.append_content(&text)?
            }
            LlmEvent::Done(response) => return Ok(response),
        }
    }
    Err(GenerationError::Failed(
        "The response of the language model ended unexpectedly".to_string(),
    ))
}

/// Records the calls in the order the model requested them and runs them at the same time.
async fn run_tools(
    state: &AppState,
    generation: &Generation,
    tools: &RepositoryTools,
    tool_uses: &[ToolUse],
    proposals: &mut Proposals,
) -> Result<Vec<ContentBlock>, GenerationError> {
    let mut calls = Vec::with_capacity(tool_uses.len());
    for tool_use in tool_uses {
        let invocation = tools.parse(tool_use);
        let repository = invocation.as_ref().ok().and_then(|i| i.repository());
        let repository_id = repository.map(|r| r.id);
        let id = generation
            .start_tool_call(
                &state.db,
                &tool_use.name,
                tool_use.input.clone(),
                repository_id,
                repository.map(|r| r.snapshot.commit()),
            )
            .await?;
        calls.push((id, tool_use, repository_id, invocation));
    }

    let outputs = join_all(calls.iter().map(|(_, _, _, invocation)| async move {
        match invocation {
            Ok(invocation) => invocation.run().await,
            Err(message) => ToolOutput::error(message.clone()),
        }
    }))
    .await;

    let mut results = Vec::with_capacity(calls.len());
    for ((id, tool_use, repository_id, _), output) in calls.iter().zip(outputs) {
        generation
            .finish_tool_call(
                &state.db,
                *id,
                &output.content,
                output.is_error,
                output.change.as_ref(),
            )
            .await?;
        if let (Some(change), Some(repository_id)) = (&output.change, repository_id) {
            proposals.add(tool_use, *repository_id, change, *id);
        }
        results.push(tool_result(tool_use, output.content, output.is_error));
    }
    Ok(results)
}

fn tool_result(tool_use: &ToolUse, content: String, is_error: bool) -> ContentBlock {
    ContentBlock::ToolResult {
        tool_use_id: tool_use.id.clone(),
        content,
        is_error,
    }
}

/// The messages before `answer_id` as text, with the attachments the user sent described in
/// their messages and the user's messages starting with when they were sent. Earlier tool calls
/// are left out, so the model looks things up again if it needs them. Consecutive messages of
/// the same role are merged, e.g. around a failed answer without content.
///
/// The time is the user's local time, so the model knows the current date and time. It is in
/// the messages rather than the system prompt, which would change with every question and
/// invalidate the cached history.
fn history_messages(
    messages: &[Message],
    attachments: &[Attachment],
    answer_id: Uuid,
    utc_offset: Option<FixedOffset>,
) -> Vec<ChatMessage> {
    let mut history: Vec<ChatMessage> = Vec::new();
    for message in messages.iter().take_while(|m| m.id != answer_id) {
        let (role, text) = match (message.role, message.status) {
            (MessageRole::User, _) => {
                let attachment = attachments
                    .iter()
                    .find(|a| a.message_id == Some(message.id));
                let text = match attachment {
                    Some(attachment) if message.content.trim().is_empty() => {
                        describe_attachment(attachment)
                    }
                    Some(attachment) => {
                        format!("{}\n\n{}", message.content, describe_attachment(attachment))
                    }
                    None => message.content.clone(),
                };
                if text.trim().is_empty() {
                    continue;
                }
                let sent_at = sent_at(message.created_at, utc_offset);
                (Role::User, format!("{sent_at}\n{text}"))
            }
            (MessageRole::Assistant, MessageStatus::Completed) => {
                (Role::Assistant, message.content.clone())
            }
            (MessageRole::Assistant, MessageStatus::Failed | MessageStatus::Cancelled)
                if !message.content.trim().is_empty() =>
            {
                (
                    Role::Assistant,
                    format!("{}\n\n{INTERRUPTED_NOTE}", message.content),
                )
            }
            _ => continue,
        };
        if text.trim().is_empty() {
            continue;
        }
        match history.last_mut() {
            Some(last) if last.role == role => last.content.push(ContentBlock::Text(text)),
            _ => history.push(ChatMessage {
                role,
                content: vec![ContentBlock::Text(text)],
            }),
        }
    }
    history
}

/// Like `[Tuesday, 2026-10-27 14:32]`, in the user's time zone.
fn sent_at(created_at: DateTime<Utc>, utc_offset: Option<FixedOffset>) -> String {
    let offset = utc_offset.unwrap_or_else(|| Utc.fix());
    created_at
        .with_timezone(&offset)
        .format("[%A, %Y-%m-%d %H:%M]")
        .to_string()
}

/// Stays the same during the tool loop, so it can be cached.
fn system_prompt(
    profile: &UserProfile,
    utc_offset: Option<FixedOffset>,
    scoped: &[ScopedRepository],
    tools: &RepositoryTools,
) -> String {
    let language = answer_language(profile);
    if scoped.is_empty() {
        let mut prompt = String::from("You are a helpful assistant.\n\n");
        push_user_section(&mut prompt, profile, false);
        push_time_section(&mut prompt, utc_offset);
        let _ = writeln!(
            prompt,
            "For calculations, e.g. totals, percentages or date differences, run a script with \
            run_script instead of working them out in your head. The user does not see your \
            tool calls, so present the result in plain words.\n\n\
            {language}, and format it with Markdown."
        );
        return prompt;
    }

    let mut prompt = String::from("You answer questions about the user's Git repositories.\n\n");
    push_user_section(&mut prompt, profile, true);
    push_time_section(&mut prompt, utc_offset);

    prompt.push_str("Repositories you can read:\n");
    for repository in tools.repositories() {
        let Some(scoped) = scoped.iter().find(|s| s.id == repository.id) else {
            continue;
        };
        let commit = repository.snapshot.commit();
        let commit = &commit[..commit.len().min(12)];
        let _ = write!(
            prompt,
            "- `{}` (branch `{}`, commit {commit}{})",
            repository.name,
            scoped.branch,
            if repository.can_commit {
                ", you can propose changes"
            } else {
                ""
            }
        );
        if let Some(description) = scoped.description.as_deref().map(str::trim)
            && !description.is_empty()
        {
            let _ = write!(prompt, ": {}", description.replace('\n', " "));
        }
        prompt.push('\n');
    }
    let unsynced: Vec<String> = scoped
        .iter()
        .filter(|s| s.head_commit_sha.is_none())
        .map(|s| format!("`{}`", s.name))
        .collect();
    if !unsynced.is_empty() {
        let _ = writeln!(
            prompt,
            "Not available yet, since they were not synced: {}.",
            unsynced.join(", ")
        );
    }
    if tools.repositories().is_empty() {
        let _ = writeln!(
            prompt,
            "\nNone of the repositories can be read yet, so you cannot look anything up. Tell \
            the user to wait for the sync to finish. {language}."
        );
        return prompt;
    }

    let _ = writeln!(
        prompt,
        "\nHow to answer:\n\
        - Look things up with the tools instead of answering from memory. Search for the terms \
        of the question with grep, which also searches the text converted from PDFs, or get an \
        overview with list_files. For long Markdown files, use outline and read only the \
        relevant sections with read_file. Read PDFs with read_file.\n\
        - Base your answer on what you read. If the repositories do not cover the question, \
        say so instead of guessing.\n\
        - Name the files your answer is based on, e.g. `docs/setup.md`, with the repository if \
        there are several.\n\
        - When the user wants to see a file, or a file is what they are looking for, show it with \
        present_file_to_user instead of copying its content into the answer.\n\
        - For calculations, e.g. totals, percentages or date differences, run a script with \
        run_script instead of working them out in your head, and pass it the files with the \
        data.\n\
        - The user may not be technical and does not see your tool calls. Describe what you \
        looked at in plain words, e.g. \"I searched all files\", without naming the tools or \
        terms like grep, regular expression, Markdown or OCR."
    );
    if tools.repositories().iter().any(|r| r.can_commit) {
        prompt.push_str(
            "- Only when the user asks you to change, fix or add something in a repository you \
            can propose changes to, read the files concerned, then propose the changes with \
            change_file, one call per file. To move or rename files or folders, use \
            move_files, with all moves in one call. ",
        );
        prompt.push_str(if profile.auto_commit {
            "They appear below your answer as commits, which are committed automatically once \
            your answer is complete. Summarize what you changed.\n"
        } else {
            "They appear below your answer as proposed commits, which the user reviews and \
            commits, so don't say they are committed. Summarize what you changed.\n"
        });
    }
    if tools.can_save_attachments() {
        let _ = writeln!(
            prompt,
            "- When the user attaches a file, they usually want it stored in a repository you \
            can propose changes to. Once you know where it belongs, call save_attachment, \
            before you write your answer. If it remains unclear, don't call it, but ask the \
            user and suggest the likely places. Only say that you {} the file after \
            save_attachment succeeded.",
            if profile.auto_commit {
                "stored"
            } else {
                "proposed storing"
            }
        );
    }
    let _ = writeln!(prompt, "- {language}, and format it with Markdown.");
    prompt
}

/// Who "I" and "my" in the questions are, since repositories can be shared by several people.
fn push_user_section(prompt: &mut String, profile: &UserProfile, with_repositories: bool) {
    if profile.full_name.is_none() && profile.about.is_none() {
        return;
    }
    match &profile.full_name {
        Some(full_name) => {
            let _ = writeln!(prompt, "The user asking is {full_name}.");
        }
        None => prompt.push_str("About the user asking:\n"),
    }
    if let Some(about) = &profile.about {
        let _ = writeln!(
            prompt,
            "What the user says about themselves:\n<about_user>\n{about}\n</about_user>"
        );
    }
    prompt.push_str("\"I\", \"me\" and \"my\" in the questions refer to this user.");
    if with_repositories {
        prompt.push_str(
            " The repositories may contain information about several people: answer with the \
            information about this user, and if it is unclear whom something belongs to, say so \
            instead of guessing.",
        );
    }
    prompt.push_str("\n\n");
}

fn push_time_section(prompt: &mut String, utc_offset: Option<FixedOffset>) {
    let time_zone = match utc_offset {
        Some(offset) => format!("the user's local time (UTC{offset})"),
        None => "UTC, since the user's time zone is unknown".to_string(),
    };
    let _ = writeln!(
        prompt,
        "The user's messages start with the date and time they were sent, in {time_zone}. The \
        last one is the current date and time.\n"
    );
}

/// The question's language comes first, the locale only decides when it is unclear.
fn answer_language(profile: &UserProfile) -> String {
    match &profile.locale {
        Some(locale) => format!(
            "Answer in the language of the question, or in the language of the locale \
            `{locale}` if that is unclear"
        ),
        None => "Answer in the language of the question".to_string(),
    }
}

/// The message is shown to the user, details go to the logs.
fn llm_failed(error: LlmError) -> GenerationError {
    tracing::error!("LLM request failed: {error}");
    let message = match &error {
        LlmError::Status { message, .. } | LlmError::Stream { message, .. } => {
            format!("The language model returned an error: {message}")
        }
        LlmError::Http(_) => "The language model could not be reached".to_string(),
        LlmError::Request(_) => "The request to the language model is invalid".to_string(),
        LlmError::InvalidResponse(_) => "The language model sent an invalid response".to_string(),
    };
    GenerationError::Failed(message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::service::mirror::Snapshot;
    use chrono::Utc;
    use std::path::PathBuf;

    fn message(role: MessageRole, status: MessageStatus, content: &str) -> Message {
        Message {
            id: Uuid::now_v7(),
            role,
            content: content.to_string(),
            status,
            error: None,
            model_id: None,
            created_at: Utc::now(),
            finished_at: None,
            input_tokens: None,
            output_tokens: None,
            cache_read_tokens: None,
            cache_write_tokens: None,
            cost: None,
            cost_currency: None,
        }
    }

    fn texts(history: &[ChatMessage]) -> Vec<(Role, Vec<&str>)> {
        history
            .iter()
            .map(|m| {
                let texts = m
                    .content
                    .iter()
                    .map(|block| match block {
                        ContentBlock::Text(text) => text.as_str(),
                        _ => panic!("only text expected"),
                    })
                    .collect();
                (m.role, texts)
            })
            .collect()
    }

    #[test]
    fn builds_history_up_to_the_answer() {
        use MessageRole::{Assistant, User};
        use MessageStatus::{Cancelled, Completed, Failed, Generating};
        let answer = message(Assistant, Generating, "");
        let messages = vec![
            message(User, Completed, "First?"),
            message(Assistant, Completed, "First answer"),
            message(User, Completed, "Second?"),
            message(Assistant, Failed, ""),
            message(User, Completed, "Second again?"),
            message(Assistant, Cancelled, "Partial"),
            message(User, Completed, "Third?"),
            answer.clone(),
            message(User, Completed, "Later"),
        ];
        let sent_at = "2026-10-27T13:32:00Z".parse().unwrap();
        let messages: Vec<Message> = messages
            .into_iter()
            .map(|m| Message {
                created_at: sent_at,
                ..m
            })
            .collect();
        let history = history_messages(&messages, &[], answer.id, None);
        assert_eq!(
            texts(&history),
            vec![
                (Role::User, vec!["[Tuesday, 2026-10-27 13:32]\nFirst?"]),
                (Role::Assistant, vec!["First answer"]),
                (
                    Role::User,
                    vec![
                        "[Tuesday, 2026-10-27 13:32]\nSecond?",
                        "[Tuesday, 2026-10-27 13:32]\nSecond again?"
                    ]
                ),
                (
                    Role::Assistant,
                    vec!["Partial\n\n[This answer was interrupted.]"]
                ),
                (Role::User, vec!["[Tuesday, 2026-10-27 13:32]\nThird?"]),
            ]
        );
    }

    #[test]
    fn dates_messages_in_the_users_time_zone() {
        let question = Message {
            created_at: "2026-10-27T23:32:00Z".parse().unwrap(),
            ..message(MessageRole::User, MessageStatus::Completed, "Today?")
        };
        let answer = message(MessageRole::Assistant, MessageStatus::Generating, "");
        let messages = vec![question, answer.clone()];
        let offset = FixedOffset::east_opt(60 * 60);
        let history = history_messages(&messages, &[], answer.id, offset);
        assert_eq!(
            texts(&history),
            vec![(Role::User, vec!["[Wednesday, 2026-10-28 00:32]\nToday?"])]
        );

        let prompt = system_prompt(&UserProfile::default(), offset, &[], &tools_for(&[]));
        assert!(prompt.contains("in the user's local time (UTC+01:00)."));
        let prompt = system_prompt(&UserProfile::default(), None, &[], &tools_for(&[]));
        assert!(prompt.contains("in UTC, since the user's time zone is unknown."));
    }

    fn scoped(name: &str, head_commit_sha: Option<&str>) -> ScopedRepository {
        ScopedRepository {
            id: Uuid::now_v7(),
            name: name.to_string(),
            description: Some("Team\nhandbook".to_string()),
            branch: "main".to_string(),
            head_commit_sha: head_commit_sha.map(str::to_string),
            can_commit: false,
        }
    }

    fn tools_for(scoped: &[ScopedRepository]) -> RepositoryTools {
        RepositoryTools::new(
            scoped
                .iter()
                .filter_map(|s| {
                    Some(ToolRepository {
                        id: s.id,
                        name: s.name.clone(),
                        snapshot: Snapshot::at(PathBuf::new(), s.head_commit_sha.clone()?),
                        can_commit: s.can_commit,
                    })
                })
                .collect(),
            crate::service::tools::unused_db(),
            CommitIdentities::new("mock-model", "alice".to_string(), None),
        )
    }

    #[test]
    fn lists_repositories_in_the_system_prompt() {
        let scoped = vec![
            scoped("handbook", Some("0123456789abcdef0123")),
            scoped("wiki", None),
        ];
        let prompt = system_prompt(&UserProfile::default(), None, &scoped, &tools_for(&scoped));
        assert!(!prompt.contains("The user asking"));
        assert!(prompt.contains(
            "- `handbook` (branch `main`, commit 0123456789ab): Team handbook\n\
            Not available yet, since they were not synced: `wiki`.\n"
        ));
        assert!(prompt.contains("How to answer:"));
        assert!(!prompt.contains("change_file"));

        let writable = vec![ScopedRepository {
            can_commit: true,
            ..self::scoped("handbook", Some("0123456789abcdef0123"))
        }];
        let prompt = system_prompt(
            &UserProfile::default(),
            None,
            &writable,
            &tools_for(&writable),
        );
        assert!(prompt.contains(
            "- `handbook` (branch `main`, commit 0123456789ab, you can propose changes): Team \
            handbook\n"
        ));
        assert!(prompt.contains("propose the changes with change_file"));
        assert!(prompt.contains("which the user reviews and commits"));
        assert!(prompt.ends_with("and format it with Markdown.\n"));

        let auto_commit = UserProfile {
            auto_commit: true,
            ..UserProfile::default()
        };
        let prompt = system_prompt(&auto_commit, None, &writable, &tools_for(&writable));
        assert!(prompt.contains("committed automatically once your answer is complete"));
        assert!(!prompt.contains("which the user reviews and commits"));
    }

    #[test]
    fn handles_missing_repositories() {
        let profile = UserProfile::default();
        let prompt = system_prompt(&profile, None, &[], &tools_for(&[]));
        assert!(prompt.starts_with("You are a helpful assistant.\n\n"));
        assert!(!prompt.contains("repositor"));
        let unsynced = vec![scoped("wiki", None)];
        let prompt = system_prompt(&profile, None, &unsynced, &tools_for(&unsynced));
        assert!(prompt.contains("None of the repositories can be read yet"));
        assert!(!prompt.contains("How to answer:"));
    }

    #[test]
    fn describes_the_user_in_the_system_prompt() {
        let profile = UserProfile {
            full_name: Some("Alice Doe".to_string()),
            about: Some("Married to Bob Doe.\nMy documents are in /alice.".to_string()),
            locale: None,
            auto_commit: false,
        };
        let prompt = system_prompt(&profile, None, &[], &tools_for(&[]));
        assert!(prompt.contains(
            "The user asking is Alice Doe.\n\
            What the user says about themselves:\n\
            <about_user>\nMarried to Bob Doe.\nMy documents are in /alice.\n</about_user>\n\
            \"I\", \"me\" and \"my\" in the questions refer to this user."
        ));

        let profile = UserProfile {
            full_name: None,
            about: Some("I am the oldest daughter.".to_string()),
            locale: None,
            auto_commit: false,
        };
        let prompt = system_prompt(&profile, None, &[], &tools_for(&[]));
        assert!(prompt.contains("About the user asking:\nWhat the user says"));
    }

    #[test]
    fn falls_back_to_the_locale() {
        let readable = vec![scoped("handbook", Some("0123456789abcdef0123"))];
        let prompt = system_prompt(
            &UserProfile::default(),
            None,
            &readable,
            &tools_for(&readable),
        );
        assert!(
            prompt.ends_with(
                "- Answer in the language of the question, and format it with Markdown.\n"
            )
        );

        let profile = UserProfile {
            locale: Some("de-DE".to_string()),
            ..UserProfile::default()
        };
        let prompt = system_prompt(&profile, None, &readable, &tools_for(&readable));
        assert!(prompt.ends_with(
            "- Answer in the language of the question, or in the language of the locale `de-DE` \
            if that is unclear, and format it with Markdown.\n"
        ));
        assert!(!prompt.contains("The user asking"));
        let prompt = system_prompt(&profile, None, &[], &tools_for(&[]));
        assert!(prompt.ends_with(
            "Answer in the language of the question, or in the language of the locale `de-DE` \
            if that is unclear, and format it with Markdown.\n"
        ));
    }
}
