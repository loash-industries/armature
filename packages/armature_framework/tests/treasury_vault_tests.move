#[test_only]
module armature::treasury_vault_tests;

use armature::dao;
use armature::governance;
use armature::proposal;
use armature::treasury_vault::{Self, TreasuryVault};
use std::string;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario;

const CREATOR: address = @0xA;
const NON_MEMBER: address = @0xC;

// A second coin type for testing multi-type deposits
public struct USDC has drop {}

/// Helper: create a DAO (which creates and shares a TreasuryVault)
fun create_test_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"Test"),
            string::utf8(b""),
            scenario.ctx(),
        );
    };
}

/// Helper: create an ExecutionRequest for testing withdrawals.
/// Uses a test-only function to bypass the proposal lifecycle.
/// We create it via the package-internal constructor.
fun create_test_execution_request<P>(vault: &TreasuryVault): proposal::ExecutionRequest<P> {
    let dao_id = vault.dao_id();
    let proposal_id = object::id_from_address(@0x2);
    proposal::new_execution_request<P>(dao_id, proposal_id)
}

// A phantom type to parameterize ExecutionRequest in tests
public struct TestProposal {}

#[test]
/// Deposit first coin adds to registry.
fun test_deposit_first_coin_adds_to_registry() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        assert!(
            vault.coin_types().contains(&std::type_name::with_original_ids<SUI>().into_string()),
        );
        assert!(vault.balance<SUI>() == 1000);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Deposit second coin type adds to registry.
fun test_deposit_second_coin_type_adds_to_registry() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let sui_coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(sui_coin, scenario.ctx());

        let usdc_coin = coin::mint_for_testing<USDC>(2000, scenario.ctx());
        vault.deposit(usdc_coin, scenario.ctx());

        assert!(
            vault.coin_types().contains(&std::type_name::with_original_ids<SUI>().into_string()),
        );
        assert!(
            vault.coin_types().contains(&std::type_name::with_original_ids<USDC>().into_string()),
        );
        assert!(vault.balance<SUI>() == 1000);
        assert!(vault.balance<USDC>() == 2000);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Deposit same type joins balance.
fun test_deposit_same_type_joins_balance() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();

        let coin1 = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(coin1, scenario.ctx());

        let coin2 = coin::mint_for_testing<SUI>(500, scenario.ctx());
        vault.deposit(coin2, scenario.ctx());

        // Balance joined, coin_types unchanged
        assert!(vault.balance<SUI>() == 1500);
        assert!(vault.coin_types().length() == 1);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Non-member can deposit — permissionless.
fun test_deposit_permissionless() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(NON_MEMBER);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(500, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        assert!(vault.balance<SUI>() == 500);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Zero-value deposit is a no-op.
fun test_deposit_zero_amount() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(0, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        // No type registered, balance is 0
        assert!(vault.coin_types().length() == 0);
        assert!(vault.balance<SUI>() == 0);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Withdraw with valid request succeeds.
fun test_withdraw_with_valid_request_succeeds() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        let req = create_test_execution_request<TestProposal>(&vault);
        let withdrawn = vault.withdraw<SUI, TestProposal>(400, &req, scenario.ctx());

        assert!(withdrawn.value() == 400);
        assert!(vault.balance<SUI>() == 600);

        // Cleanup
        proposal::consume(req);
        transfer::public_transfer(withdrawn, CREATOR);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Partial withdraw preserves field and registry entry.
fun test_partial_withdraw_preserves_field() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        let req = create_test_execution_request<TestProposal>(&vault);
        let withdrawn = vault.withdraw<SUI, TestProposal>(300, &req, scenario.ctx());

        // Type still in registry, balance reduced
        assert!(
            vault.coin_types().contains(&std::type_name::with_original_ids<SUI>().into_string()),
        );
        assert!(vault.balance<SUI>() == 700);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, CREATOR);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// After partial withdraw, type still in registry (coin_types reflects non-zero balances).
fun test_coin_types_reflects_non_zero_balances() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        let req = create_test_execution_request<TestProposal>(&vault);
        let withdrawn = vault.withdraw<SUI, TestProposal>(999, &req, scenario.ctx());

        // Still 1 MIST left — type stays in registry
        assert!(
            vault.coin_types().contains(&std::type_name::with_original_ids<SUI>().into_string()),
        );
        assert!(vault.balance<SUI>() == 1);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, CREATOR);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Withdraw exact balance removes dynamic field and registry entry.
fun test_withdraw_exact_balance_removes_field() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        let req = create_test_execution_request<TestProposal>(&vault);
        let withdrawn = vault.withdraw<SUI, TestProposal>(1000, &req, scenario.ctx());

        // Type removed from registry
        assert!(
            !vault.coin_types().contains(&std::type_name::with_original_ids<SUI>().into_string()),
        );
        assert!(vault.coin_types().length() == 0);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, CREATOR);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Withdraw exact balance removes dynamic field — balance query returns 0.
fun test_withdraw_exact_balance_removes_dynamic_field() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(500, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        let req = create_test_execution_request<TestProposal>(&vault);
        let withdrawn = vault.withdraw<SUI, TestProposal>(500, &req, scenario.ctx());

        // Dynamic field gone, balance is 0
        assert!(vault.balance<SUI>() == 0);

        proposal::consume(req);
        transfer::public_transfer(withdrawn, CREATOR);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = treasury_vault::EInsufficientBalance)]
/// Withdraw insufficient balance aborts.
fun test_withdraw_insufficient_balance_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(100, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        let req = create_test_execution_request<TestProposal>(&vault);
        let withdrawn = vault.withdraw<SUI, TestProposal>(200, &req, scenario.ctx());

        // Should not reach here
        proposal::consume(req);
        transfer::public_transfer(withdrawn, CREATOR);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Empty vault returns zero balance.
fun test_balance_empty_vault_returns_zero() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<TreasuryVault>();
        assert!(vault.balance<SUI>() == 0);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// Balance after deposit returns correct amount.
fun test_balance_after_deposit_returns_correct() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let coin = coin::mint_for_testing<SUI>(42_000_000, scenario.ctx());
        vault.deposit(coin, scenario.ctx());

        assert!(vault.balance<SUI>() == 42_000_000);

        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// claim_coin recovers a coin that was directly transferred to the vault address.
fun test_claim_coin_recovers_direct_transfer() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    // Get vault's object ID (used as the "owner" address for direct transfers)
    let vault_id;
    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<TreasuryVault>();
        vault_id = object::id(&vault);
        test_scenario::return_shared(vault);
    };

    // Simulate misdirected transfer: send a coin directly to the vault address
    scenario.next_tx(CREATOR);
    {
        let coin = coin::mint_for_testing<SUI>(50_000, scenario.ctx());
        transfer::public_transfer(coin, vault_id.to_address());
    };

    // Claim the coin via claim_coin
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        assert!(vault.balance<SUI>() == 0); // Not deposited yet

        let ticket = test_scenario::most_recent_receiving_ticket<coin::Coin<SUI>>(
            &vault_id,
        );
        vault.claim_coin<SUI>(ticket, scenario.ctx());

        // Now the balance should reflect the recovered coin
        assert!(vault.balance<SUI>() == 50_000);
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

#[test]
/// claim_coin works for multiple coin types and sequential claims.
fun test_claim_coin_multiple_types() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_test_dao(&mut scenario);

    let vault_id;
    scenario.next_tx(CREATOR);
    {
        let vault = scenario.take_shared<TreasuryVault>();
        vault_id = object::id(&vault);
        test_scenario::return_shared(vault);
    };

    // Send SUI directly to vault
    scenario.next_tx(CREATOR);
    {
        let coin = coin::mint_for_testing<SUI>(10_000, scenario.ctx());
        transfer::public_transfer(coin, vault_id.to_address());
    };

    // Claim SUI
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let ticket = test_scenario::most_recent_receiving_ticket<coin::Coin<SUI>>(
            &vault_id,
        );
        vault.claim_coin<SUI>(ticket, scenario.ctx());
        assert!(vault.balance<SUI>() == 10_000);
        test_scenario::return_shared(vault);
    };

    // Send USDC directly to vault
    scenario.next_tx(CREATOR);
    {
        let coin = coin::mint_for_testing<USDC>(25_000, scenario.ctx());
        transfer::public_transfer(coin, vault_id.to_address());
    };

    // Claim USDC
    scenario.next_tx(CREATOR);
    {
        let mut vault = scenario.take_shared<TreasuryVault>();
        let ticket = test_scenario::most_recent_receiving_ticket<coin::Coin<USDC>>(
            &vault_id,
        );
        vault.claim_coin<USDC>(ticket, scenario.ctx());
        assert!(vault.balance<USDC>() == 25_000);
        assert!(vault.balance<SUI>() == 10_000); // Still there
        test_scenario::return_shared(vault);
    };

    scenario.end();
}

// Note: test_withdraw_requires_execution_request is enforced by the ExecutionRequest
// parameter — only code holding a valid ExecutionRequest (from governance) can withdraw.
// This is verified by the Move type system and does not need a runtime test.
