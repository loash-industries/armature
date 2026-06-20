#[test_only]
module armature_proposals::composite_tests;

use armature::board_voting;
use armature::charter::Charter;
use armature::composite::{Self, CompositeFrame, CompositePayload};
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::add_member::{Self, AddMember};
use armature_proposals::admin_ops;
use armature_proposals::batch_add_members::{Self, BatchAddMembers};
use armature_proposals::board_ops;
use armature_proposals::enable_proposal_type::{Self, EnableProposalType};
use armature_proposals::member_ops;
use armature_proposals::remove_member::{Self, RemoveMember};
use armature_proposals::send_coin::{Self, SendCoin};
use armature_proposals::send_coin_to_dao::{Self, SendCoinToDAO};
use armature_proposals::set_board::{Self, SetBoard};
use armature_proposals::treasury_ops;
use armature_proposals::update_metadata::{Self, UpdateMetadata};
use std::string;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

/// Placeholder payload type for type-binding tests (e.g., enable_proposal_type_step).
public struct TestPayload has drop, store { _dummy: u64 }

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const MEMBER_C: address = @0xC;
const MEMBER_D: address = @0xD;
const RECIPIENT: address = @0xF;

// === Helpers ===

fun create_dao_two_members(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Disable composability for a given type_key on the DAO using the test helper.
/// Used to test the ENotComposable rejection path for types that are composable by opt-in.
fun disable_composable(scenario: &mut test_scenario::Scenario, type_key: vector<u8>) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let existing = *dao.proposal_configs().get(&type_key.to_ascii_string());
        let updated = existing.with_composable_allowed(false);
        dao.test_update_config(type_key.to_ascii_string(), updated);
        test_scenario::return_shared(dao);
    };
}

// === Tests ===

#[test]
/// End-to-end: composite with two AddMember steps adds both members in one vote.
fun composite_two_add_member_steps_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Build and submit composite frame with two AddMember steps.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_D),
        );

        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());

        test_scenario::return_shared(dao);
    };

    // CREATOR votes yes — with 2 members the default 50% quorum is met by 1 vote.
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute composite: authorize → begin_pipeline → advance step 0 → advance step 1 → finalize.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        // Step 0: AddMember(MEMBER_C)
        let (payload_c_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_c_ticket);

        // Step 1: AddMember(MEMBER_D)
        let (payload_d_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_d_ticket);

        composite::finalize_pipeline(pipeline);

        // Both members are now on the board
        assert!(dao.governance().is_board_member(CREATOR));
        assert!(dao.governance().is_board_member(MEMBER_B));
        assert!(dao.governance().is_board_member(MEMBER_C));
        assert!(dao.governance().is_board_member(MEMBER_D));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Composite with AddMember + RemoveMember steps executes both actions atomically.
fun composite_add_then_remove_member_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Frame: add MEMBER_C, then remove MEMBER_B (swap out a board member).
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::add_step<RemoveMember>(
            &mut frame,
            &dao,
            b"RemoveMember".to_ascii_string(),
            remove_member::new(MEMBER_B),
        );

        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());

        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_add_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_add_ticket);

        let (payload_remove_ticket, pipeline) = composite::advance_step<RemoveMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_remove_member(&mut dao, payload_remove_ticket);

        composite::finalize_pipeline(pipeline);

        assert!(dao.governance().is_board_member(CREATOR));
        assert!(!dao.governance().is_board_member(MEMBER_B));
        assert!(dao.governance().is_board_member(MEMBER_C));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = composite::ENotComposable)]
/// add_step aborts when the type does not have composable_allowed = true.
fun add_step_rejects_non_composable_type() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_dao_two_members(&mut scenario);
    disable_composable(&mut scenario, b"AddMember");

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        // This should abort with ENotComposable.
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        transfer::public_share_object(frame);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = composite::ECompositeNesting)]
/// add_step aborts when the type_key is "Composite" (self-nesting is blocked).
fun add_step_rejects_composite_nesting() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_dao_two_members(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        // AddMember payload used here is incidental; the abort is on type_key = "Composite".
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"Composite".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        transfer::public_share_object(frame);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = composite::EEmptyFrame)]
/// submit_composite aborts when the frame has no steps.
fun submit_composite_empty_frame_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let frame = composite::new_frame(dao.id(), scenario.ctx());
        // Frame has no steps — should abort.
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = composite::EPipelineIncomplete)]
/// finalize_pipeline aborts when not all steps have been advanced.
fun finalize_pipeline_incomplete_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_D),
        );

        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        // Only advance step 0 — skip step 1.
        let (payload_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_ticket);

        // finalize with step 1 remaining — should abort with EPipelineIncomplete.
        composite::finalize_pipeline(pipeline);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = composite::EStepTypeMismatch)]
/// advance_step aborts when the caller supplies the wrong type P for the step index.
fun advance_step_wrong_type_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Frame: step 0 = AddMember, but we will advance with RemoveMember<> type.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );

        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        // Step 0 is AddMember but we try to advance with RemoveMember — should abort.
        let (payload_ticket, pipeline) = composite::advance_step<RemoveMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_remove_member(&mut dao, payload_ticket);

        composite::finalize_pipeline(pipeline);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Composite with a single SendCoin step withdraws from treasury and delivers the coin.
fun composite_send_coin_step_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Create single-member DAO
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Treasury DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Enable SendCoin type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            604_800_000,
            0,
            0,
        ).with_composable_allowed(true);
        dao.test_enable_type(b"SendCoin".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Fund treasury
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        vault.deposit(coin::mint_for_testing<SUI>(1_000_000, scenario.ctx()), scenario.ctx());
        test_scenario::return_shared(vault);
    };

    // Submit composite: one SendCoin<SUI> step
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<SendCoin<SUI>>(
            &mut frame,
            &dao,
            b"SendCoin".to_ascii_string(),
            send_coin::new<SUI>(RECIPIENT, 200_000),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<SendCoin<SUI>>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        treasury_ops::execute_send_coin<SUI>(&mut vault, payload_ticket, scenario.ctx());

        composite::finalize_pipeline(pipeline);

        assert!(vault.balance<SUI>() == 800_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    // Recipient received the coin
    scenario.next_tx(RECIPIENT);
    {
        let c = scenario.take_from_sender<sui::coin::Coin<SUI>>();
        assert!(c.value() == 200_000);
        test_scenario::return_to_sender(&scenario, c);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Composite with a single SendCoinToDAO step moves funds between two DAO treasuries.
fun composite_send_coin_to_dao_step_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    let source_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        source_dao_id =
            dao::create(
                &init,
                string::utf8(b"Source DAO"),
                string::utf8(b"https://example.com/source.png"),
                scenario.ctx(),
            );
    };

    let target_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        target_dao_id =
            dao::create(
                &init,
                string::utf8(b"Target DAO"),
                string::utf8(b"https://example.com/target.png"),
                scenario.ctx(),
            );
    };

    let source_vault_id;
    let target_vault_id;
    let source_freeze_id;
    scenario.next_tx(CREATOR);
    {
        let source_dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let target_dao = scenario.take_shared_by_id<DAO>(target_dao_id);
        source_vault_id = source_dao.treasury_id();
        source_freeze_id = source_dao.emergency_freeze_id();
        target_vault_id = target_dao.treasury_id();
        test_scenario::return_shared(source_dao);
        test_scenario::return_shared(target_dao);
    };

    // Enable SendCoinToDAO on source DAO
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let config = proposal::new_config(
            5_000,
            5_000,
            0,
            604_800_000,
            0,
            0,
        ).with_composable_allowed(true);
        dao.test_enable_type(b"SendCoinToDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // Fund source treasury
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared_by_id<TreasuryVault>(source_vault_id);
        vault.deposit(coin::mint_for_testing<SUI>(1_000_000, scenario.ctx()), scenario.ctx());
        test_scenario::return_shared(vault);
    };

    // Submit composite: one SendCoinToDAO<SUI> step
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<SendCoinToDAO<SUI>>(
            &mut frame,
            &dao,
            b"SendCoinToDAO".to_ascii_string(),
            send_coin_to_dao::new<SUI>(target_vault_id, 300_000),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(source_dao_id);
        let mut source_vault = scenario.take_shared_by_id<TreasuryVault>(source_vault_id);
        let mut target_vault = scenario.take_shared_by_id<TreasuryVault>(target_vault_id);
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(source_freeze_id);
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<SendCoinToDAO<SUI>>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        treasury_ops::execute_send_coin_to_dao<SUI>(
            &mut source_vault,
            &mut target_vault,
            payload_ticket,
            scenario.ctx(),
        );

        composite::finalize_pipeline(pipeline);

        assert!(source_vault.balance<SUI>() == 700_000);
        assert!(target_vault.balance<SUI>() == 300_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(target_vault);
        test_scenario::return_shared(source_vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Composite with a single SetBoard step replaces the board atomically.
fun composite_set_board_step_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Submit composite: SetBoard → replace board with [MEMBER_C]
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<SetBoard>(
            &mut frame,
            &dao,
            b"SetBoard".to_ascii_string(),
            set_board::new(vector[MEMBER_C]),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<SetBoard>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        board_ops::execute_set_board(&mut dao, payload_ticket);

        composite::finalize_pipeline(pipeline);

        assert!(!dao.governance().is_board_member(CREATOR));
        assert!(!dao.governance().is_board_member(MEMBER_B));
        assert!(dao.governance().is_board_member(MEMBER_C));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Composite with a single UpdateMetadata step updates the DAO charter's IPFS CID.
fun composite_update_metadata_step_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    let charter_id;
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        charter_id = dao.charter_id();
        test_scenario::return_shared(dao);
    };

    // Submit composite: one UpdateMetadata step
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<UpdateMetadata>(
            &mut frame,
            &dao,
            b"CharterUpdate".to_ascii_string(),
            update_metadata::new(string::utf8(b"ipfs://QmCompositeTest")),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut charter = scenario.take_shared_by_id<Charter>(charter_id);
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<UpdateMetadata>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        admin_ops::execute_update_metadata(&mut charter, payload_ticket);

        composite::finalize_pipeline(pipeline);

        assert!(charter.metadata_uri() == &string::utf8(b"ipfs://QmCompositeTest"));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = composite::ENotComposable)]
/// add_step aborts for a governance-sensitive type that is deny-by-default non-composable.
/// BatchAddMembers is a default type with no _step handler, so composable_allowed = false
/// without any manual disable call — regression guard for the deny-by-default fix.
fun add_step_rejects_governance_sensitive_type_by_default() {
    let mut scenario = test_scenario::begin(CREATOR);

    create_dao_two_members(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<BatchAddMembers>(
            &mut frame,
            &dao,
            b"BatchAddMembers".to_ascii_string(),
            batch_add_members::new(vector[MEMBER_C]),
        );
        transfer::public_share_object(frame);
        test_scenario::return_shared(dao);
    };

    scenario.end();
}

#[test]
/// Two AddMember steps with cooldown > 0 both succeed: advance_step checks cooldown
/// against the pre-pipeline snapshot, so intra-composite steps don't block each other.
fun composite_same_type_cooldown_snapshot_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Set a non-zero cooldown on AddMember.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let existing = *dao.proposal_configs().get(&b"AddMember".to_ascii_string());
        let with_cooldown = proposal::new_config(
            existing.quorum(),
            existing.approval_threshold(),
            existing.propose_threshold(),
            existing.expiry_ms(),
            existing.execution_delay_ms(),
            1_000,
        ).with_composable_allowed(true);
        dao.test_update_config(b"AddMember".to_ascii_string(), with_cooldown);
        test_scenario::return_shared(dao);
    };

    // Build composite with two AddMember steps.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_D),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_c_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_c_ticket);

        // Step 1 shares the same type_key and runs at the same timestamp.
        // Without the snapshot fix this would abort ECooldownActive.
        let (payload_d_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_d_ticket);

        composite::finalize_pipeline(pipeline);

        assert!(dao.governance().is_board_member(MEMBER_C));
        assert!(dao.governance().is_board_member(MEMBER_D));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Composite with a single EnableProposalType step enables a new proposal type within
/// the pipeline. Uses a single-member DAO so CREATOR's vote alone reaches 100% approval,
/// satisfying the 66% effective threshold floor imposed by assert_composite_floors.
fun composite_enable_proposal_type_step_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // Single-member DAO — CREATOR's yes vote = 100% approval.
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Enable Step DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Submit composite: one EnableProposalType step that enables "MyGrant" / TestPayload.
    // EnableProposalType default threshold = 6600; effective = max(Composite 5000, 6600) = 6600,
    // meeting the 66% composite floor check.
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let type_config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let step_payload = enable_proposal_type::new(b"MyGrant".to_ascii_string(), type_config);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<EnableProposalType>(
            &mut frame,
            &dao,
            b"EnableProposalType".to_ascii_string(),
            step_payload,
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<EnableProposalType>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        admin_ops::execute_enable_proposal_type<TestPayload>(&mut dao, payload_ticket);

        composite::finalize_pipeline(pipeline);

        assert!(dao.enabled_proposal_types().contains(&b"MyGrant".to_ascii_string()));
        assert!(dao.has_type_binding(&b"MyGrant".to_ascii_string()));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// delete_exhausted_frame tests
// =========================================================================

#[test]
/// delete_exhausted_frame succeeds after all step payloads have been extracted.
fun composite_delete_exhausted_frame_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Submit a 1-step composite
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    // Vote
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute: advance step → finalize → delete frame
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_ticket);
        composite::finalize_pipeline(pipeline);

        // Frame is now exhausted — delete it
        composite::delete_exhausted_frame(frame);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = armature::composite::EFrameNotExhausted)]
/// delete_exhausted_frame aborts when steps have not been extracted.
fun composite_delete_exhausted_frame_not_exhausted_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Submit a 1-step composite
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    // Try to delete the frame before any execution — steps_extracted == 0, length == 1
    scenario.next_tx(CREATOR);
    {
        let frame = scenario.take_shared<CompositeFrame>();
        composite::delete_exhausted_frame(frame);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// seal_frame / EFrameAlreadySealed tests
// =========================================================================

#[test, expected_failure(abort_code = armature::composite::EFrameAlreadySealed)]
/// add_step aborts after the frame has been sealed via submit_composite.
fun composite_add_step_after_seal_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Submit composite (seals the frame)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    // Attempt to add a step to the now-shared sealed frame — must abort
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_D),
        );
        test_scenario::return_shared(frame);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// is_sealed returns true after submit_composite.
fun composite_frame_is_sealed_after_submit() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        // Not sealed yet
        assert!(!frame.is_sealed());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    // Verify the shared frame is sealed
    scenario.next_tx(CREATOR);
    {
        let frame = scenario.take_shared<CompositeFrame>();
        assert!(frame.is_sealed());
        test_scenario::return_shared(frame);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// ECooldownTypeNotComposable: advance_step rejects cooldown types not opted in
// =========================================================================

#[test, expected_failure(abort_code = armature::composite::ECooldownTypeNotComposable)]
/// advance_step aborts when a type has cooldown_ms > 0 without composable_allowed.
/// This is a defense-in-depth check: composable_allowed is validated at add_step,
/// but if the config is changed between submission and execution, advance_step catches it.
fun composite_cooldown_type_not_composable_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    create_dao_two_members(&mut scenario);

    // Submit composite with AddMember (composable_allowed = true by default, cooldown = 0)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let mut frame = composite::new_frame(dao.id(), scenario.ctx());
        composite::add_step<AddMember>(
            &mut frame,
            &dao,
            b"AddMember".to_ascii_string(),
            add_member::new(MEMBER_C),
        );
        composite::submit_composite(&dao, frame, option::none(), &clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };

    // Vote
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // AFTER vote passes, change the config: add cooldown and disable composable.
    // This simulates a governance config change between submission and execution.
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let bad_config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 1_000);
        // composable_allowed defaults to false, cooldown = 1000ms → the conflict
        dao.test_update_config(b"AddMember".to_ascii_string(), bad_config);
        test_scenario::return_shared(dao);
    };

    // Execute — advance_step must abort because cooldown > 0 and !composable_allowed
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CompositePayload>>();
        let mut frame = scenario.take_shared<CompositeFrame>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&dao, &frame, ticket);

        let (payload_ticket, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member(&mut dao, payload_ticket);
        composite::finalize_pipeline(pipeline);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
