CREATE TABLE messages_new
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
    response_ms        BIGINT CHECK (response_ms >= 0),
    cost               TEXT,
    cost_currency      TEXT,

    CHECK (role = 'ASSISTANT' OR status = 'COMPLETED'),
    CHECK ((status = 'FAILED') = (error IS NOT NULL)),
    CHECK (role = 'ASSISTANT' OR model_id IS NULL),
    CHECK (role = 'ASSISTANT' OR finished_at IS NULL),
    CHECK ((input_tokens IS NULL) + (output_tokens IS NULL) + (cache_read_tokens IS NULL)
               + (cache_write_tokens IS NULL) + (response_ms IS NULL) IN (0, 5)),
    CHECK ((cost IS NULL) = (cost_currency IS NULL)),
    CHECK (status <> 'GENERATING' OR finished_at IS NULL)
);

INSERT INTO messages_new (id, chat_id, role, content, status, error, model_id, created_at, finished_at, input_tokens,
                          output_tokens, cache_read_tokens, cache_write_tokens, response_ms, cost, cost_currency)
SELECT id,
       chat_id,
       role,
       content,
       status,
       error,
       model_id,
       created_at,
       finished_at,
       input_tokens,
       output_tokens,
       cache_read_tokens,
       cache_write_tokens,
       CASE WHEN input_tokens IS NOT NULL THEN 0 END,
       cost,
       cost_currency
FROM messages;

DROP TABLE messages;
ALTER TABLE messages_new RENAME TO messages;

CREATE INDEX idx_messages_chat_created_at ON messages (chat_id, created_at);
CREATE INDEX idx_messages_model_id ON messages (model_id);
CREATE UNIQUE INDEX idx_messages_generating ON messages (chat_id) WHERE status = 'GENERATING';

ALTER TABLE tool_calls ADD COLUMN duration_ms BIGINT CHECK (duration_ms >= 0)
    CHECK (duration_ms IS NULL OR output IS NOT NULL);

CREATE TABLE raw_answers
(
    message_id BLOB PRIMARY KEY NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
    raw        BLOB NOT NULL -- compressed JSON
);
