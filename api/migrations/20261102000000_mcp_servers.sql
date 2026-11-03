CREATE TABLE mcp_servers
(
    id              BLOB PRIMARY KEY NOT NULL,
    user_id         BLOB      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name            TEXT      NOT NULL,
    url             TEXT      NOT NULL,
    enabled         BOOLEAN   NOT NULL,
    token_encrypted BLOB,
    token_hint      TEXT,
    oauth_encrypted BLOB,
    status          TEXT      NOT NULL CHECK (status IN ('READY', 'AUTHORIZATION_REQUIRED', 'FAILED')),
    last_error      TEXT,
    tools           TEXT      NOT NULL CHECK (json_valid(tools)),
    disabled_tools  TEXT      NOT NULL CHECK (json_valid(disabled_tools)),
    checked_at      TIMESTAMP NOT NULL,
    created_at      TIMESTAMP NOT NULL,
    updated_at      TIMESTAMP NOT NULL,

    CHECK ((status = 'FAILED') = (last_error IS NOT NULL)),
    CHECK (token_encrypted IS NOT NULL OR token_hint IS NULL),
    CHECK (token_encrypted IS NULL OR oauth_encrypted IS NULL)
);

CREATE UNIQUE INDEX idx_mcp_servers_user_name ON mcp_servers (user_id, lower(name));

CREATE TABLE users_new
(
    id                      BLOB PRIMARY KEY NOT NULL,
    role                    TEXT      NOT NULL CHECK (role IN ('USER', 'ADMIN')),
    user_name               TEXT      NOT NULL,
    email                   TEXT,
    password_hash           TEXT      NOT NULL,
    can_login               BOOLEAN   NOT NULL,
    can_manage_repositories BOOLEAN   NOT NULL,
    can_manage_mcp_servers  BOOLEAN   NOT NULL,
    can_change_identity     BOOLEAN   NOT NULL,
    must_change_password    BOOLEAN   NOT NULL,
    default_model_id        BLOB REFERENCES llm_models (id) ON DELETE SET NULL,
    locale                  TEXT,
    auto_commit             BOOLEAN   NOT NULL,
    full_name               TEXT,
    first_name              TEXT,
    about                   TEXT,
    created_at              TIMESTAMP NOT NULL,

    CHECK (role <> 'ADMIN' OR (can_login AND can_manage_repositories AND can_manage_mcp_servers AND can_change_identity))
);

INSERT INTO users_new (id, role, user_name, email, password_hash, can_login, can_manage_repositories, can_manage_mcp_servers, can_change_identity, must_change_password, default_model_id, locale, auto_commit, full_name, first_name, about, created_at)
SELECT id, role, user_name, email, password_hash, can_login, can_manage_repositories, true, can_change_identity, must_change_password, default_model_id, locale, auto_commit, full_name, first_name, about, created_at
FROM users;

DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

CREATE UNIQUE INDEX idx_users_user_name ON users (lower(user_name));
CREATE UNIQUE INDEX idx_users_email ON users (lower(email));
CREATE INDEX idx_users_default_model_id ON users (default_model_id);
