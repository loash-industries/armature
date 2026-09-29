module armature::tribe;

use armature::capability_vault;
use armature::emergency;
use armature::governance;
use armature::ou::{Self, ProposalTypeInit};
use armature::permissions;
use armature::proposal::ExecutionRequest;
use std::string::String;

// === Public Functions ===

/// Create a SubOU with the given board, wire its SubOUControl into `parent_vault`,
/// share all companion objects, and transfer the FreezeAdminCap to `freeze_admin`.
///
/// `config_overrides` is applied after the default SubOU proposal-type slots are seeded:
/// existing types have their config replaced; non-blocked types not yet enabled are
/// inserted and enabled. Build entries with `ou::new_type_init<T>(display_key, config)`.
/// Passing an empty vector produces the standard SubOU defaults.
///
/// Requires an `ExecutionRequest` from the parent OU's governance carrying
/// VAULT_STORE and VAULT_EXTRACT, the bits CreateSubOU holds: it mints a
/// SubOUControl into `parent_vault`. Use `proposal::ticket_request` to obtain
/// the request from a `board_voting::submit_vote_execute` or standard two-PTB
/// execution ticket.
///
/// Returns the new SubOU's ID.
public fun create_wired_subou<P>(
    board: vector<address>,
    name: String,
    metadata_uri: String,
    freeze_admin: address,
    parent_vault: &mut capability_vault::CapabilityVault,
    req: &ExecutionRequest<P>,
    config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): ID {
    req.assert_permitted(permissions::vault_store() | permissions::vault_extract());
    let gov = governance::init_board(board);
    let (subou, freeze_cap) = ou::create_subou_configured(
        &gov,
        name,
        metadata_uri,
        config_overrides,
        ctx,
    );
    let subou_id = object::id(&subou);

    let ctrl = capability_vault::new_subou_control(subou_id, ctx);
    let ctrl_id = object::id(&ctrl);
    capability_vault::store_cap(parent_vault, ctrl, req);

    ou::share_subou(subou, ctrl_id);
    emergency::transfer_admin_cap(freeze_cap, freeze_admin);

    subou_id
}

/// Create a parent Tribe OU with an Officers SubOU and a Members SubOU.
/// All three OUs use Board governance seeded from the provided address arrays.
/// All companion objects are created and shared internally.
/// The tribe's FreezeAdminCap is transferred to the transaction sender.
/// Officer and member FreezeAdminCaps are transferred to the provided addresses.
///
/// Control hierarchy:
/// Tribe OU CapabilityVault       → SubOUControl for Officers SubOU
/// Officers SubOU CapabilityVault → SubOUControl for Members SubOU
///
/// Returns (tribe_ou_id, officer_ou_id, member_ou_id).
public fun create_tribe(
    tribe_board: vector<address>,
    officers: vector<address>,
    members: vector<address>,
    tribe_name: String,
    officer_name: String,
    member_name: String,
    tribe_metadata_uri: String,
    officer_metadata_uri: String,
    member_metadata_uri: String,
    officer_freeze_admin: address,
    member_freeze_admin: address,
    ctx: &mut TxContext,
): (ID, ID, ID) {
    let tribe_gov = governance::init_board(tribe_board);
    let officer_gov = governance::init_board(officers);
    let member_gov = governance::init_board(members);

    // Create parent OU; vault returned un-shared so we can wire the officer control.
    let (tribe_ou_id, mut tribe_vault) = ou::create_returning_vault(
        &tribe_gov,
        tribe_name,
        tribe_metadata_uri,
        ctx,
    );

    // Create Officers SubOU; vault also returned un-shared so we can wire the member control.
    let (officer_ou, officer_freeze_cap, mut officer_vault) = ou::create_subou_returning_vault(
        &officer_gov,
        officer_name,
        officer_metadata_uri,
        ctx,
    );
    let officer_ou_id = object::id(&officer_ou);

    // Create Members SubOU (vault shared internally — no further wiring needed).
    let (member_ou, member_freeze_cap) = ou::create_subou(
        &member_gov,
        member_name,
        member_metadata_uri,
        ctx,
    );
    let member_ou_id = object::id(&member_ou);

    // Tribe OU controls Officers SubOU.
    let officer_ctrl = capability_vault::new_subou_control(officer_ou_id, ctx);
    let officer_ctrl_id = object::id(&officer_ctrl);
    capability_vault::store_cap_init(&mut tribe_vault, officer_ctrl);

    // Officers SubOU controls Members SubOU.
    let member_ctrl = capability_vault::new_subou_control(member_ou_id, ctx);
    let member_ctrl_id = object::id(&member_ctrl);
    capability_vault::store_cap_init(&mut officer_vault, member_ctrl);

    // Share vaults (now populated), then share the SubOUs.
    capability_vault::share(tribe_vault);
    capability_vault::share(officer_vault);
    ou::share_subou(officer_ou, officer_ctrl_id);
    ou::share_subou(member_ou, member_ctrl_id);

    // Transfer SubOU freeze caps to their respective admins.
    emergency::transfer_admin_cap(officer_freeze_cap, officer_freeze_admin);
    emergency::transfer_admin_cap(member_freeze_cap, member_freeze_admin);

    (tribe_ou_id, officer_ou_id, member_ou_id)
}

/// Like `create_tribe` but accepts per-OU proposal-type overrides applied at
/// construction time, before any OU is shared. Each override is a `ProposalTypeInit`
/// built with `ou::new_type_init<T>(display_key, config)`. For each entry:
/// - If the type is already enabled by default, its config is replaced. The
/// override's display key must match the default key (EDisplayKeyMismatch).
/// - If the type is not yet enabled, it is inserted and enabled.
/// - If the type is blocked (hierarchy-altering or bypass-meta), the call aborts.
/// The original `create_tribe` is unchanged and continues to use hardcoded defaults.
///
/// Returns (tribe_ou_id, officer_ou_id, member_ou_id).
public fun create_tribe_configured(
    tribe_board: vector<address>,
    officers: vector<address>,
    members: vector<address>,
    tribe_name: String,
    officer_name: String,
    member_name: String,
    tribe_metadata_uri: String,
    officer_metadata_uri: String,
    member_metadata_uri: String,
    officer_freeze_admin: address,
    member_freeze_admin: address,
    tribe_config_overrides: vector<ProposalTypeInit>,
    officer_config_overrides: vector<ProposalTypeInit>,
    member_config_overrides: vector<ProposalTypeInit>,
    ctx: &mut TxContext,
): (ID, ID, ID) {
    let tribe_gov = governance::init_board(tribe_board);
    let officer_gov = governance::init_board(officers);
    let member_gov = governance::init_board(members);

    // Create parent OU; vault returned un-shared so we can wire the officer control.
    let (tribe_ou_id, mut tribe_vault) = ou::create_returning_vault_configured(
        &tribe_gov,
        tribe_name,
        tribe_metadata_uri,
        tribe_config_overrides,
        ctx,
    );

    // Create Officers SubOU; vault also returned un-shared so we can wire the member control.
    let (
        officer_ou,
        officer_freeze_cap,
        mut officer_vault,
    ) = ou::create_subou_returning_vault_configured(
        &officer_gov,
        officer_name,
        officer_metadata_uri,
        officer_config_overrides,
        ctx,
    );
    let officer_ou_id = object::id(&officer_ou);

    // Create Members SubOU (vault shared internally — no further wiring needed).
    let (member_ou, member_freeze_cap) = ou::create_subou_configured(
        &member_gov,
        member_name,
        member_metadata_uri,
        member_config_overrides,
        ctx,
    );
    let member_ou_id = object::id(&member_ou);

    // Tribe OU controls Officers SubOU.
    let officer_ctrl = capability_vault::new_subou_control(officer_ou_id, ctx);
    let officer_ctrl_id = object::id(&officer_ctrl);
    capability_vault::store_cap_init(&mut tribe_vault, officer_ctrl);

    // Officers SubOU controls Members SubOU.
    let member_ctrl = capability_vault::new_subou_control(member_ou_id, ctx);
    let member_ctrl_id = object::id(&member_ctrl);
    capability_vault::store_cap_init(&mut officer_vault, member_ctrl);

    // Share vaults (now populated), then share the SubOUs.
    capability_vault::share(tribe_vault);
    capability_vault::share(officer_vault);
    ou::share_subou(officer_ou, officer_ctrl_id);
    ou::share_subou(member_ou, member_ctrl_id);

    // Transfer SubOU freeze caps to their respective admins.
    emergency::transfer_admin_cap(officer_freeze_cap, officer_freeze_admin);
    emergency::transfer_admin_cap(member_freeze_cap, member_freeze_admin);

    (tribe_ou_id, officer_ou_id, member_ou_id)
}
