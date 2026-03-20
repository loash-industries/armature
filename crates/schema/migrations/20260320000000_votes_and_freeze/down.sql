DROP INDEX IF EXISTS events_search;
DROP INDEX IF EXISTS proposals_type_key;

ALTER TABLE daos
    DROP COLUMN IF EXISTS successor_dao_id,
    DROP COLUMN IF EXISTS destroyed_at_ms;

DROP TABLE IF EXISTS freeze_exempt_types;
DROP TABLE IF EXISTS frozen_types;
DROP TABLE IF EXISTS votes;
