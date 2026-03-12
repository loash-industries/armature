module armature::board_voting;

use armature::dao::DAO;
use armature::proposal::{Self, ExecutionRequest, Proposal};
use std::string::String;
use sui::clock::Clock;

// === Errors ===

const EDAONotActive: u64 = 0;
const ETypeNotEnabled: u64 = 1;
const EDAOIdMismatch: u64 = 2;

// === Submit ===

/// Submit a new proposal for board governance.
/// Validates: DAO is active, type is enabled, proposer is a board member.
/// Looks up the ProposalConfig for the given type_key from the DAO.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_proposal<P: store>(
    dao: &DAO,
    type_key: std::ascii::String,
    metadata_ipfs: String,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(dao.enabled_proposal_types().contains(&type_key), ETypeNotEnabled);

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    let config = *dao.proposal_configs().get(&type_key);

    proposal::create<P>(
        dao.id(),
        type_key,
        proposer,
        metadata_ipfs,
        payload,
        config,
        dao.governance(),
        clock,
        ctx,
    );
}

// === Execute ===

/// Authorize execution of a passed proposal for board governance.
/// Validates: DAO is active, proposal belongs to this DAO.
/// Looks up last_executed_at for cooldown, then records the execution timestamp.
public fun authorize_execution<P: store>(
    dao: &mut DAO,
    prop: &mut Proposal<P>,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionRequest<P> {
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(prop.dao_id() == dao.id(), EDAOIdMismatch);

    let type_key = prop.type_key();
    let last_executed_at = dao.last_executed_at();
    let last_ms = if (last_executed_at.contains(&type_key)) {
        option::some(*last_executed_at.get(&type_key))
    } else {
        option::none()
    };

    let req = proposal::execute(
        prop,
        dao.governance(),
        last_ms,
        clock,
        ctx,
    );

    dao.record_execution(type_key, clock.timestamp_ms());

    req
}
