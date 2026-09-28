module armature_proposals::burn_coin;

use std::internal::{Self, Permit};

/// Burn `amount` of `Coin<T>` using the DAO's custodied `TreasuryCap<T>`.
/// The burned coins are withdrawn from the DAO's `TreasuryVault` — the clean,
/// accountable source — so supply contraction goes through the same balance
/// the spend proposals draw from.
public struct BurnCoin<phantom T> has drop, store {
    treasury_cap_id: ID,
    amount: u64,
}

// === Constructor ===

public fun new<T>(treasury_cap_id: ID, amount: u64): BurnCoin<T> {
    BurnCoin { treasury_cap_id, amount }
}

// === Accessors ===

public fun treasury_cap_id<T>(self: &BurnCoin<T>): ID { self.treasury_cap_id }

public fun amount<T>(self: &BurnCoin<T>): u64 { self.amount }

// === Handler authority ===

/// `Permit<BurnCoin>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<BurnCoin>` (see `proposal::ticket_request`).
public(package) fun permit<T>(): Permit<BurnCoin<T>> { internal::permit() }
