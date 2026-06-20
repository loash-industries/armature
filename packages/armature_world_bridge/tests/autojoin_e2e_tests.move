/// End-to-end tests for the AutojoinDAO bridge against a real
/// `world::character::Character`. Setup uses world's public `init_for_testing`
/// hooks (cross-package #[test_only] are accessible) plus armature's
/// test seams (`test_enable_type`, `test_bind_type`) and the
/// `ExternalExecutionCap` test helper from #143 to avoid the 80%
/// governance setup. Focuses coverage on bridge logic.
#[test_only]
module armature_world_bridge::autojoin_e2e_tests;

use armature::board_voting;
use armature::capability_vault::{Self, CapabilityVault};
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature_world_bridge::autojoin_ops::{Self, AutojoinDAO};
use armature_world_bridge::configure_autojoin::{Self, ConfigureAutojoin};
use std::string;
use sui::clock;
use sui::test_scenario as ts;
use world::access::{Self, AdminACL};
use world::character::{Self, Character};
use world::object_registry::{Self, ObjectRegistry};
use world::world::{Self as world_module, GovernorCap};

// === Test constants ===

const GOVERNOR: address = @0xA1;
const ADMIN: address = @0xA2;
const CREATOR: address = @0xA3;
const PLAYER: address = @0xB1;

const TENANT: vector<u8> = b"TEST";

// === Setup helpers ===

/// Minimal world bootstrap: init world+access+object_registry and
/// authorize ADMIN as a sponsor so we can mint Characters.
fun setup_world(scenario: &mut ts::Scenario) {
    ts::next_tx(scenario, GOVERNOR);
    {
        world_module::init_for_testing(scenario.ctx());
        access::init_for_testing(scenario.ctx());
        object_registry::init_for_testing(scenario.ctx());
    };
    ts::next_tx(scenario, GOVERNOR);
    {
        let gov_cap = ts::take_from_sender<GovernorCap>(scenario);
        let mut admin_acl = ts::take_shared<AdminACL>(scenario);
        access::add_sponsor_to_acl(&mut admin_acl, &gov_cap, ADMIN);
        ts::return_to_sender(scenario, gov_cap);
        ts::return_shared(admin_acl);
    };
}

/// Create + share a Character with the given game_id, tribe_id, and wallet.
fun create_character(
    scenario: &mut ts::Scenario,
    game_id: u32,
    tribe_id: u32,
    wallet: address,
): ID {
    ts::next_tx(scenario, ADMIN);
    let mut registry = ts::take_shared<ObjectRegistry>(scenario);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
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

/// Create a DAO with CREATOR as sole board member; enable AutojoinDAO and
/// ConfigureAutojoin types via test seams; deposit a synthetic
/// ExternalExecutionCap<AutojoinDAO> into the vault. Returns (dao_id, vault_id, cap_id).
fun setup_dao_with_autojoin(scenario: &mut ts::Scenario): (ID, ID, ID) {
    ts::next_tx(scenario, CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    let mut dao_id_opt = option::none<ID>();
    let mut vault_id_opt = option::none<ID>();
    let mut cap_id_opt = option::none<ID>();

    ts::next_tx(scenario, CREATOR);
    {
        let mut dao = ts::take_shared<DAO>(scenario);
        let mut vault = ts::take_shared<CapabilityVault>(scenario);

        // Enable + bind both proposal types via test seams.
        let cfg = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"AutojoinDAO".to_ascii_string(), cfg);
        dao.test_bind_type<AutojoinDAO>(b"AutojoinDAO".to_ascii_string());
        dao.test_enable_type(b"ConfigureAutojoin".to_ascii_string(), cfg);
        dao.test_bind_type<ConfigureAutojoin>(b"ConfigureAutojoin".to_ascii_string());

        // Mint a synthetic cap for AutojoinDAO and deposit into the vault.
        // capability_vault::store_cap_for_testing bypasses the request gate.
        let cap = proposal::new_external_execution_cap_for_testing<AutojoinDAO>(
            dao.id(),
            scenario.ctx(),
        );
        let cap_id = object::id(&cap);
        capability_vault::store_cap_for_testing(&mut vault, cap);

        dao_id_opt.fill(dao.id());
        vault_id_opt.fill(object::id(&vault));
        cap_id_opt.fill(cap_id);

        ts::return_shared(vault);
        ts::return_shared(dao);
    };

    (dao_id_opt.destroy_some(), vault_id_opt.destroy_some(), cap_id_opt.destroy_some())
}

/// Configure the allowlist via a real ConfigureAutojoin governance flow
/// (single-member board → 100% vote). add_ids are added; enabled is set.
fun configure_allowlist(
    scenario: &mut ts::Scenario,
    clock: &mut clock::Clock,
    add_ids: vector<u32>,
    enabled: bool,
    ts_submit: u64,
    ts_vote: u64,
    ts_exec: u64,
) {
    clock.set_for_testing(ts_submit);
    ts::next_tx(scenario, CREATOR);
    {
        let dao = ts::take_shared<DAO>(scenario);
        let payload = configure_autojoin::new(add_ids, vector[], option::some(enabled));
        board_voting::submit_proposal(
            &dao,
            b"ConfigureAutojoin".to_ascii_string(),
            option::none(),
            payload,
            clock,
            scenario.ctx(),
        );
        ts::return_shared(dao);
    };

    clock.set_for_testing(ts_vote);
    ts::next_tx(scenario, CREATOR);
    {
        let mut p = ts::take_shared<Proposal<ConfigureAutojoin>>(scenario);
        p.vote(true, clock, scenario.ctx());
        ts::return_shared(p);
    };

    clock.set_for_testing(ts_exec);
    ts::next_tx(scenario, CREATOR);
    {
        let mut dao = ts::take_shared<DAO>(scenario);
        let mut p = ts::take_shared<Proposal<ConfigureAutojoin>>(scenario);
        let freeze = ts::take_shared<EmergencyFreeze>(scenario);
        let req = board_voting::ticket_from_vote(
            &mut dao,
            &mut p,
            &freeze,
            clock,
            scenario.ctx(),
        );
        configure_autojoin::execute_configure_autojoin(&mut dao, req);
        ts::return_shared(freeze);
        ts::return_shared(p);
        ts::return_shared(dao);
    };
}

/// Run a complete submit_autojoin + execute_autojoin_dao for the given
/// character. Production code runs both in the same PTB, and since
/// ExecutionTicket is a hot potato we do both in a single test transaction.
fun do_autojoin(
    scenario: &mut ts::Scenario,
    clock: &clock::Clock,
    cap_id: ID,
    character_id: ID,
    sender: address,
) {
    ts::next_tx(scenario, sender);
    {
        let mut dao = ts::take_shared<DAO>(scenario);
        let vault = ts::take_shared<CapabilityVault>(scenario);
        let character = ts::take_shared_by_id<Character>(scenario, character_id);
        let freeze = ts::take_shared<EmergencyFreeze>(scenario);

        let ticket = autojoin_ops::submit_autojoin(
            &mut dao,
            &vault,
            cap_id,
            &character,
            &freeze,
            clock,
            scenario.ctx(),
        );
        autojoin_ops::execute_autojoin_dao(&mut dao, ticket);

        ts::return_shared(freeze);
        ts::return_shared(character);
        ts::return_shared(vault);
        ts::return_shared(dao);
    };
}

// === Tests ===

#[test]
/// Happy path: setup, configure tribe 42, character with tribe 42 joins.
fun autojoin_happy_path() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 42, PLAYER);
    let (_dao_id, _vault_id, cap_id) = setup_dao_with_autojoin(&mut scenario);
    configure_allowlist(&mut scenario, &mut clock, vector[42], true, 1000, 2000, 3000);

    clock.set_for_testing(4000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, PLAYER);

    ts::next_tx(&mut scenario, CREATOR);
    {
        let dao = ts::take_shared<DAO>(&scenario);
        let gov = dao.governance();
        assert!(gov.is_board_member(PLAYER));
        ts::return_shared(dao);
    };

    clock.destroy_for_testing();
    ts::end(scenario);
}

#[test, expected_failure(abort_code = armature::governance::EDuplicateBoardMember)]
/// Double-join: player joins once, then attempts again in a later PTB.
/// add_board_member_governance aborts on duplicate.
fun autojoin_double_join_aborts() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 42, PLAYER);
    let (_, _, cap_id) = setup_dao_with_autojoin(&mut scenario);
    configure_allowlist(&mut scenario, &mut clock, vector[42], true, 1000, 2000, 3000);

    clock.set_for_testing(4000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, PLAYER);

    clock.set_for_testing(5000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, PLAYER);

    clock.destroy_for_testing();
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = armature_world_bridge::autojoin_ops::ESenderNotCharacterOwner,
    ),
]
/// Sender wallet doesn't match character.character_address — abort.
fun autojoin_wrong_sender_aborts() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 42, PLAYER);
    let (_, _, cap_id) = setup_dao_with_autojoin(&mut scenario);
    configure_allowlist(&mut scenario, &mut clock, vector[42], true, 1000, 2000, 3000);

    // Submit as a different sender than the character's wallet.
    clock.set_for_testing(4000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, @0xDEAD);

    clock.destroy_for_testing();
    ts::end(scenario);
}

#[test, expected_failure(abort_code = armature_world_bridge::autojoin_ops::ETribeIdNotAllowed)]
/// Character's tribe is not in the allowlist — abort.
fun autojoin_tribe_not_allowed_aborts() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 999, PLAYER); // tribe 999
    let (_, _, cap_id) = setup_dao_with_autojoin(&mut scenario);
    configure_allowlist(&mut scenario, &mut clock, vector[42], true, 1000, 2000, 3000);

    clock.set_for_testing(4000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, PLAYER);

    clock.destroy_for_testing();
    ts::end(scenario);
}

#[test, expected_failure(abort_code = armature_world_bridge::autojoin_ops::EAutojoinDisabled)]
/// Kill-switch off: even with the tribe whitelisted, submit aborts.
fun autojoin_kill_switch_off_aborts() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 42, PLAYER);
    let (_, _, cap_id) = setup_dao_with_autojoin(&mut scenario);
    // enabled = false
    configure_allowlist(&mut scenario, &mut clock, vector[42], false, 1000, 2000, 3000);

    clock.set_for_testing(4000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, PLAYER);

    clock.destroy_for_testing();
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = armature_world_bridge::autojoin_ops::EAllowlistNotInitialized,
    ),
]
/// Allowlist type-state never initialised (ConfigureAutojoin never ran) — abort.
fun autojoin_uninitialized_allowlist_aborts() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let character_id = create_character(&mut scenario, 100, 42, PLAYER);
    let (_, _, cap_id) = setup_dao_with_autojoin(&mut scenario);
    // NOTE: deliberately not calling configure_allowlist.

    clock.set_for_testing(1000);
    do_autojoin(&mut scenario, &clock, cap_id, character_id, PLAYER);

    clock.destroy_for_testing();
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = armature_world_bridge::configure_autojoin::EZeroTribeIdNotAllowed,
    ),
]
/// ConfigureAutojoin rejects 0 in adds (config-time guard).
fun configure_rejects_zero_tribe_id() {
    let mut scenario = ts::begin(GOVERNOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    setup_world(&mut scenario);
    let _character_id = create_character(&mut scenario, 100, 42, PLAYER);
    let (_, _, _cap_id) = setup_dao_with_autojoin(&mut scenario);
    configure_allowlist(&mut scenario, &mut clock, vector[42, 0], true, 1000, 2000, 3000);

    clock.destroy_for_testing();
    ts::end(scenario);
}
