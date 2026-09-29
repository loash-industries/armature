/// AutojoinOU — permissionless self-join for OUs whose Members SubOU
/// has opted into bypass execution for this type and configured an
/// allowlist of in-game tribe IDs synonymous with it.
///
/// Flow (single PTB, no vote):
///   1. OU has previously passed `EnableBypassType { type_key: "AutojoinOU", .. }`
///      with `NewType = AutojoinOU`, depositing an `ExternalExecutionCap<AutojoinOU>`
///      in the OU's CapabilityVault.
///   2. OU has previously passed `EnableProposalType { type_key: "ConfigureAutojoin", .. }`
///      with `NewType = ConfigureAutojoin`, then `ConfigureAutojoin { add_tribe_ids: [N],
/// set_enabled: some(true), .. }`
///      to populate the allowlist.
///   3. Player calls `autojoin(ou, vault, cap_id, character, freeze, clock, ctx)`.
///      The function verifies the character's wallet matches `ctx.sender()`,
///      the character's tribe is in the allowlist, the kill-switch is on,
///      then mints the ticket through `external_execution::ticket_from_cap<AutojoinOU>`
///      (which runs the standard cross-cutting checks: OU active, type slot
///      present, not frozen/paused, cooldown, record_execution), adds the
///      joiner, and discharges the ticket. The ticket never leaves this module.
///
/// Threat model:
///   - World admin is the trust anchor for `character.tribe_id` and
///     `character.character_address`. Both are written only by
///     `world::character::create_character` / `update_tribe` / `update_address`,
///     all of which call `admin_acl.verify_sponsor(ctx)`.
///   - `Character` is shared; the `&Character` reference cannot be fabricated.
///   - `&CapabilityVault` is shared and read-only here; `borrow_external_cap`
///     asserts `vault.ou_id == ou.id()` so a wrong vault aborts at the source.
///   - `ticket_from_cap` re-asserts `cap.ou_id == ou.id()` and runs
///     the full cross-cutting check set. Two independent ou-id boundaries.
///   - The ticket's request (BOARD_ADD) is spent only here, on `ctx.sender()`:
///     the caller never holds the ticket, and `Permit<AutojoinOU>` can only be
///     minted in this module, so nobody can add any other address with it.
module armature_world_bridge::autojoin_ops;

use armature::capability_vault::CapabilityVault;
use armature::ou::OU;
use armature::emergency::EmergencyFreeze;
use armature::external_execution;
use armature::permissions;
use armature_world_bridge::configure_autojoin::ConfigureAutojoin;
use armature_world_bridge::tribe_allowlist::TribeIdAllowlist;
use std::internal;
use sui::clock::Clock;
use sui::event;
use world::character::Character;

// === Errors ===

// 0 was EOuMismatch: the joiner is added inside `autojoin`, on the OU the ticket was minted for.
const ESenderNotCharacterOwner: u64 = 1;
const EAllowlistNotInitialized: u64 = 2;
const EAutojoinDisabled: u64 = 3;
const ETribeIdNotAllowed: u64 = 4;
const EZeroTribeIdNotAllowed: u64 = 5;

// === Structs ===

/// Per-self-join payload. Recorded for the audit trail; the execute
/// handler re-reads `ou` and `character` state at execution time
/// rather than trusting payload values, so the payload is informational.
public struct AutojoinOU has drop, store {
    character_id: ID,
    tribe_id: u32,
    joining_address: address,
}

// === Events ===

public struct MemberAutojoined has copy, drop {
    ou_id: ID,
    member: address,
    tribe_id: u32,
    character_id: ID,
}

// === Accessors ===

public fun character_id(self: &AutojoinOU): ID { self.character_id }

public fun tribe_id(self: &AutojoinOU): u32 { self.tribe_id }

public fun joining_address(self: &AutojoinOU): address { self.joining_address }

/// The permission bits AutojoinOU needs in the config its EnableBypassType
/// carries: BOARD_ADD only (`execute_autojoin_ou` adds the joining member).
/// ConfigureAutojoin needs none: it writes only its own type-state.
public fun autojoin_permissions(): u64 { permissions::board_add() }

// === Autojoin ===

/// Add `ctx.sender()` to the Members OU's board without a vote.
///
/// Aborts on:
///   - `character.character_address() != ctx.sender()` — joiner wallet must
///     match the world-admin-asserted owner of the character.
///   - Allowlist type-state missing — `ConfigureAutojoin` has never run.
///   - Allowlist `enabled == false` — kill-switch.
///   - `character.tribe()` not in allowlist.
///   - Any check inside `ticket_from_cap` (OU active, type slot present,
///     not paused/frozen, cooldown, etc).
public fun autojoin(
    members_ou: &mut OU,
    members_vault: &CapabilityVault,
    cap_id: ID,
    character: &Character,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();

    // 1. Authenticate the joiner against the character record. The world
    //    admin sets `character_address`; matching `ctx.sender()` against it
    //    is the joiner-identity gate.
    assert!(character.character_address() == sender, ESenderNotCharacterOwner);

    // 2. Read the per-OU allowlist. type-state is keyed by ConfigureAutojoin.
    assert!(members_ou.has_type_state<ConfigureAutojoin>(), EAllowlistNotInitialized);
    let allowlist: &TribeIdAllowlist = members_ou.borrow_type_state<
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

    // 3. Borrow the cap. borrow_external_cap asserts vault.ou_id == members_ou.id().
    let cap = members_vault.borrow_external_cap<AutojoinOU>(members_ou.id(), cap_id);

    // 4. Mint the ticket through the framework's cap-gated path.
    let payload = AutojoinOU {
        character_id: object::id(character),
        tribe_id,
        joining_address: sender,
    };
    let ticket = external_execution::ticket_from_cap<AutojoinOU>(
        cap,
        members_ou,
        freeze,
        option::none(),
        payload,
        internal::permit(),
        clock,
        ctx,
    );

    // 5. Spend the request on the joiner only, then close the ticket.
    members_ou.add_board_member_governance(sender, ticket.ticket_request(internal::permit()));

    event::emit(MemberAutojoined {
        ou_id: members_ou.id(),
        member: sender,
        tribe_id,
        character_id: object::id(character),
    });

    ticket.discharge(internal::permit());
}
