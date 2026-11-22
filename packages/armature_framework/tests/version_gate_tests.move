/// ARMATURE-45: one abort test per gated function, part 1 (object modules:
/// `ou`, `capability_vault`, `treasury_vault`, `charter`, `emergency`,
/// `encrypted_entry`, `tribe`). Parts 2 and 3 are `version_gate_tests_proposals`
/// and `version_gate_tests_handlers`; this module also holds the setup helpers
/// they share.
///
/// Each test raises one floor (an object's `min_version`, or a hot potato's
/// stamp) to `version::retired_floor_for_testing()` and calls the function,
/// which must abort with `version::EVersionRetired`. The check is the
/// function's first statement, so the other arguments only need to type-check.
/// `scripts/check_version_gates.py` fails CI when a gated function has no test
/// named `<function>_retired` (`<function>_retired_<module>` when the name is
/// gated in more than one module).
#[test_only]
module armature::version_gate_tests;

use armature::capability_vault::{Self, CapabilityVault};
use armature::charter::Charter;
use armature::emergency::{EmergencyFreeze, FreezeAdminCap};
use armature::encrypted_entry::{Self, EncryptedEntry};
use armature::governance;
use armature::ou::{Self, OU};
use armature::proposal::{Self, ExecutionRequest, ExecutionTicket, ProposalConfig};
use armature::treasury_vault::TreasuryVault;
use armature::tribe;
use armature::version;
use std::string::{Self, String};
use std::type_name;
use sui::clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};

const CREATOR: address = @0xA;
const MEMBER: address = @0xB;
const PROPOSAL: address = @0x1;
const OTHER: address = @0x2;

/// Payload type for the requests and tickets these tests mint.
public struct Dummy has drop, store {}

/// A `key + store` object to store, borrow and move.
public struct TestCap has key, store { id: UID }

// === Shared helpers ===

public fun creator(): address { CREATOR }

public fun member(): address { MEMBER }

/// An ID that names no object; for arguments the aborting call never reads.
public fun other_id(): ID { OTHER.to_id() }

public fun retired(): u64 { version::retired_floor_for_testing() }

public fun s(bytes: vector<u8>): String { string::utf8(bytes) }

/// Start a scenario with one OU (its four companions shared, its
/// FreezeAdminCap sent to CREATOR), in a fresh transaction.
public fun begin(): (Scenario, ID) {
    let mut sc = ts::begin(CREATOR);
    let ou_id = ou::create(
        &governance::init_board(vector[CREATOR, MEMBER]),
        s(b"OU"),
        s(b"u"),
        sc.ctx(),
    );
    sc.next_tx(CREATOR);
    (sc, ou_id)
}

/// A request for `ou_id` stamped at MIN_SUPPORTED with every permission bit.
public fun request<P>(ou_id: ID): ExecutionRequest<P> {
    proposal::new_execution_request_for_testing<P>(ou_id, PROPOSAL.to_id())
}

/// `request`, stamped retired.
public fun retired_request<P>(ou_id: ID): ExecutionRequest<P> {
    proposal::with_min_version_for_testing(request<P>(ou_id), retired())
}

/// A Standalone ticket for `ou_id` stamped at MIN_SUPPORTED.
public fun ticket<P: store>(ou_id: ID, payload: P): ExecutionTicket<P> {
    proposal::new_standalone_ticket_for_testing(ou_id, PROPOSAL.to_id(), payload, 0, 0)
}

/// `ticket`, stamped retired.
public fun retired_ticket<P: store>(ou_id: ID, payload: P): ExecutionTicket<P> {
    proposal::ticket_with_min_version_for_testing(ticket(ou_id, payload), retired())
}

public fun config(): ProposalConfig { proposal::new_config(5_000, 5_000, 0, 604_800_000, 0, 0) }

public fun new_cap(sc: &mut Scenario): TestCap { TestCap { id: object::new(sc.ctx()) } }

public fun retired_ou(sc: &Scenario): OU {
    let mut ou = sc.take_shared<OU>();
    ou.set_min_version_for_testing(retired());
    ou
}

public fun retired_vault(sc: &Scenario): CapabilityVault {
    let mut vault = sc.take_shared<CapabilityVault>();
    vault.set_min_version_for_testing(retired());
    vault
}

public fun retired_treasury(sc: &Scenario): TreasuryVault {
    let mut treasury = sc.take_shared<TreasuryVault>();
    treasury.set_min_version_for_testing(retired());
    treasury
}

public fun retired_charter(sc: &Scenario): Charter {
    let mut charter = sc.take_shared<Charter>();
    charter.set_min_version_for_testing(retired());
    charter
}

public fun retired_freeze(sc: &Scenario): EmergencyFreeze {
    let mut freeze = sc.take_shared<EmergencyFreeze>();
    freeze.set_min_version_for_testing(retired());
    freeze
}

/// A second CapabilityVault for `ou_id` at MIN_SUPPORTED, for functions that
/// take two vaults.
public fun second_vault(sc: &mut Scenario, ou_id: ID): CapabilityVault {
    capability_vault::new(ou_id, version::min_supported(), sc.ctx())
}

/// Publish an EncryptedEntry on the scenario's OU (as CREATOR, a member),
/// then start a fresh transaction.
fun publish_entry_for_test(sc: &mut Scenario) {
    let mut ou = sc.take_shared<OU>();
    encrypted_entry::publish_entry(&mut ou, s(b"loc"), s(b"desc"), sc.ctx());
    ts::return_shared(ou);
    sc.next_tx(CREATOR);
}

fun retired_entry(sc: &Scenario): EncryptedEntry {
    let mut entry = sc.take_shared<EncryptedEntry>();
    entry.set_min_version_for_testing(retired());
    entry
}

// === ou ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun destroy_retired() {
    let (sc, _) = begin();
    let ou = retired_ou(&sc);
    ou::destroy(
        ou,
        sc.take_shared<TreasuryVault>(),
        sc.take_shared<CapabilityVault>(),
        sc.take_shared<Charter>(),
        sc.take_shared<EmergencyFreeze>(),
    );
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun set_board_governance_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.set_board_governance(vector[OTHER], vector[], &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun add_board_member_governance_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.add_board_member_governance(OTHER, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun add_board_members_governance_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    let (_, _) = ou.add_board_members_governance(vector[OTHER], &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun remove_board_member_governance_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.remove_board_member_governance(MEMBER, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun remove_board_members_governance_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    let _ = ou.remove_board_members_governance(vector[MEMBER], &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enable_proposal_type_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.enable_proposal_type<Dummy, Dummy>(b"Dummy".to_ascii_string(), config(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun disable_proposal_type_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.disable_proposal_type(type_name::with_defining_ids<Dummy>(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun update_proposal_config_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.update_proposal_config(type_name::with_defining_ids<Dummy>(), config(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun set_execution_paused_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.set_execution_paused(true, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun set_controller_paused_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.set_controller_paused(true, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun clear_controller_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.clear_controller(&req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun set_migrating_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.set_migrating(other_id(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun borrow_type_state_mut_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    let _ = ou.borrow_type_state_mut<Dummy, u64>(&req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun init_type_state_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    ou.init_type_state<Dummy, u64>(0, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun remove_type_state_retired() {
    let (sc, ou_id) = begin();
    let mut ou = retired_ou(&sc);
    let req = request<Dummy>(ou_id);
    let _ = ou.remove_type_state<Dummy, u64>(&req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_ou() {
    let (sc, _) = begin();
    let mut ou = retired_ou(&sc);
    ou.enforce_version();
    abort
}

// === capability_vault ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun store_cap_retired() {
    let (mut sc, ou_id) = begin();
    let cap = new_cap(&mut sc);
    let mut vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    vault.store_cap(cap, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun receive_cap_authorized_retired() {
    let (mut sc, ou_id) = begin();
    let cap = new_cap(&mut sc);
    let mut vault = retired_vault(&sc);
    let sendreq = request<Dummy>(other_id());
    let recvreq = request<Dummy>(ou_id);
    vault.receive_cap_authorized(cap, &sendreq, &recvreq);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun borrow_cap_retired() {
    let (sc, ou_id) = begin();
    let vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    let _ = vault.borrow_cap<TestCap, Dummy>(other_id(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun borrow_external_cap_retired() {
    let (sc, ou_id) = begin();
    let vault = retired_vault(&sc);
    let _ = vault.borrow_external_cap<Dummy>(ou_id, other_id());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun borrow_cap_mut_retired() {
    let (sc, ou_id) = begin();
    let mut vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    let _ = vault.borrow_cap_mut<TestCap, Dummy>(other_id(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun loan_cap_retired() {
    let (sc, ou_id) = begin();
    let mut vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    let (_cap, _loan) = vault.loan_cap<TestCap, Dummy>(other_id(), &req);
    abort
}

/// Take a real loan from the scenario's vault: store a TestCap, then loan it
/// with a request whose borrow scope names TestCap.
fun loan_from(
    sc: &mut Scenario,
    vault: &mut CapabilityVault,
    ou_id: ID,
): (TestCap, capability_vault::CapLoan) {
    let cap = new_cap(sc);
    let cap_id = object::id(&cap);
    vault.store_cap_for_testing(cap);
    let req = proposal::with_borrow_scope_for_testing(
        request<Dummy>(ou_id),
        vector[type_name::with_defining_ids<TestCap>()],
    );
    let (cap, loan) = vault.loan_cap<TestCap, Dummy>(cap_id, &req);
    proposal::consume_execution_request_for_testing(req);
    (cap, loan)
}

/// The vault's floor was raised after the loan went out.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun return_cap_retired() {
    let (mut sc, ou_id) = begin();
    let mut vault = sc.take_shared<CapabilityVault>();
    let (cap, loan) = loan_from(&mut sc, &mut vault, ou_id);
    vault.set_min_version_for_testing(retired());
    vault.return_cap(cap, loan);
    abort
}

/// The loan is stamped above VERSION (a newer release lent it); the vault is live.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun return_cap_retired_loan() {
    let (mut sc, ou_id) = begin();
    let mut vault = sc.take_shared<CapabilityVault>();
    let (cap, loan) = loan_from(&mut sc, &mut vault, ou_id);
    let loan = capability_vault::cap_loan_with_min_version_for_testing(loan, retired());
    vault.return_cap(cap, loan);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun extract_cap_retired() {
    let (sc, ou_id) = begin();
    let mut vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    let _cap = vault.extract_cap<TestCap, Dummy>(other_id(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun destroy_subou_control_retired() {
    let (sc, ou_id) = begin();
    let mut vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    vault.destroy_subou_control(other_id(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_capability_vault() {
    let (sc, _) = begin();
    let mut vault = retired_vault(&sc);
    vault.enforce_version();
    abort
}

// === treasury_vault ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun deposit_retired() {
    let (mut sc, _) = begin();
    let coin = coin::mint_for_testing<SUI>(1, sc.ctx());
    let mut treasury = retired_treasury(&sc);
    treasury.deposit(coin, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun withdraw_retired() {
    let (mut sc, ou_id) = begin();
    let mut treasury = retired_treasury(&sc);
    let req = request<Dummy>(ou_id);
    let _coin = treasury.withdraw<SUI, Dummy>(1, &req, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun claim_coin_retired() {
    let (mut sc, _) = begin();
    let treasury = sc.take_shared<TreasuryVault>();
    let treasury_id = object::id(&treasury);
    ts::return_shared(treasury);
    transfer::public_transfer(coin::mint_for_testing<SUI>(1, sc.ctx()), treasury_id.to_address());
    sc.next_tx(CREATOR);
    let mut treasury = retired_treasury(&sc);
    let receiving = ts::most_recent_receiving_ticket<Coin<SUI>>(&treasury_id);
    treasury.claim_coin(receiving, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_treasury_vault() {
    let (sc, _) = begin();
    let mut treasury = retired_treasury(&sc);
    treasury.enforce_version();
    abort
}

// === charter ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun update_metadata_retired() {
    let (sc, ou_id) = begin();
    let mut charter = retired_charter(&sc);
    let req = request<Dummy>(ou_id);
    charter.update_metadata(s(b"ipfs://new"), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_charter() {
    let (sc, _) = begin();
    let mut charter = retired_charter(&sc);
    charter.enforce_version();
    abort
}

// === emergency ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun freeze_type_retired() {
    let (mut sc, _) = begin();
    let clock = clock::create_for_testing(sc.ctx());
    let cap = sc.take_from_sender<FreezeAdminCap>();
    let mut freeze = retired_freeze(&sc);
    freeze.freeze_type<Dummy>(&cap, &clock);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun unfreeze_type_retired() {
    let (sc, _) = begin();
    let cap = sc.take_from_sender<FreezeAdminCap>();
    let mut freeze = retired_freeze(&sc);
    freeze.unfreeze_type<Dummy>(&cap);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun governance_unfreeze_type_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    let req = request<Dummy>(ou_id);
    freeze.governance_unfreeze_type(type_name::with_defining_ids<Dummy>(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun update_freeze_duration_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    let req = request<Dummy>(ou_id);
    freeze.update_freeze_duration(1, &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun unfreeze_all_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    let req = request<Dummy>(ou_id);
    freeze.unfreeze_all(&req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun add_freeze_exempt_type_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    let req = request<Dummy>(ou_id);
    freeze.add_freeze_exempt_type(type_name::with_defining_ids<Dummy>(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun remove_freeze_exempt_type_retired() {
    let (sc, ou_id) = begin();
    let mut freeze = retired_freeze(&sc);
    let req = request<Dummy>(ou_id);
    freeze.remove_freeze_exempt_type(type_name::with_defining_ids<Dummy>(), &req);
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_emergency() {
    let (sc, _) = begin();
    let mut freeze = retired_freeze(&sc);
    freeze.enforce_version();
    abort
}

// === encrypted_entry ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun publish_entry_retired() {
    let (mut sc, _) = begin();
    let mut ou = retired_ou(&sc);
    encrypted_entry::publish_entry(&mut ou, s(b"loc"), s(b"desc"), sc.ctx());
    abort
}

/// The entry's floor is raised; the OU (checked first) is live.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun update_entry_retired() {
    let (mut sc, _) = begin();
    publish_entry_for_test(&mut sc);
    let ou = sc.take_shared<OU>();
    let mut entry = retired_entry(&sc);
    encrypted_entry::update_entry(&ou, &mut entry, s(b"loc2"), sc.ctx());
    abort
}

/// The entry's floor is raised; the OU (checked first) is live.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun edit_entry_retired() {
    let (mut sc, _) = begin();
    publish_entry_for_test(&mut sc);
    let ou = sc.take_shared<OU>();
    let mut entry = retired_entry(&sc);
    encrypted_entry::edit_entry(&ou, &mut entry, s(b"loc2"), sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun rotate_encryption_epoch_retired() {
    let (mut sc, _) = begin();
    let mut ou = retired_ou(&sc);
    encrypted_entry::rotate_encryption_epoch(&mut ou, sc.ctx());
    abort
}

/// The entry's floor is raised; the OU (checked first) is live.
#[test, expected_failure(abort_code = version::EVersionRetired)]
fun remove_entry_retired() {
    let (mut sc, _) = begin();
    publish_entry_for_test(&mut sc);
    let mut ou = sc.take_shared<OU>();
    let entry = retired_entry(&sc);
    encrypted_entry::remove_entry(&mut ou, entry, sc.ctx());
    abort
}

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun enforce_version_retired_encrypted_entry() {
    let (mut sc, _) = begin();
    publish_entry_for_test(&mut sc);
    let mut entry = retired_entry(&sc);
    entry.enforce_version();
    abort
}

// === tribe ===

#[test, expected_failure(abort_code = version::EVersionRetired)]
fun create_wired_subou_retired() {
    let (mut sc, ou_id) = begin();
    let mut vault = retired_vault(&sc);
    let req = request<Dummy>(ou_id);
    tribe::create_wired_subou(
        vector[CREATOR],
        s(b"Sub"),
        s(b"u"),
        CREATOR,
        &mut vault,
        &req,
        vector[],
        sc.ctx(),
    );
    abort
}
