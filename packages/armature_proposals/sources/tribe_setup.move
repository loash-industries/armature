/// Tribe constructors with the controller proposal types pre-enabled.
///
/// `armature::tribe` wires each parent's SubOUControl into its vault, but the
/// types that use it live here, in armature_proposals, so the framework cannot
/// enable them. Without them a new tribe's controls are dormant until each
/// parent passes an EnableProposalType vote (80% of its whole board). These
/// wrappers enable them on the Tribe OU and the Officers SubOU (the two
/// controllers) at construction, with the single-vote policy of
/// docs/tribe_configuration_proposals_config.md.
module armature_proposals::tribe_setup;

use armature::ou::{Self, ProposalTypeInit};
use armature::proposal::{Self, ProposalConfig};
use armature::tribe;
use armature_proposals::controller_batch_add_members::ControllerBatchAddMembers;
use armature_proposals::controller_batch_remove_members::ControllerBatchRemoveMembers;
use armature_proposals::pause_execution::{PauseSubOUExecution, UnpauseSubOUExecution};
use armature_proposals::reclaim_cap_from_subou::ReclaimCapFromSubOU;
use armature_proposals::transfer_cap_to_subou::TransferCapToSubOU;
use armature_proposals::type_permissions;
use std::string::String;
use std::type_name::TypeName;

/// 1 bps: one board member's YES reaches quorum on any realistic board, so
/// `board_voting::submit_vote_execute` works for a single member.
const SINGLE_VOTE_QUORUM: u16 = 1;
const CONSENSUS_QUORUM: u16 = 5_000;
/// Every type configured here holds an 80%-floor bit (VAULT_BORROW or
/// VAULT_EXTRACT), so 80% is the lowest threshold allowed.
const APPROVAL_THRESHOLD: u16 = 8_000;
const EXPIRY_MS: u64 = 604_800_000; // 7 days

// === Public Functions ===

/// The controller types a parent OU needs to act on a SubOU through its
/// SubOUControl, each with its permission bits and borrow scope from
/// `type_permissions`. Pass them as `config_overrides` to any OU constructor.
///
/// Single-vote (one member can submit, vote and execute in one PTB):
/// ControllerBatchAddMembers, ControllerBatchRemoveMembers, PauseSubOUExecution.
/// Consensus (50% quorum): UnpauseSubOUExecution, so one member cannot reverse
/// an emergency pause, and ReclaimCapFromSubOU and TransferCapToSubOU, which
/// move capabilities.
public fun controller_type_inits(): vector<ProposalTypeInit> {
    let control = type_permissions::subou_control();
    let scope = type_permissions::subou_control_scope();
    vector[
        ou::new_type_init<ControllerBatchAddMembers>(
            b"ControllerBatchAddMembers".to_ascii_string(),
            config(SINGLE_VOTE_QUORUM, control, scope),
        ),
        ou::new_type_init<ControllerBatchRemoveMembers>(
            b"ControllerBatchRemoveMembers".to_ascii_string(),
            config(SINGLE_VOTE_QUORUM, control, scope),
        ),
        ou::new_type_init<PauseSubOUExecution>(
            b"PauseSubOUExecution".to_ascii_string(),
            config(SINGLE_VOTE_QUORUM, control, scope),
        ),
        ou::new_type_init<UnpauseSubOUExecution>(
            b"UnpauseSubOUExecution".to_ascii_string(),
            config(CONSENSUS_QUORUM, control, scope),
        ),
        ou::new_type_init<ReclaimCapFromSubOU>(
            b"ReclaimCapFromSubOU".to_ascii_string(),
            config(CONSENSUS_QUORUM, type_permissions::reclaim_cap_from_subou(), scope),
        ),
        ou::new_type_init<TransferCapToSubOU>(
            b"TransferCapToSubOU".to_ascii_string(),
            config(CONSENSUS_QUORUM, type_permissions::transfer_cap_to_subou(), vector[]),
        ),
    ]
}

/// `tribe::create_tribe` with `controller_type_inits` enabled on the Tribe OU
/// and the Officers SubOU. The Members SubOU gets the standard defaults.
///
/// EnableProposalType keeps the framework default: YES from 80% of the whole
/// board. Enable types the tribe needs from day one (e.g. trading types) as
/// overrides in `create_tribe_configured` instead.
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
    create_tribe_configured(
        tribe_board,
        officers,
        members,
        tribe_name,
        officer_name,
        member_name,
        tribe_metadata_uri,
        officer_metadata_uri,
        member_metadata_uri,
        officer_freeze_admin,
        member_freeze_admin,
        vector[],
        vector[],
        vector[],
        ctx,
    )
}

/// `tribe::create_tribe_configured` with `controller_type_inits` enabled on
/// the Tribe OU and the Officers SubOU.
/// The caller's overrides are applied after them, so an override of one of
/// these types replaces its config (keeping its bits and scope; the display
/// key must match).
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
    let mut tribe_inits = controller_type_inits();
    tribe_inits.append(tribe_config_overrides);
    let mut officer_inits = controller_type_inits();
    officer_inits.append(officer_config_overrides);

    tribe::create_tribe_configured(
        tribe_board,
        officers,
        members,
        tribe_name,
        officer_name,
        member_name,
        tribe_metadata_uri,
        officer_metadata_uri,
        member_metadata_uri,
        officer_freeze_admin,
        member_freeze_admin,
        tribe_inits,
        officer_inits,
        member_config_overrides,
        ctx,
    )
}

// === Private Functions ===

fun config(quorum: u16, bits: u64, scope: vector<TypeName>): ProposalConfig {
    proposal::new_config(quorum, APPROVAL_THRESHOLD, 0, EXPIRY_MS, 0, 0)
        .with_permissions(bits)
        .with_borrow_scope(scope)
}
