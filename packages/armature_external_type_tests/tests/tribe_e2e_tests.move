/// End-to-end tribe flow on `armature_proposals::tribe_setup`, with
/// three-member boards so every "one-click" step is one member acting alone
/// through `board_voting::submit_vote_execute`. Registering a new type is not
/// one-click: EnableProposalType needs YES from 80% of the whole board.
/// `Rebalance<T>` stands in for a third-party trading type. No test seams
/// touch any OU's registry.
#[test_only]
module armature_external_type_tests::tribe_e2e_tests;

use armature::admin_ops;
use armature::batch_add_members;
use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::emergency::EmergencyFreeze;
use armature::enable_proposal_type::{Self, EnableProposalType};
use armature::ou::OU;
use armature::proposal::{Self, Proposal};
use armature::update_proposal_config;
use armature_external_type_tests::rebalance::{Self, Rebalance};
use armature_proposals::controller_batch_add_members::{Self, ControllerBatchAddMembers};
use armature_proposals::controller_batch_remove_members::{Self, ControllerBatchRemoveMembers};
use armature_proposals::pause_execution::{Self, PauseSubOUExecution, UnpauseSubOUExecution};
use armature_proposals::send_coin::SendCoin;
use armature_proposals::subou_ops;
use armature_proposals::tribe_setup;
use armature_proposals::type_permissions;
use std::string;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

const OWNER_A: address = @0xA1;
const OWNER_B: address = @0xA2;
const OWNER_C: address = @0xA3;
const OFFICER_A: address = @0xB1;
const OFFICER_B: address = @0xB2;
const OFFICER_C: address = @0xB3;
const MEMBER_A: address = @0xC1;
const MEMBER_B: address = @0xC2;
const MEMBER_C: address = @0xC3;
const NEW_OFFICER: address = @0xD1;
const NEW_MEMBER: address = @0xD2;
const OFFICER_FREEZE_ADMIN: address = @0xE1;
const MEMBER_FREEZE_ADMIN: address = @0xE2;

public struct Tribe has drop {
    tribe_id: ID,
    officer_id: ID,
    member_id: ID,
}

// === Setup ===

fun begin(): (Scenario, Clock, Tribe) {
    let mut scenario = ts::begin(OWNER_A);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);
    scenario.next_tx(OWNER_A);
    let (tribe_id, officer_id, member_id) = tribe_setup::create_tribe(
        vector[OWNER_A, OWNER_B, OWNER_C],
        vector[OFFICER_A, OFFICER_B, OFFICER_C],
        vector[MEMBER_A, MEMBER_B, MEMBER_C],
        string::utf8(b"Tribe"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"ipfs://tribe"),
        string::utf8(b"ipfs://officers"),
        string::utf8(b"ipfs://members"),
        OFFICER_FREEZE_ADMIN,
        MEMBER_FREEZE_ADMIN,
        scenario.ctx(),
    );
    (scenario, clock, Tribe { tribe_id, officer_id, member_id })
}

fun end(scenario: Scenario, clock: Clock) {
    clock.destroy_for_testing();
    scenario.end();
}

fun tick(clock: &mut Clock) {
    let now = clock.timestamp_ms();
    clock.set_for_testing(now + 1_000);
}

// === One-click steps ===

/// `sender` alone adds `members` to `subou_id` through `controller_id`'s control.
fun one_click_add(
    scenario: &mut Scenario,
    clock: &mut Clock,
    sender: address,
    controller_id: ID,
    subou_id: ID,
    members: vector<address>,
) {
    tick(clock);
    scenario.next_tx(sender);
    let mut controller = scenario.take_shared_by_id<OU>(controller_id);
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(controller.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(controller.emergency_freeze_id());
    let mut subou = scenario.take_shared_by_id<OU>(subou_id);
    let control_id = vault.ids_for_type<SubOUControl>()[0];

    let ticket = board_voting::submit_vote_execute<ControllerBatchAddMembers>(
        &mut controller,
        option::none(),
        controller_batch_add_members::new(control_id, members),
        &freeze,
        clock,
        scenario.ctx(),
    );
    subou_ops::execute_controller_batch_add_members(&mut vault, &mut subou, ticket, scenario.ctx());

    ts::return_shared(subou);
    ts::return_shared(freeze);
    ts::return_shared(vault);
    ts::return_shared(controller);
}

/// `sender` alone removes `members` from `subou_id` through `controller_id`'s control.
fun one_click_remove(
    scenario: &mut Scenario,
    clock: &mut Clock,
    sender: address,
    controller_id: ID,
    subou_id: ID,
    members: vector<address>,
) {
    tick(clock);
    scenario.next_tx(sender);
    let mut controller = scenario.take_shared_by_id<OU>(controller_id);
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(controller.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(controller.emergency_freeze_id());
    let mut subou = scenario.take_shared_by_id<OU>(subou_id);
    let control_id = vault.ids_for_type<SubOUControl>()[0];

    let ticket = board_voting::submit_vote_execute<ControllerBatchRemoveMembers>(
        &mut controller,
        option::none(),
        controller_batch_remove_members::new(control_id, members),
        &freeze,
        clock,
        scenario.ctx(),
    );
    subou_ops::execute_controller_batch_remove_members(
        &mut vault,
        &mut subou,
        ticket,
        scenario.ctx(),
    );

    ts::return_shared(subou);
    ts::return_shared(freeze);
    ts::return_shared(vault);
    ts::return_shared(controller);
}

/// `sender` alone pauses execution on the Members SubOU.
fun one_click_pause_members(
    scenario: &mut Scenario,
    clock: &mut Clock,
    sender: address,
    t: &Tribe,
) {
    tick(clock);
    scenario.next_tx(sender);
    let mut officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let mut vault = scenario.take_shared_by_id<CapabilityVault>(officers.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let mut members = scenario.take_shared_by_id<OU>(t.member_id);
    let control_id = vault.ids_for_type<SubOUControl>()[0];

    let ticket = board_voting::submit_vote_execute<PauseSubOUExecution>(
        &mut officers,
        option::none(),
        pause_execution::new_pause(control_id),
        &freeze,
        clock,
        scenario.ctx(),
    );
    subou_ops::execute_pause_subou_execution(&mut vault, &mut members, ticket, scenario.ctx());

    ts::return_shared(members);
    ts::return_shared(freeze);
    ts::return_shared(vault);
    ts::return_shared(officers);
}

/// EnableProposalType payload registering `Rebalance<SUI>` as a single-vote type.
fun enable_trading_payload(): EnableProposalType {
    enable_proposal_type::new(
        b"Rebalance".to_ascii_string(),
        type_name::with_defining_ids<Rebalance<SUI>>(),
        proposal::new_config(1, 5_000, 0, 3_600_000, 0, 0),
    )
}

/// `sender` proposes registering `Rebalance<SUI>` on the Officers SubOU.
fun propose_enable_trading(scenario: &mut Scenario, clock: &mut Clock, sender: address, t: &Tribe) {
    tick(clock);
    scenario.next_tx(sender);
    let officers = scenario.take_shared_by_id<OU>(t.officer_id);
    board_voting::submit_proposal(
        &officers,
        option::none(),
        enable_trading_payload(),
        clock,
        scenario.ctx(),
    );
    ts::return_shared(officers);
}

/// `voter` votes YES on the open EnableProposalType proposal.
fun vote_yes_on_enable(scenario: &mut Scenario, clock: &mut Clock, voter: address, t: &Tribe) {
    tick(clock);
    scenario.next_tx(voter);
    let mut prop = scenario.take_shared<Proposal<EnableProposalType>>();
    let officers = scenario.take_shared_by_id<OU>(t.officer_id);
    board_voting::vote(&mut prop, &officers, true, clock, scenario.ctx());
    ts::return_shared(officers);
    ts::return_shared(prop);
}

/// `sender` executes the EnableProposalType proposal.
fun execute_enable_trading(scenario: &mut Scenario, clock: &mut Clock, sender: address, t: &Tribe) {
    tick(clock);
    scenario.next_tx(sender);
    let mut officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let prop = scenario.take_shared<Proposal<EnableProposalType>>();
    let ticket = board_voting::ticket_from_vote(
        &mut officers,
        prop,
        &freeze,
        clock,
        scenario.ctx(),
    );
    admin_ops::execute_enable_proposal_type<Rebalance<SUI>>(&mut officers, ticket);
    ts::return_shared(freeze);
    ts::return_shared(officers);
}

/// `sender` alone executes a `Rebalance<SUI>` on the Officers SubOU.
fun one_click_trade(scenario: &mut Scenario, clock: &mut Clock, sender: address, t: &Tribe) {
    tick(clock);
    scenario.next_tx(sender);
    let officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());

    let ticket = board_voting::submit_vote_execute_readonly(
        &officers,
        option::none(),
        rebalance::new<SUI>(100),
        &freeze,
        clock,
        scenario.ctx(),
    );
    rebalance::execute_rebalance(&officers, ticket);

    ts::return_shared(freeze);
    ts::return_shared(officers);
}

// === Tests ===

#[test]
/// The whole tribe lifecycle, each step by a single board member:
/// owner seats an officer; officers add and remove members, pause the Members
/// SubOU, and trade. Registering the trading type takes the whole Officers
/// board.
fun tribe_full_lifecycle_one_click() {
    let (mut scenario, mut clock, t) = begin();

    // Owners: one owner seats a new officer.
    one_click_add(
        &mut scenario,
        &mut clock,
        OWNER_A,
        t.tribe_id,
        t.officer_id,
        vector[NEW_OFFICER],
    );

    // Officers: the new officer adds a member, another removes one.
    one_click_add(
        &mut scenario,
        &mut clock,
        NEW_OFFICER,
        t.officer_id,
        t.member_id,
        vector[NEW_MEMBER],
    );
    one_click_remove(
        &mut scenario,
        &mut clock,
        OFFICER_B,
        t.officer_id,
        t.member_id,
        vector[MEMBER_C],
    );

    scenario.next_tx(OWNER_A);
    {
        let officers = scenario.take_shared_by_id<OU>(t.officer_id);
        let members = scenario.take_shared_by_id<OU>(t.member_id);
        assert!(officers.governance().is_board_member(NEW_OFFICER));
        assert!(members.governance().is_board_member(NEW_MEMBER));
        assert!(!members.governance().is_board_member(MEMBER_C));
        assert!(members.governance().is_board_member(MEMBER_A));
        ts::return_shared(members);
        ts::return_shared(officers);
    };

    // Officers: registering a trading type needs YES from 80% of the four
    // officers, so all four vote; then any one officer trades in one click.
    propose_enable_trading(&mut scenario, &mut clock, OFFICER_A, &t);
    vote_yes_on_enable(&mut scenario, &mut clock, OFFICER_A, &t);
    vote_yes_on_enable(&mut scenario, &mut clock, OFFICER_B, &t);
    vote_yes_on_enable(&mut scenario, &mut clock, OFFICER_C, &t);
    vote_yes_on_enable(&mut scenario, &mut clock, NEW_OFFICER, &t);
    execute_enable_trading(&mut scenario, &mut clock, OFFICER_A, &t);
    one_click_trade(&mut scenario, &mut clock, OFFICER_C, &t);

    scenario.next_tx(OWNER_A);
    {
        let officers = scenario.take_shared_by_id<OU>(t.officer_id);
        assert!(officers.is_type_enabled<Rebalance<SUI>>());
        ts::return_shared(officers);
    };

    // Officers: one officer pauses the Members SubOU.
    one_click_pause_members(&mut scenario, &mut clock, OFFICER_A, &t);

    scenario.next_tx(OWNER_A);
    {
        let members = scenario.take_shared_by_id<OU>(t.member_id);
        assert!(members.is_controller_paused());
        ts::return_shared(members);
    };

    end(scenario, clock);
}

#[test, expected_failure(abort_code = board_voting::EInsufficientVotingWeight)]
/// Unpausing needs officer consensus: one officer cannot reverse a pause.
fun single_officer_cannot_unpause_members() {
    let (mut scenario, mut clock, t) = begin();
    one_click_pause_members(&mut scenario, &mut clock, OFFICER_A, &t);

    tick(&mut clock);
    scenario.next_tx(OFFICER_B);
    let mut officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let vault = scenario.take_shared_by_id<CapabilityVault>(officers.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let control_id = vault.ids_for_type<SubOUControl>()[0];
    let _ticket = board_voting::submit_vote_execute<UnpauseSubOUExecution>(
        &mut officers,
        option::none(),
        pause_execution::new_unpause(control_id),
        &freeze,
        &clock,
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = board_voting::EInsufficientVotingWeight)]
/// Changing the Officers board itself needs officer consensus: one officer
/// cannot add another officer.
fun single_officer_cannot_add_officer() {
    let (mut scenario, mut clock, t) = begin();

    tick(&mut clock);
    scenario.next_tx(OFFICER_A);
    let mut officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let _ticket = board_voting::submit_vote_execute(
        &mut officers,
        option::none(),
        batch_add_members::new(vector[NEW_OFFICER]),
        &freeze,
        &clock,
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = board_voting::ETypeNotEnabled)]
/// A trading type is not usable until an officer registers it.
fun trade_before_enable_aborts() {
    let (mut scenario, mut clock, t) = begin();
    one_click_trade(&mut scenario, &mut clock, OFFICER_A, &t);
    end(scenario, clock);
}

#[test, expected_failure(abort_code = board_voting::EInsufficientVotingWeight)]
/// One officer cannot enable a type in one click, even one that withdraws
/// from the treasury: EnableProposalType needs YES from 80% of the whole board.
fun single_officer_cannot_enable_treasury_type() {
    let (mut scenario, mut clock, t) = begin();

    tick(&mut clock);
    scenario.next_tx(OFFICER_A);
    let mut officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let _ticket = board_voting::submit_vote_execute<EnableProposalType>(
        &mut officers,
        option::none(),
        enable_proposal_type::new(
            b"SendCoin<SUI>".to_ascii_string(),
            type_name::with_defining_ids<SendCoin<SUI>>(),
            proposal::new_config(1, 8_000, 0, 3_600_000, 0, 0).with_permissions(
                type_permissions::treasury_spend(),
            ),
        ),
        &freeze,
        &clock,
        scenario.ctx(),
    );
    abort 0
}

#[test, expected_failure(abort_code = proposal::ENotPassed)]
/// Two of three officers (67%) are below the 80% whole-board floor: the
/// proposal does not pass and cannot be executed.
fun two_of_three_officers_cannot_enable_type() {
    let (mut scenario, mut clock, t) = begin();
    propose_enable_trading(&mut scenario, &mut clock, OFFICER_A, &t);
    vote_yes_on_enable(&mut scenario, &mut clock, OFFICER_A, &t);
    vote_yes_on_enable(&mut scenario, &mut clock, OFFICER_B, &t);
    execute_enable_trading(&mut scenario, &mut clock, OFFICER_A, &t);
    end(scenario, clock);
}

#[test, expected_failure(abort_code = board_voting::EInsufficientVotingWeight)]
/// One officer cannot rewrite a type's config in one click (here: drop the
/// quorum of UnpauseSubOUExecution to 1 bps): UpdateProposalConfig needs YES
/// from 80% of the whole board.
fun single_officer_cannot_update_proposal_config() {
    let (mut scenario, mut clock, t) = begin();

    tick(&mut clock);
    scenario.next_tx(OFFICER_A);
    let mut officers = scenario.take_shared_by_id<OU>(t.officer_id);
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(officers.emergency_freeze_id());
    let _ticket = board_voting::submit_vote_execute(
        &mut officers,
        option::none(),
        update_proposal_config::new(
            b"UnpauseSubOUExecution".to_ascii_string(),
            option::some(1),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::none(),
        ),
        &freeze,
        &clock,
        scenario.ctx(),
    );
    abort 0
}
