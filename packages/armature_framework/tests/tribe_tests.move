#[test_only]
module armature::tribe_tests;

use armature::capability_vault::{Self, CapabilityVault, SubDAOControl};
use armature::charter::Charter;
use armature::dao::{Self, DAO};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal;
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use std::string;
use sui::test_scenario;
use sui::vec_map;

// === Test addresses ===

const CREATOR: address = @0xA;
const TRIBE_MEMBER: address = @0xB;
const OFFICER_A: address = @0xC;
const OFFICER_B: address = @0xD;
const MEMBER_A: address = @0xE;
const MEMBER_B: address = @0xF;
const OFFICER_ADMIN: address = @0x10;
const MEMBER_ADMIN: address = @0x11;

// === Dummy proposal type for ExecutionRequest construction in tests ===

public struct TestProposal has drop {}

// === Helper ===

fun do_create_tribe(scenario: &mut test_scenario::Scenario): (ID, ID, ID) {
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[CREATOR, TRIBE_MEMBER],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A, MEMBER_B],
        string::utf8(b"Tribe DAO"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        scenario.ctx(),
    )
}

// === Test 1: returned IDs are distinct ===

#[test]
/// create_tribe returns three distinct IDs.
fun create_tribe_returns_distinct_dao_ids() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    assert!(owner_id != officer_id);
    assert!(owner_id != member_id);
    assert!(officer_id != member_id);

    scenario.end();
}

// === Test 2: all three DAOs are active with the correct boards ===

#[test]
/// Each DAO is Active and seeded with the correct board members.
fun create_tribe_daos_are_active_with_correct_boards() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_dao = scenario.take_shared_by_id<DAO>(owner_id);
        let officer_dao = scenario.take_shared_by_id<DAO>(officer_id);
        let member_dao = scenario.take_shared_by_id<DAO>(member_id);

        assert!(tribe_dao.status().is_active());
        assert!(officer_dao.status().is_active());
        assert!(member_dao.status().is_active());

        assert!(tribe_dao.governance().is_board_member(CREATOR));
        assert!(tribe_dao.governance().is_board_member(TRIBE_MEMBER));
        assert!(!tribe_dao.governance().is_board_member(OFFICER_A));

        assert!(officer_dao.governance().is_board_member(OFFICER_A));
        assert!(officer_dao.governance().is_board_member(OFFICER_B));
        assert!(!officer_dao.governance().is_board_member(CREATOR));

        assert!(member_dao.governance().is_board_member(MEMBER_A));
        assert!(member_dao.governance().is_board_member(MEMBER_B));
        assert!(!member_dao.governance().is_board_member(CREATOR));

        test_scenario::return_shared(tribe_dao);
        test_scenario::return_shared(officer_dao);
        test_scenario::return_shared(member_dao);
    };

    scenario.end();
}

// === Test 3: control hierarchy — tribe→officers→members ===

#[test]
/// Tribe vault holds one SubDAOControl pointing at the Officers SubDAO.
/// Officers vault holds one SubDAOControl pointing at the Members SubDAO.
fun create_tribe_control_hierarchy_is_tribe_officers_members() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_dao = scenario.take_shared_by_id<DAO>(owner_id);
        let officer_dao = scenario.take_shared_by_id<DAO>(officer_id);
        let tribe_vault_id = tribe_dao.capability_vault_id();
        let officer_vault_id = officer_dao.capability_vault_id();
        test_scenario::return_shared(tribe_dao);
        test_scenario::return_shared(officer_dao);

        // Tribe vault: exactly one control, pointing at the Officers SubDAO.
        let mut tribe_vault = scenario.take_shared_by_id<CapabilityVault>(tribe_vault_id);
        let tribe_ctrl_ids = tribe_vault.ids_for_type<SubDAOControl>();
        assert!(tribe_ctrl_ids.length() == 1);

        let req = proposal::new_execution_request<TestProposal>(
            tribe_vault.dao_id(),
            object::id_from_address(@0xBEEF),
        );
        let (tribe_ctrl, tribe_loan) = tribe_vault.loan_cap<SubDAOControl, TestProposal>(
            tribe_ctrl_ids[0],
            &req,
        );
        assert!(tribe_ctrl.subdao_id() == officer_id);
        tribe_vault.return_cap(tribe_ctrl, tribe_loan);
        proposal::consume(req);
        test_scenario::return_shared(tribe_vault);

        // Officers vault: exactly one control, pointing at the Members SubDAO.
        let mut officer_vault = scenario.take_shared_by_id<CapabilityVault>(officer_vault_id);
        let officer_ctrl_ids = officer_vault.ids_for_type<SubDAOControl>();
        assert!(officer_ctrl_ids.length() == 1);

        let req = proposal::new_execution_request<TestProposal>(
            officer_vault.dao_id(),
            object::id_from_address(@0xBEEF),
        );
        let (officer_ctrl, officer_loan) = officer_vault.loan_cap<SubDAOControl, TestProposal>(
            officer_ctrl_ids[0],
            &req,
        );
        assert!(officer_ctrl.subdao_id() == member_id);
        officer_vault.return_cap(officer_ctrl, officer_loan);
        proposal::consume(req);
        test_scenario::return_shared(officer_vault);
    };

    scenario.end();
}

// === Test 4: FreezeAdminCaps are routed to the correct addresses ===

#[test]
/// Tribe cap goes to ctx.sender(); officer and member caps go to their admin addresses.
fun create_tribe_freeze_caps_routed_correctly() {
    let mut scenario = test_scenario::begin(CREATOR);
    do_create_tribe(&mut scenario);

    // Tribe cap → CREATOR
    scenario.next_tx(CREATOR);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    // Officer cap → OFFICER_ADMIN
    scenario.next_tx(OFFICER_ADMIN);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    // Member cap → MEMBER_ADMIN
    scenario.next_tx(MEMBER_ADMIN);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    scenario.end();
}

// === Test 5: all fifteen companion objects are shared ===

#[test]
/// Each of the three DAOs has its four companion objects shared on-chain.
fun create_tribe_all_companion_objects_are_shared() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    // Verify IDs stored on each DAO reference distinct shared objects.
    scenario.next_tx(CREATOR);
    {
        let tribe_dao = scenario.take_shared_by_id<DAO>(owner_id);
        let officer_dao = scenario.take_shared_by_id<DAO>(officer_id);
        let member_dao = scenario.take_shared_by_id<DAO>(member_id);

        // All companion IDs are non-zero and distinct from their parent DAO.
        assert!(tribe_dao.treasury_id()         != owner_id);
        assert!(tribe_dao.capability_vault_id() != owner_id);
        assert!(tribe_dao.charter_id()          != owner_id);
        assert!(tribe_dao.emergency_freeze_id() != owner_id);

        assert!(officer_dao.treasury_id()         != officer_id);
        assert!(officer_dao.capability_vault_id() != officer_id);
        assert!(officer_dao.charter_id()          != officer_id);
        assert!(officer_dao.emergency_freeze_id() != officer_id);

        assert!(member_dao.treasury_id()         != member_id);
        assert!(member_dao.capability_vault_id() != member_id);
        assert!(member_dao.charter_id()          != member_id);
        assert!(member_dao.emergency_freeze_id() != member_id);

        let tribe_vault_id = tribe_dao.capability_vault_id();

        test_scenario::return_shared(tribe_dao);
        test_scenario::return_shared(officer_dao);
        test_scenario::return_shared(member_dao);

        // Spot-check: each shared type can actually be taken.
        let vault = scenario.take_shared_by_id<CapabilityVault>(tribe_vault_id);
        test_scenario::return_shared(vault);

        // Three of each companion type are available.
        let t1 = scenario.take_shared<TreasuryVault>();
        let t2 = scenario.take_shared<TreasuryVault>();
        let t3 = scenario.take_shared<TreasuryVault>();
        test_scenario::return_shared(t1);
        test_scenario::return_shared(t2);
        test_scenario::return_shared(t3);

        let c1 = scenario.take_shared<Charter>();
        let c2 = scenario.take_shared<Charter>();
        let c3 = scenario.take_shared<Charter>();
        test_scenario::return_shared(c1);
        test_scenario::return_shared(c2);
        test_scenario::return_shared(c3);

        let e1 = scenario.take_shared<EmergencyFreeze>();
        let e2 = scenario.take_shared<EmergencyFreeze>();
        let e3 = scenario.take_shared<EmergencyFreeze>();
        test_scenario::return_shared(e1);
        test_scenario::return_shared(e2);
        test_scenario::return_shared(e3);
    };

    scenario.end();
}

// === Test 6: empty tribe board aborts ===

#[test, expected_failure(abort_code = governance::EEmptyBoard)]
/// Passing an empty tribe_board vector causes an abort during DAO creation.
fun create_tribe_aborts_on_empty_tribe_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe DAO"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        scenario.ctx(),
    );
    scenario.end();
}

// === Test 7: empty officers array aborts ===

#[test, expected_failure(abort_code = governance::EEmptyBoard)]
/// Passing an empty officers vector causes an abort during SubDAO creation.
fun create_tribe_aborts_on_empty_officer_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[CREATOR],
        vector[],
        vector[MEMBER_A],
        string::utf8(b"Tribe DAO"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        scenario.ctx(),
    );
    scenario.end();
}

// === Test 8: empty members array aborts ===

#[test, expected_failure(abort_code = governance::EEmptyBoard)]
/// Passing an empty members vector causes an abort during SubDAO creation.
fun create_tribe_aborts_on_empty_member_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[CREATOR],
        vector[OFFICER_A],
        vector[],
        string::utf8(b"Tribe DAO"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        scenario.ctx(),
    );
    scenario.end();
}

// ============================================================
// create_wired_subdao tests
// ============================================================

const SUBDAO_ADMIN: address = @0x20;

// Minimum valid config reused across tests.
fun default_config(): proposal::ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0)
}

/// Create a parent DAO (vault kept un-shared), wire a SubDAO into it, then share
/// the vault. Returns (parent_dao_id, subdao_id).
fun do_create_parent_and_wired_subdao(scenario: &mut test_scenario::Scenario): (ID, ID) {
    scenario.next_tx(CREATOR);
    let gov = governance::init_board(vector[CREATOR, TRIBE_MEMBER]);
    let (parent_id, mut parent_vault) = dao::create_returning_vault(
        &gov,
        string::utf8(b"Parent DAO"),
        string::utf8(b"https://example.com/parent.png"),
        scenario.ctx(),
    );
    let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
    let subdao_id = tribe::create_wired_subdao(
        vector[OFFICER_A],
        string::utf8(b"SubDAO"),
        string::utf8(b"https://example.com/sub.png"),
        SUBDAO_ADMIN,
        &mut parent_vault,
        &req,
        vec_map::empty(),
        scenario.ctx(),
    );
    proposal::consume(req);
    capability_vault::share(parent_vault);
    (parent_id, subdao_id)
}

// === Test 9: create_wired_subdao returns a non-zero ID ===

#[test]
/// create_wired_subdao returns an ID that matches the shared SubDAO object.
fun create_wired_subdao_returns_correct_subdao_id() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, subdao_id) = do_create_parent_and_wired_subdao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        assert!(subdao.id() == subdao_id);
        assert!(subdao.status().is_active());
        test_scenario::return_shared(subdao);
    };

    scenario.end();
}

// === Test 10: parent vault contains exactly one SubDAOControl pointing at the new subdao ===

#[test]
/// After create_wired_subdao the parent vault holds exactly one SubDAOControl
/// whose subdao_id matches the returned subdao ID.
fun create_wired_subdao_wires_control_into_parent_vault() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (parent_id, subdao_id) = do_create_parent_and_wired_subdao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let parent_dao = scenario.take_shared_by_id<DAO>(parent_id);
        let vault_id = parent_dao.capability_vault_id();
        test_scenario::return_shared(parent_dao);

        let mut vault = scenario.take_shared_by_id<CapabilityVault>(vault_id);
        let ctrl_ids = vault.ids_for_type<SubDAOControl>();
        assert!(ctrl_ids.length() == 1);

        let req = proposal::new_execution_request<TestProposal>(
            vault.dao_id(),
            object::id_from_address(@0xBEEF),
        );
        let (ctrl, loan) = vault.loan_cap<SubDAOControl, TestProposal>(ctrl_ids[0], &req);
        assert!(ctrl.subdao_id() == subdao_id);
        vault.return_cap(ctrl, loan);
        proposal::consume(req);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// === Test 11: new subdao has controller_cap_id set ===

#[test]
/// The wired SubDAO has controller_cap_id populated (it is a controlled subdao).
fun create_wired_subdao_subdao_is_controlled() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, subdao_id) = do_create_parent_and_wired_subdao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        assert!(subdao.controller_cap_id().is_some());
        test_scenario::return_shared(subdao);
    };

    scenario.end();
}

// === Test 12: FreezeAdminCap goes to freeze_admin ===

#[test]
/// create_wired_subdao transfers the SubDAO FreezeAdminCap to the freeze_admin address.
fun create_wired_subdao_freeze_cap_routed_to_admin() {
    let mut scenario = test_scenario::begin(CREATOR);
    do_create_parent_and_wired_subdao(&mut scenario);

    scenario.next_tx(SUBDAO_ADMIN);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    scenario.end();
}

// === Test 13: subdao companion objects are shared ===

#[test]
/// create_wired_subdao shares the SubDAO's treasury, charter, and emergency freeze.
fun create_wired_subdao_companion_objects_are_shared() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, subdao_id) = do_create_parent_and_wired_subdao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);

        // Companion IDs are populated and distinct from the subdao itself.
        assert!(subdao.treasury_id()         != subdao_id);
        assert!(subdao.capability_vault_id() != subdao_id);
        assert!(subdao.charter_id()          != subdao_id);
        assert!(subdao.emergency_freeze_id() != subdao_id);

        let treasury_id = subdao.treasury_id();
        let vault_id = subdao.capability_vault_id();
        let charter_id = subdao.charter_id();
        let freeze_id = subdao.emergency_freeze_id();
        test_scenario::return_shared(subdao);

        // Each companion can be taken as a shared object.
        let treasury = scenario.take_shared_by_id<TreasuryVault>(treasury_id);
        test_scenario::return_shared(treasury);
        let vault = scenario.take_shared_by_id<CapabilityVault>(vault_id);
        test_scenario::return_shared(vault);
        let charter = scenario.take_shared_by_id<Charter>(charter_id);
        test_scenario::return_shared(charter);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(freeze_id);
        test_scenario::return_shared(freeze);
    };

    scenario.end();
}

// === Test 14: config override is reflected in the subdao ===

#[test]
/// A config override passed to create_wired_subdao is applied to the resulting SubDAO.
fun create_wired_subdao_config_override_applied() {
    let mut scenario = test_scenario::begin(CREATOR);

    let subdao_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        // Override the SetBoard config with a custom quorum.
        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"SetBoard".to_ascii_string(),
            proposal::new_config(7_500, 7_500, 0, 604_800_000, 0, 0),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        subdao_id =
            tribe::create_wired_subdao(
                vector[OFFICER_A],
                string::utf8(b"SubDAO"),
                string::utf8(b"https://example.com/sub.png"),
                SUBDAO_ADMIN,
                &mut parent_vault,
                &req,
                overrides,
                scenario.ctx(),
            );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        let config = subdao.proposal_configs().get(&b"SetBoard".to_ascii_string());
        assert!(config.quorum() == 7_500);
        assert!(config.approval_threshold() == 7_500);
        test_scenario::return_shared(subdao);
    };

    scenario.end();
}

// === Test 15: new type enabled via override ===

#[test]
/// An override key not in the subdao defaults is inserted and enabled on the subdao.
fun create_wired_subdao_new_type_enabled_via_override() {
    let mut scenario = test_scenario::begin(CREATOR);

    let subdao_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"SendCoin".to_ascii_string(),
            default_config(),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        subdao_id =
            tribe::create_wired_subdao(
                vector[OFFICER_A],
                string::utf8(b"SubDAO"),
                string::utf8(b"https://example.com/sub.png"),
                SUBDAO_ADMIN,
                &mut parent_vault,
                &req,
                overrides,
                scenario.ctx(),
            );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        assert!(subdao.enabled_proposal_types().contains(&b"SendCoin".to_ascii_string()));
        test_scenario::return_shared(subdao);
    };

    scenario.end();
}

// === Test 16: blocked proposal type in overrides aborts ===

#[test, expected_failure(abort_code = dao::EBlockedProposalType)]
/// Passing a blocked type key (SpawnDAO) in config_overrides aborts with EBlockedProposalType.
fun create_wired_subdao_aborts_on_blocked_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"SpawnDAO".to_ascii_string(),
            default_config(),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        tribe::create_wired_subdao(
            vector[OFFICER_A],
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            SUBDAO_ADMIN,
            &mut parent_vault,
            &req,
            overrides,
            scenario.ctx(),
        );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };
    scenario.end();
}

// === Test 17: EnableProposalType below floor aborts ===

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// Setting EnableProposalType threshold below 66% aborts with EThresholdBelowMinimum.
fun create_wired_subdao_aborts_on_enable_proposal_type_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"EnableProposalType".to_ascii_string(),
            proposal::new_config(5_000, 6_599, 0, 604_800_000, 0, 0),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        tribe::create_wired_subdao(
            vector[OFFICER_A],
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            SUBDAO_ADMIN,
            &mut parent_vault,
            &req,
            overrides,
            scenario.ctx(),
        );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };
    scenario.end();
}

// === Test 18: UpdateProposalConfig below floor aborts ===

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// Setting UpdateProposalConfig threshold below 80% aborts with EThresholdBelowMinimum.
fun create_wired_subdao_aborts_on_update_proposal_config_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"UpdateProposalConfig".to_ascii_string(),
            proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        tribe::create_wired_subdao(
            vector[OFFICER_A],
            string::utf8(b"SubDAO"),
            string::utf8(b"https://example.com/sub.png"),
            SUBDAO_ADMIN,
            &mut parent_vault,
            &req,
            overrides,
            scenario.ctx(),
        );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };
    scenario.end();
}

// === Test 19: EnableProposalType at exact floor passes ===

#[test]
/// Setting EnableProposalType threshold at exactly 66% (6600) succeeds.
fun create_wired_subdao_enable_proposal_type_at_floor_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let subdao_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"EnableProposalType".to_ascii_string(),
            proposal::new_config(5_000, 6_600, 0, 604_800_000, 0, 0),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        subdao_id =
            tribe::create_wired_subdao(
                vector[OFFICER_A],
                string::utf8(b"SubDAO"),
                string::utf8(b"https://example.com/sub.png"),
                SUBDAO_ADMIN,
                &mut parent_vault,
                &req,
                overrides,
                scenario.ctx(),
            );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        let config = subdao.proposal_configs().get(&b"EnableProposalType".to_ascii_string());
        assert!(config.approval_threshold() == 6_600);
        test_scenario::return_shared(subdao);
    };

    scenario.end();
}

// ============================================================
// create_tribe_configured tests
// ============================================================

fun do_create_tribe_configured(scenario: &mut test_scenario::Scenario): (ID, ID, ID) {
    scenario.next_tx(CREATOR);
    tribe::create_tribe_configured(
        vector[CREATOR, TRIBE_MEMBER],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A, MEMBER_B],
        string::utf8(b"Tribe DAO"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vec_map::empty(),
        vec_map::empty(),
        vec_map::empty(),
        scenario.ctx(),
    )
}

// === Test 20: create_tribe_configured with empty overrides matches create_tribe structure ===

#[test]
/// create_tribe_configured with all-empty override maps produces the same
/// three-DAO structure (distinct IDs, correct boards, control hierarchy) as create_tribe.
fun create_tribe_configured_empty_overrides_matches_create_tribe() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe_configured(&mut scenario);

    assert!(owner_id != officer_id);
    assert!(owner_id != member_id);
    assert!(officer_id != member_id);

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<DAO>(owner_id);
        let officer = scenario.take_shared_by_id<DAO>(officer_id);
        let member = scenario.take_shared_by_id<DAO>(member_id);

        assert!(tribe.status().is_active());
        assert!(officer.status().is_active());
        assert!(member.status().is_active());

        assert!(tribe.governance().is_board_member(CREATOR));
        assert!(tribe.governance().is_board_member(TRIBE_MEMBER));
        assert!(officer.governance().is_board_member(OFFICER_A));
        assert!(officer.governance().is_board_member(OFFICER_B));
        assert!(member.governance().is_board_member(MEMBER_A));
        assert!(member.governance().is_board_member(MEMBER_B));

        test_scenario::return_shared(tribe);
        test_scenario::return_shared(officer);
        test_scenario::return_shared(member);
    };

    scenario.end();
}

// === Test 21: override applied to tribe DAO ===

#[test]
/// A config override for the tribe DAO is reflected in its proposal_configs.
fun create_tribe_configured_override_applied_to_tribe_dao() {
    let mut scenario = test_scenario::begin(CREATOR);

    let owner_id: ID;
    scenario.next_tx(CREATOR);
    {
        let mut tribe_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut tribe_overrides,
            b"AddMember".to_ascii_string(),
            proposal::new_config(8_000, 8_000, 0, 604_800_000, 0, 0),
        );

        (owner_id, _, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe DAO"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                tribe_overrides,
                vec_map::empty(),
                vec_map::empty(),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<DAO>(owner_id);
        let config = tribe.proposal_configs().get(&b"AddMember".to_ascii_string());
        assert!(config.quorum() == 8_000);
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(tribe);
    };

    scenario.end();
}

// === Test 22: override applied to officer subdao ===

#[test]
/// A config override for the officer SubDAO is reflected in its proposal_configs.
fun create_tribe_configured_override_applied_to_officer_subdao() {
    let mut scenario = test_scenario::begin(CREATOR);

    let officer_id: ID;
    scenario.next_tx(CREATOR);
    {
        let mut officer_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut officer_overrides,
            b"RemoveMember".to_ascii_string(),
            proposal::new_config(9_000, 9_000, 0, 604_800_000, 0, 0),
        );

        (_, officer_id, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe DAO"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                vec_map::empty(),
                officer_overrides,
                vec_map::empty(),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let officer = scenario.take_shared_by_id<DAO>(officer_id);
        let config = officer.proposal_configs().get(&b"RemoveMember".to_ascii_string());
        assert!(config.quorum() == 9_000);
        assert!(config.approval_threshold() == 9_000);
        test_scenario::return_shared(officer);
    };

    scenario.end();
}

// === Test 23: new type enabled via member override ===

#[test]
/// A non-default type in member_config_overrides is inserted and enabled on the member SubDAO.
fun create_tribe_configured_new_type_enabled_via_member_override() {
    let mut scenario = test_scenario::begin(CREATOR);

    let member_id: ID;
    scenario.next_tx(CREATOR);
    {
        let mut member_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut member_overrides,
            b"SendCoin".to_ascii_string(),
            default_config(),
        );

        (_, _, member_id) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe DAO"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                vec_map::empty(),
                vec_map::empty(),
                member_overrides,
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let member = scenario.take_shared_by_id<DAO>(member_id);
        assert!(member.enabled_proposal_types().contains(&b"SendCoin".to_ascii_string()));
        test_scenario::return_shared(member);
    };

    scenario.end();
}

// === Test 25: UpdateProposalConfig below floor in officer overrides aborts ===

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// Setting UpdateProposalConfig threshold below 80% in officer overrides aborts.
fun create_tribe_configured_aborts_on_update_config_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let mut officer_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut officer_overrides,
            b"UpdateProposalConfig".to_ascii_string(),
            proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0),
        );

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe DAO"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            vec_map::empty(),
            officer_overrides,
            vec_map::empty(),
            scenario.ctx(),
        );
    };
    scenario.end();
}

// === Test 26: EnableProposalType below floor in member overrides aborts ===

#[test, expected_failure(abort_code = dao::EThresholdBelowMinimum)]
/// Setting EnableProposalType threshold below 66% in member overrides aborts.
fun create_tribe_configured_aborts_on_enable_type_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let mut member_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut member_overrides,
            b"EnableProposalType".to_ascii_string(),
            proposal::new_config(5_000, 6_599, 0, 604_800_000, 0, 0),
        );

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe DAO"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            vec_map::empty(),
            vec_map::empty(),
            member_overrides,
            scenario.ctx(),
        );
    };
    scenario.end();
}

// === Test 27: UpdateProposalConfig at exact floor passes ===

#[test]
/// Setting UpdateProposalConfig threshold at exactly 80% (8000) succeeds.
fun create_tribe_configured_update_config_at_floor_passes() {
    let mut scenario = test_scenario::begin(CREATOR);

    let owner_id: ID;
    scenario.next_tx(CREATOR);
    {
        let mut tribe_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut tribe_overrides,
            b"UpdateProposalConfig".to_ascii_string(),
            proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0),
        );

        (owner_id, _, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe DAO"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                tribe_overrides,
                vec_map::empty(),
                vec_map::empty(),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<DAO>(owner_id);
        let config = tribe.proposal_configs().get(&b"UpdateProposalConfig".to_ascii_string());
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(tribe);
    };

    scenario.end();
}

// === Test 28: composable_allowed preserved when overriding a composable type ===

#[test]
/// Overriding AddMember (composable by default) via create_wired_subdao must not
/// silently strip composable_allowed — it should remain true after the override.
fun create_wired_subdao_preserves_composable_allowed_on_override() {
    let mut scenario = test_scenario::begin(CREATOR);

    let subdao_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = dao::create_returning_vault(
            &gov,
            string::utf8(b"Parent DAO"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        // Override AddMember with a higher quorum — composable_allowed must be preserved.
        let mut overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut overrides,
            b"AddMember".to_ascii_string(),
            proposal::new_config(7_500, 7_500, 0, 604_800_000, 0, 0),
        );

        let req = proposal::new_execution_request<TestProposal>(parent_id, parent_id);
        subdao_id =
            tribe::create_wired_subdao(
                vector[OFFICER_A],
                string::utf8(b"SubDAO"),
                string::utf8(b"https://example.com/sub.png"),
                SUBDAO_ADMIN,
                &mut parent_vault,
                &req,
                overrides,
                scenario.ctx(),
            );
        proposal::consume(req);
        capability_vault::share(parent_vault);
    };

    scenario.next_tx(CREATOR);
    {
        let subdao = scenario.take_shared_by_id<DAO>(subdao_id);
        let config = subdao.proposal_configs().get(&b"AddMember".to_ascii_string());
        assert!(config.quorum() == 7_500);
        assert!(config.approval_threshold() == 7_500);
        assert!(config.composable_allowed());
        test_scenario::return_shared(subdao);
    };

    scenario.end();
}

// === Test 29: parent DAO can override a subdao-blocked type at construction ===

#[test]
/// CreateSubDAO is blocked for SubDAOs but must be overridable for a parent tribe DAO,
/// which legitimately has it enabled by default.
fun create_tribe_configured_parent_can_override_subdao_blocked_type() {
    let mut scenario = test_scenario::begin(CREATOR);

    let owner_id: ID;
    scenario.next_tx(CREATOR);
    {
        let mut tribe_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut tribe_overrides,
            b"CreateSubDAO".to_ascii_string(),
            proposal::new_config(8_000, 8_000, 0, 604_800_000, 0, 0),
        );

        (owner_id, _, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe DAO"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                tribe_overrides,
                vec_map::empty(),
                vec_map::empty(),
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<DAO>(owner_id);
        let config = tribe.proposal_configs().get(&b"CreateSubDAO".to_ascii_string());
        assert!(config.quorum() == 8_000);
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(tribe);
    };

    scenario.end();
}

// === Test 30: subdao path still rejects subdao-blocked types ===

#[test, expected_failure(abort_code = dao::EBlockedProposalType)]
/// Passing CreateSubDAO in officer_config_overrides (a SubDAO) still aborts —
/// the fix only relaxes the check on the parent DAO path.
fun create_tribe_configured_subdao_still_rejects_blocked_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let mut officer_overrides = vec_map::empty<std::ascii::String, proposal::ProposalConfig>();
        vec_map::insert(
            &mut officer_overrides,
            b"CreateSubDAO".to_ascii_string(),
            proposal::new_config(8_000, 8_000, 0, 604_800_000, 0, 0),
        );

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe DAO"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            vec_map::empty(),
            officer_overrides,
            vec_map::empty(),
            scenario.ctx(),
        );
    };
    scenario.end();
}
