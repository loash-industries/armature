module armature_proposals::treasury_ops;

use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::send_coin::SendCoin;
use armature_proposals::send_coin_to_dao::SendCoinToDAO;
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ETargetVaultMismatch: u64 = 1;

// === Events ===

public struct CoinSent has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    recipient: address,
}

public struct CoinSentToDAO has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    target_treasury: ID,
}

// === Handlers ===

/// Execute a SendCoin proposal: withdraw from treasury and transfer to recipient.
public fun execute_send_coin<T>(
    vault: &mut TreasuryVault,
    proposal: &Proposal<SendCoin<T>>,
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    let coin = vault.withdraw<T, SendCoin<T>>(payload.amount(), &request, ctx);

    event::emit(CoinSent {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
    });

    transfer::public_transfer(coin, payload.recipient());

    proposal::finalize(request, proposal);
}

/// Execute a SendCoinToDAO proposal: withdraw from source treasury, deposit into target.
public fun execute_send_coin_to_dao<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    proposal: &Proposal<SendCoinToDAO<T>>,
    request: ExecutionRequest<SendCoinToDAO<T>>,
    ctx: &mut TxContext,
) {
    assert!(source_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    assert!(object::id(target_vault) == payload.recipient_treasury(), ETargetVaultMismatch);

    let coin = source_vault.withdraw<T, SendCoinToDAO<T>>(payload.amount(), &request, ctx);
    target_vault.deposit(coin);

    event::emit(CoinSentToDAO {
        dao_id: source_vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        target_treasury: payload.recipient_treasury(),
    });

    proposal::finalize(request, proposal);
}
