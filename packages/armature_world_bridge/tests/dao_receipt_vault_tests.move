/// Tests for `dao_receipt_vault` — the DAO/OU-gated warehouse-receipt vault.
///
/// Coverage focuses on the access-control surface that differs from the
/// upstream `tribe_vault` fork: DAO-membership gating (principal = sender),
/// the deposit/withdraw OU role split, OU-substitution rejection, and the
/// collection binding. Vaults are built via `new_for_testing` to skip the
/// heavy world StorageUnit anchor — the ACL paths under test (deposit/withdraw)
/// never reference the StorageUnit.
#[test_only]
module armature_world_bridge::dao_receipt_vault_tests;

use armature::dao::{Self, DAO};
use armature::governance;
use armature_world_bridge::dao_receipt_vault::{Self as vault, DaoReceiptVault};
use multicoin::multicoin::{Self, Collection, CollectionCap, Balance};
use std::string;
use sui::test_scenario as ts;

const DEPOSITOR: address = @0xD1;
const WITHDRAWER: address = @0xC1;
const OUTSIDER: address = @0x0E;

const ASSET: u64 = 42;

// === Helpers ===

/// Create + share a DAO with the given board members. Returns its id.
fun make_dao(scenario: &mut ts::Scenario, creator: address, members: vector<address>): ID {
    ts::next_tx(scenario, creator);
    let init = governance::init_board(members);
    let id = dao::create(
        &init,
        string::utf8(b"OU"),
        string::utf8(b"test ou"),
        string::utf8(b"https://example.com/i.png"),
        scenario.ctx(),
    );
    id
}

/// Create + share a multicoin Collection, returning the cap to the sender.
/// The collection's object id is the receipts' `collection_id`.
fun make_collection(scenario: &mut ts::Scenario, owner: address): ID {
    ts::next_tx(scenario, owner);
    let (collection, cap) = multicoin::new_collection(scenario.ctx());
    let cid = object::id(&collection);
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, owner);
    cid
}

fun mint(
    scenario: &mut ts::Scenario,
    owner: address,
    collection_id: ID,
    asset_id: u64,
    amount: u64,
): Balance {
    ts::next_tx(scenario, owner);
    let mut collection = ts::take_shared_by_id<Collection>(scenario, collection_id);
    let cap = ts::take_from_sender<CollectionCap>(scenario);
    let bal = multicoin::mint_balance(&cap, &mut collection, asset_id, amount, scenario.ctx());
    ts::return_to_sender(scenario, cap);
    ts::return_shared(collection);
    bal
}

// === Tests ===

/// Happy path: a deposit-OU member deposits, a withdraw-OU member withdraws.
#[test]
fun deposit_then_withdraw_by_members() {
    let mut scenario = ts::begin(DEPOSITOR);
    vault::init_for_testing(scenario.ctx());

    let deposit_dao = make_dao(&mut scenario, DEPOSITOR, vector[DEPOSITOR]);
    let withdraw_dao = make_dao(&mut scenario, WITHDRAWER, vector[WITHDRAWER]);
    let collection_id = make_collection(&mut scenario, DEPOSITOR);

    // Build + share the vault.
    ts::next_tx(&mut scenario, DEPOSITOR);
    let v = vault::new_for_testing(
        deposit_dao,
        withdraw_dao,
        object::id_from_address(@0x5501), // arbitrary SSU id
        collection_id,
        scenario.ctx(),
    );
    vault::share_for_testing(v);

    // DEPOSITOR (deposit-OU member) deposits 100.
    let receipt = mint(&mut scenario, DEPOSITOR, collection_id, ASSET, 100);
    ts::next_tx(&mut scenario, DEPOSITOR);
    {
        let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
        let dao = ts::take_shared_by_id<DAO>(&scenario, deposit_dao);
        vault::deposit_receipt(&mut v, &dao, receipt, scenario.ctx());
        assert!(vault::vault_balance(&v, ASSET) == 100, 0);
        ts::return_shared(dao);
        ts::return_shared(v);
    };

    // WITHDRAWER (withdraw-OU member) withdraws 60.
    ts::next_tx(&mut scenario, WITHDRAWER);
    {
        let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
        let dao = ts::take_shared_by_id<DAO>(&scenario, withdraw_dao);
        let out = vault::withdraw_receipt(&mut v, &dao, ASSET, 60, scenario.ctx());
        assert!(out.value() == 60, 1);
        assert!(vault::vault_balance(&v, ASSET) == 40, 2);
        transfer::public_transfer(out, WITHDRAWER);
        ts::return_shared(dao);
        ts::return_shared(v);
    };

    ts::end(scenario);
}

/// A non-member cannot deposit.
#[test]
#[expected_failure(abort_code = vault::ENotDaoMember)]
fun deposit_rejected_for_non_member() {
    let mut scenario = ts::begin(DEPOSITOR);
    let deposit_dao = make_dao(&mut scenario, DEPOSITOR, vector[DEPOSITOR]);
    let collection_id = make_collection(&mut scenario, DEPOSITOR);

    ts::next_tx(&mut scenario, DEPOSITOR);
    let v = vault::new_for_testing(
        deposit_dao,
        deposit_dao,
        object::id_from_address(@0x5501),
        collection_id,
        scenario.ctx(),
    );
    vault::share_for_testing(v);

    let receipt = mint(&mut scenario, DEPOSITOR, collection_id, ASSET, 100);
    // OUTSIDER tries to deposit DEPOSITOR's receipt.
    ts::next_tx(&mut scenario, OUTSIDER);
    let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
    let dao = ts::take_shared_by_id<DAO>(&scenario, deposit_dao);
    vault::deposit_receipt(&mut v, &dao, receipt, scenario.ctx());

    abort // unreachable
}

/// A withdraw-OU member cannot withdraw by passing the *deposit* DAO it also
/// belongs to — the vault asserts the DAO id matches `withdraw_dao_id`.
#[test]
#[expected_failure(abort_code = vault::EWrongDao)]
fun withdraw_rejected_with_wrong_ou() {
    let mut scenario = ts::begin(DEPOSITOR);
    // Single player on BOTH boards (mirrors admin cascade): if we only checked
    // membership, they could withdraw via the deposit DAO. The id-binding stops it.
    let deposit_dao = make_dao(&mut scenario, DEPOSITOR, vector[DEPOSITOR]);
    let withdraw_dao = make_dao(&mut scenario, DEPOSITOR, vector[DEPOSITOR]);
    let collection_id = make_collection(&mut scenario, DEPOSITOR);

    ts::next_tx(&mut scenario, DEPOSITOR);
    let v = vault::new_for_testing(
        deposit_dao,
        withdraw_dao,
        object::id_from_address(@0x5501),
        collection_id,
        scenario.ctx(),
    );
    vault::share_for_testing(v);

    let receipt = mint(&mut scenario, DEPOSITOR, collection_id, ASSET, 100);
    ts::next_tx(&mut scenario, DEPOSITOR);
    {
        let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
        let dao = ts::take_shared_by_id<DAO>(&scenario, deposit_dao);
        vault::deposit_receipt(&mut v, &dao, receipt, scenario.ctx());
        ts::return_shared(dao);
        ts::return_shared(v);
    };

    // Try to withdraw passing the DEPOSIT dao (member of it, but it's not the bound withdraw OU).
    ts::next_tx(&mut scenario, DEPOSITOR);
    let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
    let wrong_dao = ts::take_shared_by_id<DAO>(&scenario, deposit_dao);
    let out = vault::withdraw_receipt(&mut v, &wrong_dao, ASSET, 10, scenario.ctx());
    transfer::public_transfer(out, DEPOSITOR);

    abort // unreachable
}

/// A receipt from a different collection is rejected on deposit.
#[test]
#[expected_failure(abort_code = vault::EWrongCollection)]
fun deposit_rejected_for_wrong_collection() {
    let mut scenario = ts::begin(DEPOSITOR);
    let deposit_dao = make_dao(&mut scenario, DEPOSITOR, vector[DEPOSITOR]);
    let bound_collection = make_collection(&mut scenario, DEPOSITOR);
    let other_collection = make_collection(&mut scenario, DEPOSITOR);

    ts::next_tx(&mut scenario, DEPOSITOR);
    let v = vault::new_for_testing(
        deposit_dao,
        deposit_dao,
        object::id_from_address(@0x5501),
        bound_collection, // vault bound to this collection
        scenario.ctx(),
    );
    vault::share_for_testing(v);

    // Mint a receipt from the OTHER collection.
    let receipt = mint(&mut scenario, DEPOSITOR, other_collection, ASSET, 100);
    ts::next_tx(&mut scenario, DEPOSITOR);
    let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
    let dao = ts::take_shared_by_id<DAO>(&scenario, deposit_dao);
    vault::deposit_receipt(&mut v, &dao, receipt, scenario.ctx());

    abort // unreachable
}

/// Withdrawing more than the vault holds aborts.
#[test]
#[expected_failure(abort_code = vault::EInsufficientVaultBalance)]
fun withdraw_rejected_when_insufficient() {
    let mut scenario = ts::begin(DEPOSITOR);
    let dao_id = make_dao(&mut scenario, DEPOSITOR, vector[DEPOSITOR]);
    let collection_id = make_collection(&mut scenario, DEPOSITOR);

    ts::next_tx(&mut scenario, DEPOSITOR);
    let v = vault::new_for_testing(
        dao_id,
        dao_id,
        object::id_from_address(@0x5501),
        collection_id,
        scenario.ctx(),
    );
    vault::share_for_testing(v);

    let receipt = mint(&mut scenario, DEPOSITOR, collection_id, ASSET, 50);
    ts::next_tx(&mut scenario, DEPOSITOR);
    {
        let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
        let dao = ts::take_shared_by_id<DAO>(&scenario, dao_id);
        vault::deposit_receipt(&mut v, &dao, receipt, scenario.ctx());
        ts::return_shared(dao);
        ts::return_shared(v);
    };

    ts::next_tx(&mut scenario, DEPOSITOR);
    let mut v = ts::take_shared<DaoReceiptVault>(&scenario);
    let dao = ts::take_shared_by_id<DAO>(&scenario, dao_id);
    let out = vault::withdraw_receipt(&mut v, &dao, ASSET, 999, scenario.ctx());
    transfer::public_transfer(out, DEPOSITOR);

    abort // unreachable
}
