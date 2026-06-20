# `ExecutionTicket<P>` Implementation Guide

This document is the engineering reference for the `ExecutionTicket<P>` refactor described in
`unify_invocation.md` and reviewed in `unify_invocation_review.md`. Read those documents first
for motivation and design rationale.

---

## Design Decisions Settled Here

Two questions left open by the review are resolved before any code is written.

**`unpack` vs `borrow/discharge`.** The review preferred a destructuring API where `unpack`
returns `(P, ExecutionRequest<P>, Closeout)` and `close(req, payload, closeout)` finalises
the ticket. That breaks across package boundaries: `Closeout` is `public(package)` (it must
be, to prevent external code from fabricating a unit variant), so `armature_proposals` cannot
receive or pass it.

The chosen API instead is:
- `ticket.ticket_payload()` → `&P` (borrow the payload from the ticket)
- `ticket.ticket_request()` → `&ExecutionRequest<P>` (borrow the request for vault/DAO auth)
- `ticket.discharge()` (consume the ticket, run the closeout logic)

In Move 2024, borrows end at last use. A simple handler that calls the two borrow methods,
passes the references to an `_impl`, then calls `discharge` compiles without issue. For the
handful of handlers with per-branch logic, the same rule applies as long as the borrows are
not live across the `discharge` call — which is true for every existing handler and should be
enforced as a convention.

**`req_dao_id` and `req_proposal_id` visibility.** The review recommended narrowing these to
`public(package)`. This is deferred: the `_impl` functions in `armature_proposals` still call
`request.req_dao_id()` for their DAO ID assertion, and changing every `_impl` to use a
different accessor adds noise without a concrete security benefit. The key surface reduction —
removing `consume_execution_request` — is carried regardless.

---

## 1. New Types and Events (`proposal.move`)

### 1.1 `Proposal<P>`: payload becomes `Option<P>`

```move
public struct Proposal<P: store> has key {
    id: UID,
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    payload: Option<P>,           // was: payload: P
    vote_snapshot: VecMap<address, u64>,
    total_snapshot_weight: u64,
    votes_cast: VecMap<address, bool>,
    yes_weight: u64,
    no_weight: u64,
    config: ProposalConfig,
    created_at_ms: u64,
    passed_at_ms: Option<u64>,
    status: ProposalStatus,
}
```

The `payload()` accessor keeps its current signature (`&P`) and uses `option::borrow`
internally. It panics if called post-execution (payload is `None`). This is correct: no
handler should call `proposal.payload()` after migration — all handlers receive the payload
via the ticket.

```move
public fun payload<P: store>(self: &Proposal<P>): &P {
    self.payload.borrow()
}
```

### 1.2 `ProposalPayloadCreated` event

This event records the full proposal payload at creation time so that the payload is
permanently queryable even after execution sets `Proposal.payload` to `None`.

```move
public struct ProposalPayloadCreated has copy, drop {
    proposal_id: ID,
    dao_id: ID,
    payload_bcs: vector<u8>,   // std::bcs::to_bytes(&payload)
}
```

Emit this event from **both** `proposal::create` (vote path) and from `ticket_from_cap`
(external path — see §3). The vote-path proposal object exists in `Some` state from creation
until execution, so its version history is also queryable, but the event is the canonical
durable record regardless of path.

### 1.3 `ExecutionTicket<P>` and `Closeout`

```move
/// Hot potato — no abilities. Created only by the three framework mint functions.
/// Carries the owned payload and a package-private closeout tag so that
/// `discharge()` can run the correct finalisation logic regardless of which
/// path minted the ticket.
public struct ExecutionTicket<P> {
    request: ExecutionRequest<P>,
    payload: P,
    closeout: Closeout,
}

/// Package-private: external code cannot construct or hold a Closeout value.
/// `Standalone` captures vote-weight data for approval-floor checks.
public(package) enum Closeout has drop {
    Standalone {
        proposal_id: ID,
        yes_weight: u64,
        total_snapshot_weight: u64,
    },
    Composite,
    External,
}
```

### 1.4 Public accessors on `ExecutionTicket<P>`

```move
/// Borrow the payload. Borrow ends at last use; safe to call `discharge` after.
public fun ticket_payload<P>(ticket: &ExecutionTicket<P>): &P {
    &ticket.payload
}

/// Borrow the request for vault/DAO auth calls.
public fun ticket_request<P>(ticket: &ExecutionTicket<P>): &ExecutionRequest<P> {
    &ticket.request
}

/// Shortcut: DAO ID from the embedded request.
public fun ticket_dao_id<P>(ticket: &ExecutionTicket<P>): ID {
    ticket.request.dao_id
}

/// Returns true iff the ticket was minted via the vote path (Closeout::Standalone).
/// Use this to guard handlers that require a governance vote before reading vote weights.
public fun ticket_is_standalone<P>(ticket: &ExecutionTicket<P>): bool {
    match (&ticket.closeout) {
        Closeout::Standalone { .. } => true,
        _ => false,
    }
}

/// Yes weight at vote time. Only valid for Standalone (vote-path) tickets.
/// Aborts with ENotStandaloneTicket for Composite or External tickets.
/// Call ticket_is_standalone() first if the path is not statically known.
public fun ticket_yes_weight<P>(ticket: &ExecutionTicket<P>): u64 {
    match (&ticket.closeout) {
        Closeout::Standalone { yes_weight, .. } => *yes_weight,
        _ => abort ENotStandaloneTicket,
    }
}

/// Total snapshot weight at vote time. Only valid for Standalone tickets.
/// Aborts with ENotStandaloneTicket for Composite or External tickets.
public fun ticket_total_snapshot_weight<P>(ticket: &ExecutionTicket<P>): u64 {
    match (&ticket.closeout) {
        Closeout::Standalone { total_snapshot_weight, .. } => *total_snapshot_weight,
        _ => abort ENotStandaloneTicket,
    }
}

/// Consume the ticket, enforce the path-appropriate closeout, drop the payload.
/// P must have `drop` — all existing payload types satisfy this.
public fun discharge<P: store + drop>(ticket: ExecutionTicket<P>) {
    let ExecutionTicket { request, payload: _, closeout } = ticket;
    match (closeout) {
        Closeout::Standalone { proposal_id, .. } => {
            assert!(request.proposal_id == proposal_id, ERequestMismatch);
            let ExecutionRequest { dao_id: _, proposal_id: _ } = request;
        },
        Closeout::Composite | Closeout::External => {
            let ExecutionRequest { dao_id: _, proposal_id: _ } = request;
        },
    }
}
```

The `Standalone` assertion (`request.proposal_id == closeout.proposal_id`) is strictly
stronger than the old `finalize` status check: it is an unforgeable cross-reference between
the request (created from the vote path) and the specific proposal that authorised it.
`finalize` is removed from the public API.

An additional `discharge_returning_payload<P: store>(ticket) → P` variant is also provided
for payload types that do not have `drop`. This was not in the original spec but is present
in the implementation. It performs the same closeout logic and returns the payload rather than
dropping it, enabling callers to inspect or re-use the payload value after discharge.

### 1.5 Framework-internal ticket constructors

```move
/// Called by board_voting::ticket_from_vote.
public(package) fun new_ticket_standalone<P: store>(
    request: ExecutionRequest<P>,
    payload: P,
    yes_weight: u64,
    total_snapshot_weight: u64,
): ExecutionTicket<P> {
    let proposal_id = request.proposal_id;
    ExecutionTicket {
        request,
        payload,
        closeout: Closeout::Standalone { proposal_id, yes_weight, total_snapshot_weight },
    }
}

/// Called by composite::advance_step.
public(package) fun new_ticket_composite<P>(
    dao_id: ID,
    composite_proposal_id: ID,
    payload: P,
): ExecutionTicket<P> {
    ExecutionTicket {
        request: new_execution_request<P>(dao_id, composite_proposal_id),
        payload,
        closeout: Closeout::Composite,
    }
}

/// Called by external_execution::ticket_from_cap.
public(package) fun new_ticket_external<P>(
    request: ExecutionRequest<P>,
    payload: P,
): ExecutionTicket<P> {
    ExecutionTicket { request, payload, closeout: Closeout::External }
}
```

### 1.6 Changes to `proposal::execute`

`execute` now extracts the payload from `Option<P>` and returns it alongside the request.
Callers (`board_voting::ticket_from_vote`) wrap both into a ticket.

```move
public(package) fun execute<P: store>(
    self: &mut Proposal<P>,
    governance: &GovernanceConfig,
    last_executed_at_ms: Option<u64>,
    execution_paused: bool,
    clock: &Clock,
    ctx: &TxContext,
): (P, ExecutionRequest<P>) {
    assert!(!execution_paused, EExecutionPaused);
    assert!(self.status.is_passed(), ENotPassed);

    let executor = ctx.sender();
    assert!(governance.is_board_member(executor), ENotEligible);

    let now = clock.timestamp_ms();
    let passed_at = self.passed_at_ms.destroy_some();

    if (self.config.execution_delay_ms > 0) {
        assert!(now >= passed_at + self.config.execution_delay_ms, EDelayNotElapsed);
    };

    if (self.config.cooldown_ms > 0) {
        if (last_executed_at_ms.is_some()) {
            let last = last_executed_at_ms.destroy_some();
            assert!(now >= last + self.config.cooldown_ms, ECooldownActive);
        };
    };

    self.status = ProposalStatus::Executed;

    let proposal_id = object::id(self);
    let dao_id = self.dao_id;

    event::emit(ProposalExecuted { proposal_id, dao_id, executor });

    let payload = self.payload.extract();   // leaves None; unforgeable replay protection

    (payload, ExecutionRequest<P> { dao_id, proposal_id })
}
```

### 1.7 Changes to `proposal::create`

Emit `ProposalPayloadCreated` using BCS-serialised bytes before moving the payload into the
`Option`. BCS serialisation happens before the move so we can take a reference.

```move
public(package) fun create<P: store>(
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
) {
    assert!(is_dao_active, EDAONotActive);
    let (vote_snapshot, total_snapshot_weight) = governance.board_vote_snapshot();

    let payload_bcs = std::bcs::to_bytes(&payload);   // serialize before move

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload: option::some(payload),   // wrapped in Option
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

    transfer::share_object(proposal);
}
```

### 1.8 Changes to `proposal::privileged_create`

The external path never stores the payload in the proposal (it goes directly into the ticket).
`privileged_create` is refactored to take no payload; it creates the audit proposal in
`Executed` status with `payload: None` from the start.

The `ProposalPayloadCreated` event for this path is emitted by `ticket_from_cap` (§3) before
the payload is moved into the ticket, so the payload is still serialisable at that point.

```move
#[allow(lint(share_owned, custom_state_change))]
public(package) fun privileged_create<P: store>(
    dao_id: ID,
    type_key: std::ascii::String,
    proposer: address,
    metadata_ipfs: Option<String>,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionRequest<P> {
    let now = clock.timestamp_ms();

    let proposal = Proposal<P> {
        id: object::new(ctx),
        dao_id,
        type_key,
        proposer,
        metadata_ipfs,
        payload: option::none(),          // payload lives in the ticket
        vote_snapshot: vec_map::empty(),
        total_snapshot_weight: 0,
        votes_cast: vec_map::empty(),
        yes_weight: 0,
        no_weight: 0,
        config: new_config(10_000, 10_000, 0, MIN_EXPIRY_MS, 0, 0),
        created_at_ms: now,
        passed_at_ms: option::some(now),
        status: ProposalStatus::Executed,
    };

    let proposal_id = object::id(&proposal);

    event::emit(ProposalCreated { proposal_id, dao_id, type_key, proposer });
    event::emit(ProposalExecuted { proposal_id, dao_id, executor: proposer });

    transfer::share_object(proposal);

    ExecutionRequest<P> { dao_id, proposal_id }
}
```

### 1.9 Removed from `proposal.move` public API

| Symbol | What replaces it |
|---|---|
| `pub fun finalize` | `ticket.discharge()` handles all paths |
| `pub fun consume_execution_request` | `ticket.discharge()` — the only public close-out surface |

`finalize` was called from vote-path handlers and `execute_enable_bypass_type`. After
migration, all handlers call `ticket.discharge()`. `consume_execution_request` is the main
security removal: it allowed any package holding an `ExecutionRequest<P>` to discharge it
without executing anything. Under the new design the close-out variant is baked into the
ticket at mint time by the framework and is not a choice available to handler authors.

`new_execution_request_for_testing` stays (test-only).

### 1.10 `delete_executed_proposal`

Audit proposals created by `privileged_create` (external-path executions) and executed
vote-path proposals both end in the same state: `status = Executed`, `payload = None`.
Neither has a cleanup path, so they accumulate as permanent shared objects. Add a public
function that lets anyone reclaim the storage and collect the Sui storage rebate:

```move
/// Delete an executed proposal whose payload has already been consumed.
/// Safe to call by any party — the audit record is preserved in events
/// (ProposalCreated, ProposalExecuted, ProposalPayloadCreated) regardless.
/// The caller receives the Sui storage rebate.
public fun delete_executed_proposal<P: store + drop>(proposal: Proposal<P>) {
    let Proposal {
        id,
        status,
        payload,
        dao_id: _,
        type_key: _,
        proposer: _,
        metadata_ipfs: _,
        vote_snapshot: _,
        total_snapshot_weight: _,
        votes_cast: _,
        yes_weight: _,
        no_weight: _,
        config: _,
        created_at_ms: _,
        passed_at_ms: _,
    } = proposal;
    assert!(status.is_executed(), ENotExecuted);
    assert!(payload.is_none(), EPayloadNotConsumed);
    object::delete(id);
}
```

The `is_none()` guard is the key safety invariant: it means the payload was extracted by
`proposal::execute` (vote path) or was never stored (external path). A proposal with a live
payload cannot be deleted. The function does not require a capability: the two status
assertions are sufficient because neither can be forged — `status` is only set to `Executed`
inside `proposal::execute` (which enforces `is_passed()` first), and `payload` is only `None`
after extraction or on an external-path audit proposal.

For the external path the typical PTB is:

```move
// 1. execute the action — ticket.discharge() called inside the handler
execute_autojoin_dao(&mut dao, ticket);
// 2. optional same-PTB cleanup — caller collects storage rebate
delete_executed_proposal(audit_proposal);
```

Cleanup can also be deferred to a later transaction; nothing is broken if the object sits
undeleted.

---

## 2. `board_voting.move`: `ticket_from_vote`

Replace `authorize_execution` with `ticket_from_vote`. The return type changes from
`ExecutionRequest<P>` to `ExecutionTicket<P>`. All call sites must update.

```move
/// Replace authorize_execution with this function.
/// All board-voted proposals use this to enter the execution phase.
public fun ticket_from_vote<P: store>(
    dao: &mut DAO,
    prop: &mut Proposal<P>,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): ExecutionTicket<P> {
    let type_key = prop.type_key();
    let is_active = dao.status().is_active();
    let is_migration_ok =
        dao.status().is_migrating() && dao::is_migration_allowed_type(&type_key);
    assert!(is_active || is_migration_ok, EDAONotActive);
    assert!(prop.dao_id() == dao.id(), EDAOIdMismatch);
    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&type_key, clock);

    let last_executed_at = dao.last_executed_at();
    let last_ms = if (last_executed_at.contains(&type_key)) {
        option::some(*last_executed_at.get(&type_key))
    } else {
        option::none()
    };

    let yes_weight = prop.yes_weight();
    let total_snapshot_weight = prop.total_snapshot_weight();

    let (payload, req) = proposal::execute(
        prop,
        dao.governance(),
        last_ms,
        dao.is_execution_paused(),
        clock,
        ctx,
    );

    dao.record_execution(type_key, clock.timestamp_ms());

    proposal::new_ticket_standalone(req, payload, yes_weight, total_snapshot_weight)
}
```

`yes_weight` and `total_snapshot_weight` are read from the proposal before `execute` is
called, since `execute` may modify proposal state. Both values are copied into
`Closeout::Standalone` via `new_ticket_standalone`.

---

## 3. `external_execution.move`: `ticket_from_cap`

Replace `external_executed_create` with `ticket_from_cap`. The `ProposalPayloadCreated`
event is emitted here (before the payload moves into the ticket) to ensure the external-path
payload is permanently recorded.

```move
/// Replace external_executed_create with this function.
pub fun ticket_from_cap<P: store>(
    cap: &ExternalExecutionCap<P>,
    dao: &mut DAO,
    freeze: &EmergencyFreeze,
    type_key: std::ascii::String,
    metadata_ipfs: Option<String>,
    payload: P,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<P> {
    proposal::assert_cap_for_dao(cap, dao.id());
    assert!(dao.status().is_active(), EDAONotActive);
    assert!(dao.enabled_proposal_types().contains(&type_key), ETypeNotEnabled);
    assert!(!dao.is_execution_paused(), EExecutionPaused);
    assert!(!dao.is_controller_paused(), EControllerPaused);
    freeze.assert_not_frozen(&type_key, clock);

    // Type binding is mandatory for all external-path types: every type accessible via
    // ticket_from_cap is created by execute_enable_bypass_type, which always sets a binding.
    // Dropping the conditional means vote-path types (no binding) cannot be executed here
    // even if a cap were somehow fabricated, and a missing binding is a hard error rather
    // than a silently skipped check.
    let actual = type_name::with_defining_ids<P>().into_string();
    assert!(dao.has_type_binding(&type_key), ETypeBindingRequired);
    assert!(dao.type_binding_for(&type_key) == actual, ETypeMismatch);

    let now = clock.timestamp_ms();
    let cooldown_ms = dao.proposal_configs().get(&type_key).cooldown_ms();
    if (cooldown_ms > 0) {
        let last_executed_at = dao.last_executed_at();
        if (last_executed_at.contains(&type_key)) {
            let last = *last_executed_at.get(&type_key);
            assert!(now >= last + cooldown_ms, ECooldownActive);
        };
    };

    dao.record_execution(type_key, now);

    event::emit(ExternalExecutionCreated {
        dao_id: dao.id(),
        type_key,
        submitter: ctx.sender(),
    });

    // Serialize payload BEFORE moving it into the ticket.
    let payload_bcs = std::bcs::to_bytes(&payload);

    let req = proposal::privileged_create<P>(
        dao.id(),
        type_key,
        ctx.sender(),
        metadata_ipfs,
        clock,
        ctx,
    );

    event::emit(proposal::ProposalPayloadCreated {
        proposal_id: req.req_proposal_id(),
        dao_id: dao.id(),
        payload_bcs,
    });

    proposal::new_ticket_external(req, payload)
}
```

Note: `proposal::ProposalPayloadCreated` needs to be accessible from `external_execution`
since they are in the same `armature` package — no visibility issue.

### 3.1 Updated handlers in `external_execution.move`

`execute_enable_bypass_type` no longer receives `&Proposal<EnableBypassType>` or
`ExecutionRequest<EnableBypassType>`. It receives `ExecutionTicket<EnableBypassType>` and
reads vote weights from the ticket for the approval floor check.

```move
pub fun execute_enable_bypass_type<NewType: store>(
    dao: &mut DAO,
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<EnableBypassType>,
    ctx: &mut TxContext,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDAOIdMismatch);
    assert!(vault.dao_id() == dao.id(), EVaultDAOMismatch);

    assert_not_bypass_forbidden<NewType>();
    assert_approval_floor_ticket(&ticket, ENABLE_BYPASS_APPROVAL_FLOOR_BPS);

    let payload = ticket.ticket_payload();
    let type_key = payload.type_key;
    let config = payload.config;

    // Enforce the composability–cooldown mutual exclusion before the config is committed.
    // A bypass type with cooldown_ms > 0 must not be composable: composite pipelines check
    // cooldown against a frozen snapshot and cannot enforce inter-step cooldown.
    // (Same invariant is enforced in admin_ops::assert_config_composability for vote-path types.)
    assert!(
        config.cooldown_ms() == 0 || !config.composable_allowed(),
        EComposableCooldownConflict,
    );

    if (dao.controller_cap_id().is_some()) {
        assert!(!dao::is_subdao_blocked_type(&type_key), ESubDAOBlockedType);
    };

    let req = ticket.ticket_request();
    dao.enable_proposal_type(type_key, config, req);
    dao.bind_type_key<NewType, EnableBypassType>(type_key, req);

    let cap = proposal::new_external_execution_cap<EnableBypassType, NewType>(req, ctx);
    let cap_id = object::id(&cap);
    vault.store_cap(cap, req);

    event::emit(BypassEnabled { dao_id: dao.id(), type_key, cap_id });

    ticket.discharge();
}

pub fun execute_disable_bypass_type<NewType: store>(
    dao: &mut DAO,
    vault: &mut CapabilityVault,
    ticket: ExecutionTicket<DisableBypassType>,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDAOIdMismatch);
    assert!(vault.dao_id() == dao.id(), EVaultDAOMismatch);

    let payload = ticket.ticket_payload();
    let type_key = payload.type_key;
    let cap_id = payload.cap_id;

    assert!(dao.has_type_binding(&type_key), ETypeNotEnabled);
    let expected = type_name::with_defining_ids<NewType>().into_string();
    assert!(dao.type_binding_for(&type_key) == expected, ETypeMismatch);

    let cap_ids = vault.ids_for_type<ExternalExecutionCap<NewType>>();
    assert!(cap_ids.contains(&cap_id), ECapNotFound);

    let req = ticket.ticket_request();
    let cap: ExternalExecutionCap<NewType> = vault.extract_cap(cap_id, req);
    proposal::destroy_external_execution_cap(cap, req);

    dao.disable_proposal_type(type_key, req);

    event::emit(BypassDisabled { dao_id: dao.id(), type_key, cap_id });

    ticket.discharge();
}

// Internal: replaces assert_approval_floor(&Proposal<P>, ...).
// Requires a Standalone ticket — ticket_yes_weight / ticket_total_snapshot_weight abort on
// other paths, so the path check comes first with a clear error.
fun assert_approval_floor_ticket<P>(ticket: &ExecutionTicket<P>, floor_bps: u64) {
    assert!(ticket.ticket_is_standalone(), ENotStandaloneTicket);
    let total = ticket.ticket_total_snapshot_weight();
    assert!(utils::gte_bps(ticket.ticket_yes_weight(), total, floor_bps), EApprovalFloorNotMet);
}
```

The old `assert_approval_floor(proposal: &Proposal<P>, ...)` is removed.

---

## 4. `composite.move`: `advance_step` and `begin_pipeline`

### 4.1 `advance_step` returns `ExecutionTicket<P>`

```move
pub fun advance_step<P: store>(
    dao: &mut DAO,
    frame: &mut CompositeFrame,
    pipeline: Pipeline,
    freeze: &EmergencyFreeze,
    clock: &Clock,
): (ExecutionTicket<P>, Pipeline) {   // was: (P, ExecutionRequest<P>, Pipeline)
    assert!(object::id(frame) == pipeline.frame_id, EFrameMismatch);
    assert!(pipeline.current_step < pipeline.total_steps, EPipelineComplete);

    let step_idx = pipeline.current_step;
    let step_type_key = frame.step_type_keys[step_idx];
    let expected_type = frame.step_types[step_idx];

    assert!(type_name::with_defining_ids<P>() == expected_type, EStepTypeMismatch);

    freeze.assert_not_frozen(&step_type_key, clock);

    let step_config = *dao.proposal_configs().get(&step_type_key);

    // Cooldown-bearing types are prohibited from composites (enforced at config-write time
    // by assert_config_composability). Assert here as defence-in-depth: if a config with
    // cooldown_ms > 0 ever reaches a composite step, abort rather than silently bypass the
    // rate limit via the frozen snapshot.
    assert!(step_config.cooldown_ms() == 0, ECooldownTypeNotComposable);

    dao.record_execution(step_type_key, clock.timestamp_ms());

    let payload: P = df::remove(&mut frame.id, StepKey { index: step_idx });

    let ticket = proposal::new_ticket_composite<P>(
        pipeline.dao_id,
        pipeline.composite_proposal_id,
        payload,
    );

    let Pipeline {
        frame_id, dao_id, composite_proposal_id, current_step: _, total_steps, last_executed_snapshot,
    } = pipeline;

    let next = Pipeline {
        frame_id, dao_id, composite_proposal_id,
        current_step: step_idx + 1,
        total_steps,
        last_executed_snapshot,
    };

    (ticket, next)
}
```

### 4.2 `begin_pipeline` no longer receives `&Proposal<CompositePayload>`

The `CompositePayload` now lives in the ticket after `ticket_from_vote` extracts it.
`begin_pipeline` takes the ticket and reads `frame_id`, step counts, and DAO ID from it.

Two new assertions guard against frame substitution or post-approval mutation (see §4.3):
- `frame.is_sealed()` — the frame was locked at composite proposal creation time.
- `step_type_keys` and `step_types` arrays match what was voted on.

```move
pub fun begin_pipeline(
    dao: &DAO,
    frame: &CompositeFrame,
    ticket: ExecutionTicket<CompositePayload>,  // was: (dao, &proposal, &frame, req)
): Pipeline {
    let payload = ticket.ticket_payload();
    assert!(payload.frame_id == object::id(frame), EFrameMismatch);

    // Verify the frame was sealed at proposal creation and has not been modified since.
    assert!(frame.is_sealed(), EFrameNotSealed);
    assert!(payload.step_type_keys == frame.step_type_keys(), EFrameContentsMismatch);
    assert!(payload.step_types == frame.step_types(), EFrameContentsMismatch);

    let total_steps = payload.step_type_keys.length();
    let last_executed_snapshot = *dao.last_executed_at();
    let dao_id = ticket.ticket_dao_id();
    let composite_proposal_id = ticket.ticket_request().req_proposal_id();

    ticket.discharge();    // consume the composite-level ticket

    Pipeline {
        frame_id: object::id(frame),
        dao_id,
        composite_proposal_id,
        current_step: 0,
        total_steps,
        last_executed_snapshot,
    }
}
```

The `Proposal<CompositePayload>` parameter is gone entirely: the proposal_id comes from the
request embedded in the ticket (`req_proposal_id()` is still public), and the payload (which
held `frame_id`, `step_type_keys`, `step_types`) comes from the ticket directly.

### 4.3 `CompositeFrame` sealing

`CompositeFrame` is a shared object. Without a seal, anyone holding it as `&mut` in a PTB
could modify its dynamic fields (step payloads) between the governance vote and pipeline
execution, causing the executed steps to differ from what board members approved.

Add a `sealed: bool` field and the corresponding accessors. A frame is created unsealed,
populated with step payloads, then sealed exactly once when the composite proposal is
created. After sealing, all public write operations on the frame abort.

```move
public struct CompositeFrame has key {
    id: UID,
    sealed: bool,              // set to true when the proposal is created; never unset
    steps_extracted: u64,      // incremented by advance_step; checked by delete_exhausted_frame
    step_type_keys: vector<std::ascii::String>,
    step_types: vector<TypeName>,
}

/// Returns true after seal_frame has been called. Used by begin_pipeline.
public fun is_sealed(frame: &CompositeFrame): bool {
    frame.sealed
}

/// Expose the type-key and type arrays for content verification in begin_pipeline.
public fun step_type_keys(frame: &CompositeFrame): vector<std::ascii::String> {
    frame.step_type_keys
}
public fun step_types(frame: &CompositeFrame): vector<TypeName> {
    frame.step_types
}

/// Called once during composite proposal creation. Irreversible.
public(package) fun seal_frame(frame: &mut CompositeFrame) {
    assert!(!frame.sealed, EFrameAlreadySealed);
    frame.sealed = true;
}
```

Every existing public function that writes to the frame (adding step payloads, modifying
step metadata) must gain a `assert!(!frame.sealed, EFrameAlreadySealed)` guard. The
framework's own `advance_step` uses `df::remove` on `frame.id`, which is permitted because
`advance_step` holds `&mut CompositeFrame` obtained through the pipeline's authorization
chain — not through a public write accessor.

**Sealing security dependency: `id: UID` must not be publicly accessible as `&mut`.**
`df::add` and `df::remove` take `&mut UID` directly, bypassing any seal check. If the
`id` field were exposed publicly — or if `CompositeFrame` provided a `uid_mut()` accessor —
a caller could mutate dynamic fields after sealing without touching the frame's write API.
The `composite` module must not expose `&mut UID` externally. `object::uid_to_inner` (which
yields `&ID`, not `&mut UID`) is safe to expose; a `uid_mut` accessor is not.

The required creation sequence is:

```
1. Create CompositeFrame (sealed = false, steps_extracted = 0)
2. Add all step payloads via the frame's write API
3. Call composite::seal_frame(&mut frame)                 ← frame is now immutable to callers
4. Create the CompositeProposal referencing frame.id
5. board members vote; proposal passes
6. begin_pipeline(&dao, &frame, ticket)                  ← asserts is_sealed()
7. N × advance_step + handler (increments steps_extracted each time)
8. finalize_pipeline(pipeline)
9. delete_exhausted_frame(frame)                          ← asserts steps_extracted == step_type_keys.length()
```

Attempting to add or replace a step payload after step 3 aborts with `EFrameAlreadySealed`.
`delete_exhausted_frame` reclaims storage; omitting it is safe but accumulates storage debt.
The canonical pattern is to include it in the same PTB as the last `advance_step` + `finalize_pipeline`.

---

## 5. Handler Migration in `armature_proposals`

Every handler follows the same mechanical pattern:

**Before:**
```move
pub fun execute_foo(
    dao: &mut DAO,
    proposal: &Proposal<Foo>,
    request: ExecutionRequest<Foo>,
) {
    foo_impl(dao, proposal.payload(), &request);
    proposal::finalize(request, proposal);
}

pub fun execute_foo_step(dao: &mut DAO, payload: Foo, request: ExecutionRequest<Foo>) {
    foo_impl(dao, &payload, &request);
    proposal::consume_execution_request(request);
}
```

**After (unified):**
```move
pub fun execute_foo(dao: &mut DAO, ticket: ExecutionTicket<Foo>) {
    foo_impl(dao, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}
// execute_foo_step is deleted.
```

The `_impl` function signature is unchanged: it still takes `(&Foo, &ExecutionRequest<Foo>)`.
The `execute_foo` function now borrows both from the ticket, passes them to `_impl`, then
discharges. The borrows end at last use (after `_impl` returns), so `discharge()` sees no
live borrows.

### 5.1 `member_ops.move`

```move
pub fun execute_add_member(dao: &mut DAO, ticket: ExecutionTicket<AddMember>) {
    add_member_impl(dao, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}
// execute_add_member_step — DELETE

pub fun execute_batch_add_members(dao: &mut DAO, ticket: ExecutionTicket<BatchAddMembers>) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    let payload = ticket.ticket_payload();
    let members = payload.members();
    let len = members.length();
    assert!(len > 0, EEmptyBatch);
    assert!(len <= MAX_BATCH_SIZE, EBatchTooLarge);
    let (added, skipped) = dao.add_board_members_governance(*members, ticket.ticket_request());
    event::emit(MembersBatchAdded { dao_id: dao.id(), added, skipped });
    ticket.discharge();
}

pub fun execute_remove_member(dao: &mut DAO, ticket: ExecutionTicket<RemoveMember>) {
    remove_member_impl(dao, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}
// execute_remove_member_step — DELETE
```

`add_member_impl` and `remove_member_impl` are unchanged.

### 5.2 `board_ops.move`

```move
pub fun execute_set_board(dao: &mut DAO, ticket: ExecutionTicket<SetBoard>) {
    set_board_impl(dao, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}
// execute_set_board_step — DELETE
```

`set_board_impl` is unchanged.

### 5.3 `admin_ops.move`

`assert_config_composability` is a new private helper that enforces the invariant:
a config with `cooldown_ms > 0` must not be composable. It is called at every point a
`ProposalConfig` is written to DAO state. The same rule is enforced in
`external_execution::execute_enable_bypass_type` (§3.1) and as defence-in-depth in
`composite::advance_step` (§4.1).

```move
fun assert_config_composability(config: &ProposalConfig) {
    // Composite pipelines check cooldown against a frozen pre-pipeline snapshot and cannot
    // enforce inter-step cooldown. Disallow the combination at the config level.
    assert!(
        config.cooldown_ms() == 0 || !config.composable_allowed(),
        EComposableCooldownConflict,
    );
}

pub fun execute_disable_proposal_type(
    dao: &mut DAO,
    ticket: ExecutionTicket<DisableProposalType>,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    let type_key = ticket.ticket_payload().type_key();
    assert_disableable(&type_key);
    dao.disable_proposal_type(type_key, ticket.ticket_request());
    event::emit(ProposalTypeDisabled { dao_id: dao.id(), type_key });
    ticket.discharge();
}

pub fun execute_enable_proposal_type<NewType: store>(
    dao: &mut DAO,
    ticket: ExecutionTicket<EnableProposalType>,
) {
    // assert_config_composability is called inside enable_proposal_type_impl before
    // the config is committed to DAO state.
    enable_proposal_type_impl<NewType>(dao, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}
// execute_enable_proposal_type_step — DELETE

pub fun execute_update_proposal_config(
    dao: &mut DAO,
    ticket: ExecutionTicket<UpdateProposalConfig>,
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    let payload = ticket.ticket_payload();
    let target_key = payload.target_type_key();
    let existing = dao.proposal_configs().get(&target_key);
    let new_config = proposal::new_config(
        payload.quorum().destroy_with_default(existing.quorum()),
        payload.approval_threshold().destroy_with_default(existing.approval_threshold()),
        payload.propose_threshold().destroy_with_default(existing.propose_threshold()),
        payload.expiry_ms().destroy_with_default(existing.expiry_ms()),
        payload.execution_delay_ms().destroy_with_default(existing.execution_delay_ms()),
        payload.cooldown_ms().destroy_with_default(existing.cooldown_ms()),
    ).with_composable_allowed(
        payload.composable_allowed().destroy_with_default(existing.composable_allowed()),
    );
    assert_threshold_meets_floor(&target_key, &new_config);
    assert_config_composability(&new_config);
    dao.update_proposal_config(target_key, new_config, ticket.ticket_request());
    event::emit(ProposalConfigUpdated { dao_id: dao.id(), target_type_key: target_key });
    ticket.discharge();
}

pub fun execute_update_metadata(
    charter: &mut Charter,
    ticket: ExecutionTicket<UpdateMetadata>,
) {
    update_metadata_impl(charter, ticket.ticket_payload(), ticket.ticket_request());
    ticket.discharge();
}
// execute_update_metadata_step — DELETE
```

`enable_proposal_type_impl` gains a call to `assert_config_composability` before committing
the config. `update_metadata_impl` is unchanged.

### 5.4 `treasury_ops.move`

```move
pub fun execute_send_coin<T>(
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    send_coin_impl(vault, ticket.ticket_payload(), ticket.ticket_request(), ctx);
    ticket.discharge();
}
// execute_send_coin_step — DELETE

pub fun execute_send_coin_to_dao<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendCoinToDAO<T>>,
    ctx: &mut TxContext,
) {
    send_coin_to_dao_impl(
        source_vault, target_vault,
        ticket.ticket_payload(), ticket.ticket_request(), ctx,
    );
    ticket.discharge();
}
// execute_send_coin_to_dao_step — DELETE

pub fun execute_send_small_payment<T>(
    dao: &mut DAO,
    vault: &mut TreasuryVault,
    ticket: ExecutionTicket<SendSmallPayment<T>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == ticket.ticket_dao_id(), EVaultDAOMismatch);
    let payload = ticket.ticket_payload();
    let req = ticket.ticket_request();
    let now = clock.timestamp_ms();

    if (!dao.has_type_state<SendSmallPayment<T>>()) {
        let balance = vault.balance<T>();
        let max_spend = utils::mul_bps(balance, send_small_payment::default_spend_limit_bps());
        dao.init_type_state(
            send_small_payment::new_state(
                now, 0, max_spend,
                send_small_payment::default_epoch_duration_ms(),
                send_small_payment::default_spend_limit_bps(),
            ),
            req,
        );
    };

    let state: &mut SmallPaymentState = dao.borrow_type_state_mut(req);

    if (now >= state.epoch_start_ms() + state.epoch_duration_ms()) {
        let balance = vault.balance<T>();
        let new_max = utils::mul_bps(balance, state.spend_limit_bps());
        state.reset_epoch(now, new_max);
    };

    assert!(state.epoch_spend() + payload.amount() <= state.max_epoch_spend(), EExceedsDailyCap);
    state.add_epoch_spend(payload.amount());

    let coin = vault.withdraw<T, SendSmallPayment<T>>(payload.amount(), req, ctx);

    event::emit(SmallPaymentSent {
        dao_id: vault.dao_id(),
        coin_type: std::type_name::with_original_ids<T>().into_string(),
        amount: payload.amount(),
        recipient: payload.recipient(),
        epoch_spend: state.epoch_spend(),
        max_epoch_spend: state.max_epoch_spend(),
    });

    transfer::public_transfer(coin, payload.recipient());

    ticket.discharge();
}
```

`send_coin_impl` and `send_coin_to_dao_impl` are unchanged.

### 5.5 `currency_ops.move`, `security_ops.move`, `upgrade_ops.move`, `subdao_ops.move`

All follow the identical mechanical transformation. For each handler:
1. Replace `(proposal: &Proposal<P>, request: ExecutionRequest<P>)` with
   `(ticket: ExecutionTicket<P>)`.
2. Replace `proposal.payload()` with `ticket.ticket_payload()`.
3. Replace `&request` with `ticket.ticket_request()`.
4. Replace `proposal::finalize(request, proposal)` with `ticket.discharge()`.

### 5.6 `subdao_ops.move`: `validate_transfer_assets` / `finalize_transfer_assets`

`TransferAssets` has a multi-step PTB pattern where the ticket must stay live across
several typed vault operations between `validate_transfer_assets` and
`finalize_transfer_assets`. This maps cleanly onto the ticket model.

```move
/// Validate the proposal and emit the event. Borrows the ticket so the caller
/// can compose typed withdraw/extract calls (all borrowing ticket.ticket_request())
/// before calling finalize_transfer_assets to consume the ticket.
///
/// PTB flow:
///   1. ticket_from_vote(dao, &mut proposal, freeze, clock, ctx) → ExecutionTicket<TransferAssets>
///   2. validate_transfer_assets(..., &ticket)
///   3. N × source_treasury.withdraw<T>(amount, ticket.ticket_request(), ctx)
///   4. N × source_vault.extract_cap<T>(cap_id, ticket.ticket_request())
///   5. finalize_transfer_assets(ticket)
pub fun validate_transfer_assets(
    source_treasury: &TreasuryVault,
    source_cap_vault: &CapabilityVault,
    target_treasury: &TreasuryVault,
    target_cap_vault: &CapabilityVault,
    ticket: &ExecutionTicket<TransferAssets>,   // was: &Proposal + &ExecutionRequest
) {
    let request = ticket.ticket_request();
    let payload = ticket.ticket_payload();

    assert!(source_treasury.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(source_cap_vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    assert!(object::id(target_treasury) == payload.target_treasury_id(), ETargetTreasuryMismatch);
    assert!(object::id(target_cap_vault) == payload.target_vault_id(), ETargetVaultMismatch);
    assert!(target_treasury.dao_id() == payload.target_dao_id(), ETargetDAOMismatch);
    assert!(target_cap_vault.dao_id() == payload.target_dao_id(), ETargetDAOMismatch);
    assert!(
        payload.coin_types().length() + payload.cap_ids().length() <= MAX_TRANSFER_ASSETS,
        EAssetLimitExceeded,
    );

    event::emit(AssetsTransferInitiated {
        dao_id: source_treasury.dao_id(),
        target_dao_id: payload.target_dao_id(),
        coin_count: payload.coin_types().length(),
        cap_count: payload.cap_ids().length(),
    });
}

pub fun finalize_transfer_assets(ticket: ExecutionTicket<TransferAssets>) {
    ticket.discharge();
}
```

The borrow discipline here: `validate_transfer_assets` borrows the ticket by reference
(`&ticket`), reads from it, returns. Between steps 2 and 5, the caller borrows
`ticket.ticket_request()` for each vault operation — those borrows also end at each use.
`finalize_transfer_assets` then consumes `ticket` with `discharge()`. No borrow of the
ticket survives into `discharge`.

---

## 6. `armature_world_bridge`: `autojoin_ops.move`

### 6.1 `submit_autojoin`

Returns `ExecutionTicket<AutojoinDAO>` instead of `ExecutionRequest<AutojoinDAO>`.

```move
pub fun submit_autojoin(
    members_dao: &mut DAO,
    members_vault: &CapabilityVault,
    freeze: &EmergencyFreeze,
    cap_id: ID,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
): ExecutionTicket<AutojoinDAO> {    // was: ExecutionRequest<AutojoinDAO>
    // ... all existing validation unchanged ...

    external_execution::ticket_from_cap<AutojoinDAO>(
        cap,
        members_dao,
        freeze,
        b"AutojoinDAO".to_ascii_string(),
        option::none(),
        AutojoinDAO {
            character_id: object::id(character),
            owner_id,
            joining_address: sender,
        },
        clock,
        ctx,
    )
}
```

### 6.2 `execute_autojoin_dao`

```move
pub fun execute_autojoin_dao(
    dao: &mut DAO,
    ticket: ExecutionTicket<AutojoinDAO>,    // was: &Proposal + ExecutionRequest
) {
    assert!(dao.id() == ticket.ticket_dao_id(), EDaoMismatch);
    let payload = ticket.ticket_payload();

    assert!(dao.has_type_state<ConfigureAutojoin>(), EAllowlistNotInitialized);
    let allowlist: &TribeIdAllowlist =
        dao.borrow_type_state<ConfigureAutojoin, TribeIdAllowlist>();
    assert!(allowlist.is_enabled(), EAutojoinDisabled);
    assert!(allowlist.contains(payload.owner_id), ETribeIdNotAllowed);

    dao.add_board_member_governance(payload.joining_address, ticket.ticket_request());

    event::emit(MemberAutojoined {
        dao_id: dao.id(),
        member: payload.joining_address,
        owner_id: payload.owner_id,
        character_id: payload.character_id,
    });

    ticket.discharge();
}
```

The `&Proposal<AutojoinDAO>` parameter is gone. The payload was moved into the ticket by
`ticket_from_cap`; `execute_autojoin_dao` reads it from there.

### 6.3 Autojoin PTB with audit proposal cleanup

Every autojoin creates a shared audit `Proposal<AutojoinDAO>` via `privileged_create`. For
DAOs with high autojoin volume this accumulates unbounded chain state. The canonical PTB
includes an optional same-transaction cleanup step that reclaims the storage rebate:

```move
// 1. Mint the ticket (creates the audit proposal as a side-effect).
let ticket = autojoin_ops::submit_autojoin(
    &mut members_dao, &members_vault, &freeze, cap_id, &character, &clock, ctx,
);

// 2. Execute — ticket.discharge() called internally.
autojoin_ops::execute_autojoin_dao(&mut members_dao, ticket);

// 3. Delete the now-empty audit proposal; caller collects storage rebate.
// Omitting this is safe but accumulates storage debt — include it as standard practice.
proposal::delete_executed_proposal(audit_proposal);
```

`audit_proposal` is the shared `Proposal<AutojoinDAO>` object created by step 1. The caller
passes it by value in the same PTB. This deletion is the **canonical pattern**: not including
it leaves a permanently-executed proposal object on-chain. While nothing breaks, the storage
debt accumulates and the pattern is considered incomplete.

---

## 7. API Surface Changes

### Removed from the public API

| Symbol | Package | Reason |
|---|---|---|
| `proposal::finalize` | `armature` | Subsumed by `ticket.discharge()` |
| `proposal::consume_execution_request` | `armature` | Closed the "execute nothing" escape hatch |
| `board_voting::authorize_execution` | `armature` | Replaced by `ticket_from_vote` |
| `external_execution::external_executed_create` | `armature` | Replaced by `ticket_from_cap` |
| 7 × `execute_*_step` handlers | `armature_proposals` | Replaced by unified `execute_*` |

### New public API

| Symbol | Package | Description |
|---|---|---|
| `proposal::ExecutionTicket<P>` | `armature` | The unified execution hot potato |
| `proposal::ProposalPayloadCreated` | `armature` | Payload-recording event |
| `proposal::ticket_payload` | `armature` | Borrow payload from ticket |
| `proposal::ticket_request` | `armature` | Borrow request from ticket |
| `proposal::ticket_dao_id` | `armature` | DAO ID shortcut |
| `proposal::ticket_yes_weight` | `armature` | Vote weight for floor checks |
| `proposal::ticket_total_snapshot_weight` | `armature` | Vote weight for floor checks |
| `proposal::discharge` | `armature` | Consume ticket, enforce closeout |
| `proposal::ticket_is_standalone` | `armature` | Returns true for vote-path tickets; use before reading vote weights |
| `proposal::delete_executed_proposal` | `armature` | Clean up an executed proposal; caller collects storage rebate |
| `board_voting::ticket_from_vote` | `armature` | Vote-path ticket mint |
| `external_execution::ticket_from_cap` | `armature` | External-path ticket mint |
| `composite::seal_frame` | `armature` | Lock a CompositeFrame after population; must be called before proposal creation |
| `composite::is_sealed` | `armature` | Query seal state; used by begin_pipeline |
| `composite::step_type_keys` | `armature` | Read-only accessor for content verification |
| `composite::step_types` | `armature` | Read-only accessor for content verification |
| `composite::delete_exhausted_frame` | `armature` | Destroy a CompositeFrame after all steps have been advanced; caller collects storage rebate |

### New error codes

| Code | Module | Meaning |
|---|---|---|
| `EComposableCooldownConflict` | `external_execution`, `admin_ops` | Config sets `cooldown_ms > 0` and `composable_allowed = true` simultaneously |
| `ECooldownTypeNotComposable` | `composite` | Defence-in-depth: a step type with `cooldown_ms > 0` reached `advance_step` |
| `EPayloadNotConsumed` | `proposal` | `delete_executed_proposal` called on a proposal whose payload has not been extracted |
| `ETypeBindingRequired` | `external_execution` | `ticket_from_cap` called for a type key that has no type binding |
| `ENotStandaloneTicket` | `proposal` | `ticket_yes_weight` or `ticket_total_snapshot_weight` called on a non-vote-path ticket |
| `EFrameNotSealed` | `composite` | `begin_pipeline` called with an unsealed frame |
| `EFrameAlreadySealed` | `composite` | Frame write operation attempted after `seal_frame` |
| `EFrameContentsMismatch` | `composite` | Frame's `step_type_keys` or `step_types` do not match the voted-on payload |

### Structural narrowing (no API removal, but stronger invariants)

`composite::advance_step` previously returned `(P, ExecutionRequest<P>, Pipeline)`. Any PTB
caller holding the bare `ExecutionRequest<P>` could pass it to the wrong handler or call
`consume_execution_request` to discharge without executing. Returning `ExecutionTicket<P>`
means the request is only reachable via `ticket.ticket_request()` as a borrow. The only way
to resolve the ticket is to call a type-matched handler that calls `discharge`.

`composite::begin_pipeline` no longer takes `&Proposal<CompositePayload>` — the composite
proposal is not passed through to PTB callers as a live object reference, reducing the
PTB surface for composite execution.

---

## 8. Test Migration

### 8.1 Vote-path tests

Replace every occurrence of:
```move
let request = board_voting::authorize_execution(&mut dao, &mut proposal, &freeze, &clock, &ctx);
handler::execute_foo(&mut dao, &proposal, request);
```
with:
```move
let ticket = board_voting::ticket_from_vote(&mut dao, &mut proposal, &freeze, &clock, &ctx);
handler::execute_foo(&mut dao, ticket);
```

### 8.2 Composite-path tests

Replace:
```move
let request = board_voting::authorize_execution(...);
let pipeline = composite::begin_pipeline(&dao, &proposal, &frame, request);
let (payload, req, pipeline) = composite::advance_step<AddMember>(..., pipeline, ...);
member_ops::execute_add_member_step(&mut dao, payload, req);
composite::finalize_pipeline(pipeline);
```
with:
```move
let ticket = board_voting::ticket_from_vote(...);
let pipeline = composite::begin_pipeline(&dao, &frame, ticket);   // no &proposal
let (step_ticket, pipeline) = composite::advance_step<AddMember>(..., pipeline, ...);
member_ops::execute_add_member(&mut dao, step_ticket);
composite::finalize_pipeline(pipeline);
```

### 8.3 External-path tests (including `autojoin_ops`)

Replace:
```move
let request = external_execution::external_executed_create(cap, ...);
handler::execute_foo(&mut dao, &proposal, request);
```
with:
```move
let ticket = external_execution::ticket_from_cap(cap, ...);
handler::execute_foo(&mut dao, ticket);
```

### 8.4 New tests to add

For each proposal type, add a test that exercises the same type through all three paths
using the same `execute_*` handler. The canonical form:

```move
// 1. Vote path
let ticket = board_voting::ticket_from_vote(...);
handler::execute_foo(&mut dao, ticket);

// 2. Composite path (in a separate composite test)
let (step_ticket, pipeline) = composite::advance_step<Foo>(...);
handler::execute_foo(&mut dao, step_ticket);

// 3. External path (where applicable)
let ticket = external_execution::ticket_from_cap(cap, ..., payload, ...);
handler::execute_foo(&mut dao, ticket);
```

Verify that the same `execute_foo` function is called in all three cases.

---

## 9. Migration Order

The migration can land additively with no flag-day because `ticket_from_vote` /
`ticket_from_cap` / `advance_step` (new returns) can coexist with the old API until all
call sites are updated.

1. **`proposal.move`** — add `ExecutionTicket<P>`, `Closeout`, all accessors,
   `discharge`, the three `new_ticket_*` constructors, `ProposalPayloadCreated` event.
   Change `Proposal.payload` to `Option<P>`. Change `proposal::execute` to return
   `(P, ExecutionRequest<P>)`. Change `proposal::create` to emit the payload event.
   Change `proposal::privileged_create` to take no payload. Keep `finalize` and
   `consume_execution_request` as deprecated stubs for now (remove in step 5).

2. **`board_voting.move`** — add `ticket_from_vote`. Keep `authorize_execution` as a
   deprecated shim that internally calls `ticket_from_vote` and immediately unpacks to the
   old `ExecutionRequest<P>` (for transitional compatibility if needed).

3. **`external_execution.move`** — add `ticket_from_cap`. Keep `external_executed_create`
   as a deprecated shim.

4. **`composite.move`** — change `advance_step` return type to
   `(ExecutionTicket<P>, Pipeline)`. Change `begin_pipeline` to take
   `ExecutionTicket<CompositePayload>` and remove the `&Proposal<CompositePayload>` param.

5. **`armature_proposals`** — migrate all handlers one file at a time. Delete all
   `_step` twins. After the last file is done, remove the deprecated shims from steps 2–3
   and remove `finalize` and `consume_execution_request` from `proposal.move`.

6. **`armature_world_bridge`** — migrate `autojoin_ops.move`.

7. **Tests** — update all test files to the new PTB patterns. Add the cross-path tests
   described in §8.4.

---

## 10. Acceptance Checklist

- [x] One `execute_*` handler per proposal type; no `_step` twins remain.
- [x] `proposal::consume_execution_request` is removed from the public API.
- [x] `proposal::finalize` is removed from the public API.
- [x] `board_voting::authorize_execution` is removed (or is a clearly deprecated shim).
- [x] `external_execution::external_executed_create` is removed (or is a clearly deprecated shim).
- [x] `composite::advance_step` returns `(ExecutionTicket<P>, Pipeline)`.
- [x] `composite::begin_pipeline` takes `ExecutionTicket<CompositePayload>` with no `&Proposal<CompositePayload>`.
- [x] `ProposalPayloadCreated` event is emitted for every proposal creation path (vote and external).
- [x] A newly added proposal type with only `execute_*` is immediately usable in all three paths with zero composition-specific code (subject to `composable_allowed = true`).
- [x] Pre-migration config audit (§9 step 0) completed: no live DAO has a stored config with `cooldown_ms > 0` and `composable_allowed = true`.
- [x] `assert_config_composability` is called in `enable_proposal_type_impl`, `execute_update_proposal_config`, and `execute_enable_bypass_type`; no config with `cooldown_ms > 0` and `composable_allowed = true` can be stored.
- [x] `composite::advance_step` asserts `step_config.cooldown_ms() == 0` with `ECooldownTypeNotComposable`; the old snapshot-based cooldown block is removed.
- [x] `proposal::delete_executed_proposal` exists and is covered by tests confirming it (a) succeeds for `Executed + None` proposals, (b) aborts for non-executed proposals, and (c) aborts when `payload.is_some()`.
- [x] `ticket_from_cap` checks `dao.has_type_binding` unconditionally before the type-name comparison; `ETypeBindingRequired` aborts if no binding exists.
- [x] `ticket_yes_weight` and `ticket_total_snapshot_weight` abort with `ENotStandaloneTicket` for non-Standalone tickets (no longer return 0).
- [x] `ticket_is_standalone` accessor exists and is used as the first guard in `assert_approval_floor_ticket`.
- [x] `CompositeFrame` has a `sealed: bool` field; `seal_frame` is `public(package)`; all frame write operations assert `!frame.sealed`.
- [x] Composite proposal creation calls `seal_frame` before creating the proposal object; tests confirm a frame cannot be modified after sealing.
- [x] `begin_pipeline` asserts `frame.is_sealed()`, `payload.step_type_keys == frame.step_type_keys()`, and `payload.step_types == frame.step_types()`; tests confirm mismatched or unsealed frames are rejected.
- [x] Full test suite passes.
- [x] New cross-path tests cover at least one type exercised via vote, composite, and external cap through the same handler.
