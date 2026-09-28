# Admin Proposal Tests (10 types)

## Summary

The admin types are framework types (`armature_framework/sources/types/`) with fixed permission bits (`dao::framework_permissions`). Their handlers live in three framework modules; only those modules can mint the `Permit` that spends or closes their tickets:

| Handler module | Types | Bits (fixed) | Floor |
|---|---|---|---|
| `armature::admin_ops` | `EnableProposalType`, `DisableProposalType`, `UpdateProposalConfig` | `TYPE_ADMIN` | 80% |
| `armature::admin_ops` | `UpdateMetadata` (display key "CharterUpdate") | `METADATA` | — |
| `armature::external_execution` | `EnableBypassType` / `DisableBypassType` | `TYPE_ADMIN` + `VAULT_STORE` / `TYPE_ADMIN` + `VAULT_EXTRACT` | 80% |
| `armature::freeze_ops` | `TransferFreezeAdmin`, `UnfreezeProposalType`, `UpdateFreezeConfig`, `UpdateFreezeExemptTypes` | `FREEZE` | — |

Every DAO is seeded with all of them except `UpdateFreezeConfig` and `UpdateFreezeExemptTypes` (opt-in); SubDAOs are not seeded with `EnableBypassType` / `DisableBypassType`. `EnableProposalType`, `DisableProposalType`, `EnableBypassType`, `DisableBypassType`, `TransferFreezeAdmin` and `UnfreezeProposalType` are undisableable (`dao::is_undisableable_type`).

The type registry is one dynamic-field slot per enabled type, keyed by the payload's canonical `TypeName` (`type_name::with_defining_ids`). Display keys are unique per DAO, carry no authority, and are used only on cold admin paths: `UpdateProposalConfig.target_type_key`, `DisableProposalType.type_key` and `DisableBypassType.type_key` name their target by display key. `EnableProposalType` and `EnableBypassType` pin the target's `TypeName` in the payload, and the executor's `NewType` must match it.

This file covers handler behaviour. The permission model these handlers go through (type and permission floors, fixed bits, grant rules, borrow scope, per-mutator gates) is tested in `permissions_tests.move`, `borrow_scope_tests.move` and `gate_tests.move`; see `03_governance.md` and `17_coverage_summary.md`. Charter behaviour of `UpdateMetadata` is in `14_charter_ops.md`; freeze mechanics are in `08_emergency.md`.

Real suites: `packages/armature_proposals/tests/admin_ops_tests.move` (21), `packages/armature_framework/tests/external_execution_tests.move` (22), `freeze_ops_tests.move` (5), plus tests cited from `permissions_tests.move`, `emergency_tests.move`, `emergency_freeze_tests.move`, `charter_tests.move` and `external_type_lifecycle_tests.move`.

## Test Matrix

| Type | Test | Expected |
|------|------|----------|
| UpdateProposalConfig | `update_proposal_config_non_self_target_succeeds` | Target "SetBoard" gets `quorum = 3000`; other fields keep their values |
| UpdateProposalConfig | `update_proposal_config_composable_allowed_updates_config` | `composable_allowed` on AddMember goes false, then true again |
| UpdateProposalConfig | `update_proposal_config_preserves_permissions` | Payload without `permissions` keeps the target's bits (threshold changed to 6000) |
| UpdateProposalConfig | `permissions_tests::update_proposal_config_grants_and_revokes_high_bits` | `with_permissions` grants an 80% bit, a later update revokes it |
| UpdateProposalConfig | `borrow_scope_tests::meta_type_may_change_scope` | `with_borrow_scope` changes the scope; the next request carries it |
| UpdateProposalConfig | `update_config_below_floor_aborts` | EnableProposalType threshold → 5000: Abort `dao::EThresholdBelowMinimum` |
| UpdateProposalConfig | `update_proposal_config_composable_cooldown_conflict_aborts` | `cooldown_ms > 0` with `composable_allowed`: Abort `admin_ops::EComposableCooldownConflict` |
| UpdateProposalConfig | `permissions_tests::update_proposal_config_self_grant_aborts` | Changing a framework type's bits: Abort `dao::EFixedPermissions` |
| UpdateProposalConfig | `update_proposal_config_self_submission_floor_rejects_below_80_percent` | Self-targeting `propose_update_proposal_config` with own threshold < 8000: Abort `admin_ops::EFloorNotMet` |
| UpdateProposalConfig | `update_proposal_config_self_submission_floor_allows_80_percent` | Same at 8000: proposal created |
| UpdateProposalConfig | `test_update_config__unknown_target_key_aborts` (planned) | `target_type_key` names no enabled type: Abort `admin_ops::ETypeNotEnabled` |
| UpdateProposalConfig | `test_update_config__invalid_config_aborts` (planned) | e.g. `quorum = some(0)`: the merged config is rebuilt with `proposal::new_config`, Abort `proposal::EInvalidQuorum` |
| UpdateProposalConfig | `test_update_config__does_not_affect_other_types` (planned) | Only the target slot changes; `TypeSlotConfigUpdated` and `ProposalConfigUpdated` emitted |
| EnableProposalType | `execute_enable_proposal_type_adds_slot` | Slot keyed by `NewType` under the voted display key ("MyGrant") |
| EnableProposalType | `execute_enable_proposal_type_reenable_same_type_succeeds` | Re-enable after a disable, same key |
| EnableProposalType | `execute_enable_proposal_type_display_key_reusable_after_disable` | A key freed by a disable can name another type |
| EnableProposalType | `execute_enable_proposal_type_wrong_new_type_aborts` | Executor's `NewType` ≠ payload `type_name`: Abort `admin_ops::ETypeMismatch` |
| EnableProposalType | `execute_enable_proposal_type_duplicate_display_key_aborts` | Key in use: Abort `dao::EDisplayKeyTaken` |
| EnableProposalType | `enable_proposal_type_submission_floor_rejects_below_80_percent` | EnableProposalType slot < 8000: Abort `board_voting::EFloorNotMet` at submission |
| EnableProposalType | `enable_proposal_type_submission_floor_allows_80_percent` | Slot at 8000: submitted |
| EnableProposalType | `enable_type_with_sub_floor_config_aborts` | Re-enable UpdateProposalConfig below 8000: Abort `dao::EThresholdBelowMinimum` |
| EnableProposalType | `enable_proposal_type_composable_cooldown_conflict_aborts` | Abort `admin_ops::EComposableCooldownConflict` |
| EnableProposalType | `enable_blocked_type_aborts_for_subdao_with_controller` | SpawnDAO on a controlled SubDAO: Abort `admin_ops::ESubDAOBlockedType` at execution |
| EnableProposalType | `enable_non_blocked_type_succeeds_for_subdao_with_controller` | Third-party type on a controlled SubDAO: enabled |
| EnableProposalType | `enable_blocked_type_succeeds_for_independent_dao` | SpawnDAO on an independent DAO: enabled |
| EnableProposalType | `permissions_tests::enable_proposal_type_grants_high_bits` | Payload config's 80% bit stored on the new slot |
| EnableProposalType | `permissions_tests::framework_type_enabled_with_other_bits_aborts` | Framework type with non-fixed bits: Abort `dao::EFixedPermissions` |
| EnableProposalType | `test_enable_type__already_enabled_aborts` (planned) | `NewType` already has a slot: Abort `dao::ETypeAlreadyEnabled` (registry level: `dao_tests::test_enable_twice_aborts`) |
| EnableProposalType | `test_enable_type__subdao_blocks_other_hierarchy_types` (planned) | SpinOutSubDAO, CreateSubDAO, EnableBypassType or DisableBypassType on a controlled SubDAO: Abort `admin_ops::ESubDAOBlockedType` |
| DisableProposalType | `disable_core_type_enable_proposal_type_aborts` | Abort `admin_ops::EUndisableableType` |
| DisableProposalType | `disable_core_type_unfreeze_proposal_type_aborts` | Abort `admin_ops::EUndisableableType` |
| DisableProposalType | `test_disable_type__removes_slot` (planned) | Slot, display-key index and cooldown state removed; `ProposalTypeDisabled` emitted (registry level: `dao_tests::test_enable_then_disable_leaves_nothing_behind`) |
| DisableProposalType | `test_disable_type__unknown_key_aborts` (planned) | Abort `admin_ops::ETypeNotEnabled` |
| UpdateMetadata | `charter_tests::charter_update_lifecycle` | `metadata_uri` updated, twice |
| UpdateMetadata | `charter_tests::charter_update_wrong_dao_aborts` | Abort `admin_ops::ECharterDaoMismatch` |
| EnableBypassType | `execute_enable_bypass_type_e2e` | Slot added; `ExternalExecutionCap<NewType>` stored; bypass mint works |
| EnableBypassType | `execute_enable_bypass_type_below_floor_aborts` | 2 members, 1 YES (passes the vote): yes/total = 50% → Abort `external_execution::EApprovalFloorNotMet` |
| EnableBypassType | `execute_enable_bypass_type_zero_weight_aborts` | Total weight 0: Abort `external_execution::EApprovalFloorNotMet` |
| EnableBypassType | `execute_enable_bypass_type_self_bootstrap_denied` | `NewType` = EnableBypassType: Abort `external_execution::ESelfBootstrapDenied` |
| EnableBypassType | `execute_enable_bypass_type_wrong_new_type_aborts` | Abort `external_execution::ETypeMismatch` |
| EnableBypassType | `enable_bypass_type_composable_cooldown_conflict_aborts` | Abort `external_execution::EComposableCooldownConflict` |
| EnableBypassType | `execute_enable_bypass_type_forbidden_bits_aborts` | Config holds TYPE_ADMIN: Abort `external_execution::EBypassForbiddenBits` |
| EnableBypassType | `permissions_tests::enable_bypass_type_grants_high_bits` | Payload config's 80% bit stored |
| EnableBypassType | `dao_tests::test_subdao_default_types_omit_bypass_meta` | SubDAOs are not seeded with either bypass meta-type |
| DisableBypassType | `execute_disable_bypass_type_e2e` | Cap extracted and destroyed; slot removed |
| DisableBypassType | `execute_disable_bypass_type_wrong_new_type_aborts` | Payload key ≠ `NewType`'s slot key: Abort `external_execution::ETypeMismatch` |
| DisableBypassType | `execute_disable_bypass_type_wrong_cap_id_aborts` | Abort `external_execution::ECapNotFound` |
| TransferFreezeAdmin | `test_transfer_freeze_admin__transfers_cap_and_unfreezes_all` (planned) | Every frozen type unfrozen (`TypeUnfrozen` each), `FreezeAdminTransferred`, cap owned by `new_admin` |
| TransferFreezeAdmin | `test_transfer_freeze_admin__cap_of_other_dao_aborts` (planned) | Abort `freeze_ops::ECapDaoMismatch` |
| TransferFreezeAdmin | `test_transfer_freeze_admin__freeze_of_other_dao_aborts` (planned) | Abort `freeze_ops::EFreezeDaoMismatch` |
| TransferFreezeAdmin | `emergency_tests::test_protected__transfer_freeze_admin_cannot_be_frozen` | `freeze_type<TransferFreezeAdmin>`: Abort `emergency::EProtectedType` |
| UnfreezeProposalType | `emergency_freeze_tests::governance_unfreeze_via_proposal` | Frozen type unfrozen by a board vote, no `FreezeAdminCap` needed |
| UnfreezeProposalType | `external_type_lifecycle_tests::governance_unfreeze_restores_execution` | `UnfreezeProposalType::new<Rebalance<CredA>>()` lifts the freeze; the type executes again |
| UnfreezeProposalType | `emergency_tests::test_protected__unfreeze_proposal_type_cannot_be_frozen` | Abort `emergency::EProtectedType` |
| UnfreezeProposalType | `test_unfreeze__not_frozen_type_aborts` (planned) | Type not frozen: Abort `emergency::ENotFrozen` (admin path: `emergency_tests::test_unfreeze__not_frozen_aborts`) |
| UpdateFreezeConfig | `freeze_ops_tests::update_freeze_config_e2e` | `max_freeze_duration_ms` 7 days → 3 days |
| UpdateFreezeConfig | `freeze_ops_tests::freeze_governance_types_hold_fixed_freeze_bit` | Enabled with a plain config, the slot holds exactly `FREEZE` |
| UpdateFreezeExemptTypes | `freeze_ops_tests::add_freeze_exempt_type_e2e` | Added type is exempt |
| UpdateFreezeExemptTypes | `freeze_ops_tests::remove_freeze_exempt_type_e2e` | Removed type can be frozen again |
| UpdateFreezeExemptTypes | `freeze_ops_tests::remove_mandatory_exempt_type_aborts` | Removing TransferFreezeAdmin: Abort `emergency::EMandatoryExemptType` |

Unqualified test names are in `admin_ops_tests.move` (UpdateProposalConfig, EnableProposalType, DisableProposalType) or `external_execution_tests.move` (EnableBypassType, DisableBypassType).

## Tests

---

### UpdateProposalConfig: merges overrides into the target's config

**Requirement:** `admin_ops::execute_update_proposal_config(dao, ticket)` resolves `target_type_key` to an enabled type (`admin_ops::ETypeNotEnabled` otherwise), rebuilds its config with `proposal::new_config` from the payload's `Some` fields and the existing values for `None` fields (including `composable_allowed`, `permissions` and `borrow_scope`), and stores it with `dao::update_proposal_config`.

**Why it matters:** This is how DAOs tune governance after creation. A field left unset must keep its value; in particular, an update that does not mention `permissions` must not strip the target's bits.

```move
// update_proposal_config_non_self_target_succeeds
let payload = update_proposal_config::new(
    b"SetBoard".to_ascii_string(),
    option::some(3_000), // quorum
    option::none(),      // approval_threshold
    option::none(),      // propose_threshold
    option::none(),      // expiry_ms
    option::none(),      // execution_delay_ms
    option::none(),      // cooldown_ms
    option::none(),      // composable_allowed
); // .with_permissions(bits) / .with_borrow_scope(scope) set the last two Option fields
board_voting::submit_proposal(&dao, option::some(string::utf8(b"Lower SetBoard quorum")), payload, &clock, scenario.ctx());
// ... votes ...
let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
admin_ops::execute_update_proposal_config(&mut dao, ticket);
```

`dao::update_proposal_config` checks TYPE_ADMIN, keeps a framework type's fixed bits and scope (`dao::EFixedPermissions`), runs the floors on the new config (`dao::EThresholdBelowMinimum`) and the grant rules (UpdateProposalConfig may grant). The handler also refuses `cooldown_ms > 0` together with `composable_allowed = true` (`admin_ops::EComposableCooldownConflict`).

This test lowers UpdateProposalConfig's own config to 5000 with the `test_update_config` seam so a 3-of-5 vote passes. On a real DAO that config cannot go below 8000 (`dao::min_approval_threshold_for_type`), so the test shows only that the self-targeting submission check does not apply to other targets.

---

### UpdateProposalConfig: floors and the self-targeting submission check

**Requirement:** Every config `dao` stores meets the target type's floor and the floor of the bits it holds (`dao::EThresholdBelowMinimum`). Separately, `admin_ops::propose_update_proposal_config` refuses a proposal that targets UpdateProposalConfig itself while UpdateProposalConfig's own threshold is below 8000 (`admin_ops::EFloorNotMet`), before the proposal is created.

**Why it matters:** Without floors a simple majority could lower the supermajority required for type administration, then use the lowered threshold.

- `update_config_below_floor_aborts`: an UpdateProposalConfig proposal lowering EnableProposalType's threshold to 5000 passes the vote; `execute_update_proposal_config` aborts with `dao::EThresholdBelowMinimum`.
- `update_proposal_config_self_submission_floor_rejects_below_80_percent` / `update_proposal_config_self_submission_floor_allows_80_percent`: the submission-time check with UpdateProposalConfig's own threshold lowered to 5100 (with the `test_update_config` seam) and at exactly 8000.

---

### EnableProposalType: adds a slot keyed by the pinned type

**Requirement:** `admin_ops::execute_enable_proposal_type<NewType: store>(dao, ticket)` aborts with `admin_ops::ETypeMismatch` unless `type_name::with_defining_ids<NewType>()` equals the payload's `type_name`, then enables `NewType` under the payload's display key with the payload's config (fixed bits applied for framework types, floors and grant rules enforced) and emits `ProposalTypeEnabled`.

**Why it matters:** The board votes on a specific Move type. Pinning it in the payload stops the executor from registering a different type under the approved key and config.

```move
let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0)
    .with_permissions(type_permissions::treasury_spend()); // TREASURY_WITHDRAW needs >= 8000
let payload = enable_proposal_type::new(
    b"SendCoin<SUI>".to_ascii_string(),
    type_name::with_defining_ids<SendCoin<SUI>>(),
    config,
);
board_voting::submit_proposal(&dao, option::none(), payload, &clock, scenario.ctx());
// ... votes: EnableProposalType's own config is >= 8000 ...
let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
admin_ops::execute_enable_proposal_type<SendCoin<SUI>>(&mut dao, ticket);
assert!(dao.is_type_enabled<SendCoin<SUI>>());
```

`execute_enable_proposal_type_adds_slot`, `execute_enable_proposal_type_reenable_same_type_succeeds`, `execute_enable_proposal_type_display_key_reusable_after_disable`, `execute_enable_proposal_type_wrong_new_type_aborts` and `execute_enable_proposal_type_duplicate_display_key_aborts` cover the slot and key rules.

---

### EnableProposalType: SubDAO blocklist enforced at execution

**Requirement:** On a DAO whose `controller_cap_id` is set, the handler aborts with `admin_ops::ESubDAOBlockedType` for SpawnDAO, SpinOutSubDAO, CreateSubDAO, EnableBypassType and DisableBypassType (`dao::is_subdao_blocked_type`). Submission and voting succeed; the check runs in the handler.

**Why it matters:** A controlled SubDAO that could enable these types could create its own SubDAOs, migrate away, spin itself out, or grant itself no-vote execution without its controller.

```move
#[test, expected_failure(abort_code = admin_ops::ESubDAOBlockedType)]
fun enable_blocked_type_aborts_for_subdao_with_controller() {
    // create_and_share_subdao: dao::create_subdao(..) then dao::share_subdao(subdao, controller_id)
    ...
    submit_enable_type_proposal<SpawnDAO>(&mut scenario, &clock, b"SpawnDAO");
    vote_yes(&mut scenario, &clock);
    ...
    let ticket = board_voting::ticket_from_vote(&mut subdao, proposal, &freeze, &clock, scenario.ctx());
    admin_ops::execute_enable_proposal_type<SpawnDAO>(&mut subdao, ticket); // aborts
    ...
}
```

Creation-time overrides that name a blocked type abort earlier, with `dao::EBlockedProposalType` (`tribe_tests::create_wired_subdao_aborts_on_blocked_type`, `create_tribe_configured_subdao_still_rejects_blocked_type`).

---

### EnableProposalType: 80% floor at submission

**Requirement:** `board_voting::submit_proposal<EnableProposalType>` aborts with `board_voting::EFloorNotMet` if the slot's `approval_threshold` is below 8000. The same floor holds in `dao` (`EThresholdBelowMinimum` on any stored config) and in composites.

**Why it matters:** EnableProposalType holds TYPE_ADMIN and may grant any bit to the type it enables, so its vote is held to the highest floor.

`enable_proposal_type_submission_floor_rejects_below_80_percent` lowers the slot to 7999 with the `test_update_config` seam and expects the submission to abort; `enable_proposal_type_submission_floor_allows_80_percent` submits at exactly 8000.

---

### DisableProposalType: undisableable types

**Requirement:** `admin_ops::execute_disable_proposal_type(dao, ticket)` resolves the payload's display key (`admin_ops::ETypeNotEnabled` if none), aborts with `admin_ops::EUndisableableType` for the six undisableable types, removes the slot (config, display key, cooldown state) and emits `ProposalTypeDisabled`.

**Why it matters:** Disabling EnableProposalType would freeze the type set forever. Disabling UnfreezeProposalType would remove the board's way to lift an admin freeze without the `FreezeAdminCap`, and TransferFreezeAdmin is the governed way to rotate that cap. EnableBypassType and DisableBypassType are the only types that mint and destroy an `ExternalExecutionCap`.

```move
// disable_core_type_enable_proposal_type_aborts
let payload = disable_proposal_type::new(b"EnableProposalType".to_ascii_string());
// ... submit, vote, ticket_from_vote ...
admin_ops::execute_disable_proposal_type(&mut dao, ticket); // Abort admin_ops::EUndisableableType
```

Re-enabling a disabled type needs an 80% EnableProposalType or EnableBypassType vote; its cooldown state starts empty.

---

### EnableBypassType / DisableBypassType

**Requirement:** `external_execution::execute_enable_bypass_type<NewType: store>(dao, vault, ticket, ctx)` refuses the bypass meta-types themselves (`ESelfBootstrapDenied`), requires a Standalone ticket whose yes weight is at least 80% of the total snapshot weight (`EApprovalFloorNotMet`), checks the pinned type (`ETypeMismatch`), the composable/cooldown rule, the bypass-safe bits (`EBypassForbiddenBits`: no TYPE_ADMIN, MIGRATE, VAULT_EXTRACT or FREEZE) and the SubDAO blocklist, then enables `NewType` and stores a fresh `ExternalExecutionCap<NewType>` in the vault (`BypassEnabled`). `execute_disable_bypass_type<NewType: store>(dao, vault, ticket)` checks that the payload's display key is `NewType`'s (`ETypeMismatch`) and that `cap_id` is an `ExternalExecutionCap<NewType>` in the vault (`ECapNotFound`), then destroys the cap and removes the slot (`BypassDisabled`).

**Why it matters:** Every later execution of a bypass type skips the vote, so the enabling vote is checked on actual weights (YES over the whole board), not only on votes cast. Bypass-safe bits keep a no-vote path from changing who may do what.

```move
// execute_enable_bypass_type_e2e
let config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0);
let payload = external_execution::new_enable_bypass_type(
    b"DummyBypass".to_ascii_string(),
    type_name::with_defining_ids<DummyBypass>(),
    config,
);
// ... submit, 1-member board votes YES ...
let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
external_execution::execute_enable_bypass_type<DummyBypass>(&mut dao, &mut vault, ticket, scenario.ctx());
assert!(vault.ids_for_type<ExternalExecutionCap<DummyBypass>>().length() == 1);
```

The test then mints a bypass ticket with `external_execution::ticket_from_cap<DummyBypass>(cap, &mut dao, &freeze, option::none(), DummyBypass { x: 7 }, internal::permit(), &clock, ctx)`; the `Permit<DummyBypass>` is available because the test module defines `DummyBypass`. The bypass path itself is covered in `04_proposals.md`.

---

### TransferFreezeAdmin (planned handler tests)

**Requirement:** `freeze_ops::execute_transfer_freeze_admin(freeze, cap: FreezeAdminCap, ticket)` aborts with `freeze_ops::EFreezeDaoMismatch` if `freeze` is not the ticket's DAO's and `freeze_ops::ECapDaoMismatch` if `cap` belongs to another DAO, calls `emergency::unfreeze_all` (FREEZE), emits `FreezeAdminTransferred { dao_id, new_admin }` and transfers the cap to `new_admin`. The cap is an argument by value, so the transaction must supply the current `FreezeAdminCap` object.

**Why it matters:** Rotating the freeze admin must also lift every freeze the outgoing admin placed. TransferFreezeAdmin is a mandatory freeze exemption, so a freeze cannot block it.

No test calls `execute_transfer_freeze_admin` yet. The exemption is covered at the freeze level (`emergency_tests::test_protected__transfer_freeze_admin_cannot_be_frozen`, `emergency_freeze_tests::cannot_freeze_transfer_freeze_admin`, both `emergency::EProtectedType`).

```move
#[test]
fun test_transfer_freeze_admin__transfers_cap_and_unfreezes_all() { // (planned)
    // CREATOR holds the FreezeAdminCap (dao::create transfers it to the sender).
    // 1. freeze.freeze_type<SetBoard>(&cap, &clock)
    // 2. submit transfer_freeze_admin::new(BOB), vote, ticket_from_vote
    // 3. freeze_ops::execute_transfer_freeze_admin(&mut freeze, cap, ticket)
    // Expect: freeze.frozen_types() empty; BOB owns the FreezeAdminCap.
}
```

---

### UnfreezeProposalType

**Requirement:** `freeze_ops::execute_unfreeze_proposal_type(freeze, ticket)` calls `emergency::governance_unfreeze_type(freeze, payload.type_name(), req)`, which checks the freeze's DAO (`emergency::EDAOMismatch`), requires FREEZE, and removes the entry or aborts with `emergency::ENotFrozen` if the type is not in the frozen set. The payload names the type by `TypeName`: `unfreeze_proposal_type::new<T>()`.

**Why it matters:** This is the board's override of an admin freeze without the `FreezeAdminCap`. It is a mandatory exemption, so it stays executable while other types are frozen.

`emergency_freeze_tests::governance_unfreeze_via_proposal` and `external_type_lifecycle_tests::governance_unfreeze_restores_execution` cover the happy path; `lifecycle_tests::medium_enterprise_lifecycle` (step 8) unfreezes `SendCoin<USDC>` on a SubDAO through its own board.

---

### UpdateFreezeConfig and UpdateFreezeExemptTypes

**Requirement:** `freeze_ops::execute_update_freeze_config(freeze, ticket)` sets `max_freeze_duration_ms` for future freezes (`FreezeConfigUpdated`). `freeze_ops::execute_update_freeze_exempt_types(freeze, ticket)` adds, then removes, the payload's types (`update_freeze_exempt_types::new()` then `add_type<T>()` / `remove_type<T>()`); removing a mandatory exemption aborts with `emergency::EMandatoryExemptType`. Both check the freeze belongs to the ticket's DAO (`freeze_ops::EFreezeDaoMismatch`).

**Why it matters:** The exempt set decides what keeps running during a freeze, so it is framework-owned (fixed FREEZE bit) and the two mandatory exemptions can never be removed.

`update_freeze_config_e2e`, `add_freeze_exempt_type_e2e`, `remove_freeze_exempt_type_e2e` and `remove_mandatory_exempt_type_aborts` in `freeze_ops_tests.move`.

---

### UpdateMetadata

Covered in `14_charter_ops.md`: `admin_ops::execute_update_metadata(charter, ticket)` checks the charter's DAO (`admin_ops::ECharterDaoMismatch`), calls `charter::update_metadata` (METADATA) and emits `MetadataUpdated`.
