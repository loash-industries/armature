#[test_only]
module armature_proposals::upgrade_ops_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::propose_upgrade::{Self, ProposeUpgrade};
use armature_proposals::upgrade_ops;
use std::string;
use sui::clock;
use sui::package;
use sui::test_scenario;

const CREATOR: address = @0xA;

// === Helpers ===

fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Upgrade ops test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun enable_upgrade_type(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"ProposeUpgrade".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };
}

fun store_upgrade_cap(scenario: &mut test_scenario::Scenario, package_id: ID): ID {
    scenario.next_tx(CREATOR);
    let cap_id;
    {
        let mut vault = scenario.take_shared<CapabilityVault>();
        let cap = package::test_publish(package_id, scenario.ctx());
        cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        test_scenario::return_shared(vault);
    };
    cap_id
}

// === Tests ===

#[test]
/// E2E: Store UpgradeCap → submit ProposeUpgrade → vote → execute → commit.
fun upgrade_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);
    enable_upgrade_type(&mut scenario);

    let package_id = object::id_from_address(@0xABC1);
    let cap_id = store_upgrade_cap(&mut scenario, package_id);

    // Submit ProposeUpgrade proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = propose_upgrade::new(
            cap_id,
            package_id,
            b"fake_digest",
            0, // COMPATIBLE policy
        );
        board_voting::submit_proposal(
            &dao,
            b"ProposeUpgrade".to_ascii_string(),
            option::some(string::utf8(b"Upgrade package")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute: authorize upgrade, simulate upgrade, commit
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Step 1: authorize upgrade — returns ticket, cap, and loan
        let (ticket, cap, loan) = upgrade_ops::execute_propose_upgrade(
            &mut vault,
            &proposal,
            request,
        );

        // Step 2: simulate the PTB Upgrade command
        let receipt = package::test_upgrade(ticket);

        // Step 3: commit upgrade and return cap to vault
        upgrade_ops::commit_upgrade(&mut vault, cap, receipt, loan);

        // Verify: UpgradeCap is back in the vault
        assert!(vault.contains(cap_id));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = upgrade_ops::EVaultDaoMismatch)]
/// Vault DAO ID mismatch aborts.
fun upgrade_vault_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create first DAO
    let first_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        first_dao_id =
            dao::create(
                &init,
                string::utf8(b"First DAO"),
                string::utf8(b"First DAO"),
                string::utf8(b"https://example.com/first.png"),
                scenario.ctx(),
            );
    };

    // Create second DAO
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Other DAO"),
            string::utf8(b"Second DAO"),
            string::utf8(b"https://example.com/other.png"),
            scenario.ctx(),
        );
    };

    // Enable upgrade on first DAO
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(first_dao_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"ProposeUpgrade".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    let package_id = object::id_from_address(@0xABC2);
    let fake_cap_id = object::id_from_address(@0xCAFE);

    // Submit ProposeUpgrade on first DAO (cap doesn't need to exist — abort is earlier)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(first_dao_id);
        clock.set_for_testing(1000);
        let payload = propose_upgrade::new(
            fake_cap_id,
            package_id,
            b"fake_digest",
            0,
        );
        board_voting::submit_proposal(
            &dao,
            b"ProposeUpgrade".to_ascii_string(),
            option::some(string::utf8(b"Upgrade package")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute with second DAO's vault — should abort with EVaultDaoMismatch
    scenario.next_tx(CREATOR);
    {
        let mut first_dao = scenario.take_shared_by_id<DAO>(first_dao_id);
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(first_dao.emergency_freeze_id());
        clock.set_for_testing(3000);

        // Get the other DAO's vault
        let other_dao = scenario.take_shared<DAO>();
        let other_vault_id = other_dao.capability_vault_id();
        test_scenario::return_shared(other_dao);
        let mut wrong_vault = scenario.take_shared_by_id<CapabilityVault>(other_vault_id);

        let request = board_voting::authorize_execution(
            &mut first_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // This will abort: wrong_vault.dao_id() != request.req_dao_id()
        let (ticket, cap, loan) = upgrade_ops::execute_propose_upgrade(
            &mut wrong_vault,
            &proposal,
            request,
        );

        let receipt = package::test_upgrade(ticket);
        upgrade_ops::commit_upgrade(&mut wrong_vault, cap, receipt, loan);

        test_scenario::return_shared(wrong_vault);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(first_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
