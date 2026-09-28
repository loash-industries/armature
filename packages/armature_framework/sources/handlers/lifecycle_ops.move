/// Handlers for the framework's DAO-lifecycle types: CreateSubDAO, SpawnDAO,
/// SpinOutSubDAO and TransferAssets. They live in the framework because only
/// this package can mint the `Permit` for these types (see
/// `proposal::ticket_request`).
module armature::lifecycle_ops;

use armature::capability_vault::{CapabilityVault, SubDAOControl};
use armature::controller;
use armature::create_subdao::{Self, CreateSubDAO};
use armature::dao::{Self, DAO};
use armature::emergency;
use armature::governance;
use armature::proposal::ExecutionTicket;
use armature::spawn_dao::{Self, SpawnDAO};
use armature::spin_out_subdao::{Self, SpinOutSubDAO};
use armature::transfer_assets::{Self, TransferAssets};
use armature::treasury_vault::TreasuryVault;
use std::type_name::{Self, TypeName};
use sui::event;

// === Errors ===

const EVaultDAOMismatch: u64 = 0;
const ESubDAOVaultMismatch: u64 = 1;
const EDAOMismatch: u64 = 2;
const EAssetLimitExceeded: u64 = 4;
const ETargetTreasuryMismatch: u64 = 5;
const ETargetVaultMismatch: u64 = 6;
const ETargetDAOMismatch: u64 = 7;
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

public struct SubDAOCreated has copy, drop {
    controller_dao_id: ID,
    subdao_id: ID,
    control_cap_id: ID,
}

public struct SuccessorDAOSpawned has copy, drop {
    origin_dao_id: ID,
    successor_dao_id: ID,
}

public struct SubDAOSpunOut has copy, drop {
    controller_dao_id: ID,
    subdao_id: ID,
}

public struct AssetsTransferInitiated has copy, drop {
    dao_id: ID,
    target_dao_id: ID,
    coin_count: u64,
    cap_count: u64,
}

// === Handlers ===

/// Execute a CreateSubDAO proposal.
public fun execute_create_subdao(
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<CreateSubDAO>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let gov_init = governance::init_board(*payload.initial_board());

    let (subdao, freeze_admin_cap) = dao::create_subdao(
        &gov_init,
        *payload.name(),
        *payload.metadata_uri(),
        ctx,
    );

    let subdao_id = object::id(&subdao);
    let req = ticket.ticket_request(create_subdao::permit());

    let control_cap_id = vault.create_subdao_control(subdao_id, req, ctx);
    vault.store_cap(freeze_admin_cap, req);
    dao::share_subdao(subdao, control_cap_id);

    event::emit(SubDAOCreated {
        controller_dao_id: vault.dao_id(),
        subdao_id,
        control_cap_id,
    });

    ticket.discharge(create_subdao::permit());
}

/// Execute a SpawnDAO proposal.
public fun execute_spawn_dao(
    dao: &mut DAO,
    ticket: ExecutionTicket<SpawnDAO>,
    ctx: &mut TxContext,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDAOMismatch);

    let payload = ticket.ticket_payload();

    let successor_id = dao::create(
        payload.governance_init(),
        *payload.name(),
        *payload.metadata_uri(),
        ctx,
    );

    dao.set_migrating(successor_id, ticket.ticket_request(spawn_dao::permit()));

    event::emit(SuccessorDAOSpawned {
        origin_dao_id: dao.id(),
        successor_dao_id: successor_id,
    });

    ticket.discharge(spawn_dao::permit());
}

/// Execute a SpinOutSubDAO proposal.
public fun execute_spin_out_subdao(
    vault: &mut CapabilityVault,
    subdao_vault: &mut CapabilityVault,
    subdao: &mut DAO,
    ticket: ExecutionTicket<SpinOutSubDAO>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    assert!(subdao_vault.dao_id() == payload.subdao_id(), ESubDAOVaultMismatch);

    let req = ticket.ticket_request(spin_out_subdao::permit());

    let (control, loan) = vault.loan_cap<SubDAOControl, SpinOutSubDAO>(
        payload.control_cap_id(),
        req,
    );

    let subdao_req = controller::privileged_submit(
        &control,
        subdao,
        b"SpinOutSubDAO".to_ascii_string(),
        option::some(std::string::utf8(b"Controller-initiated spin-out")),
        spin_out_subdao::new(
            payload.subdao_id(),
            payload.control_cap_id(),
            payload.freeze_admin_cap_id(),
            *payload.spawn_dao_config(),
            *payload.spin_out_subdao_config(),
            *payload.create_subdao_config(),
        ),
        ctx,
    );

    subdao.clear_controller(&subdao_req);
    subdao.enable_proposal_type<SpawnDAO, SpinOutSubDAO>(
        b"SpawnDAO".to_ascii_string(),
        *payload.spawn_dao_config(),
        &subdao_req,
    );
    subdao.enable_proposal_type<SpinOutSubDAO, SpinOutSubDAO>(
        b"SpinOutSubDAO".to_ascii_string(),
        *payload.spin_out_subdao_config(),
        &subdao_req,
    );
    subdao.enable_proposal_type<CreateSubDAO, SpinOutSubDAO>(
        b"CreateSubDAO".to_ascii_string(),
        *payload.create_subdao_config(),
        &subdao_req,
    );

    controller::privileged_consume(subdao_req, &control);
    vault.return_cap(control, loan);

    let freeze_cap = vault.extract_cap<emergency::FreezeAdminCap, SpinOutSubDAO>(
        payload.freeze_admin_cap_id(),
        req,
    );
    subdao_vault.receive_cap(freeze_cap, req);

    vault.destroy_subdao_control(payload.control_cap_id(), req);

    event::emit(SubDAOSpunOut {
        controller_dao_id: vault.dao_id(),
        subdao_id: payload.subdao_id(),
    });

    ticket.discharge(spin_out_subdao::permit());
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
    let dao_id = ticket.ticket_dao_id();
    let payload = ticket.ticket_payload();

    assert!(source_treasury.dao_id() == dao_id, EVaultDAOMismatch);
    assert!(source_cap_vault.dao_id() == dao_id, EVaultDAOMismatch);
    assert!(
        payload.coin_types().length() + payload.cap_ids().length() <= MAX_TRANSFER_ASSETS,
        EAssetLimitExceeded,
    );

    event::emit(AssetsTransferInitiated {
        dao_id,
        target_dao_id: payload.target_dao_id(),
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
    assert!(target.dao_id() == payload.target_dao_id(), ETargetDAOMismatch);

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
    assert!(target.dao_id() == payload.target_dao_id(), ETargetDAOMismatch);

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
