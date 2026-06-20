#[test_only]
module armature_proposals::batch_multicoin_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::multicoin_item;
use armature_proposals::send_batch_multicoin_to_dao::{Self, SendBatchMulticoinToDAO};
use armature_proposals::send_batch_multicoin_to_player::{Self, SendBatchMulticoinToAddress};
use armature_proposals::treasury_ops;
use multicoin::multicoin;
use std::string;
use sui::clock;
use sui::test_scenario;

// === Constants ===

const CREATOR: address = @0xA;
const PLAYER: address = @0xB;

const COLL_A: address = @0xCA;
const COLL_B: address = @0xCB;

const ASSET_SWORD: u64 = 1;
const ASSET_SHIELD: u64 = 2;
const ASSET_POTION: u64 = 3;

// === Helpers ===

fun coll(addr: address): ID { object::id_from_address(addr) }

fun create_named_dao(scenario: &mut test_scenario::Scenario, name: vector<u8>): ID {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    dao::create(
        &init,
        string::utf8(name),
        string::utf8(b""),
        scenario.ctx(),
    )
}

fun enable_type(scenario: &mut test_scenario::Scenario, dao_id: ID, type_name: vector<u8>) {
    scenario.next_tx(CREATOR);
    let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
    let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
    dao.test_enable_type(type_name.to_ascii_string(), config);
    test_scenario::return_shared(dao);
}

fun fund_vault(scenario: &mut test_scenario::Scenario, vault_id: ID) {
    scenario.next_tx(CREATOR);
    let mut vault = scenario.take_shared_by_id<TreasuryVault>(vault_id);
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
}

// =========================================================================
// SendBatchMulticoinToAddress tests
// =========================================================================

#[test]
/// E2E: fund vault with 3 items → propose batch send to address → vote → execute
/// → vault balances reduced correctly, address receives all three objects.
fun send_batch_to_address_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let dao_id = create_named_dao(&mut scenario, b"Test DAO");
    enable_type(&mut scenario, dao_id, b"SendBatchMulticoinToAddress");

    let vault_id;
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        vault_id = dao.treasury_id();
        test_scenario::return_shared(dao);
    };

    fund_vault(&mut scenario, vault_id);

    // Submit proposal: send sword(4) + shield(6) + potion(8) to PLAYER
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        let items = vector[
            multicoin_item::new(coll(COLL_A), ASSET_SWORD, 4),
            multicoin_item::new(coll(COLL_A), ASSET_SHIELD, 6),
            multicoin_item::new(coll(COLL_B), ASSET_POTION, 8),
        ];
        let payload = send_batch_multicoin_to_player::new(PLAYER, items);
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"SendBatchMulticoinToAddress".to_ascii_string(),
            option::some(string::utf8(b"Send batch to address")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToAddress>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared_by_id<TreasuryVault>(vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToAddress>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        treasury_ops::execute_send_batch_multicoin_to_player(&mut vault, ticket, scenario.ctx());

        // sword: 10 - 4 = 6 remaining; shield: 6 - 6 = 0 (removed); potion: 8 - 8 = 0 (removed)
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD)  == 6);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 0);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 0);
        assert!(vault.collection_item_count(coll(COLL_A)) == 1);
        assert!(vault.collection_item_count(coll(COLL_B)) == 0);
        assert!(vault.multicoin_collection_count() == 1);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Partial batch: send only 2 of 3 items, leaving the third untouched in the vault.
fun send_batch_to_address_partial_withdraw() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let dao_id = create_named_dao(&mut scenario, b"Test DAO");
    enable_type(&mut scenario, dao_id, b"SendBatchMulticoinToAddress");

    let vault_id;
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        vault_id = dao.treasury_id();
        test_scenario::return_shared(dao);
    };

    fund_vault(&mut scenario, vault_id);

    // Submit proposal: send sword(3) + potion(5) only; shield stays
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        let items = vector[
            multicoin_item::new(coll(COLL_A), ASSET_SWORD, 3),
            multicoin_item::new(coll(COLL_B), ASSET_POTION, 5),
        ];
        let payload = send_batch_multicoin_to_player::new(PLAYER, items);
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"SendBatchMulticoinToAddress".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToAddress>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared_by_id<TreasuryVault>(vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToAddress>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        treasury_ops::execute_send_batch_multicoin_to_player(&mut vault, ticket, scenario.ctx());

        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SWORD)  == 7);
        assert!(vault.multicoin_balance(coll(COLL_A), ASSET_SHIELD) == 6);
        assert!(vault.multicoin_balance(coll(COLL_B), ASSET_POTION) == 3);
        assert!(vault.collection_item_count(coll(COLL_A)) == 2);
        assert!(vault.collection_item_count(coll(COLL_B)) == 1);
        assert!(vault.multicoin_collection_count() == 2);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::treasury_vault::EInsufficientBalance)]
/// Batch with an item whose amount exceeds the vault balance aborts the whole transaction.
fun send_batch_to_address_insufficient_balance_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let dao_id = create_named_dao(&mut scenario, b"Test DAO");
    enable_type(&mut scenario, dao_id, b"SendBatchMulticoinToAddress");

    let vault_id;
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        vault_id = dao.treasury_id();
        test_scenario::return_shared(dao);
    };

    fund_vault(&mut scenario, vault_id); // vault has sword=10

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        let items = vector[
            multicoin_item::new(coll(COLL_A), ASSET_SWORD, 999), // exceeds vault balance of 10
        ];
        let payload = send_batch_multicoin_to_player::new(PLAYER, items);
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"SendBatchMulticoinToAddress".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToAddress>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared_by_id<TreasuryVault>(vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToAddress>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        treasury_ops::execute_send_batch_multicoin_to_player(&mut vault, ticket, scenario.ctx());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// SendBatchMulticoinToDAO tests
// =========================================================================

/// Seed a vault with a single sword balance (lean helper for 2-DAO tests).
fun fund_vault_single(scenario: &mut test_scenario::Scenario, vault_id: ID, amount: u64) {
    scenario.next_tx(CREATOR);
    let mut vault = scenario.take_shared_by_id<TreasuryVault>(vault_id);
    let sword = multicoin::create_balance_for_testing(
        coll(COLL_A),
        ASSET_SWORD,
        amount,
        scenario.ctx(),
    );
    vault.deposit_multicoin(sword, scenario.ctx());
    test_scenario::return_shared(vault);
}

#[test]
/// E2E: Two DAOs — fund source vault, propose batch transfer, vote, execute
/// → source vault debited, target vault credited with all items.
fun send_batch_to_dao_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let source_dao_id = create_named_dao(&mut scenario, b"Source DAO");
    let target_dao_id = create_named_dao(&mut scenario, b"Target DAO");

    enable_type(&mut scenario, source_dao_id, b"SendBatchMulticoinToDAO");

    let source_vault_id;
    let target_vault_id;
    scenario.next_tx(CREATOR);
    {
        let source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let target_dao = scenario.take_shared_by_id<DAO>(target_dao_id);
        source_vault_id = source_dao.treasury_id();
        target_vault_id = target_dao.treasury_id();
        test_scenario::return_shared(target_dao);
        test_scenario::return_shared(source_dao);
    };

    fund_vault_single(&mut scenario, source_vault_id, 10);

    // Submit proposal: send sword(4) to target DAO
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let items = vector[multicoin_item::new(coll(COLL_A), ASSET_SWORD, 4)];
        let payload = send_batch_multicoin_to_dao::new(target_vault_id, items);
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"SendBatchMulticoinToDAO".to_ascii_string(),
            option::some(string::utf8(b"Send batch to target DAO")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let mut source_vault = scenario.take_shared_by_id<TreasuryVault>(source_vault_id);
        let mut target_vault = scenario.take_shared_by_id<TreasuryVault>(target_vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToDAO>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(source_dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut source_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        treasury_ops::execute_send_batch_multicoin_to_dao(
            &mut source_vault,
            &mut target_vault,
            ticket,
            scenario.ctx(),
        );

        // Source: 10 - 4 = 6 remaining
        assert!(source_vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 6);
        assert!(source_vault.multicoin_collection_count() == 1);
        // Target received the 4 swords
        assert!(target_vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 4);
        assert!(target_vault.multicoin_collection_count() == 1);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(target_vault);
        test_scenario::return_shared(source_vault);
        test_scenario::return_shared(source_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Sending to a DAO that already holds the same asset accumulates the balance.
fun send_batch_to_dao_accumulates_in_target() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let source_dao_id = create_named_dao(&mut scenario, b"Source DAO");
    let target_dao_id = create_named_dao(&mut scenario, b"Target DAO");

    enable_type(&mut scenario, source_dao_id, b"SendBatchMulticoinToDAO");

    let source_vault_id;
    let target_vault_id;
    scenario.next_tx(CREATOR);
    {
        let source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let target_dao = scenario.take_shared_by_id<DAO>(target_dao_id);
        source_vault_id = source_dao.treasury_id();
        target_vault_id = target_dao.treasury_id();
        test_scenario::return_shared(target_dao);
        test_scenario::return_shared(source_dao);
    };

    fund_vault_single(&mut scenario, source_vault_id, 10);
    fund_vault_single(&mut scenario, target_vault_id, 2); // pre-existing 2 swords

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let items = vector[multicoin_item::new(coll(COLL_A), ASSET_SWORD, 5)];
        let payload = send_batch_multicoin_to_dao::new(target_vault_id, items);
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"SendBatchMulticoinToDAO".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let mut source_vault = scenario.take_shared_by_id<TreasuryVault>(source_vault_id);
        let mut target_vault = scenario.take_shared_by_id<TreasuryVault>(target_vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToDAO>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(source_dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut source_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        treasury_ops::execute_send_batch_multicoin_to_dao(
            &mut source_vault,
            &mut target_vault,
            ticket,
            scenario.ctx(),
        );

        // Target: pre-existing 2 + transferred 5 = 7
        assert!(target_vault.multicoin_balance(coll(COLL_A), ASSET_SWORD) == 7);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(target_vault);
        test_scenario::return_shared(source_vault);
        test_scenario::return_shared(source_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = treasury_ops::ETargetVaultMismatch)]
/// Passing a vault whose object ID does not match the proposal's `recipient_treasury` aborts.
fun send_batch_to_dao_target_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let source_dao_id = create_named_dao(&mut scenario, b"Source DAO");
    let target_dao_id = create_named_dao(&mut scenario, b"Target DAO");

    enable_type(&mut scenario, source_dao_id, b"SendBatchMulticoinToDAO");

    let source_vault_id;
    let target_vault_id;
    scenario.next_tx(CREATOR);
    {
        let source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let target_dao = scenario.take_shared_by_id<DAO>(target_dao_id);
        source_vault_id = source_dao.treasury_id();
        target_vault_id = target_dao.treasury_id();
        test_scenario::return_shared(target_dao);
        test_scenario::return_shared(source_dao);
    };

    fund_vault(&mut scenario, source_vault_id);

    // Payload names source_vault_id as recipient — target_vault has a different ID
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let items = vector[multicoin_item::new(coll(COLL_A), ASSET_SWORD, 2)];
        // Intentionally wrong: recipient_treasury = source_vault_id instead of target_vault_id
        let payload = send_batch_multicoin_to_dao::new(source_vault_id, items);
        clock.set_for_testing(1000);
        board_voting::submit_proposal(
            &dao,
            b"SendBatchMulticoinToDAO".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — target_vault's object ID ≠ source_vault_id in payload → ETargetVaultMismatch
    scenario.next_tx(CREATOR);
    {
        let mut source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let mut source_vault = scenario.take_shared_by_id<TreasuryVault>(source_vault_id);
        let mut target_vault = scenario.take_shared_by_id<TreasuryVault>(target_vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendBatchMulticoinToDAO>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(source_dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut source_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        treasury_ops::execute_send_batch_multicoin_to_dao(
            &mut source_vault,
            &mut target_vault, // object::id(target_vault) != source_vault_id → ETargetVaultMismatch
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(target_vault);
        test_scenario::return_shared(source_vault);
        test_scenario::return_shared(source_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
