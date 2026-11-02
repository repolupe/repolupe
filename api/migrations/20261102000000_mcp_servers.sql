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
