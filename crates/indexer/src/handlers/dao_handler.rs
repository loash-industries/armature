use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use diesel_async::RunQueryDsl;
use move_core_types::account_address::AccountAddress;
use sui_indexer_alt_framework::pipeline::Processor;
use sui_indexer_alt_framework::postgres::handler::Handler;
use sui_indexer_alt_framework::types::full_checkpoint_content::Checkpoint;
use sui_pg_db::Connection;

use armature_schema::models::Dao;
use armature_schema::schema::daos;

use crate::models::{id_to_hex, DAOCreated};
use crate::{is_armature_event, parse_package_addresses};

pub struct DaoHandler {
    packages: Vec<AccountAddress>,
}

impl DaoHandler {
    pub fn new(package_ids: &[String]) -> Self {
        Self {
            packages: parse_package_addresses(package_ids),
        }
    }
}

#[async_trait]
impl Processor for DaoHandler {
    const NAME: &'static str = "dao";
    type Value = Dao;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut rows = vec![];
        let ts = checkpoint.summary.timestamp_ms;

        for tx in &checkpoint.transactions {
            let Some(events) = &tx.events else { continue };
            for event in &events.data {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }
                if event.type_.module.as_str() != "dao" || event.type_.name.as_str() != "DAOCreated"
                {
                    continue;
                }

                match bcs::from_bytes::<DAOCreated>(&event.contents) {
                    Ok(e) => rows.push(Dao {
                        dao_id: id_to_hex(&e.dao_id),
                        treasury_id: id_to_hex(&e.treasury_id),
                        charter_id: id_to_hex(&e.charter_id),
                        freeze_id: id_to_hex(&e.emergency_freeze_id),
                        cap_vault_id: id_to_hex(&e.capability_vault_id),
                        creator: id_to_hex(&e.creator),
                        created_at_ms: ts as i64,
                    }),
                    Err(e) => {
                        tracing::warn!("Failed to deserialize DAOCreated: {e}");
                    }
                }
            }
        }

        Ok(rows)
    }
}

#[async_trait]
impl Handler for DaoHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        if values.is_empty() {
            return Ok(0);
        }
        diesel::insert_into(daos::table)
            .values(values)
            .on_conflict_do_nothing()
            .execute(conn)
            .await?;
        Ok(values.len())
    }
}
