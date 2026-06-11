/// DAO Receipt Vault — a DAO/OU-scoped accumulator for warehouse receipts.
///
/// A fork of `tribal_vault::tribe_vault` (loash-industries/warehouse-receipts)
/// where the access-control data source is **armature DAO identity** instead of
/// a raw in-game `tribe_id`. The vault structure, receipt storage, and flow are
/// otherwise identical: players mint standard `multicoin::Balance` receipts via
/// the warehouse_receipts package, then deposit them here; the vault accepts only
/// receipts from the SSU's specific collection (locked at initialization) and
/// accumulates balances per `asset_id` in dynamic object fields.
///
/// Access control (per RFC #153, confirmed by review):
///   - The canonical principal is `ctx.sender()` (decision (a)): a caller may
///     deposit/withdraw iff `ctx.sender()` is a board member of the bound DAO/OU.
///     We do NOT bind `character_address == sender` — DAO membership is
///     address-keyed, and the receipt is minted upstream against the character
///     in the same PTB.
///   - Roles are split per Hecate's design: deposits gate on `deposit_dao_id`,
///     withdrawals on `withdraw_dao_id`. Because the admins→officers→members
///     hierarchy is a data fact (a player is literally on each sub-DAO board),
///     binding each role to a different OU-DAO yields the cascade for free.
///     A single-DAO vault sets both ids to the same DAO.
///   - OU substitution is prevented by asserting the passed `&DAO`'s id equals
///     the bound `deposit_dao_id` / `withdraw_dao_id` before the membership check,
///     so a caller cannot swap in a different DAO they happen to be a member of.
///
/// Flow:
/// 1. Any deposit-OU member calls `initialize_dao_vault`, passing the SSU, the
///    deposit/withdraw OU DAOs, and the SSU's receipt collection_id — creates a
///    shared DaoReceiptVault and registers it. Reverts if a vault already exists
///    for this (SSU, deposit_dao) pair.
/// 2. A deposit-OU member calls `deposit_receipt(vault, deposit_dao, balance)` —
///    dao membership + collection_id validated, Balance merged into the pool.
/// 3. A withdraw-OU member calls `withdraw_receipt(vault, withdraw_dao, asset_id,
///    amount)` — dao membership checked, split Balance returned to caller.
///
/// The `multicoin` and `world` types used here MUST resolve to the same on-chain
/// packages as the warehouse_receipts package the receipts are minted from
/// (multicoin `c7a97f2`, world `8e2e97b`) — otherwise the `Balance` / `StorageUnit`
/// types diverge and receipts cannot be deposited. See RFC #153.
module armature_world_bridge::dao_receipt_vault;

use armature::dao::DAO;
use multicoin::multicoin::Balance;
use sui::{dynamic_object_field as dof, event, table::{Self, Table}};
use world::storage_unit::StorageUnit;

// === Errors ===

#[error(code = 0)]
const ENotDaoMember: vector<u8> =
    b"Sender is not a board member of this vault's bound DAO/OU — access denied";
#[error(code = 1)]
const EInsufficientVaultBalance: vector<u8> = b"Insufficient balance in DAO receipt vault";
#[error(code = 2)]
const EWrongCollection: vector<u8> =
    b"Receipt collection_id does not match this vault's collection";
#[error(code = 3)]
const EDaoVaultAlreadyExists: vector<u8> =
    b"A receipt vault already exists for this DAO at this storage unit";
#[error(code = 4)]
const EWrongDao: vector<u8> =
    b"Passed DAO does not match the vault's bound deposit/withdraw DAO";
#[error(code = 5)]
const EDaoNotActive: vector<u8> = b"Bound DAO is not active";

// === Structs ===

/// Composite key used in the registry table. Keyed by the *deposit* DAO, which
/// is the vault's primary scope (officers/members deposit, a higher OU withdraws).
public struct VaultKey has copy, drop, store {
    storage_unit_id: ID,
    deposit_dao_id: ID,
}

/// Shared singleton registry that maps (storage_unit_id, deposit_dao_id) →
/// vault_id. Enforces one vault per (SSU, deposit DAO). Created once by the
/// module initializer.
public struct DaoReceiptVaultRegistry has key {
    id: UID,
    vaults: Table<VaultKey, ID>,
}

/// Shared per-(StorageUnit, DAO) vault.
/// Accepts only receipts from `collection_id` (the SSU's receipt collection).
/// Per-asset balances are stored as dynamic object fields keyed by asset_id (u64).
///
/// `deposit_dao_id` and `withdraw_dao_id` may be the same DAO (symmetric access)
/// or different OUs in the same tribe hierarchy (role split).
public struct DaoReceiptVault has key {
    id: UID,
    deposit_dao_id: ID,
    withdraw_dao_id: ID,
    storage_unit_id: ID,
    collection_id: ID,
}

// === Module initializer ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(DaoReceiptVaultRegistry {
        id: object::new(ctx),
        vaults: table::new(ctx),
    });
}

// === Events ===

public struct DaoReceiptVaultInitializedEvent has copy, drop {
    vault_id: ID,
    deposit_dao_id: ID,
    withdraw_dao_id: ID,
    storage_unit_id: ID,
    collection_id: ID,
}

public struct DaoReceiptVaultDepositEvent has copy, drop {
    vault_id: ID,
    deposit_dao_id: ID,
    collection_id: ID,
    asset_id: u64,
    amount: u64,
    depositor: address,
}

public struct DaoReceiptVaultWithdrawEvent has copy, drop {
    vault_id: ID,
    withdraw_dao_id: ID,
    collection_id: ID,
    asset_id: u64,
    amount: u64,
    withdrawer: address,
}

// === Public Functions ===

/// Initialize a DAO receipt vault on a given StorageUnit.
/// `deposit_dao` is the OU whose members may deposit; `withdraw_dao` is the OU
/// whose members may withdraw. They may be the same DAO for symmetric access.
/// The caller must be a member of `deposit_dao`. Reverts if a vault for this
/// (SSU, deposit_dao) pair already exists — use `lookup` to check first.
/// `collection_id` must be the ID of the SSU's warehouse receipt Collection.
public fun initialize_dao_vault(
    registry: &mut DaoReceiptVaultRegistry,
    storage_unit: &StorageUnit,
    deposit_dao: &DAO,
    withdraw_dao: &DAO,
    collection_id: ID,
    ctx: &mut TxContext,
) {
    assert!(deposit_dao.status().is_active(), EDaoNotActive);
    assert!(deposit_dao.is_governance_member(ctx.sender()), ENotDaoMember);

    let storage_unit_id = object::id(storage_unit);
    let deposit_dao_id = deposit_dao.id();
    let withdraw_dao_id = withdraw_dao.id();
    let key = VaultKey { storage_unit_id, deposit_dao_id };

    assert!(!table::contains(&registry.vaults, key), EDaoVaultAlreadyExists);

    let vault = DaoReceiptVault {
        id: object::new(ctx),
        deposit_dao_id,
        withdraw_dao_id,
        storage_unit_id,
        collection_id,
    };
    let vault_id = object::id(&vault);

    table::add(&mut registry.vaults, key, vault_id);
    transfer::share_object(vault);

    event::emit(DaoReceiptVaultInitializedEvent {
        vault_id,
        deposit_dao_id,
        withdraw_dao_id,
        storage_unit_id,
        collection_id,
    });
}

/// Deposit a warehouse receipt into the DAO vault.
/// `deposit_dao` must be the vault's bound deposit DAO and the caller must be one
/// of its board members. Receipt must belong to the vault's collection.
/// The Balance is merged with any existing balance for that asset_id.
public fun deposit_receipt(
    vault: &mut DaoReceiptVault,
    deposit_dao: &DAO,
    receipt: Balance,
    ctx: &mut TxContext,
) {
    assert!(deposit_dao.id() == vault.deposit_dao_id, EWrongDao);
    assert!(deposit_dao.is_governance_member(ctx.sender()), ENotDaoMember);
    assert!(receipt.collection_id() == vault.collection_id, EWrongCollection);

    let asset_id = receipt.asset_id();
    let amount = receipt.value();

    if (dof::exists_(&vault.id, asset_id)) {
        let stored: &mut Balance = dof::borrow_mut(&mut vault.id, asset_id);
        stored.join(receipt, ctx);
    } else {
        dof::add(&mut vault.id, asset_id, receipt);
    };

    event::emit(DaoReceiptVaultDepositEvent {
        vault_id: object::id(vault),
        deposit_dao_id: vault.deposit_dao_id,
        collection_id: vault.collection_id,
        asset_id,
        amount,
        depositor: ctx.sender(),
    });
}

/// Withdraw a specific amount for a given asset_id from the DAO vault.
/// `withdraw_dao` must be the vault's bound withdraw DAO and the caller must be
/// one of its board members. Returns the split Balance to the caller.
public fun withdraw_receipt(
    vault: &mut DaoReceiptVault,
    withdraw_dao: &DAO,
    asset_id: u64,
    amount: u64,
    ctx: &mut TxContext,
): Balance {
    assert!(withdraw_dao.id() == vault.withdraw_dao_id, EWrongDao);
    assert!(withdraw_dao.is_governance_member(ctx.sender()), ENotDaoMember);

    assert!(dof::exists_(&vault.id, asset_id), EInsufficientVaultBalance);
    let stored: &mut Balance = dof::borrow_mut(&mut vault.id, asset_id);
    assert!(stored.value() >= amount, EInsufficientVaultBalance);

    let withdrawn = stored.split(amount, ctx);

    // Remove zero-balance slot to reclaim storage
    if (stored.value() == 0) {
        let zero: Balance = dof::remove(&mut vault.id, asset_id);
        zero.destroy_zero();
    };

    event::emit(DaoReceiptVaultWithdrawEvent {
        vault_id: object::id(vault),
        withdraw_dao_id: vault.withdraw_dao_id,
        collection_id: vault.collection_id,
        asset_id,
        amount,
        withdrawer: ctx.sender(),
    });

    withdrawn
}

// === View Functions ===

/// Look up the vault_id for a (storage_unit_id, deposit_dao_id) pair.
/// Returns `option::none()` if no vault has been initialized for that pair.
public fun lookup(
    registry: &DaoReceiptVaultRegistry,
    storage_unit_id: ID,
    deposit_dao_id: ID,
): Option<ID> {
    let key = VaultKey { storage_unit_id, deposit_dao_id };
    if (table::contains(&registry.vaults, key)) {
        option::some(*table::borrow(&registry.vaults, key))
    } else {
        option::none()
    }
}

public fun deposit_dao_id(vault: &DaoReceiptVault): ID {
    vault.deposit_dao_id
}

public fun withdraw_dao_id(vault: &DaoReceiptVault): ID {
    vault.withdraw_dao_id
}

public fun storage_unit_id(vault: &DaoReceiptVault): ID {
    vault.storage_unit_id
}

public fun collection_id(vault: &DaoReceiptVault): ID {
    vault.collection_id
}

/// Returns the vault's accumulated balance for a given asset_id.
public fun vault_balance(vault: &DaoReceiptVault, asset_id: u64): u64 {
    if (dof::exists_(&vault.id, asset_id)) {
        let stored: &Balance = dof::borrow(&vault.id, asset_id);
        stored.value()
    } else {
        0
    }
}

// === Test Functions ===

/// Construct and share a vault directly, bypassing the SSU/registry setup
/// (anchoring a real StorageUnit requires the full world bootstrap). The
/// deposit/withdraw ACL logic under test does not touch the StorageUnit — only
/// `initialize_dao_vault` references it, for `object::id` — so tests bind the
/// vault to arbitrary ids and exercise the membership/collection/OU guards.
#[test_only]
public fun new_for_testing(
    deposit_dao_id: ID,
    withdraw_dao_id: ID,
    storage_unit_id: ID,
    collection_id: ID,
    ctx: &mut TxContext,
): DaoReceiptVault {
    DaoReceiptVault {
        id: object::new(ctx),
        deposit_dao_id,
        withdraw_dao_id,
        storage_unit_id,
        collection_id,
    }
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}

/// Share a vault built via `new_for_testing` (the vault has `key` but not
/// `store`, so callers outside this module cannot share it themselves).
#[test_only]
public fun share_for_testing(vault: DaoReceiptVault) {
    transfer::share_object(vault)
}
