/// Handlers for the framework's OU-lifecycle types: CreateSubOU, SpawnOU,
/// SpinOutSubOU and TransferAssets. They live in the framework because only
/// this package can mint the `Permit` for these types (see
/// `proposal::ticket_request`).
module armature::lifecycle_ops;

use armature::capability_vault::{CapabilityVault, SubOUControl};
use armature::controller;
use armature::create_subou::{Self, CreateSubOU};
use armature::ou::{Self, OU};
use armature::emergency;
use armature::governance;
use armature::proposal::ExecutionTicket;
use armature::spawn_ou::{Self, SpawnOU};
use armature::spin_out_subou::{Self, SpinOutSubOU};
use armature::transfer_assets::{Self, TransferAssets};
use armature::treasury_vault::TreasuryVault;
use std::type_name::{Self, TypeName};
use sui::event;

// === Errors ===

const EVaultOUMismatch: u64 = 0;
const ESubOUVaultMismatch: u64 = 1;
const EOUMismatch: u64 = 2;
const EAssetLimitExceeded: u64 = 4;
const ETargetTreasuryMismatch: u64 = 5;
const ETargetVaultMismatch: u64 = 6;
const ETargetOUMismatch: u64 = 7;
/// The source treasury or vault is not the one the transfer was begun with.
const ESourceMismatch: u64 = 8;
/// The coin type or cap ID is not in the TransferAssets payload, or has
/// already been moved.
const EAssetNotListed: u64 = 9;
/// finish_transfer_assets called before every listed asset was moved.
const EAssetsRemaining: u64 = 10;

// === Constants ===

const MAX_TRANSFER_ASSETS: u64 = 50;

// === Structs ===

/// Hot potato for a TransferAssets execution. Holds the ticket, so the
/// request never leaves this module: each listed asset is moved by
/// `transfer_coin` / `transfer_cap` straight into the payload's target
/// treasury or vault, and `finish_transfer_assets` aborts until every listed
/// asset has moved.
public struct AssetTransfer {
    ticket: ExecutionTicket<TransferAssets>,
    source_treasury_id: ID,
    source_vault_id: ID,
    coins_left: vector<TypeName>,
    caps_left: vector<ID>,
}

// === Events ===

public struct SubOUCreated has copy, drop {
    controller_ou_id: ID,
    subou_id: ID,
    control_cap_id: ID,
}

public struct SuccessorOUSpawned has copy, drop {
    origin_ou_id: ID,
    successor_ou_id: ID,
}

public struct SubOUSpunOut has copy, drop {
    controller_ou_id: ID,
    subou_id: ID,
}

public struct AssetsTransferInitiated has copy, drop {
    ou_id: ID,
    target_ou_id: ID,
    coin_count: u64,
    cap_count: u64,
}

// === Handlers ===

/// Execute a CreateSubOU proposal.
public fun execute_create_subou(
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<CreateSubOU>,
    ctx: &mut TxContext,
) {
    assert!(vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    let gov_init = governance::init_board(*payload.initial_board());

    let (subou, freeze_admin_cap) = ou::create_subou(
        &gov_init,
        *payload.name(),
        *payload.metadata_uri(),
        ctx,
    );

    let subou_id = object::id(&subou);
    let req = ticket.ticket_request(create_subou::permit());

    let control_cap_id = vault.create_subou_control(subou_id, req, ctx);
    vault.store_cap(freeze_admin_cap, req);
    ou::share_subou(subou, control_cap_id);

    event::emit(SubOUCreated {
        controller_ou_id: vault.ou_id(),
        subou_id,
        control_cap_id,
    });

    ticket.discharge(create_subou::permit());
}

/// Execute a SpawnOU proposal.
public fun execute_spawn_ou(
    ou: &mut OU,
    ticket: ExecutionTicket<SpawnOU>,
    ctx: &mut TxContext,
) {
    assert!(ou.id() == ticket.ticket_ou_id(), EOUMismatch);

    let payload = ticket.ticket_payload();

    let successor_id = ou::create(
        payload.governance_init(),
        *payload.name(),
        *payload.metadata_uri(),
        ctx,
    );

    ou.set_migrating(successor_id, ticket.ticket_request(spawn_ou::permit()));

    event::emit(SuccessorOUSpawned {
        origin_ou_id: ou.id(),
        successor_ou_id: successor_id,
    });

    ticket.discharge(spawn_ou::permit());
}

/// Execute a SpinOutSubOU proposal.
public fun execute_spin_out_subou(
    vault: &mut CapabilityVault,
    subou_vault: &mut CapabilityVault,
    subou: &mut OU,
    ticket: ExecutionTicket<SpinOutSubOU>,
    ctx: &mut TxContext,
) {
    assert!(vault.ou_id() == ticket.ticket_ou_id(), EVaultOUMismatch);

    let payload = ticket.ticket_payload();
    assert!(subou_vault.ou_id() == payload.subou_id(), ESubOUVaultMismatch);

    let req = ticket.ticket_request(spin_out_subou::permit());

    let (control, loan) = vault.loan_cap<SubOUControl, SpinOutSubOU>(
        payload.control_cap_id(),
        req,
    );

    let subou_req = controller::privileged_submit(
        &control,
        subou,
        b"SpinOutSubOU".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated spin-out")),
        spin_out_subou::new(
            payload.subou_id(),
            payload.control_cap_id(),
            payload.freeze_admin_cap_id(),
            *payload.spawn_ou_config(),
            *payload.spin_out_subou_config(),
            *payload.create_subou_config(),
        ),
        ctx,
    );

    subou.clear_controller(&subou_req);
    subou.enable_proposal_type<SpawnOU, SpinOutSubOU>(
        b"SpawnOU".to_ascii_string(),
        *payload.spawn_ou_config(),
        &subou_req,
    );
    subou.enable_proposal_type<SpinOutSubOU, SpinOutSubOU>(
        b"SpinOutSubOU".to_ascii_string(),
        *payload.spin_out_subou_config(),
        &subou_req,
    );
    subou.enable_proposal_type<CreateSubOU, SpinOutSubOU>(
        b"CreateSubOU".to_ascii_string(),
        *payload.create_subou_config(),
        &subou_req,
    );

    controller::privileged_consume(subou_req, &control);
    vault.return_cap(control, loan);

    let freeze_cap = vault.extract_cap<emergency::FreezeAdminCap, SpinOutSubOU>(
        payload.freeze_admin_cap_id(),
        req,
    );
    subou_vault.receive_cap(freeze_cap, req);

    vault.destroy_subou_control(payload.control_cap_id(), req);

    event::emit(SubOUSpunOut {
        controller_ou_id: vault.ou_id(),
        subou_id: payload.subou_id(),
    });

    ticket.discharge(spin_out_subou::permit());
}

// === TransferAssets ===
//
// PTB flow:
//   1. ticket_from_vote(...) → ExecutionTicket<TransferAssets>
//   2. begin_transfer_assets(...) → AssetTransfer
//   3. transfer_coin<T>(...) once per payload coin type (moves the full balance)
//   4. transfer_cap<T>(...) once per payload cap ID
//   5. finish_transfer_assets(transfer)

/// Validate a TransferAssets ticket against the source vaults and start the
/// transfer. Emits AssetsTransferInitiated.
public fun begin_transfer_assets(
    source_treasury: &TreasuryVault,
    source_cap_vault: &CapabilityVault,
    ticket: ExecutionTicket<TransferAssets>,
): AssetTransfer {
    let ou_id = ticket.ticket_ou_id();
    let payload = ticket.ticket_payload();

    assert!(source_treasury.ou_id() == ou_id, EVaultOUMismatch);
    assert!(source_cap_vault.ou_id() == ou_id, EVaultOUMismatch);
    assert!(
        payload.coin_types().length() + payload.cap_ids().length() <= MAX_TRANSFER_ASSETS,
        EAssetLimitExceeded,
    );

    event::emit(AssetsTransferInitiated {
        ou_id,
        target_ou_id: payload.target_ou_id(),
        coin_count: payload.coin_types().length(),
        cap_count: payload.cap_ids().length(),
    });

    let coins_left = *payload.coin_types();
    let caps_left = *payload.cap_ids();
    AssetTransfer {
        ticket,
        source_treasury_id: object::id(source_treasury),
        source_vault_id: object::id(source_cap_vault),
        coins_left,
        caps_left,
    }
}

/// Move the full balance of coin type `T` from the source treasury to the
/// payload's target treasury. `T` must be listed in the payload and not yet moved.
public fun transfer_coin<T>(
    self: &mut AssetTransfer,
    source: &mut TreasuryVault,
    target: &mut TreasuryVault,
    ctx: &mut TxContext,
) {
    assert!(object::id(source) == self.source_treasury_id, ESourceMismatch);
    let payload = self.ticket.ticket_payload();
    assert!(object::id(target) == payload.target_treasury_id(), ETargetTreasuryMismatch);
    assert!(target.ou_id() == payload.target_ou_id(), ETargetOUMismatch);

    let (found, i) = self.coins_left.index_of(&type_name::with_original_ids<T>());
    assert!(found, EAssetNotListed);
    self.coins_left.swap_remove(i);

    let amount = source.balance<T>();
    if (amount > 0) {
        let req = self.ticket.ticket_request(transfer_assets::permit());
        let coin = source.withdraw<T, TransferAssets>(amount, req, ctx);
        target.deposit(coin, ctx);
    };
}

/// Move capability `cap_id` from the source vault to the payload's target
/// vault. `cap_id` must be listed in the payload and not yet moved.
public fun transfer_cap<T: key + store>(
    self: &mut AssetTransfer,
    source: &mut CapabilityVault,
    target: &mut CapabilityVault,
    cap_id: ID,
) {
    assert!(object::id(source) == self.source_vault_id, ESourceMismatch);
    let payload = self.ticket.ticket_payload();
    assert!(object::id(target) == payload.target_vault_id(), ETargetVaultMismatch);
    assert!(target.ou_id() == payload.target_ou_id(), ETargetOUMismatch);

    let (found, i) = self.caps_left.index_of(&cap_id);
    assert!(found, EAssetNotListed);
    self.caps_left.swap_remove(i);

    let req = self.ticket.ticket_request(transfer_assets::permit());
    let cap: T = source.extract_cap(cap_id, req);
    target.receive_cap(cap, req);
}

/// Close the transfer. Aborts with EAssetsRemaining unless every listed coin
/// type and cap has been moved.
public fun finish_transfer_assets(self: AssetTransfer) {
    let AssetTransfer { ticket, source_treasury_id: _, source_vault_id: _, coins_left, caps_left } =
        self;
    assert!(coins_left.is_empty() && caps_left.is_empty(), EAssetsRemaining);
    ticket.discharge(transfer_assets::permit());
}
