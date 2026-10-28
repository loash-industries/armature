#[test_only]
/// ControllerEnableBypassType / ControllerDisableBypassType: a controller OU
/// grants and revokes bypass execution on a controlled SubOU, which cannot
/// pass EnableBypassType itself. Runs against tribes built by
/// `tribe::create_tribe` / `create_tribe_configured`, so the control
/// hierarchy is the real one (Tribe → Officers → Members), not a test seam.
module armature::controller_bypass_tests;

use armature::admin_ops;
use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::controller;
use armature::controller_disable_bypass_type::ControllerDisableBypassType;
use armature::controller_enable_bypass_type::ControllerEnableBypassType;
use armature::create_subou::CreateSubOU;
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::external_execution;
use armature::ou::{Self, OU, ProposalTypeInit};
use armature::permissions;
use armature::proposal::{Self, ExternalExecutionCap, Proposal, ProposalConfig};
use armature::tribe;
use std::internal;
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self, Scenario};

const CREATOR: address = @0xA;
const TRIBE_B: address = @0xB;
const OFFICER_A: address = @0xC1;
const OFFICER_B: address = @0xC2;
const OFFICER_C: address = @0xC3;
const OFFICER_D: address = @0xC4;
const OFFICER_E: address = @0xC5;
const MEMBER_A: address = @0xD1;
const OFFICER_ADMIN: address = @0x10;
const MEMBER_ADMIN: address = @0x11;

const EXPIRY_MS: u64 = 604_800_000;

/// Stand-in for an extension's bypass type (e.g. world_bridge's AutojoinOU).
public struct DummyBypass has drop, store { x: u64 }

/// Second payload type for type-pin mismatches.
public struct OtherBypass has drop, store {}

// === Config helpers ===

/// 80% quorum × 100% threshold: the whole-board config ControllerEnableBypassType needs.
fun whole_board(): ProposalConfig { proposal::new_config(8_000, 10_000, 0, EXPIRY_MS, 0, 0) }

/// 50% quorum, 80% threshold: meets the VAULT_BORROW floor.
fun consensus(): ProposalConfig { proposal::new_config(5_000, 8_000, 0, EXPIRY_MS, 0, 0) }

/// Config for the bypass-enabled type on the SubOU.
fun bypass_config(): ProposalConfig { proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 0) }

fun controller_inits(): vector<ProposalTypeInit> {
    vector[
        ou::new_type_init<ControllerEnableBypassType>(
            b"ControllerEnableBypassType".to_ascii_string(),
            whole_board(),
        ),
        ou::new_type_init<ControllerDisableBypassType>(
            b"ControllerDisableBypassType".to_ascii_string(),
            consensus(),
        ),
    ]
}

// === Setup helpers ===

/// Tribe with the controller bypass types enabled on Tribe and Officers at construction.
fun create_tribe_with_controller_types(
    scenario: &mut Scenario,
    officers: vector<address>,
    member_overrides: vector<ProposalTypeInit>,
): (ID, ID, ID) {
    scenario.next_tx(CREATOR);
    tribe::create_tribe_configured(
        vector[CREATOR, TRIBE_B],
        officers,
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        controller_inits(),
        controller_inits(),
        member_overrides,
        scenario.ctx(),
    )
}

/// The ID of the (single) SubOUControl held in `ou_id`'s vault.
fun control_id_in(scenario: &mut Scenario, ou_id: ID): ID {
    scenario.next_tx(CREATOR);
    let ou = scenario.take_shared_by_id<OU>(ou_id);
    let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let id = vault.ids_for_type<SubOUControl>()[0];
    test_scenario::return_shared(vault);
    test_scenario::return_shared(ou);
    id
}

/// `voters[0]` submits `payload` on `ou_id`; every voter then votes YES.
fun submit_and_vote<P: store>(
    scenario: &mut Scenario,
    clock: &Clock,
    ou_id: ID,
    payload: P,
    voters: vector<address>,
) {
    scenario.next_tx(voters[0]);
    {
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        board_voting::submit_proposal(&ou, option::none(), payload, clock, scenario.ctx());
        test_scenario::return_shared(ou);
    };
    let mut i = 0;
    while (i < voters.length()) {
        scenario.next_tx(voters[i]);
        let mut prop = scenario.take_shared<Proposal<P>>();
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        board_voting::vote(&mut prop, &ou, true, clock, scenario.ctx());
        test_scenario::return_shared(ou);
        test_scenario::return_shared(prop);
        i = i + 1;
    };
}

/// Pass EnableProposalType<T> on `ou_id` and execute it.
fun enable_type_by_vote<T: store>(
    scenario: &mut Scenario,
    clock: &Clock,
    ou_id: ID,
    display_key: vector<u8>,
    config: ProposalConfig,
    voters: vector<address>,
) {
    submit_and_vote(
        scenario,
        clock,
        ou_id,
        enable_proposal_type::new(
            display_key.to_ascii_string(),
            type_name::with_defining_ids<T>(),
            config,
        ),
        voters,
    );
    scenario.next_tx(voters[0]);
    let mut ou = scenario.take_shared_by_id<OU>(ou_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let prop = scenario.take_shared<Proposal<EnableProposalType>>();
    let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, clock, scenario.ctx());
    admin_ops::execute_enable_proposal_type<T>(&mut ou, ticket);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ou);
}

/// Submit and vote a ControllerEnableBypassType<NewType> on `controller_id`
/// targeting `subou_id` with the control held in the controller's vault.
fun propose_controller_enable<NewType>(
    scenario: &mut Scenario,
    clock: &Clock,
    controller_id: ID,
    subou_id: ID,
    config: ProposalConfig,
    voters: vector<address>,
) {
    let control_id = control_id_in(scenario, controller_id);
    submit_and_vote(
        scenario,
        clock,
        controller_id,
        external_execution::new_controller_enable_bypass_type(
            subou_id,
            control_id,
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<NewType>(),
            config,
        ),
        voters,
    );
}

/// As `executor` (a controller board member), execute the pending
/// ControllerEnableBypassType on `controller_id`, passing `subou_id` as the
/// SubOU and `subou_vault_owner`'s vault as the SubOU vault. Returns the IDs
/// of `ExternalExecutionCap<NewType>` in that vault afterwards.
fun execute_controller_enable<NewType: store>(
    scenario: &mut Scenario,
    clock: &Clock,
    executor: address,
    controller_id: ID,
    subou_id: ID,
    subou_vault_owner: ID,
): vector<ID> {
    scenario.next_tx(executor);
    let mut ctrl = scenario.take_shared_by_id<OU>(controller_id);
    let mut ctrl_vault = scenario.take_shared_by_id<CapabilityVault>(ctrl.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ctrl.emergency_freeze_id());
    let mut subou = scenario.take_shared_by_id<OU>(subou_id);
    let vault_owner_vault_id = if (subou_vault_owner == subou_id) {
        subou.capability_vault_id()
    } else {
        let owner = scenario.take_shared_by_id<OU>(subou_vault_owner);
        let id = owner.capability_vault_id();
        test_scenario::return_shared(owner);
        id
    };
    let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(vault_owner_vault_id);
    let prop = scenario.take_shared<Proposal<ControllerEnableBypassType>>();

    let ticket = board_voting::ticket_from_vote(&mut ctrl, prop, &freeze, clock, scenario.ctx());
    external_execution::execute_controller_enable_bypass_type<NewType>(
        &mut ctrl_vault,
        &mut subou,
        &mut subou_vault,
        ticket,
        scenario.ctx(),
    );
    let ids = subou_vault.ids_for_type<ExternalExecutionCap<NewType>>();

    test_scenario::return_shared(subou_vault);
    test_scenario::return_shared(subou);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ctrl_vault);
    test_scenario::return_shared(ctrl);
    ids
}

/// Full grant: propose, vote and execute ControllerEnableBypassType<DummyBypass>
/// from Officers onto Members. Returns the cap ID.
fun grant_dummy(
    scenario: &mut Scenario,
    clock: &Clock,
    officer_id: ID,
    member_id: ID,
    voters: vector<address>,
): ID {
    propose_controller_enable<DummyBypass>(
        scenario,
        clock,
        officer_id,
        member_id,
        bypass_config(),
        voters,
    );
    let ids = execute_controller_enable<DummyBypass>(
        scenario,
        clock,
        voters[0],
        officer_id,
        member_id,
        member_id,
    );
    assert!(ids.length() == 1);
    ids[0]
}

/// Submit, vote and execute ControllerDisableBypassType<NewType> from
/// `controller_id` on `subou_id`, naming `type_key` and `cap_id`.
fun revoke<NewType: store>(
    scenario: &mut Scenario,
    clock: &Clock,
    controller_id: ID,
    subou_id: ID,
    type_key: vector<u8>,
    cap_id: ID,
    voters: vector<address>,
) {
    let control_id = control_id_in(scenario, controller_id);
    submit_and_vote(
        scenario,
        clock,
        controller_id,
        external_execution::new_controller_disable_bypass_type(
            subou_id,
            control_id,
            type_key.to_ascii_string(),
            cap_id,
        ),
        voters,
    );
    scenario.next_tx(voters[0]);
    let mut ctrl = scenario.take_shared_by_id<OU>(controller_id);
    let mut ctrl_vault = scenario.take_shared_by_id<CapabilityVault>(ctrl.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ctrl.emergency_freeze_id());
    let mut subou = scenario.take_shared_by_id<OU>(subou_id);
    let mut subou_vault = scenario.take_shared_by_id<CapabilityVault>(subou.capability_vault_id());
    let prop = scenario.take_shared<Proposal<ControllerDisableBypassType>>();
    let ticket = board_voting::ticket_from_vote(&mut ctrl, prop, &freeze, clock, scenario.ctx());
    external_execution::execute_controller_disable_bypass_type<NewType>(
        &mut ctrl_vault,
        &mut subou,
        &mut subou_vault,
        ticket,
        scenario.ctx(),
    );
    test_scenario::return_shared(subou_vault);
    test_scenario::return_shared(subou);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ctrl_vault);
    test_scenario::return_shared(ctrl);
}

/// Mint and discharge a DummyBypass ticket on `ou_id` with cap `cap_id` from its vault.
fun use_dummy_cap(scenario: &mut Scenario, clock: &Clock, ou_id: ID, cap_id: ID) {
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared_by_id<OU>(ou_id);
    let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    let cap = vault.borrow_external_cap<DummyBypass>(ou_id, cap_id);
    let ticket = external_execution::ticket_from_cap<DummyBypass>(
        cap,
        &mut ou,
        &freeze,
        option::none(),
        DummyBypass { x: 1 },
        internal::permit(),
        clock,
        scenario.ctx(),
    );
    assert!(ticket.ticket_ou_id() == ou_id);
    ticket.discharge(internal::permit());
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(ou);
}

// === Framework type registration ===

#[test]
/// Both controller types are framework types with VAULT_BORROW fixed and the
/// SubOUControl as their borrow scope; enable holds the 80% bypass floor.
fun controller_types_have_fixed_bits_and_scope() {
    let enable = type_name::with_defining_ids<ControllerEnableBypassType>();
    let disable = type_name::with_defining_ids<ControllerDisableBypassType>();
    let scope = vector[type_name::with_defining_ids<SubOUControl>()];

    assert!(ou::is_framework_type(&enable));
    assert!(ou::is_framework_type(&disable));
    assert!(ou::framework_permissions(&enable) == permissions::vault_borrow());
    assert!(ou::framework_permissions(&disable) == permissions::vault_borrow());
    assert!(ou::framework_borrow_scope(&enable) == scope);
    assert!(ou::framework_borrow_scope(&disable) == scope);
    assert!(ou::min_approval_threshold_for_type(&enable) == 8_000);
    assert!(ou::min_approval_threshold_for_type(&disable) == 0);

    // A controlled SubOU (Officers) must be able to hold them.
    assert!(!ou::is_subou_blocked_type(&enable));
    assert!(!ou::is_subou_blocked_type(&disable));
    assert!(!ou::is_undisableable_type(&enable));
    assert!(!ou::is_undisableable_type(&disable));
}

#[test]
/// Enabled at construction, the slots carry the fixed bits and scope even
/// though the overrides named none.
fun construction_override_applies_fixed_bits() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, officer_id, _) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    scenario.next_tx(CREATOR);
    let officers = scenario.take_shared_by_id<OU>(officer_id);
    let config = officers.type_config<ControllerEnableBypassType>();
    assert!(config.permissions() == permissions::vault_borrow());
    assert!(config.borrow_scope() == vector[type_name::with_defining_ids<SubOUControl>()]);
    test_scenario::return_shared(officers);
    scenario.end();
}

#[test, expected_failure(abort_code = armature::ou::EBypassQuorumTooLow)]
/// ControllerEnableBypassType is held to the whole-board rule: quorum ×
/// threshold below 80% is refused when the config is stored.
fun controller_enable_config_below_whole_board_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe_configured(
        vector[CREATOR],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[],
        vector[
            ou::new_type_init<ControllerEnableBypassType>(
                b"ControllerEnableBypassType".to_ascii_string(),
                consensus(),
            ),
        ],
        vector[],
        scenario.ctx(),
    );
    scenario.end();
}

#[test, expected_failure(abort_code = armature::ou::EThresholdBelowMinimum)]
/// ControllerEnableBypassType's threshold floor is 80%.
fun controller_enable_config_below_threshold_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe_configured(
        vector[CREATOR],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[],
        vector[
            ou::new_type_init<ControllerEnableBypassType>(
                b"ControllerEnableBypassType".to_ascii_string(),
                proposal::new_config(10_000, 7_000, 0, EXPIRY_MS, 0, 0),
            ),
        ],
        vector[],
        scenario.ctx(),
    );
    scenario.end();
}

#[test, expected_failure(abort_code = armature::ou::EFixedPermissions)]
/// The fixed bits cannot be widened by the enabling config.
fun controller_enable_config_extra_bits_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe_configured(
        vector[CREATOR],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[],
        vector[
            ou::new_type_init<ControllerEnableBypassType>(
                b"ControllerEnableBypassType".to_ascii_string(),
                whole_board().with_permissions(
                    permissions::vault_borrow() | permissions::type_admin(),
                ),
            ),
        ],
        vector[],
        scenario.ctx(),
    );
    scenario.end();
}

// === Happy paths ===

#[test]
/// The reported blocker, end to end on a plain `tribe::create_tribe`: Officers
/// enables the controller types by vote, grants DummyBypass to Members, and
/// the cap mints tickets on Members. Previously no path could give Members a cap.
fun plain_create_tribe_officers_grant_bypass_to_members() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    scenario.next_tx(CREATOR);
    let (_, officer_id, member_id) = tribe::create_tribe(
        vector[CREATOR, TRIBE_B],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        scenario.ctx(),
    );
    let officers = vector[OFFICER_A, OFFICER_B];

    // Members starts without EnableBypassType: it cannot opt in itself.
    scenario.next_tx(CREATOR);
    {
        let members = scenario.take_shared_by_id<OU>(member_id);
        assert!(!members.is_type_enabled<EnableBypassType>());
        test_scenario::return_shared(members);
    };

    enable_type_by_vote<ControllerEnableBypassType>(
        &mut scenario,
        &clock,
        officer_id,
        b"ControllerEnableBypassType",
        whole_board(),
        officers,
    );
    enable_type_by_vote<ControllerDisableBypassType>(
        &mut scenario,
        &clock,
        officer_id,
        b"ControllerDisableBypassType",
        consensus(),
        officers,
    );

    let cap_id = grant_dummy(&mut scenario, &clock, officer_id, member_id, officers);

    scenario.next_tx(CREATOR);
    {
        let members = scenario.take_shared_by_id<OU>(member_id);
        assert!(members.is_type_enabled<DummyBypass>());
        assert!(members.type_display_key<DummyBypass>() == b"DummyBypass".to_ascii_string());
        test_scenario::return_shared(members);
    };

    use_dummy_cap(&mut scenario, &clock, member_id, cap_id);

    // The SubOUControl went back into the Officers vault.
    let _ = control_id_in(&mut scenario, officer_id);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// A 5-officer board passing at exactly 80% (4 of 5) clears the execution floor.
fun grant_at_exactly_80_percent_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A, OFFICER_B, OFFICER_C, OFFICER_D, OFFICER_E],
        vector[],
    );
    let cap_id = grant_dummy(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        vector[OFFICER_A, OFFICER_B, OFFICER_C, OFFICER_D],
    );
    use_dummy_cap(&mut scenario, &clock, member_id, cap_id);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// ControllerDisableBypassType destroys the cap and removes the slot; the
/// type can then be granted again.
fun revoke_destroys_cap_and_slot() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    let cap_id = grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);
    revoke<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        b"DummyBypass",
        cap_id,
        vector[OFFICER_A],
    );

    scenario.next_tx(CREATOR);
    {
        let members = scenario.take_shared_by_id<OU>(member_id);
        let vault = scenario.take_shared_by_id<CapabilityVault>(members.capability_vault_id());
        assert!(!members.is_type_enabled<DummyBypass>());
        assert!(vault.ids_for_type<ExternalExecutionCap<DummyBypass>>().is_empty());
        assert!(!vault.contains(cap_id));
        test_scenario::return_shared(vault);
        test_scenario::return_shared(members);
    };

    // Re-grant works after a revoke.
    let cap2 = grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);
    assert!(cap2 != cap_id);
    use_dummy_cap(&mut scenario, &clock, member_id, cap2);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Tribe can grant bypass on Officers (itself a SubOU) the same way.
fun tribe_grants_bypass_to_officers() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (tribe_id, officer_id, _) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    let cap_id = grant_dummy(&mut scenario, &clock, tribe_id, officer_id, vector[CREATOR, TRIBE_B]);
    use_dummy_cap(&mut scenario, &clock, officer_id, cap_id);
    clock.destroy_for_testing();
    scenario.end();
}

// === Abort paths: enable ===

#[test, expected_failure(abort_code = armature::external_execution::EApprovalFloorNotMet)]
/// Below 80% of the controller's whole board aborts at execute, even if the
/// on-OU config was relaxed so the vote passes.
fun grant_below_floor_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A, OFFICER_B, OFFICER_C, OFFICER_D, OFFICER_E],
        vector[],
    );
    scenario.next_tx(CREATOR);
    {
        let mut officers = scenario.take_shared_by_id<OU>(officer_id);
        officers.test_update_config<ControllerEnableBypassType>(
            proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 0),
        );
        test_scenario::return_shared(officers);
    };
    grant_dummy(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        vector[OFFICER_A, OFFICER_B, OFFICER_C],
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESubOUMismatch)]
/// The SubOU passed to the handler must be the one in the payload.
fun grant_wrong_subou_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (tribe_id, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        bypass_config(),
        vector[OFFICER_A],
    );
    execute_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        tribe_id,
        tribe_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESubOUMismatch)]
/// The SubOU vault passed to the handler must belong to the SubOU.
fun grant_wrong_subou_vault_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (tribe_id, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        bypass_config(),
        vector[OFFICER_A],
    );
    execute_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        tribe_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeMismatch)]
/// The executor's NewType must be the type the board approved.
fun grant_type_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        bypass_config(),
        vector[OFFICER_A],
    );
    execute_controller_enable<OtherBypass>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EBypassForbiddenBits)]
/// The bypass-enabled type may not hold TYPE_ADMIN (or MIGRATE, VAULT_EXTRACT, FREEZE).
fun grant_forbidden_bits_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        proposal::new_config(5_000, 8_000, 0, EXPIRY_MS, 0, 0).with_permissions(
            permissions::type_admin(),
        ),
        vector[OFFICER_A],
    );
    execute_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EComposableCooldownConflict)]
/// A bypass type with a cooldown must not be composable.
fun grant_composable_with_cooldown_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 1_000).with_composable_allowed(true),
        vector[OFFICER_A],
    );
    execute_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESelfBootstrapDenied)]
/// The bypass meta-types cannot themselves be bypass-enabled on a SubOU.
fun grant_enable_bypass_type_itself_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<EnableBypassType>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        bypass_config(),
        vector[OFFICER_A],
    );
    execute_controller_enable<EnableBypassType>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESelfBootstrapDenied)]
/// ControllerEnableBypassType cannot be bypass-enabled either.
fun grant_controller_enable_itself_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<ControllerEnableBypassType>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        bypass_config(),
        vector[OFFICER_A],
    );
    execute_controller_enable<ControllerEnableBypassType>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESubOUBlockedType)]
/// SubOU-blocked hierarchy types stay blocked on this path.
fun grant_subou_blocked_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<CreateSubOU>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        bypass_config(),
        vector[OFFICER_A],
    );
    execute_controller_enable<CreateSubOU>(
        &mut scenario,
        &clock,
        OFFICER_A,
        officer_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::controller::EControlMismatch)]
/// A controller cannot reach a grandchild: Tribe's control is bound to
/// Officers, so naming Members with it aborts.
fun grant_with_control_for_other_subou_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (tribe_id, _, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    propose_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        tribe_id,
        member_id,
        bypass_config(),
        vector[CREATOR, TRIBE_B],
    );
    execute_controller_enable<DummyBypass>(
        &mut scenario,
        &clock,
        CREATOR,
        tribe_id,
        member_id,
        member_id,
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EVaultOUMismatch)]
/// No self-escalation: Members holding the type cannot use its controller's
/// vault (and so its control) to grant itself a bypass.
fun subou_cannot_grant_itself() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[
            ou::new_type_init<ControllerEnableBypassType>(
                b"ControllerEnableBypassType".to_ascii_string(),
                whole_board(),
            ),
        ],
    );
    let control_id = control_id_in(&mut scenario, officer_id);
    submit_and_vote(
        &mut scenario,
        &clock,
        member_id,
        external_execution::new_controller_enable_bypass_type(
            member_id,
            control_id,
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            bypass_config(),
        ),
        vector[MEMBER_A],
    );

    scenario.next_tx(MEMBER_A);
    let mut members = scenario.take_shared_by_id<OU>(member_id);
    let officers = scenario.take_shared_by_id<OU>(officer_id);
    let mut officer_vault = scenario.take_shared_by_id<
        CapabilityVault,
    >(officers.capability_vault_id());
    let mut member_vault = scenario.take_shared_by_id<
        CapabilityVault,
    >(members.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(members.emergency_freeze_id());
    let prop = scenario.take_shared<Proposal<ControllerEnableBypassType>>();
    let ticket = board_voting::ticket_from_vote(
        &mut members,
        prop,
        &freeze,
        &clock,
        scenario.ctx(),
    );
    external_execution::execute_controller_enable_bypass_type<DummyBypass>(
        &mut officer_vault,
        &mut members,
        &mut member_vault,
        ticket,
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::ou::ETypeAlreadyEnabled)]
/// Granting a type the SubOU already has a slot for aborts (as EnableBypassType does).
fun grant_twice_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);
    grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EControllerPaused)]
/// The controller's pause stops a controller-granted bypass.
fun controller_pause_blocks_granted_bypass() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    let cap_id = grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);

    // Stand-in for PauseSubOUExecution (armature_proposals): borrow the control
    // and pause Members on a privileged request.
    let control_id = control_id_in(&mut scenario, officer_id);
    scenario.next_tx(CREATOR);
    {
        let officers = scenario.take_shared_by_id<OU>(officer_id);
        let vault = scenario.take_shared_by_id<CapabilityVault>(officers.capability_vault_id());
        let mut members = scenario.take_shared_by_id<OU>(member_id);
        let breq = proposal::new_execution_request_for_testing<DummyBypass>(
            officer_id,
            officer_id,
        ).with_borrow_scope_for_testing(vector[type_name::with_defining_ids<SubOUControl>()]);
        let control: &SubOUControl = vault.borrow_cap(control_id, &breq);
        let req = controller::privileged_submit(
            control,
            &members,
            b"Pause".to_ascii_string(),
            option::none(),
            DummyBypass { x: 0 },
            scenario.ctx(),
        );
        members.set_controller_paused(true, &req);
        controller::privileged_consume(req, control);
        std::unit_test::destroy(breq);
        test_scenario::return_shared(members);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(officers);
    };

    use_dummy_cap(&mut scenario, &clock, member_id, cap_id);
    abort 0
}

// === Abort paths: disable ===

#[test, expected_failure(abort_code = armature::external_execution::ETypeMismatch)]
/// The display key in the revoke payload must match the slot.
fun revoke_wrong_display_key_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    let cap_id = grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);
    revoke<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        b"NotDummy",
        cap_id,
        vector[OFFICER_A],
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ECapNotFound)]
/// The cap named in the revoke payload must be the SubOU's cap for NewType.
fun revoke_unknown_cap_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    grant_dummy(&mut scenario, &clock, officer_id, member_id, vector[OFFICER_A]);
    revoke<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        b"DummyBypass",
        object::id_from_address(@0xBAD),
        vector[OFFICER_A],
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeNotEnabled)]
/// Revoking a type the SubOU never had aborts.
fun revoke_type_not_enabled_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    let (_, officer_id, member_id) = create_tribe_with_controller_types(
        &mut scenario,
        vector[OFFICER_A],
        vector[],
    );
    revoke<DummyBypass>(
        &mut scenario,
        &clock,
        officer_id,
        member_id,
        b"DummyBypass",
        object::id_from_address(@0xBAD),
        vector[OFFICER_A],
    );
    abort 0
}
