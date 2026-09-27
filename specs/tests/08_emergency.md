# Emergency Freeze Tests

## Summary

`emergency.move` is a per-DAO circuit breaker. `EmergencyFreeze { dao_id, frozen_types: VecMap<TypeName, u64>, max_freeze_duration_ms, freeze_exempt_types: VecSet<TypeName> }` maps each frozen proposal type to its expiry time; `FreezeAdminCap { dao_id }` lets its holder freeze and unfreeze types directly, with no proposal. Entries are keyed by the payload's canonical `TypeName` (`type_name::with_defining_ids<P>()`), the same key as the DAO's type slots, so each instantiation of a generic payload is frozen separately. A freeze blocks execution of the type on the two-PTB, atomic, bypass and composite-step paths, and expires on its own after `max_freeze_duration_ms` (7 days by default).

Governance changes to the freeze need the `FREEZE` bit and go through four framework types handled by `armature::freeze_ops`: `TransferFreezeAdmin` and `UnfreezeProposalType` (default slots, undisableable, and exempt from freezing) and `UpdateFreezeConfig` and `UpdateFreezeExemptTypes` (opt-in).

These tests verify cap custody, freezing and unfreezing, expiry, type-keyed freezes on every execution path, the exempt set and its mandatory members, and the governance handlers.

## Test Matrix

**Cap custody**

| Test | Expected | Where |
|------|----------|-------|
| `test_create_dao` | `dao::create` transfers the `FreezeAdminCap` to the creator | `dao_tests` |
| `test_create_returning_vault_other_companions_are_shared` | Same for the package-internal constructor | `dao_tests` |
| `create_tribe_freeze_caps_routed_correctly` | Tribe cap to the sender; Officers and Members caps to `officer_freeze_admin` / `member_freeze_admin` | `tribe_tests` |
| `create_wired_subdao_freeze_cap_routed_to_admin` | Cap to the `freeze_admin` argument | `tribe_tests` |
| `create_subdao_and_spin_out_e2e` | `CreateSubDAO` stores the SubDAO's cap in the parent's vault; `SpinOutSubDAO` moves it into the SubDAO's own vault | `armature_proposals::migration_tests` |
| `medium_enterprise_lifecycle` | A parent-side test type holding `VAULT_BORROW` with scope `[SubDAOControl, FreezeAdminCap]` loans a SubDAO's cap from the parent vault, freezes a type on the SubDAO and returns the cap | `armature_proposals::lifecycle_tests` |
| `test_spawn_dao_successor_cap_to_executor` | After `SpawnDAO`, the successor's cap is owned by the sender of the executing transaction | planned |

**Admin freeze and unfreeze**

| Test | Expected | Where |
|------|----------|-------|
| `test_freeze__blocks_execution_of_frozen_type` | After `freeze_type<P>`, `is_frozen<P>` and `is_frozen_by_name` are true | `emergency_tests` |
| `test_freeze__assert_not_frozen_aborts` | `emergency::EFrozen` | `emergency_tests` |
| `test_freeze__does_not_block_unfrozen_types` | Other types are not frozen | `emergency_tests` |
| `test_freeze__generic_instantiations_are_independent` | Freezing `PlaceOrder<CredA>` leaves `PlaceOrder<CredB>` unfrozen | `emergency_tests` |
| `test_freeze__requires_freeze_admin_cap` | A cap for another DAO: `emergency::EDAOMismatch` | `emergency_tests` |
| `test_freeze__sets_expiry` | Expiry is `now + max_freeze_duration_ms` | `emergency_tests` |
| `test_refreeze_resets_expiry` | Freezing a frozen type sets its expiry to the new `now + max_freeze_duration_ms` and emits `TypeFrozen` again | planned |
| `test_freeze_emits_type_frozen` | `TypeFrozen { dao_id, type_name, expiry_ms }` with the canonical type string | planned |
| `test_unfreeze__cap_holder_can_unfreeze` | `unfreeze_type<P>` removes the entry; the map is empty | `emergency_tests` |
| `test_unfreeze__not_frozen_aborts` | `emergency::ENotFrozen` | `emergency_tests` |
| `test_unfreeze__governance_can_unfreeze` | The package-internal `governance_unfreeze` removes the entry | `emergency_tests` |
| `test_freeze_duration_overflow_aborts` | With `max_freeze_duration_ms` near `u64::MAX`, `freeze_type` aborts on arithmetic overflow (the sum does not saturate) | planned |

**Expiry**

| Test | Expected | Where |
|------|----------|-------|
| `test_auto_expiry__expired_freeze_treated_as_inactive` | Past its expiry the type is not frozen and `assert_not_frozen` passes | `emergency_tests` |
| `auto_expiry_allows_execution` | A proposal passed during a freeze executes after the freeze expires, without an unfreeze | `armature_proposals::emergency_freeze_tests` |
| `update_freeze_config_e2e` | A new duration bounds later freezes | `freeze_ops_tests` |
| `test_expired_entry_stays_until_removed` | An expired entry stays in `frozen_types` (`is_empty` false) until `unfreeze_type` or `unfreeze_all` removes it | planned |
| `test_zero_max_duration_freezes_nothing` | With `max_freeze_duration_ms == 0`, a new freeze expires at once (`is_frozen` false) | planned |

**Execution paths**

| Test | Expected | Where |
|------|----------|-------|
| `frozen_type_blocks_execution` | `ticket_from_vote` on a frozen type: `emergency::EFrozen` | `armature_proposals::emergency_freeze_tests` |
| `two_ptb__frozen_instantiation_aborts`, `atomic__frozen_instantiation_aborts`, `bypass__frozen_instantiation_aborts` | `emergency::EFrozen` on each path for `Order<CredA>` | `freeze_path_tests` |
| `two_ptb__other_instantiation_unaffected`, `atomic__other_instantiation_unaffected`, `bypass__other_instantiation_unaffected` | `Order<CredB>` still executes | `freeze_path_tests` |
| `test_sve__frozen_type_aborts` | Atomic path: `emergency::EFrozen` | `submit_vote_execute_tests` |
| `frozen_type_blocks_two_ptb`, `frozen_type_blocks_atomic`, `frozen_type_blocks_bypass` | A third-party type enabled by vote: `emergency::EFrozen` | `armature_external_type_tests::external_type_lifecycle_tests` |
| `freeze_leaves_other_instantiation_executable` | `Rebalance<CredB>` executes while `Rebalance<CredA>` is frozen | `armature_external_type_tests::external_type_lifecycle_tests` |
| `test_composite_frozen_step_aborts` | `composite::advance_step` for a frozen step type: `emergency::EFrozen` | planned |
| submission and voting are not blocked | `two_ptb__frozen_instantiation_aborts` submits and votes while frozen and aborts only at `ticket_from_vote`; `auto_expiry_allows_execution` votes while frozen | `freeze_path_tests`, `armature_proposals::emergency_freeze_tests` |
| controller override is not blocked | `controller::privileged_submit` takes no `EmergencyFreeze` | structural |
| `freeze_outlasting_window_blocks_execution` | A freeze that outlasts a Passed proposal's window: `proposal::EExecutionWindowClosed` once it lifts (accepted behaviour) | `armature_proposals::emergency_freeze_tests` |
| `freeze_outlasting_window_allows_delete` | Anyone deletes that proposal with `delete_expired_proposal` | `armature_proposals::emergency_freeze_tests` |

**Unfreezing and restoring execution**

| Test | Expected | Where |
|------|----------|-------|
| `unfreeze_allows_execution` | Admin unfreeze, then the pending proposal executes | `armature_proposals::emergency_freeze_tests` |
| `two_ptb__executes_after_unfreeze` | Same on the two-PTB path | `freeze_path_tests` |
| `governance_unfreeze_via_proposal` | An `UnfreezeProposalType` vote lifts the freeze (`freeze_ops::execute_unfreeze_proposal_type`) | `armature_proposals::emergency_freeze_tests` |
| `governance_unfreeze_restores_execution` | After the vote the third-party type executes on the atomic and two-PTB paths | `armature_external_type_tests::external_type_lifecycle_tests` |
| `test_governance_unfreeze_not_frozen_aborts` | `UnfreezeProposalType` for a type that is not frozen: `emergency::ENotFrozen` at execution | planned |

**Exempt types**

| Test | Expected | Where |
|------|----------|-------|
| `test_protected__transfer_freeze_admin_cannot_be_frozen`, `test_protected__unfreeze_proposal_type_cannot_be_frozen` | `emergency::EProtectedType` | `emergency_tests` |
| `cannot_freeze_transfer_freeze_admin`, `cannot_freeze_unfreeze_proposal_type` | Same with a DAO's own freeze and cap | `armature_proposals::emergency_freeze_tests` |
| `test_protected__lookalike_type_is_not_exempt` | A type from another module with the same name can be frozen | `emergency_tests` |
| `test_exempt__default_types_include_mandatory` | The default exempt set is exactly the two mandatory types | `emergency_tests` |
| `test_exempt__custom_exempt_type_cannot_be_frozen` | A type added to the set: `emergency::EProtectedType` | `emergency_tests` |
| `test_exempt__removed_type_can_be_frozen` | Removed from the set, the type can be frozen | `emergency_tests` |
| `test_exempt__mandatory_type_cannot_be_removed`, `test_exempt__mandatory_unfreeze_type_cannot_be_removed` | `emergency::EMandatoryExemptType` (test seam) | `emergency_tests` |
| `add_freeze_exempt_type_e2e`, `remove_freeze_exempt_type_e2e` | `UpdateFreezeExemptTypes` adds, then removes, `SetBoard`; once removed it can be frozen | `freeze_ops_tests` |
| `remove_mandatory_exempt_type_aborts` | Removing `TransferFreezeAdmin` by vote: `emergency::EMandatoryExemptType` | `freeze_ops_tests` |
| `test_exempting_a_frozen_type_keeps_it_frozen` | Adding a frozen type to the set does not lift its freeze | planned |
| `test_add_already_exempt_type_aborts` | Aborts in `sui::vec_set` (`EKeyAlreadyExists`); removing a type that is not exempt aborts with `EKeyDoesNotExist` | planned |
| `disable_core_type_unfreeze_proposal_type_aborts` | `UnfreezeProposalType` cannot be disabled: `admin_ops::EUndisableableType` | `armature_proposals::admin_ops_tests` |

**Governance changes (`FREEZE`)**

| Test | Expected | Where |
|------|----------|-------|
| `governance_unfreeze_type_needs_freeze`, `update_freeze_duration_needs_freeze`, `unfreeze_all_needs_freeze`, `add_freeze_exempt_type_needs_freeze`, `remove_freeze_exempt_type_needs_freeze` | Every bit except `FREEZE`: `proposal::EPermissionDenied` | `gate_tests` |
| `bypass_ticket_cannot_unfreeze_other_type`, `atomic_ticket_cannot_unfreeze_other_type` | A request of a type without `FREEZE` cannot lift a freeze on another type: `proposal::EPermissionDenied` | `armature_external_type_tests::external_type_lifecycle_tests` |
| `freeze_governance_types_hold_fixed_freeze_bit` | `UpdateFreezeConfig` and `UpdateFreezeExemptTypes` are framework types holding exactly `FREEZE` | `freeze_ops_tests` |
| `update_freeze_config_e2e` | `max_freeze_duration_ms` changes from 7 days to 3 days | `freeze_ops_tests` |
| `test_emergency_mutator_other_dao_request_aborts` | A request for another DAO: `emergency::EDAOMismatch` | planned |
| `test_freeze_ops_wrong_freeze_aborts` | `UpdateFreezeConfig` / `UpdateFreezeExemptTypes` / `TransferFreezeAdmin` executed against another DAO's freeze: `freeze_ops::EFreezeDaoMismatch` (`UnfreezeProposalType`: `emergency::EDAOMismatch`) | planned |
| `test_freeze_governance_events` | `TypeUnfrozen`, `FreezeExemptTypeAdded`, `FreezeExemptTypeRemoved`, `freeze_ops::FreezeConfigUpdated` | planned |
| `test_transfer_freeze_admin__moves_cap_and_unfreezes_all` | Every entry removed (a `TypeUnfrozen` each), `FreezeAdminTransferred` emitted, cap owned by `new_admin` | planned |
| `test_transfer_freeze_admin__other_dao_cap_aborts` | `freeze_ops::ECapDaoMismatch` | planned |

## Tests

---

### Who holds the FreezeAdminCap

**Requirement:** The cap is an ordinary owned object (`key, store`), bound to one DAO by `dao_id`.

| Creation path | Cap goes to |
|---|---|
| `dao::create` | the sender (the creator) |
| `SpawnDAO` (successor created with `dao::create` inside `lifecycle_ops::execute_spawn_dao`) | the sender of the executing transaction |
| `dao::create_subdao(_configured)` | returned to the caller |
| `tribe::create_tribe(_configured)` | the tribe's cap to the sender; the Officers and Members caps to `officer_freeze_admin` and `member_freeze_admin` |
| `tribe::create_wired_subdao` | the `freeze_admin` argument |
| `CreateSubDAO` (`lifecycle_ops::execute_create_subdao`) | stored in the parent's `CapabilityVault` (`VAULT_STORE`) |
| `SpinOutSubDAO` | extracted from the parent's vault into the SubDAO's own vault |

A wallet-held cap is used directly by its owner, who can also move it with `transfer::public_transfer` without a vote. A vault-held cap is reached with `borrow_cap` or `loan_cap`, which need `VAULT_BORROW` with `FreezeAdminCap` in the request's borrow scope; no shipped proposal type has that scope, so a DAO whose cap sits in a vault needs its own type for it, as the test-local `ControllerOp` in `medium_enterprise_lifecycle` does.

**Why it matters:** The freeze is only as useful as the reachability of its cap, and only as safe as its custody.

```move
// From tribe_tests::create_tribe_freeze_caps_routed_correctly
scenario.next_tx(OFFICER_ADMIN);
{
    let cap = scenario.take_from_sender<FreezeAdminCap>();
    test_scenario::return_to_sender(&scenario, cap);
};
```

---

### The cap holder freezes a type directly

**Requirement:** `emergency::freeze_type<P>(&mut freeze, &cap, &clock)` aborts `emergency::EDAOMismatch` unless the cap is for the freeze's DAO and `emergency::EProtectedType` if `P` is exempt; it then sets `P`'s expiry to `clock.timestamp_ms() + max_freeze_duration_ms` (overwriting any earlier expiry) and emits `TypeFrozen { dao_id, type_name, expiry_ms }`. It does not check that `P` is enabled on the DAO. `unfreeze_type<P>(&mut freeze, &cap)` removes the entry (`emergency::ENotFrozen` if there is none) and emits `TypeUnfrozen`.

**Why it matters:** If a handler turns out to be exploitable, the admin can stop it at once, without waiting for a vote.

```move
// From armature_proposals::emergency_freeze_tests::unfreeze_allows_execution
scenario.next_tx(CREATOR);
{
    let mut freeze = scenario.take_shared<EmergencyFreeze>();
    let cap = scenario.take_from_sender<FreezeAdminCap>();
    clock.set_for_testing(3000);
    freeze.freeze_type<SetBoard>(&cap, &clock);
    assert!(freeze.is_frozen<SetBoard>(&clock));

    freeze.unfreeze_type<SetBoard>(&cap);
    assert!(!freeze.is_frozen<SetBoard>(&clock));
    scenario.return_to_sender(cap);
    test_scenario::return_shared(freeze);
};
```

---

### Freezes are keyed by Move type

**Requirement:** `frozen_types` and `freeze_exempt_types` are keyed by `type_name::with_defining_ids<P>()`. `Order<CredA>` and `Order<CredB>` are different keys. Events carry the canonical type string (`type_name`), as `dao::TypeSlotAdded` does.

**Why it matters:** A DAO with one payload type per market or asset (e.g. `PlaceLimitOrder<CRED>`) must be able to stop one of them without halting the rest.

```move
// From emergency_tests::test_freeze__generic_instantiations_are_independent
freeze.freeze_type<PlaceOrder<CredA>>(&cap, &clock);
assert!(freeze.is_frozen<PlaceOrder<CredA>>(&clock));
assert!(!freeze.is_frozen<PlaceOrder<CredB>>(&clock));
freeze.assert_not_frozen<PlaceOrder<CredB>>(&clock);
```

---

### A frozen type cannot execute on any path

**Requirement:** `emergency::assert_not_frozen<P>(&freeze, &clock)` (`emergency::EFrozen`) runs in `board_voting::ticket_from_vote(_readonly)`, `board_voting::submit_vote_execute(_readonly)`, `external_execution::ticket_from_cap(_readonly)` and, per step, `composite::advance_step<P>`. It does not run on submission (`submit_proposal`, `submit_composite`), on `vote`, on `delete_expired_proposal`, or on `controller::privileged_submit`, which takes no `EmergencyFreeze`. So a frozen type's proposals can still be submitted and voted; they wait until the freeze ends or their window closes. Each path checks the `EmergencyFreeze` object it is given; none compares it with the DAO's own (`dao.emergency_freeze_id()`), and no test covers a mismatched freeze object.

**Why it matters:** A freeze that one path ignored would not stop anything, since the same type can usually run on several paths.

```move
// From freeze_path_tests (Order<CredA> frozen in setup; single-member board)
fun run_two_ptb<T>(scenario: &mut Scenario, clock: &Clock) {
    scenario.next_tx(CREATOR);
    {
        let dao = scenario.take_shared<DAO>();
        board_voting::submit_proposal(&dao, option::none(), Order<T> {}, clock, scenario.ctx());
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<Order<T>>>();
        let dao = scenario.take_shared_by_id<DAO>(prop.dao_id());
        board_voting::vote(&mut prop, &dao, true, clock, scenario.ctx());   // voting is not blocked
        test_scenario::return_shared(dao);
        test_scenario::return_shared(prop);
    };
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let prop = scenario.take_shared<Proposal<Order<T>>>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, clock, scenario.ctx());
        ticket.discharge(internal::permit());
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };
}

#[test, expected_failure(abort_code = emergency::EFrozen)]
fun two_ptb__frozen_instantiation_aborts() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    setup(&mut scenario, &mut clock);
    run_two_ptb<CredA>(&mut scenario, &clock);
    clock.destroy_for_testing();
    scenario.end();
}
```

---

### Freezes expire on their own

**Requirement:** `is_frozen<P>` is true only while `now < expiry`. Expired entries are not removed; they stay in `frozen_types` (so `is_empty` stays false, which blocks `dao::destroy`) until `unfreeze_type` or `unfreeze_all` removes them. `max_freeze_duration_ms` starts at 7 days; `UpdateFreezeConfig` changes it for freezes made afterwards, leaving existing expiries alone. It has no bounds: at 0 every new freeze expires at once, and a value so large that `now + max_freeze_duration_ms` overflows makes `freeze_type` abort, since this sum does not saturate (proposal deadlines do).

**Why it matters:** An admin who is compromised or absent cannot hold a type frozen past the maximum without acting again.

```move
// From emergency_tests::test_auto_expiry__expired_freeze_treated_as_inactive
let now = 1_000_000;
clock.set_for_testing(now);
freeze.freeze_type<TreasuryWithdraw>(&cap, &clock);
assert!(freeze.is_frozen<TreasuryWithdraw>(&clock));

clock.set_for_testing(now + freeze.max_freeze_duration_ms() + 1);
assert!(!freeze.is_frozen<TreasuryWithdraw>(&clock));
freeze.assert_not_frozen<TreasuryWithdraw>(&clock);
```

---

### Governance can lift a freeze

**Requirement:** `UnfreezeProposalType { type_name }` (built with `unfreeze_proposal_type::new<T>()`) is a default slot (display key "UnfreezeProposalType", fixed `FREEZE`, 50% default threshold). It is exempt from freezing and cannot be disabled. `freeze_ops::execute_unfreeze_proposal_type(&mut freeze, ticket)` calls `emergency::governance_unfreeze_type`, which checks the request's DAO (`emergency::EDAOMismatch`) and `FREEZE`, and aborts `emergency::ENotFrozen` if the type has no entry.

**Why it matters:** The board can undo an admin freeze without the cap, and the admin cannot freeze that route.

```move
// From armature_proposals::emergency_freeze_tests::governance_unfreeze_via_proposal (SetBoard frozen)
board_voting::submit_proposal(&dao, option::some(string::utf8(b"Unfreeze SetBoard")), unfreeze_proposal_type::new<SetBoard>(), &clock, scenario.ctx());
// ... vote YES, then:
let ticket = board_voting::ticket_from_vote(&mut dao, proposal, &freeze, &clock, scenario.ctx());
freeze_ops::execute_unfreeze_proposal_type(&mut freeze, ticket);
assert!(!freeze.is_frozen<SetBoard>(&clock));
```

---

### Exempt types cannot be frozen

**Requirement:** `freeze_type` aborts `emergency::EProtectedType` for any type in `freeze_exempt_types`. The set starts as exactly `armature::transfer_freeze_admin::TransferFreezeAdmin` and `armature::unfreeze_proposal_type::UnfreezeProposalType`. These two are mandatory: `emergency::is_mandatory_exempt` matches them by Move type (a same-named type elsewhere gets no exemption), and `remove_freeze_exempt_type` refuses them (`emergency::EMandatoryExemptType`). `UpdateFreezeExemptTypes` (opt-in; payload built with `update_freeze_exempt_types::new()` then `add_type<T>()` / `remove_type<T>()`) adds and then removes the listed types through `add_freeze_exempt_type` / `remove_freeze_exempt_type` (`FREEZE`). Adding a type already in the set, or removing one not in it, aborts in `sui::vec_set`. Exempting a type only prevents new freezes; an existing freeze of it stays.

**Why it matters:** If the admin could freeze `UnfreezeProposalType` or `TransferFreezeAdmin`, the board would have no vote-driven way out of a freeze.

```move
// From emergency_tests
#[test, expected_failure(abort_code = emergency::EProtectedType)]
fun test_protected__unfreeze_proposal_type_cannot_be_frozen() {
    let (mut freeze, cap, clock) = setup();
    freeze.freeze_type<UnfreezeProposalType>(&cap, &clock);
    teardown(freeze, cap, clock);
}

#[test]
/// Protection follows the Move type, not a name: a lookalike type can be frozen.
fun test_protected__lookalike_type_is_not_exempt() {
    let (mut freeze, cap, clock) = setup();
    assert!(!emergency::is_mandatory_exempt(&type_name::with_defining_ids<TransferFreezeAdminLookalike>()));
    freeze.freeze_type<TransferFreezeAdminLookalike>(&cap, &clock);
    assert!(freeze.is_frozen<TransferFreezeAdminLookalike>(&clock));
    teardown(freeze, cap, clock);
}
```

---

### Governance changes need FREEZE

**Requirement:** `governance_unfreeze_type`, `update_freeze_duration`, `unfreeze_all`, `add_freeze_exempt_type` and `remove_freeze_exempt_type` each check the request's DAO (`emergency::EDAOMismatch`) and then `FREEZE` (`proposal::EPermissionDenied`). The four framework freeze types hold exactly `FREEZE`, a bit with no approval floor. The `freeze_ops` handlers for `UpdateFreezeConfig`, `UpdateFreezeExemptTypes` and `TransferFreezeAdmin` also check that the freeze passed is the ticket's DAO's (`freeze_ops::EFreezeDaoMismatch`). `execute_update_freeze_config` emits `freeze_ops::FreezeConfigUpdated { dao_id, new_max_freeze_duration_ms }`.

**Why it matters:** The exempt set decides what keeps running while everything else is stopped. A type that was never granted `FREEZE`, including the one being frozen, must not be able to edit it or lift a freeze.

```move
// From armature_external_type_tests::external_type_lifecycle_tests
// Rebalance<CredB> holds no bits; its request cannot lift the admin freeze on Rebalance<CredA>.
#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun bypass_ticket_cannot_unfreeze_other_type() {
    with_rebalance_request!(true, |_, freeze, _, req, _| {
        freeze.unfreeze_all(req);
    });
}
```

---

### TransferFreezeAdmin moves the cap and clears every freeze (planned)

**Requirement:** `TransferFreezeAdmin { new_admin }` is a default slot (fixed `FREEZE`, 50% default threshold), exempt and undisableable. `freeze_ops::execute_transfer_freeze_admin(&mut freeze, cap: FreezeAdminCap, ticket)` checks the freeze against the ticket's DAO (`freeze_ops::EFreezeDaoMismatch`) and the cap against the freeze's DAO (`freeze_ops::ECapDaoMismatch`), removes every entry with `unfreeze_all` (a `TypeUnfrozen` each), emits `FreezeAdminTransferred { dao_id, new_admin }` and transfers the cap to `new_admin`. The handler takes the cap by value, so the executing transaction must supply it: with a wallet-held cap on the vote path, the sender must be both a current member and the cap's owner.

**Why it matters:** A handover recorded by the DAO leaves the new admin with no freezes they did not set. No test executes this type yet.

```move
#[test]
fun test_transfer_freeze_admin__moves_cap_and_unfreezes_all() {
    // ... board [CREATOR, MEMBER_B]; CREATOR (the cap holder) freezes SetBoard,
    //     then submits transfer_freeze_admin::new(MEMBER_B) and votes it through
    scenario.next_tx(CREATOR);
    {
        let mut dao = scenario.take_shared<DAO>();
        let prop = scenario.take_shared<Proposal<TransferFreezeAdmin>>();
        let mut freeze = scenario.take_shared<EmergencyFreeze>();
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        let ticket = board_voting::ticket_from_vote(&mut dao, prop, &freeze, &clock, scenario.ctx());
        freeze_ops::execute_transfer_freeze_admin(&mut freeze, cap, ticket);
        assert!(freeze.is_empty());
        test_scenario::return_shared(freeze);
        test_scenario::return_shared(dao);
    };
    scenario.next_tx(MEMBER_B);
    {
        let cap = scenario.take_from_sender<FreezeAdminCap>();
        scenario.return_to_sender(cap);
    };
    // ...
}
```

---

### A freeze can outlast an execution window

**Requirement:** A freeze does not pause a proposal's clock. With the default 7-day `expiry_ms` and 7-day freeze, freezing a type just after one of its proposals passes can close that proposal's execution window before the freeze lifts; the proposal then aborts `proposal::EExecutionWindowClosed` and can only be deleted and re-proposed. This is accepted behaviour.

**Why it matters:** The admin's freeze can, in effect, cancel a pending decision; the board's recourse is `UnfreezeProposalType` before the window closes.

```move
// From armature_proposals::emergency_freeze_tests: SetBoard passed at t=2000, frozen at t=3000,
// window closes at 604_802_000, freeze lifts at 604_803_000.
#[test, expected_failure(abort_code = proposal::EExecutionWindowClosed)]
fun freeze_outlasting_window_blocks_execution() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    pass_then_freeze(&mut scenario, &mut clock);   // clock left at 3000 + 604_800_000 + 1
    // ... ticket_from_vote(&mut dao, proposal, &freeze, &clock, ctx) aborts
}
```
