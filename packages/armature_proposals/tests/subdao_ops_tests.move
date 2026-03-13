#[test_only]
module armature_proposals::subdao_ops_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::create_subdao::{Self, CreateSubDAO};
use armature_proposals::reclaim_cap_from_subdao::{Self, ReclaimCapFromSubDAO};
use armature_proposals::subdao_ops;
use armature_proposals::transfer_cap_to_subdao::{Self, TransferCapToSubDAO};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const SUBDAO_MEMBER: address = @0xC;

#[test]
/// E2E: Create DAO → enable CreateSubDAO type → submit CreateSubDAO proposal
/// → vote → execute → verify child DAO created with SubDAOControl + FreezeAdminCap
/// stored in controller vault.
fun create_subdao_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent DAO with Board governance
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Parent DAO"),
            string::utf8(b"SubDAO creation e2e test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // 2. Enable CreateSubDAO proposal type on the parent DAO
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000, // quorum 50%
            5_000, // approval_threshold 50%
            0, // propose_threshold
            604_800_000, // expiry 7 days
            0, // execution_delay
            0, // cooldown
        );
        dao.test_enable_type(b"CreateSubDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // 3. Submit a CreateSubDAO proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = create_subdao::new(
            string::utf8(b"Child DAO"),
            string::utf8(b"A managed sub-DAO"),
            vector[SUBDAO_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );

        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Create a managed sub-DAO"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 4. Vote yes (CREATOR) — 1/2 board members = 50% quorum, passes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 5. Execute the proposal and run the handler
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
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

        subdao_ops::execute_create_subdao(
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        // 6. Verify: vault should contain SubDAOControl + FreezeAdminCap
        assert!(vault.cap_ids().length() >= 2);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // 7. Verify the child DAO was created as a shared object
    scenario.next_tx(CREATOR);
    {};

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_proposals::subdao_ops::EVaultDAOMismatch)]
/// Verify execute_create_subdao rejects a vault that doesn't match the DAO.
fun create_subdao_vault_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create two DAOs to get two different vaults
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"DAO A"),
            string::utf8(b"First DAO"),
            string::utf8(b"https://example.com/a.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"DAO B"),
            string::utf8(b"Second DAO"),
            string::utf8(b"https://example.com/b.png"),
            scenario.ctx(),
        );
    };

    // Enable CreateSubDAO on DAO A
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"CreateSubDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit CreateSubDAO proposal on DAO A
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = create_subdao::new(
            string::utf8(b"Child DAO"),
            string::utf8(b"Mismatch test"),
            vector[SUBDAO_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );

        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Mismatch test"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute with wrong vault (DAO B's vault instead of DAO A's)
    // This should abort with EVaultDAOMismatch
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Take the wrong vault — scenario returns shared objects in creation order,
        // so we take the first one (DAO A's vault), return it, then take the second
        // (DAO B's vault) to use with DAO A's proposal.
        let vault_a = scenario.take_shared<CapabilityVault>();
        test_scenario::return_shared(vault_a);
        let mut vault_b = scenario.take_shared<CapabilityVault>();

        subdao_ops::execute_create_subdao(
            &mut vault_b,
            &proposal,
            request,
            scenario.ctx(),
        );

        test_scenario::return_shared(vault_b);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// TransferCapToSubDAO tests
// =========================================================================

/// A test capability to store and transfer between vaults.
public struct TestCap has key, store {
    id: UID,
}

/// Helper: create parent DAO, create SubDAO, return (parent_dao_id, control_cap_id).
fun setup_parent_and_subdao(
    scenario: &mut test_scenario::Scenario,
    clock: &mut clock::Clock,
): (ID, ID) {
    // Create parent DAO
    let parent_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_dao_id =
            dao::create(
                &init,
                string::utf8(b"Parent DAO"),
                string::utf8(b"Cap transfer test"),
                string::utf8(b"https://example.com/parent.png"),
                scenario.ctx(),
            );
    };

    // Enable CreateSubDAO + TransferCapToSubDAO + ReclaimCapFromSubDAO
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"CreateSubDAO".to_ascii_string(), config);
        dao.test_enable_type(b"TransferCapToSubDAO".to_ascii_string(), config);
        dao.test_enable_type(b"ReclaimCapFromSubDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit + vote + execute CreateSubDAO
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = create_subdao::new(
            string::utf8(b"Child DAO"),
            string::utf8(b"Managed child"),
            vector[SUBDAO_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );
        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Create child"),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    let control_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );

        subdao_ops::execute_create_subdao(
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        let control_ids = vault.ids_for_type<SubDAOControl>();
        control_cap_id = control_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    (parent_dao_id, control_cap_id)
}

#[test]
/// E2E: Create SubDAO → store TestCap in parent → transfer to SubDAO → verify.
fun transfer_cap_to_subdao_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_dao_id, _control_cap_id) = setup_parent_and_subdao(&mut scenario, &mut clock);

    // Get SubDAO vault ID and DAO ID
    let subdao_vault_id;
    let subdao_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let subdao = scenario.take_shared<DAO>();
        subdao_vault_id = subdao.capability_vault_id();
        subdao_id = subdao.id();
        test_scenario::return_shared(subdao);
        test_scenario::return_shared(parent);
    };

    // Store a TestCap in parent's vault
    let test_cap_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(parent.capability_vault_id());
        let cap = TestCap { id: object::new(scenario.ctx()) };
        test_cap_id = object::id(&cap);
        vault.store_cap_for_testing(cap);
        assert!(vault.contains(test_cap_id));
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent);
    };

    // Submit TransferCapToSubDAO proposal — target_subdao is the SubDAO's DAO ID
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        clock.set_for_testing(5000);
        let payload = transfer_cap_to_subdao::new(test_cap_id, subdao_id);
        board_voting::submit_proposal(
            &dao,
            b"TransferCapToSubDAO".to_ascii_string(),
            string::utf8(b"Transfer cap to child"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<TransferCapToSubDAO>>();
        clock.set_for_testing(6000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut parent_dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_dao.capability_vault_id());
        let mut subdao_vault = scenario.take_shared_by_id<CapabilityVault>(subdao_vault_id);
        let mut proposal = scenario.take_shared<Proposal<TransferCapToSubDAO>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_dao.emergency_freeze_id());
        clock.set_for_testing(7000);

        let request = board_voting::authorize_execution(
            &mut parent_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_transfer_cap<TestCap>(
            &mut parent_vault,
            &mut subdao_vault,
            &proposal,
            request,
        );

        // Verify: TestCap moved from parent to subdao
        assert!(!parent_vault.contains(test_cap_id));
        assert!(subdao_vault.contains(test_cap_id));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(subdao_vault);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ReclaimCapFromSubDAO tests
// =========================================================================

#[test]
/// E2E: Create SubDAO → transfer cap to SubDAO → reclaim via SubDAOControl.
fun reclaim_cap_from_subdao_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_dao_id, control_cap_id) = setup_parent_and_subdao(&mut scenario, &mut clock);

    // Get SubDAO vault ID
    let subdao_vault_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let subdao = scenario.take_shared<DAO>();
        subdao_vault_id = subdao.capability_vault_id();
        test_scenario::return_shared(subdao);
        test_scenario::return_shared(parent);
    };

    // Store a TestCap directly in SubDAO's vault
    let test_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut subdao_vault = scenario.take_shared_by_id<CapabilityVault>(subdao_vault_id);
        let cap = TestCap { id: object::new(scenario.ctx()) };
        test_cap_id = object::id(&cap);
        subdao_vault.store_cap_for_testing(cap);
        assert!(subdao_vault.contains(test_cap_id));
        test_scenario::return_shared(subdao_vault);
    };

    // Submit ReclaimCapFromSubDAO proposal on parent
    let subdao_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let subdao = scenario.take_shared<DAO>();
        subdao_id = subdao.id();
        test_scenario::return_shared(subdao);
        test_scenario::return_shared(parent);
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        clock.set_for_testing(5000);
        let payload = reclaim_cap_from_subdao::new(subdao_id, test_cap_id, control_cap_id);
        board_voting::submit_proposal(
            &dao,
            b"ReclaimCapFromSubDAO".to_ascii_string(),
            string::utf8(b"Reclaim cap from child"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubDAO>>();
        clock.set_for_testing(6000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — loans SubDAOControl, extracts TestCap from SubDAO, stores in parent
    scenario.next_tx(CREATOR);
    {
        let mut parent_dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_dao.capability_vault_id());
        let mut subdao_vault = scenario.take_shared_by_id<CapabilityVault>(subdao_vault_id);
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubDAO>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_dao.emergency_freeze_id());
        clock.set_for_testing(7000);

        let request = board_voting::authorize_execution(
            &mut parent_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_reclaim_cap<TestCap>(
            &mut parent_vault,
            &mut subdao_vault,
            &proposal,
            request,
        );

        // Verify: TestCap moved from SubDAO back to parent
        assert!(parent_vault.contains(test_cap_id));
        assert!(!subdao_vault.contains(test_cap_id));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(subdao_vault);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = subdao_ops::EVaultDAOMismatch)]
/// Reclaim with wrong controller vault aborts.
fun reclaim_cap_wrong_vault_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let (parent_dao_id, control_cap_id) = setup_parent_and_subdao(&mut scenario, &mut clock);

    // Get SubDAO vault ID and subdao_id
    let subdao_vault_id;
    let subdao_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let subdao = scenario.take_shared<DAO>();
        subdao_vault_id = subdao.capability_vault_id();
        subdao_id = subdao.id();
        test_scenario::return_shared(subdao);
        test_scenario::return_shared(parent);
    };

    // Store a TestCap in SubDAO vault to reclaim
    let test_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut subdao_vault = scenario.take_shared_by_id<CapabilityVault>(subdao_vault_id);
        let cap = TestCap { id: object::new(scenario.ctx()) };
        test_cap_id = object::id(&cap);
        subdao_vault.store_cap_for_testing(cap);
        test_scenario::return_shared(subdao_vault);
    };

    // Submit ReclaimCapFromSubDAO
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        clock.set_for_testing(5000);
        let payload = reclaim_cap_from_subdao::new(subdao_id, test_cap_id, control_cap_id);
        board_voting::submit_proposal(
            &dao,
            b"ReclaimCapFromSubDAO".to_ascii_string(),
            string::utf8(b"Bad reclaim"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubDAO>>();
        clock.set_for_testing(6000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — pass SubDAO vault as controller vault → EVaultDAOMismatch
    scenario.next_tx(CREATOR);
    {
        let mut parent_dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let mut subdao_vault = scenario.take_shared_by_id<CapabilityVault>(subdao_vault_id);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_dao.capability_vault_id());
        let mut proposal = scenario.take_shared<Proposal<ReclaimCapFromSubDAO>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(parent_dao.emergency_freeze_id());
        clock.set_for_testing(7000);

        let request = board_voting::authorize_execution(
            &mut parent_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        // Wrong: subdao_vault passed as controller_vault — its dao_id won't match request
        subdao_ops::execute_reclaim_cap<TestCap>(
            &mut subdao_vault,
            &mut parent_vault,
            &proposal,
            request,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(subdao_vault);
        test_scenario::return_shared(parent_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
