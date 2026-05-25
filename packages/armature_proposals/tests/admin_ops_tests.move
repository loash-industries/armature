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

// === Test payload types ===

/// Stand-in third-party payload for type binding tests.
public struct TestPayload has drop, store { value: u64 }

/// Alternative payload used to verify binding rejects wrong types.
public struct AltPayload has drop, store { label: u64 }

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

        let ticket = board_voting::ticket_from_vote(
            &mut subdao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<EnableProposalType>(
            &mut subdao,
            ticket,
        );

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

        let ticket = board_voting::ticket_from_vote(
            &mut subdao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<EnableProposalType>(
            &mut subdao,
            ticket,
        );

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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<EnableProposalType>(&mut dao, ticket);

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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut dao, ticket);

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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut dao, ticket);

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

#[test, expected_failure(abort_code = 6, location = armature::board_voting)]
/// EnableProposalType submission is rejected when the DAO's config has an
/// approval_threshold below the 66% floor (EFloorNotMet). The abort happens at
/// submit_proposal, before the proposal enters the object graph.
fun enable_proposal_type_submission_floor_rejects_below_66_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Lower EnableProposalType threshold to 65% (6500 bps) via test helper.
    // Any proposal submitted while this config is active must be rejected.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 6_500, 0, 604_800_000, 0, 0);
        dao.test_update_config(b"EnableProposalType".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit EnableProposalType proposal — must abort with EFloorNotMet (6500 < 6600).
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(b"CustomAction".to_ascii_string(), config);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// EnableProposalType submission succeeds when the DAO's config has
/// approval_threshold exactly at the 66% floor (6600 bps).
fun enable_proposal_type_submission_floor_allows_66_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Set EnableProposalType threshold to exactly 66% (6600 bps).
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 6_600, 0, 604_800_000, 0, 0);
        dao.test_update_config(b"EnableProposalType".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit should succeed (6600 >= 6600).
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(b"CustomAction".to_ascii_string(), config);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- UpdateProposalConfig 80% self-referential floor ---

#[test, expected_failure(abort_code = admin_ops::EFloorNotMet)]
/// propose_update_proposal_config rejects a self-targeting submission when the
/// DAO's UpdateProposalConfig threshold is below 80%. The abort happens before
/// the proposal enters the object graph.
fun update_proposal_config_self_submission_floor_rejects_below_80_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // Lower UpdateProposalConfig threshold to 51% via test helper.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_100, 0, 604_800_000, 0, 0);
        dao.test_update_config(b"UpdateProposalConfig".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Submit self-targeting UpdateProposalConfig via the wrapper — must abort with EFloorNotMet.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"UpdateProposalConfig".to_ascii_string(), // self-target
            option::some(3_000),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        );
        admin_ops::propose_update_proposal_config(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// propose_update_proposal_config accepts a self-targeting submission when the
/// DAO's UpdateProposalConfig threshold is exactly at the 80% floor (8000 bps).
fun update_proposal_config_self_submission_floor_allows_80_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);
    // Default UpdateProposalConfig threshold is 8000 (80%) — no override needed.

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"UpdateProposalConfig".to_ascii_string(), // self-target
            option::some(8_000), // keep at 80% — floor check passes
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        );
        admin_ops::propose_update_proposal_config(
            &dao,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, ticket);

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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, ticket);

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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<EnableProposalType>(&mut dao, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Type binding tests for execute_enable_proposal_type
// =========================================================================

/// Full lifecycle helper: submit + vote + authorize + execute enable for type_key.
fun run_enable_type<NewType: store>(
    scenario: &mut test_scenario::Scenario,
    clock: &mut clock::Clock,
    type_key: vector<u8>,
    ts_submit: u64,
    ts_vote: u64,
    ts_exec: u64,
) {
    clock.set_for_testing(ts_submit);
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(type_key.to_ascii_string(), config);
        board_voting::submit_proposal(
            &dao,
            b"EnableProposalType".to_ascii_string(),
            option::none(),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    clock.set_for_testing(ts_vote);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        proposal.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(ts_exec);
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<NewType>(&mut dao, ticket);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };
}

#[test]
/// execute_enable_proposal_type<NewType> stores a type binding for the key.
fun execute_enable_proposal_type_binds_type_key() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);
    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.has_type_binding(&b"MyGrant".to_ascii_string()));
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Re-enabling a previously disabled key with the SAME NewType is idempotent — succeeds.
fun execute_enable_proposal_type_idempotent_for_same_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // First enable — binds TestPayload to "MyGrant"
    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);

    // Disable "MyGrant" via test helper (binding is kept)
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        dao.test_disable_type(b"MyGrant".to_ascii_string());
        test_scenario::return_shared(dao);
    };

    // Re-enable with the SAME TestPayload — should succeed (idempotent binding)
    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 4000, 5000, 6000);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.has_type_binding(&b"MyGrant".to_ascii_string()));
        assert!(dao.enabled_proposal_types().contains(&b"MyGrant".to_ascii_string()));
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = 10, location = armature::dao)]
/// Re-enabling a disabled key with a DIFFERENT NewType aborts with ETypeBindingMismatch.
fun execute_enable_proposal_type_binding_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // First enable — binds TestPayload to "MyGrant"
    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);

    // Disable
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        dao.test_disable_type(b"MyGrant".to_ascii_string());
        test_scenario::return_shared(dao);
    };

    // Re-enable with AltPayload — should abort with ETypeBindingMismatch
    run_enable_type<AltPayload>(&mut scenario, &mut clock, b"MyGrant", 4000, 5000, 6000);

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// composable_allowed field on UpdateProposalConfig
// =========================================================================

#[test]
/// execute_update_proposal_config correctly applies the composable_allowed override.
/// Starts with AddMember (composable by default), disables it via UpdateProposalConfig
/// with composable_allowed: some(false), then re-enables it with some(true) and verifies
/// each state transition on the DAO config.
fun update_proposal_config_composable_allowed_updates_config() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao(&mut scenario);

    // AddMember is composable by default — confirm baseline.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        assert!(dao.proposal_configs().get(&b"AddMember".to_ascii_string()).composable_allowed());
        test_scenario::return_shared(dao);
    };

    // Submit UpdateProposalConfig for AddMember with composable_allowed: some(false).
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"AddMember".to_ascii_string(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(false), // disable composability
        );
        board_voting::submit_proposal(
            &dao,
            b"UpdateProposalConfig".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, ticket);

        // Composability is now false.
        assert!(!dao.proposal_configs().get(&b"AddMember".to_ascii_string()).composable_allowed());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // Submit a second UpdateProposalConfig to re-enable composability.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(4000);
        let payload = update_proposal_config::new(
            b"AddMember".to_ascii_string(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(true), // re-enable composability
        );
        board_voting::submit_proposal(
            &dao,
            b"UpdateProposalConfig".to_ascii_string(),
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(5000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(6000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut dao, ticket);

        // Composability is restored.
        assert!(dao.proposal_configs().get(&b"AddMember".to_ascii_string()).composable_allowed());

        // Other fields are preserved — quorum unchanged from default.
        let cfg = dao.proposal_configs().get(&b"AddMember".to_ascii_string());
        assert!(cfg.quorum() == 5_000);
        assert!(cfg.approval_threshold() == 5_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
