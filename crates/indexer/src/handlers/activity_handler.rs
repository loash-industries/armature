//! Catches all Armature events and writes them to the `events` table for the
//! `/dao/:id/activity` endpoint.

use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use diesel_async::RunQueryDsl;
use move_core_types::account_address::AccountAddress;
use serde_json::json;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::postgres::handler::Handler;
use sui_indexer_alt_framework::types::effects::TransactionEffectsAPI;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_pg_db::Connection;

use armature_schema::models::Event;
use armature_schema::schema::events;

use crate::models::{
    id_to_hex, CoinClaimed, CoinDeposited, CoinWithdrawn, DAOCreated, ProposalCreated,
    ProposalExecuted, ProposalExpired, ProposalPassed, TypeFrozen, TypeUnfrozen, VoteCast,
};
use crate::{is_armature_event, parse_package_addresses};

pub struct ActivityHandler {
    packages: Vec<AccountAddress>,
}

impl ActivityHandler {
    pub fn new(package_ids: &[String]) -> Self {
        Self {
            packages: parse_package_addresses(package_ids),
        }
    }
}

/// Decode known event BCS bytes into structured JSON, returning (dao_id, payload).
fn decode_event(
    module: &str,
    name: &str,
    contents: &[u8],
) -> (Option<String>, Option<serde_json::Value>) {
    match (module, name) {
        ("dao", "DAOCreated") => {
            if let Ok(e) = bcs::from_bytes::<DAOCreated>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "dao_id": dao_id,
                    "treasury_id": id_to_hex(&e.treasury_id),
                    "cap_vault_id": id_to_hex(&e.capability_vault_id),
                    "charter_id": id_to_hex(&e.charter_id),
                    "freeze_id": id_to_hex(&e.emergency_freeze_id),
                    "creator": id_to_hex(&e.creator),
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("proposal", "ProposalCreated") => {
            if let Ok(e) = bcs::from_bytes::<ProposalCreated>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "proposal_id": id_to_hex(&e.proposal_id),
                    "dao_id": dao_id,
                    "type_key": e.type_key,
                    "proposer": id_to_hex(&e.proposer),
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("proposal", "VoteCast") => {
            if let Ok(e) = bcs::from_bytes::<VoteCast>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "proposal_id": id_to_hex(&e.proposal_id),
                    "dao_id": dao_id,
                    "voter": id_to_hex(&e.voter),
                    "approve": e.approve,
                    "weight": e.weight,
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("proposal", "ProposalPassed") => {
            if let Ok(e) = bcs::from_bytes::<ProposalPassed>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "proposal_id": id_to_hex(&e.proposal_id),
                    "dao_id": dao_id,
                    "yes_weight": e.yes_weight,
                    "no_weight": e.no_weight,
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("proposal", "ProposalExecuted") => {
            if let Ok(e) = bcs::from_bytes::<ProposalExecuted>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "proposal_id": id_to_hex(&e.proposal_id),
                    "dao_id": dao_id,
                    "executor": id_to_hex(&e.executor),
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("proposal", "ProposalExpired") => {
            if let Ok(e) = bcs::from_bytes::<ProposalExpired>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "proposal_id": id_to_hex(&e.proposal_id),
                    "dao_id": dao_id,
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("treasury_vault", "CoinDeposited") => {
            if let Ok(e) = bcs::from_bytes::<CoinDeposited>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "vault_id": id_to_hex(&e.vault_id),
                    "dao_id": dao_id,
                    "coin_type": e.coin_type,
                    "amount": e.amount,
                    "depositor": id_to_hex(&e.depositor),
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("treasury_vault", "CoinWithdrawn") => {
            if let Ok(e) = bcs::from_bytes::<CoinWithdrawn>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "vault_id": id_to_hex(&e.vault_id),
                    "dao_id": dao_id,
                    "coin_type": e.coin_type,
                    "amount": e.amount,
                    "recipient": id_to_hex(&e.recipient),
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("treasury_vault", "CoinClaimed") => {
            if let Ok(e) = bcs::from_bytes::<CoinClaimed>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "vault_id": id_to_hex(&e.vault_id),
                    "dao_id": dao_id,
                    "coin_type": e.coin_type,
                    "amount": e.amount,
                    "claimer": id_to_hex(&e.claimer),
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("emergency", "TypeFrozen") => {
            if let Ok(e) = bcs::from_bytes::<TypeFrozen>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({
                    "dao_id": dao_id,
                    "type_key": e.type_key,
                    "expiry_ms": e.expiry_ms,
                });
                return (Some(dao_id), Some(payload));
            }
        }
        ("emergency", "TypeUnfrozen") => {
            if let Ok(e) = bcs::from_bytes::<TypeUnfrozen>(contents) {
                let dao_id = id_to_hex(&e.dao_id);
                let payload = json!({ "dao_id": dao_id, "type_key": e.type_key });
                return (Some(dao_id), Some(payload));
            }
        }
        _ => {}
    }
    (None, None)
}

#[async_trait]
impl Processor for ActivityHandler {
    const NAME: &'static str = "activity";
    type Value = Event;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut rows = vec![];
        let cp_seq = checkpoint.summary.sequence_number;
        let ts = checkpoint.summary.timestamp_ms as i64;

        for tx in &checkpoint.transactions {
            let tx_digest = tx.effects.transaction_digest().to_string();
            let Some(events) = &tx.events else { continue };

            for (event_idx, event) in events.data.iter().enumerate() {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }

                let module = event.type_.module.as_str();
                let name = event.type_.name.as_str();
                let (dao_id, payload_json) = decode_event(module, name, &event.contents);

                rows.push(Event {
                    event_digest: format!("{tx_digest}:{event_idx}"),
                    digest: tx_digest.clone(),
                    sender: format!("0x{}", hex::encode(event.sender.as_ref() as &[u8])),
                    checkpoint: cp_seq as i64,
                    checkpoint_timestamp_ms: ts,
                    package: format!("0x{}", hex::encode(event.type_.address.as_slice())),
                    event_type: name.to_string(),
                    dao_id,
                    payload_json,
                });
            }
        }

        Ok(rows)
    }
}

#[async_trait]
impl Handler for ActivityHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        if values.is_empty() {
            return Ok(0);
        }
        diesel::insert_into(events::table)
            .values(values)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;
        Ok(values.len())
    }
}
