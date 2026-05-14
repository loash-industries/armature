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
use armature_proposals::board_ops;
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
            string::utf8(b"Composite test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

/// Disable composability for a given type_key on the DAO using the test helper.
/// Used to test the ENotComposable rejection path; all types are composable by default.
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        // Step 0: AddMember(MEMBER_C)
        let (payload_c, req_c, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member_step(&mut dao, payload_c, req_c);

        // Step 1: AddMember(MEMBER_D)
        let (payload_d, req_d, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member_step(&mut dao, payload_d, req_d);

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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        let (payload_add, req_add, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member_step(&mut dao, payload_add, req_add);

        let (payload_remove, req_remove, pipeline) = composite::advance_step<RemoveMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_remove_member_step(&mut dao, payload_remove, req_remove);

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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        // Only advance step 0 — skip step 1.
        let (payload, req, pipeline) = composite::advance_step<AddMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_add_member_step(&mut dao, payload, req);

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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        // Step 0 is AddMember but we try to advance with RemoveMember — should abort.
        let (payload, req, pipeline) = composite::advance_step<RemoveMember>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        member_ops::execute_remove_member_step(&mut dao, payload, req);

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
            string::utf8(b"Composite treasury test"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };

    // Enable SendCoin type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        let (payload, req, pipeline) = composite::advance_step<SendCoin<SUI>>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        treasury_ops::execute_send_coin_step<SUI>(&mut vault, payload, req, scenario.ctx());

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
                string::utf8(b"Source"),
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
                string::utf8(b"Target"),
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
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        let (payload, req, pipeline) = composite::advance_step<SendCoinToDAO<SUI>>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        treasury_ops::execute_send_coin_to_dao_step<SUI>(
            &mut source_vault,
            &mut target_vault,
            payload,
            req,
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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        let (payload, req, pipeline) = composite::advance_step<SetBoard>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        board_ops::execute_set_board_step(&mut dao, payload, req);

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

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        let pipeline = composite::begin_pipeline(&proposal, &frame, request);

        let (payload, req, pipeline) = composite::advance_step<UpdateMetadata>(
            &mut dao,
            &mut frame,
            pipeline,
            &freeze,
            &clock,
        );
        admin_ops::execute_update_metadata_step(&mut charter, payload, req);

        composite::finalize_pipeline(pipeline);

        assert!(charter.image_url() == &string::utf8(b"ipfs://QmCompositeTest"));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(frame);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(charter);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
