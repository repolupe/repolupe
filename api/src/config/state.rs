use crate::service::attachment::AttachmentStore;
use crate::service::extraction::DocumentExtractor;
use crate::service::generation::GenerationRegistry;
use crate::service::llm::LlmClient;
use crate::service::mirror::MirrorStore;
use crate::service::mistral_ocr::MistralOcr;
use crate::service::runtime_config::LiveConfig;
use crate::util::rate_limit::RateLimiter;
use crate::util::throttle::Throttle;
use crate::util::token_cipher::TokenCipher;
use chrono::TimeDelta;
use sqlx::{Pool, Sqlite};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::time::Duration;

pub type DatabasePool = Pool<Sqlite>;

/// Manual sync requests are accepted about once per repository per this interval.
const SYNC_REQUEST_INTERVAL: Duration = Duration::from_secs(60);

/// Password guesses allowed per account within [`PASSWORD_ATTEMPT_WINDOW`].
const MAX_PASSWORD_ATTEMPTS: u32 = 10;
const PASSWORD_ATTEMPT_WINDOW: Duration = Duration::from_mins(15);

#[derive(Clone)]
pub struct AppState {
    pub db: DatabasePool,
    pub token_cipher: Arc<TokenCipher>,
    pub llm: Arc<LlmClient>,
    /// The repositories cloned to `REPOS_DIR`.
    pub mirrors: Arc<MirrorStore>,
    /// The files users attached to chats, in `ATTACHMENTS_DIR`.
    pub attachments: Arc<AttachmentStore>,
    pub extractor: Arc<DocumentExtractor>,
    pub sync_throttle: Arc<Throttle>,
    /// Password guesses by lowercase user name (or the login given, if no user has it), for
    /// login and password changes.
    pub password_attempts: Arc<RateLimiter>,
    pub generations: Arc<GenerationRegistry>,
    /// See [`crate::Config::session_idle_timeout`].
    pub session_idle_timeout: Option<TimeDelta>,
    pub runtime_config: Arc<LiveConfig>,
    /// The config by environment variable, secrets masked, see `Config::to_env_map`.
    pub env: Arc<BTreeMap<String, Option<String>>>,
}

impl AppState {
    // Only called by `init`, with what it prepared.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        db: DatabasePool,
        token_cipher: TokenCipher,
        llm: LlmClient,
        mirrors: MirrorStore,
        attachments: AttachmentStore,
        mistral: Option<MistralOcr>,
        session_idle_timeout: Option<TimeDelta>,
        runtime_config: LiveConfig,
        env: BTreeMap<String, Option<String>>,
    ) -> Self {
        Self {
            db,
            token_cipher: Arc::new(token_cipher),
            llm: Arc::new(llm),
            mirrors: Arc::new(mirrors),
            attachments: Arc::new(attachments),
            extractor: Arc::new(DocumentExtractor::new(
                runtime_config.current().ocr().as_ref(),
                mistral,
            )),
            sync_throttle: Arc::new(Throttle::new(SYNC_REQUEST_INTERVAL)),
            password_attempts: Arc::new(RateLimiter::new(
                MAX_PASSWORD_ATTEMPTS,
                PASSWORD_ATTEMPT_WINDOW,
            )),
            generations: Arc::new(GenerationRegistry::default()),
            session_idle_timeout,
            runtime_config: Arc::new(runtime_config),
            env: Arc::new(env),
        }
    }
}
