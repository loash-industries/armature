use diesel::prelude::*;
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
