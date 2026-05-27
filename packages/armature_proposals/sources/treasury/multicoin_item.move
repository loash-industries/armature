module armature_proposals::multicoin_item;

/// A single (collection, asset, amount) entry used in batch multicoin proposals.
public struct MultiCoinItem has copy, drop, store {
    collection_id: ID,
    asset_id: u64,
    amount: u64,
}

// === Constructor ===

public fun new(collection_id: ID, asset_id: u64, amount: u64): MultiCoinItem {
    MultiCoinItem { collection_id, asset_id, amount }
}

// === Accessors ===

public fun collection_id(self: &MultiCoinItem): ID { self.collection_id }

public fun asset_id(self: &MultiCoinItem): u64 { self.asset_id }

public fun amount(self: &MultiCoinItem): u64 { self.amount }
