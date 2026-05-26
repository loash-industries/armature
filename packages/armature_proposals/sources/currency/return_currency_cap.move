module armature_proposals::return_currency_cap;

/// Relinquish custody of a `TreasuryCap<T>`: extract it from the DAO's
/// `CapabilityVault` and transfer it to `recipient`, dropping the currency
/// from the DAO's custody. The escape hatch / handoff path — without it a cap
/// would be locked in the vault forever, blocking sub-DAO spin-outs and
/// migrations. Vote-gated, symmetric to `AdoptCurrency`.
public struct ReturnCurrencyCap<phantom T> has drop, store {
    treasury_cap_id: ID,
    recipient: address,
}

// === Constructor ===

public fun new<T>(treasury_cap_id: ID, recipient: address): ReturnCurrencyCap<T> {
    ReturnCurrencyCap { treasury_cap_id, recipient }
}

// === Accessors ===

public fun treasury_cap_id<T>(self: &ReturnCurrencyCap<T>): ID { self.treasury_cap_id }

public fun recipient<T>(self: &ReturnCurrencyCap<T>): address { self.recipient }

public fun destroy<T>(self: ReturnCurrencyCap<T>) {
    let ReturnCurrencyCap { treasury_cap_id: _, recipient: _ } = self;
}
