module armature_proposals::mint_coin;

/// Mint `amount` of `Coin<T>` using the DAO's custodied `TreasuryCap<T>`.
///
/// `recipient = none` mints into the DAO's own `TreasuryVault`, where existing
/// `SendCoin` / `SendSmallPayment` proposals handle distribution — this is the
/// common path for a sovereign currency the DAO spends through governance.
/// `recipient = some(addr)` issues directly to an address (e.g. a one-off
/// grant) without routing through the treasury.
public struct MintCoin<phantom T> has store {
    treasury_cap_id: ID,
    amount: u64,
    recipient: Option<address>,
}

// === Constructor ===

public fun new<T>(treasury_cap_id: ID, amount: u64, recipient: Option<address>): MintCoin<T> {
    MintCoin { treasury_cap_id, amount, recipient }
}

// === Accessors ===

public fun treasury_cap_id<T>(self: &MintCoin<T>): ID { self.treasury_cap_id }

public fun amount<T>(self: &MintCoin<T>): u64 { self.amount }

public fun recipient<T>(self: &MintCoin<T>): Option<address> { self.recipient }
