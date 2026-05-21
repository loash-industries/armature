/// AutojoinDAO — permissionless self-join for DAOs whose Members SubDAO
/// has opted into bypass execution for this type and configured an
/// allowlist of in-game tribe IDs synonymous with it.
///
/// Flow (single PTB, no vote):
///   1. DAO has previously passed `EnableBypassType { type_key: "AutojoinDAO", .. }`
///      with `NewType = AutojoinDAO`, depositing an `ExternalExecutionCap<AutojoinDAO>`
///      in the DAO's CapabilityVault.
///   2. DAO has previously passed `EnableProposalType { type_key: "ConfigureAutojoin", .. }`
///      with `NewType = ConfigureAutojoin`, then `ConfigureAutojoin { add_tribe_ids: [N],
/// set_enabled: some(true), .. }`
///      to populate the allowlist.
///   3. Player calls `submit_autojoin(dao, vault, cap_id, character, freeze, clock, ctx)`.
///      The function verifies the character's wallet matches `ctx.sender()`,
///      the character's tribe is in the allowlist, the kill-switch is on,
///      then hands off to `external_execution::external_executed_create<AutojoinDAO>`
///      which mints the request after running all the standard cross-cutting
///      checks (DAO active, type enabled, not frozen/paused, type binding,
///      cooldown, record_execution).
///   4. Same PTB, player calls `execute_autojoin_dao(dao, &proposal, request)`
///      which re-reads the allowlist (defense-in-depth across PTB steps that
///      a future refactor might split) and adds the joiner to the board.
///
/// Threat model:
///   - World admin is the trust anchor for `character.tribe_id` and
///     `character.character_address`. Both are written only by
///     `world::character::create_character` / `update_tribe` / `update_address`,
///     all of which call `admin_acl.verify_sponsor(ctx)`.
///   - `Character` is shared; the `&Character` reference cannot be fabricated.
///   - `&CapabilityVault` is shared and read-only here; `borrow_external_cap`
///     asserts `vault.dao_id == dao.id()` so a wrong vault aborts at the source.
///   - `external_executed_create` re-asserts `cap.dao_id == dao.id()` and runs
///     the full cross-cutting check set. Two independent dao-id boundaries.
///   - Allowlist re-read at execute time means a hypothetical PTB split
///     (submit in tx A, execute in tx B) would still be safe: if the DAO
///     reconfigures or disables between submit and execute, execute aborts.
module armature_world_bridge::autojoin_ops;

use armature::capability_vault::CapabilityVault;
use armature::dao::DAO;
use armature::emergency::EmergencyFreeze;
use armature::external_execution;
use armature::proposal::{Self, ExecutionRequest, Proposal};
use armature_world_bridge::configure_autojoin::ConfigureAutojoin;
use armature_world_bridge::tribe_allowlist::TribeIdAllowlist;
use sui::clock::Clock;
use sui::event;
use world::character::Character;

// === Errors ===

const EDaoMismatch: u64 = 0;
const ESenderNotCharacterOwner: u64 = 1;
const EAllowlistNotInitialized: u64 = 2;
const EAutojoinDisabled: u64 = 3;
const ETribeIdNotAllowed: u64 = 4;
const EZeroTribeIdNotAllowed: u64 = 5;

// === Structs ===

/// Per-self-join payload. Recorded for the audit trail; the execute
/// handler re-reads `dao` and `character` state at execution time
/// rather than trusting payload values, so the payload is informational.
public struct AutojoinDAO has store {
    character_id: ID,
    tribe_id: u32,
    joining_address: address,
}

// === Events ===

public struct MemberAutojoined has copy, drop {
    dao_id: ID,
    member: address,
    tribe_id: u32,
    character_id: ID,
}

// === Accessors ===

public fun character_id(self: &AutojoinDAO): ID { self.character_id }

public fun tribe_id(self: &AutojoinDAO): u32 { self.tribe_id }

public fun joining_address(self: &AutojoinDAO): address { self.joining_address }

// === Submit ===

/// Submit and pre-mint the AutojoinDAO execution request. The caller must
/// pass the `cap_id` of the DAO's `ExternalExecutionCap<AutojoinDAO>` (the
/// cap is in the CapabilityVault if the DAO has bypass-enabled this type).
///
/// Aborts on:
///   - `character.character_address() != ctx.sender()` — joiner wallet must
///     match the world-admin-asserted owner of the character.
///   - Allowlist type-state missing — `ConfigureAutojoin` has never run.
///   - Allowlist `enabled == false` — kill-switch.
///   - `character.tribe()` not in allowlist.
///   - Any check inside `external_executed_create` (DAO active, type enabled,
///     not paused/frozen, type binding mismatch, cooldown, etc).
///
/// The returned `ExecutionRequest<AutojoinDAO>` must be consumed in the
/// same PTB by `execute_autojoin_dao`.
public fun submit_autojoin(
    members_dao: &mut DAO,
    members_vault: &CapabilityVault,
    cap_id: ID,
    character: &Character,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionRequest<AutojoinDAO> {
    let sender = ctx.sender();

    // 1. Authenticate the joiner against the character record. The world
    //    admin sets `character_address`; matching `ctx.sender()` against it
    //    is the joiner-identity gate.
    assert!(character.character_address() == sender, ESenderNotCharacterOwner);

    // 2. Read the per-DAO allowlist. type-state is keyed by ConfigureAutojoin.
    assert!(members_dao.has_type_state<ConfigureAutojoin>(), EAllowlistNotInitialized);
    let allowlist: &TribeIdAllowlist = members_dao.borrow_type_state<
        ConfigureAutojoin,
        TribeIdAllowlist,
    >();
    assert!(allowlist.is_enabled(), EAutojoinDisabled);
    let tribe_id = character.tribe();
    // Reject tribe_id == 0 at the use site too. ConfigureAutojoin rejects 0
    // on adds, but defense-in-depth: if the world-contracts admin gate ever
    // changes and produces a 0-tribe Character, this catches it independently.
    assert!(tribe_id != 0, EZeroTribeIdNotAllowed);
    assert!(allowlist.contains(tribe_id), ETribeIdNotAllowed);

    // 3. Borrow the cap. borrow_external_cap asserts vault.dao_id == members_dao.id().
    let cap = members_vault.borrow_external_cap<AutojoinDAO>(members_dao.id(), cap_id);

    // 4. Hand off to the framework's cap-gated mint. external_executed_create
    //    re-asserts cap.dao_id == dao.id() (second independent boundary),
    //    checks DAO active / type enabled / not paused / not frozen / type
    //    binding match / cooldown, records execution, mints the request.
    external_execution::external_executed_create<AutojoinDAO>(
        cap,
        members_dao,
        freeze,
        b"AutojoinDAO".to_ascii_string(),
        option::none(),
        AutojoinDAO {
            character_id: object::id(character),
            tribe_id,
            joining_address: sender,
        },
        clock,
        ctx,
    )
}

// === Execute ===

/// Consume the AutojoinDAO request and add the joiner to the board.
///
/// Re-reads the allowlist as defense-in-depth: if a future refactor ever
/// allows the submit/execute steps to be in different PTBs, this read
/// would catch a DAO that revoked the tribe between steps. Today they
/// are always in the same PTB so this is belt-and-suspenders.
///
/// The payload `joining_address` is the address the cap-gated mint
/// captured from `ctx.sender()` in `submit_autojoin`. We add THAT
/// address rather than re-reading `character.character_address()`,
/// because the payload is the recorded intent and is what indexers
/// will see in the event.
public fun execute_autojoin_dao(
    dao: &mut DAO,
    proposal: &Proposal<AutojoinDAO>,
    request: ExecutionRequest<AutojoinDAO>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();

    // Defense-in-depth re-read. submit_autojoin already verified these,
    // but a same-PTB re-read is cheap and protects against
    // future-refactor regressions.
    assert!(dao.has_type_state<ConfigureAutojoin>(), EAllowlistNotInitialized);
    let allowlist: &TribeIdAllowlist = dao.borrow_type_state<ConfigureAutojoin, TribeIdAllowlist>();
    assert!(allowlist.is_enabled(), EAutojoinDisabled);
    assert!(allowlist.contains(payload.tribe_id), ETribeIdNotAllowed);

    // add_board_member_governance aborts on duplicate (governance::EDuplicateBoardMember),
    // giving us natural double-join protection without any extra check here.
    dao.add_board_member_governance(payload.joining_address, &request);

    event::emit(MemberAutojoined {
        dao_id: dao.id(),
        member: payload.joining_address,
        tribe_id: payload.tribe_id,
        character_id: payload.character_id,
    });

    proposal::finalize(request, proposal);
}
