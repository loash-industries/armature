#[test_only]
module armature_proposals::admin_ops_tests;

use armature::add_member::AddMember;
use armature::admin_ops;
use armature::board_voting;
use armature::disable_proposal_type::{Self, DisableProposalType};
use armature::emergency::EmergencyFreeze;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal::{Self, Proposal};
use armature::set_board::SetBoard;
use armature::spawn_ou::SpawnOU;
use armature::update_proposal_config::{Self, UpdateProposalConfig};
use std::string;
use std::type_name;
use sui::clock;
use sui::test_scenario;

// === Test payload types ===

/// Stand-in third-party payload for type-slot tests.
public struct TestPayload has drop, store { value: u64 }

/// Alternative payload used to verify the executor cannot swap the approved type.
public struct AltPayload has drop, store { label: u64 }

const CREATOR: address = @0xA;

// === Test helpers ===

/// Create a standalone OU (no controller) with a single board member.
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

/// Create a SubOU with a controller cap ID set, then share it.
fun create_and_share_subou(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        let (subou, freeze_cap) = ou::create_subou(
            &init,
            string::utf8(b"Sub OU"),
            string::utf8(b"https://example.com/sub.png"),
            scenario.ctx(),
        );
        // Use the FreezeAdminCap's object ID as a stand-in controller cap ID.
        let controller_id = sui::object::id(&freeze_cap);
        ou::share_subou(subou, controller_id);
        std::unit_test::destroy(freeze_cap);
    };
}

/// Submit an EnableProposalType proposal enabling `NewType` under the given display key.
fun submit_enable_type_proposal<NewType>(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    type_key: vector<u8>,
) {
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        // Framework types carry fixed bits; meet the floor those bits need.
        let bits = ou::framework_permissions(&type_name::with_defining_ids<NewType>());
        let threshold = ou::permission_floor(bits).max(5_000);
        let config = proposal::new_config(5_000, threshold, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(
            type_key.to_ascii_string(),
            type_name::with_defining_ids<NewType>(),
            config,
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Enable proposal type")),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };
}

/// Vote yes on the pending proposal (single board member → 100% approval).
fun vote_yes(scenario: &mut test_scenario::Scenario, clock: &clock::Clock) {
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };
}

// === Tests ===

#[test, expected_failure(abort_code = admin_ops::ESubOUBlockedType)]
/// SubOU with a controller cannot enable hierarchy-altering types (SpawnOU).
fun enable_blocked_type_aborts_for_subou_with_controller() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subou(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal<SpawnOU>(&mut scenario, &clock, b"SpawnOU");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    // Execute — must abort with ESubOUBlockedType
    scenario.next_tx(CREATOR);
    {
        let mut subou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut subou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<SpawnOU>(
            &mut subou,
            ticket,
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// SubOU with a controller CAN enable a non-blocked type.
fun enable_non_blocked_type_succeeds_for_subou_with_controller() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subou(&mut scenario);
    clock.set_for_testing(1000);
    // A third-party payload type that is not pre-enabled and not SubOU-blocked.
    submit_enable_type_proposal<TestPayload>(&mut scenario, &clock, b"CustomAction");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut subou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut subou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<TestPayload>(
            &mut subou,
            ticket,
        );

        // Verify the type was added under its display key
        assert!(subou.is_type_enabled<TestPayload>());
        assert!(subou.type_display_key<TestPayload>() == b"CustomAction".to_ascii_string());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(subou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Independent OU (no controller) CAN enable a hierarchy-altering type (SpawnOU).
fun enable_blocked_type_succeeds_for_independent_ou() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    clock.set_for_testing(1000);
    submit_enable_type_proposal<SpawnOU>(&mut scenario, &clock, b"SpawnOU");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<SpawnOU>(&mut ou, ticket);

        // Verify SpawnOU is now enabled
        assert!(ou.is_type_enabled<SpawnOU>());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
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

    create_ou(&mut scenario);

    // Submit DisableProposalType proposal targeting "EnableProposalType"
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = disable_proposal_type::new(b"EnableProposalType".to_ascii_string());
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Try to disable core type")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EUndisableableType
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = admin_ops::EUndisableableType)]
/// Cannot disable UnfreezeProposalType (core undisableable type).
fun disable_core_type_unfreeze_proposal_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = disable_proposal_type::new(b"UnfreezeProposalType".to_ascii_string());
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Try to disable core type")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- DisableProposalType removes a disableable type ---

#[test]
/// E2E: DisableProposalType on a disableable type (AddMember) removes its
/// slot and its display key; other types stay enabled.
fun disable_proposal_type_removes_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.is_type_enabled<AddMember>());
        clock.set_for_testing(1000);
        let payload = disable_proposal_type::new(b"AddMember".to_ascii_string());
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Disable AddMember")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let proposal = scenario.take_shared<Proposal<DisableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_disable_proposal_type(&mut ou, ticket);

        assert!(!ou.is_type_enabled<AddMember>());
        assert!(ou.type_for_display_key(&b"AddMember".to_ascii_string()).is_none());
        assert!(ou.is_type_enabled<SetBoard>());
        assert!(ou.is_type_enabled<DisableProposalType>());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- EnableProposalType 80% approval floor ---

const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;
const MEMBER_D: address = @0xD;
const MEMBER_E: address = @0xE;

#[test, expected_failure(abort_code = 6, location = armature::board_voting)]
/// EnableProposalType submission is rejected when the OU's config has an
/// approval_threshold below the 80% floor (EFloorNotMet). The abort happens at
/// submit_proposal, before the proposal enters the object graph.
fun enable_proposal_type_submission_floor_rejects_below_80_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Lower EnableProposalType threshold to 65% (6500 bps) via test helper.
    // Any proposal submitted while this config is active must be rejected.
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0);
        ou.test_update_config<EnableProposalType>(config);
        test_scenario::return_shared(ou);
    };

    // Submit EnableProposalType proposal — must abort with EFloorNotMet (6500 < 6600).
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(
            b"CustomAction".to_ascii_string(),
            type_name::with_defining_ids<TestPayload>(),
            config,
        );
        board_voting::submit_proposal(
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// EnableProposalType submission succeeds when the OU's config has
/// approval_threshold exactly at the 80% floor (8000 bps).
fun enable_proposal_type_submission_floor_allows_80_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Set EnableProposalType threshold to exactly 80% (8000 bps).
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        ou.test_update_config<EnableProposalType>(config);
        test_scenario::return_shared(ou);
    };

    // Submit should succeed (8000 >= 8000).
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(
            b"CustomAction".to_ascii_string(),
            type_name::with_defining_ids<TestPayload>(),
            config,
        );
        board_voting::submit_proposal(
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// --- UpdateProposalConfig 80% self-referential floor ---

#[test, expected_failure(abort_code = admin_ops::EFloorNotMet)]
/// propose_update_proposal_config rejects a self-targeting submission when the
/// OU's UpdateProposalConfig threshold is below 80%. The abort happens before
/// the proposal enters the object graph.
fun update_proposal_config_self_submission_floor_rejects_below_80_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Lower UpdateProposalConfig threshold to 51% via test helper.
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_100, 0, 604_800_000, 0, 0);
        ou.test_update_config<UpdateProposalConfig>(config);
        test_scenario::return_shared(ou);
    };

    // Submit self-targeting UpdateProposalConfig via the wrapper — must abort with EFloorNotMet.
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
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
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// propose_update_proposal_config accepts a self-targeting submission when the
/// OU's UpdateProposalConfig threshold is exactly at the 80% floor (8000 bps).
fun update_proposal_config_self_submission_floor_allows_80_percent() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    // Default UpdateProposalConfig threshold is 8000 (80%) — no override needed.

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
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
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
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

    // Create OU with 5 board members
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B, MEMBER_C, MEMBER_D, MEMBER_E]);
        ou::create(
            &init,
            string::utf8(b"Test OU"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Override UpdateProposalConfig config with quorum needing 3+ votes
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(
            6_000, // quorum 60% (need 3 of 5)
            5_000, // approval_threshold 50%
            0,
            604_800_000,
            0,
            0,
        );
        ou.test_update_config<UpdateProposalConfig>(config);
        test_scenario::return_shared(ou);
    };

    // Submit UpdateProposalConfig targeting SetBoard (not self)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
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
            &ou,
            option::some(string::utf8(b"Lower SetBoard quorum")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // 3 of 5 vote yes (60% — no 80% floor for non-self targets)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_B);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(3000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(MEMBER_C);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(4000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — should succeed (no 80% floor for SetBoard target)
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(5000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut ou, ticket);

        // Verify SetBoard quorum was updated
        let new_config = ou.type_config<SetBoard>();
        assert!(new_config.quorum() == 3_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EThresholdBelowFloor tests
// =========================================================================

#[test, expected_failure(abort_code = armature::ou::EThresholdBelowMinimum)]
/// UpdateProposalConfig cannot lower EnableProposalType threshold below 80% floor.
fun update_config_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Submit UpdateProposalConfig targeting EnableProposalType with threshold=5000 (below 6600
    // floor)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"EnableProposalType".to_ascii_string(),
            option::none(), // keep quorum
            option::some(5_000), // lower threshold to 50% — below 80% floor
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Lower EnableProposalType threshold")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes (single-member board → 100% approval, passes 80% floor)
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EThresholdBelowFloor
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::ou::EThresholdBelowMinimum)]
/// EnableProposalType cannot enable a floor-gated type with a sub-floor threshold.
/// Uses a SubOU that has had UpdateProposalConfig disabled via test helper,
/// then tries to re-enable it with a threshold below the 80% floor.
fun enable_type_with_sub_floor_config_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_and_share_subou(&mut scenario);

    // Disable UpdateProposalConfig on the SubOU via test helper so we can re-enable it
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        ou.test_disable_type<UpdateProposalConfig>();
        test_scenario::return_shared(ou);
    };

    // Submit EnableProposalType proposal to re-enable UpdateProposalConfig with threshold=5000
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        // 5000 (50%) is below the 80% floor for UpdateProposalConfig
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(
            b"UpdateProposalConfig".to_ascii_string(),
            type_name::with_defining_ids<UpdateProposalConfig>(),
            config,
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Re-enable UpdateProposalConfig with weak threshold")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — should abort with EThresholdBelowFloor
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<UpdateProposalConfig>(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Type-slot tests for execute_enable_proposal_type
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
        let ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = enable_proposal_type::new(
            type_key.to_ascii_string(),
            type_name::with_defining_ids<NewType>(),
            config,
        );
        board_voting::submit_proposal(
            &ou,
            option::none(),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    clock.set_for_testing(ts_vote);
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    clock.set_for_testing(ts_exec);
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<NewType>(&mut ou, ticket);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };
}

#[test]
/// execute_enable_proposal_type<NewType> adds a slot keyed by NewType carrying the
/// display key the board voted on.
fun execute_enable_proposal_type_adds_slot() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.is_type_enabled<TestPayload>());
        assert!(ou.type_display_key<TestPayload>() == b"MyGrant".to_ascii_string());
        assert!(!ou.is_type_enabled<AltPayload>());
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Re-enabling a previously disabled type under the same display key succeeds.
fun execute_enable_proposal_type_reenable_same_type_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);

    // Disable via test helper — slot and display key are released.
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        ou.test_disable_type<TestPayload>();
        assert!(!ou.is_type_enabled<TestPayload>());
        test_scenario::return_shared(ou);
    };

    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 4000, 5000, 6000);

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.is_type_enabled<TestPayload>());
        assert!(ou.type_display_key<TestPayload>() == b"MyGrant".to_ascii_string());
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// After a disable, the display key is free for a different type: nothing about
/// the old slot lingers.
fun execute_enable_proposal_type_display_key_reusable_after_disable() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        ou.test_disable_type<TestPayload>();
        test_scenario::return_shared(ou);
    };

    run_enable_type<AltPayload>(&mut scenario, &mut clock, b"MyGrant", 4000, 5000, 6000);

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.is_type_enabled<AltPayload>());
        assert!(!ou.is_type_enabled<TestPayload>());
        assert!(ou.type_display_key<AltPayload>() == b"MyGrant".to_ascii_string());
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = 15, location = armature::ou)]
/// Enabling a second type under a display key that is still in use aborts with
/// ou::EDisplayKeyTaken.
fun execute_enable_proposal_type_duplicate_display_key_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    run_enable_type<TestPayload>(&mut scenario, &mut clock, b"MyGrant", 1000, 2000, 3000);
    // TestPayload still holds "MyGrant" — AltPayload cannot take it.
    run_enable_type<AltPayload>(&mut scenario, &mut clock, b"MyGrant", 4000, 5000, 6000);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = admin_ops::ETypeMismatch)]
/// The payload pins the Move type the board approved; executing the handler with a
/// different NewType aborts, so an executor cannot register a type the board never saw.
fun execute_enable_proposal_type_wrong_new_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Board approves TestPayload under "MyGrant"...
    clock.set_for_testing(1000);
    submit_enable_type_proposal<TestPayload>(&mut scenario, &clock, b"MyGrant");
    clock.set_for_testing(2000);
    vote_yes(&mut scenario, &clock);

    // ...but the executor tries to register AltPayload.
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_enable_proposal_type<AltPayload>(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

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
/// each state transition on the OU config.
fun update_proposal_config_composable_allowed_updates_config() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // AddMember is composable by default — confirm baseline.
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.type_config<AddMember>().composable_allowed());
        test_scenario::return_shared(ou);
    };

    // Submit UpdateProposalConfig for AddMember with composable_allowed: some(false).
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
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
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut ou, ticket);

        // Composability is now false.
        assert!(!ou.type_config<AddMember>().composable_allowed());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    // Submit a second UpdateProposalConfig to re-enable composability.
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
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
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(5000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(6000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut ou, ticket);

        // Composability is restored.
        assert!(ou.type_config<AddMember>().composable_allowed());

        // Other fields are preserved — quorum unchanged from default.
        let cfg = ou.type_config<AddMember>();
        assert!(cfg.quorum() == 5_000);
        assert!(cfg.approval_threshold() == 5_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// EComposableCooldownConflict: enable_proposal_type rejects cooldown+composable
// =========================================================================

#[test, expected_failure(abort_code = armature::admin_ops::EComposableCooldownConflict)]
/// execute_enable_proposal_type aborts when config has cooldown > 0 AND composable_allowed = true.
fun enable_proposal_type_composable_cooldown_conflict_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Submit EnableProposalType with a conflicting config: cooldown + composable
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let bad_config = proposal::new_config(
            5_000,
            6_600,
            0,
            604_800_000,
            0,
            3_600_000,
        ).with_composable_allowed(true);
        let payload = enable_proposal_type::new(
            b"BadType".to_ascii_string(),
            type_name::with_defining_ids<TestPayload>(),
            bad_config,
        );
        board_voting::submit_proposal(
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — must abort at composable_cooldown check
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<EnableProposalType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        admin_ops::execute_enable_proposal_type<TestPayload>(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::admin_ops::EComposableCooldownConflict)]
/// execute_update_proposal_config aborts when updated config has cooldown > 0 AND
/// composable_allowed = true.
fun update_proposal_config_composable_cooldown_conflict_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);

    // Submit UpdateProposalConfig that sets cooldown > 0 and composable_allowed = true for
    // AddMember
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"AddMember".to_ascii_string(),
            option::none(), // quorum
            option::none(), // approval_threshold
            option::none(), // propose_threshold
            option::none(), // expiry_ms
            option::none(), // execution_delay_ms
            option::some(3_600_000u64), // cooldown_ms > 0
            option::some(true), // composable_allowed = true → CONFLICT
        );
        board_voting::submit_proposal(
            &ou,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // Vote
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // Execute — must abort at composable_cooldown check
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        admin_ops::execute_update_proposal_config(&mut ou, ticket);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// UpdateProposalConfig rebuilds the target's config from the payload; it must
/// keep the target's permission bits, not reset them to none.
fun update_proposal_config_preserves_permissions() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let bits = armature::permissions::board_add() | armature::permissions::pause();

    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        ou.test_enable_type<TestPayload>(
            b"TestPayload".to_ascii_string(),
            proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0).with_permissions(bits),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = update_proposal_config::new(
            b"TestPayload".to_ascii_string(),
            option::none(),
            option::some(6_000),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        );
        board_voting::submit_proposal(&ou, option::none(), payload, &clock, scenario.ctx());
        test_scenario::return_shared(ou);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let proposal = scenario.take_shared<Proposal<UpdateProposalConfig>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        admin_ops::execute_update_proposal_config(&mut ou, ticket);

        let config = ou.type_config<TestPayload>();
        assert!(config.approval_threshold() == 6_000);
        assert!(config.permissions() == bits);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}
