use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use diesel::prelude::*;
use diesel_async::RunQueryDsl;
use move_core_types::account_address::AccountAddress;
use sui_field_count::FieldCount;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::postgres::handler::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_pg_db::Connection;

use armature_schema::models::Proposal;
use armature_schema::schema::proposals;

use crate::models::{
    id_to_hex, ProposalCreated, ProposalExecuted, ProposalExpired, ProposalPassed,
};
use crate::{is_armature_event, parse_package_addresses};

pub enum ProposalMutation {
    Insert(Proposal),
    UpdateStatus {
        proposal_id: String,
        status: String,
    },
    UpdateVotes {
        proposal_id: String,
        status: String,
        yes_votes: i64,
        no_votes: i64,
    },
}

// FieldCount is required by the framework for batch-size calculations.
// Use the field count of the largest variant (Proposal = 8 fields).
impl FieldCount for ProposalMutation {
    const FIELD_COUNT: usize = 8;
}

pub struct ProposalHandler {
    packages: Vec<AccountAddress>,
}

impl ProposalHandler {
    pub fn new(package_ids: &[String]) -> Self {
        Self {
            packages: parse_package_addresses(package_ids),
        }
    }
}

#[async_trait]
impl Processor for ProposalHandler {
    const NAME: &'static str = "proposal";
    type Value = ProposalMutation;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut mutations = vec![];
        let ts = checkpoint.summary.timestamp_ms;

        for tx in &checkpoint.transactions {
            let Some(events) = &tx.events else { continue };
            for event in &events.data {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }
                if event.type_.module.as_str() != "proposal" {
                    continue;
                }

                match event.type_.name.as_str() {
                    "ProposalCreated" => {
                        match bcs::from_bytes::<ProposalCreated>(&event.contents) {
                            Ok(e) => mutations.push(ProposalMutation::Insert(Proposal {
                                proposal_id: id_to_hex(&e.proposal_id),
                                dao_id: id_to_hex(&e.dao_id),
                                type_key: e.type_key,
                                proposer: id_to_hex(&e.proposer),
                                status: "Active".to_string(),
                                yes_votes: 0,
                                no_votes: 0,
                                created_at_ms: ts as i64,
                            })),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize ProposalCreated: {e}")
                            }
                        }
                    }
                    "ProposalPassed" => match bcs::from_bytes::<ProposalPassed>(&event.contents) {
                        Ok(e) => mutations.push(ProposalMutation::UpdateVotes {
                            proposal_id: id_to_hex(&e.proposal_id),
                            status: "Passed".to_string(),
                            yes_votes: e.yes_weight as i64,
                            no_votes: e.no_weight as i64,
                        }),
                        Err(e) => {
                            tracing::warn!("Failed to deserialize ProposalPassed: {e}")
                        }
                    },
                    "ProposalExecuted" => {
                        match bcs::from_bytes::<ProposalExecuted>(&event.contents) {
                            Ok(e) => mutations.push(ProposalMutation::UpdateStatus {
                                proposal_id: id_to_hex(&e.proposal_id),
                                status: "Executed".to_string(),
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize ProposalExecuted: {e}")
                            }
                        }
                    }
                    "ProposalExpired" => {
                        match bcs::from_bytes::<ProposalExpired>(&event.contents) {
                            Ok(e) => mutations.push(ProposalMutation::UpdateStatus {
                                proposal_id: id_to_hex(&e.proposal_id),
                                status: "Expired".to_string(),
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize ProposalExpired: {e}")
                            }
                        }
                    }
                    _ => {}
                }
            }
        }

        Ok(mutations)
    }
}

#[async_trait]
impl Handler for ProposalHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        let mut n = 0usize;

        let inserts: Vec<&Proposal> = values
            .iter()
            .filter_map(|v| {
                if let ProposalMutation::Insert(p) = v {
                    Some(p)
                } else {
                    None
                }
            })
            .collect();

        if !inserts.is_empty() {
            let count = inserts.len();
            diesel::insert_into(proposals::table)
                .values(inserts)
                .on_conflict_do_nothing()
                .execute(conn)
                .await?;
            n += count;
        }

        for v in values {
            match v {
                ProposalMutation::UpdateStatus {
                    proposal_id,
                    status,
                } => {
                    diesel::update(proposals::table.filter(proposals::proposal_id.eq(proposal_id)))
                        .set(proposals::status.eq(status))
                        .execute(conn)
                        .await?;
                    n += 1;
                }
                ProposalMutation::UpdateVotes {
                    proposal_id,
                    status,
                    yes_votes,
                    no_votes,
                } => {
                    diesel::update(proposals::table.filter(proposals::proposal_id.eq(proposal_id)))
                        .set((
                            proposals::status.eq(status),
                            proposals::yes_votes.eq(yes_votes),
                            proposals::no_votes.eq(no_votes),
                        ))
                        .execute(conn)
                        .await?;
                    n += 1;
                }
                ProposalMutation::Insert(_) => {}
            }
        }

        Ok(n)
    }
}
