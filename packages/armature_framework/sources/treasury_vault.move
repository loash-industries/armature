#[allow(deprecated_usage)]
module armature::treasury_vault;

use armature::permissions;
use armature::proposal::ExecutionRequest;
use armature::version;
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use sui::dynamic_field as df;
use sui::event;
use sui::vec_set::{Self, VecSet};

// === Errors ===

const EInsufficientBalance: u64 = 0;
const EOUIdMismatch: u64 = 1;
const EVaultNotEmpty: u64 = 2;

// === Events ===

/// Emitted when a coin is deposited into the vault.
public struct CoinDeposited has copy, drop {
    vault_id: ID,
    ou_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    depositor: address,
}

/// Emitted when a coin is withdrawn from the vault via a proposal execution.
public struct CoinWithdrawn has copy, drop {
    vault_id: ID,
    ou_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    recipient: address,
}

/// Emitted when a coin directly transferred to the vault is claimed.
public struct CoinClaimed has copy, drop {
    vault_id: ID,
    ou_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    claimer: address,
}

// === Structs ===

/// Multi-coin treasury vault.
/// Coin balances: dynamic fields keyed by type name string.
/// Created as a shared object during OU creation.
public struct TreasuryVault has key, store {
    id: UID,
    ou_id: ID,
    coin_types: VecSet<std::ascii::String>,
    /// Version floor (see `version`): its OU's floor at creation.
    min_version: u64,
}

// === Constructor ===

/// Create a new empty TreasuryVault. Only callable within the framework package.
public(package) fun new(ou_id: ID, min_version: u64, ctx: &mut TxContext): TreasuryVault {
    TreasuryVault {
        id: object::new(ctx),
        ou_id,
        coin_types: vec_set::empty(),
        min_version,
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
    self.check_version_mut();
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
        ou_id: self.ou_id,
        coin_type: type_key,
        amount,
        depositor: ctx.sender(),
    });
}

/// Withdraw a coin from the vault. Requires an `ExecutionRequest`.
/// If the withdrawal drains the balance to zero, the dynamic field and registry entry are removed.
/// Requires TREASURY_WITHDRAW (`proposal::assert_permitted`).
public fun withdraw<T, P>(
    self: &mut TreasuryVault,
    amount: u64,
    req: &ExecutionRequest<P>,
    ctx: &mut TxContext,
): Coin<T> {
    self.check_version_mut();
    req.check_request_version();
    assert!(self.ou_id == req.req_ou_id(), EOUIdMismatch);
    req.assert_permitted(permissions::treasury_withdraw());
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
        ou_id: self.ou_id,
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
    self.check_version_mut();
    let coin: Coin<T> = transfer::public_receive(&mut self.id, coin_to_claim);
    let amount = coin.value();
    let type_key = std::type_name::with_original_ids<T>().into_string();

    event::emit(CoinClaimed {
        vault_id: object::uid_to_inner(&self.id),
        ou_id: self.ou_id,
        coin_type: type_key,
        amount,
        claimer: ctx.sender(),
    });

    self.deposit(coin, ctx);
}

// === Accessors ===

/// Returns the OU ID this vault belongs to.
public fun ou_id(self: &TreasuryVault): ID { self.ou_id }

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

/// Destroy an empty TreasuryVault. Aborts with `EVaultNotEmpty` if the
/// vault still holds any coin balances.
public(package) fun destroy_empty(vault: TreasuryVault) {
    let TreasuryVault { id, ou_id: _, coin_types, min_version: _ } = vault;
    assert!(coin_types.is_empty(), EVaultNotEmpty);
    id.delete();
}

// === Version gate (ARMATURE-45, see `version`) ===

/// The oldest framework version allowed to act on this TreasuryVault.
public fun min_version(self: &TreasuryVault): u64 { self.min_version }

/// Raise this TreasuryVault's floor to the running release's `MIN_SUPPORTED`. Anyone
/// may call it; it never lowers the floor. Run by the sweep after a security
/// upgrade.
public fun enforce_version(self: &mut TreasuryVault) { self.check_version_mut() }

/// Abort `version::EVersionRetired` if this release is retired for `self`.
public(package) fun check_version(self: &TreasuryVault) {
    version::assert_supported(self.min_version)
}

/// `check_version`, then raise the floor to `MIN_SUPPORTED`.
public(package) fun check_version_mut(self: &mut TreasuryVault) {
    self.min_version = version::check_and_raise(object::id(self), self.min_version);
}

#[test_only]
public fun set_min_version_for_testing(self: &mut TreasuryVault, min_version: u64) {
    self.min_version = min_version;
}
