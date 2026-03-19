use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use bigdecimal::BigDecimal;
use diesel::prelude::*;
use diesel::upsert::excluded;
use diesel_async::RunQueryDsl;
use move_core_types::account_address::AccountAddress;
use sui_field_count::FieldCount;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::postgres::handler::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_pg_db::Connection;

use crate::models::{id_to_hex, CoinClaimed, CoinDeposited, CoinWithdrawn};
use crate::{is_armature_event, parse_package_addresses};

/// A balance change to apply atomically via upsert.
/// Positive delta = deposit, negative = withdrawal or claim.
#[derive(FieldCount)]
pub struct BalanceDelta {
    pub treasury_id: String,
    pub coin_type: String,
    pub delta: BigDecimal,
}

pub struct TreasuryHandler {
    packages: Vec<AccountAddress>,
}

impl TreasuryHandler {
    pub fn new(package_ids: &[String]) -> Self {
        Self {
            packages: parse_package_addresses(package_ids),
        }
    }
}

#[async_trait]
impl Processor for TreasuryHandler {
    const NAME: &'static str = "treasury";
    type Value = BalanceDelta;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut deltas = vec![];

        for tx in &checkpoint.transactions {
            let Some(events) = &tx.events else { continue };
            for event in &events.data {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }
                if event.type_.module.as_str() != "treasury_vault" {
                    continue;
                }

                match event.type_.name.as_str() {
                    "CoinDeposited" => {
                        match bcs::from_bytes::<CoinDeposited>(&event.contents) {
                            Ok(e) => deltas.push(BalanceDelta {
                                treasury_id: id_to_hex(&e.vault_id),
                                coin_type: e.coin_type,
                                delta: BigDecimal::from(e.amount),
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize CoinDeposited: {e}")
                            }
                        }
                    }
                    "CoinWithdrawn" => {
                        match bcs::from_bytes::<CoinWithdrawn>(&event.contents) {
                            Ok(e) => deltas.push(BalanceDelta {
                                treasury_id: id_to_hex(&e.vault_id),
                                coin_type: e.coin_type,
                                delta: BigDecimal::from(-(e.amount as i64)),
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize CoinWithdrawn: {e}")
                            }
                        }
                    }
                    "CoinClaimed" => {
                        match bcs::from_bytes::<CoinClaimed>(&event.contents) {
                            Ok(e) => deltas.push(BalanceDelta {
                                treasury_id: id_to_hex(&e.vault_id),
                                coin_type: e.coin_type,
                                delta: BigDecimal::from(-(e.amount as i64)),
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize CoinClaimed: {e}")
                            }
                        }
                    }
                    _ => {}
                }
            }
        }

        Ok(deltas)
    }
}

#[async_trait]
impl Handler for TreasuryHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        use armature_schema::schema::treasury_balances as tb;

        let mut n = 0usize;
        for delta in values {
            // INSERT (treasury_id, coin_type, balance=delta)
            // ON CONFLICT DO UPDATE SET balance = balance + EXCLUDED.balance
            diesel::insert_into(tb::table)
                .values((
                    tb::treasury_id.eq(&delta.treasury_id),
                    tb::coin_type.eq(&delta.coin_type),
                    tb::balance.eq(&delta.delta),
                ))
                .on_conflict((tb::treasury_id, tb::coin_type))
                .do_update()
                .set(tb::balance.eq(tb::balance + excluded(tb::balance)))
                .execute(conn)
                .await?;
            n += 1;
        }
        Ok(n)
    }
}
