# Board Voting Tests

## Summary

`armature::board_voting` is the board-facing entry point of the vote path. It submits proposals (`submit_proposal`), records votes (`vote`), turns a passed proposal into an execution ticket (`ticket_from_vote`, `ticket_from_vote_readonly`) and runs the atomic single-vote path (`submit_vote_execute`, `submit_vote_execute_readonly`). Board is the only governance model: one member, one vote (`governance::member_vote_weight()` = 1).

The pass rule is `ProposalConfig::passes` (package-internal in `proposal`), evaluated after every vote:

- `total_voted > 0`, where `total_voted = yes + no`
- quorum: `total_voted * 10000 >= quorum * total_snapshot_weight`, where `total_snapshot_weight` is the board's `member_count` when the proposal was created
- threshold: `yes * 10000 >= approval_threshold * total_voted`

Both comparisons cross-multiply in u128 (`utils::gte_bps`), so there is no division and no rounding. The first vote that satisfies the rule sets the proposal to `Passed`; after that `vote` aborts with `proposal::ENotActive`. Non-voters count toward neither `yes` nor `no`. Approval floors (80% for `EnableProposalType`, `UpdateProposalConfig`, `EnableBypassType` and any config holding a high-impact bit) bound `approval_threshold`, which is measured against votes cast; participation is governed by `quorum` alone.

These tests cover quorum and threshold arithmetic, the propose threshold, type-slot submission, read-only execution and the atomic single-vote path. Real suites: `packages/armature_framework/tests/board_voting_tests.move` (22 tests) and `packages/armature_framework/tests/submit_vote_execute_tests.move` (26 tests). The proposal lifecycle rules this module relies on (snapshot eligibility, voting deadline, execution window, delay, cooldown, deletion) are tested in `proposal_tests.move` and specified in `04_proposals.md`.

## Test Matrix

### Vote counting and propose threshold (`board_voting_tests.move`)

| Test | Config (quorum / threshold, bps) | Expected |
|------|------|----------|
| `test_board__single_member_yes_passes` | 5000 / 5000, 1 member | 1 YES → Passed |
| `test_board__unanimous_3_member_passes` | 10000 / 5000 | 3 YES → Passed; yes = 3, no = 0 |
| `test_board__2_of_3_yes_passes_at_66` | 6600 / 6600 | Active after 1 YES (10000 < 19800); Passed after 2 YES |
| `test_board__1_of_3_yes_fails_at_66` | 6600 / 5000 | 1 YES → still Active (quorum not met) |
| `test_board__exact_quorum_boundary` | 6666 / 5000 | 2 of 3 vote: 20000 ≥ 19998 → Passed |
| `test_board__below_quorum_does_not_pass` | 6667 / 5000 | 2 of 3 vote: 20000 < 20001 → Active |
| `test_board__threshold_boundary_50_percent` | 5000 / 5000, 3 members | 1 YES + 1 NO: 10000 ≥ 10000 → Passed |
| `test_board__no_votes_majority_fails` | 10000 / 5000 | 1 YES + 2 NO → Active (3333 bps < 5000) |
| `test_board__abstention_not_counted_in_threshold` | 1 / 5000 | 1 YES of 3 members → Passed |
| `test_board__large_board_10_members` | 7000 / 6600 | 10 members; Passed at the 7th YES |
| `test_propose_threshold__zero_never_blocks` | propose_threshold 0 | Submission succeeds |
| `test_propose_threshold__at_board_weight_passes` | propose_threshold 1 | Submission succeeds (member weight is 1) |
| `test_propose_threshold__above_board_weight_aborts` | propose_threshold 2 | Abort `board_voting::EProposeThresholdNotMet` |

### Submission and two-PTB execution (`board_voting_tests.move`)

| Test | Expected |
|------|----------|
| `submit_proposal_succeeds_with_enabled_type` | `Proposal<P>` shared; `type_key()` is the slot's display key ("CustomKey") |
| `submit_proposal_aborts_for_type_without_slot` | Abort `board_voting::ETypeNotEnabled`: another type's slot does not enable `P` |
| `submit_proposal_default_type_uses_its_payload_slot` | A `SetBoard` payload submits against the default "SetBoard" slot |
| `ticket_from_vote__records_execution` | Ticket minted, proposal deleted, `last_executed_ms<P>()` = clock |
| `ticket_from_vote__type_disabled_after_pass_aborts` | Type disabled after its proposal passed → Abort `board_voting::ETypeNotEnabled` |
| `ticket_from_vote_readonly__executes_without_recording` | Ticket minted from `&OU`; `last_executed_ms<P>()` stays `none` |
| `ticket_from_vote_readonly__slot_cooldown_aborts` | Slot cooldown > 0 → Abort `board_voting::ECooldownRequiresMutableOU` |
| `ticket_from_vote_readonly__slot_only_cooldown_aborts` | Cooldown raised on the slot after submission → same abort |
| `ticket_from_vote_readonly__snapshot_cooldown_aborts` | Cooldown in the proposal's snapshot, cleared on the slot since → same abort |

### Atomic single-vote path (`submit_vote_execute_tests.move`)

| Test | Expected |
|------|----------|
| `test_sve__single_member_returns_ticket` | Standalone ticket; yes = 1, total = 1 |
| `test_sve__two_member_50_quorum_single_vote_passes` | quorum 5000, 2 members: 10000 ≥ 10000 → ticket; total = 2 |
| `test_sve__metadata_some_accepted` | `metadata_ipfs = some(..)` accepted |
| `test_sve__cooldown_zero_allows_back_to_back` | Two calls at the same timestamp succeed |
| `test_sve__cooldown_active_aborts_second_call` | 60 s cooldown, second call 1 s later → Abort `proposal::ECooldownActive` |
| `test_sve__cooldown_elapsed_allows_second_call` | Second call 61 s later succeeds |
| `test_sve__mutable_variant_records_execution` | `last_executed_ms<P>()` = clock |
| `test_sve__quorum_not_met_aborts` | quorum 6000, 3 members → Abort `board_voting::EInsufficientVotingWeight` |
| `test_sve__quorum_boundary_just_below_aborts` | quorum 3400, 3 members: 10000 < 10200 → Abort `board_voting::EInsufficientVotingWeight` |
| `test_sve__nonzero_delay_aborts` | delay 1000 ms → Abort `board_voting::EDelayForbidsAtomicExecution` |
| `test_sve__non_member_aborts` | Abort `governance::ENotBoardMember` |
| `test_sve__disabled_type_aborts` | Abort `board_voting::ETypeNotEnabled` |
| `test_sve__frozen_type_aborts` | Abort `emergency::EFrozen` |
| `test_sve__execution_paused_aborts` | Abort `proposal::EExecutionPaused` |
| `test_sve__controller_paused_aborts` | Abort `board_voting::EControllerPaused` |
| `test_sve__enable_proposal_type_below_floor_aborts` | EnableProposalType slot at 5000 → Abort `board_voting::EFloorNotMet` |
| `test_sve_readonly__returns_ticket_and_leaves_ou_untouched` | Same Standalone ticket from `&OU`; `last_executed_ms<P>()` stays `none` |
| `test_sve_readonly__back_to_back` | Two read-only calls succeed |
| `test_sve_readonly__cooldown_type_aborts` | Abort `board_voting::ECooldownRequiresMutableOU` |
| `test_sve_readonly__nonzero_delay_aborts` | Abort `board_voting::EDelayForbidsAtomicExecution` |
| `test_sve_readonly__type_not_enabled_aborts` | Abort `board_voting::ETypeNotEnabled` |
| `test_sve_readonly__quorum_not_met_aborts` | Abort `board_voting::EInsufficientVotingWeight` |
| `test_sve_readonly__quorum_boundary_just_below_aborts` | Abort `board_voting::EInsufficientVotingWeight` |
| `test_sve__creates_no_objects_and_emits_lifecycle_events` | No object created; exactly 5 user events; `ProposalCreated`, `ProposalPayloadCreated` and `ProposalExecuted` carry the ticket's proposal ID |
| `test_sve_readonly__creates_no_objects_and_ids_are_distinct` | Same for the read-only variant; two runs get different proposal IDs |
| `test_sve__same_tx_executions_get_distinct_ids` | Two executions in one transaction get different proposal IDs |

### Planned (no test yet)

| Test | Expected |
|------|----------|
| `test_sve__migrating_ou_aborts` (planned) | OU `Migrating`, `P` is not `TransferAssets` → Abort `board_voting::EOUNotActive` |
| `test_sve__propose_threshold_above_weight_aborts` (planned) | propose_threshold 2 → Abort `board_voting::EProposeThresholdNotMet` |
| `test_sve__enable_bypass_type_multi_member_aborts_in_handler` (planned) | 2-member board, default `EnableBypassType` config (quorum 5000, threshold 8000): the single vote passes, then `external_execution::execute_enable_bypass_type` sees yes 1 / total 2 → Abort `external_execution::EApprovalFloorNotMet` |
| `ticket_from_vote__other_ou_aborts` (planned) | Passed proposal of OU A executed against OU B → Abort `board_voting::EOUIdMismatch` |
| `ticket_from_vote__disabled_type_aborts` (planned) | Type disabled after the proposal passed → Abort `board_voting::ETypeNotEnabled` |

## Tests

The vote-counting tests share three helpers local to `board_voting_tests.move`: `create_ou_with_members` wraps `ou::create(&governance::init_board(members), name, metadata_uri, ctx)`; `submit_proposal_with_config` calls the package-internal `proposal::create` with an explicit config, so each test sets its own quorum and threshold without an `EnableProposalType` vote; `vote_as` casts a vote through the public entry point:

```move
fun vote_as(scenario: &mut test_scenario::Scenario, voter: address, approve: bool, clock: &Clock) {
    scenario.next_tx(voter);
    {
        let mut prop = scenario.take_shared<Proposal<TestPayload>>();
        let vote_ou = scenario.take_shared_by_id<OU>(prop.ou_id());
        board_voting::vote(&mut prop, &vote_ou, approve, clock, scenario.ctx());
        test_scenario::return_shared(vote_ou);
        test_scenario::return_shared(prop);
    };
}
```

`board_voting::vote` aborts with `board_voting::EOUIdMismatch` unless `ou` is the proposal's own OU, then records the vote (`proposal::ENotActive`, `EVotingClosed`, `ENotInSnapshot`, `EAlreadyVoted`; see `04_proposals.md`).

---

### Single member, single YES vote passes

**Why it matters:** The simplest OU (a solo founder) must be fully functional. If a 1-member board cannot pass proposals, the creation flow breaks.

```move
#[test]
fun test_board__single_member_yes_passes() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_ou_with_members(&mut scenario, vector[CREATOR]);
    submit_proposal_with_config(&mut scenario, &clock, 5_000, 5_000); // quorum, threshold
    vote_as(&mut scenario, CREATOR, true, &clock);

    scenario.next_tx(CREATOR);
    {
        let prop = scenario.take_shared<Proposal<TestPayload>>();
        // 1 yes, 0 no, total 1: 1*10000 >= 5000*1 and 1*10000 >= 5000*1
        assert!(prop.status().is_passed());
        test_scenario::return_shared(prop);
    };
    clock.destroy_for_testing();
    scenario.end();
}
```

---

### 2 of 3 YES passes at 66%

**Why it matters:** A common board configuration. With quorum 6600 on 3 members the first YES is not enough (10000 < 19800); the second is (20000 ≥ 19800), and 2/2 YES meets the threshold (20000 ≥ 13200).

```move
submit_proposal_with_config(&mut scenario, &clock, 6_600, 6_600);
vote_as(&mut scenario, CREATOR, true, &clock);
// status().is_active()
vote_as(&mut scenario, MEMBER_B, true, &clock);
// status().is_passed()
```

---

### Quorum boundaries

**Why it matters:** Off-by-one errors in the quorum check would let a proposal pass with one vote too few, or block one that has enough. Cross-multiplication makes the boundary exact.

- `test_board__exact_quorum_boundary`: quorum 6666, 2 of 3 vote: 2 × 10000 = 20000 ≥ 6666 × 3 = 19998 → Passed.
- `test_board__below_quorum_does_not_pass`: quorum 6667, 2 of 3 vote: 20000 < 20001 → Active.
- `test_board__1_of_3_yes_fails_at_66`: quorum 6600, 1 of 3 vote: 10000 < 19800 → Active, even though 1/1 YES meets any threshold.

---

### NO-vote majority does not pass

**Why it matters:** If NO votes were ignored or counted as YES, governance would be meaningless.

`test_board__no_votes_majority_fails` uses quorum 10000 so all three members must vote. Votes: YES, NO, NO. Threshold: 1 × 10000 = 10000 < 5000 × 3 = 15000, so the proposal stays Active with yes = 1, no = 2.

---

### Threshold boundary: exactly 50%

**Why it matters:** `yes == no` is the boundary case. With `approval_threshold = 5000` the comparison is `>=`, so it passes.

`test_board__threshold_boundary_50_percent` runs on a 3-member board with quorum 5000: YES then NO gives quorum 20000 ≥ 15000 and threshold 10000 ≥ 10000 → Passed, yes = 1, no = 1.

---

### Abstention (non-voting) is not counted in the threshold

**Why it matters:** The threshold is `yes / (yes + no)`, not `yes / member_count`. Abstainers affect quorum only.

`test_board__abstention_not_counted_in_threshold`: 3 members, quorum 1 bps, threshold 5000. One YES: quorum 10000 ≥ 3, threshold 10000 ≥ 5000 → Passed, no = 0.

---

### Large board (10 members)

**Why it matters:** Vote math must scale; integer-division bugs tend to show up on larger boards.

`test_board__large_board_10_members`: quorum 7000, threshold 6600. After the 7th YES: quorum 70000 ≥ 70000, threshold 70000 ≥ 46200 → Passed with yes = 7. Any later vote would abort `proposal::ENotActive`.

---

### Propose threshold

**Why it matters:** `propose_threshold` limits who may submit. Under Board governance every member's proposer weight is 1, so `0` and `1` never block a member and anything above `1` blocks everyone.

`test_propose_threshold__above_board_weight_aborts` enables `TestPayload` with `new_config(5_000, 5_000, 2, 3_600_000, 0, 0)` and expects `board_voting::submit_proposal` to abort with `board_voting::EProposeThresholdNotMet`.

---

### Submission is keyed by the payload type

**Requirement:** `submit_proposal<P>(ou: &OU, metadata_ipfs: Option<String>, payload: P, clock, ctx)` takes no type key. `P` selects its own slot, which supplies the config and the display key recorded on the proposal.

**Why it matters:** A payload cannot be submitted under another type's config: there is no string key to spoof.

```move
#[test, expected_failure(abort_code = armature::board_voting::ETypeNotEnabled)]
fun submit_proposal_aborts_for_type_without_slot() {
    // Only TestPayload has a slot (display key "CustomKey").
    ...
    board_voting::submit_proposal(
        &ou,
        option::none(),
        AltPayload { label: 99 }, // no slot for AltPayload
        &clock,
        scenario.ctx(),
    );
    ...
}
```

`submit_proposal` also aborts with `board_voting::EOUNotActive` unless the OU is Active (or Migrating and `P` is `TransferAssets`), with `governance::ENotBoardMember` for a non-member, and with `board_voting::EFloorNotMet` when `P` is `EnableProposalType` and its slot's threshold is below 8000.

---

### Two-PTB execution: ticket_from_vote and the read-only variant

**Requirement:** `ticket_from_vote<P>(ou: &mut OU, prop: Proposal<P>, freeze, clock, ctx): ExecutionTicket<P>` takes the proposal by value, deletes it and records the execution timestamp on the slot. `ticket_from_vote_readonly` takes `&OU`, records nothing, and aborts with `board_voting::ECooldownRequiresMutableOU` if the slot's config or the proposal's snapshotted config has `cooldown_ms > 0`.

**Why it matters:** A PTB that reaches the OU only through read-only entry points can pass it as an immutable shared input, which takes no write lock. Cooldown tracking needs the write, so a cooldown on either config forces the `&mut` variant; otherwise the next execution would skip the cooldown.

```move
// ticket_from_vote_readonly__executes_without_recording
let ticket = board_voting::ticket_from_vote_readonly(&ou, prop, &freeze, &clock, scenario.ctx());
assert!(ticket.ticket_payload().value == 7);
ticket.discharge(internal::permit()); // TestPayload is defined in the test module
assert!(ou.last_executed_ms<TestPayload>().is_none());
```

The execution checks themselves (`proposal::ENotPassed`, `ENotEligible`, `EDelayNotElapsed`, `EExecutionWindowClosed`, `ECooldownActive`, `EExecutionPaused`) are covered in `04_proposals.md`.

---

## Atomic single-vote path

`submit_vote_execute<P: store>(ou: &mut OU, metadata_ipfs: Option<String>, payload: P, freeze: &EmergencyFreeze, clock: &Clock, ctx: &mut TxContext): ExecutionTicket<P>` submits, casts the caller's YES vote and executes in one call. `submit_vote_execute_readonly<P>` has the same arguments with `ou: &OU`.

**No `Proposal` object is created**, owned or shared. The proposal ID comes from `ctx.fresh_object_address()`, and the events a shared proposal would emit over its life are emitted in order and form the audit record:

1. `ProposalCreated { proposal_id, ou_id, type_key, proposer, metadata_ipfs }`
2. `ProposalPayloadCreated { proposal_id, ou_id, payload_bcs }`
3. `VoteCast { voter: proposer, approve: true, weight: 1 }`
4. `ProposalPassed { yes_weight: 1, no_weight: 0 }`
5. `ProposalExecuted { executor: proposer }`

Checks, in order (they mirror `submit_proposal` followed by `ticket_from_vote`):

| # | Check | Abort |
|---|-------|-------|
| 1 | OU Active, or Migrating and `P` is migration-allowed | `board_voting::EOUNotActive` |
| 2 | `P` has a slot | `board_voting::ETypeNotEnabled` |
| 3 | Caller is a current board member | `governance::ENotBoardMember` |
| 4 | `EnableProposalType` slot threshold ≥ 8000 | `board_voting::EFloorNotMet` |
| 5 | Propose threshold | `board_voting::EProposeThresholdNotMet` |
| 6 | `execution_delay_ms == 0` | `board_voting::EDelayForbidsAtomicExecution` |
| 7 | Read-only variant only: `cooldown_ms == 0` | `board_voting::ECooldownRequiresMutableOU` |
| 8 | Not controller-paused | `board_voting::EControllerPaused` |
| 9 | `P` not frozen | `emergency::EFrozen` |
| 10 | The caller's single YES passes quorum and threshold against the current `member_count` | `board_voting::EInsufficientVotingWeight` |
| 11 | Execution not paused | `proposal::EExecutionPaused` |
| 12 | Cooldown elapsed since the slot's last execution | `proposal::ECooldownActive` |

The ticket is Standalone with `yes_weight = 1` and `total_snapshot_weight = member_count`, and its request carries the slot's permission bits and borrow scope at that moment. Handler checks on actual vote weights therefore behave as on the two-PTB path: `EnableBypassType`'s handler requires yes / total ≥ 80%, which one vote meets only on a 1-member board. The `&mut OU` variant records the execution timestamp (cooldown); the read-only variant writes nothing.

**Single-vote pass math.** With one YES and no NO the threshold is always met (10000 ≥ any `approval_threshold`). Quorum is met iff `quorum × member_count ≤ 10000`:

| Board size | Largest quorum a single vote meets |
|---|---|
| 1 | 10000 (any) |
| 2 | 5000 |
| 3 | 3333 |
| 5 | 2000 |
| 10 | 1000 |

A config built for single-vote execution typically uses quorum 1 bps and delay 0.

**Security note.** The atomic path removes the window between submission and execution in which members can see a proposal and the freeze admin can freeze its type. Governance-sensitive types (SetBoard, AddMember, RemoveMember, UpdateProposalConfig, EnableProposalType) should be configured with `execution_delay_ms > 0` so they cannot take this path. This is a recommendation, not enforced: every default config has `execution_delay_ms = 0`, and `proposals/ADR_GOVERNANCE_TYPE_DELAY_DEFAULTS.md` (non-zero defaults) is still Proposed.

---

### Single member receives a Standalone ticket

**Why it matters:** Single-member OUs and single-vote trading configs execute in one PTB without a shared object per execution.

```move
#[test]
fun test_sve__single_member_returns_ticket() {
    let mut scenario = test_scenario::begin(CREATOR);
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(1_000_000);

    create_single_member_ou(&mut scenario);
    // ou.test_enable_type<FastPayload>(...) with new_config(5_000, 5_000, 0, 3_600_000, 0, 0)
    enable_fast_type(&mut scenario, 5_000, 5_000, 0, 0); // quorum, threshold, delay, cooldown

    scenario.next_tx(CREATOR);
    {
        let mut ou = scenario.take_shared<OU>();
        let freeze = scenario.take_shared<EmergencyFreeze>();
        let ticket = board_voting::submit_vote_execute<FastPayload>(
            &mut ou,
            option::none(),
            FastPayload { value: 42 },
            &freeze,
            &clock,
            scenario.ctx(),
        );
        assert!(ticket.ticket_is_standalone());
        assert!(ticket.ticket_yes_weight() == 1);
        assert!(ticket.ticket_total_snapshot_weight() == 1);
        ticket.discharge(internal::permit()); // FastPayload is defined in the test module
        test_scenario::return_shared(ou);
        test_scenario::return_shared(freeze);
    };
    clock.destroy_for_testing();
    scenario.end();
}
```

---

### No object is created; the events are the audit record

**Why it matters:** Before event-only execution every single-vote execution left a shared audit object whose storage deposit nobody reclaimed. Indexers now reconstruct the lifecycle from five events under one fresh proposal ID.

```move
// test_sve__creates_no_objects_and_emits_lifecycle_events
sve_and_check_events(&mut scenario, &clock, false); // asserts one event of each kind: proposal IDs,
                                                    // proposer, metadata, payload bytes, weights
let effects = scenario.next_tx(CREATOR);
assert!(effects.created().is_empty());
assert!(effects.num_user_events() == 5);
```

`test_sve_readonly__creates_no_objects_and_ids_are_distinct` and `test_sve__same_tx_executions_get_distinct_ids` check that every execution, including two in one transaction, gets its own ID.

---

### A configured delay forbids atomic execution

**Requirement:** `execution_delay_ms > 0` aborts with `board_voting::EDelayForbidsAtomicExecution` before any event is emitted.

**Why it matters:** A delay exists to leave time between pass and execution. The atomic path has none, so it refuses up front rather than failing later. Setting a delay is how an OU keeps a type off this path.

`test_sve__nonzero_delay_aborts` enables `FastPayload` with a 1000 ms delay; `test_sve_readonly__nonzero_delay_aborts` checks the read-only variant.

---

### The caller's single vote must pass on its own

**Requirement:** The proposer's YES (weight 1) must satisfy quorum and threshold against the current `member_count`, else `board_voting::EInsufficientVotingWeight`.

**Why it matters:** A single member must not execute a type whose config needs more participation than one vote.

`test_sve__quorum_boundary_just_below_aborts`: 3 members, quorum 3400: 1 × 10000 = 10000 < 3400 × 3 = 10200 → abort. `test_sve__two_member_50_quorum_single_vote_passes`: 2 members, quorum 5000: 10000 ≥ 10000 → ticket with total = 2.

---

### Read-only variant requires cooldown 0

**Requirement:** `submit_vote_execute_readonly` aborts with `board_voting::ECooldownRequiresMutableOU` when the slot's `cooldown_ms > 0`. It never writes the OU.

**Why it matters:** Concurrent single-vote executions of a cooldown-free type can share the OU as an immutable input and stop contending on it. A type with a cooldown must record its execution time, so it must use the `&mut OU` variant.

`test_sve_readonly__returns_ticket_and_leaves_ou_untouched` asserts `ou.last_executed_ms<FastPayload>().is_none()` after a read-only execution; `test_sve__mutable_variant_records_execution` asserts the `&mut` variant records the clock.

---

### Freeze, pause and floors apply on the atomic path

**Why it matters:** The atomic path must not be a way around the safety checks of the two-PTB path.

- `test_sve__frozen_type_aborts`: the freeze admin calls `freeze.freeze_type<FastPayload>(&cap, &clock)`; the atomic call aborts `emergency::EFrozen`.
- `test_sve__execution_paused_aborts`: `ou.set_execution_paused(true, &req)` with a test request; abort `proposal::EExecutionPaused`.
- `test_sve__controller_paused_aborts`: `ou.set_controller_paused(true, &req)` with a privileged test request; abort `board_voting::EControllerPaused`.
- `test_sve__enable_proposal_type_below_floor_aborts`: EnableProposalType's slot lowered to 5000 with the `test_update_config` seam; the atomic submission aborts `board_voting::EFloorNotMet`, the same submission-time floor as `submit_proposal`.
