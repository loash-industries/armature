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

use armature_schema::schema::{freeze_exempt_types, frozen_types};

use crate::models::{
    id_to_hex, FreezeExemptTypeAdded, FreezeExemptTypeRemoved, TypeFrozen, TypeUnfrozen,
};
use crate::{is_armature_event, parse_package_addresses};

pub enum EmergencyMutation {
    Freeze {
        dao_id: String,
        type_key: String,
        frozen_until_ms: i64,
    },
    Unfreeze {
        dao_id: String,
        type_key: String,
    },
    AddExempt {
        dao_id: String,
        type_key: String,
    },
    RemoveExempt {
        dao_id: String,
        type_key: String,
    },
}

// Max fields across variants = 3 (Freeze).
impl FieldCount for EmergencyMutation {
    const FIELD_COUNT: usize = 3;
}

pub struct EmergencyHandler {
    packages: Vec<AccountAddress>,
}

impl EmergencyHandler {
    pub fn new(package_ids: &[String]) -> Self {
        Self {
            packages: parse_package_addresses(package_ids),
        }
    }
}

#[async_trait]
impl Processor for EmergencyHandler {
    const NAME: &'static str = "emergency";
    type Value = EmergencyMutation;

    async fn process(&self, checkpoint: &Arc<Checkpoint>) -> Result<Vec<Self::Value>> {
        let mut mutations = vec![];

        for tx in &checkpoint.transactions {
            let Some(events) = &tx.events else { continue };
            for event in &events.data {
                if !is_armature_event(&event.type_, &self.packages) {
                    continue;
                }
                if event.type_.module.as_str() != "emergency" {
                    continue;
                }

                match event.type_.name.as_str() {
                    "TypeFrozen" => match bcs::from_bytes::<TypeFrozen>(&event.contents) {
                        Ok(e) => mutations.push(EmergencyMutation::Freeze {
                            dao_id: id_to_hex(&e.dao_id),
                            type_key: e.type_key,
                            frozen_until_ms: e.expiry_ms as i64,
                        }),
                        Err(e) => tracing::warn!("Failed to deserialize TypeFrozen: {e}"),
                    },
                    "TypeUnfrozen" => match bcs::from_bytes::<TypeUnfrozen>(&event.contents) {
                        Ok(e) => mutations.push(EmergencyMutation::Unfreeze {
                            dao_id: id_to_hex(&e.dao_id),
                            type_key: e.type_key,
                        }),
                        Err(e) => tracing::warn!("Failed to deserialize TypeUnfrozen: {e}"),
                    },
                    "FreezeExemptTypeAdded" => {
                        match bcs::from_bytes::<FreezeExemptTypeAdded>(&event.contents) {
                            Ok(e) => mutations.push(EmergencyMutation::AddExempt {
                                dao_id: id_to_hex(&e.dao_id),
                                type_key: e.type_key,
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize FreezeExemptTypeAdded: {e}")
                            }
                        }
                    }
                    "FreezeExemptTypeRemoved" => {
                        match bcs::from_bytes::<FreezeExemptTypeRemoved>(&event.contents) {
                            Ok(e) => mutations.push(EmergencyMutation::RemoveExempt {
                                dao_id: id_to_hex(&e.dao_id),
                                type_key: e.type_key,
                            }),
                            Err(e) => {
                                tracing::warn!("Failed to deserialize FreezeExemptTypeRemoved: {e}")
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
impl Handler for EmergencyHandler {
    async fn commit<'a>(values: &[Self::Value], conn: &mut Connection<'a>) -> Result<usize> {
        let mut n = 0usize;

        for v in values {
            match v {
                EmergencyMutation::Freeze {
                    dao_id,
                    type_key,
                    frozen_until_ms,
                } => {
                    diesel::insert_into(frozen_types::table)
                        .values((
                            frozen_types::dao_id.eq(dao_id),
                            frozen_types::type_key.eq(type_key),
                            frozen_types::frozen_until_ms.eq(frozen_until_ms),
                        ))
                        .on_conflict((frozen_types::dao_id, frozen_types::type_key))
                        .do_update()
                        .set(frozen_types::frozen_until_ms.eq(frozen_until_ms))
                        .execute(conn)
                        .await?;
                    n += 1;
                }
                EmergencyMutation::Unfreeze { dao_id, type_key } => {
                    diesel::delete(
                        frozen_types::table
                            .filter(frozen_types::dao_id.eq(dao_id))
                            .filter(frozen_types::type_key.eq(type_key)),
                    )
                    .execute(conn)
                    .await?;
                    n += 1;
                }
                EmergencyMutation::AddExempt { dao_id, type_key } => {
                    diesel::insert_into(freeze_exempt_types::table)
                        .values((
                            freeze_exempt_types::dao_id.eq(dao_id),
                            freeze_exempt_types::type_key.eq(type_key),
                        ))
                        .on_conflict_do_nothing()
                        .execute(conn)
                        .await?;
                    n += 1;
                }
                EmergencyMutation::RemoveExempt { dao_id, type_key } => {
                    diesel::delete(
                        freeze_exempt_types::table
                            .filter(freeze_exempt_types::dao_id.eq(dao_id))
                            .filter(freeze_exempt_types::type_key.eq(type_key)),
                    )
                    .execute(conn)
                    .await?;
                    n += 1;
                }
            }
        }

        Ok(n)
    }
}
