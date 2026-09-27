# SubDAO Operations Tests

## Summary

Eight proposal types create, control and release SubDAOs. Each is proposed and voted on the parent side (the **controller** DAO, or for `TransferCapToSubDAO` the sending DAO); the SubDAO's own board never votes on them.

| Type | Package / handler | Bits (scope) | Floor |
|------|-------------------|--------------|-------|
| `CreateSubDAO { name, initial_board, metadata_uri }` | framework `lifecycle_ops::execute_create_subdao(vault, ticket, ctx)` | `VAULT_STORE` + `VAULT_EXTRACT` (fixed) | 80% |
| `SpinOutSubDAO { subdao_id, control_cap_id, freeze_admin_cap_id, spawn_dao_config, spin_out_subdao_config, create_subdao_config }` | framework `lifecycle_ops::execute_spin_out_subdao(vault, subdao_vault, subdao, ticket, ctx)` | `VAULT_BORROW` + `VAULT_EXTRACT` ([`SubDAOControl`], fixed) | 80% |
| `TransferCapToSubDAO { cap_id, target_subdao }` | `armature_proposals::subdao_ops::execute_transfer_cap<T>(source_vault, target_vault, target_subdao, ticket)` | `VAULT_EXTRACT` | 80% |
| `ReclaimCapFromSubDAO { subdao_id, cap_id, control_id }` | `subdao_ops::execute_reclaim_cap<T>(controller_vault, subdao_vault, subdao, ticket)` | `VAULT_BORROW` + `VAULT_STORE` ([`SubDAOControl`]) | 80% |
| `PauseSubDAOExecution { control_id }` / `UnpauseSubDAOExecution { control_id }` | `subdao_ops::execute_pause_subdao_execution(controller_vault, subdao, ticket, ctx)` / `execute_unpause_subdao_execution` | `VAULT_BORROW` ([`SubDAOControl`]) | 80% |
| `ControllerBatchAddMembers { control_id, members }` / `ControllerBatchRemoveMembers` | `subdao_ops::execute_controller_batch_add_members(controller_vault, members_dao, ticket, ctx)` / `execute_controller_batch_remove_members` (same arguments) | `VAULT_BORROW` ([`SubDAOControl`]) | 80% |

None is a default type. The `armature_proposals` types must be enabled with the bits and scope `type_permissions` names (`transfer_cap_to_subdao()`, `reclaim_cap_from_subdao()`, `subdao_control()`, `subdao_control_scope()`); the framework types hold theirs whatever config enables them.

The controller-side handlers that act on the SubDAO loan the `SubDAOControl` from the controller's vault (`capability_vault::loan_cap`, which needs `VAULT_BORROW` and `SubDAOControl` in the request's borrow scope), then either extract from the SubDAO's vault with `controller::privileged_extract` or obtain a privileged request on the SubDAO with `controller::privileged_submit` (see `15_privileged_submit.md`), and return the control in the same PTB. The checks involved are exactly:

- `privileged_submit`: `controller::assert_registered_control` — `control.subdao_id == subdao.id()` (`controller::EControlMismatch`) and `subdao.controller_cap_id() == some(object::id(control))` (`controller::ENotController`) — and the SubDAO is Active (`controller::EDAONotActive`).
- `controller::privileged_extract`: the vault is the SubDAO's (`controller::EControlMismatch`), then `assert_registered_control`.
- `controller::receive_cap_from_controller` (used by `TransferCapToSubDAO`, no control loaned): the target vault is the SubDAO's and the controller vault is the request's DAO's (`controller::EControlMismatch`), and the controller vault holds the SubDAO's registered control (`controller::ENotController`).
- `set_controller_paused` / `clear_controller`: the request is privileged and for this DAO (`dao::ENotPrivileged`, `dao::EDAOIdMismatch`).

`controller_cap_id` is set by `dao::share_subdao` when the SubDAO is shared, cleared by `clear_controller` at spin-out (so the old control stops working), and is what makes the DAO "controlled" for the SubDAO blocklist. The framework's creation paths (`CreateSubDAO`, `tribe::create_tribe(_configured)`, `tribe::create_wired_subdao`) mint one `SubDAOControl` per SubDAO they create; `capability_vault::create_subdao_control` is `public(package)` and only `CreateSubDAO` calls it. Any other control naming a SubDAO fails `assert_registered_control`.

A DAO with `controller_cap_id` set cannot enable SpawnDAO, SpinOutSubDAO, CreateSubDAO, EnableBypassType or DisableBypassType (`dao::is_subdao_blocked_type`): not by an EnableProposalType vote (`admin_ops::ESubDAOBlockedType`) and not by a creation-time override (`dao::EBlockedProposalType`). SubDAOs are not seeded with the bypass meta-types, so they have no first-party way to enable a bypass type; `external_execution::execute_enable_bypass_type` repeats the blocklist check for `NewType` (`external_execution::ESubDAOBlockedType`) regardless.

While `controller_paused` is set, the SubDAO's two-PTB, atomic and bypass paths refuse to mint tickets (`board_voting::EControllerPaused`, `external_execution::EControllerPaused`); composites are covered because their ticket comes from `ticket_from_vote`. Submission and voting are not blocked, and the controller's privileged path still runs, so it can unpause.

Real suites: `packages/armature_proposals/tests/subdao_ops_tests.move` (16) and `migration_tests.move` (`create_subdao_and_spin_out_e2e`, `controller_set_board_via_privileged_submit`), plus tests cited from `admin_ops_tests.move`, `controller_tests.move`, `cross_dao_auth_tests.move`, `capability_vault_tests.move`, `gate_tests.move`, `tribe_tests.move`, `dao_tests.move` and `lifecycle_tests.move`. The hierarchy model is specified in `specs/04_subdao_hierarchy.md`.

## Test Matrix

| Test | Expected |
|------|----------|
| `admin_ops_tests::enable_blocked_type_aborts_for_subdao_with_controller` | SubDAO votes to enable SpawnDAO: Abort `admin_ops::ESubDAOBlockedType` at execution |
| `admin_ops_tests::enable_non_blocked_type_succeeds_for_subdao_with_controller` | A non-blocked type is enabled on a SubDAO |
| `admin_ops_tests::enable_blocked_type_succeeds_for_independent_dao` | SpawnDAO is enabled on an independent DAO |
| `test_subdao_cannot_enable_spinout_aborts` (planned) | Same as above for SpinOutSubDAO: Abort `admin_ops::ESubDAOBlockedType` |
| `test_subdao_cannot_enable_create_subdao_aborts` (planned) | Same for CreateSubDAO: Abort `admin_ops::ESubDAOBlockedType` |
| `tribe_tests::create_wired_subdao_aborts_on_blocked_type` | Creation override naming SpawnDAO: Abort `dao::EBlockedProposalType` |
| `tribe_tests::create_tribe_configured_subdao_still_rejects_blocked_type` | CreateSubDAO in an Officers override: Abort `dao::EBlockedProposalType` |
| `tribe_tests::create_tribe_configured_parent_can_override_subdao_blocked_type` | The same override on the parent Tribe DAO is accepted |
| `dao_tests::test_subdao_default_types_omit_bypass_meta` | SubDAO default slots exclude EnableBypassType / DisableBypassType |
| `subdao_ops_tests::create_subdao_e2e` | Child created; parent vault holds its `SubDAOControl` and `FreezeAdminCap` |
| `subdao_ops_tests::create_subdao_vault_mismatch_aborts` | Another DAO's vault: Abort `lifecycle_ops::EVaultDAOMismatch` |
| `subdao_ops_tests::create_multi_member_subdao` | 3-member SubDAO; every member can submit |
| `migration_tests::create_subdao_and_spin_out_e2e` (create phase) | Parent vault: exactly one `SubDAOControl` and one `FreezeAdminCap`; child `controller_cap_id` is some; SpawnDAO / SpinOutSubDAO / CreateSubDAO not enabled on the child |
| `migration_tests::create_subdao_and_spin_out_e2e` (spin-out phase) | Child `controller_cap_id` none, not paused, the three hierarchy types enabled; parent vault empty; child vault holds its own `FreezeAdminCap` |
| `tribe_tests::create_wired_subdao_subdao_is_controlled` | `create_wired_subdao` sets `controller_cap_id` |
| `tribe_tests::create_tribe_control_hierarchy_is_tribe_officers_members` | Tribe vault holds the Officers' control; Officers vault holds the Members' |
| `borrow_scope_tests::spin_out_subdao_scope_is_subdao_control` | SpinOutSubDAO's fixed scope is [`SubDAOControl`] |
| `test_spinout_clears_paused_flag` (planned) | Pause, then spin out: `is_controller_paused()` is false afterwards |
| `test_spin_out__below_floor_config_aborts` (planned) | A payload config below 8000 for SpawnDAO / SpinOutSubDAO / CreateSubDAO: Abort `dao::EThresholdBelowMinimum` |
| `test_create_subdao__emits_subdao_created_event` (planned) | `SubDAOCreated { controller_dao_id, subdao_id, control_cap_id }` |
| `test_spinout__emits_subdao_spun_out_event` (planned) | `SubDAOSpunOut { controller_dao_id, subdao_id }` |
| `subdao_ops_tests::transfer_cap_to_subdao_e2e` | Cap leaves the parent vault and is in the child's |
| `test_transfer_cap__wrong_target_vault_aborts` (planned) | Target vault's DAO ≠ `target_subdao`: Abort `subdao_ops::ESubDAOVaultMismatch` |
| `subdao_ops_tests::reclaim_cap_from_subdao_e2e` | Cap back in the parent vault, gone from the child's |
| `subdao_ops_tests::reclaim_cap_wrong_vault_aborts` | Wrong controller vault: Abort `subdao_ops::EVaultDAOMismatch` |
| `test_reclaim_cap__control_for_other_subdao_aborts` (planned) | `control_id` names another SubDAO's control: Abort `controller::EControlMismatch` |
| `capability_vault_tests::test_privileged_extract_wrong_subdao_aborts` | Package-level `privileged_extract` with a control for another DAO: Abort `capability_vault::ENotController` |
| `cross_dao_auth_tests::forged_control_cannot_privileged_submit` | Another DAO mints a control naming the victim and calls `privileged_submit`: Abort `controller::ENotController` |
| `cross_dao_auth_tests::unregistered_control_cannot_privileged_extract` | A control naming the SubDAO but not its `controller_cap_id`: Abort `controller::ENotController` |
| `cross_dao_auth_tests::registered_control_privileged_extract_succeeds` | The registered control extracts through `controller::privileged_extract` |
| `cross_dao_auth_tests::cleared_controller_rejects_old_control` | After `clear_controller`, `privileged_submit` with the old control: Abort `controller::ENotController` |
| `cross_dao_auth_tests::unrelated_dao_cannot_deposit_into_subdao_vault` | `receive_cap_from_controller` from a DAO without the SubDAO's control: Abort `controller::ENotController` |
| `cross_dao_auth_tests::cannot_deposit_into_top_level_dao_vault` | Target has no controller: Abort `controller::ENotController` |
| `cross_dao_auth_tests::controller_vault_must_match_request` | The real controller's vault with another DAO's request: Abort `controller::EControlMismatch` |
| `test_transfer_cap__target_not_controlled_aborts` (planned) | `TransferCapToSubDAO` naming a DAO the sender does not control: Abort `controller::ENotController` |
| `subdao_ops_tests::pause_and_unpause_subdao_e2e` | Controller vote pauses, a second vote unpauses |
| `subdao_ops_tests::paused_subdao_blocks_execution` | While paused, the SubDAO submits and votes a SetBoard; `ticket_from_vote` aborts `board_voting::EControllerPaused` |
| `controller_tests::authorize_execution_blocks_when_controller_paused` | Abort `board_voting::EControllerPaused` |
| `submit_vote_execute_tests::test_sve__controller_paused_aborts` | Atomic path: Abort `board_voting::EControllerPaused` |
| `external_execution_tests::external_executed_create_controller_paused_aborts` | Bypass path: Abort `external_execution::EControllerPaused` |
| `gate_tests::set_controller_paused_needs_privileged_request` | Unprivileged request with every bit: Abort `dao::ENotPrivileged` |
| `gate_tests::clear_controller_needs_privileged_request` | Abort `dao::ENotPrivileged` |
| `test_pause__control_for_other_subdao_aborts` (planned) | Pause payload names another SubDAO's control: Abort `controller::EControlMismatch` |
| `subdao_ops_tests::controller_batch_add_members_e2e` | Both members on the SubDAO board |
| `subdao_ops_tests::controller_batch_add_members_existing_skipped` | Existing member skipped, no abort |
| `subdao_ops_tests::controller_batch_remove_members_e2e` | Members added then removed via the controller |
| `subdao_ops_tests::controller_batch_remove_members_nonmember_aborts` | Abort `governance::ENotBoardMember` |
| `subdao_ops_tests::controller_batch_add_members_empty_aborts` / `controller_batch_remove_members_empty_aborts` | Abort `subdao_ops::EEmptyBatch` |
| `subdao_ops_tests::controller_batch_add_members_oversize_aborts` / `controller_batch_remove_members_oversize_aborts` | 101 entries: Abort `subdao_ops::EBatchTooLarge` |
| `migration_tests::controller_set_board_via_privileged_submit` | A test controller type (VAULT_BORROW, scope [`SubDAOControl`]) applies a SetBoard diff to the SubDAO through a privileged request |
| `lifecycle_tests::medium_enterprise_lifecycle` | Two SubDAOs; controller removes a member from one and freezes a type there in one PTB; parent funds the other with SendCoinToDAO |
| `test_atomic_reclaim__full_sequence` (planned) | One controller PTB: pause, remove members, reclaim a cap, unpause (see below) |

### Removed from the plan

| Old test | Why |
|----------|-----|
| `test_only_one_control_per_subdao`, `test_each_subdao_has_at_most_one_controller` | Replaced: `controller_cap_id` holds one ID and only that control passes `assert_registered_control`, so other controls naming the SubDAO have no authority (`cross_dao_auth_tests::forged_control_cannot_privileged_submit`, `unregistered_control_cannot_privileged_extract`). |
| `test_acyclic_graph_enforced` | No graph check exists. Creation paths only build trees; `TransferCapToSubDAO` can move a `SubDAOControl` into the vault of any SubDAO the sender controls. |
| `test_create_subdao__funds_child_treasury` | `CreateSubDAO` carries no funding. Fund a SubDAO with a separate `SendCoinToDAO<T>` (`lifecycle_tests::medium_enterprise_lifecycle`, step 9). |
| `test_transfer_cap__requires_subdao_control` | `TransferCapToSubDAO` loans no `SubDAOControl`; instead `receive_cap_from_controller` requires the sender's vault to hold the target's registered control (`cross_dao_auth_tests::unrelated_dao_cannot_deposit_into_subdao_vault`). |
| `test_pause_requires_privileged_submit`, `test_unpause_requires_privileged_submit` | Pause/unpause are ordinary types voted on the controller; only their SubDAO-side effect needs a privileged request. Covered by `pause_and_unpause_subdao_e2e` and the two `gate_tests` above. |

## Tests

---

### SubDAO cannot enable hierarchy-altering or bypass meta-types

**Requirement:** A DAO whose `controller_cap_id` is set cannot enable `SpawnDAO`, `SpinOutSubDAO`, `CreateSubDAO`, `EnableBypassType` or `DisableBypassType`.

**Why it matters:** A controlled SubDAO that could create its own SubDAOs, spawn a successor, spin itself out or grant itself no-vote execution would move authority out of its controller's reach.

The EnableProposalType submission and vote succeed; `admin_ops::execute_enable_proposal_type` aborts:

```move
#[test, expected_failure(abort_code = admin_ops::ESubDAOBlockedType)]
fun enable_blocked_type_aborts_for_subdao_with_controller() {
    // create_and_share_subdao: dao::create_subdao(&init, name, uri, ctx), then
    // dao::share_subdao(subdao, controller_id)
    ...
    submit_enable_type_proposal<SpawnDAO>(&mut scenario, &clock, b"SpawnDAO");
    vote_yes(&mut scenario, &clock);
    ...
    let ticket = board_voting::ticket_from_vote(&mut subdao, proposal, &freeze, &clock, scenario.ctx());
    admin_ops::execute_enable_proposal_type<SpawnDAO>(&mut subdao, ticket);
    ...
}
```

---

### CreateSubDAO: child DAO, control and freeze cap in the parent vault

**Requirement:** `execute_create_subdao` checks the vault belongs to the ticket's DAO (`lifecycle_ops::EVaultDAOMismatch`), builds the SubDAO with `dao::create_subdao` (Board of `initial_board`, SubDAO default slots, charter from `name` and `metadata_uri`), mints a `SubDAOControl` into the parent vault (`create_subdao_control`, VAULT_EXTRACT), stores the SubDAO's `FreezeAdminCap` there (`store_cap`, VAULT_STORE), shares the SubDAO with `controller_cap_id = some(control_id)` and emits `SubDAOCreated`.

**Why it matters:** The control must end up in the parent's vault, not at an address, or the parent has no way to govern the child. The child's `FreezeAdminCap` is also held by the parent's vault rather than by any wallet; using it needs a parent type with `VAULT_BORROW` scoped to `FreezeAdminCap` (no first-party type has one; `lifecycle_tests::medium_enterprise_lifecycle` uses a test type).

```move
// subdao_ops_tests::create_subdao_e2e (execution step)
let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
lifecycle_ops::execute_create_subdao(&mut vault, ticket, scenario.ctx());
assert!(vault.cap_ids().length() >= 2); // SubDAOControl + the SubDAO's FreezeAdminCap
```

The payload was `create_subdao::new(string::utf8(b"Child DAO"), vector[SUBDAO_MEMBER], string::utf8(b"https://example.com/child.png"))`. `migration_tests::create_subdao_and_spin_out_e2e` checks the exact contents (`ids_for_type<SubDAOControl>()` and `ids_for_type<FreezeAdminCap>()` of length 1), `controller_cap_id().is_some()` and that no hierarchy type is enabled on the child.

---

### Controller pause blocks every execution path on the SubDAO

**Requirement:** `PauseSubDAOExecution` is voted on the controller. Its handler loans the control, gets a privileged request with `privileged_submit`, calls `subdao.set_controller_paused(true, &req)`, closes the request with `privileged_consume`, returns the control and emits `SubDAOExecutionPaused`. While paused, the SubDAO's tickets are refused on every path.

**Why it matters:** The pause lets the controller change the board or reclaim capabilities without the SubDAO executing anything in between. Proposals can still be submitted and voted, so nothing is lost; they execute after the unpause if still within their window.

```move
// subdao_ops_tests::pause_and_unpause_subdao_e2e (pause step, on the controller)
let ticket = board_voting::ticket_from_vote(&mut parent_dao, proposal, &freeze, &clock, scenario.ctx());
subdao_ops::execute_pause_subdao_execution(&mut vault, &mut subdao, ticket, scenario.ctx());
assert!(subdao.is_controller_paused());
```

```move
#[test, expected_failure(abort_code = armature::board_voting::EControllerPaused)]
fun paused_subdao_blocks_execution() {
    // ... controller pauses the SubDAO ...
    // The SubDAO board submits and passes set_board::new(vector[CREATOR], vector[]): both succeed.
    let ticket = board_voting::ticket_from_vote(&mut subdao, proposal, &freeze, &clock, scenario.ctx());
    // ^ aborts EControllerPaused
    ...
}
```

The unpause step of `pause_and_unpause_subdao_e2e` runs `privileged_submit` on the paused SubDAO, showing the controller's own path is not blocked.

---

### SpinOutSubDAO: independence

**Requirement:** `execute_spin_out_subdao` checks the parent vault (`lifecycle_ops::EVaultDAOMismatch`) and that `subdao_vault` belongs to `payload.subdao_id` (`lifecycle_ops::ESubDAOVaultMismatch`), loans the control, and with a privileged request on the SubDAO calls `clear_controller` (clears `controller_cap_id` and `controller_paused`) and enables SpawnDAO, SpinOutSubDAO and CreateSubDAO with the payload's configs (floors still apply). It then returns the control, moves the SubDAO's `FreezeAdminCap` from the parent vault into the SubDAO's vault, destroys the control and emits `SubDAOSpunOut`.

**Why it matters:** A spun-out DAO must be fully independent: no controller, not paused, able to create its own hierarchy, and in custody of its own freeze admin cap. The parent keeps nothing that governs it.

```move
// migration_tests::create_subdao_and_spin_out_e2e (spin-out phase)
let spin_config = proposal::new_config(5_000, 8_000, 0, 604_800_000, 0, 0); // 80%: these types hold high bits
let payload = spin_out_subdao::new(
    subdao_id, control_cap_id, freeze_admin_cap_id,
    spin_config, spin_config, spin_config,
);
// ... submit, vote, ticket_from_vote on the parent ...
lifecycle_ops::execute_spin_out_subdao(&mut parent_vault, &mut subdao_vault, &mut subdao, ticket, scenario.ctx());

assert!(subdao.controller_cap_id().is_none());
assert!(!subdao.is_controller_paused());
assert!(subdao.is_type_enabled<SpawnDAO>());
assert!(parent_vault.is_empty());
assert!(subdao_vault.ids_for_type<FreezeAdminCap>()[0] == freeze_admin_cap_id);
```

`test_spinout_clears_paused_flag` (planned) should pause the SubDAO first; the existing test spins out an unpaused SubDAO.

---

### TransferCapToSubDAO: moves a cap into the target vault

**Requirement:** `execute_transfer_cap<T>` checks the source vault belongs to the ticket's DAO (`subdao_ops::EVaultDAOMismatch`) and the target vault belongs to `payload.target_subdao` (`subdao_ops::ESubDAOVaultMismatch`), extracts `cap_id` (VAULT_EXTRACT) and hands it to the target vault with `controller::receive_cap_from_controller` on the same request, which requires `target_subdao` to be a SubDAO whose registered `SubDAOControl` sits in the source vault (`controller::ENotController`). Emits `CapTransferredToSubDAO`.

**Why it matters:** This is how a DAO delegates a capability. Only the SubDAO's controller can push caps into its vault this way, and only it can later reclaim them with `ReclaimCapFromSubDAO`.

```move
// subdao_ops_tests::transfer_cap_to_subdao_e2e
let payload = transfer_cap_to_subdao::new(test_cap_id, subdao_id);
// ... submit, vote, ticket_from_vote on the parent ...
subdao_ops::execute_transfer_cap<TestCap>(&mut parent_vault, &mut subdao_vault, &subdao, ticket);
assert!(!parent_vault.contains(test_cap_id));
assert!(subdao_vault.contains(test_cap_id));
```

---

### ReclaimCapFromSubDAO: returns a delegated cap

**Requirement:** `execute_reclaim_cap<T>` checks both vaults (`subdao_ops::EVaultDAOMismatch`, `subdao_ops::ESubDAOVaultMismatch`), loans the control named by `control_id`, calls `controller::privileged_extract(subdao_vault, cap_id, subdao, &control)` (`controller::EControlMismatch` unless `subdao_vault` is `subdao`'s and the control names it, `controller::ENotController` unless it is the SubDAO's registered control), stores the cap in the controller vault (VAULT_STORE), returns the control and emits `CapReclaimedFromSubDAO`. The SubDAO's board is not involved and its pause state does not matter.

**Why it matters:** Delegation is revocable only if the controller can take the cap back without the SubDAO's cooperation.

```move
// subdao_ops_tests::reclaim_cap_from_subdao_e2e
let payload = reclaim_cap_from_subdao::new(subdao_id, test_cap_id, control_cap_id);
// ... submit, vote, ticket_from_vote on the parent ...
subdao_ops::execute_reclaim_cap<TestCap>(&mut parent_vault, &mut subdao_vault, &subdao, ticket);
assert!(parent_vault.contains(test_cap_id));
assert!(!subdao_vault.contains(test_cap_id));
```

---

### Controller batch membership changes

**Requirement:** `execute_controller_batch_add_members` / `execute_controller_batch_remove_members` check the controller vault and the batch size (1 to 100: `subdao_ops::EEmptyBatch`, `subdao_ops::EBatchTooLarge`) before touching the SubDAO, then loan the control, `privileged_submit` a `BatchAddMembers` / `BatchRemoveMembers` payload on the SubDAO, apply it with `add_board_members_governance` / `remove_board_members_governance` on the privileged request, and emit `ControllerMembersBatchAdded { controller_dao_id, subdao_id, added, skipped }` / `ControllerMembersBatchRemoved`.

**Why it matters:** The controller can replace an inactive or compromised SubDAO board whatever the SubDAO's own configuration. Membership rules are the same as the SubDAO's own batch types: existing members are skipped on add, and removals are atomic and cannot empty the board.

`controller_batch_add_members_e2e`, `controller_batch_add_members_existing_skipped`, `controller_batch_remove_members_e2e`, `controller_batch_remove_members_nonmember_aborts` and the four size tests in `subdao_ops_tests.move`.

---

### Atomic reclaim: full sequence (planned)

**Requirement:** The controller can stop a SubDAO, replace its board, take back a capability and resume it in one PTB, executing four proposals already passed on the controller.

**Why it matters:** Done in one transaction, the SubDAO is paused for zero real time and cannot act between the steps.

```move
// One PTB, executed by a current member of the controller DAO. Each step has its own
// passed Proposal<P> on the controller; each ticket is spent by its own handler.
let t1 = board_voting::ticket_from_vote(&mut parent, pause_prop, &parent_freeze, &clock, ctx);
subdao_ops::execute_pause_subdao_execution(&mut parent_vault, &mut subdao, t1, ctx);

let t2 = board_voting::ticket_from_vote(&mut parent, remove_prop, &parent_freeze, &clock, ctx);
subdao_ops::execute_controller_batch_remove_members(&mut parent_vault, &mut subdao, t2, ctx);

let t3 = board_voting::ticket_from_vote(&mut parent, reclaim_prop, &parent_freeze, &clock, ctx);
subdao_ops::execute_reclaim_cap<GateCap>(&mut parent_vault, &mut subdao_vault, &subdao, t3);

let t4 = board_voting::ticket_from_vote(&mut parent, unpause_prop, &parent_freeze, &clock, ctx);
subdao_ops::execute_unpause_subdao_execution(&mut parent_vault, &mut subdao, t4, ctx);

// Expect: subdao not paused; old members gone; cap in parent_vault, not in subdao_vault.
```

`GateCap` stands for any `key + store` capability type the SubDAO holds. The same steps can also run as one composite if the controller has made the types composable. The closest existing test is `lifecycle_tests::medium_enterprise_lifecycle` (step 7), which freezes a SubDAO type and removes a member in one PTB through a single test controller type.
