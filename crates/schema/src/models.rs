use diesel::prelude::*;
use serde::Serialize;
use sui_field_count::FieldCount;

/// Example model — replace with your actual event tables.
#[derive(Queryable, Selectable, Insertable, Identifiable, Debug, FieldCount)]
#[diesel(table_name = crate::schema::events, primary_key(event_digest))]
pub struct Event {
    pub event_digest: String,
    pub digest: String,
    pub sender: String,
    pub checkpoint: i64,
    pub checkpoint_timestamp_ms: i64,
    pub package: String,
}
