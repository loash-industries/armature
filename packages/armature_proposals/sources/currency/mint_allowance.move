module armature_proposals::mint_allowance;

/// Operational minting twin of `MintCoin`. Structurally identical, but kept as
/// a distinct type so a DAO can `EnableBypassType` on it (80% floor) to allow
/// minting *without a fresh vote each time*, while plain `MintCoin` stays
/// fully vote-gated. The bypass path runs through the framework's
/// `ExternalExecutionCap<MintAllowance<T>>` (#141): an approved actor mints up
/// to `amount` per call, throttled by the proposal type's `cooldown_ms`.
///
/// This is the mint-side counterpart to `SendSmallPayment` on the spend side.
/// Note the deliberate asymmetry: `SendSmallPayment` enforces a per-epoch
/// budget via `SmallPaymentState`; this type does NOT — per the DAO's
/// governance-only policy choice, the cooldown plus per-call `amount` are the
/// only throttles. If enforced per-epoch mint budgets are ever wanted, the
/// seam is a `MintAllowanceState` type-state mirroring `SmallPaymentState`,
/// checked in `currency_ops::execute_mint_allowance`.
public struct MintAllowance<phantom T> has store {
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
