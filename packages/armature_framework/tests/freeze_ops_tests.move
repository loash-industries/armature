/// UpdateFreezeConfig and UpdateFreezeExemptTypes: framework freeze-governance
/// types executed through `freeze_ops`. Moved from armature_proposals when the
/// types became framework types (fixed FREEZE bits).
#[test_only]
module armature::freeze_ops_tests;

use armature::board_voting;
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::freeze_ops;
use armature::governance;
use armature::ou::{Self, OU};
use armature::permissions;
use armature::proposal::{Self, Proposal};
use armature::set_board::SetBoard;
use armature::transfer_freeze_admin::TransferFreezeAdmin;
use armature::update_freeze_config::{Self, UpdateFreezeConfig};
use armature::update_freeze_exempt_types::{Self, UpdateFreezeExemptTypes};
use std::string;
use std::type_name;
use sui::clock;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;

// === Helpers ===

fun create_ou(scenario: &mut test_scenario::Scenario): ID {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR, MEMBER_B]);
    ou::create(
        &init,
        string::utf8(b"Test OU"),
        string::utf8(b"https://example.com/logo.png"),
        scenario.ctx(),
    )
}

/// Enable `T` with a plain config. Framework types get their fixed bits from
/// the OU regardless of what the config carries.
fun enable_type<T>(scenario: &mut test_scenario::Scenario, key: vector<u8>) {
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<T>(key.to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };
}

fun submit_exempt_types(
    scenario: &mut test_scenario::Scenario,
    clock: &mut clock::Clock,
    payload: UpdateFreezeExemptTypes,
    ts: u64,
) {
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(ts);
        board_voting::submit_proposal(&ou, option::none(), payload, clock, scenario.ctx());
        test_scenario::return_shared(ou);
    };
    scenario.next_tx(CREATOR);
    {
        let mut p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        clock.set_for_testing(ts + 1000);
        let vote_ou = scenario.take_shared_by_id<OU>(p.ou_id());
        board_voting::vote(&mut p, &vote_ou, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(p);
    };
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let p = scenario.take_shared<Proposal<UpdateFreezeExemptTypes>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(ts + 2000);
        let ticket = board_voting::ticket_from_vote(&mut ou, p, &freeze, clock, scenario.ctx());
        freeze_ops::execute_update_freeze_exempt_types(&mut freeze, ticket);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };
}

// === Fixed bits ===

#[test]
/// Both types are framework types holding exactly FREEZE, whatever config
/// enables them.
fun freeze_governance_types_hold_fixed_freeze_bit() {
    let cfg = type_name::with_defining_ids<UpdateFreezeConfig>();
    let exempt = type_name::with_defining_ids<UpdateFreezeExemptTypes>();
    assert!(ou::is_framework_type(&cfg));
    assert!(ou::is_framework_type(&exempt));
    assert!(ou::framework_permissions(&cfg) == permissions::emergency_freeze());
    assert!(ou::framework_permissions(&exempt) == permissions::emergency_freeze());

    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    enable_type<UpdateFreezeConfig>(&mut scenario, b"UpdateFreezeConfig");
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.type_config_by_name(&cfg).permissions() == permissions::emergency_freeze());
        test_scenario::return_shared(ou);
    };
    scenario.end();
}

// === UpdateFreezeConfig ===

#[test]
/// E2E: Submit UpdateFreezeConfig → vote → execute → verify duration changed.
fun update_freeze_config_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    enable_type<UpdateFreezeConfig>(&mut scenario, b"UpdateFreezeConfig");

    // Default max freeze duration is 7 days.
    scenario.next_tx(CREATOR);
    {
        let freeze = scenario.take_shared<EmergencyFreeze>();
        assert!(freeze.max_freeze_duration_ms() == 604_800_000);
        test_scenario::return_shared(freeze);
    };

    let new_duration: u64 = 259_200_000; // 3 days

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = update_freeze_config::new(new_duration);
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Reduce freeze duration")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<UpdateFreezeConfig>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let proposal = scenario.take_shared<Proposal<UpdateFreezeConfig>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);
        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        freeze_ops::execute_update_freeze_config(&mut freeze, ticket);
        assert!(freeze.max_freeze_duration_ms() == new_duration);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    // The new duration bounds an admin freeze.
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        clock.set_for_testing(10000);
        freeze.freeze_type<SetBoard>(&cap, &clock);
        assert!(freeze.is_frozen<SetBoard>(&clock));
        clock.set_for_testing(259_210_001);
        assert!(!freeze.is_frozen<SetBoard>(&clock));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === UpdateFreezeExemptTypes ===

#[test]
/// E2E: Add a custom exempt type → verify it is exempt.
fun add_freeze_exempt_type_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    enable_type<UpdateFreezeExemptTypes>(&mut scenario, b"UpdateFreezeExemptTypes");

    let mut payload = update_freeze_exempt_types::new();
    payload.add_type<SetBoard>();
    submit_exempt_types(&mut scenario, &mut clock, payload, 1000);

    scenario.next_tx(CREATOR);
    {
        let freeze = scenario.take_shared<EmergencyFreeze>();
        assert!(freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// E2E: Remove a non-mandatory exempt type → verify it can be frozen again.
fun remove_freeze_exempt_type_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    enable_type<UpdateFreezeExemptTypes>(&mut scenario, b"UpdateFreezeExemptTypes");

    let mut add = update_freeze_exempt_types::new();
    add.add_type<SetBoard>();
    submit_exempt_types(&mut scenario, &mut clock, add, 1000);

    scenario.next_tx(CREATOR);
    {
        let freeze = scenario.take_shared<EmergencyFreeze>();
        assert!(freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));
        test_scenario::return_shared(freeze);
    };

    let mut remove = update_freeze_exempt_types::new();
    remove.remove_type<SetBoard>();
    submit_exempt_types(&mut scenario, &mut clock, remove, 4000);

    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        assert!(!freeze.is_exempt_by_name(&type_name::with_defining_ids<SetBoard>()));
        clock.set_for_testing(7000);
        freeze.freeze_type<SetBoard>(&cap, &clock);
        assert!(freeze.is_frozen<SetBoard>(&clock));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = emergency::EMandatoryExemptType)]
/// Cannot remove a mandatory exempt type (TransferFreezeAdmin) from the set.
fun remove_mandatory_exempt_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_ou(&mut scenario);
    enable_type<UpdateFreezeExemptTypes>(&mut scenario, b"UpdateFreezeExemptTypes");

    let mut payload = update_freeze_exempt_types::new();
    payload.remove_type<TransferFreezeAdmin>();
    submit_exempt_types(&mut scenario, &mut clock, payload, 1000);

    clock.destroy_for_testing();
    scenario.end();
}
