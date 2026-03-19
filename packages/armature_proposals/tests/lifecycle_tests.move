#[test_only]
module armature_proposals::lifecycle_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::board_ops;
use armature_proposals::create_subdao::{Self, CreateSubDAO};
use armature_proposals::security_ops;
use armature_proposals::send_coin::{Self, SendCoin};
use armature_proposals::send_coin_to_dao::{Self, SendCoinToDAO};
use armature_proposals::send_small_payment::{Self, SendSmallPayment};
use armature_proposals::set_board::{Self, SetBoard};
use armature_proposals::subdao_ops;
use armature_proposals::treasury_ops;
use armature_proposals::unfreeze_proposal_type::{Self, UnfreezeProposalType};
use std::string;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

// =========================================================================
// Scenario 1 — Small Startup
//
// 3-person board (ALICE, BOB, CAROL). 2-of-3 quorum on normal proposals.
// They enable SendSmallPayment, make a payment, then CAROL leaves and
// two new members (DAN, EVE) join → board grows to [ALICE, BOB, DAN, EVE].
// After board change, submit another proposal to confirm new board works.
// =========================================================================

const ALICE: address = @0xA1;
const BOB: address = @0xB0;
const CAROL: address = @0xCA;
const DAN: address = @0xDA;
const EVE: address = @0xEE;

const EMPLOYEE: address = @0xE1;

public struct USDC has drop {}

#[test]
fun small_startup_lifecycle() {
    let mut scenario = test_scenario::begin(ALICE);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // ── 1. Create DAO with 3-person board ────────────────────────────
    let dao_id;
    scenario.next_tx(ALICE);
    {
        let init = governance::init_board(vector[ALICE, BOB, CAROL]);
        dao_id =
            dao::create(
                &init,
                string::utf8(b"Startup DAO"),
                string::utf8(b"Small team governance"),
                string::utf8(b"https://example.com/startup.png"),
                scenario.ctx(),
            );
    };

    // ── 2. Enable SendSmallPayment type (ALICE proposes, BOB votes yes → 2/3) ──
    //    Use test_enable_type for setup brevity — real governance path is
    //    tested in admin_ops_tests.
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"SendSmallPayment".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // ── 3. Fund the treasury ─────────────────────────────────────────
    scenario.next_tx(ALICE);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let funding = coin::mint_for_testing<SUI>(1_000_000, scenario.ctx());
        vault.deposit(funding, scenario.ctx());
        assert!(vault.balance<SUI>() == 1_000_000);
        test_scenario::return_shared(vault);
    };

    // ── 4. ALICE submits a SendSmallPayment proposal ──────────────────
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(1_000);
        let payload = send_small_payment::new<SUI>(CAROL, 5_000);
        board_voting::submit_proposal(
            &dao,
            b"SendSmallPayment".to_ascii_string(),
            string::utf8(b"Pay Carol for design work"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // ── 5. ALICE + BOB vote yes (2/3 quorum met) ─────────────────────
    scenario.next_tx(ALICE);
    {
        let mut proposal = scenario.take_shared<Proposal<SendSmallPayment<SUI>>>();
        clock.set_for_testing(1_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(BOB);
    {
        let mut proposal = scenario.take_shared<Proposal<SendSmallPayment<SUI>>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // ── 6. Execute the payment ───────────────────────────────────────
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<SendSmallPayment<SUI>>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        treasury_ops::execute_send_small_payment<SUI>(
            &mut dao,
            &mut vault,
            &proposal,
            request,
            &clock,
            scenario.ctx(),
        );

        assert!(vault.balance<SUI>() == 995_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    // ── 7. CAROL leaves, DAN and EVE join → ALICE proposes SetBoard ──
    scenario.next_tx(ALICE);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(10_000);
        let payload = set_board::new(vector[ALICE, BOB, DAN, EVE]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Carol leaving, welcome Dan and Eve"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // ── 8. ALICE + BOB vote yes on SetBoard (2/3 quorum) ─────────────
    scenario.next_tx(ALICE);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(10_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(BOB);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(11_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // ── 9. Execute SetBoard ─────────────────────────────────────────
    scenario.next_tx(ALICE);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(12_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        board_ops::execute_set_board(&mut dao, &proposal, request);

        // Verify new board
        assert!(dao.governance().is_board_member(ALICE));
        assert!(dao.governance().is_board_member(BOB));
        assert!(dao.governance().is_board_member(DAN));
        assert!(dao.governance().is_board_member(EVE));
        assert!(!dao.governance().is_board_member(CAROL));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // ── 10. New board works: DAN proposes, DAN + EVE vote → 2/4 = 50% ─
    scenario.next_tx(DAN);
    {
        let dao = scenario.take_shared_by_id<DAO>(dao_id);
        clock.set_for_testing(20_000);
        let payload = send_small_payment::new<SUI>(DAN, 1_000);
        board_voting::submit_proposal(
            &dao,
            b"SendSmallPayment".to_ascii_string(),
            string::utf8(b"DAN expense reimbursement"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(DAN);
    {
        let mut proposal = scenario.take_shared<Proposal<SendSmallPayment<SUI>>>();
        clock.set_for_testing(20_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(EVE);
    {
        let mut proposal = scenario.take_shared<Proposal<SendSmallPayment<SUI>>>();
        clock.set_for_testing(21_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(DAN);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let mut vault = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<SendSmallPayment<SUI>>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(22_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        treasury_ops::execute_send_small_payment<SUI>(
            &mut dao,
            &mut vault,
            &proposal,
            request,
            &clock,
            scenario.ctx(),
        );

        assert!(vault.balance<SUI>() == 994_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// Scenario 2 — Medium Enterprise
//
// Top-level DAO: 5-member board [M1..M5].
//   - 3/5 quorum for normal proposals (60%)
//   - 4/5 for supermajority items (80% — e.g. UpdateProposalConfig targeting itself)
// Engineering SubDAO: board = [ENG1, ENG2, ROGUE]
// Finance SubDAO: board = [FIN1, FIN2]
//
// Flow:
//   1. Create top-level DAO, fund treasury
//   2. Create Engineering and Finance SubDAOs
//   3. ROGUE causes trouble → freeze SendCoin on Engineering
//   4. Controller changes Engineering board: remove ROGUE, keep [ENG1, ENG2]
//   5. Unfreeze SendCoin on Engineering via governance
//   6. Top-level receives revenue, sends salary budget to Finance SubDAO
//   7. Finance SubDAO pays salary to Engineering employee
// =========================================================================

const M1: address = @0x11;
const M2: address = @0x12;
const M3: address = @0x13;
const M4: address = @0x14;
const M5: address = @0x15;
const ENG1: address = @0x21;
const ENG2: address = @0x22;
const ROGUE: address = @0x33;
const FIN1: address = @0x41;
const FIN2: address = @0x42;

#[test]
fun medium_enterprise_lifecycle() {
    let mut scenario = test_scenario::begin(M1);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // ── 1. Create top-level DAO with 5-member board ──────────────────
    let top_dao_id;
    scenario.next_tx(M1);
    {
        let init = governance::init_board(vector[M1, M2, M3, M4, M5]);
        top_dao_id =
            dao::create(
                &init,
                string::utf8(b"Enterprise DAO"),
                string::utf8(b"Medium enterprise with subdaos"),
                string::utf8(b"https://example.com/enterprise.png"),
                scenario.ctx(),
            );
    };

    // ── 2. Enable opt-in types on top-level DAO ──────────────────────
    scenario.next_tx(M1);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"CreateSubDAO".to_ascii_string(), config);
        dao.test_enable_type(b"SendCoin".to_ascii_string(), config);
        dao.test_enable_type(b"SendCoinToDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // ── 3. Fund top-level treasury ───────────────────────────────────
    scenario.next_tx(M1);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let revenue = coin::mint_for_testing<USDC>(10_000_000, scenario.ctx());
        vault.deposit(revenue, scenario.ctx());
        assert!(vault.balance<USDC>() == 10_000_000);
        test_scenario::return_shared(vault);
    };

    // ── 4. Create Engineering SubDAO ─────────────────────────────────
    //    M1 proposes, M1+M2+M3 vote (3/5 = 60% quorum)
    scenario.next_tx(M1);
    {
        let dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        clock.set_for_testing(1_000);
        let payload = create_subdao::new(
            string::utf8(b"Engineering"),
            string::utf8(b"Engineering team subdao"),
            vector[ENG1, ENG2, ROGUE],
            string::utf8(b"https://example.com/eng.png"),
        );
        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Create Engineering SubDAO"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(M1);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(1_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M2);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M3);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2_100);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    let eng_control_id;
    scenario.next_tx(M1);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_create_subdao(&mut vault, &proposal, request, scenario.ctx());

        let control_ids = vault.ids_for_type<SubDAOControl>();
        eng_control_id = control_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // Capture Engineering DAO ID
    let eng_dao_id;
    scenario.next_tx(M1);
    {
        let top = scenario.take_shared_by_id<DAO>(top_dao_id);
        let eng = scenario.take_shared<DAO>();
        eng_dao_id = eng.id();
        test_scenario::return_shared(eng);
        test_scenario::return_shared(top);
    };

    // ── 5. Create Finance SubDAO ─────────────────────────────────────
    scenario.next_tx(M1);
    {
        let dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        clock.set_for_testing(5_000);
        let payload = create_subdao::new(
            string::utf8(b"Finance"),
            string::utf8(b"Finance team subdao"),
            vector[FIN1, FIN2],
            string::utf8(b"https://example.com/fin.png"),
        );
        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Create Finance SubDAO"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(M1);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(5_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M2);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(6_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M3);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(6_100);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M1);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        clock.set_for_testing(7_000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_create_subdao(&mut vault, &proposal, request, scenario.ctx());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // Capture Finance DAO ID and treasury
    let fin_dao_id;
    let fin_vault_id;
    scenario.next_tx(M1);
    {
        let top = scenario.take_shared_by_id<DAO>(top_dao_id);
        let eng = scenario.take_shared_by_id<DAO>(eng_dao_id);
        let fin = scenario.take_shared<DAO>();
        fin_dao_id = fin.id();
        fin_vault_id = fin.treasury_id();
        test_scenario::return_shared(fin);
        test_scenario::return_shared(eng);
        test_scenario::return_shared(top);
    };

    // ── 6. ROGUE detected — freeze SendCoin on Engineering SubDAO ────
    //    The FreezeAdminCap for the Engineering SubDAO is in the parent vault.
    //    We loan it via a vehicle proposal on parent, freeze the type on Eng,
    //    then also change Eng board via privileged_submit in the same PTB.

    // Submit a SetBoard proposal on parent DAO as a vehicle (self-SetBoard).
    scenario.next_tx(M1);
    {
        let dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        clock.set_for_testing(20_000);
        let payload = set_board::new(vector[M1, M2, M3, M4, M5]); // same board
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Vehicle: freeze eng type + change eng board"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // 3/5 vote: M1, M2, M3
    scenario.next_tx(M1);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(20_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M2);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(21_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M3);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(21_100);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // ── 7. Execute vehicle: freeze SendCoin on Eng + change Eng board ──
    scenario.next_tx(M1);
    {
        let mut top_dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        let mut top_proposal = scenario.take_shared<Proposal<SetBoard>>();
        let top_freeze = scenario.take_shared_by_id<EmergencyFreeze>(top_dao.emergency_freeze_id());
        let mut vault = scenario.take_shared_by_id<CapabilityVault>(top_dao.capability_vault_id());
        let mut eng_dao = scenario.take_shared_by_id<DAO>(eng_dao_id);
        let mut eng_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(eng_dao.emergency_freeze_id());
        clock.set_for_testing(22_000);

        // Authorize parent proposal
        let parent_req = board_voting::authorize_execution(
            &mut top_dao,
            &mut top_proposal,
            &top_freeze,
            &clock,
            scenario.ctx(),
        );

        // Loan Engineering FreezeAdminCap from parent vault
        let freeze_cap_ids = vault.ids_for_type<FreezeAdminCap>();
        let eng_freeze_cap_id = freeze_cap_ids[0];
        let (freeze_cap, freeze_loan) = vault.loan_cap<FreezeAdminCap, SetBoard>(
            eng_freeze_cap_id,
            &parent_req,
        );

        // Freeze SendCoin on Engineering SubDAO
        eng_freeze.freeze_type(
            &freeze_cap,
            b"SendCoin".to_ascii_string(),
            &clock,
        );

        // Return FreezeAdminCap
        vault.return_cap(freeze_cap, freeze_loan);

        // Loan SubDAOControl to change Engineering board
        let (control, control_loan) = vault.loan_cap<SubDAOControl, SetBoard>(
            eng_control_id,
            &parent_req,
        );

        // Privileged submit: remove ROGUE from Engineering board
        let priv_req = controller::privileged_submit(
            &control,
            &eng_dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Remove rogue actor"),
            set_board::new(vector[ENG1, ENG2]),
            &clock,
            scenario.ctx(),
        );

        // Apply board change on Engineering SubDAO
        dao::set_board_governance(
            &mut eng_dao,
            vector[ENG1, ENG2],
            &priv_req,
        );

        // Consume privileged request
        controller::privileged_consume(priv_req, &control);

        // Return SubDAOControl
        vault.return_cap(control, control_loan);

        // Verify Engineering board changed
        assert!(eng_dao.governance().is_board_member(ENG1));
        assert!(eng_dao.governance().is_board_member(ENG2));
        assert!(!eng_dao.governance().is_board_member(ROGUE));

        // Finalize parent vehicle proposal (SetBoard on parent — no-op, same board)
        board_ops::execute_set_board(&mut top_dao, &top_proposal, parent_req);

        test_scenario::return_shared(eng_freeze);
        test_scenario::return_shared(eng_dao);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(top_freeze);
        test_scenario::return_shared(top_proposal);
        test_scenario::return_shared(top_dao);
    };

    // ── 8. Unfreeze SendCoin on Engineering via governance ────────────
    //    Engineering's own board submits UnfreezeProposalType.
    scenario.next_tx(ENG1);
    {
        let eng_dao = scenario.take_shared_by_id<DAO>(eng_dao_id);
        clock.set_for_testing(30_000);
        let payload = unfreeze_proposal_type::new(b"SendCoin".to_ascii_string());
        board_voting::submit_proposal(
            &eng_dao,
            b"UnfreezeProposalType".to_ascii_string(),
            string::utf8(b"Unfreeze SendCoin after rogue removed"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(eng_dao);
    };

    scenario.next_tx(ENG2);
    {
        let mut proposal = scenario.take_shared<Proposal<UnfreezeProposalType>>();
        clock.set_for_testing(31_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(ENG1);
    {
        let mut eng_dao = scenario.take_shared_by_id<DAO>(eng_dao_id);
        let mut proposal = scenario.take_shared<Proposal<UnfreezeProposalType>>();
        let mut eng_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(eng_dao.emergency_freeze_id());
        clock.set_for_testing(32_000);

        let request = board_voting::authorize_execution(
            &mut eng_dao,
            &mut proposal,
            &eng_freeze,
            &clock,
            scenario.ctx(),
        );

        security_ops::execute_unfreeze_proposal_type(
            &mut eng_freeze,
            &proposal,
            request,
        );

        // Verify unfrozen
        assert!(!eng_freeze.is_frozen(&b"SendCoin".to_ascii_string(), &clock));

        test_scenario::return_shared(eng_freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(eng_dao);
    };

    // ── 9. Top-level DAO sends salary budget to Finance SubDAO ───────
    //    M1 proposes SendCoinToDAO<USDC> to Finance treasury, M1+M2+M3 vote.
    scenario.next_tx(M1);
    {
        let dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        clock.set_for_testing(40_000);
        let payload = send_coin_to_dao::new<USDC>(fin_vault_id, 500_000);
        board_voting::submit_proposal(
            &dao,
            b"SendCoinToDAO".to_ascii_string(),
            string::utf8(b"Q1 salary budget to Finance"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(M1);
    {
        let mut proposal = scenario.take_shared<Proposal<SendCoinToDAO<USDC>>>();
        clock.set_for_testing(40_500);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M2);
    {
        let mut proposal = scenario.take_shared<Proposal<SendCoinToDAO<USDC>>>();
        clock.set_for_testing(41_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M3);
    {
        let mut proposal = scenario.take_shared<Proposal<SendCoinToDAO<USDC>>>();
        clock.set_for_testing(41_100);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(M1);
    {
        let mut top_dao = scenario.take_shared_by_id<DAO>(top_dao_id);
        let mut top_vault = scenario.take_shared_by_id<TreasuryVault>(top_dao.treasury_id());
        let mut fin_vault = scenario.take_shared_by_id<TreasuryVault>(fin_vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendCoinToDAO<USDC>>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(top_dao.emergency_freeze_id());
        clock.set_for_testing(42_000);

        let request = board_voting::authorize_execution(
            &mut top_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        treasury_ops::execute_send_coin_to_dao<USDC>(
            &mut top_vault,
            &mut fin_vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        // Verify balances
        assert!(top_vault.balance<USDC>() == 9_500_000);
        assert!(fin_vault.balance<USDC>() == 500_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(fin_vault);
        test_scenario::return_shared(top_vault);
        test_scenario::return_shared(top_dao);
    };

    // ── 10. Finance SubDAO pays salary to EMPLOYEE ───────────────────
    //    Finance board enables SendCoin, then FIN1 proposes, FIN2 votes.
    scenario.next_tx(FIN1);
    {
        let mut fin_dao = scenario.take_shared_by_id<DAO>(fin_dao_id);
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        fin_dao.test_enable_type(b"SendCoin".to_ascii_string(), config);
        test_scenario::return_shared(fin_dao);
    };

    scenario.next_tx(FIN1);
    {
        let fin_dao = scenario.take_shared_by_id<DAO>(fin_dao_id);
        clock.set_for_testing(50_000);
        let payload = send_coin::new<USDC>(EMPLOYEE, 100_000);
        board_voting::submit_proposal(
            &fin_dao,
            b"SendCoin".to_ascii_string(),
            string::utf8(b"March salary for EMPLOYEE"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(fin_dao);
    };

    scenario.next_tx(FIN2);
    {
        let mut proposal = scenario.take_shared<Proposal<SendCoin<USDC>>>();
        clock.set_for_testing(51_000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(FIN1);
    {
        let mut fin_dao = scenario.take_shared_by_id<DAO>(fin_dao_id);
        let mut fin_vault = scenario.take_shared_by_id<TreasuryVault>(fin_vault_id);
        let mut proposal = scenario.take_shared<Proposal<SendCoin<USDC>>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(fin_dao.emergency_freeze_id());
        clock.set_for_testing(52_000);

        let request = board_voting::authorize_execution(
            &mut fin_dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        treasury_ops::execute_send_coin<USDC>(
            &mut fin_vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        // Finance treasury reduced by salary
        assert!(fin_vault.balance<USDC>() == 400_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(fin_vault);
        test_scenario::return_shared(fin_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
