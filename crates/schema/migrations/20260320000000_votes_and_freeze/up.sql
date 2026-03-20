-- Vote ledger: one row per VoteCast event
CREATE TABLE votes (
    vote_id      TEXT    PRIMARY KEY,  -- {tx_digest}:{event_idx}
    proposal_id  TEXT    NOT NULL,
    dao_id       TEXT    NOT NULL,
    voter        TEXT    NOT NULL,
    approve      BOOLEAN NOT NULL,
    weight       BIGINT  NOT NULL,
    timestamp_ms BIGINT  NOT NULL
);

CREATE INDEX votes_proposal_id ON votes (proposal_id);
CREATE INDEX votes_dao_id      ON votes (dao_id);

-- Currently frozen proposal types (upserted on TypeFrozen, deleted on TypeUnfrozen)
CREATE TABLE frozen_types (
    dao_id          TEXT   NOT NULL,
    type_key        TEXT   NOT NULL,
    frozen_until_ms BIGINT NOT NULL,
    PRIMARY KEY (dao_id, type_key)
);

-- Proposal types exempt from freezing
CREATE TABLE freeze_exempt_types (
    dao_id   TEXT NOT NULL,
    type_key TEXT NOT NULL,
    PRIMARY KEY (dao_id, type_key)
);

-- Soft-delete support for DAODestroyed
ALTER TABLE daos
    ADD COLUMN destroyed_at_ms  BIGINT,
    ADD COLUMN successor_dao_id TEXT;

-- Proposal type_key filter index
CREATE INDEX proposals_type_key ON proposals (dao_id, type_key);

-- Activity search composite index
CREATE INDEX events_search ON events (dao_id, event_type, checkpoint_timestamp_ms DESC);
