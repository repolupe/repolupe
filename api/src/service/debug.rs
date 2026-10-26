use crate::config::error::AppError;
use crate::config::state::AppState;
use crate::repository;
use crate::repository::debug::{DummyChat, DummyMessage};
use chrono::{Duration, Utc};
use rand::seq::IndexedRandom;
use rand::{Rng, RngExt};
use uuid::Uuid;

const DUMMY_CHAT_COUNT: usize = 200;
const MAX_EXCHANGES: usize = 8;
/// Chats start at most this long ago.
const MAX_AGE_DAYS: i64 = 90;

const WORDS: [&str; 32] = [
    "repository",
    "branch",
    "commit",
    "function",
    "module",
    "error",
    "config",
    "server",
    "client",
    "request",
    "response",
    "token",
    "database",
    "query",
    "index",
    "cache",
    "file",
    "test",
    "build",
    "deploy",
    "the",
    "a",
    "is",
    "how",
    "why",
    "where",
    "does",
    "with",
    "from",
    "into",
    "fast",
    "broken",
];

/// Creates [`DUMMY_CHAT_COUNT`] chats with random words, each for a random user. Each chat uses
/// a random model and either no repository, all of the user's, or a single one, all equally
/// likely. Returns the number of chats.
pub(crate) async fn create_dummy_chats(state: &AppState) -> Result<usize, AppError> {
    let user_ids = repository::user::list_users(&state.db)
        .await?
        .into_iter()
        .map(|u| u.id)
        .collect::<Vec<_>>();
    if user_ids.is_empty() {
        return Err(AppError::BadRequest(
            "There are no users to create chats for".to_string(),
        ));
    }
    let model_ids = repository::llm::list_available_models(&state.db)
        .await?
        .into_iter()
        .map(|m| m.id)
        .collect::<Vec<_>>();
    // The repositories each user can read, owned or shared
    let mut users = Vec::with_capacity(user_ids.len());
    for user_id in user_ids {
        let repository_ids = repository::repository::list_repositories(&state.db, user_id)
            .await?
            .into_iter()
            .map(|r| r.id)
            .collect::<Vec<_>>();
        users.push((user_id, repository_ids));
    }

    let chats = (0..DUMMY_CHAT_COUNT)
        .map(|_| {
            let rng = &mut rand::rng();
            let (user_id, repository_ids) = users.choose(rng).unwrap();
            dummy_chat(rng, *user_id, &model_ids, repository_ids)
        })
        .collect::<Vec<_>>();
    repository::debug::insert_dummy_chats(&state.db, &chats).await?;
    Ok(chats.len())
}

fn dummy_chat(
    rng: &mut impl Rng,
    user_id: Uuid,
    model_ids: &[Uuid],
    repository_ids: &[Uuid],
) -> DummyChat {
    let model_id = model_ids.choose(rng).copied();
    // 0 is no repository, 1 all of them, the rest a single one
    let (all_repositories, repository_id) = match rng.random_range(0..repository_ids.len() + 2) {
        0 => (false, None),
        1 => (true, None),
        i => (false, Some(repository_ids[i - 2])),
    };

    let mut time = Utc::now() - Duration::seconds(rng.random_range(0..MAX_AGE_DAYS * 24 * 3600));
    let created_at = time;
    let mut messages = Vec::new();
    for _ in 0..rng.random_range(1..=MAX_EXCHANGES) {
        // Both messages of an exchange share `created_at`, like real ones
        let finished_at = time + Duration::seconds(rng.random_range(2..120));
        messages.push(DummyMessage {
            id: Uuid::now_v7(),
            is_user: true,
            content: random_text(rng, 3, 30),
            model_id: None,
            created_at: time,
            finished_at: None,
        });
        messages.push(DummyMessage {
            id: Uuid::now_v7(),
            is_user: false,
            content: random_paragraphs(rng),
            model_id,
            created_at: time,
            finished_at: Some(finished_at),
        });
        time = finished_at + Duration::seconds(rng.random_range(10..3600));
    }

    DummyChat {
        id: Uuid::now_v7(),
        user_id,
        title: capitalize(&random_text(rng, 2, 6)),
        all_repositories,
        repository_id,
        model_id,
        created_at,
        updated_at: messages.last().map_or(created_at, |m| m.created_at),
        messages,
    }
}

fn random_paragraphs(rng: &mut impl Rng) -> String {
    (0..rng.random_range(1..=4))
        .map(|_| capitalize(&random_text(rng, 10, 60)) + ".")
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn random_text(rng: &mut impl Rng, min_words: usize, max_words: usize) -> String {
    (0..rng.random_range(min_words..=max_words))
        .map(|_| *WORDS.choose(rng).unwrap())
        .collect::<Vec<_>>()
        .join(" ")
}

fn capitalize(text: &str) -> String {
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}
