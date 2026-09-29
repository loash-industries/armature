#[test_only]
module armature_proposals::tribe_setup_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::emergency::EmergencyFreeze;
use armature::enable_proposal_type::EnableProposalType;
use armature::ou::{Self, OU};
use armature::proposal;
use armature_proposals::controller_batch_add_members::{Self, ControllerBatchAddMembers};
use armature_proposals::controller_batch_remove_members::ControllerBatchRemoveMembers;
use armature_proposals::pause_execution::{PauseSubOUExecution, UnpauseSubOUExecution};
use armature_proposals::reclaim_cap_from_subou::ReclaimCapFromSubOU;
use armature_proposals::subou_ops;
use armature_proposals::transfer_cap_to_subou::TransferCapToSubOU;
use armature_proposals::tribe_setup;
use armature_proposals::type_permissions;
use std::string;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const OFFICER: address = @0xB;
const MEMBER: address = @0xC;
const NEW_OFFICER: address = @0xD;
const OFFICER_FREEZE_ADMIN: address = @0xE;
const MEMBER_FREEZE_ADMIN: address = @0xF;

// === Helpers ===

fun do_create_tribe(scenario: &mut test_scenario::Scenario): (ID, ID, ID) {
    scenario.next_tx(CREATOR);
    tribe_setup::create_tribe(
        vector[CREATOR],
        vector[OFFICER],
        vector[MEMBER],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"ipfs://tribe"),
        string::utf8(b"ipfs://officers"),
        string::utf8(b"ipfs://members"),
        OFFICER_FREEZE_ADMIN,
        MEMBER_FREEZE_ADMIN,
        scenario.ctx(),
    )
}

/// Assert all six controller types are enabled on `ou` with their bits and scope.
fun assert_controller_types_enabled(ou: &OU) {
    let control = type_permissions::subou_control();
    let scope = type_permissions::subou_control_scope();
    assert_type<ControllerBatchAddMembers>(ou, control, scope);
    assert_type<ControllerBatchRemoveMembers>(ou, control, scope);
    assert_type<PauseSubOUExecution>(ou, control, scope);
    assert_type<UnpauseSubOUExecution>(ou, control, scope);
    assert_type<ReclaimCapFromSubOU>(ou, type_permissions::reclaim_cap_from_subou(), scope);
    assert_type<TransferCapToSubOU>(ou, type_permissions::transfer_cap_to_subou(), vector[]);
}

fun assert_type<T>(ou: &OU, bits: u64, scope: vector<std::type_name::TypeName>) {
    assert!(ou.is_type_enabled<T>());
    let config = ou.type_config<T>();
    assert!(config.permissions() == bits);
    assert!(config.borrow_scope() == scope);
    assert!(config.approval_threshold() == 8_000);
}

/// Member management and pause are single-vote; unpause and cap moves need
/// consensus; type registration keeps the framework's whole-board default.
fun assert_single_vote_policy(ou: &OU) {
    assert!(ou.type_config<ControllerBatchAddMembers>().quorum() == 1);
    assert!(ou.type_config<ControllerBatchRemoveMembers>().quorum() == 1);
    assert!(ou.type_config<PauseSubOUExecution>().quorum() == 1);
    assert!(ou.type_config<UnpauseSubOUExecution>().quorum() == 5_000);
    assert!(ou.type_config<ReclaimCapFromSubOU>().quorum() == 5_000);
    assert!(ou.type_config<TransferCapToSubOU>().quorum() == 5_000);
    let enable = ou.type_config<EnableProposalType>();
    assert!(enable.quorum() == 8_000);
    assert!(enable.approval_threshold() == 10_000);
    assert!(
        enable.permissions() == ou::framework_permissions(&ou::type_name_of<EnableProposalType>()),
    );
}

// === Tests ===

#[test]
/// Both controllers (Tribe, Officers) get the controller types; Members does not.
fun create_tribe_enables_controller_types_on_controllers() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (tribe_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_ou = scenario.take_shared_by_id<OU>(tribe_id);
        let officer_ou = scenario.take_shared_by_id<OU>(officer_id);
        let member_ou = scenario.take_shared_by_id<OU>(member_id);

        assert_controller_types_enabled(&tribe_ou);
        assert_controller_types_enabled(&officer_ou);
        assert_single_vote_policy(&tribe_ou);
        assert_single_vote_policy(&officer_ou);
        assert!(member_ou.type_config<EnableProposalType>().quorum() == 8_000);
        assert!(!member_ou.is_type_enabled<ControllerBatchAddMembers>());
        assert!(!member_ou.is_type_enabled<TransferCapToSubOU>());

        test_scenario::return_shared(member_ou);
        test_scenario::return_shared(officer_ou);
        test_scenario::return_shared(tribe_ou);
    };

    scenario.end();
}

#[test]
/// E2E: straight after creation, the Tribe OU adds an officer to the Officers
/// SubOU through its SubOUControl, with no EnableProposalType vote first.
fun tribe_controls_officers_without_enable_vote() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    let (tribe_id, officer_id, _) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut tribe_ou = scenario.take_shared_by_id<OU>(tribe_id);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(tribe_ou.capability_vault_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(tribe_ou.emergency_freeze_id());
        let mut officer_ou = scenario.take_shared_by_id<OU>(officer_id);
        let control_id = vault.ids_for_type<SubOUControl>()[0];
        clock.set_for_testing(10_000);

        let ticket = board_voting::submit_vote_execute<ControllerBatchAddMembers>(
            &mut tribe_ou,
            option::none(),
            controller_batch_add_members::new(control_id, vector[NEW_OFFICER]),
            &freeze,
            &clock,
            scenario.ctx(),
        );
        subou_ops::execute_controller_batch_add_members(
            &mut vault,
            &mut officer_ou,
            ticket,
            scenario.ctx(),
        );

        assert!(officer_ou.governance().is_board_member(OFFICER));
        assert!(officer_ou.governance().is_board_member(NEW_OFFICER));

        test_scenario::return_shared(officer_ou);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(tribe_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// A caller override of a controller type replaces its config but keeps its
/// permission bits and borrow scope.
fun create_tribe_configured_override_tunes_controller_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    let (tribe_id, _, _) = tribe_setup::create_tribe_configured(
        vector[CREATOR],
        vector[OFFICER],
        vector[MEMBER],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"ipfs://tribe"),
        string::utf8(b"ipfs://officers"),
        string::utf8(b"ipfs://members"),
        OFFICER_FREEZE_ADMIN,
        MEMBER_FREEZE_ADMIN,
        vector[
            ou::new_type_init<ControllerBatchAddMembers>(
                b"ControllerBatchAddMembers".to_ascii_string(),
                proposal::new_config(5_000, 9_000, 0, 604_800_000, 0, 0),
            ),
        ],
        vector[],
        vector[],
        scenario.ctx(),
    );

    scenario.next_tx(CREATOR);
    {
        let tribe_ou = scenario.take_shared_by_id<OU>(tribe_id);
        let config = tribe_ou.type_config<ControllerBatchAddMembers>();
        assert!(config.approval_threshold() == 9_000);
        assert!(config.permissions() == type_permissions::subou_control());
        assert!(config.borrow_scope() == type_permissions::subou_control_scope());
        test_scenario::return_shared(tribe_ou);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// Overriding a controller type below its 80% floor aborts.
fun create_tribe_configured_override_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe_setup::create_tribe_configured(
        vector[CREATOR],
        vector[OFFICER],
        vector[MEMBER],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"ipfs://tribe"),
        string::utf8(b"ipfs://officers"),
        string::utf8(b"ipfs://members"),
        OFFICER_FREEZE_ADMIN,
        MEMBER_FREEZE_ADMIN,
        vector[],
        vector[
            ou::new_type_init<PauseSubOUExecution>(
                b"PauseSubOUExecution".to_ascii_string(),
                proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0),
            ),
        ],
        vector[],
        scenario.ctx(),
    );
    abort 0
}
