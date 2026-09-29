#[test_only]
/// The emergency freeze is keyed by the payload's Move type, so freezing one
/// instantiation of a generic payload blocks it on every execution path
/// (atomic, bypass, two-PTB) while other instantiations stay executable.
module armature::freeze_path_tests;

use armature::board_voting;
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::external_execution;
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal::{Self, Proposal};
use std::internal;
use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self, Scenario};

const CREATOR: address = @0xA;

/// Generic payload standing in for e.g. `PlaceLimitOrder<CRED>`.
public struct Order<phantom T> has drop, store {}
public struct CredA has drop {}
public struct CredB has drop {}

// === Helpers ===

/// Single-member OU with `Order<CredA>` and `Order<CredB>` enabled (no delay,
/// no cooldown, so one YES passes and the atomic path is allowed), and
/// `Order<CredA>` frozen.
fun setup(scenario: &mut Scenario, clock: &mut Clock) {
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

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<Order<CredA>>(b"OrderA".to_ascii_string(), config);
        ou.test_enable_type<Order<CredB>>(b"OrderB".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    clock.set_for_testing(1_000);
    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        freeze.freeze_type<Order<CredA>>(&cap, clock);
        assert!(freeze.is_frozen<Order<CredA>>(clock));
        assert!(!freeze.is_frozen<Order<CredB>>(clock));
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };
}

fun run_atomic<T>(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let ticket = board_voting::submit_vote_execute<Order<T>>(
        &mut ou,
        option::none(),
        Order<T> {},
        &freeze,
        clock,
        scenario.ctx(),
    );
    ticket.discharge(internal::permit());
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ou);
}

fun run_bypass<T>(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let cap = proposal::new_external_execution_cap_for_testing<Order<T>>(ou.id(), scenario.ctx());
    let ticket = external_execution::ticket_from_cap<Order<T>>(
        &cap,
        &mut ou,
        &freeze,
        option::none(),
        Order<T> {},
        internal::permit(),
        clock,
        scenario.ctx(),
    );
    ticket.discharge(internal::permit());
    proposal::destroy_external_execution_cap_for_testing(cap);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ou);
}

/// Submit and pass a two-PTB proposal, then execute it in a later transaction.
fun run_two_ptb<T>(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        board_voting::submit_proposal(&ou, option::none(), Order<T> {}, clock, scenario.ctx());
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<Order<T>>>();
        let ou = scenario.take_shared_by_id<OU>(prop.ou_id());
        board_voting::vote(&mut prop, &ou, true, clock, scenario.ctx());
        test_scenario::return_shared(ou);
        test_scenario::return_shared(prop);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let prop = scenario.take_shared<Proposal<Order<T>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, clock, scenario.ctx());
        ticket.discharge(internal::permit());
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };
}

// === Atomic (submit_vote_execute) ===

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun atomic__frozen_instantiation_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    run_atomic<CredA>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun atomic__other_instantiation_unaffected() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    run_atomic<CredB>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

// === Bypass (ticket_from_cap) ===

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun bypass__frozen_instantiation_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    run_bypass<CredA>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun bypass__other_instantiation_unaffected() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    run_bypass<CredB>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

// === Two-PTB (ticket_from_vote) ===

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun two_ptb__frozen_instantiation_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    run_two_ptb<CredA>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
fun two_ptb__other_instantiation_unaffected() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    run_two_ptb<CredB>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// A two-PTB proposal frozen while pending executes once the admin unfreezes it.
fun two_ptb__executes_after_unfreeze() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);

    scenario.next_tx(CREATOR);
    {
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        freeze.unfreeze_type<Order<CredA>>(&cap);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(freeze);
    };

    run_two_ptb<CredA>(&mut scenario, &clock);

    clock.destroy_for_testing();
    scenario.end();
}
