/// Controller chains inside a SubOU's own subtree: a SubOU creates a child and
/// grants it bypass execution, and a controller chain passes through an OU that
/// is Migrating.
#[test_only]
module armature::controller_chain_subtree_tests;

use armature::admin_ops;
use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::controller;
use armature::controller_disable_bypass_type::ControllerDisableBypassType;
use armature::controller_enable_bypass_type::ControllerEnableBypassType;
use armature::emergency::EmergencyFreeze;
use armature::enable_proposal_type;
use armature::external_execution;
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, ExternalExecutionCap, ProposalConfig};
use armature::tribe;
use std::internal;
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};

const ADMIN: address = @0xA1;
const EXPIRY_MS: u64 = 604_800_000;

/// An extension type whose module passes its request to
/// `tribe::create_wired_subou`, so an OU can create a SubOU by its own vote.
public struct SpawnChild has drop, store {}

/// An extension type holding MIGRATE; its module calls `ou::set_migrating`.
public struct SelfMigrate has drop, store {}

/// The bypass type granted to the child.
public struct ChildBypass has drop, store {}

/// Payload for the root's controller override.
public struct Override has drop, store {}

// === Helpers ===

fun whole_board(): ProposalConfig { proposal::new_config(8_000, 10_000, 0, EXPIRY_MS, 0, 0) }

fun bypass_config(): ProposalConfig { proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 0) }

fun new_clock(scenario: &mut Scenario): Clock {
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);
    clock
}

/// A root R and a SubOU M it controls. Both boards are [ADMIN].
fun build_root_and_subou(scenario: &mut Scenario): (ID, ID) {
    scenario.next_tx(ADMIN);
    let root_id = ou::create(
        &governance::init_board(vector[ADMIN]),
        string::utf8(b"Root"),
        string::utf8(b""),
        scenario.ctx(),
    );
    scenario.next_tx(ADMIN);
    let root = scenario.take_shared_by_id<OU>(root_id);
    let mut root_vault = scenario.take_shared_by_id<CapabilityVault>(root.capability_vault_id());
    // Stands in for R's CreateSubOU vote.
    let req = proposal::new_privileged_request_for_testing<Override>(root.id(), root.id());
    let m_id = tribe::create_wired_subou(
        vector[ADMIN],
        string::utf8(b"M"),
        string::utf8(b""),
        ADMIN,
        &mut root_vault,
        &req,
        vector[],
        scenario.ctx(),
    );
    proposal::consume_execution_request_for_testing(req);
    ts::return_shared(root_vault);
    ts::return_shared(root);
    (root_id, m_id)
}

/// `ou_id`'s board enables `T` by its own vote.
fun enable_on<T: store>(
    scenario: &mut Scenario,
    clock: &Clock,
    ou_id: ID,
    key: vector<u8>,
    cfg: ProposalConfig,
) {
    scenario.next_tx(ADMIN);
    let mut o = scenario.take_shared_by_id<OU>(ou_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(o.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        &mut o,
        option::none(),
        enable_proposal_type::new(key.to_ascii_string(), type_name::with_defining_ids<T>(), cfg),
        &freeze,
        clock,
        scenario.ctx(),
    );
    admin_ops::execute_enable_proposal_type<T>(&mut o, ticket);
    ts::return_shared(freeze);
    ts::return_shared(o);
}

/// M's board creates a child wired to M, enables ControllerEnableBypassType on
/// M, and grants the child ChildBypass through a one-level chain.
fun subou_creates_child_with_bypass(scenario: &mut Scenario, clock: &Clock, m_id: ID): ID {
    enable_on<SpawnChild>(
        scenario,
        clock,
        m_id,
        b"SpawnChild",
        whole_board().with_permissions(permissions::vault_store() | permissions::vault_extract()),
    );

    scenario.next_tx(ADMIN);
    let child_id = {
        let mut m = scenario.take_shared_by_id<OU>(m_id);
        let mut m_vault = scenario.take_shared_by_id<CapabilityVault>(m.capability_vault_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(m.emergency_freeze_id());
        let ticket = board_voting::submit_vote_execute(
            &mut m,
            option::none(),
            SpawnChild {},
            &freeze,
            clock,
            scenario.ctx(),
        );
        let child_id = tribe::create_wired_subou(
            vector[ADMIN],
            string::utf8(b"Child"),
            string::utf8(b""),
            ADMIN,
            &mut m_vault,
            proposal::ticket_request(&ticket, internal::permit<SpawnChild>()),
            vector[],
            scenario.ctx(),
        );
        proposal::discharge(ticket, internal::permit<SpawnChild>());
        ts::return_shared(freeze);
        ts::return_shared(m_vault);
        ts::return_shared(m);
        child_id
    };

    enable_on<ControllerEnableBypassType>(
        scenario,
        clock,
        m_id,
        b"ControllerEnableBypassType",
        whole_board(),
    );

    scenario.next_tx(ADMIN);
    {
        let mut m = scenario.take_shared_by_id<OU>(m_id);
        let m_vault = scenario.take_shared_by_id<CapabilityVault>(m.capability_vault_id());
        let mut child = scenario.take_shared_by_id<OU>(child_id);
        let mut child_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(child.capability_vault_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(m.emergency_freeze_id());
        let ticket = board_voting::submit_vote_execute(
            &mut m,
            option::none(),
            external_execution::new_controller_enable_bypass_type(
                child_id,
                *child.controller_cap_id().borrow(),
                b"ChildBypass".to_ascii_string(),
                type_name::with_defining_ids<ChildBypass>(),
                bypass_config(),
            ),
            &freeze,
            clock,
            scenario.ctx(),
        );
        let mut chain = external_execution::start_controller_chain(ticket);
        external_execution::extend_controller_chain(&mut chain, &m_vault, &child);
        external_execution::finish_controller_enable_bypass_type<ChildBypass>(
            chain,
            &mut child,
            &mut child_vault,
            scenario.ctx(),
        );
        assert!(child_vault.ids_for_type<ExternalExecutionCap<ChildBypass>>().length() == 1);
        ts::return_shared(freeze);
        ts::return_shared(child_vault);
        ts::return_shared(child);
        ts::return_shared(m_vault);
        ts::return_shared(m);
    };

    child_id
}

/// `ou_id`'s board enables SelfMigrate (MIGRATE) and marks the OU Migrating.
fun self_migrate(scenario: &mut Scenario, clock: &Clock, ou_id: ID, successor_id: ID) {
    enable_on<SelfMigrate>(
        scenario,
        clock,
        ou_id,
        b"SelfMigrate",
        whole_board().with_permissions(permissions::migrate()),
    );
    scenario.next_tx(ADMIN);
    let mut o = scenario.take_shared_by_id<OU>(ou_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(o.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        &mut o,
        option::none(),
        SelfMigrate {},
        &freeze,
        clock,
        scenario.ctx(),
    );
    o.set_migrating(
        successor_id,
        proposal::ticket_request(&ticket, internal::permit<SelfMigrate>()),
    );
    proposal::discharge(ticket, internal::permit<SelfMigrate>());
    assert!(o.status().is_migrating());
    ts::return_shared(freeze);
    ts::return_shared(o);
}

/// One PTB: mint a ChildBypass ticket on `child_id` from its vault's cap.
fun use_child_bypass(scenario: &mut Scenario, clock: &Clock, child_id: ID) {
    scenario.next_tx(ADMIN);
    let child = scenario.take_shared_by_id<OU>(child_id);
    let child_vault = scenario.take_shared_by_id<CapabilityVault>(child.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(child.emergency_freeze_id());
    let cap_id = child_vault.ids_for_type<ExternalExecutionCap<ChildBypass>>()[0];
    let cap = child_vault.borrow_external_cap<ChildBypass>(child.id(), cap_id);
    let ticket = external_execution::ticket_from_cap_readonly<ChildBypass>(
        cap,
        &child,
        &freeze,
        option::none(),
        ChildBypass {},
        internal::permit<ChildBypass>(),
        clock,
        scenario.ctx(),
    );
    proposal::discharge(ticket, internal::permit<ChildBypass>());
    ts::return_shared(freeze);
    ts::return_shared(child_vault);
    ts::return_shared(child);
}

// === Tests ===

/// A SubOU creates a child by its own vote and grants it a bypass through a
/// one-level chain. The bypass belongs to the child, so pausing the SubOU does
/// not stop it; the SubOU's controller revokes it through the chain instead.
#[test]
fun subou_grants_bypass_to_own_child() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let (root_id, m_id) = build_root_and_subou(&mut scenario);
    let child_id = subou_creates_child_with_bypass(&mut scenario, &clock, m_id);

    // R pauses M with a controller override.
    scenario.next_tx(ADMIN);
    {
        let root = scenario.take_shared_by_id<OU>(root_id);
        let root_vault = scenario.take_shared_by_id<CapabilityVault>(root.capability_vault_id());
        let mut m = scenario.take_shared_by_id<OU>(m_id);
        let ctrl_id = *m.controller_cap_id().borrow();
        let rreq = proposal::with_borrow_scope_for_testing(
            proposal::new_privileged_request_for_testing<Override>(root.id(), root.id()),
            vector[type_name::with_defining_ids<SubOUControl>()],
        );
        let control: &SubOUControl = root_vault.borrow_cap(ctrl_id, &rreq);
        let mreq = controller::privileged_submit(
            control,
            &m,
            b"Pause".to_ascii_string(),
            option::none(),
            Override {},
            scenario.ctx(),
        );
        m.set_controller_paused(true, &mreq);
        controller::privileged_consume(mreq, control);
        proposal::consume_execution_request_for_testing(rreq);
        assert!(m.is_controller_paused());
        ts::return_shared(m);
        ts::return_shared(root_vault);
        ts::return_shared(root);
    };

    use_child_bypass(&mut scenario, &clock, child_id);

    clock.destroy_for_testing();
    scenario.end();
}

/// A Migrating OU in the middle of a chain does not stop it: R revokes the
/// child's bypass through R -> M -> child after M marks itself Migrating.
#[test]
fun root_revokes_through_migrating_subou() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let (root_id, m_id) = build_root_and_subou(&mut scenario);
    let child_id = subou_creates_child_with_bypass(&mut scenario, &clock, m_id);
    self_migrate(&mut scenario, &clock, m_id, child_id);
    use_child_bypass(&mut scenario, &clock, child_id);

    enable_on<ControllerDisableBypassType>(
        &mut scenario,
        &clock,
        root_id,
        b"ControllerDisableBypassType",
        whole_board(),
    );
    scenario.next_tx(ADMIN);
    let mut root = scenario.take_shared_by_id<OU>(root_id);
    let root_vault = scenario.take_shared_by_id<CapabilityVault>(root.capability_vault_id());
    let m = scenario.take_shared_by_id<OU>(m_id);
    let m_vault = scenario.take_shared_by_id<CapabilityVault>(m.capability_vault_id());
    let mut child = scenario.take_shared_by_id<OU>(child_id);
    let mut child_vault = scenario.take_shared_by_id<CapabilityVault>(child.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(root.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        &mut root,
        option::none(),
        external_execution::new_controller_disable_bypass_type(
            child_id,
            *child.controller_cap_id().borrow(),
            type_name::with_defining_ids<ChildBypass>(),
        ),
        &freeze,
        &clock,
        scenario.ctx(),
    );
    let mut chain = external_execution::start_controller_chain(ticket);
    external_execution::extend_controller_chain(&mut chain, &root_vault, &m);
    external_execution::extend_controller_chain(&mut chain, &m_vault, &child);
    external_execution::finish_controller_disable_bypass_type<ChildBypass>(
        chain,
        &mut child,
        &mut child_vault,
        scenario.ctx(),
    );
    assert!(child_vault.ids_for_type<ExternalExecutionCap<ChildBypass>>().is_empty());
    assert!(!child.is_type_enabled<ChildBypass>());

    ts::return_shared(freeze);
    ts::return_shared(child_vault);
    ts::return_shared(child);
    ts::return_shared(m_vault);
    ts::return_shared(m);
    ts::return_shared(root_vault);
    ts::return_shared(root);
    clock.destroy_for_testing();
    scenario.end();
}

/// A grant needs an Active target: the chain reaches a Migrating SubOU, and
/// finish aborts.
#[test, expected_failure(abort_code = external_execution::EOUNotActive)]
fun grant_to_migrating_subou_aborts() {
    let mut scenario = ts::begin(ADMIN);
    let clock = new_clock(&mut scenario);
    let (root_id, m_id) = build_root_and_subou(&mut scenario);
    self_migrate(&mut scenario, &clock, m_id, root_id);
    enable_on<ControllerEnableBypassType>(
        &mut scenario,
        &clock,
        root_id,
        b"ControllerEnableBypassType",
        whole_board(),
    );

    scenario.next_tx(ADMIN);
    let mut root = scenario.take_shared_by_id<OU>(root_id);
    let root_vault = scenario.take_shared_by_id<CapabilityVault>(root.capability_vault_id());
    let mut m = scenario.take_shared_by_id<OU>(m_id);
    let mut m_vault = scenario.take_shared_by_id<CapabilityVault>(m.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(root.emergency_freeze_id());
    let ticket = board_voting::submit_vote_execute(
        &mut root,
        option::none(),
        external_execution::new_controller_enable_bypass_type(
            m_id,
            *m.controller_cap_id().borrow(),
            b"ChildBypass".to_ascii_string(),
            type_name::with_defining_ids<ChildBypass>(),
            bypass_config(),
        ),
        &freeze,
        &clock,
        scenario.ctx(),
    );
    let mut chain = external_execution::start_controller_chain(ticket);
    external_execution::extend_controller_chain(&mut chain, &root_vault, &m);
    external_execution::finish_controller_enable_bypass_type<ChildBypass>(
        chain,
        &mut m,
        &mut m_vault,
        scenario.ctx(),
    );
    abort 0
}
