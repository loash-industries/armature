CREATE TABLE IF NOT EXISTS events (
    event_digest TEXT PRIMARY KEY,
    digest TEXT NOT NULL,
    sender TEXT NOT NULL,
    checkpoint BIGINT NOT NULL,
    checkpoint_timestamp_ms BIGINT NOT NULL,
    package TEXT NOT NULL
);
