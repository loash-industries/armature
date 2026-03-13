module armature::treasury_vault;

use armature::proposal::ExecutionRequest;
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use sui::dynamic_field as df;
use sui::event;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EInsufficientBalance: u64 = 0;
const EDAOIdMismatch: u64 = 1;

// === Events ===

/// Emitted when a coin directly transferred to the vault is claimed.
public struct CoinClaimed has copy, drop {
    vault_id: ID,
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    claimer: address,
}

// === Structs ===

/// Multi-coin treasury vault. Stores `Balance<T>` as dynamic fields keyed by type name.
/// Created as a shared object during DAO creation.
public struct TreasuryVault has key, store {
    id: UID,
    dao_id: ID,
    coin_types: VecSet<std::ascii::String>,
}

// === Constructor ===

/// Create a new empty TreasuryVault. Only callable within the framework package.
public(package) fun new(dao_id: ID, ctx: &mut TxContext): TreasuryVault {
    TreasuryVault {
        id: object::new(ctx),
        dao_id,
        coin_types: vec_set::empty(),
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
public fun deposit<T>(self: &mut TreasuryVault, coin: Coin<T>) {
    let amount = coin.value();
    if (amount == 0) {
        coin.destroy_zero();
        return
    };

    let type_key = std::type_name::with_original_ids<T>().into_string();

    if (df::exists_(&self.id, type_key)) {
        // Join with existing balance
        let existing: &mut Balance<T> = df::borrow_mut(&mut self.id, type_key);
        existing.join(coin.into_balance());
    } else {
        // Add new balance and register the type
        df::add(&mut self.id, type_key, coin.into_balance());
        self.coin_types.insert(type_key);
    };
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

    // Zero-balance cleanup
    if (bal.value() == 0) {
        let remaining: Balance<T> = df::remove(&mut self.id, type_key);
        remaining.destroy_zero();
        self.coin_types.remove(&type_key);
    };

    coin::from_balance(withdrawn, ctx)
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

    // Deposit the claimed coin
    self.deposit(coin);
}

// === Accessors ===

/// Returns the DAO ID this vault belongs to.
public fun dao_id(self: &TreasuryVault): ID { self.dao_id }

/// Returns the set of coin type names currently held.
public fun coin_types(self: &TreasuryVault): &VecSet<std::ascii::String> { &self.coin_types }

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

/// Returns true if the vault holds no coin balances.
public fun is_empty(self: &TreasuryVault): bool {
    self.coin_types.is_empty()
}

/// Destroy an empty TreasuryVault. Aborts if the vault still holds coins.
public(package) fun destroy_empty(vault: TreasuryVault) {
    let TreasuryVault { id, dao_id: _, coin_types } = vault;
    assert!(coin_types.is_empty(), EInsufficientBalance);
    id.delete();
}
