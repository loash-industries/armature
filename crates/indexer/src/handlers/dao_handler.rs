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

use armature_schema::models::Dao;
use armature_schema::schema::daos;

use crate::models::{id_to_hex, is_zero_id, DAOCreated, DAODestroyed};
use crate::{is_armature_event, parse_package_addresses};

pub enum DaoMutation {
    Insert(Dao),
    Destroy {
        dao_id: String,
        destroyed_at_ms: i64,
        successor_dao_id: Option<String>,
    },
}

// Use the field count of the largest variant (Dao = 9 fields).
impl FieldCount for DaoMutation {
    const FIELD_COUNT: usize = 9;
}

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
    type Value = DaoMutation;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut mutations = vec![];
        let ts = checkpoint.summary.timestamp_ms as i64;

        for tx in &checkpoint.transactions {
            let Some(events) = &tx.events else { continue };
            for event in &events.data {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }
                if event.type_.module.as_str() != "dao" {
                    continue;
                }

                match event.type_.name.as_str() {
                    "DAOCreated" => match bcs::from_bytes::<DAOCreated>(&event.contents) {
                        Ok(e) => mutations.push(DaoMutation::Insert(Dao {
                            dao_id: id_to_hex(&e.dao_id),
                            treasury_id: id_to_hex(&e.treasury_id),
                            charter_id: id_to_hex(&e.charter_id),
                            freeze_id: id_to_hex(&e.emergency_freeze_id),
                            cap_vault_id: id_to_hex(&e.capability_vault_id),
                            creator: id_to_hex(&e.creator),
                            created_at_ms: ts,
                            destroyed_at_ms: None,
                            successor_dao_id: None,
                        })),
                        Err(e) => {
                            tracing::warn!("Failed to deserialize DAOCreated: {e}");
                        }
                    },
                    "DAODestroyed" => match bcs::from_bytes::<DAODestroyed>(&event.contents) {
                        Ok(e) => mutations.push(DaoMutation::Destroy {
                            dao_id: id_to_hex(&e.dao_id),
                            destroyed_at_ms: ts,
                            successor_dao_id: if is_zero_id(&e.successor_dao_id) {
                                None
                            } else {
                                Some(id_to_hex(&e.successor_dao_id))
                            },
                        }),
                        Err(e) => {
                            tracing::warn!("Failed to deserialize DAODestroyed: {e}");
                        }
                    },
                    _ => {}
                }
            }
        }

        Ok(mutations)
    }
}

#[async_trait]
impl Handler for DaoHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        let mut n = 0usize;

        let inserts: Vec<&Dao> = values
            .iter()
            .filter_map(|v| {
                if let DaoMutation::Insert(d) = v {
                    Some(d)
                } else {
                    None
                }
            })
            .collect();

        if !inserts.is_empty() {
            let count = inserts.len();
            diesel::insert_into(daos::table)
                .values(inserts)
                .on_conflict_do_nothing()
                .execute(conn)
                .await?;
            n += count;
        }

        for v in values {
            if let DaoMutation::Destroy {
                dao_id,
                destroyed_at_ms,
                successor_dao_id,
            } = v
            {
                diesel::update(daos::table.filter(daos::dao_id.eq(dao_id)))
                    .set((
                        daos::destroyed_at_ms.eq(destroyed_at_ms),
                        daos::successor_dao_id.eq(successor_dao_id),
                    ))
                    .execute(conn)
                    .await?;
                n += 1;
            }
        }

        Ok(n)
    }
}
