# ADR: Atomic Submit-Vote-Execute (`submit_vote_execute`)

| Field          | Value                                                    |
| -------------- | -------------------------------------------------------- |
| **Status**     | Proposed                                                 |
| **Date**       | 2026-06-07                                               |
| **Authors**    | —                                                        |
| **Package**    | `armature_framework` (`proposal.move`, `board_voting.move`) |
| **Depends on** | `ADR_SUBMISSION_TIME_FLOOR_ENFORCEMENT` (floor constants) |
| **Supersedes** | —                                                        |

---

## Context

### The Shared-Object Wall

The standard vote-path requires at least two programmable transaction blocks (PTBs):

```
PTB 1: submit_proposal<P>(...)    → Proposal<P> shared [Active]
       vote<P>(proposal, true, ...)  → Proposal<P> [Passed]

PTB 2: ticket_from_vote<P>(dao, proposal, freeze, clock, ctx) → ExecutionTicket<P>
       execute_<op>(ticket, ...)
```

`proposal::create` ends with `transfer::share_object(proposal)`. Once a Sui object is
shared, Sui's consensus model prevents it from being accessed again in the same PTB.
Even with `execution_delay_ms = 0` and a board member whose single vote is enough to
pass, the caller must submit two separate transactions.

### The Use Case

A highly-dynamic organizational unit — for example, a single-operator trading sub-DAO
or a fast-action committee on an exchange — needs to place, cancel, and manage trades on
Triex without the two-PTB overhead. They have sufficient voting weight to unilaterally
pass proposals under their DAO's configured `quorum` and `approval_threshold`. Forcing
two separate transactions introduces unnecessary latency and operational complexity for
time-sensitive trading actions.

### Why Not `ExternalExecutionCap`?

The existing bypass path (`external_execution::ticket_from_cap`) already enables
single-PTB execution. However it bypasses the vote entirely — no `VoteCast`,
`ProposalPassed`, or approval-weight check ever runs. The use case here specifically
wants the vote to be on-chain: quorum and threshold are checked against the live
governance snapshot, all events are emitted, and the audit trail is identical to
the normal vote path. The atomic path is an ergonomic shortcut, not a privilege
escalation.

---

## Decision

Add two new functions to the `armature_framework` package:

1. `proposal::create_returning<P>` — a `public(package)` counterpart to
   `proposal::create` that returns the owned `Proposal<P>` instead of sharing it,
   allowing the caller to vote and execute before sharing the proposal as an audit
   record.

2. `board_voting::submit_vote_execute<P>` — a public entry that:
   - Runs all the same validation as `submit_proposal` and `ticket_from_vote`
   - Creates a `Proposal<P>` as an owned object
   - Immediately casts the caller's YES vote
   - Asserts the proposal passed (aborts if the caller's weight alone is insufficient)
   - Calls `proposal::execute` to extract the payload and `ExecutionRequest`
   - Records the execution timestamp for cooldown tracking
   - Shares the now-`Executed` proposal as an immutable audit record
   - Returns `ExecutionTicket<P>` to the caller

The resulting ticket has `Closeout::Standalone`, making it indistinguishable from a
ticket produced by the standard two-PTB path. All execution-time floor checks
(`assert_approval_floor_ticket` in `execute_enable_bypass_type`, etc.) apply
identically.

---

## Constraints

Any implementation must preserve:

1. **Audit parity** — The events emitted (`ProposalCreated`, `ProposalPayloadCreated`,
   `VoteCast`, `ProposalPassed`, `ProposalExecuted`) and the final on-chain
   `Proposal<P>` object in `Executed` state must be identical to the standard path.

2. **No new privilege** — A caller using `submit_vote_execute` must not be able to
   execute any proposal that could not also be executed via the standard two-PTB path
   with the same voter set, config, and DAO state.

3. **Floor constant inviolability** — Hardcoded approval floors (`ENABLE_APPROVAL_FLOOR_BPS`,
   `ENABLE_BYPASS_APPROVAL_FLOOR_BPS`) must remain effective. The function must produce
   a `Standalone` ticket so execution-time floor checks in handlers still apply.

4. **`execution_delay_ms > 0` safety** — Types configured with a non-zero execution
   delay must not be executable via this path. The function must assert the delay is
   zero with a clear error, rather than relying on `EDelayNotElapsed` propagating from
   `proposal::execute`.

5. **All DAO safety checks** — Emergency freeze, execution pause, controller pause,
   cooldown, and migration-status guards must all be checked in the same order as the
   combined `submit_proposal` + `ticket_from_vote` call sequence.

6. **Governance-sensitive types must use `execution_delay_ms > 0`** — Any proposal
   type that modifies board membership or governance configuration (`SetBoard`,
   `AddMember`, `RemoveMember`, `UpdateProposalConfig`, `EnableProposalType`) MUST be
   configured with a non-zero execution delay. This simultaneously preserves the
   inter-PTB freeze-admin window and acts as a firewall against `submit_vote_execute`
   use. This is a configuration requirement, not a framework enforcement — DAO
   deployers are responsible for it. See S4 and the Governance Tooling Blindspot
   section for why this matters.

7. **Floor check sync obligation** — Every time a new submission-time floor check is
   added to `submit_proposal` (e.g., as part of `ADR_SUBMISSION_TIME_FLOOR_ENFORCEMENT`
   or future ADRs), the identical check must be added to `submit_vote_execute`. The two
   functions must remain in lockstep. Failure to sync will silently make
   `submit_vote_execute` a weaker gatekeeper than `submit_proposal`.

---

## Proposed Design

### 1. New Internal Primitive: `proposal::create_returning`

```move
/// Like create(), but returns the owned Proposal instead of sharing it.
///
/// INVARIANT: This function may only be called by submit_vote_execute.
/// The caller MUST call transfer::share_object on the returned proposal
/// after execution completes. Transferring the proposal to an address
/// (transfer::transfer) instead of sharing it would strand an Active
/// proposal object in an owned-object state that can never complete its
/// lifecycle, while the ProposalCreated event would still be on-chain.
///
/// Visibility is public(package) — no external caller can hold an
/// un-shared Proposal<P> by value.
public(package) fun create_returning<P: store>(
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: P,
    config: ProposalConfig,
    governance: &GovernanceConfig,
    is_dao_active: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): Proposal<P> {
    assert!(is_dao_active, EDAONotActive);
    let (vote_snapshot, total_snapshot_weight) = governance.board_vote_snapshot();
    let payload_bcs = std::bcs::to_bytes(&payload);

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload: option::some(payload),
        vote_snapshot,
        total_snapshot_weight,
        votes_cast: vec_map::empty(),
        yes_weight: 0,
        no_weight: 0,
        config,
        created_at_ms: clock.timestamp_ms(),
        passed_at_ms: option::none(),
        status: ProposalStatus::Active,
    };

    let proposal_id = object::id(&proposal);

    event::emit(ProposalCreated { proposal_id, dao_id, type_key, proposer });
    event::emit(ProposalPayloadCreated { proposal_id, dao_id, payload_bcs });

    proposal
    // NOTE: no transfer::share_object — caller is responsible
}
```

This is the only change to `proposal.move`. The struct definition, `vote`, `execute`,
`new_ticket_standalone`, and all other functions are unchanged.

### 2. New Errors in `board_voting.move`

```move
/// Proposal type has execution_delay_ms > 0; atomic execution is impossible.
const EDelayForbidsAtomicExecution: u64 = 7;
/// Caller's vote weight alone did not satisfy quorum + threshold.
const EInsufficientVotingWeight: u64 = 8;
```

### 3. New Entry: `board_voting::submit_vote_execute`

```move
/// Submit a proposal, cast the caller's YES vote, and execute — all in one PTB.
///
/// Requires:
///   - execution_delay_ms = 0 for this proposal type
///   - The caller's single vote satisfies quorum and approval_threshold
///
/// Validation order mirrors submit_proposal + ticket_from_vote exactly.
/// The proposal is kept owned until execution completes, then shared as an
/// Executed audit record. Returns a Standalone ExecutionTicket<P>.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_vote_execute<P: store>(
    dao: &mut DAO,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    // --- submit_proposal checks ---

    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating()
        && dao::is_migration_allowed_type(&type_key);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(dao.enabled_proposal_types().contains(&type_key), ETypeNotEnabled);

    if (dao.has_type_binding(&type_key)) {
        let actual = type_name::with_defining_ids<P>().into_string();
        assert!(dao.type_binding_for(&type_key) == actual, ETypeMismatch);
    };

    let proposer = ctx.sender();
    dao.governance().assert_board_member(proposer);

    let config = *dao.proposal_configs().get(&type_key);

    // Submission-time floor for EnableProposalType (mirrors submit_proposal)
    if (type_key == b"EnableProposalType".to_ascii_string()) {
        assert!(
            (config.approval_threshold() as u64) >= ENABLE_APPROVAL_FLOOR_BPS,
            EFloorNotMet,
        );
    };

    if (config.propose_threshold() > 0) {
        let weight = dao.governance().proposer_weight(proposer);
        assert!(weight >= config.propose_threshold(), EProposeThresholdNotMet);
    };

    // Atomic execution is impossible if a delay is configured.
    assert!(config.execution_delay_ms() == 0, EDelayForbidsAtomicExecution);

    // --- ticket_from_vote checks ---

    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&type_key, clock);

    // Cooldown check (mirrors ticket_from_vote)
    let last_executed_at = dao.last_executed_at();
    let last_ms = if (last_executed_at.contains(&type_key)) {
        option::some(*last_executed_at.get(&type_key))
    } else {
        option::none()
    };

    // --- Create owned proposal (never shared while active) ---

    let status_ok = true;
    let mut proposal = proposal::create_returning<P>(
        dao.id(),
        type_key,
        proposer,
        metadata_ipfs,
        payload,
        config,
        dao.governance(),
        status_ok,
        clock,
        ctx,
    );

    // --- Vote ---

    proposal::vote(&mut proposal, true, clock, ctx);

    // If the caller's weight alone was not enough, abort with a clear error.
    assert!(proposal.status().is_passed(), EInsufficientVotingWeight);

    // --- Execute ---

    let yes_weight = proposal.yes_weight();
    let total_snapshot_weight = proposal.total_snapshot_weight();

    let (payload_out, req) = proposal::execute(
        &mut proposal,
        dao.governance(),
        last_ms,
        dao.is_execution_paused(),
        clock,
        ctx,
    );

    dao.record_execution(type_key, clock.timestamp_ms());

    // Share the Executed proposal as the permanent audit record.
    transfer::share_object(proposal);

    proposal::new_ticket_standalone(req, payload_out, yes_weight, total_snapshot_weight)
}
```

### 4. PTB Usage Pattern

```
// Single PTB — submit, vote, and execute atomically:
let ticket = board_voting::submit_vote_execute<PlaceLimitOrder>(
    dao,
    b"PlaceLimitOrder",
    option::none(),
    place_limit_order_payload,
    freeze,
    clock,
    ctx,
);
trading_ops::execute_place_limit_order<QuoteAsset>(
    pool,
    balance_manager,
    cap_vault,
    ticket,
    clock,
    ctx,
);
```

---

## Correctness

### Audit Record Equivalence

The events emitted by `submit_vote_execute` are identical to those emitted by the
two-PTB path:

| Event | Two-PTB source | Atomic source |
|---|---|---|
| `ProposalCreated` | `proposal::create` | `proposal::create_returning` |
| `ProposalPayloadCreated` | `proposal::create` | `proposal::create_returning` |
| `VoteCast` | `proposal::vote` | `proposal::vote` (same function) |
| `ProposalPassed` | `proposal::vote` | `proposal::vote` (same function) |
| `ProposalExecuted` | `proposal::execute` | `proposal::execute` (same function) |

The final shared `Proposal<P>` object is in `Executed` status with `payload: None`,
identical to the standard path.

### Ticket Equivalence

The returned `ExecutionTicket<P>` has `Closeout::Standalone { proposal_id, yes_weight,
total_snapshot_weight }`, produced by `proposal::new_ticket_standalone` — the exact
same constructor called by `ticket_from_vote`. Handlers that inspect vote weights
(e.g. `assert_approval_floor_ticket` in `external_execution.move`) receive the same
data structure and run identical checks.

---

## Security Analysis

### S1: No New Privilege Over the Standard Vote Path

**Claim:** A caller cannot execute any proposal via `submit_vote_execute` that they
could not also execute via `submit_proposal` + `vote` + `ticket_from_vote` in
separate PTBs.

**Reasoning:** All checks are identical. The function performs every validation from
`submit_proposal` (DAO active, type enabled, type binding, board member, propose
threshold, submission-time floor) and every validation from `ticket_from_vote`
(controller pause, freeze, cooldown). The `proposal::execute` call performs the
remaining checks (execution pause, board member at execution time, delay, cooldown).
In the standard two-PTB flow, all of these same checks must also pass. No check is
skipped or weakened.

### S2: Execution-Time Floor Checks Remain Effective

`execute_enable_bypass_type` calls `assert_approval_floor_ticket` which:
1. Asserts `ticket.ticket_is_standalone()` — true, since `submit_vote_execute`
   produces a `Closeout::Standalone` ticket.
2. Asserts `total_snapshot_weight > 0` — true, since a board with zero members
   cannot exist (`governance.move:EEmptyBoard`).
3. Asserts `gte_bps(yes_weight, total_snapshot_weight, FLOOR_BPS)`.

For `EnableBypassType` with `FLOOR = 8000`:
- If N=1 (1 member): `gte_bps(1, 1, 8000)` = `10000 >= 8000` = **pass**.
  A single-member DAO can also pass this in the standard flow; no new attack.
- If N=2 (2 members, quorum=50%): `gte_bps(1, 2, 8000)` = `10000 >= 16000` = **fail**.
  The handler aborts with `EApprovalFloorNotMet` even though the proposal passed the
  vote. This is correct and matches the standard path's behavior.

### S3: `execution_delay_ms > 0` Types Are Blocked

The explicit `assert!(config.execution_delay_ms() == 0, EDelayForbidsAtomicExecution)`
check fires before any state is mutated. A type with delay > 0 cannot be submitted via
this path. Without this pre-check, `proposal::execute` would absorb the error as
`EDelayNotElapsed`, which is technically equivalent but produces a misleading error and
leaves the question of why the proposal was created. The pre-check prevents the owned
proposal from being constructed at all.

### S4: The Inter-PTB Window Is Eliminated — a Real Trade-off

In the standard path with `execution_delay_ms = 0`, two windows exist between the
two PTBs that `submit_vote_execute` eliminates:

**The freeze admin window.** Between PTB 1 (submit+vote → Passed) and PTB 2
(execute), a `FreezeAdminCap` holder who observes the passed proposal in events
can freeze the type before PTB 2 lands. `submit_vote_execute` removes this window
— the freeze check fires once at PTB start and execution is atomic. This is not a
hypothetical: the `EmergencyFreeze` mechanism exists precisely so a freeze admin
can react to a passed proposal before it executes.

**The NO vote window.** In the standard path, between `submit_proposal` and the
proposer's vote, other members can cast NO votes. A timely NO vote can change the
outcome if the threshold math is sensitive — for example, on a 3-member board with
quorum=33% and threshold=51%, one NO vote before the proposer votes YES yields
`yes=1, total_voted=2`, and `gte_bps(1, 2, 5100)` = `10000 >= 10200` = **false**,
blocking the proposal. `submit_vote_execute` eliminates this window entirely: no
other member can react before the vote is cast and the proposal is executed.

**Why this does not constitute a new attack.** A caller using `submit_vote_execute`
can only pass proposals that their configured quorum and threshold already allow
a single voter to pass. A motivated proposer in the standard path could submit PTB 1
and PTB 2 back-to-back in the same epoch, making the inter-PTB window extremely
narrow in practice. The atomic path removes it entirely, which is an intentional
ergonomic choice for the trading use case.

**The mitigation.** For governance-sensitive types where the inter-PTB observation
window matters, configure `execution_delay_ms > 0`. This simultaneously ensures a
meaningful deliberation window and blocks `submit_vote_execute` (see Constraint 6).
Trading operation types have no need for this window and correctly use delay=0.

### S5: Board Snapshot Cannot Diverge From Current Membership

In the standard path, the vote snapshot is taken at `submit_proposal` time. Between
the two PTBs, `SetBoard` or `RemoveMember` proposals could execute and change the
board. The executor's current membership is re-checked in `proposal::execute`, but
a removed member's YES vote still counts in the snapshot. In the atomic path, the
snapshot is taken and execution happens in the same PTB — no board change can
interleave. This is strictly tighter than the standard path.

### S6: Cooldown Enforcement Is Preserved

`dao.record_execution(type_key, clock.timestamp_ms())` is called immediately after
`proposal::execute`, before the function returns. If the function panics after this
point (impossible by construction, since only `transfer::share_object` and
`new_ticket_standalone` follow), the record would be set without a ticket being
returned, effectively throttling the type for `cooldown_ms` without a successful
execution. Since both operations are infallible after `record_execution`, this is
not a realistic concern.

### S7: Replay Protection

Each call to `submit_vote_execute` creates a new `Proposal<P>` object with a fresh
`UID`. The `ExecutionTicket<P>` carries the `proposal_id` in its `ExecutionRequest`
and `Closeout`. The `discharge()` function asserts `request.proposal_id == proposal_id`.
Replay is impossible: each ticket is bound to a unique proposal object.

### S8: Cannot Be Used to Bootstrap `EnableBypassType` on a SubDAO

SubDAOs have `EnableBypassType` in `SUBDAO_BLOCKED_TYPES`, so it is not in their
`enabled_proposal_types`. The `assert!(dao.enabled_proposal_types().contains(&type_key))`
check fires before any state is mutated. No bypass-escalation path exists.

### S9: Type Binding Anti-Spoofing Preserved

The type binding check — `dao.type_binding_for(type_key) == type_name::with_defining_ids<P>()` —
is replicated verbatim from `submit_proposal`. A caller cannot submit a proposal for
a bound type key using a different payload type `P`.

### S10: `propose_threshold` Enforced

The `propose_threshold` check is replicated. A caller without sufficient proposer
weight cannot invoke `submit_vote_execute` for types that require it, just as they
cannot invoke `submit_proposal`.

### S11: Governance Tooling Blindspot

In the standard path, the `Active` shared proposal object is queryable by any
governance dashboard, monitoring bot, or multi-sig review flow between PTB 1 and
execution. These systems can alert board members before a proposal executes.

With `submit_vote_execute`, all five governance events land in a single transaction.
The proposal is already `Executed` by the time any off-chain system processes the
transaction. For trading operations this is the intended behavior. For governance-
modifying types (`SetBoard`, `AddMember`, `UpdateProposalConfig`, etc.) it means a
single member with sufficient quorum weight could make governance changes that are
invisible to monitoring until after they are committed.

The mitigation is Constraint 6: governance-sensitive types must use
`execution_delay_ms > 0`, which prevents `submit_vote_execute` from being called for
them entirely. There is no framework-level enforcement of which types are "governance-
sensitive" — this remains a DAO configuration responsibility.

### S12: `create_returning` as a Future Misuse Surface

`proposal::create_returning` is `public(package)`, meaning any code added to
`armature_framework` in a future upgrade can call it. The risk is a developer calling
`create_returning` and then using `transfer::transfer` (valid for `key` objects)
instead of `transfer::share_object`, stranding the `Proposal<P>` as an owned object
in `Active` state with a `ProposalCreated` event on-chain pointing to an object that
can never complete its lifecycle.

Mitigations: (a) the `INVARIANT` comment in `create_returning` documents the contract,
(b) the function is package-internal so external code can never call it, and (c) the
only current caller is `submit_vote_execute`, which always shares the result.
Any future caller must be reviewed against this invariant at the time of the upgrade.

---

## Risk Summary

| Risk | Severity | Mitigated by |
|---|---|---|
| Caller executes proposal their weight can't pass | Critical | `EInsufficientVotingWeight` abort; vote check is identical to standard path |
| Approval floor bypass (EnableBypassType, etc.) | Critical | Standalone ticket; `assert_approval_floor_ticket` in handlers still fires |
| Execution of delay-gated types | High | `EDelayForbidsAtomicExecution` pre-check |
| Type-key spoofing | High | Type binding check replicated from `submit_proposal` |
| Replay attack | High | Fresh `UID` per proposal; `discharge()` cross-checks `proposal_id` |
| Governance changes invisible to monitoring tools | High | Constraint 6: governance-sensitive types must use `execution_delay_ms > 0` |
| Floor check divergence from `submit_proposal` | High | Constraint 7: explicit sync obligation on every new submission-time floor |
| SubDAO bypass-escalation | Medium | `enabled_proposal_types` check; `EnableBypassType` blocked for SubDAOs |
| Cooldown evasion | Medium | `dao.record_execution` called before ticket returned |
| Freeze admin window eliminated | Medium | Constraint 6: governance-sensitive types must use `execution_delay_ms > 0` |
| NO vote window eliminated for other members | Medium | Constraint 6; accepted trade-off for trading use case |
| `create_returning` future misuse in upgrades | Medium | INVARIANT comment; review obligation at upgrade time |
| Board snapshot race | Low | Snapshot and execution are in same PTB; no interleave possible |

---

## Alternatives Considered

### A: Keep the Two-PTB Flow

No framework changes. The trading unit submits two transactions for every trade.

**Why not chosen:** Adds latency and complexity for a well-understood use case. The
two-PTB requirement is an artifact of Sui's shared-object constraint, not a meaningful
governance safeguard for `execution_delay_ms = 0` types.

### B: `ExternalExecutionCap` for Trading Types

Use `EnableBypassType<PlaceLimitOrder>` etc. to grant single-PTB execution with full
vote bypass. Requires one-time 80% governance vote per trading operation type.

**Why not chosen:** No vote is recorded per-execution. The trading unit's actions
are indistinguishable from a purely bypassed execution in the governance event stream.
This ADR's approach preserves per-execution vote accountability at the cost of the
trading unit needing sufficient voting weight (which, for a solo operator, is trivially
satisfied).

### C: PTB-Level Atomicity with Existing Functions

The caller constructs a PTB that calls `submit_proposal`, then `vote`, then
`ticket_from_vote`, then `execute_<op>`. This appears to be a single PTB but fails:
after `submit_proposal`, the `Proposal<P>` is a shared object. Sui does not allow
a freshly shared object to be accessed again in the same PTB via a mutable reference.

**Why not chosen:** Does not actually work. The shared-object consensus boundary is
an on-chain constraint, not a client-side issue.

---

## Implementation Checklist

- [ ] Add `proposal::create_returning<P>` in `proposal.move` (package-internal), with the `INVARIANT: only callable by submit_vote_execute` comment
- [ ] Add `EDelayForbidsAtomicExecution` and `EInsufficientVotingWeight` error constants in `board_voting.move`
- [ ] Implement `board_voting::submit_vote_execute<P>` with full validation sequence
- [ ] Confirm `submit_vote_execute` is gated behind `#[allow(lint(share_owned, custom_state_change))]`
- [ ] Unit test: single-member board, `PlaceLimitOrder` type, `execution_delay_ms = 0` → ticket returned
- [ ] Unit test: two-member board, quorum=50%, single vote → ticket returned (1 of 2 passes 50% quorum)
- [ ] Unit test: two-member board, quorum=60%, single vote → aborts `EInsufficientVotingWeight`
- [ ] Unit test: type with `execution_delay_ms > 0` → aborts `EDelayForbidsAtomicExecution`
- [ ] Unit test: non-board-member caller → aborts `ENotBoardMember`
- [ ] Unit test: cooldown active → aborts `ECooldownActive`
- [ ] Unit test: emergency freeze active → aborts
- [ ] Unit test: `EnableBypassType` on single-member board → handler `assert_approval_floor_ticket` passes (1/1 ≥ 80%)
- [ ] Unit test: `EnableBypassType` on two-member board, single vote → handler `assert_approval_floor_ticket` fails (1/2 < 80%)
- [ ] Confirm events emitted match standard two-PTB path in integration test
- [ ] Add `submit_vote_execute` to the trading ops integration tests in `armature-trading`
- [ ] Document the required `ProposalConfig` shape for trading types: `execution_delay_ms = 0`, quorum and threshold set to allow the operator's weight
- [ ] Document governance-sensitive types that MUST NOT be configured with `execution_delay_ms = 0` when `submit_vote_execute` is in use
- [ ] Add a note to the `armature_framework` upgrade checklist: any new submission-time floor added to `submit_proposal` must be synced to `submit_vote_execute` (Constraint 7)

---

## Open Questions

1. **`execution_delay_ms = 0` enforcement at config level** — Should governance be
   prevented from setting `execution_delay_ms > 0` on types that are intended for
   atomic execution? The current design relies on the pre-check in `submit_vote_execute`
   aborting at call time. A config-level constraint (e.g., a flag `atomic_only: bool`
   in `ProposalConfig`) would prevent misconfiguration earlier, but adds a new
   constraint dimension. Proposed: leave as-is for now; document the config requirement.

2. **Multi-member atomic voting** — The current design only casts the single caller's
   vote. A variant `submit_votes_execute<P>` that takes a vector of signatures from
   multiple co-signers could allow a multi-sig committee to execute atomically. This
   is out of scope for this ADR but compatible with the `create_returning` primitive.

3. **Composite variant** — Should a `submit_vote_execute_composite` variant exist for
   the composite pipeline? The hot-potato `Pipeline` constraint already forces all steps
   into a single PTB; the only gain would be eliminating the separate `submit_composite`
   call. Deferred.

---

## References

- `armature_framework/sources/proposal.move` — `create`, `vote`, `execute`, `new_ticket_standalone`
- `armature_framework/sources/board_voting.move` — `submit_proposal`, `ticket_from_vote`
- `armature_framework/sources/external_execution.move` — `ticket_from_cap`, `assert_approval_floor_ticket`
- `armature_framework/sources/governance.move` — `board_vote_snapshot`, `is_board_member`
- `armature_framework/sources/dao.move` — `record_execution`, `SUBDAO_BLOCKED_TYPES`
- `ADR_SUBMISSION_TIME_FLOOR_ENFORCEMENT.md` — floor constant definitions and submission-time enforcement
- `ADR_COMPOSABLE_PROPOSALS.md` — composite pipeline design
