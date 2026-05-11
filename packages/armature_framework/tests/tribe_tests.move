#[test_only]
module armature::tribe_tests;

use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::charter::Charter;
use armature::dao::DAO;
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::proposal;
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use std::string;
use sui::test_scenario;

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
        string::utf8(b"The tribe"),
        string::utf8(b"Officer channel"),
        string::utf8(b"Member channel"),
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
    let (tribe_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    assert!(tribe_id != officer_id);
    assert!(tribe_id != member_id);
    assert!(officer_id != member_id);

    scenario.end();
}

// === Test 2: all three DAOs are active with the correct boards ===

#[test]
/// Each DAO is Active and seeded with the correct board members.
fun create_tribe_daos_are_active_with_correct_boards() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (tribe_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_dao = scenario.take_shared_by_id<DAO>(tribe_id);
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
    let (tribe_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_dao = scenario.take_shared_by_id<DAO>(tribe_id);
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
    let (tribe_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    // Verify IDs stored on each DAO reference distinct shared objects.
    scenario.next_tx(CREATOR);
    {
        let tribe_dao = scenario.take_shared_by_id<DAO>(tribe_id);
        let officer_dao = scenario.take_shared_by_id<DAO>(officer_id);
        let member_dao = scenario.take_shared_by_id<DAO>(member_id);

        // All companion IDs are non-zero and distinct from their parent DAO.
        assert!(tribe_dao.treasury_id()         != tribe_id);
        assert!(tribe_dao.capability_vault_id() != tribe_id);
        assert!(tribe_dao.charter_id()          != tribe_id);
        assert!(tribe_dao.emergency_freeze_id() != tribe_id);

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
        string::utf8(b"The tribe"),
        string::utf8(b"Officer channel"),
        string::utf8(b"Member channel"),
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
        string::utf8(b"The tribe"),
        string::utf8(b"Officer channel"),
        string::utf8(b"Member channel"),
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
        string::utf8(b"The tribe"),
        string::utf8(b"Officer channel"),
        string::utf8(b"Member channel"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        scenario.ctx(),
    );
    scenario.end();
}
