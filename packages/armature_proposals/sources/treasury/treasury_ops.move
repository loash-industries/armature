module armature_proposals::treasury_ops;

use armature::ou::OU;
use armature::proposal::{ExecutionRequest, ExecutionTicket};
use armature::treasury_vault::TreasuryVault;
use armature::utils;
use armature_proposals::multicoin_item::MultiCoinItem;
use armature_proposals::send_batch_multicoin_to_ou::{Self, SendBatchMulticoinToOU};
use armature_proposals::send_batch_multicoin_to_player::{Self, SendBatchMulticoinToAddress};
use armature_proposals::send_coin::{Self, SendCoin};
use armature_proposals::send_coin_to_ou::{Self, SendCoinToOU};
use armature_proposals::send_small_payment::{Self, SendSmallPayment, SmallPaymentState};
use multicoin::multicoin::Balance as MultiCoinBalance;
use sui::clock::Clock;
use sui::event;

// === Errors ===

const EVaultOUMismatch: u64 = 0;
const ETargetVaultMismatch: u64 = 1;
const EExceedsDailyCap: u64 = 2;

// === Events ===

public struct CoinSent has copy, drop {
    ou_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    recipient: address,
}

public struct CoinSentToOU has copy, drop {
    ou_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    target_treasury: ID,
}

public struct SmallPaymentSent has copy, drop {
    ou_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    recipient: address,
    epoch_spend: u64,
    max_epoch_spend: u64,
}

public struct BatchMulticoinSentToAddress has copy, drop {
    ou_id: ID,
    recipient: address,
    item_count: u64,
}

public struct BatchMulticoinSentToOU has copy, drop {
    ou_id: ID,
    target_treasury: ID,
    item_count: u64,
}

// === Handlers ===

public fun execute_send_coin<T>(
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    send_coin_impl(
        vault,
        ticket.ticket_payload(),
        ticket.ticket_request(send_coin::permit<T>()),
        ctx,
    );
    ticket.discharge(send_coin::permit<T>());
}

public fun execute_send_coin_to_ou<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendCoinToOU<T>>,
    ctx: &mut TxContext,
) {
    send_coin_to_ou_impl(
        source_vault,
        target_vault,
        ticket.ticket_payload(),
        ticket.ticket_request(send_coin_to_ou::permit<T>()),
        ctx,
    );
    ticket.discharge(send_coin_to_ou::permit<T>());
}

/// Execute a SendSmallPayment proposal: rate-limited withdrawal from treasury.
/// Uses ProposalTypeState on the OU to enforce epoch-based cumulative spend caps.
public fun execute_send_small_payment<T>(
    ou: &mut OU,
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendSmallPayment<T>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(send_small_payment::permit<T>());
    let now = clock.timestamp_ms();

    if (!ou.has_type_state<SendSmallPayment<T>>()) {
        let balance = vault.balance<T>();
        let max_spend = utils::mul_bps(balance, send_small_payment::default_spend_limit_bps());
        ou.init_type_state(
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

    let state: &mut SmallPaymentState = ou.borrow_type_state_mut(req);

    if (now >= state.epoch_start_ms() + state.epoch_duration_ms()) {
        let balance = vault.balance<T>();
        let new_max = utils::mul_bps(balance, state.spend_limit_bps());
        state.reset_epoch(now, new_max);
    };

    assert!(state.epoch_spend() + payload.amount() <= state.max_epoch_spend(), EExceedsDailyCap);
    state.add_epoch_spend(payload.amount());

    let coin = vault.withdraw<T, SendSmallPayment<T>>(payload.amount(), req, ctx);

    event::emit(SmallPaymentSent {
        ou_id: vault.ou_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
        epoch_spend: state.epoch_spend(),
        max_epoch_spend: state.max_epoch_spend(),
    });

    transfer::public_transfer(coin, payload.recipient());

    ticket.discharge(send_small_payment::permit<T>());
}

public fun execute_send_batch_multicoin_to_player(
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendBatchMulticoinToAddress>,
    ctx: &mut TxContext,
) {
    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(send_batch_multicoin_to_player::permit());
    assert!(vault.ou_id() == req.req_ou_id(), EVaultOUMismatch);
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
        ou_id: vault.ou_id(),
        recipient,
        item_count,
    });
    ticket.discharge(send_batch_multicoin_to_player::permit());
}

public fun execute_send_batch_multicoin_to_ou(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendBatchMulticoinToOU>,
    ctx: &mut TxContext,
) {
    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request(send_batch_multicoin_to_ou::permit());
    assert!(source_vault.ou_id() == req.req_ou_id(), EVaultOUMismatch);
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
    event::emit(BatchMulticoinSentToOU {
        ou_id: source_vault.ou_id(),
        target_treasury: payload.recipient_treasury(),
        item_count,
    });
    ticket.discharge(send_batch_multicoin_to_ou::permit());
}

// === Internal ===

fun send_coin_impl<T>(
    vault: &mut TreasuryVault,
    payload: &SendCoin<T>,
    request: &ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    assert!(vault.ou_id() == request.req_ou_id(), EVaultOUMismatch);
    let coin = vault.withdraw<T, SendCoin<T>>(payload.amount(), request, ctx);
    event::emit(CoinSent {
        ou_id: vault.ou_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
    });
    transfer::public_transfer(coin, payload.recipient());
}

fun send_coin_to_ou_impl<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    payload: &SendCoinToOU<T>,
    request: &ExecutionRequest<SendCoinToOU<T>>,
    ctx: &mut TxContext,
) {
    assert!(source_vault.ou_id() == request.req_ou_id(), EVaultOUMismatch);
    assert!(object::id(target_vault) == payload.recipient_treasury(), ETargetVaultMismatch);
    let coin = source_vault.withdraw<T, SendCoinToOU<T>>(payload.amount(), request, ctx);
    target_vault.deposit(coin, ctx);
    event::emit(CoinSentToOU {
        ou_id: source_vault.ou_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        target_treasury: payload.recipient_treasury(),
    });
}
