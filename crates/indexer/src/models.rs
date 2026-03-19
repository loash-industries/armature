/// Move event structs mirrored for BCS deserialization.
///
/// Field order and types must exactly match the Move struct layout.
/// Sui `ID` / `address` = 32-byte fixed array in BCS.
/// Move `String` / `std::ascii::String` = length-prefixed bytes in BCS → Rust `String`.
use serde::Deserialize;

pub type SuiId = [u8; 32];

pub fn id_to_hex(id: &SuiId) -> String {
    format!("0x{}", hex::encode(id))
}

// ── armature::dao ────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct DAOCreated {
    pub dao_id: SuiId,
    pub treasury_id: SuiId,
    pub capability_vault_id: SuiId,
    pub charter_id: SuiId,
    pub emergency_freeze_id: SuiId,
    pub creator: SuiId,
}

// ── armature::proposal ───────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct ProposalCreated {
    pub proposal_id: SuiId,
    pub dao_id: SuiId,
    pub type_key: String,
    pub proposer: SuiId,
}

#[derive(Debug, Deserialize)]
pub struct VoteCast {
    pub proposal_id: SuiId,
    pub dao_id: SuiId,
    pub voter: SuiId,
    pub approve: bool,
    pub weight: u64,
}

#[derive(Debug, Deserialize)]
pub struct ProposalPassed {
    pub proposal_id: SuiId,
    pub dao_id: SuiId,
    pub yes_weight: u64,
    pub no_weight: u64,
}

#[derive(Debug, Deserialize)]
pub struct ProposalExecuted {
    pub proposal_id: SuiId,
    pub dao_id: SuiId,
    pub executor: SuiId,
}

#[derive(Debug, Deserialize)]
pub struct ProposalExpired {
    pub proposal_id: SuiId,
    pub dao_id: SuiId,
}

// ── armature::treasury_vault ─────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct CoinDeposited {
    pub vault_id: SuiId,
    pub dao_id: SuiId,
    pub coin_type: String,
    pub amount: u64,
    pub depositor: SuiId,
}

#[derive(Debug, Deserialize)]
pub struct CoinWithdrawn {
    pub vault_id: SuiId,
    pub dao_id: SuiId,
    pub coin_type: String,
    pub amount: u64,
    pub recipient: SuiId,
}

#[derive(Debug, Deserialize)]
pub struct CoinClaimed {
    pub vault_id: SuiId,
    pub dao_id: SuiId,
    pub coin_type: String,
    pub amount: u64,
    pub claimer: SuiId,
}

// ── armature::emergency ───────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct TypeFrozen {
    pub dao_id: SuiId,
    pub type_key: String,
    pub expiry_ms: u64,
}

#[derive(Debug, Deserialize)]
pub struct TypeUnfrozen {
    pub dao_id: SuiId,
    pub type_key: String,
}
