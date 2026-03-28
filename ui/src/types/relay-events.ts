/**
 * TypeScript shapes for relay-sdk `decoded_fields` on every armature event.
 *
 * Rule: u64/u128/u256 fields arrive as `string` (exceeds Number.MAX_SAFE_INTEGER).
 *       u8/u16/u32 arrive as `number`. Addresses and IDs arrive as `string`.
 */

// ─── armature_framework ─────────────────────────────────────────────────────

// armature::dao
export interface DAOCreatedFields {
  dao_id: string
  treasury_id: string
  capability_vault_id: string
  charter_id: string
  emergency_freeze_id: string
  creator: string
}

export interface DAODestroyedFields {
  dao_id: string
  successor_dao_id: string
}

// armature::proposal
export interface ProposalCreatedFields {
  proposal_id: string
  dao_id: string
  type_key: string
  proposer: string
}

export interface VoteCastFields {
  proposal_id: string
  dao_id: string
  voter: string
  approve: boolean
  weight: string // u64
}

export interface ProposalPassedFields {
  proposal_id: string
  dao_id: string
  yes_weight: string // u64
  no_weight: string // u64
}

export interface ProposalExecutedFields {
  proposal_id: string
  dao_id: string
  executor: string
}

export interface ProposalExpiredFields {
  proposal_id: string
  dao_id: string
}

// armature::emergency
export interface TypeFrozenFields {
  dao_id: string
  type_key: string
  expiry_ms: string // u64
}

export interface TypeUnfrozenFields {
  dao_id: string
  type_key: string
}

export interface FreezeExemptTypeAddedFields {
  dao_id: string
  type_key: string
}

export interface FreezeExemptTypeRemovedFields {
  dao_id: string
  type_key: string
}

// armature::treasury_vault
//
// NOTE: Move's `std::ascii::String` / `std::string::String` serialises over
// the wire as `{ bytes: number[] }` (BCS), not a plain string.  Use
// `decodeMoveString()` from `@/lib/utils` before treating `coin_type` as a
// string.
export interface CoinDepositedFields {
  vault_id: string
  dao_id: string
  coin_type: string | { bytes: number[] }
  amount: string // u64
  depositor: string
}

export interface CoinWithdrawnFields {
  vault_id: string
  dao_id: string
  coin_type: string | { bytes: number[] }
  amount: string // u64
  recipient: string
}

export interface CoinClaimedFields {
  vault_id: string
  dao_id: string
  coin_type: string | { bytes: number[] }
  amount: string // u64
  claimer: string
}

// ─── armature_proposals ─────────────────────────────────────────────────────

// armature_proposals::board_ops
export interface BoardUpdatedFields {
  dao_id: string
  new_members: string[]
}

// armature_proposals::admin_ops
export interface ProposalTypeDisabledFields {
  dao_id: string
  type_key: string
}

export interface ProposalTypeEnabledFields {
  dao_id: string
  type_key: string
}

export interface ProposalConfigUpdatedFields {
  dao_id: string
  target_type_key: string
}

export interface MetadataUpdatedFields {
  dao_id: string
  new_ipfs_cid: string
}

// armature_proposals::subdao_ops
export interface CapTransferredToSubDAOFields {
  dao_id: string
  cap_id: string
  target_vault: string
}

export interface CapReclaimedFromSubDAOFields {
  dao_id: string
  cap_id: string
  subdao_id: string
}

export interface SubDAOCreatedFields {
  controller_dao_id: string
  subdao_id: string
  control_cap_id: string
}

export interface SubDAOExecutionPausedFields {
  dao_id: string
}

export interface SubDAOExecutionUnpausedFields {
  dao_id: string
}

export interface SuccessorDAOSpawnedFields {
  origin_dao_id: string
  successor_dao_id: string
}

export interface SubDAOSpunOutFields {
  controller_dao_id: string
  subdao_id: string
}

export interface AssetsTransferInitiatedFields {
  dao_id: string
  target_dao_id: string
  coin_count: string // u64
  cap_count: string  // u64
}

// armature_proposals::security_ops
export interface FreezeAdminTransferredFields {
  dao_id: string
  new_admin: string
}

export interface FreezeConfigUpdatedFields {
  dao_id: string
  new_max_freeze_duration_ms: string // u64
}

// armature_proposals::treasury_ops
export interface CoinSentFields {
  dao_id: string
  coin_type: string
  amount: string // u64
  recipient: string
}

export interface CoinSentToDAOFields {
  dao_id: string
  coin_type: string
  amount: string // u64
  target_treasury: string
}

export interface SmallPaymentSentFields {
  dao_id: string
  coin_type: string
  amount: string     // u64
  recipient: string
  epoch_spend: string    // u64
  max_epoch_spend: string // u64
}

// armature_proposals::upgrade_ops
export interface UpgradeAuthorizedFields {
  dao_id: string
  cap_id: string
  package_id: string
  policy: number // u8
}
