#[test_only]
module armature_proposals::currency_ops_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::proposal::{Self, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::adopt_currency::{Self, AdoptCurrency};
use armature_proposals::burn_coin::{Self, BurnCoin};
use armature_proposals::currency_ops;
use armature_proposals::mint_coin::{Self, MintCoin};
use armature_proposals::return_currency_cap::{Self, ReturnCurrencyCap};
use std::string;
use sui::clock;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::test_scenario;

const CREATOR: address = @0xA;
const RECIPIENT: address = @0xB;

/// One-time-witness-style test coin. The DAO's sovereign currency.
public struct GLYPH has drop {}

// === Helpers ===

fun create_dao(scenario: &mut test_scenario::Scenario) {
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR]);
        dao::create(
            &init,
            string::utf8(b"Test DAO"),
            string::utf8(b"A test DAO"),
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun enable_type(scenario: &mut test_scenario::Scenario, type_key: vector<u8>) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0);
        dao.test_enable_type(type_key.to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };
}

/// Mint a fresh TreasuryCap<GLYPH> and adopt it through a full proposal cycle.
/// Returns the cap's object ID for use in later mint/burn proposals.
fun adopt_glyph(scenario: &mut test_scenario::Scenario, clock: &clock::Clock): ID {
    enable_type(scenario, b"AdoptCurrency");

    // Submit
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = adopt_currency::new<GLYPH>();
        board_voting::submit_proposal(
            &dao,
            b"AdoptCurrency".to_ascii_string(),
            option::some(string::utf8(b"Adopt GLYPH")),
            payload,
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };

    // Vote
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<AdoptCurrency<GLYPH>>>();
        proposal.vote(true, clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute: mint a cap in-tx and hand it to the handler
    let cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<AdoptCurrency<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let cap = coin::create_treasury_cap_for_testing<GLYPH>(scenario.ctx());
        cap_id = object::id(&cap);

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );
        currency_ops::execute_adopt_currency<GLYPH>(&mut vault, cap, &proposal, request);

        assert!(vault.contains(cap_id));
        assert!(vault.ids_for_type<TreasuryCap<GLYPH>>().contains(&cap_id));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    cap_id
}

// === Tests ===

#[test]
/// Mint into the treasury (recipient = none): GLYPH supply lands in the DAO's
/// own TreasuryVault, where SendCoin would later distribute it.
fun mint_into_treasury() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let cap_id = adopt_glyph(&mut scenario, &clock);
    enable_type(&mut scenario, b"MintCoin");

    // Submit + vote
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 1_000_000, option::none());
        board_voting::submit_proposal(
            &dao,
            b"MintCoin".to_ascii_string(),
            option::some(string::utf8(b"Mint into treasury")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };

    // Execute
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            &proposal,
            request,
            scenario.ctx(),
        );

        assert!(treasury.balance<GLYPH>() == 1_000_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Mint directly to a recipient (recipient = some): coins go to the address,
/// the treasury is untouched.
fun mint_to_recipient() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let cap_id = adopt_glyph(&mut scenario, &clock);
    enable_type(&mut scenario, b"MintCoin");

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 500, option::some(RECIPIENT));
        board_voting::submit_proposal(
            &dao,
            b"MintCoin".to_ascii_string(),
            option::some(string::utf8(b"Mint to recipient")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let request = board_voting::authorize_execution(
            &mut dao,
            &mut proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            &proposal,
            request,
            scenario.ctx(),
        );

        // Treasury stays empty — direct issuance bypasses it.
        assert!(treasury.balance<GLYPH>() == 0);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    // Recipient holds the minted coin.
    scenario.next_tx(RECIPIENT);
    {
        let coin = scenario.take_from_sender<Coin<GLYPH>>();
        assert!(coin.value() == 500);
        test_scenario::return_to_sender(&scenario, coin);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Burn contracts supply: mint 1_000_000 into treasury, burn 400_000, treasury
/// holds 600_000 and total supply drops correspondingly.
fun burn_from_treasury() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let cap_id = adopt_glyph(&mut scenario, &clock);
    enable_type(&mut scenario, b"MintCoin");
    enable_type(&mut scenario, b"BurnCoin");

    // Mint 1_000_000 into treasury (reuse the mint flow inline)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 1_000_000, option::none());
        board_voting::submit_proposal(
            &dao,
            b"MintCoin".to_ascii_string(),
            option::some(string::utf8(b"Mint")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let request = board_voting::authorize_execution(
            &mut dao, &mut proposal, &freeze, &clock, scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault, &mut treasury, &proposal, request, scenario.ctx(),
        );
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    // Burn 400_000
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = burn_coin::new<GLYPH>(cap_id, 400_000);
        board_voting::submit_proposal(
            &dao,
            b"BurnCoin".to_ascii_string(),
            option::some(string::utf8(b"Burn")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<BurnCoin<GLYPH>>>();
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<BurnCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let request = board_voting::authorize_execution(
            &mut dao, &mut proposal, &freeze, &clock, scenario.ctx(),
        );
        currency_ops::execute_burn_coin<GLYPH>(
            &mut cap_vault, &mut treasury, &proposal, request, scenario.ctx(),
        );

        assert!(treasury.balance<GLYPH>() == 600_000);

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// Returning the cap relinquishes custody: the cap leaves the vault and lands
/// with the recipient, who can then mint with it independently.
fun return_cap_relinquishes_custody() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let cap_id = adopt_glyph(&mut scenario, &clock);
    enable_type(&mut scenario, b"ReturnCurrencyCap");

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = return_currency_cap::new<GLYPH>(cap_id, RECIPIENT);
        board_voting::submit_proposal(
            &dao,
            b"ReturnCurrencyCap".to_ascii_string(),
            option::some(string::utf8(b"Hand off GLYPH")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<ReturnCurrencyCap<GLYPH>>>();
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<ReturnCurrencyCap<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let request = board_voting::authorize_execution(
            &mut dao, &mut proposal, &freeze, &clock, scenario.ctx(),
        );
        currency_ops::execute_return_currency_cap<GLYPH>(&mut cap_vault, &proposal, request);

        // Cap is gone from the vault.
        assert!(!cap_vault.contains(cap_id));

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    // Recipient now holds the TreasuryCap and can mint freely.
    scenario.next_tx(RECIPIENT);
    {
        let mut cap = scenario.take_from_sender<TreasuryCap<GLYPH>>();
        let minted = coin::mint(&mut cap, 7, scenario.ctx());
        assert!(minted.value() == 7);
        transfer::public_transfer(minted, RECIPIENT);
        test_scenario::return_to_sender(&scenario, cap);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = currency_ops::ECapNotInVault)]
/// A MintCoin naming a cap_id not in the vault aborts.
fun mint_with_unknown_cap_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    adopt_glyph(&mut scenario, &clock);
    enable_type(&mut scenario, b"MintCoin");

    // Bogus cap_id — a freshly minted, never-adopted cap.
    let bogus_cap_id;
    scenario.next_tx(CREATOR);
    {
        let cap = coin::create_treasury_cap_for_testing<GLYPH>(scenario.ctx());
        bogus_cap_id = object::id(&cap);
        transfer::public_transfer(cap, CREATOR);
    };

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(bogus_cap_id, 1, option::none());
        board_voting::submit_proposal(
            &dao,
            b"MintCoin".to_ascii_string(),
            option::some(string::utf8(b"Mint with bogus cap")),
            payload,
            &clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        proposal.vote(true, &clock, scenario.ctx());
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let request = board_voting::authorize_execution(
            &mut dao, &mut proposal, &freeze, &clock, scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault, &mut treasury, &proposal, request, scenario.ctx(),
        );
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(proposal);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}
