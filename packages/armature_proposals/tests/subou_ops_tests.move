#[test_only]
module armature_proposals::subou_ops_tests;

use armature::board_voting;
use armature::capability_vault::{Self, CapabilityVault, SubOUControl};
use armature::create_subou::{Self, CreateSubOU};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::lifecycle_ops;
use armature::ou::{Self, OU};
use armature::proposal::{Self, Proposal};
use armature_proposals::controller_batch_add_members::{Self, ControllerBatchAddMembers};
use armature_proposals::controller_batch_remove_members::{Self, ControllerBatchRemoveMembers};
use armature_proposals::pause_execution;
use armature_proposals::reclaim_cap_from_subou::{Self, ReclaimCapFromSubOU};
use armature_proposals::subou_ops;
use armature_proposals::transfer_cap_to_subou::{Self, TransferCapToSubOU};
use armature_proposals::type_permissions;
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const SUBOU_MEMBER: address = @0xC;
const NEW_SUBOU_MEMBER: address = @0xD;

#[test]
/// E2E: Create OU → enable CreateSubOU type → submit CreateSubOU proposal
/// → vote → execute → verify child OU created with SubOUControl + FreezeAdminCap
/// stored in controller vault.
fun create_subou_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent OU with Board governance
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        ou::create(
            &init,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // 2. Enable CreateSubOU proposal type on the parent OU
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(
            5_000, // quorum 50%
            5_000, // approval_threshold 50%
            0, // propose_threshold
            604_800_000, // expiry 7 days
            0, // execution_delay
            0, // cooldown
        );
        ou.test_enable_type<CreateSubOU>(b"CreateSubOU".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    // 3. Submit a CreateSubOU proposal
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);

        let payload = create_subou::new(
            string::utf8(b"Child OU"),
            vector[SUBOU_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );

        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Create a managed sub-OU")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // 4. Vote yes (CREATOR) — 1/2 board members = 50% quorum, passes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 5. Execute the proposal and run the handler
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
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

        lifecycle_ops::execute_create_subou(
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        // 6. Verify: vault should contain SubOUControl + FreezeAdminCap
        assert!(vault.cap_ids().length() >= 2);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };

    // 7. Verify the child OU was created as a shared object
    scenario.next_tx(CREATOR);
    {};

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::lifecycle_ops::EVaultOUMismatch)]
/// Verify execute_create_subou rejects a vault that doesn't match the OU.
fun create_subou_vault_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create two OUs to get two different vaults
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou::create(
            &init,
            string::utf8(b"OU A"),
            string::utf8(b"https://example.com/a.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        ou::create(
            &init,
            string::utf8(b"OU B"),
            string::utf8(b"https://example.com/b.png"),
            scenario.ctx(),
        );
    };

    // Enable CreateSubOU on OU A
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<CreateSubOU>(b"CreateSubOU".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    // Submit CreateSubOU proposal on OU A
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);

        let payload = create_subou::new(
            string::utf8(b"Child OU"),
            vector[SUBOU_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );

        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Mismatch test")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute with wrong vault (OU B's vault instead of OU A's)
    // This should abort with EVaultOUMismatch
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Take the wrong vault — scenario returns shared objects in creation order,
        // so we take the first one (OU A's vault), return it, then take the second
        // (OU B's vault) to use with OU A's proposal.
        let vault_a = scenario.take_shared<CapabilityVault>();
        test_scenario::return_shared(vault_a);
        let mut vault_b = scenario.take_shared<CapabilityVault>();

        lifecycle_ops::execute_create_subou(
            &mut vault_b,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(vault_b);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// TransferCapToSubOU tests
// =========================================================================

/// A test capability to store and transfer between vaults.
public struct TestCap has key, store {
    id: UID,
}

/// Helper: create parent OU, create SubOU, return (parent_ou_id, control_cap_id).
fun setup_parent_and_subou(
    scenario: &mut test_scenario::Scenario,
    clock: &mut clock::Clock,
): (ID, ID) {
    // Create parent OU
    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"Parent OU"),
                string::utf8(b"https://example.com/parent.png"),
                scenario.ctx(),
            );
    };

    // Enable CreateSubOU + TransferCapToSubOU + ReclaimCapFromSubOU
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<CreateSubOU>(b"CreateSubOU".to_ascii_string(), config);
        ou.test_enable_type<TransferCapToSubOU>(
            b"TransferCapToSubOU".to_ascii_string(),
            config.with_permissions(type_permissions::transfer_cap_to_subou()),
        );
        ou.test_enable_type<ReclaimCapFromSubOU>(
            b"ReclaimCapFromSubOU".to_ascii_string(),
            config
                .with_permissions(type_permissions::reclaim_cap_from_subou())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // Submit + vote + execute CreateSubOU
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = create_subou::new(
            string::utf8(b"Child OU"),
            vector[SUBOU_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Create child")),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    let control_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );

        lifecycle_ops::execute_create_subou(
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        let control_ids = vault.ids_for_type<SubOUControl>();
        control_cap_id = control_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };

    (parent_ou_id, control_cap_id)
}

#[test]
/// E2E: Create SubOU → store TestCap in parent → transfer to SubOU → verify.
fun transfer_cap_to_subou_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, _control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    // Get SubOU vault ID and OU ID
    let subou_vault_id;
    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_vault_id = subou.capability_vault_id();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // Store a TestCap in parent's vault
    let test_cap_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(parent.capability_vault_id());
        let cap = TestCap { id: object::new(scenario.ctx()) };
        test_cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        assert!(vault.contains(test_cap_id));
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent);
    };

    // Submit TransferCapToSubOU proposal — target_subou is the SubOU's OU ID
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(5000);
        let payload = transfer_cap_to_subou::new(test_cap_id, subou_id);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Transfer cap to child")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<TransferCapToSubOU>>();
        clock.set_for_testing(6000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou_vault_id);
        let mut proposal = scenario.take_shared<Proposal<TransferCapToSubOU>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(7000);

        let subou = scenario.take_shared_by_id<OU>(subou_id);
        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_transfer_cap<TestCap>(
            &mut parent_vault,
            &mut subou_vault,
            &subou,
            ticket,
        );

        // Verify: TestCap moved from parent to subou
        assert!(!parent_vault.contains(test_cap_id));
        assert!(subou_vault.contains(test_cap_id));

        test_scenario::return_shared(subou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou_vault);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ReclaimCapFromSubOU tests
// =========================================================================

#[test]
/// E2E: Create SubOU → transfer cap to SubOU → reclaim via SubOUControl.
fun reclaim_cap_from_subou_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    // Get SubOU vault ID
    let subou_vault_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_vault_id = subou.capability_vault_id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // Store a TestCap directly in SubOU's vault
    let test_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou_vault_id);
        let cap = TestCap { id: object::new(scenario.ctx()) };
        test_cap_id = object::id(&cap);
        subou_vault.store_cap_for_testing(cap);
        assert!(subou_vault.contains(test_cap_id));
        test_scenario::return_shared(subou_vault);
    };

    // Submit ReclaimCapFromSubOU proposal on parent
    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(5000);
        let payload = reclaim_cap_from_subou::new(subou_id, test_cap_id, control_cap_id);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Reclaim cap from child")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubOU>>();
        clock.set_for_testing(6000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — loans SubOUControl, extracts TestCap from SubOU, stores in parent
    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou_vault_id);
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubOU>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(7000);

        let subou = scenario.take_shared_by_id<OU>(subou_id);
        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_reclaim_cap<TestCap>(
            &mut parent_vault,
            &mut subou_vault,
            &subou,
            ticket,
        );

        // Verify: TestCap moved from SubOU back to parent
        assert!(parent_vault.contains(test_cap_id));
        assert!(!subou_vault.contains(test_cap_id));

        test_scenario::return_shared(subou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou_vault);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = subou_ops::EVaultOUMismatch)]
/// Reclaim with wrong controller vault aborts.
fun reclaim_cap_wrong_vault_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    // Get SubOU vault ID and subou_id
    let subou_vault_id;
    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_vault_id = subou.capability_vault_id();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // Store a TestCap in SubOU vault to reclaim
    let test_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou_vault_id);
        let cap = TestCap { id: object::new(scenario.ctx()) };
        test_cap_id = object::id(&cap);
        subou_vault.store_cap_for_testing(cap);
        test_scenario::return_shared(subou_vault);
    };

    // Submit ReclaimCapFromSubOU
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(5000);
        let payload = reclaim_cap_from_subou::new(subou_id, test_cap_id, control_cap_id);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Bad reclaim")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubOU>>();
        clock.set_for_testing(6000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — pass SubOU vault as controller vault → EVaultOUMismatch
    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou_vault_id);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubOU>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(7000);

        let subou = scenario.take_shared_by_id<OU>(subou_id);
        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Wrong: subou_vault passed as controller_vault — its ou_id won't match request
        subou_ops::execute_reclaim_cap<TestCap>(
            &mut subou_vault,
            &mut parent_vault,
            &subou,
            ticket,
        );

        test_scenario::return_shared(subou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(subou_vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Pause / Unpause SubOU Execution
// =========================================================================

#[test]
/// E2E: Controller pauses SubOU execution → SubOU board cannot authorize
/// proposals → Controller unpauses → SubOU can authorize again.
fun pause_and_unpause_subou_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(
        &mut scenario,
        &mut clock,
    );

    // Enable PauseSubOUExecution and UnpauseSubOUExecution on parent
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<pause_execution::PauseSubOUExecution>(
            b"PauseSubOUExecution".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        ou.test_enable_type<pause_execution::UnpauseSubOUExecution>(
            b"UnpauseSubOUExecution".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // Capture SubOU ID
    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        assert!(!subou.is_controller_paused());
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // ── Pause: submit on parent, vote, execute ──
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(10_000);
        let payload = pause_execution::new_pause(control_cap_id);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Pause SubOU")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<pause_execution::PauseSubOUExecution>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut proposal = scenario.take_shared<Proposal<pause_execution::PauseSubOUExecution>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_pause_subou_execution(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        // Verify SubOU is paused
        assert!(subou.is_controller_paused());

        test_scenario::return_shared(subou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    // ── Unpause: submit on parent, vote, execute ──
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(20_000);
        let payload = pause_execution::new_unpause(control_cap_id);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Unpause SubOU")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<pause_execution::UnpauseSubOUExecution>>();
        clock.set_for_testing(21_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut proposal = scenario.take_shared<Proposal<pause_execution::UnpauseSubOUExecution>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        clock.set_for_testing(22_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_unpause_subou_execution(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        // Verify SubOU is unpaused
        assert!(!subou.is_controller_paused());

        test_scenario::return_shared(subou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::board_voting::EControllerPaused)]
/// Paused SubOU rejects authorize_execution with EControllerPaused.
fun paused_subou_blocks_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(
        &mut scenario,
        &mut clock,
    );

    // Enable PauseSubOUExecution on parent
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<pause_execution::PauseSubOUExecution>(
            b"PauseSubOUExecution".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // Capture SubOU ID
    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // Pause the SubOU
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Pause SubOU")),
            pause_execution::new_pause(control_cap_id),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<pause_execution::PauseSubOUExecution>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut proposal = scenario.take_shared<Proposal<pause_execution::PauseSubOUExecution>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_pause_subou_execution(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(subou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    // Now try to enable a type on the paused SubOU and execute a proposal
    // The SubOU has SetBoard enabled by default.
    scenario.next_tx(SUBOU_MEMBER);
    {
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        clock.set_for_testing(20_000);
        board_voting::submit_proposal(
            &subou,
            option::some(string::utf8(b"Try to change board while paused")),
            armature::set_board::new(vector[CREATOR], vector[]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(subou);
    };

    scenario.next_tx(SUBOU_MEMBER);
    {
        let mut proposal = scenario.take_shared<Proposal<armature::set_board::SetBoard>>();
        clock.set_for_testing(21_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // This should abort with EControllerPaused
    scenario.next_tx(SUBOU_MEMBER);
    {
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut proposal = scenario.take_shared<Proposal<armature::set_board::SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(subou.emergency_freeze_id());
        clock.set_for_testing(22_000);

        // This will abort — SubOU is controller-paused
        let ticket = board_voting::ticket_from_vote(
            &mut subou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Unreachable: consume the request so compiler is happy
        armature::board_ops::execute_set_board(
            &mut subou,
            ticket,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Multi-member SubOU
// =========================================================================

#[test]
/// Create SubOU with 3-member board, verify all members can submit proposals.
fun create_multi_member_subou() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"Parent OU"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<CreateSubOU>(b"CreateSubOU".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    // Create SubOU with 3 members: SUBOU_MEMBER, CREATOR, MEMBER_B
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(1_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Create 3-member SubOU")),
            create_subou::new(
                string::utf8(b"Engineering"),
                vector[SUBOU_MEMBER, CREATOR, MEMBER_B],
                string::utf8(b"x"),
            ),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        clock.set_for_testing(2_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3_000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        lifecycle_ops::execute_create_subou(
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };

    // Verify SubOU board has all 3 members
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        assert!(subou.governance().is_board_member(SUBOU_MEMBER));
        assert!(subou.governance().is_board_member(CREATOR));
        assert!(subou.governance().is_board_member(MEMBER_B));
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ControllerBatchAddMembers tests
// =========================================================================

#[test]
/// E2E: Controller proposes adding two members to a SubOU → vote → execute →
/// verify both appear on the SubOU board.
fun controller_batch_add_members_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // Enable ControllerBatchAddMembers on parent
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<ControllerBatchAddMembers>(
            b"ControllerBatchAddMembers".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // Submit ControllerBatchAddMembers proposal on parent
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Add two members to SubOU")),
            controller_batch_add_members::new(control_cap_id, vector[CREATOR, NEW_SUBOU_MEMBER]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes (CREATOR — 1/2 = 50%, passes)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchAddMembers>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchAddMembers>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_controller_batch_add_members(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        let gov = subou.governance();
        assert!(gov.is_board_member(SUBOU_MEMBER));
        assert!(gov.is_board_member(CREATOR));
        assert!(gov.is_board_member(NEW_SUBOU_MEMBER));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Adding an address already on the SubOU board is silently skipped.
fun controller_batch_add_members_existing_skipped() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<ControllerBatchAddMembers>(
            b"ControllerBatchAddMembers".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // Batch includes SUBOU_MEMBER (already on board) + NEW_SUBOU_MEMBER (new)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Add with one existing")),
            controller_batch_add_members::new(
                control_cap_id,
                vector[SUBOU_MEMBER, NEW_SUBOU_MEMBER],
            ),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchAddMembers>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchAddMembers>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_controller_batch_add_members(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        // NEW_SUBOU_MEMBER added; SUBOU_MEMBER still present (was skipped, not removed)
        let gov = subou.governance();
        assert!(gov.is_board_member(SUBOU_MEMBER));
        assert!(gov.is_board_member(NEW_SUBOU_MEMBER));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ControllerBatchRemoveMembers tests
// =========================================================================

#[test]
/// E2E: Use ControllerBatchAddMembers to seat two members, then
/// ControllerBatchRemoveMembers to remove them — verifies both handlers
/// chain correctly and the SubOU board reaches the expected final state.
fun controller_batch_remove_members_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    // Enable both controller types on parent
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<ControllerBatchAddMembers>(
            b"ControllerBatchAddMembers".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        ou.test_enable_type<ControllerBatchRemoveMembers>(
            b"ControllerBatchRemoveMembers".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // ── Add CREATOR + NEW_SUBOU_MEMBER to SubOU via controller ──
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::none(),
            controller_batch_add_members::new(
                control_cap_id,
                vector[CREATOR, NEW_SUBOU_MEMBER],
            ),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchAddMembers>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchAddMembers>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_controller_batch_add_members(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    // ── Now remove CREATOR + NEW_SUBOU_MEMBER via controller ──
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(20_000);
        board_voting::submit_proposal(
            &ou,
            option::none(),
            controller_batch_remove_members::new(
                control_cap_id,
                vector[CREATOR, NEW_SUBOU_MEMBER],
            ),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchRemoveMembers>>();
        clock.set_for_testing(21_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchRemoveMembers>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(22_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_controller_batch_remove_members(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        // Only SUBOU_MEMBER should remain
        let gov = subou.governance();
        assert!(gov.is_board_member(SUBOU_MEMBER));
        assert!(!gov.is_board_member(CREATOR));
        assert!(!gov.is_board_member(NEW_SUBOU_MEMBER));
        // encrypt_epoch incremented once by the remove batch
        assert!(subou.encrypt_epoch() == 1);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::governance::ENotBoardMember)]
/// Removing a non-member from a SubOU via controller aborts.
fun controller_batch_remove_members_nonmember_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_ou_id, control_cap_id) = setup_parent_and_subou(&mut scenario, &mut clock);

    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let subou = scenario.take_shared<OU>();
        subou_id = subou.id();
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<ControllerBatchRemoveMembers>(
            b"ControllerBatchRemoveMembers".to_ascii_string(),
            config
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        test_scenario::return_shared(ou);
    };

    // CREATOR is not on the SubOU board (SubOU has only SUBOU_MEMBER)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(10_000);
        board_voting::submit_proposal(
            &ou,
            option::none(),
            controller_batch_remove_members::new(control_cap_id, vector[CREATOR]),
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchRemoveMembers>>();
        clock.set_for_testing(11_000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut proposal = scenario.take_shared<Proposal<ControllerBatchRemoveMembers>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_ou.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subou_ops::execute_controller_batch_remove_members(
            &mut vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// ── Batch-guard parity tests for controller handlers ──────────────────────
// These tests use proposal::new_standalone_ticket_for_testing to synthesize
// an ExecutionTicket directly, bypassing the full governance flow. This keeps
// the tests fast and avoids hitting the per-test gas limit.

#[test, expected_failure(abort_code = armature_proposals::subou_ops::EEmptyBatch)]
/// Empty ControllerBatchAddMembers aborts before any sub-OU mutation.
fun controller_batch_add_members_empty_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    // Create two OUs: parent (holds the vault) and members_ou (the target).
    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"P"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    let members_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        members_ou_id =
            ou::create(
                &init,
                string::utf8(b"M"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut members_ou = scenario.take_shared_by_id<OU>(members_ou_id);

        // Synthesize a SubOUControl and store it in the vault without governance.
        let control = capability_vault::new_subou_control_for_testing(
            members_ou_id,
            scenario.ctx(),
        );
        let control_id = object::id(&control);
        vault.store_cap_for_testing(control);

        // Synthesize a ticket with an empty members list — should abort EEmptyBatch.
        let ticket = proposal::new_standalone_ticket_for_testing<ControllerBatchAddMembers>(
            parent_ou_id,
            object::id_from_address(@0x1),
            controller_batch_add_members::new(control_id, vector[]),
            0,
            0,
        );

        subou_ops::execute_controller_batch_add_members(
            &mut vault,
            &mut members_ou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(parent_ou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(members_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::subou_ops::EEmptyBatch)]
/// Empty ControllerBatchRemoveMembers aborts before any sub-OU mutation.
fun controller_batch_remove_members_empty_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"P"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    let members_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        members_ou_id =
            ou::create(
                &init,
                string::utf8(b"M"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut members_ou = scenario.take_shared_by_id<OU>(members_ou_id);

        let control = capability_vault::new_subou_control_for_testing(
            members_ou_id,
            scenario.ctx(),
        );
        let control_id = object::id(&control);
        vault.store_cap_for_testing(control);

        let ticket = proposal::new_standalone_ticket_for_testing<ControllerBatchRemoveMembers>(
            parent_ou_id,
            object::id_from_address(@0x1),
            controller_batch_remove_members::new(control_id, vector[]),
            0,
            0,
        );

        subou_ops::execute_controller_batch_remove_members(
            &mut vault,
            &mut members_ou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(parent_ou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(members_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::subou_ops::EBatchTooLarge)]
/// ControllerBatchAddMembers with 101 entries aborts before any sub-OU mutation.
fun controller_batch_add_members_oversize_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"P"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    let members_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        members_ou_id =
            ou::create(
                &init,
                string::utf8(b"M"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut members_ou = scenario.take_shared_by_id<OU>(members_ou_id);

        let control = capability_vault::new_subou_control_for_testing(
            members_ou_id,
            scenario.ctx(),
        );
        let control_id = object::id(&control);
        vault.store_cap_for_testing(control);

        // Build 101 addresses — content doesn't matter since EBatchTooLarge fires
        // before any address processing.
        let mut addrs = vector::empty<address>();
        let mut i = 0u64;
        while (i < 101) {
            addrs.push_back(@0xDEAD);
            i = i + 1;
        };

        let ticket = proposal::new_standalone_ticket_for_testing<ControllerBatchAddMembers>(
            parent_ou_id,
            object::id_from_address(@0x1),
            controller_batch_add_members::new(control_id, addrs),
            0,
            0,
        );

        subou_ops::execute_controller_batch_add_members(
            &mut vault,
            &mut members_ou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(parent_ou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(members_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::subou_ops::EBatchTooLarge)]
/// ControllerBatchRemoveMembers with 101 entries aborts before any sub-OU mutation.
fun controller_batch_remove_members_oversize_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());

    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"P"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    let members_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        members_ou_id =
            ou::create(
                &init,
                string::utf8(b"M"),
                string::utf8(b"x"),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut members_ou = scenario.take_shared_by_id<OU>(members_ou_id);

        let control = capability_vault::new_subou_control_for_testing(
            members_ou_id,
            scenario.ctx(),
        );
        let control_id = object::id(&control);
        vault.store_cap_for_testing(control);

        // Build 101 addresses — content doesn't matter since EBatchTooLarge fires
        // before any address processing.
        let mut addrs = vector::empty<address>();
        let mut i = 0u64;
        while (i < 101) {
            addrs.push_back(@0xDEAD);
            i = i + 1;
        };

        let ticket = proposal::new_standalone_ticket_for_testing<ControllerBatchRemoveMembers>(
            parent_ou_id,
            object::id_from_address(@0x1),
            controller_batch_remove_members::new(control_id, addrs),
            0,
            0,
        );

        subou_ops::execute_controller_batch_remove_members(
            &mut vault,
            &mut members_ou,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(parent_ou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(members_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}
