#[test_only]
module armature_proposals::migration_tests;

use armature::board_voting;
use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::charter::Charter;
use armature::controller;
use armature::create_subou::{Self, CreateSubOU};
use armature::ou::{Self, OU};
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::governance;
use armature::lifecycle_ops;
use armature::proposal::{Self, Proposal};
use armature::set_board::{Self, SetBoard};
use armature::spawn_ou::{Self, SpawnOU};
use armature::spin_out_subou::{Self, SpinOutSubOU};
use armature::transfer_assets::{Self, TransferAssets};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::subou_ops;
use armature_proposals::type_permissions;
use std::internal;
use std::string;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

const CREATOR: address = @0xA;
const MEMBER_B: address = @0xB;
const SUBOU_MEMBER: address = @0xC;

/// Test payload for a parent-side controller operation: granted VAULT_BORROW
/// so its ticket may loan the SubOUControl.
public struct ControllerOp has drop, store {}

// =========================================================================
// E2E: Full migration lifecycle
// Create OU → SpawnOU → vote → execute (successor created, origin Migrating)
// → ou::destroy (origin destroyed)
// =========================================================================

#[test]
fun spawn_ou_and_destroy_origin_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent OU
    scenario.next_tx(CREATOR);
    let origin_ou_id;
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        origin_ou_id =
            ou::create(
                &init,
                string::utf8(b"Origin OU"),
                string::utf8(b"https://example.com/origin.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable SpawnOU proposal type
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<SpawnOU>(b"SpawnOU".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    // 3. Submit SpawnOU proposal
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);

        let payload = spawn_ou::new(
            governance::init_board(vector[CREATOR, MEMBER_B]),
            string::utf8(b"Successor OU"),
            string::utf8(b"https://example.com/successor.png"),
        );

        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Spawn successor OU for migration")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // 4. Vote yes — CREATOR votes, 1/2 = 50% quorum met
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SpawnOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 5. Execute SpawnOU → creates successor OU, sets origin to Migrating
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<SpawnOU>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        lifecycle_ops::execute_spawn_ou(
            &mut ou,
            ticket,
            scenario.ctx(),
        );

        // Verify origin OU is now Migrating
        assert!(ou.status().is_migrating());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    // 6. Verify successor OU exists and origin can be destroyed
    scenario.next_tx(CREATOR);
    {
        // Origin OU: take by known ID
        let ou = scenario.take_shared_by_id<OU>(origin_ou_id);
        let treasury_id = ou.treasury_id();
        let vault_id = ou.capability_vault_id();
        let charter_id = ou.charter_id();
        let freeze_id = ou.emergency_freeze_id();

        // Verify Migrating status
        assert!(ou.status().is_migrating());

        // Take companion objects by ID (origin's companions)
        let treasury = scenario.take_shared_by_id<TreasuryVault>(treasury_id);
        let vault = scenario.take_shared_by_id<CapabilityVault>(vault_id);
        let charter = scenario.take_shared_by_id<Charter>(charter_id);
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(freeze_id);

        // Destroy — permissionless, vaults are empty
        ou::destroy(ou, treasury, vault, charter, freeze);
    };

    // 7. Verify successor OU is shared and Active
    scenario.next_tx(CREATOR);
    {
        let successor = scenario.take_shared<OU>();
        assert!(successor.status().is_active());
        test_scenario::return_shared(successor);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// E2E: Full SubOU creation + spin-out lifecycle
// Create parent OU → CreateSubOU → verify SubOUControl + FreezeAdminCap
// → SpinOutSubOU → verify SubOU is independent
// =========================================================================

#[test]
fun create_subou_and_spin_out_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent OU
    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"Parent OU"),
                string::utf8(b"https://example.com/parent.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable CreateSubOU + SpinOutSubOU proposal types
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<CreateSubOU>(b"CreateSubOU".to_ascii_string(), config);
        ou.test_enable_type<SpinOutSubOU>(b"SpinOutSubOU".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    // ---- Phase A: CreateSubOU ----

    // 3. Submit CreateSubOU proposal
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);

        let payload = create_subou::new(
            string::utf8(b"Child OU"),
            vector[SUBOU_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );

        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Create child OU")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // 4. Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 5. Execute CreateSubOU → creates SubOU, stores SubOUControl + FreezeAdminCap
    let subou_id;
    let control_cap_id;
    let freeze_admin_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        lifecycle_ops::execute_create_subou(
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        // Vault should now contain SubOUControl + FreezeAdminCap (2 caps)
        assert!(vault.cap_ids().length() == 2);

        // Get the cap IDs for the spin-out payload
        let control_ids = vault.ids_for_type<SubOUControl>();
        let freeze_ids = vault.ids_for_type<FreezeAdminCap>();
        assert!(control_ids.length() == 1);
        assert!(freeze_ids.length() == 1);

        control_cap_id = control_ids[0];
        freeze_admin_cap_id = freeze_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };

    // 6. Get the SubOU ID from the shared object
    scenario.next_tx(CREATOR);
    {
        // Take parent by known ID to skip it; take child as second OU
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let child = scenario.take_shared<OU>();
        subou_id = child.id();
        test_scenario::return_shared(parent);

        // Verify SubOU has controller set
        assert!(child.controller_cap_id().is_some());
        // Verify SubOU does NOT have SpawnOU/SpinOutSubOU/CreateSubOU enabled
        assert!(!child.is_type_enabled<SpawnOU>());
        assert!(!child.is_type_enabled<SpinOutSubOU>());
        assert!(!child.is_type_enabled<CreateSubOU>());

        test_scenario::return_shared(child);
    };

    // ---- Phase B: SpinOutSubOU ----

    // 7. Submit SpinOutSubOU proposal on the parent OU
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(5000);

        // SpawnOU, SpinOutSubOU and CreateSubOU hold high-impact bits, so
        // their configs need the 80% permission floor.
        let spin_config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
        let payload = spin_out_subou::new(
            subou_id,
            control_cap_id,
            freeze_admin_cap_id,
            spin_config, // spawn_ou_config for the SubOU
            spin_config, // spin_out_subou_config for the SubOU
            spin_config, // create_subou_config for the SubOU
        );

        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Spin out child OU to independence")),
            payload,
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(ou);
    };

    // 8. Vote yes
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SpinOutSubOU>>();
        clock.set_for_testing(6000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 9. Execute SpinOutSubOU
    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let mut proposal = scenario.take_shared<Proposal<SpinOutSubOU>>();
        let parent_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(parent_ou.emergency_freeze_id());
        let mut parent_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        let mut subou_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(subou.capability_vault_id());
        clock.set_for_testing(7000);

        let ticket = board_voting::ticket_from_vote(
            &mut parent_ou,
            proposal,
            &parent_freeze,
            &clock,
            scenario.ctx(),
        );

        lifecycle_ops::execute_spin_out_subou(
            &mut parent_vault,
            &mut subou_vault,
            &mut subou,
            ticket,
            scenario.ctx(),
        );

        // Verify: SubOU controller cleared
        assert!(subou.controller_cap_id().is_none());
        assert!(!subou.is_controller_paused());

        // Verify: SubOU now has SpawnOU, SpinOutSubOU, CreateSubOU enabled
        assert!(subou.is_type_enabled<SpawnOU>());
        assert!(subou.is_type_enabled<SpinOutSubOU>());
        assert!(subou.is_type_enabled<CreateSubOU>());

        // Verify: Parent vault no longer holds SubOUControl or FreezeAdminCap
        assert!(parent_vault.is_empty());

        // Verify: SubOU vault now holds the FreezeAdminCap
        assert!(subou_vault.cap_ids().length() == 1);
        let subou_freeze_ids = subou_vault.ids_for_type<FreezeAdminCap>();
        assert!(subou_freeze_ids.length() == 1);
        assert!(subou_freeze_ids[0] == freeze_admin_cap_id);

        test_scenario::return_shared(subou_vault);
        test_scenario::return_shared(subou);
        test_scenario::return_shared(parent_vault);
        test_scenario::return_shared(parent_freeze);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// E2E: Controller SetBoard via privileged_submit (#87)
// Create parent OU → CreateSubOU → parent uses privileged_submit to change
// SubOU's board → verify board changed
// =========================================================================

#[test]
fun controller_set_board_via_privileged_submit() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create parent OU
    let parent_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        parent_ou_id =
            ou::create(
                &init,
                string::utf8(b"Parent OU"),
                string::utf8(b"https://example.com/parent.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable CreateSubOU
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<CreateSubOU>(b"CreateSubOU".to_ascii_string(), config);
        test_scenario::return_shared(ou);
    };

    // 3. Submit + vote CreateSubOU proposal
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = create_subou::new(
            string::utf8(b"Child OU"),
            vector[SUBOU_MEMBER],
            string::utf8(b"https://example.com/child.png"),
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Create child")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 4. Execute CreateSubOU
    let control_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<CreateSubOU>>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        lifecycle_ops::execute_create_subou(
            &mut vault,
            ticket,
            scenario.ctx(),
        );

        let control_ids = vault.ids_for_type<SubOUControl>();
        control_cap_id = control_ids[0];

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(ou);
    };

    // 5. Get SubOU ID
    let subou_id;
    scenario.next_tx(CREATOR);
    {
        let parent = scenario.take_shared_by_id<OU>(parent_ou_id);
        let child = scenario.take_shared<OU>();
        subou_id = child.id();

        // Verify initial board: only SUBOU_MEMBER
        assert!(child.governance().is_board_member(SUBOU_MEMBER));
        assert!(!child.governance().is_board_member(CREATOR));

        test_scenario::return_shared(parent);
        test_scenario::return_shared(child);
    };

    // 6. Parent passes a ControllerOp, a type granted VAULT_BORROW, to loan
    // the SubOUControl. (Any other ticket, e.g. SetBoard, is now denied.)
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        clock.set_for_testing(5000);
        ou.test_enable_type<ControllerOp>(
            b"ControllerOp".to_ascii_string(),
            proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0)
                .with_permissions(type_permissions::subou_control())
                .with_borrow_scope(type_permissions::subou_control_scope()),
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Controller op")),
            ControllerOp {},
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    // CREATOR's yes meets quorum (1 of 2) and 100% approval of votes cast.
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ControllerOp>>();
        clock.set_for_testing(6000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 7. Execute: loan SubOUControl → privileged_submit SetBoard on SubOU
    // → set_board_governance → privileged_consume → return_cap → consume parent request
    scenario.next_tx(CREATOR);
    {
        let mut parent_ou = scenario.take_shared_by_id<OU>(parent_ou_id);
        let parent_proposal = scenario.take_shared<Proposal<ControllerOp>>();
        let parent_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(parent_ou.emergency_freeze_id());
        let mut vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(parent_ou.capability_vault_id());
        let mut subou = scenario.take_shared_by_id<OU>(subou_id);
        clock.set_for_testing(7000);

        // Get parent ExecutionRequest (for vault loan authorization)
        let parent_req = board_voting::ticket_from_vote(
            &mut parent_ou,
            parent_proposal,
            &parent_freeze,
            &clock,
            scenario.ctx(),
        );

        // Loan SubOUControl from parent vault
        let (control, loan) = vault.loan_cap<SubOUControl, ControllerOp>(
            control_cap_id,
            parent_req.ticket_request(internal::permit()),
        );

        // Privileged submit: set SubOU's board to [SUBOU_MEMBER, CREATOR]
        let priv_req = controller::privileged_submit(
            &control,
            &subou,
            b"SetBoard".to_ascii_string(),
            option::some(string::utf8(b"Controller sets SubOU board")),
            set_board::new(vector[CREATOR], vector[]),
            scenario.ctx(),
        );

        // Apply board change on SubOU using privileged ExecutionRequest
        ou::set_board_governance(&mut subou, vector[CREATOR], vector[], &priv_req);

        // Consume privileged request
        controller::privileged_consume(priv_req, &control);

        // Return SubOUControl to vault
        vault.return_cap(control, loan);

        parent_req.discharge(internal::permit());

        // Verify: SubOU board now includes CREATOR
        assert!(subou.governance().is_board_member(SUBOU_MEMBER));
        assert!(subou.governance().is_board_member(CREATOR));

        test_scenario::return_shared(subou);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(parent_freeze);
        test_scenario::return_shared(parent_ou);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// =========================================================================
// E2E: Full migration with TransferAssets (#88)
// Create OU → fund treasury → SpawnOU → TransferAssets (coins) → ou::destroy
// =========================================================================

#[test]
fun migration_with_transfer_assets_e2e() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());

    // 1. Create origin OU
    let origin_ou_id;
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        origin_ou_id =
            ou::create(
                &init,
                string::utf8(b"Origin OU"),
                string::utf8(b"https://example.com/origin.png"),
                scenario.ctx(),
            );
    };

    // 2. Enable SpawnOU + TransferAssets on origin
    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        ou.test_enable_type<SpawnOU>(b"SpawnOU".to_ascii_string(), config);
        ou.test_enable_type<TransferAssets>(b"TransferAssets".to_ascii_string(), config);
        test_scenario::return_shared(ou);
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

    // 4. Submit + vote + execute SpawnOU → origin becomes Migrating
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        clock.set_for_testing(1000);
        let payload = spawn_ou::new(
            governance::init_board(vector[CREATOR, MEMBER_B]),
            string::utf8(b"Successor OU"),
            string::utf8(b"https://example.com/successor.png"),
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Spawn successor")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<SpawnOU>>();
        clock.set_for_testing(2000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let mut proposal = scenario.take_shared<Proposal<SpawnOU>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        clock.set_for_testing(3000);

        let ticket = board_voting::ticket_from_vote(
            &mut ou,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );

        lifecycle_ops::execute_spawn_ou(&mut ou, ticket, scenario.ctx());
        assert!(ou.status().is_migrating());

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(ou);
    };

    // 5. Get successor OU's treasury + vault IDs
    let successor_treasury_id;
    let successor_vault_id;
    scenario.next_tx(CREATOR);
    {
        let origin = scenario.take_shared_by_id<OU>(origin_ou_id);
        let successor = scenario.take_shared<OU>();
        assert!(successor.status().is_active());
        successor_treasury_id = successor.treasury_id();
        successor_vault_id = successor.capability_vault_id();
        test_scenario::return_shared(origin);
        test_scenario::return_shared(successor);
    };

    // 6. Submit TransferAssets proposal on origin (Migrating — allowed for TransferAssets)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(origin_ou_id);
        clock.set_for_testing(5000);
        let payload = transfer_assets::new(
            ou.status().successor_ou_id(),
            successor_treasury_id,
            successor_vault_id,
            vector[std::type_name::with_original_ids<SUI>()],
            vector[],
        );
        board_voting::submit_proposal(
            &ou,
            option::some(string::utf8(b"Transfer all assets to successor")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(ou);
    };

    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<TransferAssets>>();
        clock.set_for_testing(6000);
        let vote_ou = scenario.take_shared_by_id<OU>(proposal.ou_id());
        board_voting::vote(&mut proposal, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(proposal);
    };

    // 7. Execute TransferAssets: validate → withdraw + deposit → finalize
    scenario.next_tx(CREATOR);
    {
        let mut origin_ou = scenario.take_shared_by_id<OU>(origin_ou_id);
        let mut proposal = scenario.take_shared<Proposal<TransferAssets>>();
        let origin_freeze = scenario.take_shared_by_id<
            EmergencyFreeze,
        >(origin_ou.emergency_freeze_id());
        let mut origin_treasury = scenario.take_shared_by_id<
            TreasuryVault,
        >(origin_ou.treasury_id());
        let origin_vault = scenario.take_shared_by_id<
            CapabilityVault,
        >(origin_ou.capability_vault_id());
        let mut successor_treasury = scenario.take_shared_by_id<TreasuryVault>(
            successor_treasury_id,
        );
        let successor_vault = scenario.take_shared_by_id<CapabilityVault>(successor_vault_id);
        clock.set_for_testing(7000);

        let ticket = board_voting::ticket_from_vote(
            &mut origin_ou,
            proposal,
            &origin_freeze,
            &clock,
            scenario.ctx(),
        );

        // Move every listed asset straight into the successor's vaults
        let mut transfer = lifecycle_ops::begin_transfer_assets(
            &origin_treasury,
            &origin_vault,
            ticket,
        );
        transfer.transfer_coin<SUI>(&mut origin_treasury, &mut successor_treasury, scenario.ctx());
        transfer.finish_transfer_assets();

        // Verify balances
        assert!(origin_treasury.balance<SUI>() == 0);
        assert!(successor_treasury.balance<SUI>() == 500_000);

        test_scenario::return_shared(successor_vault);
        test_scenario::return_shared(successor_treasury);
        test_scenario::return_shared(origin_vault);
        test_scenario::return_shared(origin_treasury);
        test_scenario::return_shared(origin_freeze);
        test_scenario::return_shared(origin_ou);
    };

    // 8. Destroy origin OU (treasury is now empty)
    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared_by_id<OU>(origin_ou_id);
        let treasury = scenario.take_shared_by_id<TreasuryVault>(ou.treasury_id());
        let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
        let charter = scenario.take_shared_by_id<Charter>(ou.charter_id());
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
        ou::destroy(ou, treasury, vault, charter, freeze);
    };

    // 9. Verify successor still active with funds
    scenario.next_tx(CREATOR);
    {
        let successor = scenario.take_shared<OU>();
        assert!(successor.status().is_active());
        let treasury = scenario.take_shared_by_id<TreasuryVault>(successor.treasury_id());
        assert!(treasury.balance<SUI>() == 500_000);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(successor);
    };

    clock.destroy_for_testing();
    scenario.end();
}
