/// TransferAssets moves only the assets its payload lists, only into the
/// payload's target, and every one of them before the ticket can close.
#[test_only]
module armature::lifecycle_ops_tests;

use armature::board_voting;
use armature::capability_vault::CapabilityVault;
use armature::dao::{Self, DAO};
use armature::emergency::EmergencyFreeze;
use armature::governance;
use armature::lifecycle_ops::{Self, AssetTransfer};
use armature::proposal;
use armature::transfer_assets::{Self, TransferAssets};
use armature::treasury_vault::TreasuryVault;
use std::string;
use std::type_name::{Self, TypeName};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

const CREATOR: address = @0xA;

/// A second coin type for the treasury.
public struct OTHER has drop {}

fun create_dao(scenario: &mut Scenario): ID {
    scenario.next_tx(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    dao::create(&init, string::utf8(b"DAO"), string::utf8(b""), scenario.ctx())
}

/// Three DAOs: `source` holds 1_000 SUI and 500 OTHER and has TransferAssets
/// enabled; `target` is the payload's target; `other` is an unrelated DAO.
/// Mints a TransferAssets ticket on `source` listing `coin_types`, begins the
/// transfer and hands it to `$f` with the three treasuries.
macro fun with_transfer(
    $coin_types: vector<TypeName>,
    $f: |
        &mut AssetTransfer,
        &mut TreasuryVault,
        &mut TreasuryVault,
        &mut TreasuryVault,
        &mut TxContext,
    |,
) {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());
    let source_id = create_dao(&mut scenario);
    let target_id = create_dao(&mut scenario);
    let other_id = create_dao(&mut scenario);

    scenario.next_tx(CREATOR);
    let mut source = scenario.take_shared_by_id<DAO>(source_id);
    let target = scenario.take_shared_by_id<DAO>(target_id);
    let other = scenario.take_shared_by_id<DAO>(other_id);
    let mut source_treasury = scenario.take_shared_by_id<TreasuryVault>(source.treasury_id());
    let mut target_treasury = scenario.take_shared_by_id<TreasuryVault>(target.treasury_id());
    let mut other_treasury = scenario.take_shared_by_id<TreasuryVault>(other.treasury_id());
    let source_vault = scenario.take_shared_by_id<CapabilityVault>(source.capability_vault_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(source.emergency_freeze_id());

    source_treasury.deposit(coin::mint_for_testing<SUI>(1_000, scenario.ctx()), scenario.ctx());
    source_treasury.deposit(coin::mint_for_testing<OTHER>(500, scenario.ctx()), scenario.ctx());
    source.test_enable_type<TransferAssets>(
        b"TransferAssets".to_ascii_string(),
        proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0),
    );

    let payload = transfer_assets::new(
        target_id,
        target.treasury_id(),
        target.capability_vault_id(),
        $coin_types,
        vector[],
    );
    let ticket = board_voting::submit_vote_execute(
        &mut source,
        option::none(),
        payload,
        &freeze,
        &clock,
        scenario.ctx(),
    );
    let mut transfer = lifecycle_ops::begin_transfer_assets(
        &source_treasury,
        &source_vault,
        ticket,
    );
    $f(
        &mut transfer,
        &mut source_treasury,
        &mut target_treasury,
        &mut other_treasury,
        scenario.ctx(),
    );
    transfer.finish_transfer_assets();

    test_scenario::return_shared(freeze);
    test_scenario::return_shared(source_vault);
    test_scenario::return_shared(other_treasury);
    test_scenario::return_shared(target_treasury);
    test_scenario::return_shared(source_treasury);
    test_scenario::return_shared(other);
    test_scenario::return_shared(target);
    test_scenario::return_shared(source);
    clock.destroy_for_testing();
    scenario.end();
}

#[test]
/// A listed coin type moves in full to the payload's target treasury; an
/// unlisted one stays put.
fun transfer_assets_moves_listed_coin_to_target() {
    with_transfer!(vector[type_name::with_original_ids<SUI>()], |t, source, target, _, ctx| {
        t.transfer_coin<SUI>(source, target, ctx);
        assert!(source.balance<SUI>() == 0);
        assert!(target.balance<SUI>() == 1_000);
        assert!(source.balance<OTHER>() == 500);
    });
}

#[test, expected_failure(abort_code = lifecycle_ops::EAssetsRemaining)]
/// The ticket cannot close until every listed asset has moved.
fun transfer_assets_finish_with_unmoved_asset_aborts() {
    with_transfer!(vector[type_name::with_original_ids<SUI>()], |_, _, _, _, _| {});
}

#[test, expected_failure(abort_code = lifecycle_ops::EAssetNotListed)]
/// A coin type the payload does not list cannot be moved.
fun transfer_assets_unlisted_coin_aborts() {
    with_transfer!(vector[type_name::with_original_ids<SUI>()], |t, source, target, _, ctx| {
        t.transfer_coin<OTHER>(source, target, ctx);
    });
}

#[test, expected_failure(abort_code = lifecycle_ops::EAssetNotListed)]
/// A listed coin type moves once.
fun transfer_assets_same_coin_twice_aborts() {
    with_transfer!(vector[type_name::with_original_ids<SUI>()], |t, source, target, _, ctx| {
        t.transfer_coin<SUI>(source, target, ctx);
        t.transfer_coin<SUI>(source, target, ctx);
    });
}

#[test, expected_failure(abort_code = lifecycle_ops::ETargetTreasuryMismatch)]
/// Coins go only to the payload's target treasury, not one the executor picks.
fun transfer_assets_wrong_target_aborts() {
    with_transfer!(vector[type_name::with_original_ids<SUI>()], |t, source, _, other, ctx| {
        t.transfer_coin<SUI>(source, other, ctx);
    });
}
