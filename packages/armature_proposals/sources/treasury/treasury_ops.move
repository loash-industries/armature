module armature_proposals::treasury_ops;

use armature::dao::DAO;
use armature::proposal::{Self, Proposal, ExecutionRequest};
use armature::treasury_vault::TreasuryVault;
use armature::utils;
use armature_proposals::send_coin::SendCoin;
use armature_proposals::send_coin_to_dao::SendCoinToDAO;
use armature_proposals::send_small_payment::{Self, SendSmallPayment, SmallPaymentState};
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ETargetVaultMismatch: u64 = 1;
const EExceedsDailyCap: u64 = 2;

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

public struct SmallPaymentSent has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    recipient: address,
    epoch_spend: u64,
    max_epoch_spend: u64,
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
    target_vault.deposit(coin, ctx);

    event::emit(CoinSentToDAO {
        dao_id: source_vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        target_treasury: payload.recipient_treasury(),
    });

    proposal::finalize(request, proposal);
}

/// Execute a SendSmallPayment proposal: rate-limited withdrawal from treasury.
/// Uses ProposalTypeState on the DAO to enforce epoch-based cumulative spend caps.
public fun execute_send_small_payment<T>(
    dao: &mut DAO,
    vault: &mut TreasuryVault,
    proposal: &Proposal<SendSmallPayment<T>>,
    request: ExecutionRequest<SendSmallPayment<T>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);

    let payload = proposal.payload();
    let now = clock.timestamp_ms();

    // Lazy-init type state on first execution
    if (!dao.has_type_state<SendSmallPayment<T>>()) {
        let balance = vault.balance<T>();
        let max_spend = utils::mul_bps(balance, send_small_payment::default_spend_limit_bps());
        dao.init_type_state(
            send_small_payment::new_state(
                now,
                0,
                max_spend,
                send_small_payment::default_epoch_duration_ms(),
                send_small_payment::default_spend_limit_bps(),
            ),
            &request,
        );
    };

    let state: &mut SmallPaymentState = dao.borrow_type_state_mut(&request);

    // Epoch rollover: reset spend tracking if the epoch window has elapsed
    if (now >= state.epoch_start_ms() + state.epoch_duration_ms()) {
        let balance = vault.balance<T>();
        let new_max = utils::mul_bps(balance, state.spend_limit_bps());
        state.reset_epoch(now, new_max);
    };

    // Enforce cumulative spend cap
    assert!(state.epoch_spend() + payload.amount() <= state.max_epoch_spend(), EExceedsDailyCap);
    state.add_epoch_spend(payload.amount());

    // Withdraw and transfer
    let coin = vault.withdraw<T, SendSmallPayment<T>>(payload.amount(), &request, ctx);

    event::emit(SmallPaymentSent {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
        epoch_spend: state.epoch_spend(),
        max_epoch_spend: state.max_epoch_spend(),
    });

    transfer::public_transfer(coin, payload.recipient());

    proposal::finalize(request, proposal);
}
