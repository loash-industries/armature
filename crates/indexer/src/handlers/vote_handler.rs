use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use diesel_async::RunQueryDsl;
use move_core_types::account_address::AccountAddress;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::postgres::handler::Handler;
use sui_indexer_alt_framework::types::effects::TransactionEffectsAPI;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_pg_db::Connection;

use armature_schema::models::Vote;
use armature_schema::schema::votes;

use crate::models::{id_to_hex, VoteCast};
use crate::{is_armature_event, parse_package_addresses};

pub struct VoteHandler {
    packages: Vec<AccountAddress>,
}

impl VoteHandler {
    pub fn new(package_ids: &[String]) -> Self {
        Self {
            packages: parse_package_addresses(package_ids),
        }
    }
}

#[async_trait]
impl Processor for VoteHandler {
    const NAME: &'static str = "vote";
    type Value = Vote;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut rows = vec![];
        let ts = checkpoint.summary.timestamp_ms as i64;

        for tx in &checkpoint.transactions {
            let tx_digest = tx.effects.transaction_digest().to_string();
            let Some(events) = &tx.events else { continue };

            for (event_idx, event) in events.data.iter().enumerate() {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }
                if event.type_.module.as_str() != "proposal"
                    || event.type_.name.as_str() != "VoteCast"
                {
                    continue;
                }

                match bcs::from_bytes::<VoteCast>(&event.contents) {
                    Ok(e) => rows.push(Vote {
                        vote_id: format!("{tx_digest}:{event_idx}"),
                        proposal_id: id_to_hex(&e.proposal_id),
                        dao_id: id_to_hex(&e.dao_id),
                        voter: id_to_hex(&e.voter),
                        approve: e.approve,
                        weight: e.weight as i64,
                        timestamp_ms: ts,
                    }),
                    Err(e) => {
                        tracing::warn!("Failed to deserialize VoteCast: {e}");
                    }
                }
            }
        }

        Ok(rows)
    }
}

#[async_trait]
impl Handler for VoteHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        if values.is_empty() {
            return Ok(0);
        }
        diesel::insert_into(votes::table)
            .values(values)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;
        Ok(values.len())
    }
}
