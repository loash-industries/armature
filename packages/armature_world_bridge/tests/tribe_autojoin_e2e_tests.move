/// End-to-end AutojoinOU on the Members SubOU of a tribe built by
/// `armature::tribe::create_tribe`, with no test seams on the armature side:
/// every type is enabled and every cap is minted through governance.
///
/// Members is a controlled SubOU, so it cannot pass EnableBypassType itself.
/// Officers (its controller) grants the bypass with ControllerEnableBypassType
/// and can revoke it with ControllerDisableBypassType.
#[test_only]
module armature_world_bridge::tribe_autojoin_e2e_tests;

use armature::admin_ops;
use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::controller_disable_bypass_type::ControllerDisableBypassType;
use armature::controller_enable_bypass_type::ControllerEnableBypassType;
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::external_execution;
use armature::ou::OU;
use armature::proposal::{Self, ExternalExecutionCap, Proposal, ProposalConfig};
use armature::tribe;
use armature_world_bridge::autojoin_ops::{Self, AutojoinOU};
use armature_world_bridge::configure_autojoin::{Self, ConfigureAutojoin};
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};
use world::access::{Self, AdminACL};
use world::character::{Self, Character};
use world::object_registry::{Self, ObjectRegistry};
use world::world::{Self as world_module, GovernorCap};

// === Test constants ===

const GOVERNOR: address = @0xA1;
const ADMIN: address = @0xA2;
const CREATOR: address = @0xA3;
const OFFICER_A: address = @0xC1;
const OFFICER_B: address = @0xC2;
const MEMBER_A: address = @0xD1;
const OFFICER_ADMIN: address = @0xE1;
const MEMBER_ADMIN: address = @0xE2;
const PLAYER: address = @0xB1;
const OTHER_PLAYER: address = @0xB2;

const TENANT: vector<u8> = b"TEST";
const TRIBE_ID: u32 = 42;
const EXPIRY_MS: u64 = 604_800_000;

/// IDs of the tribe's three OUs.
public struct Tribe has copy, drop {
    root: ID,
    officers: ID,
    members: ID,
}

// === Configs ===

fun whole_board(): ProposalConfig { proposal::new_config(8_000, 10_000, 0, EXPIRY_MS, 0, 0) }

fun consensus(): ProposalConfig { proposal::new_config(5_000, 8_000, 0, EXPIRY_MS, 0, 0) }

fun autojoin_config(): ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 0).with_permissions(
        autojoin_ops::autojoin_permissions(),
    )
}

fun configure_config(): ProposalConfig { proposal::new_config(5_000, 5_000, 0, EXPIRY_MS, 0, 0) }

// === World helpers ===

fun setup_world(scenario: &mut Scenario) {
    scenario.next_tx(GOVERNOR);
    {
        world_module::init_for_testing(scenario.ctx());
        access::init_for_testing(scenario.ctx());
        object_registry::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(GOVERNOR);
    {
        let gov_cap = scenario.take_from_sender<GovernorCap>();
        let mut admin_acl = scenario.take_shared<AdminACL>();
        access::add_sponsor_to_acl(&mut admin_acl, &gov_cap, ADMIN);
        scenario.return_to_sender(gov_cap);
        ts::return_shared(admin_acl);
    };
}

fun create_character(scenario: &mut Scenario, game_id: u32, tribe_id: u32, wallet: address): ID {
    scenario.next_tx(ADMIN);
    let mut registry = scenario.take_shared<ObjectRegistry>();
    let admin_acl = scenario.take_shared<AdminACL>();
    let ch = character::create_character(
        &mut registry,
        &admin_acl,
        game_id,
        TENANT.to_string(),
        tribe_id,
        wallet,
        string::utf8(b"test character"),
        scenario.ctx(),
    );
    let id = object::id(&ch);
    ch.share_character(&admin_acl, scenario.ctx());
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    id
}

// === Governance helpers ===

fun create_tribe(scenario: &mut Scenario): Tribe {
    scenario.next_tx(CREATOR);
    let (root, officers, members) = tribe::create_tribe(
        vector[CREATOR],
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
    Tribe { root, officers, members }
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
        ts::return_shared(ou);
    };
    let mut i = 0;
    while (i < voters.length()) {
        scenario.next_tx(voters[i]);
        let mut prop = scenario.take_shared<Proposal<P>>();
        let ou = scenario.take_shared_by_id<OU>(ou_id);
        board_voting::vote(&mut prop, &ou, true, clock, scenario.ctx());
        ts::return_shared(ou);
        ts::return_shared(prop);
        i = i + 1;
    };
}

/// Pass and execute EnableProposalType<T> on `ou_id`.
fun enable_type<T: store>(
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
    ts::return_shared(freeze);
    ts::return_shared(ou);
}

fun control_id_in(scenario: &mut Scenario, ou_id: ID): ID {
    scenario.next_tx(CREATOR);
    let ou = scenario.take_shared_by_id<OU>(ou_id);
    let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let id = vault.ids_for_type<SubOUControl>()[0];
    ts::return_shared(vault);
    ts::return_shared(ou);
    id
}

/// Officers enables the controller bypass types on itself by vote.
fun officers_enable_controller_types(scenario: &mut Scenario, clock: &Clock, t: &Tribe) {
    let officers = vector[OFFICER_A, OFFICER_B];
    enable_type<ControllerEnableBypassType>(
        scenario,
        clock,
        t.officers,
        b"ControllerEnableBypassType",
        whole_board(),
        officers,
    );
    enable_type<ControllerDisableBypassType>(
        scenario,
        clock,
        t.officers,
        b"ControllerDisableBypassType",
        consensus(),
        officers,
    );
}

/// Officers grants AutojoinOU bypass to Members. Returns the cap ID, read from
/// the Members vault.
fun officers_grant_autojoin(scenario: &mut Scenario, clock: &Clock, t: &Tribe): ID {
    let control_id = control_id_in(scenario, t.officers);
    submit_and_vote(
        scenario,
        clock,
        t.officers,
        external_execution::new_controller_enable_bypass_type(
            t.members,
            control_id,
            b"AutojoinOU".to_ascii_string(),
            type_name::with_defining_ids<AutojoinOU>(),
            autojoin_config(),
        ),
        vector[OFFICER_A, OFFICER_B],
    );

    scenario.next_tx(OFFICER_A);
    let mut officers = scenario.take_shared_by_id<OU>(t.officers);
    let mut officer_vault = scenario.take_shared_by_id<
        CapabilityVault,
    >(officers.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let mut members = scenario.take_shared_by_id<OU>(t.members);
    let mut member_vault = scenario.take_shared_by_id<
        CapabilityVault,
    >(members.capability_vault_id());
    let prop = scenario.take_shared<Proposal<ControllerEnableBypassType>>();
    let ticket = board_voting::ticket_from_vote(
        &mut officers,
        prop,
        &freeze,
        clock,
        scenario.ctx(),
    );
    external_execution::execute_controller_enable_bypass_type<AutojoinOU>(
        &mut officer_vault,
        &mut members,
        &mut member_vault,
        ticket,
        scenario.ctx(),
    );
    let ids = member_vault.ids_for_type<ExternalExecutionCap<AutojoinOU>>();
    assert!(ids.length() == 1);
    ts::return_shared(member_vault);
    ts::return_shared(members);
    ts::return_shared(freeze);
    ts::return_shared(officer_vault);
    ts::return_shared(officers);
    ids[0]
}

/// Officers revokes Members' AutojoinOU bypass.
fun officers_revoke_autojoin(scenario: &mut Scenario, clock: &Clock, t: &Tribe, cap_id: ID) {
    let control_id = control_id_in(scenario, t.officers);
    submit_and_vote(
        scenario,
        clock,
        t.officers,
        external_execution::new_controller_disable_bypass_type(
            t.members,
            control_id,
            b"AutojoinOU".to_ascii_string(),
            cap_id,
        ),
        // 50% quorum: the first of two officers' YES passes it.
        vector[OFFICER_A],
    );

    scenario.next_tx(OFFICER_A);
    let mut officers = scenario.take_shared_by_id<OU>(t.officers);
    let mut officer_vault = scenario.take_shared_by_id<
        CapabilityVault,
    >(officers.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let mut members = scenario.take_shared_by_id<OU>(t.members);
    let mut member_vault = scenario.take_shared_by_id<
        CapabilityVault,
    >(members.capability_vault_id());
    let prop = scenario.take_shared<Proposal<ControllerDisableBypassType>>();
    let ticket = board_voting::ticket_from_vote(
        &mut officers,
        prop,
        &freeze,
        clock,
        scenario.ctx(),
    );
    external_execution::execute_controller_disable_bypass_type<AutojoinOU>(
        &mut officer_vault,
        &mut members,
        &mut member_vault,
        ticket,
        scenario.ctx(),
    );
    ts::return_shared(member_vault);
    ts::return_shared(members);
    ts::return_shared(freeze);
    ts::return_shared(officer_vault);
    ts::return_shared(officers);
}

/// Members enables ConfigureAutojoin and allowlists `tribe_ids` (kill-switch on).
fun members_configure_allowlist(
    scenario: &mut Scenario,
    clock: &Clock,
    t: &Tribe,
    tribe_ids: vector<u32>,
) {
    let voters = vector[MEMBER_A];
    enable_type<ConfigureAutojoin>(
        scenario,
        clock,
        t.members,
        b"ConfigureAutojoin",
        configure_config(),
        voters,
    );
    submit_and_vote(
        scenario,
        clock,
        t.members,
        configure_autojoin::new(tribe_ids, vector[], option::some(true)),
        voters,
    );
    scenario.next_tx(MEMBER_A);
    let mut members = scenario.take_shared_by_id<OU>(t.members);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(members.emergency_freeze_id());
    let prop = scenario.take_shared<Proposal<ConfigureAutojoin>>();
    let ticket = board_voting::ticket_from_vote(&mut members, prop, &freeze, clock, scenario.ctx());
    configure_autojoin::execute_configure_autojoin(&mut members, ticket);
    ts::return_shared(freeze);
    ts::return_shared(members);
}

/// `sender` autojoins Members with the cap `cap_id` from `vault_owner`'s vault.
fun autojoin_members(
    scenario: &mut Scenario,
    clock: &Clock,
    t: &Tribe,
    vault_owner: ID,
    cap_id: ID,
    character_id: ID,
    sender: address,
) {
    scenario.next_tx(sender);
    let mut members = scenario.take_shared_by_id<OU>(t.members);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(members.emergency_freeze_id());
    let vault_id = if (vault_owner == t.members) {
        members.capability_vault_id()
    } else {
        let owner = scenario.take_shared_by_id<OU>(vault_owner);
        let id = owner.capability_vault_id();
        ts::return_shared(owner);
        id
    };
    let vault = scenario.take_shared_by_id<CapabilityVault>(vault_id);
    let character = scenario.take_shared_by_id<Character>(character_id);
    autojoin_ops::autojoin(
        &mut members,
        &vault,
        cap_id,
        &character,
        &freeze,
        clock,
        scenario.ctx(),
    );
    ts::return_shared(character);
    ts::return_shared(vault);
    ts::return_shared(freeze);
    ts::return_shared(members);
}

fun is_member(scenario: &mut Scenario, t: &Tribe, addr: address): bool {
    scenario.next_tx(CREATOR);
    let members = scenario.take_shared_by_id<OU>(t.members);
    let result = members.governance().is_board_member(addr);
    ts::return_shared(members);
    result
}

// === Tests ===

#[test]
/// The reported blocker: on a `create_tribe` tribe, Officers grants AutojoinOU
/// to Members, Members allowlists its in-game tribe, and an allowlisted player
/// joins the Members board without a vote.
fun create_tribe_members_autojoin_end_to_end() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, TRIBE_ID, PLAYER);
    let t = create_tribe(&mut scenario);

    officers_enable_controller_types(&mut scenario, &clock, &t);
    let cap_id = officers_grant_autojoin(&mut scenario, &clock, &t);
    members_configure_allowlist(&mut scenario, &clock, &t, vector[TRIBE_ID]);

    assert!(!is_member(&mut scenario, &t, PLAYER));
    autojoin_members(&mut scenario, &clock, &t, t.members, cap_id, character_id, PLAYER);
    assert!(is_member(&mut scenario, &t, PLAYER));

    // A second allowlisted player can join too; the cap is reusable.
    let other_id = create_character(&mut scenario, 101, TRIBE_ID, OTHER_PLAYER);
    autojoin_members(&mut scenario, &clock, &t, t.members, cap_id, other_id, OTHER_PLAYER);
    assert!(is_member(&mut scenario, &t, OTHER_PLAYER));

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature_world_bridge::autojoin_ops::ETribeIdNotAllowed)]
/// The bridge's own checks still apply on a controller-granted bypass.
fun create_tribe_autojoin_rejects_unlisted_tribe() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 999, PLAYER);
    let t = create_tribe(&mut scenario);

    officers_enable_controller_types(&mut scenario, &clock, &t);
    let cap_id = officers_grant_autojoin(&mut scenario, &clock, &t);
    members_configure_allowlist(&mut scenario, &clock, &t, vector[TRIBE_ID]);

    autojoin_members(&mut scenario, &clock, &t, t.members, cap_id, character_id, PLAYER);
    abort 0
}

#[test, expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
/// After Officers revokes the bypass, the old cap is gone and autojoin fails.
fun create_tribe_autojoin_after_revoke_aborts() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, TRIBE_ID, PLAYER);
    let t = create_tribe(&mut scenario);

    officers_enable_controller_types(&mut scenario, &clock, &t);
    let cap_id = officers_grant_autojoin(&mut scenario, &clock, &t);
    members_configure_allowlist(&mut scenario, &clock, &t, vector[TRIBE_ID]);
    officers_revoke_autojoin(&mut scenario, &clock, &t, cap_id);

    scenario.next_tx(CREATOR);
    {
        let members = scenario.take_shared_by_id<OU>(t.members);
        assert!(!members.is_type_enabled<AutojoinOU>());
        ts::return_shared(members);
    };

    autojoin_members(&mut scenario, &clock, &t, t.members, cap_id, character_id, PLAYER);
    abort 0
}

#[test, expected_failure(abort_code = armature::capability_vault::EOUIdMismatch)]
/// Regression guard for why the controller path is needed: a cap the root
/// mints for itself through EnableBypassType cannot drive Members' autojoin.
fun root_cap_cannot_drive_members_autojoin() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000);

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, TRIBE_ID, PLAYER);
    let t = create_tribe(&mut scenario);

    // Members gets the slot and allowlist (Officers grants nothing).
    members_configure_allowlist(&mut scenario, &clock, &t, vector[TRIBE_ID]);

    // Root bypass-enables AutojoinOU on itself.
    submit_and_vote(
        &mut scenario,
        &clock,
        t.root,
        external_execution::new_enable_bypass_type(
            b"AutojoinOU".to_ascii_string(),
            type_name::with_defining_ids<AutojoinOU>(),
            autojoin_config(),
        ),
        vector[CREATOR],
    );
    scenario.next_tx(CREATOR);
    let root_cap_id = {
        let mut root = scenario.take_shared_by_id<OU>(t.root);
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(root.capability_vault_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(root.emergency_freeze_id());
        let prop = scenario.take_shared<Proposal<EnableBypassType>>();
        let ticket = board_voting::ticket_from_vote(
            &mut root,
            prop,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<AutojoinOU>(
            &mut root,
            &mut vault,
            ticket,
            scenario.ctx(),
        );
        let id = vault.ids_for_type<ExternalExecutionCap<AutojoinOU>>()[0];
        ts::return_shared(freeze);
        ts::return_shared(vault);
        ts::return_shared(root);
        id
    };

    autojoin_members(&mut scenario, &clock, &t, t.root, root_cap_id, character_id, PLAYER);
    abort 0
}
