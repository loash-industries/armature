#[test_only]
module armature::tribe_tests;

use armature::add_member::AddMember;
use armature::capability_vault::{Self, CapabilityVault, SubOUControl};
use armature::charter::Charter;
use armature::create_subou::CreateSubOU;
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::enable_bypass_type::EnableBypassType;
use armature::enable_proposal_type::EnableProposalType;
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal;
use armature::remove_member::RemoveMember;
use armature::set_board::SetBoard;
use armature::spawn_ou::SpawnOU;
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use armature::update_metadata::UpdateMetadata;
use armature::update_proposal_config::UpdateProposalConfig;
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

// === Non-default payload type enabled through construction-time overrides ===

public struct CustomType has drop, store {}

// === Helper ===

fun do_create_tribe(scenario: &mut test_scenario::Scenario): (ID, ID, ID) {
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[CREATOR, TRIBE_MEMBER],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A, MEMBER_B],
        string::utf8(b"Tribe OU"),
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
fun create_tribe_returns_distinct_ou_ids() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    assert!(owner_id != officer_id);
    assert!(owner_id != member_id);
    assert!(officer_id != member_id);

    scenario.end();
}

// === Test 2: all three OUs are active with the correct boards ===

#[test]
/// Each OU is Active and seeded with the correct board members.
fun create_tribe_ous_are_active_with_correct_boards() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_ou = scenario.take_shared_by_id<OU>(owner_id);
        let officer_ou = scenario.take_shared_by_id<OU>(officer_id);
        let member_ou = scenario.take_shared_by_id<OU>(member_id);

        assert!(tribe_ou.status().is_active());
        assert!(officer_ou.status().is_active());
        assert!(member_ou.status().is_active());

        assert!(tribe_ou.governance().is_board_member(CREATOR));
        assert!(tribe_ou.governance().is_board_member(TRIBE_MEMBER));
        assert!(!tribe_ou.governance().is_board_member(OFFICER_A));

        assert!(officer_ou.governance().is_board_member(OFFICER_A));
        assert!(officer_ou.governance().is_board_member(OFFICER_B));
        assert!(!officer_ou.governance().is_board_member(CREATOR));

        assert!(member_ou.governance().is_board_member(MEMBER_A));
        assert!(member_ou.governance().is_board_member(MEMBER_B));
        assert!(!member_ou.governance().is_board_member(CREATOR));

        test_scenario::return_shared(tribe_ou);
        test_scenario::return_shared(officer_ou);
        test_scenario::return_shared(member_ou);
    };

    scenario.end();
}

// === Test 3: control hierarchy — tribe→officers→members ===

#[test]
/// Tribe vault holds one SubOUControl pointing at the Officers SubOU.
/// Officers vault holds one SubOUControl pointing at the Members SubOU.
fun create_tribe_control_hierarchy_is_tribe_officers_members() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let tribe_ou = scenario.take_shared_by_id<OU>(owner_id);
        let officer_ou = scenario.take_shared_by_id<OU>(officer_id);
        let tribe_vault_id = tribe_ou.capability_vault_id();
        let officer_vault_id = officer_ou.capability_vault_id();
        test_scenario::return_shared(tribe_ou);
        test_scenario::return_shared(officer_ou);

        // Tribe vault: exactly one control, pointing at the Officers SubOU.
        let mut tribe_vault = scenario.take_shared_by_id<CapabilityVault>(tribe_vault_id);
        let tribe_ctrl_ids = tribe_vault.ids_for_type<SubOUControl>();
        assert!(tribe_ctrl_ids.length() == 1);

        let req = proposal::new_execution_request_for_testing<TestProposal>(
            tribe_vault.ou_id(),
            object::id_from_address(@0xBEEF),
        ).with_borrow_scope_for_testing(vector[std::type_name::with_defining_ids<SubOUControl>()]);
        let (tribe_ctrl, tribe_loan) = tribe_vault.loan_cap<SubOUControl, TestProposal>(
            tribe_ctrl_ids[0],
            &req,
        );
        assert!(tribe_ctrl.subou_id() == officer_id);
        tribe_vault.return_cap(tribe_ctrl, tribe_loan);
        proposal::consume(req);
        test_scenario::return_shared(tribe_vault);

        // Officers vault: exactly one control, pointing at the Members SubOU.
        let mut officer_vault = scenario.take_shared_by_id<CapabilityVault>(officer_vault_id);
        let officer_ctrl_ids = officer_vault.ids_for_type<SubOUControl>();
        assert!(officer_ctrl_ids.length() == 1);

        let req = proposal::new_execution_request_for_testing<TestProposal>(
            officer_vault.ou_id(),
            object::id_from_address(@0xBEEF),
        ).with_borrow_scope_for_testing(vector[std::type_name::with_defining_ids<SubOUControl>()]);
        let (officer_ctrl, officer_loan) = officer_vault.loan_cap<SubOUControl, TestProposal>(
            officer_ctrl_ids[0],
            &req,
        );
        assert!(officer_ctrl.subou_id() == member_id);
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
/// Each of the three OUs has its four companion objects shared on-chain.
fun create_tribe_all_companion_objects_are_shared() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);

    // Verify IDs stored on each OU reference distinct shared objects.
    scenario.next_tx(CREATOR);
    {
        let tribe_ou = scenario.take_shared_by_id<OU>(owner_id);
        let officer_ou = scenario.take_shared_by_id<OU>(officer_id);
        let member_ou = scenario.take_shared_by_id<OU>(member_id);

        // All companion IDs are non-zero and distinct from their parent OU.
        assert!(tribe_ou.treasury_id()         != owner_id);
        assert!(tribe_ou.capability_vault_id() != owner_id);
        assert!(tribe_ou.charter_id()          != owner_id);
        assert!(tribe_ou.emergency_freeze_id() != owner_id);

        assert!(officer_ou.treasury_id()         != officer_id);
        assert!(officer_ou.capability_vault_id() != officer_id);
        assert!(officer_ou.charter_id()          != officer_id);
        assert!(officer_ou.emergency_freeze_id() != officer_id);

        assert!(member_ou.treasury_id()         != member_id);
        assert!(member_ou.capability_vault_id() != member_id);
        assert!(member_ou.charter_id()          != member_id);
        assert!(member_ou.emergency_freeze_id() != member_id);

        let tribe_vault_id = tribe_ou.capability_vault_id();

        test_scenario::return_shared(tribe_ou);
        test_scenario::return_shared(officer_ou);
        test_scenario::return_shared(member_ou);

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
/// Passing an empty tribe_board vector causes an abort during OU creation.
fun create_tribe_aborts_on_empty_tribe_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[],
        vector[OFFICER_A],
        vector[MEMBER_A],
        string::utf8(b"Tribe OU"),
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
/// Passing an empty officers vector causes an abort during SubOU creation.
fun create_tribe_aborts_on_empty_officer_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[CREATOR],
        vector[],
        vector[MEMBER_A],
        string::utf8(b"Tribe OU"),
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
/// Passing an empty members vector causes an abort during SubOU creation.
fun create_tribe_aborts_on_empty_member_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    tribe::create_tribe(
        vector[CREATOR],
        vector[OFFICER_A],
        vector[],
        string::utf8(b"Tribe OU"),
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
// create_wired_subou tests
// ============================================================

const SUBOU_ADMIN: address = @0x20;

// Minimum valid config reused across tests.
fun default_config(): proposal::ProposalConfig {
    proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0)
}

/// Create a parent OU (vault kept un-shared), wire a SubOU into it, then share
/// the vault. Returns (parent_ou_id, subou_id).
fun do_create_parent_and_wired_subou(scenario: &mut test_scenario::Scenario): (ID, ID) {
    scenario.next_tx(CREATOR);
    let gov = governance::init_board(vector[CREATOR, TRIBE_MEMBER]);
    let (parent_id, mut parent_vault) = ou::create_returning_vault(
        &gov,
        string::utf8(b"Parent OU"),
        string::utf8(b"https://example.com/parent.png"),
        scenario.ctx(),
    );
    let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
    let subou_id = tribe::create_wired_subou(
        vector[OFFICER_A],
        string::utf8(b"SubOU"),
        string::utf8(b"https://example.com/sub.png"),
        SUBOU_ADMIN,
        &mut parent_vault,
        &req,
        vector[],
        scenario.ctx(),
    );
    proposal::consume(req);
    capability_vault::share(parent_vault);
    (parent_id, subou_id)
}

// === Test 9: create_wired_subou returns a non-zero ID ===

#[test]
/// create_wired_subou returns an ID that matches the shared SubOU object.
fun create_wired_subou_returns_correct_subou_id() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, subou_id) = do_create_parent_and_wired_subou(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        assert!(subou.id() == subou_id);
        assert!(subou.status().is_active());
        test_scenario::return_shared(subou);
    };

    scenario.end();
}

// === Test 10: parent vault contains exactly one SubOUControl pointing at the new subou ===

#[test]
/// After create_wired_subou the parent vault holds exactly one SubOUControl
/// whose subou_id matches the returned subou ID.
fun create_wired_subou_wires_control_into_parent_vault() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (parent_id, subou_id) = do_create_parent_and_wired_subou(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let parent_ou = scenario.take_shared_by_id<OU>(parent_id);
        let vault_id = parent_ou.capability_vault_id();
        test_scenario::return_shared(parent_ou);

        let mut vault = scenario.take_shared_by_id<CapabilityVault>(vault_id);
        let ctrl_ids = vault.ids_for_type<SubOUControl>();
        assert!(ctrl_ids.length() == 1);

        let req = proposal::new_execution_request_for_testing<TestProposal>(
            vault.ou_id(),
            object::id_from_address(@0xBEEF),
        ).with_borrow_scope_for_testing(vector[std::type_name::with_defining_ids<SubOUControl>()]);
        let (ctrl, loan) = vault.loan_cap<SubOUControl, TestProposal>(ctrl_ids[0], &req);
        assert!(ctrl.subou_id() == subou_id);
        vault.return_cap(ctrl, loan);
        proposal::consume(req);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// === Test 11: new subou has controller_cap_id set ===

#[test]
/// The wired SubOU has controller_cap_id populated (it is a controlled subou).
fun create_wired_subou_subou_is_controlled() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, subou_id) = do_create_parent_and_wired_subou(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        assert!(subou.controller_cap_id().is_some());
        test_scenario::return_shared(subou);
    };

    scenario.end();
}

// === Test 12: FreezeAdminCap goes to freeze_admin ===

#[test]
/// create_wired_subou transfers the SubOU FreezeAdminCap to the freeze_admin address.
fun create_wired_subou_freeze_cap_routed_to_admin() {
    let mut scenario = test_scenario::begin(CREATOR);
    do_create_parent_and_wired_subou(&mut scenario);

    scenario.next_tx(SUBOU_ADMIN);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        test_scenario::return_to_sender(&scenario, cap);
    };

    scenario.end();
}

// === Test 13: subou companion objects are shared ===

#[test]
/// create_wired_subou shares the SubOU's treasury, charter, and emergency freeze.
fun create_wired_subou_companion_objects_are_shared() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (_, subou_id) = do_create_parent_and_wired_subou(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let subou = scenario.take_shared_by_id<OU>(subou_id);

        // Companion IDs are populated and distinct from the subou itself.
        assert!(subou.treasury_id()         != subou_id);
        assert!(subou.capability_vault_id() != subou_id);
        assert!(subou.charter_id()          != subou_id);
        assert!(subou.emergency_freeze_id() != subou_id);

        let treasury_id = subou.treasury_id();
        let vault_id = subou.capability_vault_id();
        let charter_id = subou.charter_id();
        let freeze_id = subou.emergency_freeze_id();
        test_scenario::return_shared(subou);

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

// === Test 14: config override is reflected in the subou ===

#[test]
/// A config override passed to create_wired_subou is applied to the resulting SubOU.
fun create_wired_subou_config_override_applied() {
    let mut scenario = test_scenario::begin(CREATOR);

    let subou_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        // Override the SetBoard config with a custom quorum.
        let overrides = vector[
            ou::new_type_init<SetBoard>(
                b"SetBoard".to_ascii_string(),
                proposal::new_config(7_500, 7_500, 0, 604_800_000, 0, 0),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        subou_id =
            tribe::create_wired_subou(
                vector[OFFICER_A],
                string::utf8(b"SubOU"),
                string::utf8(b"https://example.com/sub.png"),
                SUBOU_ADMIN,
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
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        let config = subou.type_config<SetBoard>();
        assert!(config.quorum() == 7_500);
        assert!(config.approval_threshold() == 7_500);
        test_scenario::return_shared(subou);
    };

    scenario.end();
}

// === Test 15: new type enabled via override ===

#[test]
/// An override for a type not in the subou defaults is inserted and enabled on the subou.
fun create_wired_subou_new_type_enabled_via_override() {
    let mut scenario = test_scenario::begin(CREATOR);

    let subou_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let overrides = vector[
            ou::new_type_init<CustomType>(
                b"CustomType".to_ascii_string(),
                default_config(),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        subou_id =
            tribe::create_wired_subou(
                vector[OFFICER_A],
                string::utf8(b"SubOU"),
                string::utf8(b"https://example.com/sub.png"),
                SUBOU_ADMIN,
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
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        assert!(subou.is_type_enabled<CustomType>());
        assert!(subou.type_display_key<CustomType>() == b"CustomType".to_ascii_string());
        test_scenario::return_shared(subou);
    };

    scenario.end();
}

// === Test 16: blocked proposal type in overrides aborts ===

#[test, expected_failure(abort_code = ou::EBlockedProposalType)]
/// Passing a blocked type (SpawnOU) in config_overrides aborts with EBlockedProposalType.
fun create_wired_subou_aborts_on_blocked_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let overrides = vector[
            ou::new_type_init<SpawnOU>(
                b"SpawnOU".to_ascii_string(),
                default_config(),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        tribe::create_wired_subou(
            vector[OFFICER_A],
            string::utf8(b"SubOU"),
            string::utf8(b"https://example.com/sub.png"),
            SUBOU_ADMIN,
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

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// Setting EnableProposalType threshold below 80% aborts with EThresholdBelowMinimum.
fun create_wired_subou_aborts_on_enable_proposal_type_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let overrides = vector[
            ou::new_type_init<EnableProposalType>(
                b"EnableProposalType".to_ascii_string(),
                proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        tribe::create_wired_subou(
            vector[OFFICER_A],
            string::utf8(b"SubOU"),
            string::utf8(b"https://example.com/sub.png"),
            SUBOU_ADMIN,
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

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// Setting UpdateProposalConfig threshold below 80% aborts with EThresholdBelowMinimum.
fun create_wired_subou_aborts_on_update_proposal_config_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let overrides = vector[
            ou::new_type_init<UpdateProposalConfig>(
                b"UpdateProposalConfig".to_ascii_string(),
                proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        tribe::create_wired_subou(
            vector[OFFICER_A],
            string::utf8(b"SubOU"),
            string::utf8(b"https://example.com/sub.png"),
            SUBOU_ADMIN,
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
/// Setting EnableProposalType threshold at exactly 80% (8000) succeeds.
fun create_wired_subou_enable_proposal_type_at_floor_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let subou_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        let overrides = vector[
            ou::new_type_init<EnableProposalType>(
                b"EnableProposalType".to_ascii_string(),
                proposal::new_config(10_000, 8_000, 0, 604_800_000, 0, 0),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        subou_id =
            tribe::create_wired_subou(
                vector[OFFICER_A],
                string::utf8(b"SubOU"),
                string::utf8(b"https://example.com/sub.png"),
                SUBOU_ADMIN,
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
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        let config = subou.type_config<EnableProposalType>();
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(subou);
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
        string::utf8(b"Tribe OU"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[],
        vector[],
        vector[],
        scenario.ctx(),
    )
}

// === Test 20: create_tribe_configured with empty overrides matches create_tribe structure ===

#[test]
/// create_tribe_configured with all-empty override vectors produces the same
/// three-OU structure (distinct IDs, correct boards, control hierarchy) as create_tribe.
fun create_tribe_configured_empty_overrides_matches_create_tribe() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe_configured(&mut scenario);

    assert!(owner_id != officer_id);
    assert!(owner_id != member_id);
    assert!(officer_id != member_id);

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<OU>(owner_id);
        let officer = scenario.take_shared_by_id<OU>(officer_id);
        let member = scenario.take_shared_by_id<OU>(member_id);

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

// === Test 21: override applied to tribe OU ===

#[test]
/// A config override for the tribe OU is reflected in its type slot.
fun create_tribe_configured_override_applied_to_tribe_ou() {
    let mut scenario = test_scenario::begin(CREATOR);

    let owner_id: ID;
    scenario.next_tx(CREATOR);
    {
        let tribe_overrides = vector[
            ou::new_type_init<AddMember>(
                b"AddMember".to_ascii_string(),
                proposal::new_config(8_000, 8_000, 0, 604_800_000, 0, 0),
            ),
        ];

        (owner_id, _, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe OU"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                tribe_overrides,
                vector[],
                vector[],
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<OU>(owner_id);
        let config = tribe.type_config<AddMember>();
        assert!(config.quorum() == 8_000);
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(tribe);
    };

    scenario.end();
}

// === Test 22: override applied to officer subou ===

#[test]
/// A config override for the officer SubOU is reflected in its type slot.
fun create_tribe_configured_override_applied_to_officer_subou() {
    let mut scenario = test_scenario::begin(CREATOR);

    let officer_id: ID;
    scenario.next_tx(CREATOR);
    {
        let officer_overrides = vector[
            ou::new_type_init<RemoveMember>(
                b"RemoveMember".to_ascii_string(),
                proposal::new_config(9_000, 9_000, 0, 604_800_000, 0, 0),
            ),
        ];

        (_, officer_id, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe OU"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                vector[],
                officer_overrides,
                vector[],
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let officer = scenario.take_shared_by_id<OU>(officer_id);
        let config = officer.type_config<RemoveMember>();
        assert!(config.quorum() == 9_000);
        assert!(config.approval_threshold() == 9_000);
        test_scenario::return_shared(officer);
    };

    scenario.end();
}

// === Test 23: new type enabled via member override ===

#[test]
/// A non-default type in member_config_overrides is inserted and enabled on the member SubOU.
fun create_tribe_configured_new_type_enabled_via_member_override() {
    let mut scenario = test_scenario::begin(CREATOR);

    let member_id: ID;
    scenario.next_tx(CREATOR);
    {
        let member_overrides = vector[
            ou::new_type_init<CustomType>(
                b"CustomType".to_ascii_string(),
                default_config(),
            ),
        ];

        (_, _, member_id) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe OU"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                vector[],
                vector[],
                member_overrides,
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let member = scenario.take_shared_by_id<OU>(member_id);
        assert!(member.is_type_enabled<CustomType>());
        test_scenario::return_shared(member);
    };

    scenario.end();
}

// === Test 25: UpdateProposalConfig below floor in officer overrides aborts ===

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// Setting UpdateProposalConfig threshold below 80% in officer overrides aborts.
fun create_tribe_configured_aborts_on_update_config_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let officer_overrides = vector[
            ou::new_type_init<UpdateProposalConfig>(
                b"UpdateProposalConfig".to_ascii_string(),
                proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0),
            ),
        ];

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe OU"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            vector[],
            officer_overrides,
            vector[],
            scenario.ctx(),
        );
    };
    scenario.end();
}

// === Test 26: EnableProposalType below floor in member overrides aborts ===

#[test, expected_failure(abort_code = ou::EThresholdBelowMinimum)]
/// Setting EnableProposalType threshold below 80% in member overrides aborts.
fun create_tribe_configured_aborts_on_enable_type_below_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let member_overrides = vector[
            ou::new_type_init<EnableProposalType>(
                b"EnableProposalType".to_ascii_string(),
                proposal::new_config(5_000, 7_999, 0, 604_800_000, 0, 0),
            ),
        ];

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe OU"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            vector[],
            vector[],
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
        let tribe_overrides = vector[
            ou::new_type_init<UpdateProposalConfig>(
                b"UpdateProposalConfig".to_ascii_string(),
                proposal::new_config(10_000, 8_000, 0, 604_800_000, 0, 0),
            ),
        ];

        (owner_id, _, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe OU"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                tribe_overrides,
                vector[],
                vector[],
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<OU>(owner_id);
        let config = tribe.type_config<UpdateProposalConfig>();
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(tribe);
    };

    scenario.end();
}

// === Test 28: composable_allowed preserved when overriding a composable type ===

#[test]
/// Overriding AddMember (composable by default) via create_wired_subou must not
/// silently strip composable_allowed — it should remain true after the override.
fun create_wired_subou_preserves_composable_allowed_on_override() {
    let mut scenario = test_scenario::begin(CREATOR);

    let subou_id: ID;
    scenario.next_tx(CREATOR);
    {
        let gov = governance::init_board(vector[CREATOR]);
        let (parent_id, mut parent_vault) = ou::create_returning_vault(
            &gov,
            string::utf8(b"Parent OU"),
            string::utf8(b"https://example.com/parent.png"),
            scenario.ctx(),
        );

        // Override AddMember with a higher quorum — composable_allowed must be preserved.
        let overrides = vector[
            ou::new_type_init<AddMember>(
                b"AddMember".to_ascii_string(),
                proposal::new_config(7_500, 7_500, 0, 604_800_000, 0, 0),
            ),
        ];

        let req = proposal::new_execution_request_for_testing<TestProposal>(parent_id, parent_id);
        subou_id =
            tribe::create_wired_subou(
                vector[OFFICER_A],
                string::utf8(b"SubOU"),
                string::utf8(b"https://example.com/sub.png"),
                SUBOU_ADMIN,
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
        let subou = scenario.take_shared_by_id<OU>(subou_id);
        let config = subou.type_config<AddMember>();
        assert!(config.quorum() == 7_500);
        assert!(config.approval_threshold() == 7_500);
        assert!(config.composable_allowed());
        test_scenario::return_shared(subou);
    };

    scenario.end();
}

// === Test 29: parent OU can override a subou-blocked type at construction ===

#[test]
/// CreateSubOU is blocked for SubOUs but must be overridable for a parent tribe OU,
/// which legitimately has it enabled by default.
fun create_tribe_configured_parent_can_override_subou_blocked_type() {
    let mut scenario = test_scenario::begin(CREATOR);

    let owner_id: ID;
    scenario.next_tx(CREATOR);
    {
        let tribe_overrides = vector[
            ou::new_type_init<CreateSubOU>(
                b"CreateSubOU".to_ascii_string(),
                proposal::new_config(8_000, 8_000, 0, 604_800_000, 0, 0),
            ),
        ];

        (owner_id, _, _) =
            tribe::create_tribe_configured(
                vector[CREATOR],
                vector[OFFICER_A],
                vector[MEMBER_A],
                string::utf8(b"Tribe OU"),
                string::utf8(b"Officers"),
                string::utf8(b"Members"),
                string::utf8(b"https://tribe.example/logo.png"),
                string::utf8(b"https://tribe.example/officers.png"),
                string::utf8(b"https://tribe.example/members.png"),
                OFFICER_ADMIN,
                MEMBER_ADMIN,
                tribe_overrides,
                vector[],
                vector[],
                scenario.ctx(),
            );
    };

    scenario.next_tx(CREATOR);
    {
        let tribe = scenario.take_shared_by_id<OU>(owner_id);
        let config = tribe.type_config<CreateSubOU>();
        assert!(config.quorum() == 8_000);
        assert!(config.approval_threshold() == 8_000);
        test_scenario::return_shared(tribe);
    };

    scenario.end();
}

// === Test 30: subou path still rejects subou-blocked types ===

#[test, expected_failure(abort_code = ou::EBlockedProposalType)]
/// Passing CreateSubOU in officer_config_overrides (a SubOU) still aborts —
/// the fix only relaxes the check on the parent OU path.
fun create_tribe_configured_subou_still_rejects_blocked_type() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let officer_overrides = vector[
            ou::new_type_init<CreateSubOU>(
                b"CreateSubOU".to_ascii_string(),
                proposal::new_config(8_000, 8_000, 0, 604_800_000, 0, 0),
            ),
        ];

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe OU"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            vector[],
            officer_overrides,
            vector[],
            scenario.ctx(),
        );
    };
    scenario.end();
}

// === Test 31: override of a default type must keep its display key ===

#[test, expected_failure(abort_code = ou::EDisplayKeyMismatch)]
/// UpdateMetadata is seeded as "CharterUpdate". An override naming a different
/// display key aborts rather than silently keeping the default key.
fun create_tribe_configured_default_type_display_key_mismatch_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let tribe_overrides = vector[
            ou::new_type_init<UpdateMetadata>(
                b"UpdateMetadata".to_ascii_string(),
                proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0),
            ),
        ];

        tribe::create_tribe_configured(
            vector[CREATOR],
            vector[OFFICER_A],
            vector[MEMBER_A],
            string::utf8(b"Tribe OU"),
            string::utf8(b"Officers"),
            string::utf8(b"Members"),
            string::utf8(b"https://tribe.example/logo.png"),
            string::utf8(b"https://tribe.example/officers.png"),
            string::utf8(b"https://tribe.example/members.png"),
            OFFICER_ADMIN,
            MEMBER_ADMIN,
            tribe_overrides,
            vector[],
            vector[],
            scenario.ctx(),
        );
    };
    scenario.end();
}

// === Test 32: EnableBypassType quorum × threshold must reach the 80% floor ===

/// Create a tribe whose Tribe OU overrides EnableBypassType with `config`.
fun create_tribe_with_bypass_config(
    scenario: &mut test_scenario::Scenario,
    config: proposal::ProposalConfig,
): ID {
    scenario.next_tx(CREATOR);
    let (owner_id, _, _) = tribe::create_tribe_configured(
        vector[CREATOR, TRIBE_MEMBER],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A, MEMBER_B],
        string::utf8(b"Tribe OU"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[ou::new_type_init<EnableBypassType>(b"EnableBypassType".to_ascii_string(), config)],
        vector[],
        vector[],
        scenario.ctx(),
    );
    owner_id
}

#[test, expected_failure(abort_code = ou::EBypassQuorumTooLow)]
/// 50% quorum × 80% threshold = 40% of the board: a vote could pass and then
/// fail the execution floor, so the config is refused.
fun create_tribe_configured_aborts_on_bypass_quorum_too_low() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_tribe_with_bypass_config(
        &mut scenario,
        proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0),
    );
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EBypassQuorumTooLow)]
/// The single-vote shape (1 bps quorum) is refused for EnableBypassType.
fun create_tribe_configured_aborts_on_bypass_single_vote_config() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_tribe_with_bypass_config(
        &mut scenario,
        proposal::new_config(1, 10_000, 0, 3_600_000, 0, 0),
    );
    scenario.end();
}

#[test]
/// 90% quorum × 90% threshold = 81% ≥ 80%: accepted and stored.
fun create_tribe_configured_accepts_bypass_quorum_at_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    let owner_id = create_tribe_with_bypass_config(
        &mut scenario,
        proposal::new_config(9_000, 9_000, 0, 604_800_000, 0, 0),
    );
    scenario.next_tx(CREATOR);
    {
        let owner = scenario.take_shared_by_id<OU>(owner_id);
        assert!(owner.type_config<EnableBypassType>().quorum() == 9_000);
        assert!(owner.type_config<EnableBypassType>().approval_threshold() == 9_000);
        test_scenario::return_shared(owner);
    };
    scenario.end();
}

// === Test 33: EnableProposalType quorum × threshold must reach 80% of the board ===

/// Create a tribe whose Officers SubOU overrides EnableProposalType with `config`.
fun create_tribe_with_officer_enable_config(
    scenario: &mut test_scenario::Scenario,
    config: proposal::ProposalConfig,
): ID {
    scenario.next_tx(CREATOR);
    let (_, officer_id, _) = tribe::create_tribe_configured(
        vector[CREATOR, TRIBE_MEMBER],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A, MEMBER_B],
        string::utf8(b"Tribe OU"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[],
        vector[
            ou::new_type_init<EnableProposalType>(
                b"EnableProposalType".to_ascii_string(),
                config,
            ),
        ],
        vector[],
        scenario.ctx(),
    );
    officer_id
}

#[test]
/// Every OU's default EnableProposalType config needs YES from 80% of the
/// whole board: 80% quorum × 100% threshold.
fun create_tribe_enable_proposal_type_default_is_whole_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let owner = scenario.take_shared_by_id<OU>(owner_id);
        let officers = scenario.take_shared_by_id<OU>(officer_id);
        let members = scenario.take_shared_by_id<OU>(member_id);
        assert!(owner.type_config<EnableProposalType>().quorum() == 8_000);
        assert!(officers.type_config<EnableProposalType>().quorum() == 8_000);
        assert!(members.type_config<EnableProposalType>().quorum() == 8_000);
        assert!(officers.type_config<EnableProposalType>().approval_threshold() == 10_000);
        test_scenario::return_shared(members);
        test_scenario::return_shared(officers);
        test_scenario::return_shared(owner);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EEnableQuorumTooLow)]
/// 50% quorum × 80% threshold = 40% of the board: refused.
fun create_tribe_configured_aborts_on_enable_quorum_too_low() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_tribe_with_officer_enable_config(
        &mut scenario,
        proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0),
    );
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EEnableQuorumTooLow)]
/// The single-vote shape (1 bps quorum) is refused for EnableProposalType.
fun create_tribe_configured_aborts_on_enable_single_vote_config() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_tribe_with_officer_enable_config(
        &mut scenario,
        proposal::new_config(1, 10_000, 0, 3_600_000, 0, 0),
    );
    scenario.end();
}

#[test]
/// 90% quorum × 90% threshold = 81% ≥ 80%: accepted and stored.
fun create_tribe_configured_accepts_enable_quorum_at_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    let officer_id = create_tribe_with_officer_enable_config(
        &mut scenario,
        proposal::new_config(9_000, 9_000, 0, 604_800_000, 0, 0),
    );
    scenario.next_tx(CREATOR);
    {
        let officers = scenario.take_shared_by_id<OU>(officer_id);
        assert!(officers.type_config<EnableProposalType>().quorum() == 9_000);
        test_scenario::return_shared(officers);
    };
    scenario.end();
}

// === Test 34: UpdateProposalConfig quorum × threshold must reach 80% of the board ===

/// Create a tribe whose Officers SubOU overrides UpdateProposalConfig with `config`.
fun create_tribe_with_officer_update_config(
    scenario: &mut test_scenario::Scenario,
    config: proposal::ProposalConfig,
): ID {
    scenario.next_tx(CREATOR);
    let (_, officer_id, _) = tribe::create_tribe_configured(
        vector[CREATOR, TRIBE_MEMBER],
        vector[OFFICER_A, OFFICER_B],
        vector[MEMBER_A, MEMBER_B],
        string::utf8(b"Tribe OU"),
        string::utf8(b"Officers"),
        string::utf8(b"Members"),
        string::utf8(b"https://tribe.example/logo.png"),
        string::utf8(b"https://tribe.example/officers.png"),
        string::utf8(b"https://tribe.example/members.png"),
        OFFICER_ADMIN,
        MEMBER_ADMIN,
        vector[],
        vector[
            ou::new_type_init<UpdateProposalConfig>(
                b"UpdateProposalConfig".to_ascii_string(),
                config,
            ),
        ],
        vector[],
        scenario.ctx(),
    );
    officer_id
}

#[test]
/// Every OU's default UpdateProposalConfig config needs YES from 80% of the
/// whole board: 80% quorum × 100% threshold.
fun create_tribe_update_config_default_is_whole_board() {
    let mut scenario = test_scenario::begin(CREATOR);
    let (owner_id, officer_id, member_id) = do_create_tribe(&mut scenario);
    scenario.next_tx(CREATOR);
    {
        let owner = scenario.take_shared_by_id<OU>(owner_id);
        let officers = scenario.take_shared_by_id<OU>(officer_id);
        let members = scenario.take_shared_by_id<OU>(member_id);
        assert!(owner.type_config<UpdateProposalConfig>().quorum() == 8_000);
        assert!(officers.type_config<UpdateProposalConfig>().quorum() == 8_000);
        assert!(members.type_config<UpdateProposalConfig>().quorum() == 8_000);
        assert!(officers.type_config<UpdateProposalConfig>().approval_threshold() == 10_000);
        test_scenario::return_shared(members);
        test_scenario::return_shared(officers);
        test_scenario::return_shared(owner);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EUpdateConfigQuorumTooLow)]
/// 50% quorum × 80% threshold = 40% of the board: refused.
fun create_tribe_configured_aborts_on_update_config_quorum_too_low() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_tribe_with_officer_update_config(
        &mut scenario,
        proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0),
    );
    scenario.end();
}

#[test, expected_failure(abort_code = ou::EUpdateConfigQuorumTooLow)]
/// The single-vote shape (1 bps quorum) is refused for UpdateProposalConfig.
fun create_tribe_configured_aborts_on_update_config_single_vote_config() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_tribe_with_officer_update_config(
        &mut scenario,
        proposal::new_config(1, 10_000, 0, 3_600_000, 0, 0),
    );
    scenario.end();
}

#[test]
/// 90% quorum × 90% threshold = 81% ≥ 80%: accepted and stored.
fun create_tribe_configured_accepts_update_config_quorum_at_floor() {
    let mut scenario = test_scenario::begin(CREATOR);
    let officer_id = create_tribe_with_officer_update_config(
        &mut scenario,
        proposal::new_config(9_000, 9_000, 0, 604_800_000, 0, 0),
    );
    scenario.next_tx(CREATOR);
    {
        let officers = scenario.take_shared_by_id<OU>(officer_id);
        assert!(officers.type_config<UpdateProposalConfig>().quorum() == 9_000);
        test_scenario::return_shared(officers);
    };
    scenario.end();
}
