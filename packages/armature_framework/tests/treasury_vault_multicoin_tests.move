#[test_only]
module armature::treasury_vault_multicoin_tests;

use armature::dao;
use armature::governance;
use armature::proposal;
use armature::treasury_vault::{Self, TreasuryVault};
use multicoin::multicoin;
use std::string;
use sui::test_scenario;

// === Test addresses ===

const CREATOR: address = @0xA;
const NON_MEMBER: address = @0xC;
const PLAYER: address = @0xD;

// === Collection / asset constants ===

const COLL_A: address = @0xCA;
const COLL_B: address = @0xCB;

const ASSET_SWORD: u64 = 1;
const ASSET_SHIELD: u64 = 2;
const ASSET_POTION: u64 = 3;

// === Phantom proposal type ===

public struct TestProposal {}

// === Helpers ===

fun setup_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b""),
            scenario.ctx(),
        );
    };
}

fun make_req(vault: &TreasuryVault): proposal::ExecutionRequest<TestProposal> {
    proposal::new_execution_request<TestProposal>(
        vault.dao_id(),
        object::id_from_address(@0xFFF),
    )
}

fun coll(addr: address): ID { object::id_from_address(addr) }

// === Deposit: CollectionRecord lifecycle ===

#[test]
/// First deposit for a collection creates the CollectionRecord and increments collection count.
fun test_deposit_first_item_creates_collection() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        assert!(vault.multicoin_collection_count() == 1);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 5);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Depositing the same (collection, asset) again joins the balance; item_count unchanged.
fun test_deposit_same_asset_joins_balance() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let bal1 = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            3,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal1, scenario.ctx());

        let bal2 = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            7,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal2, scenario.ctx());

        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 10);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.multicoin_collection_count() == 1);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// A second distinct asset_id in the same collection increments item_count without adding a
/// collection.
fun test_deposit_second_asset_same_collection() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            1,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());

        let shield = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SHIELD,
            2,
            scenario.ctx(),
        );
        vault.deposit_multicoin(shield, scenario.ctx());

        assert!(vault.multicoin_collection_count() == 1);
        assert!(vault.collection_item_count(coll(COLL_A)) == 2);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 1);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 2);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// A deposit from a different collection creates a second CollectionRecord.
fun test_deposit_second_collection_tracked_separately() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());

        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            10,
            scenario.ctx(),
        );
        vault.deposit_multicoin(potion, scenario.ctx());

        assert!(vault.multicoin_collection_count() == 2);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.collection_item_count(coll(COLL_B)) == 1);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 5);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 10);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Zero-value deposit is a no-op — collection count and balances unchanged.
fun test_deposit_zero_is_noop() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let zero = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            0,
            scenario.ctx(),
        );
        vault.deposit_multicoin(zero, scenario.ctx());

        assert!(vault.multicoin_collection_count() == 0);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 0);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Multicoin deposit is permissionless — non-member can deposit.
fun test_deposit_permissionless() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(NON_MEMBER);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            3,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 3);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// === Withdraw: AssetKey and CollectionRecord lifecycle ===

#[test]
/// Partial withdrawal reduces balance; asset DOF and CollectionRecord are preserved.
fun test_withdraw_partial_preserves_dofs() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            10,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        let req = make_req(&vault);
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            4,
            &req,
            scenario.ctx(),
        );

        assert!(withdrawn.value() == 4);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 6);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.multicoin_collection_count() == 1);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Withdrawing the exact asset balance removes the asset DOF and decrements item_count.
fun test_withdraw_exact_removes_asset_dof() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());

        let shield = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SHIELD,
            3,
            scenario.ctx(),
        );
        vault.deposit_multicoin(shield, scenario.ctx());

        let req = make_req(&vault);
        // Withdraw all swords — removes asset DOF but collection still has shield
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            &req,
            scenario.ctx(),
        );

        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 0);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 3);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1); // shield remains
        assert!(vault.multicoin_collection_count() == 1); // collection still alive

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Withdrawing the last asset in a collection removes the CollectionRecord and decrements
/// collection count.
fun test_withdraw_last_asset_removes_collection() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        let req = make_req(&vault);
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            &req,
            scenario.ctx(),
        );

        assert!(vault.multicoin_collection_count() == 0);
        assert!(vault.collection_item_count(coll(COLL_A)) == 0);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 0);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Removing last asset from one collection does not affect sibling collection.
fun test_withdraw_last_asset_leaves_sibling_collection_intact() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());

        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            10,
            scenario.ctx(),
        );
        vault.deposit_multicoin(potion, scenario.ctx());

        let req = make_req(&vault);
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            &req,
            scenario.ctx(),
        );

        // COLL_A gone; COLL_B untouched
        assert!(vault.multicoin_collection_count() == 1);
        assert!(vault.collection_item_count(coll(COLL_A)) == 0);
        assert!(vault.collection_item_count(coll(COLL_B)) == 1);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 10);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = treasury_vault::EInsufficientBalance)]
/// Withdrawing more than the available balance aborts.
fun test_withdraw_excess_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        let req = make_req(&vault);
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            99,
            &req,
            scenario.ctx(),
        );

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = treasury_vault::EInsufficientBalance)]
/// Withdrawing from a collection not in the vault aborts.
fun test_withdraw_missing_collection_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let req = make_req(&vault);
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            1,
            &req,
            scenario.ctx(),
        );

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = treasury_vault::EInsufficientBalance)]
/// Withdrawing an asset_id not present in an existing collection aborts.
fun test_withdraw_missing_asset_in_collection_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());

        let req = make_req(&vault);
        // ASSET_SHIELD was never deposited
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SHIELD,
            1,
            &req,
            scenario.ctx(),
        );

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// === Accessors ===

#[test]
/// multicoin_balance returns 0 for a collection that was never deposited.
fun test_multicoin_balance_missing_collection_returns_zero() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<TreasuryVault>();
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 0);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// multicoin_balance returns 0 for an asset_id not present in an existing collection.
fun test_multicoin_balance_missing_asset_returns_zero() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());

        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 0);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// collection_item_count returns 0 for a collection not in the vault.
fun test_collection_item_count_missing_returns_zero() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<TreasuryVault>();
        assert!(vault.collection_item_count(coll(COLL_A)) == 0);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// === is_empty / destroy_empty ===

#[test]
/// is_empty returns false when vault holds only multicoin assets (no coins).
fun test_is_empty_false_with_only_multicoin() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            1,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        assert!(!vault.is_empty());

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// is_empty returns true after all multicoin assets are fully withdrawn.
fun test_is_empty_true_after_full_multicoin_withdrawal() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());

        let req = make_req(&vault);
        let withdrawn = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            &req,
            scenario.ctx(),
        );

        assert!(vault.is_empty());

        proposal::consume(req);
        transfer::public_transfer(withdrawn, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = treasury_vault::EVaultNotEmpty)]
/// destroy_empty aborts when the vault still holds multicoin assets.
fun test_destroy_empty_aborts_with_multicoin_assets() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let dao_id = object::id_from_address(@0xDA0);
        let mut vault = treasury_vault::new(dao_id, scenario.ctx());
        let bal = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            1,
            scenario.ctx(),
        );
        vault.deposit_multicoin(bal, scenario.ctx());
        treasury_vault::destroy_empty(vault);
    };
    scenario.end();
}

// === Multi-deposit proposal ===

#[test]
/// Proposal execution deposits warehouse receipts from multiple collections in one transaction.
/// Simulates a DAO receiving items after winning a batch auction.
fun test_multi_deposit_proposal() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        // Batch of items received in a single proposal execution
        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        let shield = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SHIELD,
            3,
            scenario.ctx(),
        );
        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            10,
            scenario.ctx(),
        );

        vault.deposit_multicoin(sword, scenario.ctx());
        vault.deposit_multicoin(shield, scenario.ctx());
        vault.deposit_multicoin(potion, scenario.ctx());

        // Two collections, three distinct asset types
        assert!(vault.multicoin_collection_count() == 2);
        assert!(vault.collection_item_count(coll(COLL_A)) == 2);
        assert!(vault.collection_item_count(coll(COLL_B)) == 1);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD)  == 5);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 3);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 10);
        assert!(!vault.is_empty());

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Depositing the same items again in a second proposal execution accumulates balances correctly.
fun test_multi_deposit_proposal_accumulates_on_repeat() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    // First deposit round
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            10,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());
        vault.deposit_multicoin(potion, scenario.ctx());

        test_scenario::return_shared(vault);
    };

    // Second deposit round — same items, more quantity
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            3,
            scenario.ctx(),
        );
        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            7,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());
        vault.deposit_multicoin(potion, scenario.ctx());

        // Counts unchanged; balances accumulated
        assert!(vault.multicoin_collection_count() == 2);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.collection_item_count(coll(COLL_B)) == 1);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD)  == 8);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 17);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// === Multi-withdraw proposal ===

#[test]
/// Proposal execution withdraws items from multiple collections in one transaction,
/// using a single ExecutionRequest. Simulates sending a bundle of items to a player.
fun test_multi_withdraw_proposal() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    // Seed the vault
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            10,
            scenario.ctx(),
        );
        let shield = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SHIELD,
            6,
            scenario.ctx(),
        );
        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            8,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());
        vault.deposit_multicoin(shield, scenario.ctx());
        vault.deposit_multicoin(potion, scenario.ctx());

        test_scenario::return_shared(vault);
    };

    // Proposal execution: single ExecutionRequest covers all three withdrawals
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let req = make_req(&vault);
        let w_sword = vault.withdraw_multicoin(coll(COLL_A), ASSET_SWORD, 4, &req, scenario.ctx());
        let w_shield = vault.withdraw_multicoin(
            coll(COLL_A),
            ASSET_SHIELD,
            6,
            &req,
            scenario.ctx(),
        );
        let w_potion = vault.withdraw_multicoin(
            coll(COLL_B),
            ASSET_POTION,
            8,
            &req,
            scenario.ctx(),
        );

        assert!(w_sword.value()  == 4);
        assert!(w_shield.value() == 6);
        assert!(w_potion.value() == 8);

        // COLL_A: sword has 6 remaining; shield fully drained → item_count 1
        // COLL_B: potion fully drained → CollectionRecord removed
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD)  == 6);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 0);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 0);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.collection_item_count(coll(COLL_B)) == 0);
        assert!(vault.multicoin_collection_count() == 1);

        proposal::consume(req);
        transfer::public_transfer(w_sword, PLAYER);
        transfer::public_transfer(w_shield, PLAYER);
        transfer::public_transfer(w_potion, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Proposal execution fully drains all multicoin holdings across both collections,
/// leaving the vault empty.
fun test_multi_withdraw_proposal_full_drain() {
    let mut scenario = test_scenario::begin(CREATOR);
    setup_dao(&mut scenario);

    // Seed
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sword = multicoin::create_balance_for_testing(
            coll(COLL_A),
            ASSET_SWORD,
            5,
            scenario.ctx(),
        );
        let potion = multicoin::create_balance_for_testing(
            coll(COLL_B),
            ASSET_POTION,
            3,
            scenario.ctx(),
        );
        vault.deposit_multicoin(sword, scenario.ctx());
        vault.deposit_multicoin(potion, scenario.ctx());

        test_scenario::return_shared(vault);
    };

    // Full drain in one proposal execution
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let req = make_req(&vault);
        let w_sword = vault.withdraw_multicoin(coll(COLL_A), ASSET_SWORD, 5, &req, scenario.ctx());
        let w_potion = vault.withdraw_multicoin(
            coll(COLL_B),
            ASSET_POTION,
            3,
            &req,
            scenario.ctx(),
        );

        assert!(vault.is_empty());
        assert!(vault.multicoin_collection_count() == 0);

        proposal::consume(req);
        transfer::public_transfer(w_sword, PLAYER);
        transfer::public_transfer(w_potion, PLAYER);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}
