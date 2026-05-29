#[allow(deprecated_usage)]
module armature::treasury_vault;

use armature::proposal::ExecutionRequest;
use multicoin::multicoin::{Self, Balance as MultiCoinBalance};
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use sui::dynamic_field as df;
use sui::dynamic_object_field as dof;
use sui::event;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EInsufficientBalance: u64 = 0;
const EDAOIdMismatch: u64 = 1;
const EVaultNotEmpty: u64 = 2;

// === Events ===

/// Emitted when a coin is deposited into the vault.
public struct CoinDeposited has copy, drop {
    vault_id: ID,
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    depositor: address,
}

/// Emitted when a coin is withdrawn from the vault via a proposal execution.
public struct CoinWithdrawn has copy, drop {
    vault_id: ID,
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    recipient: address,
}

/// Emitted when a coin directly transferred to the vault is claimed.
public struct CoinClaimed has copy, drop {
    vault_id: ID,
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    claimer: address,
}

/// Emitted when a multicoin balance is deposited into the vault.
public struct MultiCoinDeposited has copy, drop {
    vault_id: ID,
    dao_id: ID,
    collection_id: ID,
    asset_id: u64,
    amount: u64,
    depositor: address,
}

/// Emitted when a multicoin balance is withdrawn from the vault via a proposal execution.
public struct MultiCoinWithdrawn has copy, drop {
    vault_id: ID,
    dao_id: ID,
    collection_id: ID,
    asset_id: u64,
    amount: u64,
    recipient: address,
}

// === Structs ===

/// DOF key used on TreasuryVault to look up a CollectionRecord by collection ID.
public struct CollectionKey has copy, drop, store {
    collection_id: ID,
}

/// DOF key used on CollectionRecord to look up a MultiCoinBalance by asset ID.
public struct AssetKey has copy, drop, store {
    asset_id: u64,
}

/// Per-collection sub-object stored as a DOF on TreasuryVault.
/// Holds one MultiCoinBalance DOF per distinct asset_id.
/// RPC: sui_getDynamicFields(collection_record_id) enumerates all assets in this collection.
public struct CollectionRecord has key, store {
    id: UID,
    collection_id: ID,
    item_count: u64,
}

/// Multi-coin treasury vault.
/// Coin balances: dynamic fields keyed by type name string.
/// Multicoin balances: two-level DOF tree — CollectionRecord per collection_id,
///   MultiCoinBalance per asset_id within each CollectionRecord.
/// Created as a shared object during DAO creation.
public struct TreasuryVault has key, store {
    id: UID,
    dao_id: ID,
    coin_types: VecSet<std::ascii::String>,
    multicoin_collection_count: u64,
}

// === Constructor ===

/// Create a new empty TreasuryVault. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): TreasuryVault {
    TreasuryVault {
        id: object::new(ctx),
        dao_id,
        coin_types: vec_set::empty(),
        multicoin_collection_count: 0,
    }
}

/// Share the vault as a shared object.
#[allow(lint(share_owned, custom_state_change))]
public(package) fun share(vault: TreasuryVault) {
    transfer::share_object(vault);
}

// === Public operations ===

/// Deposit a coin into the vault. Permissionless — anyone can deposit.
/// Zero-value coins are destroyed as a no-op.
public fun deposit<T>(self: &mut TreasuryVault, coin: Coin<T>, ctx: &mut TxContext) {
    let amount = coin.value();
    if (amount == 0) {
        coin.destroy_zero();
        return
    };

    let type_key = std::type_name::with_original_ids<T>().into_string();

    if (df::exists_(&self.id, type_key)) {
        let existing: &mut Balance<T> = df::borrow_mut(&mut self.id, type_key);
        existing.join(coin.into_balance());
    } else {
        df::add(&mut self.id, type_key, coin.into_balance());
        self.coin_types.insert(type_key);
    };

    event::emit(CoinDeposited {
        vault_id: object::uid_to_inner(&self.id),
        dao_id: self.dao_id,
        coin_type: type_key,
        amount,
        depositor: ctx.sender(),
    });
}

/// Withdraw a coin from the vault. Requires an `ExecutionRequest`.
/// If the withdrawal drains the balance to zero, the dynamic field and registry entry are removed.
public fun withdraw<T, P>(
    self: &mut TreasuryVault,
    amount: u64,
    req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(self.dao_id == req.req_dao_id(), EDAOIdMismatch);
    let type_key = std::type_name::with_original_ids<T>().into_string();

    assert!(
        df::exists_(&self.id, type_key) && {
            let bal: &Balance<T> = df::borrow(&self.id, type_key);
            bal.value() >= amount
        },
        EInsufficientBalance,
    );

    let bal: &mut Balance<T> = df::borrow_mut(&mut self.id, type_key);
    let withdrawn = bal.split(amount);

    if (bal.value() == 0) {
        let remaining: Balance<T> = df::remove(&mut self.id, type_key);
        remaining.destroy_zero();
        self.coin_types.remove(&type_key);
    };

    let coin = coin::from_balance(withdrawn, ctx);

    event::emit(CoinWithdrawn {
        vault_id: object::uid_to_inner(&self.id),
        dao_id: self.dao_id,
        coin_type: type_key,
        amount,
        recipient: ctx.sender(),
    });

    coin
}

/// Claim a coin that was directly transferred to the vault's address.
/// This recovers coins sent via `transfer::public_transfer` to the vault.
/// Permissionless — anyone can trigger the claim, but the coin goes into the vault.
public fun claim_coin<T>(
    self: &mut TreasuryVault,
    coin_to_claim: transfer::Receiving<Coin<T>>,
    ctx: &mut TxContext,
) {
    let coin: Coin<T> = transfer::public_receive(&mut self.id, coin_to_claim);
    let amount = coin.value();
    let type_key = std::type_name::with_original_ids<T>().into_string();

    event::emit(CoinClaimed {
        vault_id: object::uid_to_inner(&self.id),
        dao_id: self.dao_id,
        coin_type: type_key,
        amount,
        claimer: ctx.sender(),
    });

    self.deposit(coin, ctx);
}

/// Deposit a multicoin balance into the vault. Permissionless — anyone can deposit.
/// Zero-value balances are destroyed as a no-op.
///
/// Storage layout:
///   TreasuryVault --dof[CollectionKey]--> CollectionRecord --dof[AssetKey]--> MultiCoinBalance
///
/// RPC enumeration:
///   All assets in a collection: sui_getDynamicFields(collection_record_id)
///   All collections: sui_getDynamicFields(treasury_vault_id) filtered by key type CollectionKey
public fun deposit_multicoin(
    self: &mut TreasuryVault,
    balance: MultiCoinBalance,
    ctx: &mut TxContext,
) {
    let amount = balance.value();
    if (amount == 0) {
        multicoin::destroy_zero(balance);
        return
    };

    let collection_id = balance.collection_id();
    let asset_id = balance.asset_id();
    let coll_key = CollectionKey { collection_id };
    let asset_key = AssetKey { asset_id };

    if (!dof::exists_(&self.id, coll_key)) {
        let record = CollectionRecord {
            id: object::new(ctx),
            collection_id,
            item_count: 0,
        };
        dof::add(&mut self.id, coll_key, record);
        self.multicoin_collection_count = self.multicoin_collection_count + 1;
    };

    let record: &mut CollectionRecord = dof::borrow_mut(&mut self.id, coll_key);

    if (dof::exists_(&record.id, asset_key)) {
        let existing: &mut MultiCoinBalance = dof::borrow_mut(&mut record.id, asset_key);
        existing.join(balance, ctx);
    } else {
        dof::add(&mut record.id, asset_key, balance);
        record.item_count = record.item_count + 1;
    };

    event::emit(MultiCoinDeposited {
        vault_id: object::uid_to_inner(&self.id),
        dao_id: self.dao_id,
        collection_id,
        asset_id,
        amount,
        depositor: ctx.sender(),
    });
}

/// Withdraw a multicoin balance from the vault. Requires an `ExecutionRequest`.
/// Cleans up the AssetKey DOF when balance reaches zero, and the CollectionRecord
/// when its last asset is removed.
public fun withdraw_multicoin<P>(
    self: &mut TreasuryVault,
    collection_id: ID,
    asset_id: u64,
    amount: u64,
    req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): MultiCoinBalance {
    assert!(self.dao_id == req.req_dao_id(), EDAOIdMismatch);

    let coll_key = CollectionKey { collection_id };
    let asset_key = AssetKey { asset_id };

    assert!(
        dof::exists_(&self.id, coll_key) && {
            let record: &CollectionRecord = dof::borrow(&self.id, coll_key);
            dof::exists_(&record.id, asset_key) && {
                let bal: &MultiCoinBalance = dof::borrow(&record.id, asset_key);
                bal.value() >= amount
            }
        },
        EInsufficientBalance,
    );

    let record: &mut CollectionRecord = dof::borrow_mut(&mut self.id, coll_key);
    let bal: &mut MultiCoinBalance = dof::borrow_mut(&mut record.id, asset_key);
    let withdrawn = bal.split(amount, ctx);
    let asset_empty = bal.value() == 0;

    if (asset_empty) {
        let remaining: MultiCoinBalance = dof::remove(&mut record.id, asset_key);
        multicoin::destroy_zero(remaining);
        record.item_count = record.item_count - 1;
    };

    let collection_empty = record.item_count == 0;

    if (collection_empty) {
        let CollectionRecord { id: record_id, collection_id: _, item_count: _ } = dof::remove(
            &mut self.id,
            coll_key,
        );
        record_id.delete();
        self.multicoin_collection_count = self.multicoin_collection_count - 1;
    };

    event::emit(MultiCoinWithdrawn {
        vault_id: object::uid_to_inner(&self.id),
        dao_id: self.dao_id,
        collection_id,
        asset_id,
        amount,
        recipient: ctx.sender(),
    });

    withdrawn
}

// === Accessors ===

/// Returns the DAO ID this vault belongs to.
public fun dao_id(self: &TreasuryVault): ID { self.dao_id }

/// Returns the set of coin type names currently held.
public fun coin_types(self: &TreasuryVault): &VecSet<std::ascii::String> { &self.coin_types }

/// Returns the number of distinct collections currently held.
public fun multicoin_collection_count(self: &TreasuryVault): u64 {
    self.multicoin_collection_count
}

/// Returns the balance of coin type T, or 0 if not present.
public fun balance<T>(self: &TreasuryVault): u64 {
    let type_key = std::type_name::with_original_ids<T>().into_string();
    if (df::exists_(&self.id, type_key)) {
        let bal: &Balance<T> = df::borrow(&self.id, type_key);
        bal.value()
    } else {
        0
    }
}

/// Returns the balance of a specific multicoin asset, or 0 if not present.
public fun multicoin_balance(self: &TreasuryVault, collection_id: ID, asset_id: u64): u64 {
    let coll_key = CollectionKey { collection_id };
    let asset_key = AssetKey { asset_id };
    if (dof::exists_(&self.id, coll_key)) {
        let record: &CollectionRecord = dof::borrow(&self.id, coll_key);
        if (dof::exists_(&record.id, asset_key)) {
            let bal: &MultiCoinBalance = dof::borrow(&record.id, asset_key);
            bal.value()
        } else {
            0
        }
    } else {
        0
    }
}

/// Returns the number of distinct asset IDs held for a collection, or 0 if not present.
public fun collection_item_count(self: &TreasuryVault, collection_id: ID): u64 {
    let coll_key = CollectionKey { collection_id };
    if (dof::exists_(&self.id, coll_key)) {
        let record: &CollectionRecord = dof::borrow(&self.id, coll_key);
        record.item_count
    } else {
        0
    }
}

/// Returns true if the vault holds no coin or multicoin balances.
public fun is_empty(self: &TreasuryVault): bool {
    self.coin_types.is_empty() && self.multicoin_collection_count == 0
}

/// Destroy an empty TreasuryVault. Aborts with `EVaultNotEmpty` if the
/// vault still holds any coin or multicoin balances.
public(package) fun destroy_empty(vault: TreasuryVault) {
    let TreasuryVault { id, dao_id: _, coin_types, multicoin_collection_count } = vault;
    assert!(coin_types.is_empty(), EVaultNotEmpty);
    assert!(multicoin_collection_count == 0, EVaultNotEmpty);
    id.delete();
}
