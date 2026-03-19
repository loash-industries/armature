-- Extend events table with activity-log columns
ALTER TABLE events
    ADD COLUMN IF NOT EXISTS event_type TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS dao_id     TEXT,
    ADD COLUMN IF NOT EXISTS payload_json JSONB;

-- DAO registry: one row per created DAO
CREATE TABLE daos (
    dao_id       TEXT PRIMARY KEY,
    treasury_id  TEXT NOT NULL,
    charter_id   TEXT NOT NULL,
    freeze_id    TEXT NOT NULL,
    cap_vault_id TEXT NOT NULL,
    creator      TEXT NOT NULL,
    created_at_ms BIGINT NOT NULL
);

-- Proposal lifecycle: inserted on ProposalCreated, status updated on Passed/Executed/Expired
CREATE TABLE proposals (
    proposal_id TEXT PRIMARY KEY,
    dao_id      TEXT    NOT NULL,
    type_key    TEXT    NOT NULL,
    proposer    TEXT    NOT NULL,
    status      TEXT    NOT NULL DEFAULT 'Active',
    yes_votes   BIGINT  NOT NULL DEFAULT 0,
    no_votes    BIGINT  NOT NULL DEFAULT 0,
    created_at_ms BIGINT NOT NULL
);

CREATE INDEX proposals_dao_id     ON proposals (dao_id);
CREATE INDEX proposals_dao_status ON proposals (dao_id, status);

-- Treasury balances: upsert on CoinDeposited/CoinWithdrawn/CoinClaimed
CREATE TABLE treasury_balances (
    treasury_id TEXT    NOT NULL,
    coin_type   TEXT    NOT NULL,
    balance     NUMERIC NOT NULL DEFAULT 0,
    PRIMARY KEY (treasury_id, coin_type)
);
