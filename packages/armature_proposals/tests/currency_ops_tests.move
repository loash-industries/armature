#[test_only]
module armature_proposals::currency_ops_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::enable_bypass_type::EnableBypassType;
use armature::external_execution;
use armature::governance;
use armature::proposal::{Self, ExternalExecutionCap, Proposal};
use armature::treasury_vault::TreasuryVault;
use armature_proposals::adopt_currency::{Self, AdoptCurrency};
use armature_proposals::burn_coin::{Self, BurnCoin};
use armature_proposals::currency_ops;
use armature_proposals::mint_allowance::{Self, MintAllowance};
use armature_proposals::mint_coin::{Self, MintCoin};
use armature_proposals::return_currency_cap::{Self, ReturnCurrencyCap};
use armature_proposals::type_permissions;
use std::string;
use std::type_name;
use sui::clock;
use sui::coin::{Self, Coin, TreasuryCap};
use sui::test_scenario;

const CREATOR: address = @0xA;
const RECIPIENT: address = @0xB;
const OUTSIDER: address = @0xBAD;

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
            string::utf8(b"https://example.com/logo.png"),
            scenario.ctx(),
        );
    };
}

fun enable_type<T>(scenario: &mut test_scenario::Scenario, type_key: vector<u8>, bits: u64) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0).with_permissions(
            bits,
        );
        dao.test_enable_type<T>(type_key.to_ascii_string(), config);
        test_scenario::return_shared(dao);
    };
}

/// Mint a fresh TreasuryCap<GLYPH> and adopt it through a full proposal cycle.
/// Returns the cap's object ID for use in later mint/burn proposals.
fun adopt_glyph(scenario: &mut test_scenario::Scenario, clock: &clock::Clock): ID {
    enable_type<AdoptCurrency<GLYPH>>(
        scenario,
        b"AdoptCurrency",
        type_permissions::adopt_currency(),
    );

    // Submit
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = adopt_currency::new<GLYPH>();
        board_voting::submit_proposal(
            &dao,
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );
        currency_ops::execute_adopt_currency<GLYPH>(&mut vault, cap, ticket);

        assert!(vault.contains(cap_id));
        assert!(vault.ids_for_type<TreasuryCap<GLYPH>>().contains(&cap_id));

        test_scenario::return_shared(freeze);
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
    enable_type<MintCoin<GLYPH>>(&mut scenario, b"MintCoin", type_permissions::mint());

    // Submit + vote
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 1_000_000, option::none());
        board_voting::submit_proposal(
            &dao,
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
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

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            ticket,
            scenario.ctx(),
        );

        assert!(treasury.balance<GLYPH>() == 1_000_000);

        test_scenario::return_shared(freeze);
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
    enable_type<MintCoin<GLYPH>>(&mut scenario, b"MintCoin", type_permissions::mint());

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 500, option::some(RECIPIENT));
        board_voting::submit_proposal(
            &dao,
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            ticket,
            scenario.ctx(),
        );

        // Treasury stays empty — direct issuance bypasses it.
        assert!(treasury.balance<GLYPH>() == 0);

        test_scenario::return_shared(freeze);
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
    enable_type<MintCoin<GLYPH>>(&mut scenario, b"MintCoin", type_permissions::mint());
    enable_type<BurnCoin<GLYPH>>(&mut scenario, b"BurnCoin", type_permissions::burn_coin());

    // Mint 1_000_000 into treasury (reuse the mint flow inline)
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 1_000_000, option::none());
        board_voting::submit_proposal(
            &dao,
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            ticket,
            scenario.ctx(),
        );
        test_scenario::return_shared(freeze);
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<BurnCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_burn_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            ticket,
            scenario.ctx(),
        );

        assert!(treasury.balance<GLYPH>() == 600_000);

        test_scenario::return_shared(freeze);
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
    enable_type<ReturnCurrencyCap<GLYPH>>(
        &mut scenario,
        b"ReturnCurrencyCap",
        type_permissions::return_currency_cap(),
    );

    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = return_currency_cap::new<GLYPH>(cap_id, RECIPIENT);
        board_voting::submit_proposal(
            &dao,
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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut proposal = scenario.take_shared<Proposal<ReturnCurrencyCap<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_return_currency_cap<GLYPH>(&mut cap_vault, ticket);

        // Cap is gone from the vault.
        assert!(!cap_vault.contains(cap_id));

        test_scenario::return_shared(freeze);
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
    enable_type<MintCoin<GLYPH>>(&mut scenario, b"MintCoin", type_permissions::mint());

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
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            ticket,
            scenario.ctx(),
        );
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    clock.destroy_for_testing();
    scenario.end();
}

/// The board bypass-enables MintAllowance<GLYPH> at the 80% floor with the
/// bits it needs. Returns the ExternalExecutionCap's ID.
fun enable_mint_allowance_bypass(scenario: &mut test_scenario::Scenario, clock: &clock::Clock): ID {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        let payload = external_execution::new_enable_bypass_type(
            b"MintAllowance".to_ascii_string(),
            type_name::with_defining_ids<MintAllowance<GLYPH>>(),
            proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0).with_permissions(
                type_permissions::mint(),
            ),
        );
        board_voting::submit_proposal(&dao, option::none(), payload, clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(proposal.dao_id());
        board_voting::vote(&mut proposal, &vote_dao, true, clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };
    let bypass_cap_id;
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut vault = scenario.take_shared<CapabilityVault>();
        let proposal = scenario.take_shared<Proposal<EnableBypassType>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            clock,
            scenario.ctx(),
        );
        external_execution::execute_enable_bypass_type<MintAllowance<GLYPH>>(
            &mut dao,
            &mut vault,
            ticket,
            scenario.ctx(),
        );
        bypass_cap_id = vault.ids_for_type<ExternalExecutionCap<MintAllowance<GLYPH>>>()[0];
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(dao);
    };

    bypass_cap_id
}

#[test]
/// ARMATURE-21: MintAllowance bypass is open minting. Once a DAO passes
/// EnableBypassType<MintAllowance<T>>, the ExternalExecutionCap sits in the
/// shared CapabilityVault and nothing checks who borrows it: a non-member
/// builds its own payload, mints a ticket and receives coins, with no vote.
/// This test records the current (vulnerable) behaviour; the bypass-cap task
/// (ARMATURE-31) flips it into an expected failure.
fun mint_allowance_bypass_open_to_non_member() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);

    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);

    // A non-member, with no vote and no approval, mints to itself.
    scenario.next_tx(OUTSIDER);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        assert!(!dao.governance().is_board_member(OUTSIDER));

        let payload = mint_allowance::new<GLYPH>(
            treasury_cap_id,
            1_000_000,
            option::some(OUTSIDER),
        );
        let cap: &ExternalExecutionCap<MintAllowance<GLYPH>> = cap_vault.borrow_external_cap(
            dao.id(),
            bypass_cap_id,
        );
        let ticket = external_execution::ticket_from_cap(
            cap,
            &mut dao,
            &freeze,
            option::none(),
            payload,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_allowance<GLYPH>(
            &mut cap_vault,
            &mut treasury,
            ticket,
            scenario.ctx(),
        );

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(OUTSIDER);
    {
        let coin = scenario.take_from_sender<Coin<GLYPH>>();
        assert!(coin.value() == 1_000_000);
        test_scenario::return_to_sender(&scenario, coin);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// ARMATURE-31: the bypass request escapes its handler. ticket_request is
/// public, so the non-member skips execute_mint_allowance (and its `amount`)
/// and borrows the TreasuryCap straight from the vault with the request's
/// VAULT_BORROW bit, minting any amount. Permission bits say what a type may
/// touch, not how much or who may use it. Records current behaviour.
fun mint_allowance_bypass_request_mints_past_amount() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);

    scenario.next_tx(OUTSIDER);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();

        let cap: &ExternalExecutionCap<MintAllowance<GLYPH>> = cap_vault.borrow_external_cap(
            dao.id(),
            bypass_cap_id,
        );
        let ticket = external_execution::ticket_from_cap(
            cap,
            &mut dao,
            &freeze,
            option::none(),
            mint_allowance::new<GLYPH>(treasury_cap_id, 1, option::none()),
            &clock,
            scenario.ctx(),
        );
        let treasury_cap: &mut TreasuryCap<GLYPH> = cap_vault.borrow_cap_mut(
            treasury_cap_id,
            ticket.ticket_request(),
        );
        let minted = coin::mint(treasury_cap, 1_000_000_000_000, scenario.ctx());
        transfer::public_transfer(minted, OUTSIDER);
        ticket.discharge();

        test_scenario::return_shared(freeze);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };

    scenario.next_tx(OUTSIDER);
    {
        let coin = scenario.take_from_sender<Coin<GLYPH>>();
        assert!(coin.value() == 1_000_000_000_000);
        test_scenario::return_to_sender(&scenario, coin);
    };

    clock.destroy_for_testing();
    scenario.end();
}
