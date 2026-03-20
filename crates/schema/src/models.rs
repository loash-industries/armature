use diesel::prelude::*;
use serde::Serialize;
use sui_field_count::FieldCount;

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::events, primary_key(event_digest))]
pub struct Event {
    pub event_digest: String,
    pub digest: String,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
    pub event_type: String,
    pub dao_id: Option<String>,
    pub payload_json: Option<serde_json::Value>,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::daos, primary_key(dao_id))]
pub struct Dao {
    pub dao_id: String,
    pub treasury_id: String,
    pub charter_id: String,
    pub freeze_id: String,
    pub cap_vault_id: String,
    pub creator: String,
    pub created_at_ms: i64,
    pub destroyed_at_ms: Option<i64>,
    pub successor_dao_id: Option<String>,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::proposals, primary_key(proposal_id))]
pub struct Proposal {
    pub proposal_id: String,
    pub dao_id: String,
    pub type_key: String,
    pub proposer: String,
    pub status: String,
    pub yes_votes: i64,
    pub no_votes: i64,
    pub created_at_ms: i64,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::treasury_balances, primary_key(treasury_id, coin_type))]
pub struct TreasuryBalance {
    pub treasury_id: String,
    pub coin_type: String,
    pub balance: bigdecimal::BigDecimal,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::votes, primary_key(vote_id))]
pub struct Vote {
    pub vote_id: String,
    pub proposal_id: String,
    pub dao_id: String,
    pub voter: String,
    pub approve: bool,
    pub weight: i64,
    pub timestamp_ms: i64,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::frozen_types, primary_key(dao_id, type_key))]
pub struct FrozenType {
    pub dao_id: String,
    pub type_key: String,
    pub frozen_until_ms: i64,
}

#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount, Serialize)]
#[diesel(table_name = crate::schema::freeze_exempt_types, primary_key(dao_id, type_key))]
pub struct FreezeExemptType {
    pub dao_id: String,
    pub type_key: String,
}
