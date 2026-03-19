#[test_only]
module armature_proposals::migration_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::charter::Charter;
use armature::controller;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::board_ops;
use armature_proposals::create_subdao::{Self, CreateSubDAO};
use armature_proposals::set_board::{Self, SetBoard};
use armature_proposals::spawn_dao::{Self, SpawnDAO};
use armature_proposals::spin_out_subdao::{Self, SpinOutSubDAO};
use armature_proposals::subdao_ops;
use armature_proposals::transfer_assets::{Self, TransferAssets};
use std::string;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const SUBDAO_MEMBER: address = @0xC;

// =========================================================================
// E2E: Full migration lifecycle
// Create DAO → SpawnDAO → vote → execute (successor created, origin Migrating)
// → dao::destroy (origin destroyed)
// =========================================================================

#[test]
fun spawn_dao_and_destroy_origin_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent DAO
    scenario.next_tx(CREATOR);
    let origin_dao_id;
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        origin_dao_id =
            dao::create(
                &init,
                string::utf8(b"Origin DAO"),
                string::utf8(b"Migration e2e test"),
                string::utf8(b"https://example.com/origin.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable SpawnDAO proposal type
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"SpawnDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // 3. Submit SpawnDAO proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = spawn_dao::new(
            governance::init_board(vector[CREATOR, MEMBER_B]),
            string::utf8(b"Successor DAO"),
            string::utf8(b"The new DAO after migration"),
            string::utf8(b"https://example.com/successor.png"),
        );

        board_voting::submit_proposal(
            &dao,
            b"SpawnDAO".to_ascii_string(),
            string::utf8(b"Spawn successor DAO for migration"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 4. Vote yes — CREATOR votes, 1/2 = 50% quorum met
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SpawnDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 5. Execute SpawnDAO → creates successor DAO, sets origin to Migrating
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<SpawnDAO>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_spawn_dao(
            &mut dao,
            &proposal,
            request,
            scenario.ctx(),
        );

        // Verify origin DAO is now Migrating
        assert!(dao.status().is_migrating());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // 6. Verify successor DAO exists and origin can be destroyed
    scenario.next_tx(CREATOR);
    {
        // Origin DAO: take by known ID
        let dao = scenario.take_shared_by_id<DAO>(origin_dao_id);
        let treasury_id = dao.treasury_id();
        let vault_id = dao.capability_vault_id();
        let charter_id = dao.charter_id();
        let freeze_id = dao.emergency_freeze_id();

        // Verify Migrating status
        assert!(dao.status().is_migrating());

        // Take companion objects by ID (origin's companions)
        let treasury = scenario.take_shared_by_id<TreasuryVault>(treasury_id);
        let vault = scenario.take_shared_by_id<CapabilityVault>(vault_id);
        let charter = scenario.take_shared_by_id<Charter>(charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(freeze_id);

        // Destroy — permissionless, vaults are empty
        dao::destroy(dao, treasury, vault, charter, freeze);
    };

    // 7. Verify successor DAO is shared and Active
    scenario.next_tx(CREATOR);
    {
        let successor = scenario.take_shared<DAO>();
        assert!(successor.status().is_active());
        test_scenario::return_shared(successor);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// E2E: Full SubDAO creation + spin-out lifecycle
// Create parent DAO → CreateSubDAO → verify SubDAOControl + FreezeAdminCap
// → SpinOutSubDAO → verify SubDAO is independent
// =========================================================================

#[test]
fun create_subdao_and_spin_out_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent DAO
    let parent_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_dao_id =
            dao::create(
                &init,
                string::utf8(b"Parent DAO"),
                string::utf8(b"SubDAO spin-out e2e test"),
                string::utf8(b"https://example.com/parent.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable CreateSubDAO + SpinOutSubDAO proposal types
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"CreateSubDAO".to_ascii_string(), config);
        dao.test_enable_type(b"SpinOutSubDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // ---- Phase A: CreateSubDAO ----

    // 3. Submit CreateSubDAO proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);

        let payload = create_subdao::new(
            string::utf8(b"Child DAO"),
            string::utf8(b"A managed sub-DAO for spin-out"),
            vector[SUBDAO_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );

        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Create child DAO"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 4. Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 5. Execute CreateSubDAO → creates SubDAO, stores SubDAOControl + FreezeAdminCap
    let subdao_id;
    let control_cap_id;
    let freeze_admin_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_create_subdao(
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        // Vault should now contain SubDAOControl + FreezeAdminCap (2 caps)
        assert!(vault.cap_ids().length() == 2);

        // Get the cap IDs for the spin-out payload
        let control_ids = vault.ids_for_type<SubDAOControl>();
        let freeze_ids = vault.ids_for_type<FreezeAdminCap>();
        assert!(control_ids.length() == 1);
        assert!(freeze_ids.length() == 1);

        control_cap_id = control_ids[0];
        freeze_admin_cap_id = freeze_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // 6. Get the SubDAO ID from the shared object
    scenario.next_tx(CREATOR);
    {
        // Take parent by known ID to skip it; take child as second DAO
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let child = scenario.take_shared<DAO>();
        subdao_id = child.id();
        test_scenario::return_shared(parent);

        // Verify SubDAO has controller set
        assert!(child.controller_cap_id().is_some());
        // Verify SubDAO does NOT have SpawnDAO/SpinOutSubDAO/CreateSubDAO enabled
        assert!(!child.enabled_proposal_types().contains(&b"SpawnDAO".to_ascii_string()));
        assert!(!child.enabled_proposal_types().contains(&b"SpinOutSubDAO".to_ascii_string()));
        assert!(!child.enabled_proposal_types().contains(&b"CreateSubDAO".to_ascii_string()));

        test_scenario::return_shared(child);
    };

    // ---- Phase B: SpinOutSubDAO ----

    // 7. Submit SpinOutSubDAO proposal on the parent DAO
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        clock.set_for_testing(5000);

        let spin_config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        let payload = spin_out_subdao::new(
            subdao_id,
            control_cap_id,
            freeze_admin_cap_id,
            spin_config, // spawn_dao_config for the SubDAO
            spin_config, // spin_out_subdao_config for the SubDAO
            spin_config, // create_subdao_config for the SubDAO
        );

        board_voting::submit_proposal(
            &dao,
            b"SpinOutSubDAO".to_ascii_string(),
            string::utf8(b"Spin out child DAO to independence"),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(dao);
    };

    // 8. Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SpinOutSubDAO>>();
        clock.set_for_testing(6000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 9. Execute SpinOutSubDAO
    scenario.next_tx(CREATOR);
    {
        let mut parent_dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let mut proposal = scenario.take_shared<Proposal<SpinOutSubDAO>>();
        let parent_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(parent_dao.emergency_freeze_id());
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_dao.capability_vault_id());
        let mut subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        let mut subdao_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(subdao.capability_vault_id());
        clock.set_for_testing(7000);

        let request = board_voting::authorize_execution(
            &mut parent_dao,
            &mut proposal,
            &parent_freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_spin_out_subdao(
            &mut parent_vault,
            &mut subdao_vault,
            &mut subdao,
            &proposal,
            request,
            &clock,
            scenario.ctx(),
        );

        // Verify: SubDAO controller cleared
        assert!(subdao.controller_cap_id().is_none());
        assert!(!subdao.is_controller_paused());

        // Verify: SubDAO now has SpawnDAO, SpinOutSubDAO, CreateSubDAO enabled
        assert!(subdao.enabled_proposal_types().contains(&b"SpawnDAO".to_ascii_string()));
        assert!(subdao.enabled_proposal_types().contains(&b"SpinOutSubDAO".to_ascii_string()));
        assert!(subdao.enabled_proposal_types().contains(&b"CreateSubDAO".to_ascii_string()));

        // Verify: Parent vault no longer holds SubDAOControl or FreezeAdminCap
        assert!(parent_vault.is_empty());

        // Verify: SubDAO vault now holds the FreezeAdminCap
        assert!(subdao_vault.cap_ids().length() == 1);
        let subdao_freeze_ids = subdao_vault.ids_for_type<FreezeAdminCap>();
        assert!(subdao_freeze_ids.length() == 1);
        assert!(subdao_freeze_ids[0] == freeze_admin_cap_id);

        test_scenario::return_shared(subdao_vault);
        test_scenario::return_shared(subdao);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent_freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(parent_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// E2E: Controller SetBoard via privileged_submit (#87)
// Create parent DAO → CreateSubDAO → parent uses privileged_submit to change
// SubDAO's board → verify board changed
// =========================================================================

#[test]
fun controller_set_board_via_privileged_submit() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent DAO
    let parent_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_dao_id =
            dao::create(
                &init,
                string::utf8(b"Parent DAO"),
                string::utf8(b"Controller SetBoard test"),
                string::utf8(b"https://example.com/parent.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable CreateSubDAO
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"CreateSubDAO".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // 3. Submit + vote CreateSubDAO proposal
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = create_subdao::new(
            string::utf8(b"Child DAO"),
            string::utf8(b"Managed child"),
            vector[SUBDAO_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );
        board_voting::submit_proposal(
            &dao,
            b"CreateSubDAO".to_ascii_string(),
            string::utf8(b"Create child"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 4. Execute CreateSubDAO
    let control_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubDAO>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_create_subdao(
            &mut vault,
            &proposal,
            request,
            scenario.ctx(),
        );

        let control_ids = vault.ids_for_type<SubDAOControl>();
        control_cap_id = control_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // 5. Get SubDAO ID
    let subdao_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let child = scenario.take_shared<DAO>();
        subdao_id = child.id();

        // Verify initial board: only SUBDAO_MEMBER
        assert!(child.governance().is_board_member(SUBDAO_MEMBER));
        assert!(!child.governance().is_board_member(CREATOR));

        test_scenario::return_shared(parent);
        test_scenario::return_shared(child);
    };

    // 6. Parent submits SetBoard on ITSELF (as vehicle to get ExecutionRequest for vault loan)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        clock.set_for_testing(5000);
        let payload = set_board::new(vector[CREATOR, MEMBER_B]);
        board_voting::submit_proposal(
            &dao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Vehicle for controller op"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SetBoard>>();
        clock.set_for_testing(6000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 7. Execute: loan SubDAOControl → privileged_submit SetBoard on SubDAO
    //    → set_board_governance → privileged_consume → return_cap → consume parent request
    scenario.next_tx(CREATOR);
    {
        let mut parent_dao = scenario.take_shared_by_id<DAO>(parent_dao_id);
        let mut parent_proposal = scenario.take_shared<Proposal<SetBoard>>();
        let parent_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(parent_dao.emergency_freeze_id());
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_dao.capability_vault_id());
        let mut subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        clock.set_for_testing(7000);

        // Get parent ExecutionRequest (for vault loan authorization)
        let parent_req = board_voting::authorize_execution(
            &mut parent_dao,
            &mut parent_proposal,
            &parent_freeze,
            &clock,
            scenario.ctx(),
        );

        // Loan SubDAOControl from parent vault
        let (control, loan) = vault.loan_cap<SubDAOControl, SetBoard>(
            control_cap_id,
            &parent_req,
        );

        // Privileged submit: set SubDAO's board to [SUBDAO_MEMBER, CREATOR]
        let priv_req = controller::privileged_submit(
            &control,
            &subdao,
            b"SetBoard".to_ascii_string(),
            string::utf8(b"Controller sets SubDAO board"),
            set_board::new(vector[SUBDAO_MEMBER, CREATOR]),
            &clock,
            scenario.ctx(),
        );

        // Apply board change on SubDAO using privileged ExecutionRequest
        dao::set_board_governance(&mut subdao, vector[SUBDAO_MEMBER, CREATOR], &priv_req);

        // Consume privileged request
        controller::privileged_consume(priv_req, &control);

        // Return SubDAOControl to vault
        vault.return_cap(control, loan);

        // Consume parent request by applying no-op board change (same members)
        board_ops::execute_set_board(&mut parent_dao, &parent_proposal, parent_req);

        // Verify: SubDAO board now includes CREATOR
        assert!(subdao.governance().is_board_member(SUBDAO_MEMBER));
        assert!(subdao.governance().is_board_member(CREATOR));

        test_scenario::return_shared(subdao);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_freeze);
        test_scenario::return_shared(parent_proposal);
        test_scenario::return_shared(parent_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// E2E: Full migration with TransferAssets (#88)
// Create DAO → fund treasury → SpawnDAO → TransferAssets (coins) → dao::destroy
// =========================================================================

#[test]
fun migration_with_transfer_assets_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create origin DAO
    let origin_dao_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        origin_dao_id =
            dao::create(
                &init,
                string::utf8(b"Origin DAO"),
                string::utf8(b"Migration + TransferAssets test"),
                string::utf8(b"https://example.com/origin.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable SpawnDAO + TransferAssets on origin
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(b"SpawnDAO".to_ascii_string(), config);
        dao.test_enable_type(b"TransferAssets".to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };

    // 3. Fund origin treasury
    scenario.next_tx(CREATOR);
    {
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(500_000, scenario.ctx());
        treasury.deposit(coin, scenario.ctx());
        assert!(treasury.balance<SUI>() == 500_000);
        test_scenario::return_shared(treasury);
    };

    // 4. Submit + vote + execute SpawnDAO → origin becomes Migrating
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        clock.set_for_testing(1000);
        let payload = spawn_dao::new(
            governance::init_board(vector[CREATOR, MEMBER_B]),
            string::utf8(b"Successor DAO"),
            string::utf8(b"The successor"),
            string::utf8(b"https://example.com/successor.png"),
        );
        board_voting::submit_proposal(
            &dao,
            b"SpawnDAO".to_ascii_string(),
            string::utf8(b"Spawn successor"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SpawnDAO>>();
        clock.set_for_testing(2000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut proposal = scenario.take_shared<Proposal<SpawnDAO>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        subdao_ops::execute_spawn_dao(&mut dao, &proposal, request, scenario.ctx());
        assert!(dao.status().is_migrating());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(dao);
    };

    // 5. Get successor DAO's treasury + vault IDs
    let successor_treasury_id;
    let successor_vault_id;
    scenario.next_tx(CREATOR);
    {
        let origin = scenario.take_shared_by_id<DAO>(origin_dao_id);
        let successor = scenario.take_shared<DAO>();
        assert!(successor.status().is_active());
        successor_treasury_id = successor.treasury_id();
        successor_vault_id = successor.capability_vault_id();
        test_scenario::return_shared(origin);
        test_scenario::return_shared(successor);
    };

    // 6. Submit TransferAssets proposal on origin (Migrating — allowed for TransferAssets)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(origin_dao_id);
        clock.set_for_testing(5000);
        let payload = transfer_assets::new(
            dao.status().successor_dao_id(),
            successor_treasury_id,
            successor_vault_id,
            vector[],
            vector[],
        );
        board_voting::submit_proposal(
            &dao,
            b"TransferAssets".to_ascii_string(),
            string::utf8(b"Transfer all assets to successor"),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<TransferAssets>>();
        clock.set_for_testing(6000);
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // 7. Execute TransferAssets: validate → withdraw + deposit → finalize
    scenario.next_tx(CREATOR);
    {
        let mut origin_dao = scenario.take_shared_by_id<DAO>(origin_dao_id);
        let mut proposal = scenario.take_shared<Proposal<TransferAssets>>();
        let origin_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(origin_dao.emergency_freeze_id());
        let mut origin_treasury = scenario.take_shared_by_id<
            TreasuryVault,
        >(origin_dao.treasury_id());
        let origin_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(origin_dao.capability_vault_id());
        let mut successor_treasury = scenario.take_shared_by_id<TreasuryVault>(
            successor_treasury_id,
        );
        let successor_vault = scenario.take_shared_by_id<CapabilityVault>(successor_vault_id);
        clock.set_for_testing(7000);

        let request = board_voting::authorize_execution(
            &mut origin_dao,
            &mut proposal,
            &origin_freeze,
            &clock,
            scenario.ctx(),
        );

        // Validate target IDs match
        subdao_ops::validate_transfer_assets(
            &origin_treasury,
            &origin_vault,
            &successor_treasury,
            &successor_vault,
            &proposal,
            &request,
        );

        // Withdraw from origin, deposit into successor
        let coin = origin_treasury.withdraw<SUI, TransferAssets>(
            500_000,
            &request,
            scenario.ctx(),
        );
        successor_treasury.deposit(coin, scenario.ctx());

        // Finalize
        subdao_ops::finalize_transfer_assets(request, &proposal);

        // Verify balances
        assert!(origin_treasury.balance<SUI>() == 0);
        assert!(successor_treasury.balance<SUI>() == 500_000);

        test_scenario::return_shared(successor_vault);
        test_scenario::return_shared(successor_treasury);
        test_scenario::return_shared(origin_vault);
        test_scenario::return_shared(origin_treasury);
        test_scenario::return_shared(origin_freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(origin_dao);
    };

    // 8. Destroy origin DAO (treasury is now empty)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared_by_id<DAO>(origin_dao_id);
        let treasury = scenario.take_shared_by_id<TreasuryVault>(dao.treasury_id());
        let vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());
        let charter = scenario.take_shared_by_id<Charter>(dao.charter_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());
        dao::destroy(dao, treasury, vault, charter, freeze);
    };

    // 9. Verify successor still active with funds
    scenario.next_tx(CREATOR);
    {
        let successor = scenario.take_shared<DAO>();
        assert!(successor.status().is_active());
        let treasury = scenario.take_shared_by_id<TreasuryVault>(successor.treasury_id());
        assert!(treasury.balance<SUI>() == 500_000);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(successor);
    };

    clock.destroy_for_testing();
    scenario.end();
}
