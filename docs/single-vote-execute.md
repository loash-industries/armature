# Single-Vote-Execute Pattern

`board_voting::submit_vote_execute` collapses the standard three-step proposal flow (submit → vote → execute) into a single PTB. It is the preferred path for operational proposal types that have a small board and do not require inter-PTB observation time.

---

## Standard Two-PTB vs Atomic Path

The normal board-voting flow spans two separate transactions:

1. **PTB 1 — Submit + Vote**: a board member calls `board_voting::submit_proposal`, then any quorum of members call `proposal::vote`. The proposal is shared while `Active`.
2. **PTB 2 — Execute**: once `Passed`, any board member calls `board_voting::ticket_from_vote` to obtain an `ExecutionTicket`, then passes it to the proposal type's handler.

The shared-object window between PTB 1 and PTB 2 is intentional for governance-sensitive types: it creates an observable period during which members can audit the payload, the emergency admin can freeze the type, and the community can react.

`submit_vote_execute` eliminates that window entirely. The proposal object is never shared while `Active` — it lives as an owned object inside a single PTB, is voted on, executed, and then shared in its final `Executed` state as a permanent audit record.

---

## When to Use It

A proposal type is eligible for the atomic path when **all** of the following hold:

| Requirement | Reason |
|---|---|
| `execution_delay_ms = 0` | A non-zero delay requires two PTBs by definition. The check fires before any mutation. |
| Caller's single vote satisfies quorum **and** `approval_threshold` | The function casts exactly one YES vote and then asserts `prop.status().is_passed()`. If weight is insufficient the call aborts with `EInsufficientVotingWeight`. |
| DAO is `Active` (or `Migrating` + `TransferAssets`) | Same guard as `submit_proposal`. |
| Type is in `enabled_proposal_types` | Same guard as `submit_proposal`. |
| Caller is a current board member | Same guard as `submit_proposal`. |
| Type is not frozen in `EmergencyFreeze` | Checked against the freeze object. |
| DAO is not `controller_paused` | Checked against the DAO's controller pause flag. |
| DAO is not `execution_paused` | Checked inside `proposal::execute`. |
| Cooldown for this type has elapsed | Checked against `dao.last_executed_at` inside `proposal::execute`. |

**Governance-sensitive types must not use this path.** Any type that alters board composition, proposal configs, or bypass privileges (`SetBoard`, `AddMember`, `RemoveMember`, `BatchAddMembers`, `BatchRemoveMembers`, `UpdateProposalConfig`, `EnableProposalType`, `EnableBypassType`, `DisableBypassType`) must be configured with `execution_delay_ms > 0` so the atomic path is statically rejected.

---

## Call Signature

```move
public fun submit_vote_execute<P: store>(
    dao: &mut DAO,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P>
```

The returned `ExecutionTicket<P>` is a `Standalone` ticket carrying the proposal payload and the vote weights at execution time. The caller passes it directly to the proposal type's handler in the same PTB, then calls `ticket.discharge()` (or `discharge_returning_payload()` for payload types without `drop`).

---

## Execution Flow

```
submit_vote_execute<P>(dao, type_key, payload, ...)
  │
  ├─ validate (mirrors submit_proposal):
  │    dao.status is Active | migration-allowed
  │    type_key ∈ enabled_proposal_types
  │    type_binding matches P (if bound)
  │    ctx.sender ∈ board members
  │    config.execution_delay_ms == 0          ← extra atomic-path guard
  │
  ├─ validate (mirrors ticket_from_vote):
  │    !dao.is_controller_paused
  │    freeze.assert_not_frozen(type_key)
  │
  ├─ proposal::create_returning<P>(...)        ← owned, never shared while Active
  │
  ├─ proposal::vote(&mut prop, true, ...)      ← single YES vote from caller
  │    assert prop.status().is_passed()        ← abort EInsufficientVotingWeight if not
  │
  ├─ proposal::execute(&mut prop, ...)
  │    checks: execution_paused, delay, cooldown
  │    extracts payload → ExecutionRequest hot potato
  │
  ├─ dao.record_execution(type_key, now)
  │
  ├─ proposal::share_proposal(prop)            ← shares in Executed state (audit record)
  │
  └─ new_ticket_standalone(req, payload, yes_weight, total_snapshot_weight)
       → ExecutionTicket<P>  (Standalone closeout)
```

---

## Vote Weight Mechanics

Board governance assigns each member weight **1**. The snapshot is taken at proposal creation time. For a board of `N` members:

- **quorum** passes when `yes_weight * 10_000 >= quorum_bps * N`
- **threshold** passes when `yes_weight * 10_000 >= threshold_bps * (yes_weight + no_weight)`

With a single YES vote (`yes_weight = 1`, `no_weight = 0`):
- quorum is met when `10_000 >= quorum_bps * N`, i.e. `quorum_bps <= 10_000 / N`
- threshold is always met (1/1 = 100%)

Practical breakpoints:

| Board size | Max quorum for single-vote pass |
|---|---|
| 1 member | 10 000 bps (100%) — always passes |
| 2 members | 5 000 bps (50%) — exactly met |
| 3 members | 3 333 bps (33%) |
| 5 members | 2 000 bps (20%) |

For operational DAOs the recommended config is `quorum = 5_000, approval_threshold = 5_000` for small boards (1–2 members) and a lower quorum for larger boards where a single operator needs to act without waiting for peers.

---

## Returned Ticket

The ticket is `Standalone` — it carries the vote weights captured at execution time and the `ExecutionRequest` hot potato. Handlers that enforce an approval floor (e.g. `assert_approval_floor_ticket` for `EnableBypassType`) read `ticket_yes_weight()` and `ticket_total_snapshot_weight()` from the ticket directly.

Calling `ticket_yes_weight()` or `ticket_total_snapshot_weight()` on a `Composite` or `External` ticket aborts with `ENotStandaloneTicket`. If a handler may receive tickets from multiple paths, call `ticket_is_standalone()` first.

---

## Audit Trail

Even though the proposal object is never publicly observable while `Active`, the full audit record is preserved:

- `ProposalCreated` event is emitted by `create_returning`
- `ProposalPayloadCreated` event records the BCS-serialised payload
- `VoteCast` event is emitted by `proposal::vote`
- `ProposalPassed` event is emitted when the vote satisfies quorum/threshold
- `ProposalExecuted` event is emitted by `proposal::execute`
- The `Executed` proposal object is shared at the end of `submit_vote_execute` — identical to a standard two-PTB execution

The on-chain event stream is indistinguishable from a standard proposal that happened to be submitted, voted on, and executed in rapid succession.

---

## Error Codes

| Abort | Code | Trigger |
|---|---|---|
| `EDAONotActive` | `board_voting::0` | DAO is not `Active` (or `Migrating` + non-`TransferAssets`) |
| `ETypeNotEnabled` | `board_voting::1` | `type_key` not in `enabled_proposal_types` |
| `EControllerPaused` | `board_voting::3` | Controller has paused the SubDAO |
| `ETypeMismatch` | `board_voting::5` | `P` does not match the bound Move type for `type_key` |
| `EFloorNotMet` | `board_voting::6` | `EnableProposalType` config has `approval_threshold < 66%` |
| `EDelayForbidsAtomicExecution` | `board_voting::7` | `execution_delay_ms > 0` |
| `EInsufficientVotingWeight` | `board_voting::8` | Single vote did not pass quorum or threshold |
| `ENotBoardMember` | `governance::2` | Caller not on the board |
| `EExecutionPaused` | `proposal::12` | `dao.execution_paused == true` |
| `ECooldownActive` | `proposal::9` | Last execution of this type was within `cooldown_ms` |
