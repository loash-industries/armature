/// ControllerEnableBypassType / ControllerDisableBypassType through a
/// controller chain: an OU grants and revokes bypass execution on a SubOU any
/// number of levels below it (`external_execution::start_controller_chain` /
/// `extend_controller_chain` / `finish_controller_*`).
#[test_only]
module armature::controller_chain_tests;

use armature::admin_ops;
use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::controller_disable_bypass_type::ControllerDisableBypassType;
use armature::controller_enable_bypass_type::ControllerEnableBypassType;
use armature::disable_proposal_type;
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type;
use armature::external_execution::{Self, ControllerChain};
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, ExecutionTicket, ExternalExecutionCap, ProposalConfig};
use armature::tribe;
use std::internal;
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};

const ADMIN: address = @0xA1;
const OFFICER_A: address = @0xC1;
const MEMBER_A: address = @0xD1;
const DEPTH: u64 = 7;
const EXPIRY_MS: u64 = 604_800_000;

/// Stand-in for an extension's bypass type (e.g. world_bridge's AutojoinOU).
public struct DummyBypass has drop, store {}

// === Helpers ===

fun whole_board(): ProposalConfig { proposal::new_config(8_000, 10_000, 0, EXPIRY_MS, 0, 0) }

fun consensus(): ProposalConfig { proposal::new_config(5_000, 8_000, 0, EXPIRY_MS, 0, 0) }

fun bypass_config(): ProposalConfig { proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 0) }

fun new_clock(scenario: &mut Scenario): Clock {
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    clock
}

/// A root OU and `depth` SubOUs below it, each controlled by the one above:
/// ids[0] is the root, ids[depth] the deepest SubOU. Every board is [ADMIN].
fun build_chain(scenario: &mut Scenario, depth: u64): vector<ID> {
    scenario.next_tx(ADMIN);
    let root_id = ou::create(
        &governance::init_board(vector[ADMIN]),
        string::utf8(b"Root"),
        string::utf8(b""),
        scenario.ctx(),
    );
    let mut ids = vector[root_id];
    let mut i = 0;
    while (i < depth) {
        scenario.next_tx(ADMIN);
        let parent = scenario.take_shared_by_id<OU>(ids[i]);
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent.capability_vault_id());
        // Stands in for the parent's CreateSubOU vote (VAULT_STORE | VAULT_EXTRACT).
        let req = proposal::new_privileged_request_for_testing<DummyBypass>(
            parent.id(),
            parent.id(),
        );
        let child = tribe::create_wired_subou(
            vector[ADMIN],
            string::utf8(b"Level"),
            string::utf8(b""),
            ADMIN,
            &mut parent_vault,
            &req,
            vector[],
            scenario.ctx(),
        );
        proposal::consume_execution_request_for_testing(req);
        ts::return_shared(parent_vault);
        ts::return_shared(parent);
        ids.push_back(child);
        i = i + 1;
    };
    ids
}

/// The root enables both controller types by its own single-member vote.
fun enable_on_root(scenario: &mut Scenario, clock: &Clock, root_id: ID) {
    scenario.next_tx(ADMIN);
    let mut root = scenario.take_shared_by_id<OU>(root_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(root.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        &mut root,
        option::none(),
        enable_proposal_type::new(
            b"ControllerEnableBypassType".to_ascii_string(),
            type_name::with_defining_ids<ControllerEnableBypassType>(),
            whole_board(),
        ),
        &freeze,
        clock,
        scenario.ctx(),
    );
    admin_ops::execute_enable_proposal_type<ControllerEnableBypassType>(&mut root, ticket);
    let ticket = board_voting::submit_vote_execute(
        &mut root,
        option::none(),
        enable_proposal_type::new(
            b"ControllerDisableBypassType".to_ascii_string(),
            type_name::with_defining_ids<ControllerDisableBypassType>(),
            consensus(),
        ),
        &freeze,
        clock,
        scenario.ctx(),
    );
    admin_ops::execute_enable_proposal_type<ControllerDisableBypassType>(&mut root, ticket);
    ts::return_shared(freeze);
    ts::return_shared(root);
}

fun take_all(scenario: &mut Scenario, ids: &vector<ID>): (vector<OU>, vector<CapabilityVault>) {
    let mut ous = vector[];
    let mut vaults = vector[];
    let mut i = 0;
    while (i < ids.length()) {
        let o = scenario.take_shared_by_id<OU>(ids[i]);
        vaults.push_back(scenario.take_shared_by_id<CapabilityVault>(o.capability_vault_id()));
        ous.push_back(o);
        i = i + 1;
    };
    (ous, vaults)
}

fun return_all(mut ous: vector<OU>, mut vaults: vector<CapabilityVault>) {
    while (!ous.is_empty()) ts::return_shared(ous.pop_back());
    while (!vaults.is_empty()) ts::return_shared(vaults.pop_back());
    ous.destroy_empty();
    vaults.destroy_empty();
}

fun control_of(subou: &OU): ID { *subou.controller_cap_id().borrow() }

/// The root's single-member vote to grant DummyBypass to `subou_id`.
fun grant_ticket(
    scenario: &mut Scenario,
    clock: &Clock,
    root: &mut OU,
    subou_id: ID,
    control_id: ID,
): ExecutionTicket<ControllerEnableBypassType> {
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(root.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        root,
        option::none(),
        external_execution::new_controller_enable_bypass_type(
            subou_id,
            control_id,
            b"DummyBypass".to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            bypass_config(),
        ),
        &freeze,
        clock,
        scenario.ctx(),
    );
    ts::return_shared(freeze);
    ticket
}

/// The root's single-member vote to revoke DummyBypass from `subou_id`.
fun revoke_ticket(
    scenario: &mut Scenario,
    clock: &Clock,
    root: &mut OU,
    subou_id: ID,
    control_id: ID,
): ExecutionTicket<ControllerDisableBypassType> {
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(root.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        root,
        option::none(),
        external_execution::new_controller_disable_bypass_type(
            subou_id,
            control_id,
            type_name::with_defining_ids<DummyBypass>(),
        ),
        &freeze,
        clock,
        scenario.ctx(),
    );
    ts::return_shared(freeze);
    ticket
}

/// Extend `chain` from the root down to ids[depth].
fun walk<P>(
    chain: &mut ControllerChain<P>,
    ous: &vector<OU>,
    vaults: &vector<CapabilityVault>,
    depth: u64,
) {
    let mut i = 0;
    while (i < depth) {
        external_execution::extend_controller_chain(chain, &vaults[i], &ous[i + 1]);
        i = i + 1;
    };
}

/// One PTB: the root grants DummyBypass to ids[depth] through the chain.
fun grant(
    scenario: &mut Scenario,
    clock: &Clock,
    ous: &mut vector<OU>,
    vaults: &mut vector<CapabilityVault>,
    depth: u64,
) {
    let subou_id = ous[depth].id();
    let control_id = control_of(&ous[depth]);
    let ticket = grant_ticket(scenario, clock, &mut ous[0], subou_id, control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, ous, vaults, depth);
    external_execution::finish_controller_enable_bypass_type<DummyBypass>(
        chain,
        &mut ous[depth],
        &mut vaults[depth],
        scenario.ctx(),
    );
}

/// One PTB: the root revokes DummyBypass from ids[depth] through the chain.
fun revoke(
    scenario: &mut Scenario,
    clock: &Clock,
    ous: &mut vector<OU>,
    vaults: &mut vector<CapabilityVault>,
    depth: u64,
) {
    let subou_id = ous[depth].id();
    let control_id = control_of(&ous[depth]);
    let ticket = revoke_ticket(scenario, clock, &mut ous[0], subou_id, control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, ous, vaults, depth);
    external_execution::finish_controller_disable_bypass_type<DummyBypass>(
        chain,
        &mut ous[depth],
        &mut vaults[depth],
        scenario.ctx(),
    );
}

/// The SubOU's own board removes DummyBypass's slot (DisableProposalType).
fun subou_disables_slot(scenario: &mut Scenario, clock: &Clock, subou: &mut OU, key: vector<u8>) {
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(subou.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        subou,
        option::none(),
        disable_proposal_type::new(key.to_ascii_string()),
        &freeze,
        clock,
        scenario.ctx(),
    );
    admin_ops::execute_disable_proposal_type(subou, ticket);
    ts::return_shared(freeze);
}

/// The SubOU's own board re-creates DummyBypass's slot (EnableProposalType).
fun subou_enables_slot(scenario: &mut Scenario, clock: &Clock, subou: &mut OU, key: vector<u8>) {
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(subou.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        subou,
        option::none(),
        enable_proposal_type::new(
            key.to_ascii_string(),
            type_name::with_defining_ids<DummyBypass>(),
            bypass_config(),
        ),
        &freeze,
        clock,
        scenario.ctx(),
    );
    admin_ops::execute_enable_proposal_type<DummyBypass>(subou, ticket);
    ts::return_shared(freeze);
}

fun dummy_caps(vault: &CapabilityVault): vector<ID> {
    vault.ids_for_type<ExternalExecutionCap<DummyBypass>>()
}

/// Each `tx_*` helper is one PTB: it takes the hierarchy, acts, and returns it.
fun tx_grant(scenario: &mut Scenario, clock: &Clock, ids: &vector<ID>, depth: u64) {
    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(scenario, ids);
    grant(scenario, clock, &mut ous, &mut vaults, depth);
    return_all(ous, vaults);
}

fun tx_revoke(scenario: &mut Scenario, clock: &Clock, ids: &vector<ID>, depth: u64) {
    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(scenario, ids);
    revoke(scenario, clock, &mut ous, &mut vaults, depth);
    return_all(ous, vaults);
}

fun tx_subou_disables_slot(scenario: &mut Scenario, clock: &Clock, id: ID, key: vector<u8>) {
    scenario.next_tx(ADMIN);
    let mut subou = scenario.take_shared_by_id<OU>(id);
    subou_disables_slot(scenario, clock, &mut subou, key);
    ts::return_shared(subou);
}

fun tx_subou_enables_slot(scenario: &mut Scenario, clock: &Clock, id: ID, key: vector<u8>) {
    scenario.next_tx(ADMIN);
    let mut subou = scenario.take_shared_by_id<OU>(id);
    subou_enables_slot(scenario, clock, &mut subou, key);
    ts::return_shared(subou);
}

/// Assert whether OU `id` has a DummyBypass slot and how many DummyBypass caps its vault holds.
fun assert_state(scenario: &mut Scenario, id: ID, slot: bool, caps: u64) {
    scenario.next_tx(ADMIN);
    let o = scenario.take_shared_by_id<OU>(id);
    let vault = scenario.take_shared_by_id<CapabilityVault>(o.capability_vault_id());
    assert!(o.is_type_enabled<DummyBypass>() == slot);
    assert!(dummy_caps(&vault).length() == caps);
    ts::return_shared(vault);
    ts::return_shared(o);
}

// === Registration ===

#[test]
/// Both controller types are framework types with VAULT_BORROW fixed and the
/// SubOUControl as their scope; enable holds the 80% bypass floor.
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
    assert!(!ou::is_subou_blocked_type(&enable));
    assert!(!ou::is_subou_blocked_type(&disable));
}

#[test, expected_failure(abort_code = armature::ou::EBypassQuorumTooLow)]
/// ControllerEnableBypassType is held to the whole-board rule when stored.
fun controller_enable_config_below_whole_board_aborts() {
    let mut scenario = ts::begin(ADMIN);
    tribe::create_tribe_configured(
        vector[ADMIN],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        ADMIN,
        ADMIN,
        vector[
            ou::new_type_init<ControllerEnableBypassType>(
                b"ControllerEnableBypassType".to_ascii_string(),
                consensus(),
            ),
        ],
        vector[],
        vector[],
        scenario.ctx(),
    );
    scenario.end();
}

#[test, expected_failure(abort_code = armature::ou::EFixedPermissions)]
/// The fixed bits cannot be widened by the enabling config.
fun controller_enable_config_extra_bits_aborts() {
    let mut scenario = ts::begin(ADMIN);
    tribe::create_tribe_configured(
        vector[ADMIN],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b""),
        string::utf8(b""),
        string::utf8(b""),
        ADMIN,
        ADMIN,
        vector[
            ou::new_type_init<ControllerEnableBypassType>(
                b"ControllerEnableBypassType".to_ascii_string(),
                whole_board().with_permissions(
                    permissions::vault_borrow() | permissions::type_admin(),
                ),
            ),
        ],
        vector[],
        vector[],
        scenario.ctx(),
    );
    scenario.end();
}

// === Grant ===

#[test]
/// The root grants a bypass seven levels down with one approval and one PTB.
/// Only the target gets the slot and the cap, and the cap mints a no-vote
/// ticket on the target.
fun chain_grants_bypass_seven_levels_down() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, DEPTH);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    grant(&mut scenario, &clock, &mut ous, &mut vaults, DEPTH);

    let mut j = 0;
    while (j < DEPTH) {
        assert!(!ous[j].is_type_enabled<DummyBypass>());
        assert!(dummy_caps(&vaults[j]).is_empty());
        j = j + 1;
    };
    assert!(ous[DEPTH].is_type_enabled<DummyBypass>());
    let cap_ids = dummy_caps(&vaults[DEPTH]);
    assert!(cap_ids.length() == 1);

    let target_id = ids[DEPTH];
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ous[DEPTH].emergency_freeze_id());
    let cap = vaults[DEPTH].borrow_external_cap<DummyBypass>(target_id, cap_ids[0]);
    assert!(cap.cap_ou_id() == target_id);
    let used = external_execution::ticket_from_cap(
        cap,
        &mut ous[DEPTH],
        &freeze,
        option::none(),
        DummyBypass {},
        internal::permit(),
        &clock,
        scenario.ctx(),
    );
    used.discharge(internal::permit());
    ts::return_shared(freeze);

    return_all(ous, vaults);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// A direct controller grants through a one-level chain.
fun chain_grants_bypass_one_level_down() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 1);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    grant(&mut scenario, &clock, &mut ous, &mut vaults, 1);
    assert!(ous[1].is_type_enabled<DummyBypass>());
    assert!(dummy_caps(&vaults[1]).length() == 1);

    return_all(ous, vaults);
    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::EChainBroken)]
/// A level cannot be skipped: the root's vault does not hold level 2's control.
fun chain_cannot_skip_a_level() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, DEPTH);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, vaults) = take_all(&mut scenario, &ids);
    let control_id = control_of(&ous[DEPTH]);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], ids[DEPTH], control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    external_execution::extend_controller_chain(&mut chain, &vaults[0], &ous[2]);
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EChainBroken)]
/// A chain cannot reach into another hierarchy.
fun chain_cannot_cross_into_another_hierarchy() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 1);
    let other = build_chain(&mut scenario, 1);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, vaults) = take_all(&mut scenario, &ids);
    let (other_ous, _other_vaults) = take_all(&mut scenario, &other);
    let control_id = control_of(&other_ous[1]);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], other[1], control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    external_execution::extend_controller_chain(&mut chain, &vaults[0], &other_ous[1]);
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EChainBroken)]
/// A chain that stops above the target cannot finish on the target.
fun chain_must_reach_the_target() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, DEPTH);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    let control_id = control_of(&ous[DEPTH]);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], ids[DEPTH], control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, &ous, &vaults, DEPTH - 1);
    external_execution::finish_controller_enable_bypass_type<DummyBypass>(
        chain,
        &mut ous[DEPTH],
        &mut vaults[DEPTH],
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EChainBroken)]
/// A chain with no levels cannot finish: an OU is not its own SubOU.
fun chain_needs_at_least_one_level() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 1);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], ids[0], ids[0]);
    let chain = external_execution::start_controller_chain(ticket);
    external_execution::finish_controller_enable_bypass_type<DummyBypass>(
        chain,
        &mut ous[0],
        &mut vaults[0],
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESubOUMismatch)]
/// The executor cannot finish on a different SubOU than the one voted on,
/// even one the chain legitimately reaches.
fun chain_finish_is_pinned_to_the_voted_subou() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, DEPTH);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    let control_id = control_of(&ous[DEPTH]);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], ids[DEPTH], control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, &ous, &vaults, 5);
    external_execution::finish_controller_enable_bypass_type<DummyBypass>(
        chain,
        &mut ous[5],
        &mut vaults[5],
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ESelfBootstrapDenied)]
/// The chain keeps the self-bootstrap denylist.
fun chain_refuses_bypass_meta_types() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 2);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    let control_id = control_of(&ous[2]);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], ids[2], control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, &ous, &vaults, 2);
    external_execution::finish_controller_enable_bypass_type<EnableBypassType>(
        chain,
        &mut ous[2],
        &mut vaults[2],
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::EChainTooDeep)]
/// Chains stop at MAX_CHAIN_DEPTH (16) levels.
fun chain_depth_is_bounded() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 17);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, vaults) = take_all(&mut scenario, &ids);
    let control_id = control_of(&ous[17]);
    let ticket = grant_ticket(&mut scenario, &clock, &mut ous[0], ids[17], control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, &ous, &vaults, 17);
    abort 0
}

// === Revoke ===

#[test]
/// The root revokes a bypass seven levels down: cap destroyed, slot removed.
fun chain_revokes_bypass_seven_levels_down() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, DEPTH);
    enable_on_root(&mut scenario, &clock, ids[0]);

    tx_grant(&mut scenario, &clock, &ids, DEPTH);
    assert_state(&mut scenario, ids[DEPTH], true, 1);
    tx_revoke(&mut scenario, &clock, &ids, DEPTH);
    assert_state(&mut scenario, ids[DEPTH], false, 0);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Finding 1 regression: the SubOU removes the slot to shield the cap. The
/// revoke still destroys the cap, so re-creating the slot revives nothing.
fun revoke_survives_subou_removing_the_slot() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 2);
    enable_on_root(&mut scenario, &clock, ids[0]);

    tx_grant(&mut scenario, &clock, &ids, 2);
    tx_subou_disables_slot(&mut scenario, &clock, ids[2], b"DummyBypass");
    assert_state(&mut scenario, ids[2], false, 1);

    tx_revoke(&mut scenario, &clock, &ids, 2);
    assert_state(&mut scenario, ids[2], false, 0);

    tx_subou_enables_slot(&mut scenario, &clock, ids[2], b"DummyBypass");
    assert_state(&mut scenario, ids[2], true, 0);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Finding 1 regression: the SubOU renames the slot. The revoke pins the Move
/// type, not the display key, so it still removes the slot and the cap.
fun revoke_survives_subou_renaming_the_slot() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 2);
    enable_on_root(&mut scenario, &clock, ids[0]);

    tx_grant(&mut scenario, &clock, &ids, 2);
    tx_subou_disables_slot(&mut scenario, &clock, ids[2], b"DummyBypass");
    tx_subou_enables_slot(&mut scenario, &clock, ids[2], b"Renamed");
    assert_state(&mut scenario, ids[2], true, 1);

    tx_revoke(&mut scenario, &clock, &ids, 2);
    assert_state(&mut scenario, ids[2], false, 0);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Finding 1 regression: an orphaned cap plus a re-grant leaves two caps. One
/// revoke sweeps both, so the controller always gets back to zero.
fun revoke_sweeps_duplicate_caps() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 2);
    enable_on_root(&mut scenario, &clock, ids[0]);

    tx_grant(&mut scenario, &clock, &ids, 2);
    tx_subou_disables_slot(&mut scenario, &clock, ids[2], b"DummyBypass");
    tx_grant(&mut scenario, &clock, &ids, 2);
    assert_state(&mut scenario, ids[2], true, 2);

    tx_revoke(&mut scenario, &clock, &ids, 2);
    assert_state(&mut scenario, ids[2], false, 0);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::external_execution::ECapNotFound)]
/// A revoke with neither a cap nor a slot to remove aborts.
fun revoke_with_nothing_to_revoke_aborts() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 2);
    enable_on_root(&mut scenario, &clock, ids[0]);

    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    revoke(&mut scenario, &clock, &mut ous, &mut vaults, 2);
    abort 0
}

#[test, expected_failure(abort_code = armature::external_execution::ETypeMismatch)]
/// The executor cannot revoke a different type than the board approved.
fun revoke_is_pinned_to_the_voted_type() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let ids = build_chain(&mut scenario, 1);
    enable_on_root(&mut scenario, &clock, ids[0]);

    tx_grant(&mut scenario, &clock, &ids, 1);
    scenario.next_tx(ADMIN);
    let (mut ous, mut vaults) = take_all(&mut scenario, &ids);
    let subou_id = ids[1];
    let control_id = control_of(&ous[1]);
    let ticket = revoke_ticket(&mut scenario, &clock, &mut ous[0], subou_id, control_id);
    let mut chain = external_execution::start_controller_chain(ticket);
    walk(&mut chain, &ous, &vaults, 1);
    external_execution::finish_controller_disable_bypass_type<EnableBypassType>(
        chain,
        &mut ous[1],
        &mut vaults[1],
        scenario.ctx(),
    );
    abort 0
}
