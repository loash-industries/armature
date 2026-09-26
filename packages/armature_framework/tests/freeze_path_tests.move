#[test_only]
/// The emergency freeze is keyed by the payload's Move type, so freezing one
/// instantiation of a generic payload blocks it on every execution path
/// (atomic, bypass, two-PTB) while other instantiations stay executable.
module armature::freeze_path_tests;

use armature::board_voting;
use armature::dao::{Self, DAO};
use armature::emergency::{Self, EmergencyFreeze, FreezeAdminCap};
use armature::external_execution;
use armature::governance;
use armature::proposal::{Self, Proposal};
use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self, Scenario};

const CREATOR: address = @0xA;

/// Generic payload standing in for e.g. `PlaceLimitOrder<CRED>`.
public struct Order<phantom T> has drop, store {}
public struct CredA has drop {}
public struct CredB has drop {}

// === Helpers ===

/// Single-member DAO with `Order<CredA>` and `Order<CredB>` enabled (no delay,
/// no cooldown, so one YES passes and the atomic path is allowed), and
/// `Order<CredA>` frozen.
fun setup(scenario: &mut Scenario, clock: &mut Clock) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type<Order<CredA>>(b"OrderA".to_ascii_string(), config);
        dao.test_enable_type<Order<CredB>>(b"OrderB".to_ascii_string(), config);
        test_scenario::return_shared(dao);
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
    let mut dao = scenario.take_shared<DAO>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let ticket = board_voting::submit_vote_execute<Order<T>>(
        &mut dao,
        option::none(),
        Order<T> {},
        &freeze,
        clock,
        scenario.ctx(),
    );
    ticket.discharge();
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(dao);
}

fun run_bypass<T>(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    let mut dao = scenario.take_shared<DAO>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let cap = proposal::new_external_execution_cap_for_testing<Order<T>>(dao.id(), scenario.ctx());
    let ticket = external_execution::ticket_from_cap<Order<T>>(
        &cap,
        &mut dao,
        &freeze,
        option::none(),
        Order<T> {},
        clock,
        scenario.ctx(),
    );
    ticket.discharge();
    proposal::destroy_external_execution_cap_for_testing(cap);
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(dao);
}

/// Submit and pass a two-PTB proposal, then execute it in a later transaction.
fun run_two_ptb<T>(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        board_voting::submit_proposal(&dao, option::none(), Order<T> {}, clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<Order<T>>>();
        let dao = scenario.take_shared_by_id<DAO>(prop.dao_id());
        board_voting::vote(&mut prop, &dao, true, clock, scenario.ctx());
        test_scenario::return_shared(dao);
        test_scenario::return_shared(prop);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let prop = scenario.take_shared<Proposal<Order<T>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, clock, scenario.ctx());
        ticket.discharge();
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
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
