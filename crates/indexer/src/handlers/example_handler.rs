use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use diesel_async::RunQueryDsl;
use sui_field_count::FieldCount;
use sui_indexer_alt_framework::pipeline::concurrent::Handler;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::types::full_checkpoint_content::CheckpointData as Checkpoint;
use sui_pg_db::Connection;

use armature_schema::models::Event;
use armature_schema::schema::events;

use crate::ArmatureEnv;

pub struct ExampleHandler {
    pub env: ArmatureEnv,
}

impl ExampleHandler {
    pub fn new(env: ArmatureEnv) -> Self {
        Self { env }
    }
}

#[async_trait]
impl Processor for ExampleHandler {
    const NAME: &'static str = "example_events";
    type Value = Event;

    async fn process(&self, _checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        // TODO: Iterate checkpoint transactions, match events, deserialize with BCS.
        // See triex-book handlers for the pattern:
        //   1. for tx in checkpoint.transactions { ... }
        //   2. for event in tx.events { ... }
        //   3. match event struct tag against known types
        //   4. bcs::from_bytes::<YourMoveEvent>(&event.contents)
        //   5. convert to DB model
        Ok(vec![])
    }
}

#[async_trait]
impl Handler for ExampleHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        let n = values.len();
        if n == 0 {
            return Ok(0);
        }
        diesel::insert_into(events::table)
            .values(values)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;
        Ok(n)
    }
}
