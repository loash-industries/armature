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
use armature_proposals::configure_mint_allowance::{Self, ConfigureMintAllowance};
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
const MINTER: address = @0xC;

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
        // Every currency type that borrows does so on TreasuryCap<GLYPH>; the
        // scope is inert for types without VAULT_BORROW.
        let config = proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0)
            .with_permissions(bits)
            .with_borrow_scope(type_permissions::currency_scope<GLYPH>());
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

#[test, expected_failure(abort_code = currency_ops::EVaultDAOMismatch)]
/// With recipient = none the minted supply lands in `treasury_vault`, so the
/// executor cannot pass another DAO's treasury and divert it there.
fun mint_into_foreign_treasury_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let cap_id = adopt_glyph(&mut scenario, &clock);
    enable_type<MintCoin<GLYPH>>(&mut scenario, b"MintCoin", type_permissions::mint());

    scenario.next_tx(CREATOR);
    let dao_id = {
        let dao = scenario.take_shared<DAO>();
        let payload = mint_coin::new<GLYPH>(cap_id, 1_000_000, option::none());
        board_voting::submit_proposal(&dao, option::none(), payload, &clock, scenario.ctx());
        let id = dao.id();
        test_scenario::return_shared(dao);
        id
    };
    scenario.next_tx(CREATOR);
    {
        let mut proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let vote_dao = scenario.take_shared_by_id<DAO>(dao_id);
        board_voting::vote(&mut proposal, &vote_dao, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_dao);
        test_scenario::return_shared(proposal);
    };

    // The executor's own DAO, whose treasury should not receive the mint.
    scenario.next_tx(OUTSIDER);
    let other_id = dao::create(
        &governance::init_board(vector[OUTSIDER]),
        string::utf8(b"Other DAO"),
        string::utf8(b""),
        scenario.ctx(),
    );

    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared_by_id<DAO>(dao_id);
        let other = scenario.take_shared_by_id<DAO>(other_id);
        let mut cap_vault = scenario.take_shared_by_id<CapabilityVault>(dao.capability_vault_id());
        let mut other_treasury = scenario.take_shared_by_id<TreasuryVault>(other.treasury_id());
        let proposal = scenario.take_shared<Proposal<MintCoin<GLYPH>>>();
        let freeze = scenario.take_shared_by_id<EmergencyFreeze>(dao.emergency_freeze_id());

        let ticket = board_voting::ticket_from_vote(
            &mut dao,
            proposal,
            &freeze,
            &clock,
            scenario.ctx(),
        );
        currency_ops::execute_mint_coin<GLYPH>(
            &mut cap_vault,
            &mut other_treasury,
            ticket,
            scenario.ctx(),
        );

        abort 0
    }
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
            proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0)
                .with_permissions(type_permissions::mint())
                .with_borrow_scope(type_permissions::currency_scope<GLYPH>()),
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

// ARMATURE-21 / ARMATURE-31: a non-member used to borrow the
// ExternalExecutionCap<MintAllowance<T>> from the shared vault, mint a bypass
// ticket with a payload of its choosing, and either run execute_mint_allowance
// on it or spend the request directly to mint past `amount`. Neither compiles
// any more: ticket_from_cap, ticket_request and discharge all take
// Permit<MintAllowance<T>>, which only armature_proposals can mint, and the
// package exposes no bypass entry point for MintAllowance. Bypass-enabling the
// type leaves a cap in the vault that nothing outside the package can use.

#[test]
/// EnableBypassType<MintAllowance<T>> still passes and stores the cap; the cap
/// alone gives an outsider nothing (see the note above).
fun mint_allowance_bypass_cap_is_stored() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);

    scenario.next_tx(OUTSIDER);
    {
        let cap_vault = scenario.take_shared<CapabilityVault>();
        assert!(cap_vault.contains(bypass_cap_id));
        test_scenario::return_shared(cap_vault);
    };

    clock.destroy_for_testing();
    scenario.end();
}

// === MintAllowance bypass: allowlisted minting (ARMATURE-31) ===

/// Enable ConfigureMintAllowance<GLYPH> on first use (it needs no bits) and
/// execute one configuration payload through a single-vote proposal.
fun configure_allowance(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    add: vector<address>,
    max_per_call: Option<u64>,
    enabled: Option<bool>,
) {
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let name = type_name::with_defining_ids<ConfigureMintAllowance<GLYPH>>();
        if (!dao.is_type_name_enabled(&name)) {
            dao.test_enable_type<ConfigureMintAllowance<GLYPH>>(
                b"ConfigureMintAllowance".to_ascii_string(),
                proposal::new_config(1, 5_000, 0, 604_800_000, 0, 0).with_permissions(
                    type_permissions::configure_mint_allowance(),
                ),
            );
        };
        let ticket = board_voting::submit_vote_execute<ConfigureMintAllowance<GLYPH>>(
            &mut dao,
            option::none(),
            configure_mint_allowance::new<GLYPH>(add, vector[], max_per_call, enabled),
            &freeze,
            clock,
            scenario.ctx(),
        );
        configure_mint_allowance::execute_configure_mint_allowance<GLYPH>(&mut dao, ticket);
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };
}

/// `sender` mints `amount` GLYPH to itself through the bypass.
fun bypass_mint(
    scenario: &mut test_scenario::Scenario,
    clock: &clock::Clock,
    sender: address,
    bypass_cap_id: ID,
    treasury_cap_id: ID,
    amount: u64,
) {
    scenario.next_tx(sender);
    {
        let mut dao = scenario.take_shared<DAO>();
        let mut cap_vault = scenario.take_shared<CapabilityVault>();
        let mut treasury = scenario.take_shared<TreasuryVault>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        currency_ops::mint_allowance_bypass<GLYPH>(
            &mut dao,
            &mut cap_vault,
            &mut treasury,
            &freeze,
            bypass_cap_id,
            treasury_cap_id,
            amount,
            option::some(sender),
            clock,
            scenario.ctx(),
        );
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(treasury);
        test_scenario::return_shared(cap_vault);
        test_scenario::return_shared(dao);
    };
}

#[test]
/// An allowlisted minter mints within the per-call cap, with no vote, and
/// receives the coins.
fun mint_allowance_bypass_allowed_minter_mints_within_cap() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);
    configure_allowance(
        &mut scenario,
        &clock,
        vector[MINTER],
        option::some(1_000),
        option::some(true),
    );

    bypass_mint(&mut scenario, &clock, MINTER, bypass_cap_id, treasury_cap_id, 700);

    scenario.next_tx(MINTER);
    {
        let minted = scenario.take_from_sender<Coin<GLYPH>>();
        assert!(minted.value() == 700);
        scenario.return_to_sender(minted);
    };

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = currency_ops::ENotAllowedMinter)]
/// ARMATURE-31 acceptance: a caller who is not an approved minter cannot mint
/// a bypass ticket, even though the cap sits in the shared vault.
fun mint_allowance_bypass_outsider_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);
    configure_allowance(
        &mut scenario,
        &clock,
        vector[MINTER],
        option::some(1_000),
        option::some(true),
    );

    bypass_mint(&mut scenario, &clock, OUTSIDER, bypass_cap_id, treasury_cap_id, 1);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = currency_ops::EExceedsAllowance)]
fun mint_allowance_bypass_over_cap_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);
    configure_allowance(
        &mut scenario,
        &clock,
        vector[MINTER],
        option::some(1_000),
        option::some(true),
    );

    bypass_mint(&mut scenario, &clock, MINTER, bypass_cap_id, treasury_cap_id, 1_001);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = currency_ops::EAllowanceNotConfigured)]
/// A bypass cap with no ConfigureMintAllowance vote behind it mints nothing.
fun mint_allowance_bypass_unconfigured_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);

    bypass_mint(&mut scenario, &clock, MINTER, bypass_cap_id, treasury_cap_id, 1);

    clock.destroy_for_testing();
    scenario.end();
}

#[test, expected_failure(abort_code = currency_ops::EAllowanceDisabled)]
/// The kill-switch stops every minter without disabling the type.
fun mint_allowance_bypass_disabled_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1000);

    create_dao(&mut scenario);
    let treasury_cap_id = adopt_glyph(&mut scenario, &clock);
    let bypass_cap_id = enable_mint_allowance_bypass(&mut scenario, &clock);
    configure_allowance(
        &mut scenario,
        &clock,
        vector[MINTER],
        option::some(1_000),
        option::some(true),
    );
    configure_allowance(&mut scenario, &clock, vector[], option::none(), option::some(false));

    bypass_mint(&mut scenario, &clock, MINTER, bypass_cap_id, treasury_cap_id, 1);

    clock.destroy_for_testing();
    scenario.end();
}
