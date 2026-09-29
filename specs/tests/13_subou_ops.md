# SubOU Operations Tests

## Summary

Eight proposal types create, control and release SubOUs. Each is proposed and voted on the parent side (the **controller** OU, or for `TransferCapToSubOU` the sending OU); the SubOU's own board never votes on them.

| Type | Package / handler | Bits (scope) | Floor |
|------|-------------------|--------------|-------|
| `CreateSubOU { name, initial_board, metadata_uri }` | framework `lifecycle_ops::execute_create_subou(vault, ticket, ctx)` | `VAULT_STORE` + `VAULT_EXTRACT` (fixed) | 80% |
| `SpinOutSubOU { subou_id, control_cap_id, freeze_admin_cap_id, spawn_ou_config, spin_out_subou_config, create_subou_config }` | framework `lifecycle_ops::execute_spin_out_subou(vault, subou_vault, subou, ticket, ctx)` | `VAULT_BORROW` + `VAULT_EXTRACT` ([`SubOUControl`], fixed) | 80% |
| `TransferCapToSubOU { cap_id, target_subou }` | `armature_proposals::subou_ops::execute_transfer_cap<T>(source_vault, target_vault, target_subou, ticket)` | `VAULT_EXTRACT` | 80% |
| `ReclaimCapFromSubOU { subou_id, cap_id, control_id }` | `subou_ops::execute_reclaim_cap<T>(controller_vault, subou_vault, subou, ticket)` | `VAULT_BORROW` + `VAULT_STORE` ([`SubOUControl`]) | 80% |
| `PauseSubOUExecution { control_id }` / `UnpauseSubOUExecution { control_id }` | `subou_ops::execute_pause_subou_execution(controller_vault, subou, ticket, ctx)` / `execute_unpause_subou_execution` | `VAULT_BORROW` ([`SubOUControl`]) | 80% |
| `ControllerBatchAddMembers { control_id, members }` / `ControllerBatchRemoveMembers` | `subou_ops::execute_controller_batch_add_members(controller_vault, members_ou, ticket, ctx)` / `execute_controller_batch_remove_members` (same arguments) | `VAULT_BORROW` ([`SubOUControl`]) | 80% |

None is a default type. The `armature_proposals` types must be enabled with the bits and scope `type_permissions` names (`transfer_cap_to_subou()`, `reclaim_cap_from_subou()`, `subou_control()`, `subou_control_scope()`); the framework types hold theirs whatever config enables them.

The controller-side handlers that act on the SubOU loan the `SubOUControl` from the controller's vault (`capability_vault::loan_cap`, which needs `VAULT_BORROW` and `SubOUControl` in the request's borrow scope), then either extract from the SubOU's vault with `controller::privileged_extract` or obtain a privileged request on the SubOU with `controller::privileged_submit` (see `15_privileged_submit.md`), and return the control in the same PTB. The checks involved are exactly:

- `privileged_submit`: `controller::assert_registered_control` — `control.subou_id == subou.id()` (`controller::EControlMismatch`) and `subou.controller_cap_id() == some(object::id(control))` (`controller::ENotController`) — and the SubOU is Active (`controller::EOUNotActive`).
- `controller::privileged_extract`: the vault is the SubOU's (`controller::EControlMismatch`), then `assert_registered_control`.
- `controller::receive_cap_from_controller` (used by `TransferCapToSubOU`, no control loaned): the target vault is the SubOU's and the controller vault is the request's OU's (`controller::EControlMismatch`), and the controller vault holds the SubOU's registered control (`controller::ENotController`).
- `set_controller_paused` / `clear_controller`: the request is privileged and for this OU (`ou::ENotPrivileged`, `ou::EOUIdMismatch`).

`controller_cap_id` is set by `ou::share_subou` when the SubOU is shared, cleared by `clear_controller` at spin-out (so the old control stops working), and is what makes the OU "controlled" for the SubOU blocklist. The framework's creation paths (`CreateSubOU`, `tribe::create_tribe(_configured)`, `tribe::create_wired_subou`) mint one `SubOUControl` per SubOU they create; `capability_vault::create_subou_control` is `public(package)` and only `CreateSubOU` calls it. Any other control naming a SubOU fails `assert_registered_control`.

An OU with `controller_cap_id` set cannot enable SpawnOU, SpinOutSubOU, CreateSubOU, EnableBypassType or DisableBypassType (`ou::is_subou_blocked_type`): not by an EnableProposalType vote (`admin_ops::ESubOUBlockedType`) and not by a creation-time override (`ou::EBlockedProposalType`). SubOUs are not seeded with the bypass meta-types, so they have no first-party way to enable a bypass type; `external_execution::execute_enable_bypass_type` repeats the blocklist check for `NewType` (`external_execution::ESubOUBlockedType`) regardless.

While `controller_paused` is set, the SubOU's two-PTB, atomic and bypass paths refuse to mint tickets (`board_voting::EControllerPaused`, `external_execution::EControllerPaused`); composites are covered because their ticket comes from `ticket_from_vote`. Submission and voting are not blocked, and the controller's privileged path still runs, so it can unpause.

Real suites: `packages/armature_proposals/tests/subou_ops_tests.move` (16) and `migration_tests.move` (`create_subou_and_spin_out_e2e`, `controller_set_board_via_privileged_submit`), plus tests cited from `admin_ops_tests.move`, `controller_tests.move`, `cross_ou_auth_tests.move`, `capability_vault_tests.move`, `gate_tests.move`, `tribe_tests.move`, `ou_tests.move` and `lifecycle_tests.move`. The hierarchy model is specified in `specs/04_subdao_hierarchy.md`.

## Test Matrix

| Test | Expected |
|------|----------|
| `admin_ops_tests::enable_blocked_type_aborts_for_subou_with_controller` | SubOU votes to enable SpawnOU: Abort `admin_ops::ESubOUBlockedType` at execution |
| `admin_ops_tests::enable_non_blocked_type_succeeds_for_subou_with_controller` | A non-blocked type is enabled on a SubOU |
| `admin_ops_tests::enable_blocked_type_succeeds_for_independent_ou` | SpawnOU is enabled on an independent OU |
| `test_subou_cannot_enable_spinout_aborts` (planned) | Same as above for SpinOutSubOU: Abort `admin_ops::ESubOUBlockedType` |
| `test_subou_cannot_enable_create_subou_aborts` (planned) | Same for CreateSubOU: Abort `admin_ops::ESubOUBlockedType` |
| `tribe_tests::create_wired_subou_aborts_on_blocked_type` | Creation override naming SpawnOU: Abort `ou::EBlockedProposalType` |
| `tribe_tests::create_tribe_configured_subou_still_rejects_blocked_type` | CreateSubOU in an Officers override: Abort `ou::EBlockedProposalType` |
| `tribe_tests::create_tribe_configured_parent_can_override_subou_blocked_type` | The same override on the parent Tribe OU is accepted |
| `ou_tests::test_subou_default_types_omit_bypass_meta` | SubOU default slots exclude EnableBypassType / DisableBypassType |
| `subou_ops_tests::create_subou_e2e` | Child created; parent vault holds its `SubOUControl` and `FreezeAdminCap` |
| `subou_ops_tests::create_subou_vault_mismatch_aborts` | Another OU's vault: Abort `lifecycle_ops::EVaultOUMismatch` |
| `subou_ops_tests::create_multi_member_subou` | 3-member SubOU; every member can submit |
| `migration_tests::create_subou_and_spin_out_e2e` (create phase) | Parent vault: exactly one `SubOUControl` and one `FreezeAdminCap`; child `controller_cap_id` is some; SpawnOU / SpinOutSubOU / CreateSubOU not enabled on the child |
| `migration_tests::create_subou_and_spin_out_e2e` (spin-out phase) | Child `controller_cap_id` none, not paused, the three hierarchy types enabled; parent vault empty; child vault holds its own `FreezeAdminCap` |
| `tribe_tests::create_wired_subou_subou_is_controlled` | `create_wired_subou` sets `controller_cap_id` |
| `tribe_tests::create_tribe_control_hierarchy_is_tribe_officers_members` | Tribe vault holds the Officers' control; Officers vault holds the Members' |
| `borrow_scope_tests::spin_out_subou_scope_is_subou_control` | SpinOutSubOU's fixed scope is [`SubOUControl`] |
| `test_spinout_clears_paused_flag` (planned) | Pause, then spin out: `is_controller_paused()` is false afterwards |
| `test_spin_out__below_floor_config_aborts` (planned) | A payload config below 8000 for SpawnOU / SpinOutSubOU / CreateSubOU: Abort `ou::EThresholdBelowMinimum` |
| `test_create_subou__emits_subou_created_event` (planned) | `SubOUCreated { controller_ou_id, subou_id, control_cap_id }` |
| `test_spinout__emits_subou_spun_out_event` (planned) | `SubOUSpunOut { controller_ou_id, subou_id }` |
| `subou_ops_tests::transfer_cap_to_subou_e2e` | Cap leaves the parent vault and is in the child's |
| `test_transfer_cap__wrong_target_vault_aborts` (planned) | Target vault's OU ≠ `target_subou`: Abort `subou_ops::ESubOUVaultMismatch` |
| `subou_ops_tests::reclaim_cap_from_subou_e2e` | Cap back in the parent vault, gone from the child's |
| `subou_ops_tests::reclaim_cap_wrong_vault_aborts` | Wrong controller vault: Abort `subou_ops::EVaultOUMismatch` |
| `test_reclaim_cap__control_for_other_subou_aborts` (planned) | `control_id` names another SubOU's control: Abort `controller::EControlMismatch` |
| `capability_vault_tests::test_privileged_extract_wrong_subou_aborts` | Package-level `privileged_extract` with a control for another OU: Abort `capability_vault::ENotController` |
| `cross_ou_auth_tests::forged_control_cannot_privileged_submit` | Another OU mints a control naming the victim and calls `privileged_submit`: Abort `controller::ENotController` |
| `cross_ou_auth_tests::unregistered_control_cannot_privileged_extract` | A control naming the SubOU but not its `controller_cap_id`: Abort `controller::ENotController` |
| `cross_ou_auth_tests::registered_control_privileged_extract_succeeds` | The registered control extracts through `controller::privileged_extract` |
| `cross_ou_auth_tests::cleared_controller_rejects_old_control` | After `clear_controller`, `privileged_submit` with the old control: Abort `controller::ENotController` |
| `cross_ou_auth_tests::unrelated_ou_cannot_deposit_into_subou_vault` | `receive_cap_from_controller` from an OU without the SubOU's control: Abort `controller::ENotController` |
| `cross_ou_auth_tests::cannot_deposit_into_top_level_ou_vault` | Target has no controller: Abort `controller::ENotController` |
| `cross_ou_auth_tests::controller_vault_must_match_request` | The real controller's vault with another OU's request: Abort `controller::EControlMismatch` |
| `test_transfer_cap__target_not_controlled_aborts` (planned) | `TransferCapToSubOU` naming an OU the sender does not control: Abort `controller::ENotController` |
| `subou_ops_tests::pause_and_unpause_subou_e2e` | Controller vote pauses, a second vote unpauses |
| `subou_ops_tests::paused_subou_blocks_execution` | While paused, the SubOU submits and votes a SetBoard; `ticket_from_vote` aborts `board_voting::EControllerPaused` |
| `controller_tests::authorize_execution_blocks_when_controller_paused` | Abort `board_voting::EControllerPaused` |
| `submit_vote_execute_tests::test_sve__controller_paused_aborts` | Atomic path: Abort `board_voting::EControllerPaused` |
| `external_execution_tests::external_executed_create_controller_paused_aborts` | Bypass path: Abort `external_execution::EControllerPaused` |
| `gate_tests::set_controller_paused_needs_privileged_request` | Unprivileged request with every bit: Abort `ou::ENotPrivileged` |
| `gate_tests::clear_controller_needs_privileged_request` | Abort `ou::ENotPrivileged` |
| `test_pause__control_for_other_subou_aborts` (planned) | Pause payload names another SubOU's control: Abort `controller::EControlMismatch` |
| `subou_ops_tests::controller_batch_add_members_e2e` | Both members on the SubOU board |
| `subou_ops_tests::controller_batch_add_members_existing_skipped` | Existing member skipped, no abort |
| `subou_ops_tests::controller_batch_remove_members_e2e` | Members added then removed via the controller |
| `subou_ops_tests::controller_batch_remove_members_nonmember_aborts` | Abort `governance::ENotBoardMember` |
| `subou_ops_tests::controller_batch_add_members_empty_aborts` / `controller_batch_remove_members_empty_aborts` | Abort `subou_ops::EEmptyBatch` |
| `subou_ops_tests::controller_batch_add_members_oversize_aborts` / `controller_batch_remove_members_oversize_aborts` | 101 entries: Abort `subou_ops::EBatchTooLarge` |
| `migration_tests::controller_set_board_via_privileged_submit` | A test controller type (VAULT_BORROW, scope [`SubOUControl`]) applies a SetBoard diff to the SubOU through a privileged request |
| `lifecycle_tests::medium_enterprise_lifecycle` | Two SubOUs; controller removes a member from one and freezes a type there in one PTB; parent funds the other with SendCoinToOU |
| `test_atomic_reclaim__full_sequence` (planned) | One controller PTB: pause, remove members, reclaim a cap, unpause (see below) |

### Removed from the plan

| Old test | Why |
|----------|-----|
| `test_only_one_control_per_subou`, `test_each_subou_has_at_most_one_controller` | Replaced: `controller_cap_id` holds one ID and only that control passes `assert_registered_control`, so other controls naming the SubOU have no authority (`cross_ou_auth_tests::forged_control_cannot_privileged_submit`, `unregistered_control_cannot_privileged_extract`). |
| `test_acyclic_graph_enforced` | No graph check exists. Creation paths only build trees; `TransferCapToSubOU` can move a `SubOUControl` into the vault of any SubOU the sender controls. |
| `test_create_subou__funds_child_treasury` | `CreateSubOU` carries no funding. Fund a SubOU with a separate `SendCoinToOU<T>` (`lifecycle_tests::medium_enterprise_lifecycle`, step 9). |
| `test_transfer_cap__requires_subou_control` | `TransferCapToSubOU` loans no `SubOUControl`; instead `receive_cap_from_controller` requires the sender's vault to hold the target's registered control (`cross_ou_auth_tests::unrelated_ou_cannot_deposit_into_subou_vault`). |
| `test_pause_requires_privileged_submit`, `test_unpause_requires_privileged_submit` | Pause/unpause are ordinary types voted on the controller; only their SubOU-side effect needs a privileged request. Covered by `pause_and_unpause_subou_e2e` and the two `gate_tests` above. |

## Tests

---

### SubOU cannot enable hierarchy-altering or bypass meta-types

**Requirement:** An OU whose `controller_cap_id` is set cannot enable `SpawnOU`, `SpinOutSubOU`, `CreateSubOU`, `EnableBypassType` or `DisableBypassType`.

**Why it matters:** A controlled SubOU that could create its own SubOUs, spawn a successor, spin itself out or grant itself no-vote execution would move authority out of its controller's reach.

The EnableProposalType submission and vote succeed; `admin_ops::execute_enable_proposal_type` aborts:

```move
#[test, expected_failure(abort_code = admin_ops::ESubOUBlockedType)]
fun enable_blocked_type_aborts_for_subou_with_controller() {
    // create_and_share_subou: ou::create_subou(&init, name, uri, ctx), then
    // ou::share_subou(subou, controller_id)
    ...
    submit_enable_type_proposal<SpawnOU>(&mut scenario, &clock, b"SpawnOU");
    vote_yes(&mut scenario, &clock);
    ...
    let ticket = board_voting::ticket_from_vote(&mut subou, proposal, &freeze, &clock, scenario.ctx());
    admin_ops::execute_enable_proposal_type<SpawnOU>(&mut subou, ticket);
    ...
}
```

---

### CreateSubOU: child OU, control and freeze cap in the parent vault

**Requirement:** `execute_create_subou` checks the vault belongs to the ticket's OU (`lifecycle_ops::EVaultOUMismatch`), builds the SubOU with `ou::create_subou` (Board of `initial_board`, SubOU default slots, charter from `name` and `metadata_uri`), mints a `SubOUControl` into the parent vault (`create_subou_control`, VAULT_EXTRACT), stores the SubOU's `FreezeAdminCap` there (`store_cap`, VAULT_STORE), shares the SubOU with `controller_cap_id = some(control_id)` and emits `SubOUCreated`.

**Why it matters:** The control must end up in the parent's vault, not at an address, or the parent has no way to govern the child. The child's `FreezeAdminCap` is also held by the parent's vault rather than by any wallet; using it needs a parent type with `VAULT_BORROW` scoped to `FreezeAdminCap` (no first-party type has one; `lifecycle_tests::medium_enterprise_lifecycle` uses a test type).

```move
// subou_ops_tests::create_subou_e2e (execution step)
let ticket = board_voting::ticket_from_vote(&mut ou, proposal, &freeze, &clock, scenario.ctx());
lifecycle_ops::execute_create_subou(&mut vault, ticket, scenario.ctx());
assert!(vault.cap_ids().length() >= 2); // SubOUControl + the SubOU's FreezeAdminCap
```

The payload was `create_subou::new(string::utf8(b"Child OU"), vector[SUBOU_MEMBER], string::utf8(b"https://example.com/child.png"))`. `migration_tests::create_subou_and_spin_out_e2e` checks the exact contents (`ids_for_type<SubOUControl>()` and `ids_for_type<FreezeAdminCap>()` of length 1), `controller_cap_id().is_some()` and that no hierarchy type is enabled on the child.

---

### Controller pause blocks every execution path on the SubOU

**Requirement:** `PauseSubOUExecution` is voted on the controller. Its handler loans the control, gets a privileged request with `privileged_submit`, calls `subou.set_controller_paused(true, &req)`, closes the request with `privileged_consume`, returns the control and emits `SubOUExecutionPaused`. While paused, the SubOU's tickets are refused on every path.

**Why it matters:** The pause lets the controller change the board or reclaim capabilities without the SubOU executing anything in between. Proposals can still be submitted and voted, so nothing is lost; they execute after the unpause if still within their window.

```move
// subou_ops_tests::pause_and_unpause_subou_e2e (pause step, on the controller)
let ticket = board_voting::ticket_from_vote(&mut parent_ou, proposal, &freeze, &clock, scenario.ctx());
subou_ops::execute_pause_subou_execution(&mut vault, &mut subou, ticket, scenario.ctx());
assert!(subou.is_controller_paused());
```

```move
#[test, expected_failure(abort_code = armature::board_voting::EControllerPaused)]
fun paused_subou_blocks_execution() {
    // ... controller pauses the SubOU ...
    // The SubOU board submits and passes set_board::new(vector[CREATOR], vector[]): both succeed.
    let ticket = board_voting::ticket_from_vote(&mut subou, proposal, &freeze, &clock, scenario.ctx());
    // ^ aborts EControllerPaused
    ...
}
```

The unpause step of `pause_and_unpause_subou_e2e` runs `privileged_submit` on the paused SubOU, showing the controller's own path is not blocked.

---

### SpinOutSubOU: independence

**Requirement:** `execute_spin_out_subou` checks the parent vault (`lifecycle_ops::EVaultOUMismatch`) and that `subou_vault` belongs to `payload.subou_id` (`lifecycle_ops::ESubOUVaultMismatch`), loans the control, and with a privileged request on the SubOU calls `clear_controller` (clears `controller_cap_id` and `controller_paused`) and enables SpawnOU, SpinOutSubOU and CreateSubOU with the payload's configs (floors still apply). It then returns the control, moves the SubOU's `FreezeAdminCap` from the parent vault into the SubOU's vault, destroys the control and emits `SubOUSpunOut`.

**Why it matters:** A spun-out OU must be fully independent: no controller, not paused, able to create its own hierarchy, and in custody of its own freeze admin cap. The parent keeps nothing that governs it.

```move
// migration_tests::create_subou_and_spin_out_e2e (spin-out phase)
let spin_config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0); // 80%: these types hold high bits
let payload = spin_out_subou::new(
    subou_id, control_cap_id, freeze_admin_cap_id,
    spin_config, spin_config, spin_config,
);
// ... submit, vote, ticket_from_vote on the parent ...
lifecycle_ops::execute_spin_out_subou(&mut parent_vault, &mut subou_vault, &mut subou, ticket, scenario.ctx());

assert!(subou.controller_cap_id().is_none());
assert!(!subou.is_controller_paused());
assert!(subou.is_type_enabled<SpawnOU>());
assert!(parent_vault.is_empty());
assert!(subou_vault.ids_for_type<FreezeAdminCap>()[0] == freeze_admin_cap_id);
```

`test_spinout_clears_paused_flag` (planned) should pause the SubOU first; the existing test spins out an unpaused SubOU.

---

### TransferCapToSubOU: moves a cap into the target vault

**Requirement:** `execute_transfer_cap<T>` checks the source vault belongs to the ticket's OU (`subou_ops::EVaultOUMismatch`) and the target vault belongs to `payload.target_subou` (`subou_ops::ESubOUVaultMismatch`), extracts `cap_id` (VAULT_EXTRACT) and hands it to the target vault with `controller::receive_cap_from_controller` on the same request, which requires `target_subou` to be a SubOU whose registered `SubOUControl` sits in the source vault (`controller::ENotController`). Emits `CapTransferredToSubOU`.

**Why it matters:** This is how an OU delegates a capability. Only the SubOU's controller can push caps into its vault this way, and only it can later reclaim them with `ReclaimCapFromSubOU`.

```move
// subou_ops_tests::transfer_cap_to_subou_e2e
let payload = transfer_cap_to_subou::new(test_cap_id, subou_id);
// ... submit, vote, ticket_from_vote on the parent ...
subou_ops::execute_transfer_cap<TestCap>(&mut parent_vault, &mut subou_vault, &subou, ticket);
assert!(!parent_vault.contains(test_cap_id));
assert!(subou_vault.contains(test_cap_id));
```

---

### ReclaimCapFromSubOU: returns a delegated cap

**Requirement:** `execute_reclaim_cap<T>` checks both vaults (`subou_ops::EVaultOUMismatch`, `subou_ops::ESubOUVaultMismatch`), loans the control named by `control_id`, calls `controller::privileged_extract(subou_vault, cap_id, subou, &control)` (`controller::EControlMismatch` unless `subou_vault` is `subou`'s and the control names it, `controller::ENotController` unless it is the SubOU's registered control), stores the cap in the controller vault (VAULT_STORE), returns the control and emits `CapReclaimedFromSubOU`. The SubOU's board is not involved and its pause state does not matter.

**Why it matters:** Delegation is revocable only if the controller can take the cap back without the SubOU's cooperation.

```move
// subou_ops_tests::reclaim_cap_from_subou_e2e
let payload = reclaim_cap_from_subou::new(subou_id, test_cap_id, control_cap_id);
// ... submit, vote, ticket_from_vote on the parent ...
subou_ops::execute_reclaim_cap<TestCap>(&mut parent_vault, &mut subou_vault, &subou, ticket);
assert!(parent_vault.contains(test_cap_id));
assert!(!subou_vault.contains(test_cap_id));
```

---

### Controller batch membership changes

**Requirement:** `execute_controller_batch_add_members` / `execute_controller_batch_remove_members` check the controller vault and the batch size (1 to 100: `subou_ops::EEmptyBatch`, `subou_ops::EBatchTooLarge`) before touching the SubOU, then loan the control, `privileged_submit` a `BatchAddMembers` / `BatchRemoveMembers` payload on the SubOU, apply it with `add_board_members_governance` / `remove_board_members_governance` on the privileged request, and emit `ControllerMembersBatchAdded { controller_ou_id, subou_id, added, skipped }` / `ControllerMembersBatchRemoved`.

**Why it matters:** The controller can replace an inactive or compromised SubOU board whatever the SubOU's own configuration. Membership rules are the same as the SubOU's own batch types: existing members are skipped on add, and removals are atomic and cannot empty the board.

`controller_batch_add_members_e2e`, `controller_batch_add_members_existing_skipped`, `controller_batch_remove_members_e2e`, `controller_batch_remove_members_nonmember_aborts` and the four size tests in `subou_ops_tests.move`.

---

### Atomic reclaim: full sequence (planned)

**Requirement:** The controller can stop a SubOU, replace its board, take back a capability and resume it in one PTB, executing four proposals already passed on the controller.

**Why it matters:** Done in one transaction, the SubOU is paused for zero real time and cannot act between the steps.

```move
// One PTB, executed by a current member of the controller OU. Each step has its own
// passed Proposal<P> on the controller; each ticket is spent by its own handler.
let t1 = board_voting::ticket_from_vote(&mut parent, pause_prop, &parent_freeze, &clock, ctx);
subou_ops::execute_pause_subou_execution(&mut parent_vault, &mut subou, t1, ctx);

let t2 = board_voting::ticket_from_vote(&mut parent, remove_prop, &parent_freeze, &clock, ctx);
subou_ops::execute_controller_batch_remove_members(&mut parent_vault, &mut subou, t2, ctx);

let t3 = board_voting::ticket_from_vote(&mut parent, reclaim_prop, &parent_freeze, &clock, ctx);
subou_ops::execute_reclaim_cap<GateCap>(&mut parent_vault, &mut subou_vault, &subou, t3);

let t4 = board_voting::ticket_from_vote(&mut parent, unpause_prop, &parent_freeze, &clock, ctx);
subou_ops::execute_unpause_subou_execution(&mut parent_vault, &mut subou, t4, ctx);

// Expect: subou not paused; old members gone; cap in parent_vault, not in subou_vault.
```

`GateCap` stands for any `key + store` capability type the SubOU holds. The same steps can also run as one composite if the controller has made the types composable. The closest existing test is `lifecycle_tests::medium_enterprise_lifecycle` (step 7), which freezes a SubOU type and removes a member in one PTB through a single test controller type.
