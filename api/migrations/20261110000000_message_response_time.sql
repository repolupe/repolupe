-- How long the responses of the language model took, in milliseconds. NULL for answers from
-- before it was measured.
ALTER TABLE messages ADD COLUMN response_ms BIGINT CHECK (response_ms >= 0);

-- How long the tool took to run, in milliseconds. NULL while it runs, for calls that were
-- interrupted, and for calls from before it was measured.
ALTER TABLE tool_calls ADD COLUMN duration_ms BIGINT CHECK (duration_ms >= 0);
