# OU Creation & Lifecycle Tests

## Summary

`ou.move` creates an OU with its four companion objects (`TreasuryVault`, `CapabilityVault`, `Charter`, `EmergencyFreeze`), seeds its type-keyed proposal registry, moves it `Active → Migrating` (`ou::set_migrating`, reached through a `SpawnOU` proposal) and destroys it once it is Migrating and empty. These tests verify construction and its aborts, the registry's shape, the migration restrictions, and the preconditions that keep `ou::destroy` from losing assets.

## Test Matrix

**Creation**

| Test | Expected | Where |
|------|----------|-------|
| `test_create_ou` | OU and its four companions are shared; both initial members are on the board; status `Active`; the charter carries the name; the creator owns the `FreezeAdminCap` | `ou_tests` |
| `test_ou_created_event` | The four companion IDs stored on the OU differ from the OU's own ID, and the treasury's from the vault's (the test does not read the `OUCreated` event) | `ou_tests` |
| `test_create__emits_creation_events` | The creating transaction emits one `OUCreated`, one `OUBoardInitialized` and 14 `TypeSlotAdded` | planned |
| `test_default_proposal_types` | 14 default slots under their display keys; default config; floor-gated and `TYPE_ADMIN` types at 80%; framework types carry their fixed bits; nothing executed yet | `ou_tests` |
| `test_subou_default_types_omit_bypass_meta` | A `ou::create_subou` OU has no `EnableBypassType` / `DisableBypassType` slot or display key (12 default slots in all) | `ou_tests` |
| `test_create_returning_vault_ids_are_consistent`, `test_create_returning_vault_vault_starts_empty`, `test_create_returning_vault_other_companions_are_shared` | The package-internal constructor returns the vault unshared and empty, shares the rest and transfers the cap to the creator | `ou_tests` |
| `create_tribe_freeze_caps_routed_correctly` | Tribe constructor: the tribe's cap to the sender, the Officers and Members caps to the named admins | `tribe_tests` |
| `test_create_empty_name_aborts` | Empty name: `ou::EInvalidName` | planned |
| `create_tribe_aborts_on_empty_tribe_board`, `create_tribe_aborts_on_empty_officer_board`, `create_tribe_aborts_on_empty_member_board` | Empty initial board: `governance::EEmptyBoard` | `tribe_tests` |
| `test_create_duplicate_initial_member_aborts` | Duplicate initial member: `governance::EDuplicateBoardMember` | planned |
| `create_tribe_configured_default_type_display_key_mismatch_aborts` | Override of a seeded type under another display key: `ou::EDisplayKeyMismatch` | `tribe_tests` |
| `create_wired_subou_aborts_on_blocked_type`, `create_tribe_configured_subou_still_rejects_blocked_type` | SubOU override enabling a SubOU-blocked type: `ou::EBlockedProposalType` | `tribe_tests` |
| `create_wired_subou_aborts_on_enable_proposal_type_below_floor` | Creation-time overrides must meet the floors: `ou::EThresholdBelowMinimum` | `tribe_tests` |

**Type registry**

| Test | Expected | Where |
|------|----------|-------|
| `test_enable_then_disable_leaves_nothing_behind` | Slot and display-key index both removed; the key is free for another type | `ou_tests` |
| `test_duplicate_display_key_aborts` | Two types under one display key: `ou::EDisplayKeyTaken` | `ou_tests` |
| `test_enable_twice_aborts` | One type under a second key: `ou::ETypeAlreadyEnabled` | `ou_tests` |
| `test_config_of_unregistered_type_aborts` | Reading a type with no slot: `ou::ETypeNotEnabled` | `ou_tests` |
| `test_root_size_independent_of_enabled_types` | 20 extra slots leave the root's BCS size unchanged (under 1 KiB) | `ou_tests` |
| `submit_proposal_aborts_for_type_without_slot` | A payload type with no slot cannot be submitted: `board_voting::ETypeNotEnabled` | `board_voting_tests` |

**Status and migration**

| Test | Expected | Where |
|------|----------|-------|
| `test_create_ou` | Status starts `Active` | `ou_tests` |
| `spawn_ou_and_destroy_origin_e2e` | `SpawnOU` executes: successor created and `Active`, origin `Migrating`; origin then destroyed | `armature_proposals::migration_tests` |
| `set_migrating_needs_migrate` | `set_migrating` with every bit except `MIGRATE`: `proposal::EPermissionDenied` | `gate_tests` |
| no path back to `Active` | Nothing sets the status to `Active` again | structural |
| `test_migrating_blocks_non_transfer_proposals_aborts` | `submit_proposal` of any type but `TransferAssets` on a Migrating OU: `board_voting::EOUNotActive` | planned |
| `test_migrating_blocks_pending_execution_aborts` | A `SetBoard` proposal passed before migration: `ticket_from_vote` aborts `board_voting::EOUNotActive` | planned |
| `test_migrating_blocks_bypass_aborts` | `ticket_from_cap` on a Migrating OU: `external_execution::EOUNotActive` | planned |
| `privileged_submit_rejects_inactive_subou` | Controller override on a Migrating SubOU: `controller::EOUNotActive` | `controller_tests` |
| `migration_with_transfer_assets_e2e` | `TransferAssets` is submitted, voted and executed while Migrating; the coins land in the successor's treasury | `armature_proposals::migration_tests` |

**Destruction**

| Test | Expected | Where |
|------|----------|-------|
| `test_destroy_requires_migrating_aborts` | `ou::destroy` on an Active OU: `ou::ENotMigrating` | planned |
| `test_destroy_wrong_companion_aborts` | Another OU's treasury passed: `ou::ETreasuryIdMismatch` (`EVaultIdMismatch`, `ECharterIdMismatch`, `EFreezeIdMismatch` for the others) | planned |
| `test_destroy_with_entries_aborts` | Encrypted entries still indexed: `ou::EEntriesNotEmpty` | `encrypted_entry_tests` |
| `test_destroy_requires_empty_treasury_aborts` | A coin left in the treasury: `treasury_vault::EVaultNotEmpty` | planned (unit level: `treasury_vault_tests::test_destroy_empty_aborts_on_non_empty_vault`) |
| `test_destroy_requires_empty_cap_vault_aborts` | A cap left in the vault: bare `expected_failure` (`capability_vault::destroy_empty` asserts without a code) | planned |
| `test_destroy_with_frozen_entry_aborts` | An entry left in `frozen_types`, even an expired one: bare `expected_failure` (`emergency::destroy`) | planned |
| `spawn_ou_and_destroy_origin_e2e`, `migration_with_transfer_assets_e2e` | Destroy succeeds once Migrating, companions match and everything is empty; no sender check | `armature_proposals::migration_tests` |
| `test_destroy_emits_ou_destroyed` | `OUDestroyed { ou_id, successor_ou_id }` | planned |
| `test_inflight_proposal_deletable_after_destroy` | A proposal of the destroyed OU cannot be executed and is deleted with `delete_expired_proposal` once its deadline passes | planned |

## Tests

---

### Creation shares the OU and its companions

**Requirement:** `ou::create(&GovernanceTypeInit, name, metadata_uri, ctx): ID` builds the OU and a `TreasuryVault`, `CapabilityVault`, `Charter` and `EmergencyFreeze` that point back at it, shares all five and transfers the `FreezeAdminCap` to the sender. The board comes from `governance::init_board(members)`; initial members join at roster version 0.

**Why it matters:** Every later operation takes these objects by ID. A missing or mis-linked companion would make the OU unusable, and a cap sent anywhere but the creator would hand the emergency brake to someone else.

```move
#[test]
fun test_create_ou() {
    let mut scenario = test_scenario::begin(CREATOR);
    scenario.next_tx(CREATOR);
    {
        let init = governance::init_board(vector[CREATOR, MEMBER_B]);
        ou::create(&init, string::utf8(b"Test OU"), string::utf8(b"https://example.com/metadata.json"), scenario.ctx());
    };

    scenario.next_tx(CREATOR);
    {
        let ou = scenario.take_shared<OU>();
        assert!(ou.governance().is_board_member(CREATOR));
        assert!(ou.governance().is_board_member(MEMBER_B));
        assert!(ou.status().is_active());
        test_scenario::return_shared(ou);

        let charter = scenario.take_shared<Charter>();
        assert!(charter.name() == &string::utf8(b"Test OU"));
        test_scenario::return_shared(charter);

        let cap = scenario.take_from_sender<FreezeAdminCap>();   // wallet-owned by the creator
        test_scenario::return_to_sender(&scenario, cap);
    };
    scenario.end();
}
```

(Condensed from `ou_tests::test_create_ou`, which also takes each companion as a shared object.)

---

### Creation seeds the default type slots

**Requirement:** Every OU starts with 14 slots, keyed by the payload's Move type and labelled with a display key: `SetBoard`, `AddMember`, `RemoveMember`, `BatchAddMembers`, `BatchRemoveMembers`, `UpdateMetadata` ("CharterUpdate"), `EnableProposalType`, `EnableBypassType`, `DisableBypassType`, `DisableProposalType`, `UpdateProposalConfig`, `TransferFreezeAdmin`, `UnfreezeProposalType`, `CompositePayload` ("Composite"). SubOU constructors omit the two bypass meta-types (12 slots). Default config: quorum 50%, threshold 50% raised to the type's floor and its bits' floor, `propose_threshold` 0, expiry 7 days, no delay, no cooldown. `AddMember`, `RemoveMember`, `SetBoard`, `UpdateMetadata` and `EnableProposalType` are composable. Each framework type holds its fixed permission bits (`ou::framework_permissions`). Everything else is opt-in.

**Why it matters:** A new OU must be able to govern itself (change its board, enable more types, react to a freeze) without any setup ceremony, and the defaults must never sit below a floor.

```move
// From ou_tests::test_default_proposal_types
let ou = scenario.take_shared<OU>();
assert!(ou.type_display_key<UpdateMetadata>() == b"CharterUpdate".to_ascii_string());
assert!(ou.type_display_key<CompositePayload>() == b"Composite".to_ascii_string());
assert!(ou.type_for_display_key(&b"NotAType".to_ascii_string()).is_none());

let config = ou.type_config<SetBoard>();
assert!(config.quorum() == 5_000 && config.approval_threshold() == 5_000);
assert!(config.expiry_ms() == 604_800_000);
assert!(config.composable_allowed());

assert!(ou.type_config<EnableProposalType>().approval_threshold() == 8_000);   // type floor
assert!(ou.type_config<DisableProposalType>().approval_threshold() == 8_000);  // TYPE_ADMIN floor
assert!(ou.type_config<SetBoard>().permissions() == permissions::board_set());
assert!(ou.type_config<CompositePayload>().permissions() == 0);
assert!(!ou.type_config<BatchAddMembers>().composable_allowed());
assert!(ou.last_executed_ms<SetBoard>().is_none());
```

---

### Creation emits the discovery events (planned)

**Requirement:** Creation emits `OUCreated { ou_id, treasury_id, capability_vault_id, charter_id, emergency_freeze_id, creator }`, then `OUBoardInitialized { ou_id, initial_members }`, then one `TypeSlotAdded { ou_id, type_name, display_key, config }` per seeded slot.

**Why it matters:** Indexers find new OUs, their boards and their registries from these events. `ou_tests::test_ou_created_event` checks only the IDs stored on the OU.

```move
#[test]
fun test_create__emits_creation_events() {
    let mut scenario = test_scenario::begin(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    ou::create(&init, string::utf8(b"OU"), string::utf8(b""), scenario.ctx());
    assert!(event::events_by_type<ou::OUCreated>().length() == 1);
    assert!(event::events_by_type<ou::OUBoardInitialized>().length() == 1);
    assert!(event::events_by_type<ou::TypeSlotAdded>().length() == 14);
    scenario.end();
}
```

---

### Creation aborts

**Requirement:** `build` checks the name first (`ou::EInvalidName` if empty), then the board (`governance::EEmptyBoard` if empty, `governance::EDuplicateBoardMember` on a repeated address). Construction-time overrides (`ProposalTypeInit` from `ou::new_type_init<T>`, taken by `create_subou_configured`, `tribe::create_tribe_configured` and `tribe::create_wired_subou`) must keep a seeded type's display key (`ou::EDisplayKeyMismatch`), may not enable a SubOU-blocked type on a SubOU (`ou::EBlockedProposalType`), and must meet the floors (`ou::EThresholdBelowMinimum`).

**Why it matters:** A nameless OU, an empty board or a sub-floor config at birth would bypass checks every later change is held to.

```move
#[test, expected_failure(abort_code = ou::EInvalidName)]
fun test_create_empty_name_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let init = governance::init_board(vector[CREATOR]);
    ou::create(&init, string::utf8(b""), string::utf8(b""), scenario.ctx());
    abort 0
}
```

The board and override aborts are covered through the tribe constructors (`tribe_tests::create_tribe_aborts_on_empty_tribe_board`, `create_tribe_configured_default_type_display_key_mismatch_aborts`, `create_wired_subou_aborts_on_blocked_type`, `create_wired_subou_aborts_on_enable_proposal_type_below_floor`). `test_create_duplicate_initial_member_aborts` is planned.

---

### Type slots are keyed by the payload's Move type

**Requirement:** Each enabled type is one dynamic field on the OU, `TypeSlot { name: TypeName }` → `ProposalType { display_key, config, last_executed_ms }`, where `name` is `type_name::with_defining_ids<P>()`. A second field, `DisplayKey { key }` → `TypeName`, indexes the display key. Display keys are unique per OU and non-empty and carry no authority. Disabling removes both fields and the cooldown state.

**Why it matters:** Submission and execution consult only the Move type, so a payload can never run under another type's config, and the root object stays a few hundred bytes however many types are enabled (Sui charges storage and computation on the whole root on every write).

```move
// From ou_tests::test_enable_then_disable_leaves_nothing_behind
let mut ou = scenario.take_shared<OU>();
let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 0, 0);
ou.test_enable_type<CustomA>(b"Custom".to_ascii_string(), config);
assert!(ou.type_for_display_key(&b"Custom".to_ascii_string()).is_some());

ou.test_disable_type<CustomA>();
assert!(!ou.is_type_enabled<CustomA>());
assert!(ou.type_for_display_key(&b"Custom".to_ascii_string()).is_none());

ou.test_enable_type<CustomB>(b"Custom".to_ascii_string(), config);   // key is free again
```

`ou_tests::test_duplicate_display_key_aborts` (`ou::EDisplayKeyTaken`), `test_enable_twice_aborts` (`ou::ETypeAlreadyEnabled`) and `test_root_size_independent_of_enabled_types` cover the rest.

---

### Active to Migrating

**Requirement:** `ou::set_migrating(successor_ou_id, &req)` requires `MIGRATE` and sets `Migrating { successor_ou_id }`. `SpawnOU` holds `MIGRATE` as a fixed bit: `lifecycle_ops::execute_spawn_ou` creates the successor with `ou::create` (its `FreezeAdminCap` goes to the executing transaction's sender), sets the origin Migrating and emits `SuccessorOUSpawned`. Nothing sets the status back to `Active`. `set_migrating` does not check the current status; the entry points in the next section keep a Migrating OU from starting any execution but `TransferAssets` (fixed bits `TREASURY_WITHDRAW` + `VAULT_EXTRACT`).

**Why it matters:** Migration is how an OU hands its assets to a successor. If it could be reversed, a board could cancel it after assets had partly moved.

```move
// As in encrypted_entry_tests::test_destroy_with_entries_aborts
scenario.next_tx(CREATOR);
{
    let mut ou = scenario.take_shared<OU>();
    let successor = object::id_from_address(@0xBEEF);
    // Every bit, MIGRATE included; in production the request comes from a SpawnOU ticket.
    let req = proposal::new_execution_request_for_testing<Probe>(ou.id(), object::id_from_address(@0x1));
    ou.set_migrating(successor, &req);
    proposal::consume(req);
    assert!(ou.status().is_migrating());
    assert!(ou.status().successor_ou_id() == successor);
    test_scenario::return_shared(ou);
};
```

The end-to-end path is `armature_proposals::migration_tests::spawn_ou_and_destroy_origin_e2e`; `gate_tests::set_migrating_needs_migrate` covers the bit.

---

### While Migrating, only TransferAssets executes

**Requirement:** `board_voting::submit_proposal`, `submit_vote_execute(_readonly)` and `ticket_from_vote(_readonly)` accept a Migrating OU only for `TransferAssets` (`ou::is_migration_allowed_type`) and otherwise abort `board_voting::EOUNotActive`. `external_execution::ticket_from_cap(_readonly)` (`external_execution::EOUNotActive`), `composite::submit_composite` (`composite::EOUNotActive`) and `controller::privileged_submit` (`controller::EOUNotActive`) require `Active`. Voting is not status-gated. `TransferAssets` also runs on an Active OU.

**Why it matters:** Once a successor exists, the old OU must not spend, reconfigure or change its board; it may only move its assets out.

```move
#[test, expected_failure(abort_code = board_voting::EOUNotActive)]
fun test_migrating_blocks_non_transfer_proposals_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let clock = clock::create_for_testing(scenario.ctx());
    create_ou(&mut scenario);
    migrate(&mut scenario);   // set_migrating as above

    scenario.next_tx(CREATOR);
    let ou = scenario.take_shared<OU>();
    board_voting::submit_proposal(
        &ou,
        option::none(),
        set_board::new(vector[MEMBER_C], vector[]),
        &clock,
        scenario.ctx(),
    );
    abort 0
}
```

---

### TransferAssets moves assets to the successor

**Requirement:** A `TransferAssets` ticket is spent through a hot potato: `lifecycle_ops::begin_transfer_assets(&src_treasury, &src_vault, ticket)` → `transfer_coin<T>(&mut xfer, &mut src, &mut target, ctx)` per listed coin type (moves the full balance) → `transfer_cap<T>(&mut xfer, &mut src_vault, &mut target_vault, cap_id)` per listed cap → `finish_transfer_assets(xfer)`, which aborts `lifecycle_ops::EAssetsRemaining` until every listed asset has moved. Targets come from the payload; the executor never holds the assets. At most 50 assets per payload (`lifecycle_ops::EAssetLimitExceeded`).

**Why it matters:** The origin must end up empty before it can be destroyed, and every asset must reach the successor the board named.

```move
// From armature_proposals::migration_tests::migration_with_transfer_assets_e2e (origin is Migrating)
let ticket = board_voting::ticket_from_vote(&mut origin_ou, proposal, &origin_freeze, &clock, scenario.ctx());
let mut transfer = lifecycle_ops::begin_transfer_assets(&origin_treasury, &origin_vault, ticket);
transfer.transfer_coin<SUI>(&mut origin_treasury, &mut successor_treasury, scenario.ctx());
transfer.finish_transfer_assets();
assert!(origin_treasury.balance<SUI>() == 0);
assert!(successor_treasury.balance<SUI>() == 500_000);
```

`lifecycle_ops_tests` covers the listed-asset checks (`EAssetNotListed`, `ETargetTreasuryMismatch`, `EAssetsRemaining`).

---

### Destroy preconditions

**Requirement:** `ou::destroy(ou, treasury, vault, charter, freeze)` has no sender check. It aborts, in order: `ou::ENotMigrating` unless Migrating; `ou::ETreasuryIdMismatch` / `EVaultIdMismatch` / `ECharterIdMismatch` / `EFreezeIdMismatch` unless each companion is the OU's own; `ou::EEntriesNotEmpty` while encrypted entries are indexed; `treasury_vault::EVaultNotEmpty` while any coin balance remains; and, without a named code, while the capability vault holds a cap (`capability_vault::destroy_empty`) or `frozen_types` has an entry (`emergency::destroy`). Freeze entries are not removed when they expire, and none of the `FREEZE` types can execute on a Migrating OU, so only the `FreezeAdminCap` can clear a leftover entry (`emergency::unfreeze_type<P>`). On success all five objects are deleted and `OUDestroyed { ou_id, successor_ou_id }` is emitted. Type slots stay attached to the deleted UID, and the roster `Table` is dropped without reclaiming its entries' deposits (neither can be enumerated).

**Why it matters:** Destroying an OU that still holds coins or capabilities would burn them; destroying an Active OU would strand its governance.

```move
#[test, expected_failure(abort_code = ou::ENotMigrating)]
fun test_destroy_requires_migrating_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    create_ou(&mut scenario);
    scenario.next_tx(CREATOR);
    let ou = scenario.take_shared<OU>();
    let treasury = scenario.take_shared_by_id<TreasuryVault>(ou.treasury_id());
    let vault = scenario.take_shared_by_id<CapabilityVault>(ou.capability_vault_id());
    let charter = scenario.take_shared_by_id<Charter>(ou.charter_id());
    let freeze = scenario.take_shared_by_id<EmergencyFreeze>(ou.emergency_freeze_id());
    ou::destroy(ou, treasury, vault, charter, freeze);
    abort 0
}
```

The other planned aborts follow the same shape after a `set_migrating`: deposit a coin (`treasury_vault::EVaultNotEmpty`), store a cap with `store_cap_for_testing` (bare `expected_failure`), or freeze a type with the creator's cap and let it expire (bare `expected_failure`). The successful path is `armature_proposals::migration_tests::spawn_ou_and_destroy_origin_e2e`; `encrypted_entry_tests::test_destroy_with_entries_aborts` covers `EEntriesNotEmpty`.

---

### In-flight proposals after destruction (planned)

**Requirement:** A `Proposal<P>` is its own shared object; destroying the OU does not delete it. It can no longer be executed, since every execution path takes the OU. `proposal::delete_expired_proposal` takes no OU, so anyone can still delete it once its voting deadline (Active) or execution window (Passed) has passed.

**Why it matters:** No decision of the old board can take effect after destruction, and the leftover objects can still be cleaned up.

```move
// After ou::destroy: the SetBoard proposal passed at `passed_at` is still shared.
scenario.next_tx(MEMBER_B);
{
    let prop = scenario.take_shared<Proposal<SetBoard>>();
    clock.set_for_testing(passed_at + 604_800_000);   // default: no delay, 7-day window
    proposal::delete_expired_proposal(prop, &clock);
};
scenario.next_tx(MEMBER_B);
assert!(!test_scenario::has_most_recent_shared<Proposal<SetBoard>>());
```
