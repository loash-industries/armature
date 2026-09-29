#[test_only]
module armature_proposals::upgrade_ops_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal::{Self, Proposal};
use armature_proposals::propose_upgrade::{Self, ProposeUpgrade};
use armature_proposals::type_permissions;
use armature_proposals::upgrade_ops;
use std::string;
use sui::clock;
use sui::package;
use sui::test_scenario;

const CREATOR: address = @0xA;

// === Helpers ===

fun create_ou(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou::create(
            &init,
            string::utf8(b"Test OU"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun enable_upgrade_type(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<ProposeUpgrade>(
            b"ProposeUpgrade".to_ascii_string(),
            config
                .with_permissions(type_permissions::propose_upgrade())
                .with_borrow_scope(type_permissions::propose_upgrade_scope()),
        );
        test_scenario::return_shared(ou);
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

    create_ou(&mut scenario);
    enable_upgrade_type(&mut scenario);

    let package_id = object::id_from_address(@0xABC1);
    let cap_id = store_upgrade_cap(&mut scenario, package_id);

    // Submit ProposeUpgrade proposal
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = propose_upgrade::new(
            cap_id,
            package_id,
            b"fake_digest",
            0, // COMPATIBLE policy
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Upgrade package")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute: authorize upgrade, simulate upgrade, commit
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Step 1: authorize upgrade — returns the upgrade ticket and the pending cap
        let (ticket, pending) = upgrade_ops::execute_propose_upgrade(
            &mut vault,
            ticket,
        );

        // Step 2: simulate the PTB Upgrade command
        let receipt = package::test_upgrade(ticket);

        // Step 3: commit upgrade and return cap to vault
        upgrade_ops::commit_upgrade(&mut vault, pending, receipt);

        // Verify: UpgradeCap is back in the vault
        assert!(vault.contains(cap_id));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = upgrade_ops::EVaultOuMismatch)]
/// Vault OU ID mismatch aborts.
fun upgrade_vault_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create first OU
    let first_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        first_ou_id =
            ou::create(
                &init,
                string::utf8(b"First OU"),
                string::utf8(b"https://example.com/first.png"),
                scenario.ctx(),
            );
    };

    // Create second OU
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou::create(
            &init,
            string::utf8(b"Other OU"),
            string::utf8(b"https://example.com/other.png"),
            scenario.ctx(),
        );
    };

    // Enable upgrade on first OU
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(first_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<ProposeUpgrade>(
            b"ProposeUpgrade".to_ascii_string(),
            config
                .with_permissions(type_permissions::propose_upgrade())
                .with_borrow_scope(type_permissions::propose_upgrade_scope()),
        );
        test_scenario::return_shared(ou);
    };

    let package_id = object::id_from_address(@0xABC2);
    let fake_cap_id = object::id_from_address(@0xCAFE);

    // Submit ProposeUpgrade on first OU (cap doesn't need to exist — abort is earlier)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(first_ou_id);
        clock.set_for_testing(1000);
        let payload = propose_upgrade::new(
            fake_cap_id,
            package_id,
            b"fake_digest",
            0,
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Upgrade package")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute with second OU's vault — should abort with EVaultOuMismatch
    scenario.next_tx(CREATOR);
    {
        let mut first_ou = scenario.take_shared_by_id<OU>(first_ou_id);
        let mut proposal = scenario.take_shared<Proposal<ProposeUpgrade>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(first_ou.emergency_freeze_id());
        clock.set_for_testing(3000);

        // Get the other OU's vault
        let other_ou = scenario.take_shared<OU>();
        let other_vault_id = other_ou.capability_vault_id();
        test_scenario::return_shared(other_ou);
        let mut wrong_vault = scenario.take_shared_by_id<CapabilityVault>(other_vault_id);

        let ticket = board_voting::ticket_from_vote(
            &mut first_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // This will abort: wrong_vault.ou_id() != request.req_ou_id()
        let (ticket, pending) = upgrade_ops::execute_propose_upgrade(
            &mut wrong_vault,
            ticket,
        );

        let receipt = package::test_upgrade(ticket);
        upgrade_ops::commit_upgrade(&mut wrong_vault, pending, receipt);

        test_scenario::return_shared(wrong_vault);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(first_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}
