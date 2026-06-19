module armature::tribe;

use armature::capability_vault;
use armature::dao;
use armature::emergency;
use armature::governance;
use armature::proposal::ProposalConfig;
use std::string::String;
use sui::vec_map::VecMap;

// === Public Functions ===

/// Create a SubDAO with the given board, wire its SubDAOControl into `parent_vault`,
/// share all companion objects, and transfer the FreezeAdminCap to `freeze_admin`.
///
/// `config_overrides` is applied after the default SubDAO proposal configs are built:
/// existing types have their config replaced; non-blocked types not yet in the enabled
/// set are inserted and enabled. Passing an empty map produces the standard SubDAO defaults.
///
/// Works both during initial tribe construction (parent vault un-shared) and post-creation
/// (parent vault already shared — borrow it mutably in the PTB).
///
/// Returns the new SubDAO's ID.
public fun create_wired_subdao(
    board: vector<address>,
    name: String,
    description: String,
    image_url: String,
    freeze_admin: address,
    parent_vault: &mut capability_vault::CapabilityVault,
    config_overrides: VecMap<std::ascii::String, ProposalConfig>,
    ctx: &mut TxContext,
): ID {
    let gov = governance::init_board(board);
    let (subdao, freeze_cap) = dao::create_subdao_configured(
        &gov,
        name,
        description,
        image_url,
        config_overrides,
        ctx,
    );
    let subdao_id = object::id(&subdao);

    let ctrl = capability_vault::new_subdao_control(subdao_id, ctx);
    let ctrl_id = object::id(&ctrl);
    capability_vault::store_cap_init(parent_vault, ctrl);

    dao::share_subdao(subdao, ctrl_id);
    emergency::transfer_admin_cap(freeze_cap, freeze_admin);

    subdao_id
}

/// Create a parent Tribe DAO with an Officers SubDAO and a Members SubDAO.
/// All three DAOs use Board governance seeded from the provided address arrays.
/// All companion objects are created and shared internally.
/// The tribe's FreezeAdminCap is transferred to the transaction sender.
/// Officer and member FreezeAdminCaps are transferred to the provided addresses.
///
/// Control hierarchy:
///   Tribe DAO CapabilityVault       → SubDAOControl for Officers SubDAO
///   Officers SubDAO CapabilityVault → SubDAOControl for Members SubDAO
///
/// Returns (tribe_dao_id, officer_dao_id, member_dao_id).
public fun create_tribe(
    tribe_board: vector<address>,
    officers: vector<address>,
    members: vector<address>,
    tribe_name: String,
    officer_name: String,
    member_name: String,
    tribe_description: String,
    officer_description: String,
    member_description: String,
    tribe_image_url: String,
    officer_image_url: String,
    member_image_url: String,
    officer_freeze_admin: address,
    member_freeze_admin: address,
    ctx: &mut TxContext,
): (ID, ID, ID) {
    let tribe_gov = governance::init_board(tribe_board);
    let officer_gov = governance::init_board(officers);
    let member_gov = governance::init_board(members);

    // Create parent DAO; vault returned un-shared so we can wire the officer control.
    let (tribe_dao_id, mut tribe_vault) = dao::create_returning_vault(
        &tribe_gov,
        tribe_name,
        tribe_description,
        tribe_image_url,
        ctx,
    );

    // Create Officers SubDAO; vault also returned un-shared so we can wire the member control.
    let (officer_dao, officer_freeze_cap, mut officer_vault) = dao::create_subdao_returning_vault(
        &officer_gov,
        officer_name,
        officer_description,
        officer_image_url,
        ctx,
    );
    let officer_dao_id = object::id(&officer_dao);

    // Create Members SubDAO (vault shared internally — no further wiring needed).
    let (member_dao, member_freeze_cap) = dao::create_subdao(
        &member_gov,
        member_name,
        member_description,
        member_image_url,
        ctx,
    );
    let member_dao_id = object::id(&member_dao);

    // Tribe DAO controls Officers SubDAO.
    let officer_ctrl = capability_vault::new_subdao_control(officer_dao_id, ctx);
    let officer_ctrl_id = object::id(&officer_ctrl);
    capability_vault::store_cap_init(&mut tribe_vault, officer_ctrl);

    // Officers SubDAO controls Members SubDAO.
    let member_ctrl = capability_vault::new_subdao_control(member_dao_id, ctx);
    let member_ctrl_id = object::id(&member_ctrl);
    capability_vault::store_cap_init(&mut officer_vault, member_ctrl);

    // Share vaults (now populated), then share the SubDAOs.
    capability_vault::share(tribe_vault);
    capability_vault::share(officer_vault);
    dao::share_subdao(officer_dao, officer_ctrl_id);
    dao::share_subdao(member_dao, member_ctrl_id);

    // Transfer SubDAO freeze caps to their respective admins.
    emergency::transfer_admin_cap(officer_freeze_cap, officer_freeze_admin);
    emergency::transfer_admin_cap(member_freeze_cap, member_freeze_admin);

    (tribe_dao_id, officer_dao_id, member_dao_id)
}

/// Like `create_tribe` but accepts per-DAO `ProposalConfig` overrides applied at
/// construction time, before any DAO is shared. Each override map is keyed by proposal
/// type name (e.g. `b"AddMember".to_ascii_string()`). For each entry:
/// - If the type is already enabled by default, its config is replaced.
/// - If the type is not yet enabled, it is inserted and enabled.
/// - If the type is blocked (hierarchy-altering or bypass-meta), the call aborts.
/// The original `create_tribe` is unchanged and continues to use hardcoded defaults.
///
/// Returns (tribe_dao_id, officer_dao_id, member_dao_id).
public fun create_tribe_configured(
    tribe_board: vector<address>,
    officers: vector<address>,
    members: vector<address>,
    tribe_name: String,
    officer_name: String,
    member_name: String,
    tribe_description: String,
    officer_description: String,
    member_description: String,
    tribe_image_url: String,
    officer_image_url: String,
    member_image_url: String,
    officer_freeze_admin: address,
    member_freeze_admin: address,
    tribe_config_overrides: VecMap<std::ascii::String, ProposalConfig>,
    officer_config_overrides: VecMap<std::ascii::String, ProposalConfig>,
    member_config_overrides: VecMap<std::ascii::String, ProposalConfig>,
    ctx: &mut TxContext,
): (ID, ID, ID) {
    let tribe_gov = governance::init_board(tribe_board);
    let officer_gov = governance::init_board(officers);
    let member_gov = governance::init_board(members);

    // Create parent DAO; vault returned un-shared so we can wire the officer control.
    let (tribe_dao_id, mut tribe_vault) = dao::create_returning_vault_configured(
        &tribe_gov,
        tribe_name,
        tribe_description,
        tribe_image_url,
        tribe_config_overrides,
        ctx,
    );

    // Create Officers SubDAO; vault also returned un-shared so we can wire the member control.
    let (
        officer_dao,
        officer_freeze_cap,
        mut officer_vault,
    ) = dao::create_subdao_returning_vault_configured(
        &officer_gov,
        officer_name,
        officer_description,
        officer_image_url,
        officer_config_overrides,
        ctx,
    );
    let officer_dao_id = object::id(&officer_dao);

    // Create Members SubDAO (vault shared internally — no further wiring needed).
    let (member_dao, member_freeze_cap) = dao::create_subdao_configured(
        &member_gov,
        member_name,
        member_description,
        member_image_url,
        member_config_overrides,
        ctx,
    );
    let member_dao_id = object::id(&member_dao);

    // Tribe DAO controls Officers SubDAO.
    let officer_ctrl = capability_vault::new_subdao_control(officer_dao_id, ctx);
    let officer_ctrl_id = object::id(&officer_ctrl);
    capability_vault::store_cap_init(&mut tribe_vault, officer_ctrl);

    // Officers SubDAO controls Members SubDAO.
    let member_ctrl = capability_vault::new_subdao_control(member_dao_id, ctx);
    let member_ctrl_id = object::id(&member_ctrl);
    capability_vault::store_cap_init(&mut officer_vault, member_ctrl);

    // Share vaults (now populated), then share the SubDAOs.
    capability_vault::share(tribe_vault);
    capability_vault::share(officer_vault);
    dao::share_subdao(officer_dao, officer_ctrl_id);
    dao::share_subdao(member_dao, member_ctrl_id);

    // Transfer SubDAO freeze caps to their respective admins.
    emergency::transfer_admin_cap(officer_freeze_cap, officer_freeze_admin);
    emergency::transfer_admin_cap(member_freeze_cap, member_freeze_admin);

    (tribe_dao_id, officer_dao_id, member_dao_id)
}
