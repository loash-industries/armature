module armature_proposals::currency_ops;

use armature::capability_vault::CapabilityVault;
use armature::proposal::{ExecutionRequest, ExecutionTicket};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::adopt_currency::AdoptCurrency;
use armature_proposals::burn_coin::BurnCoin;
use armature_proposals::mint_allowance::MintAllowance;
use armature_proposals::mint_coin::MintCoin;
use armature_proposals::return_currency_cap::ReturnCurrencyCap;
use sui::coin::{Self, TreasuryCap};
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ECapNotInVault: u64 = 1;
const ECapTypeMismatch: u64 = 2;

// === Events ===

public struct CurrencyAdopted has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    treasury_cap_id: ID,
}

public struct CoinMinted has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
    /// `none` => minted into the DAO treasury, `some` => issued directly.
    recipient: Option<address>,
}

public struct CoinBurned has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    amount: u64,
}

public struct CurrencyCapReturned has copy, drop {
    dao_id: ID,
    coin_type: std::ascii::String,
    treasury_cap_id: ID,
    recipient: address,
}

// === Handlers ===

/// Execute an AdoptCurrency proposal: take custody of a `TreasuryCap<T>` by
/// storing it in the capability vault.
public fun execute_adopt_currency<T>(
    vault: &mut CapabilityVault,
    cap: TreasuryCap<T>,
    ticket: ExecutionTicket<AdoptCurrency<T>>,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let cap_id = object::id(&cap);
    vault.store_cap(cap, ticket.ticket_request());

    event::emit(CurrencyAdopted {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        treasury_cap_id: cap_id,
    });

    ticket.discharge();
}

/// Execute a MintCoin proposal: mint `amount` of `Coin<T>` with the custodied cap.
public fun execute_mint_coin<T>(
    cap_vault: &mut CapabilityVault,
    treasury_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<MintCoin<T>>,
    ctx: &mut TxContext,
) {
    use armature_proposals::mint_coin;
    let payload = ticket.ticket_payload();
    mint<T, MintCoin<T>>(
        cap_vault,
        treasury_vault,
        mint_coin::treasury_cap_id(payload),
        mint_coin::amount(payload),
        mint_coin::recipient(payload),
        ticket.ticket_request(),
        ctx,
    );
    ticket.discharge();
}

/// Execute a MintAllowance proposal: identical mint mechanics to `MintCoin`.
public fun execute_mint_allowance<T>(
    cap_vault: &mut CapabilityVault,
    treasury_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<MintAllowance<T>>,
    ctx: &mut TxContext,
) {
    use armature_proposals::mint_allowance;
    let payload = ticket.ticket_payload();
    mint<T, MintAllowance<T>>(
        cap_vault,
        treasury_vault,
        mint_allowance::treasury_cap_id(payload),
        mint_allowance::amount(payload),
        mint_allowance::recipient(payload),
        ticket.ticket_request(),
        ctx,
    );
    ticket.discharge();
}

/// Execute a BurnCoin proposal: withdraw and burn `amount` of `Coin<T>`.
public fun execute_burn_coin<T>(
    cap_vault: &mut CapabilityVault,
    treasury_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<BurnCoin<T>>,
    ctx: &mut TxContext,
) {
    use armature_proposals::burn_coin;
    assert!(cap_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);
    assert!(treasury_vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let cap_id = burn_coin::treasury_cap_id(payload);
    let amount = burn_coin::amount(payload);
    assert_cap_in_vault<TreasuryCap<T>>(cap_vault, cap_id);

    let coin = treasury_vault.withdraw<T, BurnCoin<T>>(amount, ticket.ticket_request(), ctx);
    let cap: &mut TreasuryCap<T> = cap_vault.borrow_cap_mut(cap_id, ticket.ticket_request());
    coin::burn(cap, coin);

    event::emit(CoinBurned {
        dao_id: cap_vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount,
    });

    ticket.discharge();
}

/// Execute a ReturnCurrencyCap proposal: extract the `TreasuryCap<T>` and transfer it.
public fun execute_return_currency_cap<T>(
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<ReturnCurrencyCap<T>>,
) {
    use armature_proposals::return_currency_cap;
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let cap_id = return_currency_cap::treasury_cap_id(payload);
    let recipient = return_currency_cap::recipient(payload);
    assert_cap_in_vault<TreasuryCap<T>>(vault, cap_id);

    let cap: TreasuryCap<T> = vault.extract_cap(cap_id, ticket.ticket_request());

    event::emit(CurrencyCapReturned {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        treasury_cap_id: cap_id,
        recipient,
    });

    transfer::public_transfer(cap, recipient);

    ticket.discharge();
}

// === Internal ===

/// Shared mint path for `MintCoin` and `MintAllowance` — identical mechanics,
/// the only difference between the two is which type `P` gates execution.
/// Validates the cap, mints, emits, and routes the coin; the caller finalizes.
fun mint<T, P>(
    cap_vault: &mut CapabilityVault,
    treasury_vault: &mut TreasuryVault,
    cap_id: ID,
    amount: u64,
    recipient: Option<address>,
    request: &ExecutionRequest<P>,
    ctx: &mut TxContext,
) {
    assert!(cap_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert_cap_in_vault<TreasuryCap<T>>(cap_vault, cap_id);

    let cap: &mut TreasuryCap<T> = cap_vault.borrow_cap_mut(cap_id, request);
    let minted = coin::mint(cap, amount, ctx);

    event::emit(CoinMinted {
        dao_id: cap_vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount,
        recipient,
    });

    deposit_or_transfer(minted, recipient, treasury_vault, ctx);
}

/// Assert `cap_id` names a capability of type `Cap` currently held in `vault`.
/// Guards against a passing-but-wrong cap_id in the payload: the cap must be
/// present (`ECapNotInVault`) and registered under the expected type
/// (`ECapTypeMismatch`), so a `MintCoin<T>` cannot be steered at some other
/// currency's cap that happens to share the vault.
fun assert_cap_in_vault<Cap: key + store>(vault: &CapabilityVault, cap_id: ID) {
    assert!(vault.contains(cap_id), ECapNotInVault);
    assert!(vault.ids_for_type<Cap>().contains(&cap_id), ECapTypeMismatch);
}

/// Route a freshly minted coin either into the DAO treasury (`none`) or to a
/// direct recipient (`some`).
fun deposit_or_transfer<T>(
    coin: sui::coin::Coin<T>,
    recipient: Option<address>,
    treasury_vault: &mut TreasuryVault,
    ctx: &mut TxContext,
) {
    if (recipient.is_some()) {
        transfer::public_transfer(coin, *recipient.borrow());
    } else {
        treasury_vault.deposit(coin, ctx);
    }
}
