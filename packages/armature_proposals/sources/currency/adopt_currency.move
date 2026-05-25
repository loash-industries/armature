module armature_proposals::adopt_currency;

/// Take custody of a `TreasuryCap<T>` so the DAO can mint/burn `Coin<T>`.
///
/// The cap is NOT named in the payload: it is passed by value into the
/// execute handler within the same PTB, and its ID is derived there. The
/// `CapabilityVault` is the manifest of adopted currencies — its
/// `ids_for_type<TreasuryCap<T>>()` and `cap_types()` enumerate what the DAO
/// can mint, so no separate registry is kept.
///
/// Adoption is fully vote-gated — handing a DAO unilateral mint authority over
/// a currency is a governance-weight decision, and a vote-only entry avoids
/// the "anyone can shove an arbitrary cap into the vault" grief vector that a
/// permissionless entry would open. A DAO wanting frictionless adoption can
/// later `EnableBypassType` on this type through the sanctioned bypass path.
public struct AdoptCurrency<phantom T> has drop, store {}

// === Constructor ===

public fun new<T>(): AdoptCurrency<T> {
    AdoptCurrency {}
}
