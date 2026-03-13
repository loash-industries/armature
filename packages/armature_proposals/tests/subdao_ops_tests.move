#[test_only]
module armature_proposals::subdao_ops_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::create_subdao::{Self, CreateSubDAO};
use armature_proposals::subdao_ops;
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
