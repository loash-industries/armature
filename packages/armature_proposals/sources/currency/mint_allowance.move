module armature_proposals::mint_allowance;

use std::internal::{Self, Permit};

/// Operational minting twin of `MintCoin`. Structurally identical, but kept as
/// a distinct type so a DAO can `EnableBypassType` on it (80% floor) to allow
/// minting *without a fresh vote each time*, while plain `MintCoin` stays
/// fully vote-gated. The bypass path is `currency_ops::mint_allowance_bypass`:
/// only an address on the DAO's `ConfigureMintAllowance<T>` allowlist may mint,
/// up to the configured per-call cap, throttled by the type's `cooldown_ms`.
/// `ticket_from_cap` takes `Permit<MintAllowance<T>>`, so that function is the
/// only place a bypass ticket for this type can be minted (ARMATURE-31).
///
/// This is the mint-side counterpart to `SendSmallPayment` on the spend side.
/// The per-call cap and cooldown are the only throttles; there is no per-epoch
/// budget. If one is ever wanted, the seam is a field on `MintAllowanceConfig`
/// checked in `mint_allowance_bypass`.
public struct MintAllowance<phantom T> has drop, store {
    treasury_cap_id: ID,
    amount: u64,
    recipient: Option<address>,
}

// === Constructor ===

public fun new<T>(treasury_cap_id: ID, amount: u64, recipient: Option<address>): MintAllowance<T> {
    MintAllowance { treasury_cap_id, amount, recipient }
}

// === Accessors ===

public fun treasury_cap_id<T>(self: &MintAllowance<T>): ID { self.treasury_cap_id }

public fun amount<T>(self: &MintAllowance<T>): u64 { self.amount }

public fun recipient<T>(self: &MintAllowance<T>): Option<address> { self.recipient }

// === Handler authority ===

/// `Permit<MintAllowance>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<MintAllowance>` (see `proposal::ticket_request`).
public(package) fun permit<T>(): Permit<MintAllowance<T>> { internal::permit() }
