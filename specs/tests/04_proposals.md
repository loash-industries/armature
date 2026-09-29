# Proposal Lifecycle Tests

## Summary

`proposal.move`, driven through the vote-path entry points in `board_voting.move`, manages proposals. `board_voting::submit_proposal` shares a `Proposal<P>` that records the roster version and a copy of `P`'s slot config; members at that version vote with `board_voting::vote`; `Active → Passed` is the only stored transition. `board_voting::ticket_from_vote` takes the passed proposal by value, deletes it and returns an `ExecutionTicket<P>`; `proposal::delete_expired_proposal` lets anyone delete a proposal that can no longer run. "Executed" and "Expired" are not statuses: the `ProposalExecuted` and `ProposalExpired` events record them.

These tests verify the hot potatoes (`ExecutionRequest<P>`, `ExecutionTicket<P>`) and the permit that binds a ticket to `P`'s module, status and deletion rules, voting eligibility by roster version, executor eligibility, and the delay, window and cooldown rules. Pass math is in `09_board_voting.md`; the atomic, bypass and controller paths are in `09_board_voting.md` and `15_privileged_submit.md`.

## Test Matrix

**Hot potatoes and tickets**

| Test | Expected | Where |
|------|----------|-------|
| `test_execution_request_no_drop` | `ExecutionRequest` has no abilities, so only framework code destroys one (`proposal::consume`, `discharge`, `controller::privileged_consume`) | `proposal_tests` (structural) |
| `consume_execution_request_destroys_hot_potato`, `consume_execution_request_works_after_governance_execution` | The test-only consumer destroys a request | `proposal_tests` |
| `test_ticket_is_standalone_true` | A Standalone ticket exposes its OU and vote weights | `proposal_tests` |
| `test_ticket_yes_weight_aborts_on_composite` | `proposal::ENotStandaloneTicket` | `proposal_tests` |
| `test_ticket_total_snapshot_weight_aborts_on_external` | `proposal::ENotStandaloneTicket` | `proposal_tests` |
| `test_ticket_is_standalone_false_for_composite`, `test_ticket_is_standalone_false_for_external` | Composite and External tickets are not Standalone | `proposal_tests` |
| `test_discharge_returning_payload` | Returns the payload of a type without `drop` | `proposal_tests` |
| only `P`'s module spends or closes a ticket | `ticket_request`, `discharge`, `discharge_returning_payload` take `Permit<P>`; CI fails if they stop | structural (`scripts/check_request_gates.py`) |
| `bypass_ticket_cannot_withdraw_from_treasury`, `bypass_ticket_cannot_unfreeze_other_type`, `bypass_ticket_cannot_add_board_member`, `atomic_ticket_cannot_migrate_ou`, `atomic_ticket_cannot_unfreeze_other_type` | Even `P`'s own module is held to `P`'s bits: `proposal::EPermissionDenied` | `armature_external_type_tests::external_type_lifecycle_tests` |
| `vote_path_request_carries_current_slot_bits` | A request carries the slot's bits when minted; a revocation applies from the next request (atomic path) | `permissions_tests` |
| `request_carries_slot_scope_and_borrows_in_scope` | A request carries the slot's borrow scope | `borrow_scope_tests` |
| `test_two_ptb_request_uses_slot_bits_at_execution` | Bits revoked after the vote: the executed request carries the new bits (`req_permissions() == 0`) | planned |

**Status and deletion**

| Test | Expected | Where |
|------|----------|-------|
| `test_status_active_to_passed` | The vote that meets quorum and threshold moves the proposal to `Passed` | `proposal_tests` |
| `test_execute_deletes_proposal` | Execution returns the payload and a request and deletes the proposal | `proposal_tests` |
| `test_delete_expired_active` | Anyone deletes an Active proposal at `created_at + expiry_ms` | `proposal_tests` |
| `test_delete_expired_active_too_early_aborts` | One millisecond earlier: `proposal::ENotExpired` | `proposal_tests` |
| `test_delete_expired_passed_after_window` | A Passed proposal is deleted at `passed_at + execution_delay_ms + expiry_ms` | `proposal_tests` |
| `test_delete_expired_passed_inside_window_aborts` | Past `created_at + expiry_ms` but inside the window: `proposal::ENotExpired` | `proposal_tests` |
| `test_delete_with_max_expiry_not_expired` | A saturated deadline never passes: `proposal::ENotExpired`, not an overflow | `proposal_tests` |
| `freeze_outlasting_window_allows_delete` | A Passed proposal whose window closed during a freeze is deleted by a member | `armature_proposals::emergency_freeze_tests` |
| `test_delete_emits_proposal_expired` | `ProposalExpired { proposal_id, ou_id }` | planned |
| `test_execute_emits_proposal_executed` | Two-PTB path emits `ProposalExecuted { proposal_id, ou_id, executor }` | planned |

**Voting**

| Test | Expected | Where |
|------|----------|-------|
| `test_cannot_vote_on_passed_aborts` | `proposal::ENotActive` | `proposal_tests` |
| `test_vote_after_expiry_aborts` | At `created_at + expiry_ms`: `proposal::EVotingClosed` | `proposal_tests` |
| `test_vote_just_before_expiry` | One millisecond earlier the vote counts and passes the proposal | `proposal_tests` |
| `test_vote_double_vote_aborts` | `proposal::EAlreadyVoted` | `proposal_tests` |
| `test_vote_no_vote_counted_correctly` | NO adds to `no_weight`; the proposal stays Active | `proposal_tests` |
| `test_vote_with_other_ou_aborts` | An OU other than the proposal's: `board_voting::EOUIdMismatch` | `proposal_tests` |
| `test_vote_non_snapshot_member_aborts` | A non-member: `proposal::ENotInSnapshot` | `proposal_tests` |
| `test_new_member_cannot_vote_on_old_proposal` | A member added after creation: `proposal::ENotInSnapshot` | `proposal_tests` |
| `test_member_readded_after_creation_cannot_vote` | Removed before creation, re-added after: `proposal::ENotInSnapshot` | `proposal_tests` |
| `test_vote_snapshot_immutable_after_creation` | A member removed by a board change after creation still votes | `proposal_tests` |
| `test_removed_member_keeps_vote_on_old_proposal` | Same, and the vote passes the proposal | `proposal_tests` |
| `test_readded_member_keeps_vote_on_old_proposal` | Removed and re-added after creation: still votes | `proposal_tests` |
| `test_quorum_uses_total_weight_at_creation` | Quorum is measured against the board at creation (2), not the current one (5) | `proposal_tests` |
| `test_roster_version_and_snapshot_version` | `snapshot_version` is the roster version at creation | `proposal_tests` |

**Execution**

| Test | Expected | Where |
|------|----------|-------|
| `test_board_member_can_execute` | Any current member may execute, not only a voter | `proposal_tests` |
| `test_non_board_member_cannot_execute_aborts` | `proposal::ENotEligible` | `proposal_tests` |
| `test_removed_member_cannot_execute` | A member removed after voting: `proposal::ENotEligible` | `proposal_tests` |
| `test_execute_active_proposal_aborts` | `ticket_from_vote` on an Active proposal: `proposal::ENotPassed` | planned |
| `test_execute_delay_not_elapsed_aborts` | `proposal::EDelayNotElapsed` | `proposal_tests` |
| `test_execute_delay_elapsed_succeeds` | Executable once the delay has elapsed | `proposal_tests` |
| `test_execute_window_starts_after_delay` | Still executable at `passed_at + delay + expiry - 1` | `proposal_tests` |
| `test_execute_after_window_aborts` | `proposal::EExecutionWindowClosed` | `proposal_tests` |
| `freeze_outlasting_window_blocks_execution` | Window closed while frozen: `proposal::EExecutionWindowClosed` after the freeze lifts | `armature_proposals::emergency_freeze_tests` |
| `test_execute_with_max_expiry_does_not_overflow` | `expiry_ms = u64::MAX`: the deadline saturates and the proposal executes | `proposal_tests` |
| `test_execute_cooldown_active_aborts` | Type executed within `cooldown_ms`: `proposal::ECooldownActive` | `proposal_tests` |
| `test_execute_cooldown_elapsed_succeeds` | Executable once the cooldown has passed | `proposal_tests` |
| `test_execute_paused_aborts` | `proposal::EExecutionPaused` | `proposal_tests` |
| `test_ticket_from_vote_execution_paused_aborts` | After `ou::set_execution_paused(true, &req)` (`PAUSE`), `ticket_from_vote` aborts `proposal::EExecutionPaused` | planned |
| `ticket_from_vote__records_execution` | The `&mut OU` variant records `last_executed_ms` | `board_voting_tests` |
| `ticket_from_vote_readonly__executes_without_recording` | The read-only variant executes and writes nothing to the OU | `board_voting_tests` |
| `ticket_from_vote_readonly__slot_cooldown_aborts`, `ticket_from_vote_readonly__slot_only_cooldown_aborts`, `ticket_from_vote_readonly__snapshot_cooldown_aborts` | A cooldown on the slot or on the proposal's snapshot: `board_voting::ECooldownRequiresMutableOU` | `board_voting_tests` |
| `authorize_execution_blocks_when_controller_paused` | `board_voting::EControllerPaused` | `controller_tests` |
| `two_ptb__frozen_instantiation_aborts` | `emergency::EFrozen` | `freeze_path_tests` |
| `test_ticket_from_vote_type_disabled_aborts` | Type disabled after the vote: `board_voting::ETypeNotEnabled` | planned |
| `test_ticket_from_vote_wrong_ou_aborts` | Another OU passed: `board_voting::EOUIdMismatch` | planned |
| `test_passed_proposal_retryable_after_failure` | A Passed proposal executes; the abort-then-retry sequence itself is structural | `proposal_tests` |

**Executions without a `Proposal` object**

| Test | Expected | Where |
|------|----------|-------|
| `test_sve__creates_no_objects_and_emits_lifecycle_events` | Atomic path: no object; `ProposalCreated`, `ProposalPayloadCreated`, `VoteCast`, `ProposalPassed`, `ProposalExecuted` under a fresh ID | `submit_vote_execute_tests` |
| `privileged_submit_records_execution_in_events` | Controller path: `ProposalCreated`, `ProposalPayloadCreated`, `ProposalExecuted`; no object | `controller_tests` |
| `ticket_from_cap_creates_no_objects` | Bypass path: no object | `external_execution_tests` |

## Tests

---

### ExecutionRequest and ExecutionTicket are hot potatoes

**Requirement:** `ExecutionRequest<phantom P> { ou_id, proposal_id, permissions, borrow_scope, privileged }` and `ExecutionTicket<P> { request, payload, closeout }` have no abilities. Only `public(package)` framework functions mint them; the mint paths go through `proposal::execute` (two-PTB, via `ticket_from_vote`), `execute_single_vote` (atomic), `privileged_execute` (bypass and controller) and `new_ticket_composite` (composite steps). A ticket leaves the PTB only through `discharge` or `discharge_returning_payload`; a bare request only through `proposal::consume` (`public(package)`) or `controller::privileged_consume`. `ticket_yes_weight` and `ticket_total_snapshot_weight` work only on Standalone (vote-path) tickets. `discharge` also checks a Standalone ticket's request against its proposal ID (`proposal::ERequestMismatch`), a defensive check the framework's constructors never trip.

**Why it matters:** Governance approves an action, and the hot potato makes the approval usable only inside the transaction that executes it. With `drop` the handler could be skipped; with `store` the authority could be kept and replayed later.

```move
#[test, expected_failure(abort_code = armature::proposal::ENotStandaloneTicket)]
fun test_ticket_yes_weight_aborts_on_composite() {
    let ticket = proposal::new_composite_ticket_for_testing<TestPayload>(
        object::id_from_address(@0xDA0),
        object::id_from_address(@0xBEEF),
        TestPayload { value: 1 },
    );
    let _w = ticket.ticket_yes_weight();   // Composite ticket: aborts
    ticket.discharge(internal::permit());
}
```

The vault's `CapLoan` hot potato is covered in `06_capability_vault.md`.

---

### Only P's module can spend or close a ticket

**Requirement:** `ticket_payload(&ticket)` is public. `ticket_request(&ticket, Permit<P>)`, `discharge(ticket, Permit<P>)` and `discharge_returning_payload(ticket, Permit<P>)` take `std::internal::Permit<P>`, which only the module defining `P` can mint; a package may pass it to its own handler module through a `public(package) fun permit()` in the type module. So only `P`'s handler spends the request, and it spends it with arguments read from the approved payload. That other modules cannot mint the permit is a compile-time fact with no runtime test; `scripts/check_request_gates.py` fails CI if any of these functions, or `external_execution::ticket_from_cap(_readonly)`, stops taking it. Inside `P`'s module the request is still bounded by `P`'s bits.

**Why it matters:** Without the permit, whoever held a ticket could pass its request to any mutator its bits allow, with arguments of their own choosing instead of the approved payload's.

```move
// armature_external_type_tests::rebalance: a third-party handler
public fun execute_rebalance<T>(ou: &OU, ticket: ExecutionTicket<Rebalance<T>>) {
    assert!(ou.id() == ticket.ticket_ou_id(), EOuMismatch);
    event::emit(Rebalanced { ou_id: ou.id(), amount: ticket.ticket_payload().amount });
    ticket.discharge(internal::permit());   // compiles only in the module defining Rebalance
}

// external_type_lifecycle_tests: Rebalance holds no bits, so its request reaches no mutator
#[test, expected_failure(abort_code = proposal::EPermissionDenied)]
fun bypass_ticket_cannot_withdraw_from_treasury() {
    with_rebalance_request!(true, |_, _, treasury, req, ctx| {
        let coin = treasury.withdraw<SUI, Rebalance<CredB>>(1, req, ctx);
        abort 0
    });
}
```

---

### Requests carry the slot's bits at mint time

**Requirement:** Every mint path copies `permissions` and `borrow_scope` from `P`'s slot when the request is minted. On the two-PTB path that is execution, not submission, so a grant or revocation applies to every request minted after it, including one for a proposal that passed earlier. The voting and timing rules (quorum, threshold, delay, window, cooldown length) come from the config copied onto the proposal at creation; the last-executed time comes from the slot.

**Why it matters:** Revoking a power must take effect immediately, not after every pending proposal of that type has run.

```move
// From permissions_tests::vote_path_request_carries_current_slot_bits (atomic path)
let t1 = board_voting::submit_vote_execute(&mut ou, option::none(), Granted {}, &freeze, &clock, scenario.ctx());
assert!(t1.ticket_request(internal::permit()).req_permissions() == permissions::board_add() | permissions::pause());
t1.discharge(internal::permit());

ou.test_update_config<Granted>(base_config());   // revoke both bits
let t2 = board_voting::submit_vote_execute(&mut ou, option::none(), Granted {}, &freeze, &clock, scenario.ctx());
assert!(t2.ticket_request(internal::permit()).req_permissions() == 0);
t2.discharge(internal::permit());
```

`test_two_ptb_request_uses_slot_bits_at_execution` (planned) repeats this with the revocation between `vote` and `ticket_from_vote`.

---

### Status Active to Passed

**Requirement:** `board_voting::vote(&mut prop, &ou, approve, &clock, ctx)` records the vote and emits `VoteCast`. When `ProposalConfig::passes(yes, no, total_snapshot_weight)` holds, the status becomes `Passed`, `passed_at_ms` is set and `ProposalPassed` is emitted. `Active → Passed` is the only stored transition; a Passed proposal takes no more votes (`proposal::ENotActive`).

**Why it matters:** `Passed` is what execution checks. A late vote must not rewrite a decided record.

```move
// From proposal_tests::test_status_active_to_passed (board of 2, quorum 50%, threshold 50%)
scenario.next_tx(CREATOR);
{
    let mut prop = scenario.take_shared<Proposal<TestPayload>>();
    let vote_ou = scenario.take_shared_by_id<OU>(prop.ou_id());
    board_voting::vote(&mut prop, &vote_ou, true, &clock, scenario.ctx());
    test_scenario::return_shared(vote_ou);
    // quorum: 1 * 10000 >= 5000 * 2; threshold: 1 * 10000 >= 5000 * 1
    assert!(prop.status().is_passed());
    test_scenario::return_shared(prop);
};
```

---

### Execution deletes the proposal

**Requirement:** `board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, ctx)` takes the proposal by value. After its checks (below), `proposal::execute` deletes the object, emits `ProposalExecuted { proposal_id, ou_id, executor }` and returns the payload and request, which `ticket_from_vote` wraps in a Standalone ticket carrying the proposal's vote weights. The storage rebate goes to the executing transaction's gas payer (the gas station on sponsored flows). `ticket_from_vote` records the execution time on the slot for cooldowns; `ticket_from_vote_readonly(&ou, …)` records nothing and requires `cooldown_ms == 0` on both the slot and the proposal's copy (`board_voting::ECooldownRequiresMutableOU`).

**Why it matters:** Deleting the object is the replay protection: once executed, nothing can execute it again, and no audit object locks a storage deposit.

```move
// Two-PTB version of proposal_tests::test_execute_deletes_proposal
// (TestPayload enabled with test_enable_type; the proposal submitted and passed)
scenario.next_tx(CREATOR);
let prop_id;
{
    let mut ou = scenario.take_shared<OU>();
    let prop = scenario.take_shared<Proposal<TestPayload>>();
    prop_id = object::id(&prop);
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, scenario.ctx());
    assert!(ticket.ticket_proposal_id() == prop_id);
    ticket.discharge(internal::permit());
    test_scenario::return_shared(freeze);
    test_scenario::return_shared(ou);
};
let effects = scenario.next_tx(CREATOR);
assert!(effects.deleted().contains(&prop_id));
assert!(!test_scenario::has_most_recent_shared<Proposal<TestPayload>>());
```

(`proposal_tests::test_execute_deletes_proposal` calls the package-internal `proposal::execute` directly, as `prop.execute(...)`, and checks the same effects.)

---

### Expired proposals are deleted by anyone

**Requirement:** `proposal::delete_expired_proposal<P: store + drop>(proposal, &clock)` has no sender check. It deletes an Active proposal once `now >= created_at + expiry_ms`, and a Passed one once `now >= passed_at + execution_delay_ms + expiry_ms`; before that it aborts `proposal::ENotExpired`. It emits `ProposalExpired { proposal_id, ou_id }`; the rebate goes to the caller's gas payer. `P` must have `drop` because the payload is destroyed, which every shipped payload type has. There is no upper bound on `expiry_ms` or `execution_delay_ms`; the deadlines saturate at `u64::MAX`, so a proposal whose sum overflows never expires and can leave the chain only by executing.

**Why it matters:** Proposals that failed or were never executed must not linger as shared objects, and cleanup cannot depend on the board.

```move
// From proposal_tests::test_delete_expired_active (created at 1_000_000, expiry 1 hour)
clock.set_for_testing(1_000_000 + 3_600_000);
scenario.next_tx(NON_MEMBER);
let prop_id;
{
    let prop = scenario.take_shared<Proposal<TestPayload>>();
    prop_id = object::id(&prop);
    proposal::delete_expired_proposal(prop, &clock);
};
let effects = scenario.next_tx(CREATOR);
assert!(effects.deleted() == vector[prop_id]);
```

---

### Voting closes when the voting period ends

**Requirement:** `vote` aborts `proposal::EVotingClosed` once `now >= created_at + expiry_ms`: the same instant `delete_expired_proposal` opens for an Active proposal.

**Why it matters:** Without the check, a late vote could pass an expired proposal and open a fresh execution window from the new `passed_at`.

```move
#[test, expected_failure(abort_code = proposal::EVotingClosed)]
fun test_vote_after_expiry_aborts() {
    // ... proposal created at 1_000_000 with expiry 1 hour
    clock.set_for_testing(1_000_000 + 3_600_000);
    scenario.next_tx(CREATOR);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let vote_ou = scenario.take_shared_by_id<OU>(prop.ou_id());
        board_voting::vote(&mut prop, &vote_ou, true, &clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(prop);
    };
    // ...
}
```

---

### Eligibility is fixed by roster version

**Requirement:** A proposal stores `snapshot_version` (the roster version at creation) and `total_snapshot_weight` (the member count at creation) instead of copying the roster. `vote` aborts `board_voting::EOUIdMismatch` unless the OU passed is the proposal's, `proposal::ENotInSnapshot` unless the voter was a member at `snapshot_version` (`governance::was_member_at`), and `proposal::EAlreadyVoted` on a second vote. Members added after creation cannot vote; members removed after creation still can; an address removed before creation and re-added after cannot. Quorum is measured against `total_snapshot_weight`.

**Why it matters:** Changing the board must not change who decides a proposal already in flight, in either direction.

```move
// From proposal_tests::test_removed_member_keeps_vote_on_old_proposal
scenario.next_tx(CREATOR);
{
    let mut ou = scenario.take_shared<OU>();
    ou.governance_mut().remove_board_member(MEMBER_B);   // after the proposal was created
    test_scenario::return_shared(ou);
};

scenario.next_tx(MEMBER_B);
{
    let mut prop = scenario.take_shared<Proposal<TestPayload>>();
    let ou = scenario.take_shared<OU>();
    assert!(!ou.governance().is_board_member(MEMBER_B));
    board_voting::vote(&mut prop, &ou, true, &clock, scenario.ctx());
    assert!(prop.status().is_passed());
    test_scenario::return_shared(ou);
    test_scenario::return_shared(prop);
};
```

---

### The executor must be a current member

**Requirement:** `proposal::execute` aborts `proposal::ENotEligible` unless the transaction sender is a current board member. The executor need not have voted. A member removed after the vote cannot execute. (The bypass and controller paths have no membership check; their caps are the authority.)

**Why it matters:** Restricting execution to members keeps outsiders from choosing when an approved action runs.

```move
#[test, expected_failure(abort_code = proposal::ENotEligible)]
fun test_non_board_member_cannot_execute_aborts() {
    // ... TestPayload enabled; CREATOR submits and votes it through
    scenario.next_tx(NON_MEMBER);
    let mut ou = scenario.take_shared<OU>();
    let prop = scenario.take_shared<Proposal<TestPayload>>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let _ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, scenario.ctx());
    abort 0
}
```

(`proposal_tests` drives the same check through the package-internal `proposal::execute` directly.)

---

### Delay, window and cooldown

**Requirement:** A Passed proposal is executable from `passed_at + execution_delay_ms` (`proposal::EDelayNotElapsed` before) until `passed_at + execution_delay_ms + expiry_ms` (`proposal::EExecutionWindowClosed` from then on). If `cooldown_ms > 0` and the type has executed before, execution also needs `now >= last_executed + cooldown_ms` (`proposal::ECooldownActive`). Every sum saturates at `u64::MAX`. When the OU's execution is paused (`ou::set_execution_paused`, `PAUSE` bit) execution aborts `proposal::EExecutionPaused`.

**Why it matters:** The delay gives members time to react to a decision (including freezing the type); the window stops a stale approval from running months later; the cooldown rate-limits a type.

```move
// From proposal_tests::test_execute_window_starts_after_delay
let config = proposal::new_config(5_000, 5_000, 0, 3_600_000, 3_600_000, 0);   // expiry 1 h, delay 1 h
// ... created and passed at 1_000_000
clock.set_for_testing(1_000_000 + 3_600_000 + 3_600_000 - 1);   // last millisecond of the window
// execute succeeds; at + 1 it aborts EExecutionWindowClosed (test_execute_after_window_aborts)
```

A freeze that outlasts the window cancels the proposal: `armature_proposals::emergency_freeze_tests::freeze_outlasting_window_blocks_execution` (accepted behaviour, see `08_emergency.md`).

---

### What ticket_from_vote checks

**Requirement:** `ticket_from_vote(_readonly)` checks, in order:

| Check | Abort | Covered by |
|---|---|---|
| OU `Active`, or `Migrating` and `P` is `TransferAssets` | `board_voting::EOUNotActive` | planned (`02_ou_lifecycle.md`) |
| Proposal belongs to the OU | `board_voting::EOUIdMismatch` | planned |
| `P` still has a slot | `board_voting::ETypeNotEnabled` | planned |
| OU not paused by its controller | `board_voting::EControllerPaused` | `controller_tests::authorize_execution_blocks_when_controller_paused` |
| Read-only variant: no cooldown on slot or snapshot | `board_voting::ECooldownRequiresMutableOU` | `board_voting_tests` (three tests) |
| `P` not frozen in the `EmergencyFreeze` passed | `emergency::EFrozen` | `freeze_path_tests::two_ptb__frozen_instantiation_aborts` |
| Execution not paused | `proposal::EExecutionPaused` | `proposal_tests::test_execute_paused_aborts` |
| Proposal `Passed` | `proposal::ENotPassed` | planned |
| Sender is a current member | `proposal::ENotEligible` | `proposal_tests` (two tests) |
| Delay elapsed | `proposal::EDelayNotElapsed` | `proposal_tests::test_execute_delay_not_elapsed_aborts` |
| Window open | `proposal::EExecutionWindowClosed` | `proposal_tests::test_execute_after_window_aborts` |
| Cooldown elapsed | `proposal::ECooldownActive` | `proposal_tests::test_execute_cooldown_active_aborts` |

**Why it matters:** Each check is a reason a passed decision may no longer run: the OU moved on, the type was withdrawn or frozen, or the timing rules say not yet or not any more.

```move
#[test, expected_failure(abort_code = board_voting::ETypeNotEnabled)]
fun test_ticket_from_vote_type_disabled_aborts() {   // planned
    // ... TestPayload enabled; submitted and voted through
    scenario.next_tx(CREATOR);
    let mut ou = scenario.take_shared<OU>();
    ou.test_disable_type<TestPayload>();
    let prop = scenario.take_shared<Proposal<TestPayload>>();
    let freeze = scenario.take_shared<EmergencyFreeze>();
    let _ticket = board_voting::ticket_from_vote(&mut ou, prop, &freeze, &clock, scenario.ctx());
    abort 0
}
```

---

### A failed execution leaves the proposal Passed

**Requirement:** If the handler, or any later command in the PTB, aborts, the whole transaction reverts, including the proposal's deletion. The proposal stays `Passed` and can be executed again while its window is open.

**Why it matters:** A transient failure (an underfunded treasury, a freeze that is later lifted) must not void a governance decision.

A unit test ends at its first abort, so "abort, then retry" cannot be written as one test; the property follows from PTB atomicity. `proposal_tests::test_passed_proposal_retryable_after_failure` checks only that a Passed proposal executes. `freeze_path_tests::two_ptb__executes_after_unfreeze` and `armature_proposals::emergency_freeze_tests::unfreeze_allows_execution` show a proposal of a frozen type executing once the freeze is lifted.

---

### Executions without a Proposal object

**Requirement:** The single-PTB paths (`board_voting::submit_vote_execute(_readonly)`, `external_execution::ticket_from_cap(_readonly)`, `controller::privileged_submit`) create no `Proposal`. They mint a proposal ID from `ctx.fresh_object_address()` and emit the events a shared proposal would: `ProposalCreated`, `ProposalPayloadCreated`, then `VoteCast` and `ProposalPassed` (atomic path only), then `ProposalExecuted`. The events are the audit record.

**Why it matters:** Nobody else votes on these executions, so a shared object would only lock a storage deposit nobody reclaims.

```move
// From submit_vote_execute_tests::test_sve__creates_no_objects_and_emits_lifecycle_events
sve_and_check_events(&mut scenario, &clock, false);   // asserts one of each event under the ticket's ID
let effects = scenario.next_tx(CREATOR);
assert!(effects.created().is_empty());
assert!(effects.num_user_events() == 5);
```

The atomic path's own rules (`execution_delay_ms == 0`, the proposer's single vote must pass) are in `09_board_voting.md`; the controller path is in `15_privileged_submit.md`.
