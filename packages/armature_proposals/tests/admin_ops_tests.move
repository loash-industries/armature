#[test_only]
module armature_proposals::admin_ops_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_proposals::admin_ops;
use armature_proposals::disable_proposal_type::{Self, DisableProposalType};
use armature_proposals::enable_proposal_type::{Self, EnableProposalType};
use armature_proposals::update_proposal_config::{Self, UpdateProposalConfig};
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;

// === Test helpers ===

/// Create a standalone DAO (no controller) with a single board member.
fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"A test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Create a SubDAO with a controller cap ID set, then share it.
fun create_and_share_subdao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subdao, freeze_cap) = dao::create_subdao(
            &init,
            string::utf8(b"Sub DAO"),
            string::utf8(b"A test sub-DAO"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        // Use the FreezeAdminCap's object ID as a stand-in controller cap ID.
        let controller_id = sui::object::id(&freeze_cap);
        dao::share_subdao(subdao, controller_id);
        std::unit_test::destroy(freeze_cap);
    };
}

/// Submit an EnableProposalType proposal for the given type key.
fun submit_enable_type_proposal(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    type_key: vector<u8>,
) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(type_key.to_ascii_string(), config);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            option::some(string::utf8(b"Enable proposal type")),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
}

/// Vote yes on the pending proposal (single board member → 100% approval).
fun vote_yes(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        proposal.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
}

// === Tests ===

#[test, expected_failure(abort_code = admin_ops::ESubDAOBlockedType)]
/// SubDAO with a controller cannot enable hierarchy-altering types (SpawnDAO).
fun enable_blocked_type_aborts_for_subdao_with_controller() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subdao(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal(&mut scenario, &clock, b"SpawnDAO");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    // Execute — must abort with ESubDAOBlockedType
    scenario.next_tx(CREATOR);
    {
        let mut subdao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut subdao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut subdao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// SubDAO with a controller CAN enable a non-blocked type.
fun enable_non_blocked_type_succeeds_for_subdao_with_controller() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subdao(&mut scenario);
    clock.set_for_testing(1000);
    // "TreasuryWithdraw" is not in SUBDAO_BLOCKED_TYPES but IS in the SubDAO defaults —
    // use a custom key that isn't pre-enabled to avoid a duplicate-insert abort.
    submit_enable_type_proposal(&mut scenario, &clock, b"CustomAction");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut subdao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut subdao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut subdao, &proposal, request);

        // Verify the type was added
        assert!(subdao.enabled_proposal_types().contains(&b"CustomAction".to_ascii_string()));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(subdao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Independent DAO (no controller) CAN enable a hierarchy-altering type (SpawnDAO).
fun enable_blocked_type_succeeds_for_independent_dao() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal(&mut scenario, &clock, b"SpawnDAO");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut dao, &proposal, request);

        // Verify SpawnDAO is now enabled
        assert!(dao.enabled_proposal_types().contains(&b"SpawnDAO".to_ascii_string()));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Security invariant tests (#90)
// =========================================================================

// --- DisableProposalType cannot disable core types ---

#[test, expected_failure(abort_code = admin_ops::EUndisableableType)]
/// Cannot disable EnableProposalType (core undisableable type).
fun disable_core_type_enable_proposal_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Submit DisableProposalType proposal targeting "EnableProposalType"
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = disable_proposal_type::new(b"EnableProposalType".to_ascii_string());
        board_voting::submit_proposal(
            &dao,
            b"DisableProposalType".to_ascii_string(),
            option::some(string::utf8(b"Try to disable core type")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EUndisableableType
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = admin_ops::EUndisableableType)]
/// Cannot disable UnfreezeProposalType (core undisableable type).
fun disable_core_type_unfreeze_proposal_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = disable_proposal_type::new(b"UnfreezeProposalType".to_ascii_string());
        board_voting::submit_proposal(
            &dao,
            b"DisableProposalType".to_ascii_string(),
            option::some(string::utf8(b"Try to disable core type")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- EnableProposalType 66% approval floor ---

const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;
const MEMBER_D: address = @0xD;
const MEMBER_E: address = @0xE;

#[test, expected_failure(abort_code = admin_ops::EApprovalFloorNotMet)]
/// EnableProposalType handler enforces a 66% approval floor.
/// A proposal passing with only 40% yes (2/5 board) is rejected at execution.
fun enable_proposal_type_66_percent_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create DAO with 5 board members
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, MEMBER_C, MEMBER_D, MEMBER_E]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Approval floor test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Override EnableProposalType config: low quorum + threshold so 2/5 passes voting
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000, // quorum 50% (but we override threshold below)
            5_000, // approval_threshold 50%
            0, // propose_threshold
            604_800_000, // expiry
            0, // execution_delay
            0, // cooldown
        );
        dao.test_update_config(b"EnableProposalType".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit EnableProposalType proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(b"CustomAction".to_ascii_string(), config);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            option::some(string::utf8(b"Enable custom action")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // 3 of 5 board members vote yes (60% of snapshot — passes 50% threshold but below 66% floor)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(3000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_C);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(4000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EApprovalFloorNotMet (3/5 = 60% < 66% of total_snapshot)
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(5000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- UpdateProposalConfig 80% self-referential floor ---

#[test, expected_failure(abort_code = admin_ops::EApprovalFloorNotMet)]
/// UpdateProposalConfig targeting itself enforces an 80% approval floor.
/// A proposal passing with 60% yes (3/5 board) is rejected.
fun update_proposal_config_self_80_percent_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create DAO with 5 board members
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, MEMBER_C, MEMBER_D, MEMBER_E]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Self-update floor test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Override UpdateProposalConfig config with quorum needing 3+ votes
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            6_000, // quorum 60% (need 3 of 5)
            5_000, // approval_threshold 50%
            0,
            604_800_000,
            0,
            0,
        );
        dao.test_update_config(b"UpdateProposalConfig".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit UpdateProposalConfig proposal targeting ITSELF
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"UpdateProposalConfig".to_ascii_string(),
            option::some(3_000), // new quorum
            option::none(), // keep threshold
            option::none(), // keep propose_threshold
            option::none(), // keep expiry
            option::none(), // keep execution_delay
            option::none(), // keep cooldown
        );
        board_voting::submit_proposal(
            &dao,
            b"UpdateProposalConfig".to_ascii_string(),
            option::some(string::utf8(b"Lower own quorum")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // 3 of 5 board members vote yes (60% — passes quorum but below 80% floor)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(3000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_C);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(4000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EApprovalFloorNotMet (3/5 = 60% < 80%)
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(5000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// UpdateProposalConfig targeting a DIFFERENT type does NOT enforce the 80% floor.
/// A proposal passing with 60% yes (3/5 board) succeeds when targeting SetBoard.
fun update_proposal_config_non_self_target_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create DAO with 5 board members
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, MEMBER_C, MEMBER_D, MEMBER_E]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Non-self update test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Override UpdateProposalConfig config with quorum needing 3+ votes
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            6_000, // quorum 60% (need 3 of 5)
            5_000, // approval_threshold 50%
            0,
            604_800_000,
            0,
            0,
        );
        dao.test_update_config(b"UpdateProposalConfig".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit UpdateProposalConfig targeting SetBoard (not self)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"SetBoard".to_ascii_string(),
            option::some(3_000), // new quorum for SetBoard
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        );
        board_voting::submit_proposal(
            &dao,
            b"UpdateProposalConfig".to_ascii_string(),
            option::some(string::utf8(b"Lower SetBoard quorum")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // 3 of 5 vote yes (60% — no 80% floor for non-self targets)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(3000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_C);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(4000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should succeed (no 80% floor for SetBoard target)
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(5000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, &proposal, request);

        // Verify SetBoard quorum was updated
        let new_config = dao.proposal_configs().get(&b"SetBoard".to_ascii_string());
        assert!(new_config.quorum() == 3_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EThresholdBelowFloor tests
// =========================================================================

#[test, expected_failure(abort_code = admin_ops::EThresholdBelowFloor)]
/// UpdateProposalConfig cannot lower EnableProposalType threshold below 66% floor.
fun update_config_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Submit UpdateProposalConfig targeting EnableProposalType with threshold=5000 (below 6600
    // floor)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"EnableProposalType".to_ascii_string(),
            option::none(), // keep quorum
            option::some(5_000), // lower threshold to 50% — below 66% floor
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        );
        board_voting::submit_proposal(
            &dao,
            b"UpdateProposalConfig".to_ascii_string(),
            option::some(string::utf8(b"Lower EnableProposalType threshold")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes (single-member board → 100% approval, passes 80% floor)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EThresholdBelowFloor
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = admin_ops::EThresholdBelowFloor)]
/// EnableProposalType cannot enable a floor-gated type with a sub-floor threshold.
/// Uses a SubDAO that has had UpdateProposalConfig disabled via test helper,
/// then tries to re-enable it with a threshold below the 80% floor.
fun enable_type_with_sub_floor_config_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subdao(&mut scenario);

    // Disable UpdateProposalConfig on the SubDAO via test helper so we can re-enable it
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        dao.test_disable_type(b"UpdateProposalConfig".to_ascii_string());
        test_scenario::return_shared(dao);
    };

    // Submit EnableProposalType proposal to re-enable UpdateProposalConfig with threshold=5000
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        // 5000 (50%) is below the 80% floor for UpdateProposalConfig
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(
            b"UpdateProposalConfig".to_ascii_string(),
            config,
        );
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            option::some(string::utf8(b"Re-enable UpdateProposalConfig with weak threshold")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EThresholdBelowFloor
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type(&mut dao, &proposal, request);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
