module armature_proposals::send_coin_to_ou;

use std::internal::{Self, Permit};

/// Transfer amount of Coin<T> from treasury to another OU's TreasuryVault.
public struct SendCoinToOU<phantom T> has drop, store {
    recipient_treasury: ID,
    amount: u64,
}

// === Constructor ===

public fun new<T>(recipient_treasury: ID, amount: u64): SendCoinToOU<T> {
    SendCoinToOU { recipient_treasury, amount }
}

// === Accessors ===

public fun recipient_treasury<T>(self: &SendCoinToOU<T>): ID { self.recipient_treasury }

public fun amount<T>(self: &SendCoinToOU<T>): u64 { self.amount }

// === Handler authority ===

/// `Permit<SendCoinToOU>` for this package's handler: the only way to spend or close
/// an `ExecutionTicket<SendCoinToOU>` (see `proposal::ticket_request`).
public(package) fun permit<T>(): Permit<SendCoinToOU<T>> { internal::permit() }
