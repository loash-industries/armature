#[test_only]
module armature_proposals::migration_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::create_subdao::{Self, CreateSubDAO};
use armature_proposals::spawn_dao::{Self, SpawnDAO};
use armature_proposals::spin_out_subdao::{Self, SpinOutSubDAO};
use armature_proposals::subdao_ops;
use std::string;
use sui::clock;
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
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
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
        clock.set_for_testing(3000);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
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
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(parent_dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
