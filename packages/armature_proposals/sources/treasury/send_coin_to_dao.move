module armature_proposals::send_coin_to_dao;

/// Transfer amount of Coin<T> from treasury to another DAO's TreasuryVault.
public struct SendCoinToDAO<phantom T> has store {
    recipient_treasury: ID,
    amount: u64,
}

// === Constructor ===

public fun new<T>(recipient_treasury: ID, amount: u64): SendCoinToDAO<T> {
    SendCoinToDAO { recipient_treasury, amount }
}

// === Accessors ===

public fun recipient_treasury<T>(self: &SendCoinToDAO<T>): ID { self.recipient_treasury }

public fun amount<T>(self: &SendCoinToDAO<T>): u64 { self.amount }
