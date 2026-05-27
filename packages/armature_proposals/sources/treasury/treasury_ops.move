module armature_proposals::treasury_ops;

use armature::dao::DAO;
use armature::proposal::{ExecutionRequest, ExecutionTicket};
use armature::treasury_vault::TreasuryVault;
use armature::utils;
use armature_proposals::multicoin_item::MultiCoinItem;
use armature_proposals::send_batch_multicoin_to_dao::SendBatchMulticoinToDAO;
use armature_proposals::send_batch_multicoin_to_player::SendBatchMulticoinToAddress;
use armature_proposals::send_coin::SendCoin;
use armature_proposals::send_coin_to_dao::SendCoinToDAO;
use armature_proposals::send_small_payment::{Self, SendSmallPayment, SmallPaymentState};
use multicoin::multicoin::Balance as MultiCoinBalance;
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

public struct BatchMulticoinSentToAddress has copy, drop {
    dao_id: ID,
    recipient: address,
    item_count: u64,
}

public struct BatchMulticoinSentToDAO has copy, drop {
    dao_id: ID,
    target_treasury: ID,
    item_count: u64,
}

// === Handlers ===

public fun execute_send_coin<T>(
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    send_coin_impl(vault, ticket.ticket_payload(), ticket.ticket_request(), ctx);
    ticket.discharge();
}

public fun execute_send_coin_to_dao<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendCoinToDAO<T>>,
    ctx: &mut TxContext,
) {
    send_coin_to_dao_impl(
        source_vault,
        target_vault,
        ticket.ticket_payload(),
        ticket.ticket_request(),
        ctx,
    );
    ticket.discharge();
}

/// Execute a SendSmallPayment proposal: rate-limited withdrawal from treasury.
/// Uses ProposalTypeState on the DAO to enforce epoch-based cumulative spend caps.
public fun execute_send_small_payment<T>(
    dao: &mut DAO,
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendSmallPayment<T>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();
    let now = clock.timestamp_ms();

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
            req,
        );
    };

    let state: &mut SmallPaymentState = dao.borrow_type_state_mut(req);

    if (now >= state.epoch_start_ms() + state.epoch_duration_ms()) {
        let balance = vault.balance<T>();
        let new_max = utils::mul_bps(balance, state.spend_limit_bps());
        state.reset_epoch(now, new_max);
    };

    assert!(state.epoch_spend() + payload.amount() <= state.max_epoch_spend(), EExceedsDailyCap);
    state.add_epoch_spend(payload.amount());

    let coin = vault.withdraw<T, SendSmallPayment<T>>(payload.amount(), req, ctx);

    event::emit(SmallPaymentSent {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
        epoch_spend: state.epoch_spend(),
        max_epoch_spend: state.max_epoch_spend(),
    });

    transfer::public_transfer(coin, payload.recipient());

    ticket.discharge();
}

public fun execute_send_batch_multicoin_to_player(
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendBatchMulticoinToAddress>,
    ctx: &mut TxContext,
) {
    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();
    assert!(vault.dao_id() == req.req_dao_id(), EVaultDAOMismatch);
    let recipient = payload.recipient();
    let item_count = payload.items().length();
    payload.items().do_ref!(|item: &MultiCoinItem| {
        let balance: MultiCoinBalance = vault.withdraw_multicoin(
            item.collection_id(),
            item.asset_id(),
            item.amount(),
            req,
            ctx,
        );
        transfer::public_transfer(balance, recipient);
    });
    event::emit(BatchMulticoinSentToAddress {
        dao_id: vault.dao_id(),
        recipient,
        item_count,
    });
    ticket.discharge();
}

public fun execute_send_batch_multicoin_to_dao(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendBatchMulticoinToDAO>,
    ctx: &mut TxContext,
) {
    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();
    assert!(source_vault.dao_id() == req.req_dao_id(), EVaultDAOMismatch);
    assert!(object::id(target_vault) == payload.recipient_treasury(), ETargetVaultMismatch);
    let item_count = payload.items().length();
    payload.items().do_ref!(|item: &MultiCoinItem| {
        let balance: MultiCoinBalance = source_vault.withdraw_multicoin(
            item.collection_id(),
            item.asset_id(),
            item.amount(),
            req,
            ctx,
        );
        target_vault.deposit_multicoin(balance, ctx);
    });
    event::emit(BatchMulticoinSentToDAO {
        dao_id: source_vault.dao_id(),
        target_treasury: payload.recipient_treasury(),
        item_count,
    });
    ticket.discharge();
}

// === Internal ===

fun send_coin_impl<T>(
    vault: &mut TreasuryVault,
    payload: &SendCoin<T>,
    request: &ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    let coin = vault.withdraw<T, SendCoin<T>>(payload.amount(), request, ctx);
    event::emit(CoinSent {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
    });
    transfer::public_transfer(coin, payload.recipient());
}

fun send_coin_to_dao_impl<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    payload: &SendCoinToDAO<T>,
    request: &ExecutionRequest<SendCoinToDAO<T>>,
    ctx: &mut TxContext,
) {
    assert!(source_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(object::id(target_vault) == payload.recipient_treasury(), ETargetVaultMismatch);
    let coin = source_vault.withdraw<T, SendCoinToDAO<T>>(payload.amount(), request, ctx);
    target_vault.deposit(coin, ctx);
    event::emit(CoinSentToDAO {
        dao_id: source_vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        target_treasury: payload.recipient_treasury(),
    });
}
