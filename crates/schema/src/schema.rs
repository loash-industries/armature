// @generated — kept in sync with migrations manually.
// Run `diesel print-schema` after `diesel migration run` to regenerate.

diesel::table! {
    events (event_digest) {
        event_digest          -> Text,
        digest                -> Text,
        sender                -> Text,
        checkpoint            -> Int8,
        checkpoint_timestamp_ms -> Int8,
        package               -> Text,
        event_type            -> Text,
        dao_id                -> Nullable<Text>,
        payload_json          -> Nullable<Jsonb>,
    }
}

diesel::table! {
    daos (dao_id) {
        dao_id           -> Text,
        treasury_id      -> Text,
        charter_id       -> Text,
        freeze_id        -> Text,
        cap_vault_id     -> Text,
        creator          -> Text,
        created_at_ms    -> Int8,
        destroyed_at_ms  -> Nullable<Int8>,
        successor_dao_id -> Nullable<Text>,
    }
}

diesel::table! {
    proposals (proposal_id) {
        proposal_id   -> Text,
        dao_id        -> Text,
        type_key      -> Text,
        proposer      -> Text,
        status        -> Text,
        yes_votes     -> Int8,
        no_votes      -> Int8,
        created_at_ms -> Int8,
    }
}

diesel::table! {
    treasury_balances (treasury_id, coin_type) {
        treasury_id -> Text,
        coin_type   -> Text,
        balance     -> Numeric,
    }
}

diesel::table! {
    votes (vote_id) {
        vote_id      -> Text,
        proposal_id  -> Text,
        dao_id       -> Text,
        voter        -> Text,
        approve      -> Bool,
        weight       -> Int8,
        timestamp_ms -> Int8,
    }
}

diesel::table! {
    frozen_types (dao_id, type_key) {
        dao_id          -> Text,
        type_key        -> Text,
        frozen_until_ms -> Int8,
    }
}

diesel::table! {
    freeze_exempt_types (dao_id, type_key) {
        dao_id   -> Text,
        type_key -> Text,
    }
}
