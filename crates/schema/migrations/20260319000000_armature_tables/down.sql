DROP TABLE IF EXISTS treasury_balances;
DROP TABLE IF EXISTS proposals;
DROP TABLE IF EXISTS daos;

ALTER TABLE events
    DROP COLUMN IF EXISTS event_type,
    DROP COLUMN IF EXISTS dao_id,
    DROP COLUMN IF EXISTS payload_json;
