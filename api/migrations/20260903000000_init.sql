CREATE TABLE llm_providers
(
    id                BLOB PRIMARY KEY NOT NULL,
    name              TEXT      NOT NULL,
    api_format        TEXT      NOT NULL CHECK (api_format IN ('ANTHROPIC', 'OPENAI')),
    base_url          TEXT      NOT NULL, -- without trailing slash
    api_key_encrypted BLOB,
    api_key_hint      TEXT,
    currency          TEXT,
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL,

    CHECK (api_key_encrypted IS NOT NULL OR api_key_hint IS NULL)
);

CREATE UNIQUE INDEX idx_llm_providers_name ON llm_providers (lower(name));

CREATE TABLE llm_models
(
    id                BLOB PRIMARY KEY NOT NULL,
    provider_id       BLOB      NOT NULL REFERENCES llm_providers (id) ON DELETE CASCADE,
    api_name          TEXT      NOT NULL,
    display_name      TEXT,
    max_output_tokens INT4,
    -- prices per million tokens
    input_price       TEXT,
    output_price      TEXT,
    cache_read_price  TEXT,
    cache_write_price TEXT,
    is_default        BOOLEAN   NOT NULL,
    created_at        TIMESTAMP NOT NULL,
    updated_at        TIMESTAMP NOT NULL,

    CHECK (max_output_tokens > 0),
    CHECK (CAST(input_price AS REAL) >= 0 AND CAST(output_price AS REAL) >= 0
        AND CAST(cache_read_price AS REAL) >= 0 AND CAST(cache_write_price AS REAL) >= 0),
    CHECK ((input_price IS NULL) = (output_price IS NULL)),
    CHECK (input_price IS NOT NULL OR (cache_read_price IS NULL AND cache_write_price IS NULL))
);

CREATE UNIQUE INDEX idx_llm_models_provider_api_name ON llm_models (provider_id, api_name);
CREATE UNIQUE INDEX idx_llm_models_display_name ON llm_models (lower(COALESCE(display_name, api_name)));
CREATE UNIQUE INDEX idx_llm_models_default ON llm_models (is_default) WHERE is_default;

CREATE TABLE users
(
    id                      BLOB PRIMARY KEY NOT NULL,
    role                    TEXT      NOT NULL CHECK (role IN ('USER', 'ADMIN')),
    user_name               TEXT      NOT NULL,
    email                   TEXT,
    password_hash           TEXT      NOT NULL,
    can_login               BOOLEAN   NOT NULL,
    can_manage_repositories BOOLEAN   NOT NULL,
    can_change_identity     BOOLEAN   NOT NULL,
    must_change_password    BOOLEAN   NOT NULL,
    default_model_id        BLOB REFERENCES llm_models (id) ON DELETE SET NULL,
    locale                  TEXT,
    auto_commit             BOOLEAN   NOT NULL,
    full_name               TEXT,
    first_name              TEXT,
    about                   TEXT,
    created_at              TIMESTAMP NOT NULL,

    CHECK (role <> 'ADMIN' OR (can_login AND can_manage_repositories AND can_change_identity))
);

CREATE UNIQUE INDEX idx_users_user_name ON users (lower(user_name));
CREATE UNIQUE INDEX idx_users_email ON users (lower(email));
CREATE INDEX idx_users_default_model_id ON users (default_model_id);

CREATE TABLE sessions
(
    id           BLOB PRIMARY KEY NOT NULL,
    user_id      BLOB      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash   TEXT      NOT NULL,
    user_agent   TEXT,
    created_at   TIMESTAMP NOT NULL,
    last_used_at TIMESTAMP NOT NULL,
    expires_at   TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX idx_sessions_token_hash ON sessions (token_hash);
CREATE INDEX idx_sessions_user_id ON sessions (user_id);

CREATE TABLE repositories
(
    id                    BLOB PRIMARY KEY NOT NULL,
    user_id               BLOB      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name                  TEXT      NOT NULL,
    description           TEXT,
    remote_url            TEXT, -- never contains the token, NULL for local repositories
    branch                TEXT      NOT NULL,
    poll_interval_seconds INT4,
    token_encrypted       BLOB,
    token_hint            TEXT,
    allow_commits         BOOLEAN   NOT NULL,
    sync_status           TEXT      NOT NULL CHECK (sync_status IN ('PENDING', 'SYNCING', 'READY', 'FAILED')),
    sync_started_at       TIMESTAMP,
    head_commit_sha       TEXT,
    last_synced_at        TIMESTAMP,
    git_size              BIGINT,
    lfs_size              BIGINT,
    last_error            TEXT,
    next_sync_at          TIMESTAMP,
    created_at            TIMESTAMP NOT NULL,
    updated_at            TIMESTAMP NOT NULL,

    CHECK ((sync_status = 'SYNCING') = (sync_started_at IS NOT NULL)),
    CHECK ((remote_url IS NULL) = (poll_interval_seconds IS NULL)),
    CHECK (remote_url IS NOT NULL OR token_encrypted IS NULL),
    CHECK (token_encrypted IS NOT NULL OR token_hint IS NULL)
);

CREATE INDEX idx_repositories_next_sync_at ON repositories (next_sync_at);

-- never includes the owner (repositories.user_id)
CREATE TABLE repository_users
(
    repository_id BLOB      NOT NULL REFERENCES repositories (id) ON DELETE CASCADE,
    user_id       BLOB      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    can_commit    BOOLEAN   NOT NULL,
    created_at    TIMESTAMP NOT NULL,

    PRIMARY KEY (repository_id, user_id)
) WITHOUT ROWID;

CREATE INDEX idx_repository_users_user_id ON repository_users (user_id);

-- by git blob (for LFS files, the pointer's blob)
CREATE TABLE document_extractions
(
    blob_oid     TEXT PRIMARY KEY NOT NULL,
    status       TEXT      NOT NULL CHECK (status IN ('COMPLETED', 'FAILED')),
    markdown     TEXT,
    ocr          BOOLEAN,
    error        TEXT,
    extractor    TEXT      NOT NULL,
    extracted_at TIMESTAMP NOT NULL,

    CHECK ((status = 'COMPLETED') = (markdown IS NOT NULL)),
    CHECK ((status = 'COMPLETED') = (ocr IS NOT NULL)),
    CHECK ((status = 'FAILED') = (error IS NOT NULL))
);

CREATE TABLE repository_documents
(
    repository_id BLOB   NOT NULL REFERENCES repositories (id) ON DELETE CASCADE,
    path          TEXT   NOT NULL,
    blob_oid      TEXT   NOT NULL,

    PRIMARY KEY (repository_id, path)
) WITHOUT ROWID;

CREATE INDEX idx_repository_documents_blob_oid ON repository_documents (blob_oid);

CREATE TABLE chats
(
    id               BLOB PRIMARY KEY NOT NULL,
    user_id          BLOB      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title            TEXT      NOT NULL,
    all_repositories BOOLEAN   NOT NULL,
    model_id         BLOB REFERENCES llm_models (id) ON DELETE SET NULL,
    temporary        BOOLEAN   NOT NULL,
    created_at       TIMESTAMP NOT NULL,
    updated_at       TIMESTAMP NOT NULL
);

CREATE INDEX idx_chats_user_updated_at ON chats (user_id, updated_at DESC) WHERE NOT temporary;
CREATE INDEX idx_chats_temporary_updated_at ON chats (updated_at) WHERE temporary;
CREATE INDEX idx_chats_model_id ON chats (model_id);

-- only used if all_repositories is false
CREATE TABLE chat_repositories
(
    chat_id       BLOB NOT NULL REFERENCES chats (id) ON DELETE CASCADE,
    repository_id BLOB NOT NULL REFERENCES repositories (id) ON DELETE CASCADE,

    PRIMARY KEY (chat_id, repository_id)
) WITHOUT ROWID;

CREATE INDEX idx_chat_repositories_repository_id ON chat_repositories (repository_id);

CREATE TABLE messages
(
    id                 BLOB PRIMARY KEY NOT NULL,
    chat_id            BLOB      NOT NULL REFERENCES chats (id) ON DELETE CASCADE,
    role               TEXT      NOT NULL CHECK (role IN ('USER', 'ASSISTANT')),
    content            TEXT      NOT NULL,
    status             TEXT      NOT NULL CHECK (status IN ('GENERATING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    error              TEXT,
    model_id           BLOB REFERENCES llm_models (id) ON DELETE SET NULL,
    created_at         TIMESTAMP NOT NULL,
    finished_at        TIMESTAMP,
    input_tokens       BIGINT,
    output_tokens      BIGINT,
    cache_read_tokens  BIGINT,
    cache_write_tokens BIGINT,
    cost               TEXT,
    cost_currency      TEXT,

    CHECK (role = 'ASSISTANT' OR status = 'COMPLETED'),
    CHECK ((status = 'FAILED') = (error IS NOT NULL)),
    CHECK (role = 'ASSISTANT' OR model_id IS NULL),
    CHECK (role = 'ASSISTANT' OR finished_at IS NULL),
    CHECK ((input_tokens IS NULL) + (output_tokens IS NULL) + (cache_read_tokens IS NULL)
               + (cache_write_tokens IS NULL) IN (0, 4)),
    CHECK ((cost IS NULL) = (cost_currency IS NULL)),
    CHECK (status <> 'GENERATING' OR finished_at IS NULL)
);

CREATE INDEX idx_messages_chat_created_at ON messages (chat_id, created_at);
CREATE INDEX idx_messages_model_id ON messages (model_id);
CREATE UNIQUE INDEX idx_messages_generating ON messages (chat_id) WHERE status = 'GENERATING';

CREATE TABLE tool_calls
(
    id            BLOB PRIMARY KEY NOT NULL, -- v7, in the order the model requested the calls
    message_id    BLOB      NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
    name          TEXT      NOT NULL,
    input         TEXT      NOT NULL CHECK (json_valid(input)),
    output        TEXT,
    repository_id BLOB REFERENCES repositories (id) ON DELETE SET NULL,
    commit_sha    TEXT,
    is_error      BOOLEAN   NOT NULL,
    created_at    TIMESTAMP NOT NULL,

    CHECK (NOT is_error OR output IS NOT NULL)
);

CREATE INDEX idx_tool_calls_message_id ON tool_calls (message_id, id);
CREATE INDEX idx_tool_calls_repository_id ON tool_calls (repository_id);

CREATE TABLE proposed_commits
(
    tool_call_id    BLOB PRIMARY KEY NOT NULL REFERENCES tool_calls (id) ON DELETE CASCADE,
    path            TEXT,
    moves           TEXT CHECK (json_valid(moves)), -- [{"from": ..., "to": ...}]
    proposed_commit TEXT      NOT NULL,
    status          TEXT      NOT NULL CHECK (status IN ('PROPOSED', 'COMMITTED', 'CONFLICT', 'FAILED')),
    pushed_commit   TEXT,
    pushed_branch   TEXT,
    committed_at    TIMESTAMP,
    error           TEXT,

    CHECK ((path IS NULL) != (moves IS NULL)),
    CHECK ((status = 'COMMITTED') = (pushed_commit IS NOT NULL)),
    CHECK ((pushed_commit IS NULL) = (pushed_branch IS NULL)),
    CHECK ((pushed_commit IS NULL) = (committed_at IS NULL)),
    CHECK ((status IN ('CONFLICT', 'FAILED')) = (error IS NOT NULL))
) WITHOUT ROWID;

CREATE TABLE attachments
(
    id           BLOB PRIMARY KEY NOT NULL,
    user_id      BLOB      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    chat_id      BLOB REFERENCES chats (id) ON DELETE CASCADE,
    message_id   BLOB UNIQUE REFERENCES messages (id) ON DELETE CASCADE,
    number       INT4,
    file_name    TEXT      NOT NULL,
    content_type TEXT      NOT NULL,
    size         BIGINT    NOT NULL,
    blob_oid     TEXT      NOT NULL,
    created_at   TIMESTAMP NOT NULL,

    CHECK ((chat_id IS NULL) = (message_id IS NULL) AND (chat_id IS NULL) = (number IS NULL)),
    UNIQUE (chat_id, number)
);

CREATE INDEX idx_attachments_unsent ON attachments (created_at) WHERE message_id IS NULL;
CREATE INDEX idx_attachments_blob_oid ON attachments (blob_oid);

CREATE TABLE config
(
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
) WITHOUT ROWID;
