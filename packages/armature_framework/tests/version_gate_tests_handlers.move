/// ARMATURE-45: one abort test per gated function, part 3 (handlers:
/// `admin_ops`, `board_ops`, `freeze_ops`, `lifecycle_ops`, `member_ops`).
/// See `version_gate_tests` for the conventions and helpers.
#[test_only]
module armature::version_gate_tests_handlers;

use armature::add_member;
use armature::admin_ops;
use armature::batch_add_members;
use armature::batch_remove_members;
use armature::board_ops;
use armature::capability_vault::CapabilityVault;
use armature::create_subou;
use armature::disable_proposal_type;
use armature::emergency::FreezeAdminCap;
use armature::enable_proposal_type;
use armature::freeze_ops;
use armature::governance;
use armature::lifecycle_ops::{Self, AssetTransfer};
use armature::member_ops;
use armature::ou::OU;
use armature::remove_member;
use armature::set_board;
use armature::spawn_ou;
use armature::spin_out_subou;
use armature::transfer_assets;
use armature::transfer_freeze_admin;
use armature::treasury_vault::{Self, TreasuryVault};
use armature::unfreeze_proposal_type;
use armature::update_freeze_config;
use armature::update_freeze_exempt_types;
use armature::update_metadata;
use armature::update_proposal_config::{Self, UpdateProposalConfig};
use armature::version;
use armature::version_gate_tests::{
    begin,
    config,
    creator,
    member,
    other_id,
    retired,
    retired_charter,
    retired_freeze,
    retired_ou,
    retired_treasury,
    retired_vault,
    s,
    second_vault,
    ticket,
    Dummy,
    TestCap
};
use std::type_name;
use sui::clock;
use sui::sui::SUI;

fun type_key(): std::ascii::String { b"Dummy".to_ascii_string() }

fun update_config_payload(): UpdateProposalConfig {
    update_proposal_config::new(
        type_key(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
    )
}

/// An AssetTransfer begun (live) from `treasury` and `vault` with nothing
/// listed, then stamped above VERSION, as if a newer release had begun it.
fun retired_transfer(treasury: &TreasuryVault, vault: &CapabilityVault, ou_id: ID): AssetTransfer {
    let payload = transfer_assets::new(other_id(), other_id(), other_id(), vector[], vector[]);
    let transfer = lifecycle_ops::begin_transfer_assets(treasury, vault, ticket(ou_id, payload));
    lifecycle_ops::asset_transfer_with_min_version_for_testing(transfer, retired())
}

// === admin_ops ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_disable_proposal_type_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    admin_ops::execute_disable_proposal_type(
        &mut ou,
        ticket(ou_id, disable_proposal_type::new(type_key())),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_enable_proposal_type_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let payload = enable_proposal_type::new(
        type_key(),
        type_name::with_defining_ids<Dummy>(),
        config(),
    );
    admin_ops::execute_enable_proposal_type<Dummy>(&mut ou, ticket(ou_id, payload));
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_update_proposal_config_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    admin_ops::execute_update_proposal_config(&mut ou, ticket(ou_id, update_config_payload()));
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_update_metadata_retired() {
    let (sc, ou_id) = begin();
    let mut charter = retired_charter(&sc);
    admin_ops::execute_update_metadata(
        &mut charter,
        ticket(ou_id, update_metadata::new(s(b"ipfs://new"))),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun propose_update_proposal_config_retired() {
    let (mut sc, _) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let ou = retired_ou(&sc);
    admin_ops::propose_update_proposal_config(
        &ou,
        option::none(),
        update_config_payload(),
        &clock,
        sc.ctx(),
    );
    abort
}

// === board_ops ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_set_board_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    board_ops::execute_set_board(&mut ou, ticket(ou_id, set_board::new(vector[], vector[])));
    abort
}

// === freeze_ops ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_transfer_freeze_admin_retired() {
    let (sc, ou_id) = begin();
    let cap = sc.take_from_sender<FreezeAdminCap>();
    let mut freeze = retired_freeze(&sc);
    freeze_ops::execute_transfer_freeze_admin(
        &mut freeze,
        cap,
        ticket(ou_id, transfer_freeze_admin::new(member())),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_unfreeze_proposal_type_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    freeze_ops::execute_unfreeze_proposal_type(
        &mut freeze,
        ticket(ou_id, unfreeze_proposal_type::new<Dummy>()),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_update_freeze_config_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    freeze_ops::execute_update_freeze_config(
        &mut freeze,
        ticket(ou_id, update_freeze_config::new(1)),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_update_freeze_exempt_types_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    freeze_ops::execute_update_freeze_exempt_types(
        &mut freeze,
        ticket(ou_id, update_freeze_exempt_types::new()),
    );
    abort
}

// === lifecycle_ops ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_create_subou_retired() {
    let (mut sc, ou_id) = begin();
    let mut vault = retired_vault(&sc);
    let payload = create_subou::new(s(b"Sub"), vector[creator()], s(b"u"));
    lifecycle_ops::execute_create_subou(&mut vault, ticket(ou_id, payload), sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_spawn_ou_retired() {
    let (mut sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let payload = spawn_ou::new(governance::init_board(vector[creator()]), s(b"Next"), s(b"u"));
    lifecycle_ops::execute_spawn_ou(&mut ou, ticket(ou_id, payload), sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_spin_out_subou_retired() {
    let (mut sc, ou_id) = begin();
    let mut subou_vault = second_vault(&mut sc, other_id());
    let mut subou = sc.take_shared<OU>();
    let mut vault = retired_vault(&sc);
    let payload = spin_out_subou::new(
        other_id(),
        other_id(),
        other_id(),
        config(),
        config(),
        config(),
    );
    lifecycle_ops::execute_spin_out_subou(
        &mut vault,
        &mut subou_vault,
        &mut subou,
        ticket(ou_id, payload),
        sc.ctx(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun begin_transfer_assets_retired() {
    let (sc, ou_id) = begin();
    let vault = sc.take_shared<CapabilityVault>();
    let treasury = retired_treasury(&sc);
    let payload = transfer_assets::new(other_id(), other_id(), other_id(), vector[], vector[]);
    let _transfer = lifecycle_ops::begin_transfer_assets(
        &treasury,
        &vault,
        ticket(ou_id, payload),
    );
    abort
}

/// The transfer is stamped above VERSION; both treasuries are live.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun transfer_coin_retired() {
    let (mut sc, ou_id) = begin();
    let mut target = treasury_vault::new(other_id(), version::min_supported(), sc.ctx());
    let mut source = sc.take_shared<TreasuryVault>();
    let mut transfer = retired_transfer(&source, &sc.take_shared<CapabilityVault>(), ou_id);
    lifecycle_ops::transfer_coin<SUI>(&mut transfer, &mut source, &mut target, sc.ctx());
    abort
}

/// The transfer is stamped above VERSION; both vaults are live.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun transfer_cap_retired() {
    let (mut sc, ou_id) = begin();
    let mut target = second_vault(&mut sc, other_id());
    let mut source = sc.take_shared<CapabilityVault>();
    let mut transfer = retired_transfer(&sc.take_shared<TreasuryVault>(), &source, ou_id);
    lifecycle_ops::transfer_cap<TestCap>(&mut transfer, &mut source, &mut target, other_id());
    abort
}

/// The transfer is stamped above VERSION.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun finish_transfer_assets_retired() {
    let (sc, ou_id) = begin();
    let treasury = sc.take_shared<TreasuryVault>();
    let vault = sc.take_shared<CapabilityVault>();
    let transfer = retired_transfer(&treasury, &vault, ou_id);
    lifecycle_ops::finish_transfer_assets(transfer);
    abort
}

// === member_ops ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_add_member_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    member_ops::execute_add_member(&mut ou, ticket(ou_id, add_member::new(@0xC)));
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_batch_add_members_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    member_ops::execute_batch_add_members(
        &mut ou,
        ticket(ou_id, batch_add_members::new(vector[@0xC])),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_batch_remove_members_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    member_ops::execute_batch_remove_members(
        &mut ou,
        ticket(ou_id, batch_remove_members::new(vector[member()])),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun execute_remove_member_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    member_ops::execute_remove_member(&mut ou, ticket(ou_id, remove_member::new(member())));
    abort
}
