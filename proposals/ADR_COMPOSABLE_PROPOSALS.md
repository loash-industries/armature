# ADR: Composable Multi-Action Proposals

| Field        | Value                                |
| ------------ | ------------------------------------ |
| **Status**   | Proposed                             |
| **Date**     | 2026-05-13                           |
| **Authors**  | —                                    |
| **Package**  | `armature_framework` / `armature_proposals` |

---

## Context

Today every Armature proposal is parameterized by a single payload type `P`:

```move
struct Proposal<P: store> has key { … payload: P, … }
```

An `ExecutionRequest<phantom P>` hot potato binds execution to exactly one handler.
This means each governance action — send coins, add a member, update metadata — is a
separate proposal with its own vote, quorum, delay, and execution step.

**Real-world governance frequently needs atomic bundles:**

- "Add Alice to the board **and** remove Bob" (single vote, atomic swap)
- "Fund SubDAO treasury with 10 000 SUI **and** transfer an `UpgradeCap` to its vault"
- "Update metadata **and** enable a new proposal type **and** adjust config"
- "Spend from treasury **and** pause a SubDAO's execution"

Forcing each action into a separate proposal creates UX friction, race-condition
windows between sequential proposals, and non-atomic state transitions that can
leave the DAO in an inconsistent intermediate state.

This ADR evaluates several approaches to composable, multi-action proposals within
the constraints of the Move type system and the existing Armature framework.

---

## Constraints & Invariants

Any solution must respect:

1. **Move single-type-parameter constraint** — `Proposal<P>` has one generic slot.
2. **Hot-potato atomicity** — `ExecutionRequest<P>` has no `drop`/`store`; it must be
   consumed in the same PTB.
3. **Type-key binding security** — the framework's `type_bindings` map prevents type
   spoofing; new patterns must not weaken this.
4. **Approval-floor enforcement** — certain action types enforce hardcoded supermajority
   floors at execution time; composable proposals must still honour these.
5. **Shared-object contention** — `&mut DAO`, `&mut TreasuryVault`, and
   `&mut CapabilityVault` are separate shared objects to reduce lock pressure;
   multi-action execution must not serialize unnecessarily.
6. **Permissionless finalization** — `proposal::finalize()` validates `dao_id`,
   `proposal_id`, and status; the consumption path must remain auditable.
7. **Backwards compatibility** — existing single-action proposal types, their configs,
   and deployed handler modules must continue to work unchanged.

---

## Option A: Envelope Payload with Heterogeneous Action Vector

### Idea

Introduce a new framework-level payload type `ComposablePayload` that wraps an
ordered list of **type-erased actions** using `sui::dynamic_field`:

```move
/// Framework-level envelope stored as Proposal<ComposablePayload>.
struct ComposablePayload has store {
    action_count: u64,
    // Each action stored as a dynamic field keyed by index:
    //   df::add(&mut id, idx, ActionWrapper<P_i> { payload })
    action_keys: UID,
}

/// Wrapper that lets us store heterogeneous payloads as dynamic fields.
struct ActionWrapper<P: store> has store {
    type_key: ascii::String,
    payload: P,
}
```

A single `Proposal<ComposablePayload>` is created. At execution time, the handler
iterates through the action list and dispatches each one.

### Execution Flow

```
1.  Proposer builds ComposablePayload with N actions.
    Each action is added as a dynamic field: df::add(&mut cp.action_keys, 0u64, ActionWrapper<AddMember> { … })
2.  board_voting::submit_proposal<ComposablePayload>(dao, "Composable", payload, …)
3.  Voting proceeds normally on the single proposal.
4.  Executor calls authorize_execution → ExecutionRequest<ComposablePayload>
5.  A new composable_ops::execute_composable() handler:
    a. Extracts action 0 → dispatches to board_ops handler (via a match on type_key)
    b. Extracts action 1 → dispatches to treasury_ops handler
    c. …
    d. Calls proposal::finalize(request, proposal)
```

### Dispatch Problem

Move lacks runtime dynamic dispatch. The handler cannot call an arbitrary `execute_*`
function based on a string `type_key`. Instead, the dispatch must be **statically
enumerated** in the composable handler:

```move
public fun execute_composable(
    dao: &mut DAO,
    treasury: &mut TreasuryVault,
    cap_vault: &mut CapabilityVault,
    proposal: &mut Proposal<ComposablePayload>,
    request: ExecutionRequest<ComposablePayload>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let cp = proposal.payload_mut();
    let mut i = 0;
    while (i < cp.action_count) {
        let type_key = action_type_key_at(cp, i);
        if (type_key == b"AddMember".to_ascii_string()) {
            let wrapper: ActionWrapper<AddMember> = df::remove(&mut cp.action_keys, i);
            // inline execution or call board_ops internally
            dao.add_member(wrapper.payload.member(), …);
        } else if (type_key == b"SendCoin".to_ascii_string()) {
            // …
        }
        // every supported type must be statically listed here
        i = i + 1;
    };
    proposal::finalize(request, proposal);
}
```

### Pros

- **Single vote** for an atomic bundle of N actions.
- **Single `ExecutionRequest`** — clean hot-potato lifecycle.
- **Atomic execution** — all-or-nothing within one PTB.
- **Minimal framework changes** — `ComposablePayload` is just another payload type.

### Cons

- **Static dispatch explosion** — every permissible sub-action must be hard-coded in the
  composable handler. Adding a new proposal type requires updating the dispatch table.
  This is the primary engineering burden.
- **`payload_mut` or dynamic field access** — the composable handler needs mutable access
  to extract dynamic fields, which may conflict with `Proposal` being immutably borrowed
  elsewhere. Requires `&mut Proposal` or a separate extraction pattern.
- **Approval floor bypass risk** — a `ComposablePayload` proposal uses a single
  `ProposalConfig`. If one sub-action normally requires an 80% floor (e.g.,
  `UpdateProposalConfig` self-update), the composable vote might only require 51%.
  **Mitigation:** the dispatch loop must enforce per-action approval floors.
- **Type-key binding tension** — the proposal's outer type is `ComposablePayload`, but
  inner actions have their own type keys. The existing `type_bindings` map only validates
  the outer type. Inner action validation must be handled separately.
- **Object contention** — the handler must accept `&mut DAO`, `&mut TreasuryVault`, and
  `&mut CapabilityVault` simultaneously, even if only one sub-action needs each. This
  increases shared-object lock contention.

### Verdict

Workable but brittle. The static dispatch table becomes a maintenance bottleneck,
and approval-floor enforcement requires careful per-action checking.

---

## Option B: Action Receipt Chain (Multi-Hot-Potato Pipeline)

### Idea

Keep the existing single-action proposal type system but allow a **single PTB** to
execute multiple proposals atomically by chaining their `ExecutionRequest` hot potatoes.
Introduce a new `ComposableBatch` receipt that enforces all-or-nothing semantics:

```move
/// Created by the first action in a batch. Must be sealed after the last.
struct ComposableBatch {
    dao_id: ID,
    expected_count: u64,
    executed_count: u64,
    proposal_ids: vector<ID>,
}
```

### Execution Flow

```
PTB:
  1. batch = composable::begin_batch(dao, expected_count=3)

  2. req_1 = board_voting::authorize_execution(dao, proposal_add_alice, freeze, clock)
     board_ops::execute_add_member(dao, proposal_add_alice, req_1)
     composable::record(&mut batch, proposal_add_alice.id())

  3. req_2 = board_voting::authorize_execution(dao, proposal_remove_bob, freeze, clock)
     board_ops::execute_remove_member(dao, proposal_remove_bob, req_2)
     composable::record(&mut batch, proposal_remove_bob.id())

  4. req_3 = board_voting::authorize_execution(dao, proposal_send_coin, freeze, clock)
     treasury_ops::execute_send_coin(vault, proposal_send_coin, req_3, ctx)
     composable::record(&mut batch, proposal_send_coin.id())

  5. composable::seal_batch(batch)   // asserts executed_count == expected_count
```

### Linking Proposals

Proposals intended to be batched are **linked at creation time** via a shared
`batch_id` field (or a new `ComposableBatchTicket` object):

```move
/// Added to Proposal metadata or as a new optional field:
struct BatchLink has store, copy, drop {
    batch_id: ID,
    sequence: u64,       // 0-indexed position in the batch
    total_actions: u64,  // expected batch size
}
```

During voting, voters see the full batch and vote on the bundle. The governance
module enforces that all proposals in a batch share the same vote outcome: a vote
on one is a vote on all (or the UI enforces this, with on-chain validation at
execution time).

### Shared-Vote Variant

To avoid N separate votes, proposals in a batch can share a **single vote tally**.
The first proposal in the batch holds the canonical votes; the remaining proposals
reference it:

```move
struct BatchFollower has store {
    lead_proposal_id: ID,  // proposal that holds the actual votes
    // No separate vote_snapshot; governed by the lead
}
```

`vote()` is called only on the lead proposal. `authorize_execution()` on follower
proposals checks that the lead has `Passed` status.

### Pros

- **Existing handlers are unmodified** — each proposal type keeps its own handler.
- **No static dispatch table** — each action is dispatched via its own typed handler.
- **Per-action approval floors preserved** — each `authorize_execution()` call
  independently enforces floors, cooldowns, and freeze checks.
- **Incremental adoption** — batching is optional; single-action proposals keep working.
- **Flexible composition** — any combination of proposal types can be batched.

### Cons

- **N proposals must be created and voted on** — even with shared-vote, N proposal
  objects exist on-chain, increasing storage costs and creation complexity.
- **Batch integrity enforcement is complex** — ensuring all-or-nothing semantics
  across N hot potatoes in a single PTB requires the `ComposableBatch` receipt to
  itself be a hot potato, adding another layer of non-droppable tokens.
- **Shared-vote introduces cross-proposal coupling** — follower proposals depend on
  the lead's state, creating a new failure mode if the lead is expired/destroyed.
- **Cooldown interaction** — executing 3 proposals of the same type in one batch may
  trigger cooldown enforcement on the 2nd action.
- **PTB size limits** — very large batches with many shared objects may exceed
  Sui's PTB object and gas limits.
- **Vote UX** — presenting a batch of N proposals as a single vote to the user
  requires significant UI/indexer work.

### Verdict

Most compatible with the existing architecture. The shared-vote variant reduces
voter friction but adds cross-proposal state coupling. Best suited for cases where
2–4 actions need to be atomic.

---

## Option C: Macro-Action Proposal Types (Domain-Specific Bundles)

### Idea

Instead of a generic composition mechanism, define **purpose-built macro-action
proposal types** that encode common multi-action patterns as first-class payload
types with dedicated handlers.

```move
/// Atomic board swap: remove + add in one action.
struct SwapBoardMember has store {
    remove_member: address,
    add_member: address,
}

/// Fund-and-delegate: send coins to SubDAO treasury + transfer a capability.
struct FundAndDelegate has store {
    target_dao_id: ID,
    coin_amount: u64,
    cap_id: ID,
}

/// Batch treasury: send multiple coins to multiple recipients.
struct BatchSend<phantom T> has store {
    recipients: vector<address>,
    amounts: vector<u64>,
}
```

Each macro-action gets its own handler in `armature_proposals`:

```move
public fun execute_swap_board_member(
    dao: &mut DAO,
    proposal: &Proposal<SwapBoardMember>,
    request: ExecutionRequest<SwapBoardMember>,
) {
    let payload = proposal.payload();
    dao.remove_member(payload.remove_member, &request);
    dao.add_member(payload.add_member, &request);
    proposal::finalize(request, proposal);
}
```

### Existing Precedent

This pattern **already exists** in the codebase:

- **`TransferAssets`** — transfers multiple coins and capabilities between DAOs atomically
- **`SpinOutSubDAO`** — creates a SubDAO, transfers assets, and enables types in one proposal
- **`SendSmallPayment`** — rate-limited spending with epoch tracking

These are effectively "composable" proposals scoped to a specific domain.

### Pros

- **Zero framework changes** — works entirely within the existing type system.
- **Full type safety** — each macro-action has a dedicated `Proposal<MacroType>`, so
  `type_bindings`, approval floors, and configs all work normally.
- **Purpose-built approval policies** — a `SwapBoardMember` can have its own quorum/threshold
  tuned for the risk profile of a board swap, rather than inheriting from a generic
  "composable" config.
- **Simpler auditing** — auditors review a finite set of well-defined macro-actions rather
  than an open-ended composition framework.
- **No dispatch table** — each handler is self-contained.
- **Proven pattern** — `TransferAssets` and `SpinOutSubDAO` demonstrate this works.

### Cons

- **Combinatorial growth** — every new multi-action combination requires a new payload
  type + handler + type registration. The number of macro-actions can grow large.
- **Not truly composable** — governance participants cannot create ad-hoc bundles;
  they're limited to pre-defined combinations.
- **Slow iteration** — adding a new macro-action requires a package upgrade (Move
  upgrade), not just a governance vote.
- **Duplicated logic** — `SwapBoardMember` re-implements what `AddMember` +
  `RemoveMember` already do, risking divergence.

### Verdict

Pragmatic and battle-tested. Best for a known, stable set of common multi-action
patterns. Poor fit if the goal is open-ended governance composability.

---

## Option D: Programmable Action Payload with Capability Tokens

### Idea

Introduce a **capability-token architecture** where proposal execution issues a set
of scoped, typed capability tokens (not `ExecutionRequest`), and the proposer's PTB
can use them in any order to authorize framework operations.

```move
/// Issued during proposal execution. One per authorized action.
/// Has `store` so it can live in a vector or be passed between calls in a PTB.
struct ActionCap<phantom P> has store {
    dao_id: ID,
    proposal_id: ID,
}

/// The composable payload: a list of action descriptors.
struct ActionPlan has store {
    actions: vector<ActionDescriptor>,
}

struct ActionDescriptor has store, copy, drop {
    type_key: ascii::String,
    // parameters encoded as BCS bytes for type-erased storage
    params_bcs: vector<u8>,
}
```

### Execution Flow

```move
// 1. Execute the proposal → get a PlanReceipt (hot potato)
let receipt: PlanReceipt = composable::begin_execution(dao, proposal, request);

// 2. Claim individual action caps from the receipt
let cap_1: ActionCap<AddMember> = composable::claim_action<AddMember>(&mut receipt, 0);
let cap_2: ActionCap<SendCoin<SUI>> = composable::claim_action<SendCoin<SUI>>(&mut receipt, 1);

// 3. Use each cap to authorize its action (existing handlers adapted to accept ActionCap)
board_ops::execute_add_member_with_cap(dao, cap_1, member_addr);
treasury_ops::execute_send_coin_with_cap<SUI>(vault, cap_2, amount, recipient, ctx);

// 4. Finalize — asserts all actions were claimed and consumed
composable::finalize_plan(receipt);
```

### Key Mechanism: `PlanReceipt` as Hot-Potato Coordinator

```move
struct PlanReceipt {
    dao_id: ID,
    proposal_id: ID,
    total_actions: u64,
    claimed_actions: u64,
    consumed_actions: u64,
}
```

- `PlanReceipt` is a hot potato (no `drop`).
- `claim_action<P>()` increments `claimed_actions` and returns an `ActionCap<P>`.
  It verifies the action at index `i` has `type_key` matching `P`'s registered binding.
- `ActionCap<P>` has `store` (so it can be held in a local variable across calls
  within the PTB) but no `drop` — it must be consumed by a handler.
- `finalize_plan()` asserts `claimed == total && consumed == total`.

### Handler Adaptation

Existing handlers gain a parallel entry point:

```move
/// Original handler (unchanged)
public fun execute_add_member(
    dao: &mut DAO,
    proposal: &Proposal<AddMember>,
    request: ExecutionRequest<AddMember>,
) { … }

/// New composable entry point
public fun execute_add_member_composable(
    dao: &mut DAO,
    cap: ActionCap<AddMember>,
    member: address,
    receipt: &mut PlanReceipt,
) {
    assert!(dao.id() == cap.dao_id);
    dao.add_member(member, …);
    composable::consume_action(receipt, cap);
}
```

### Pros

- **True composability** — any combination of actions can be bundled in an `ActionPlan`.
- **Single vote** — one `Proposal<ActionPlan>` with one quorum/threshold.
- **Handlers are modular** — each action is authorized and executed independently via
  its own `ActionCap<P>`.
- **No static dispatch table** — the PTB itself is the dispatch mechanism; the
  caller sequences the handler calls.
- **Extensible** — new proposal types just need a `_composable` handler variant.

### Cons

- **Framework changes required** — new `ActionCap`, `PlanReceipt`, and `ActionPlan`
  types must be added to `armature_framework`.
- **`ActionCap<P>` has `store`** — this is weaker than the current `ExecutionRequest`
  (which has no `store`). A `store` capability could theoretically be placed in an
  object and persist beyond the PTB. **Mitigation:** the `PlanReceipt` hot potato
  prevents finalization unless all caps are consumed in the same PTB. Unclaimed caps
  left in storage would cause the receipt to abort.
- **Approval floor enforcement** — the `ActionPlan` has a single config, but individual
  actions may require different floors. The `claim_action<P>()` function must enforce
  per-action floors before issuing the cap.
- **BCS-encoded params** — type-erased parameter storage is fragile and hard to validate
  at creation time. Malformed BCS will only fail at execution.
- **Dual handler surface** — every proposal type needs both the original handler and a
  `_composable` variant, doubling the handler surface area.
- **PTB complexity** — callers must construct PTBs that sequence claim → execute → consume
  for every action, increasing client-side complexity.

### Verdict

Most powerful and flexible, but highest implementation cost and largest framework
surface area change. The `store` ability on `ActionCap` is a meaningful security
trade-off that needs careful analysis.

---

## Option E: Separate Frame Object + PTB-Dispatched Pipeline

### Idea

A refinement of Option A that eliminates the static dispatch table by splitting the
problem across two objects and pushing action dispatch into the PTB itself.

Step payloads live in a **`CompositeFrame`** — a separate owned-then-shared object whose
`UID` holds dynamic fields — rather than inside the `Proposal` object. This sidesteps the
constraint that `proposal::create` calls `transfer::share_object` internally, consuming the
object before dynamic fields can be attached. A single `Proposal<CompositePayload>` holds
only a reference to the frame and the computed effective config.

During execution, a **`Pipeline`** hot potato enforces forward-only step ordering. At each
step, `advance_step<P>` removes the typed payload from the frame's dynamic fields, validates
the type against what was recorded at submission time, and returns:
- the payload `P` by value
- a fresh `ExecutionRequest<P>` (carrying the composite proposal's ID)
- the `Pipeline` for the next step

The PTB caller then passes these directly to the existing single-action handler (with a thin
adapter), sequences the next call, and finally calls `finalize_pipeline` to consume the hot
potato. **There is no dispatch loop in Move** — the PTB is the dispatcher.

```
Submission PTB                                Execution PTB
─────────────────────────────────────         ─────────────────────────────────────────────
frame = new_frame(dao_id, ctx)                req = authorize_execution<CompositePayload>(...)
add_step<A>(frame, dao, key_a, payload_a)     pipeline = begin_pipeline(proposal, req, frame)
add_step<B>(frame, dao, key_b, payload_b)     (a, req_a, pipeline) = advance_step<A>(dao, frame, pipeline, freeze, clock)
add_step<C>(frame, dao, key_c, payload_c)     execute_a_step(a, req_a, ...)
submit_composite(dao, frame, ...)             (b, req_b, pipeline) = advance_step<B>(dao, frame, pipeline, freeze, clock)
  → CompositeFrame (shared)                   execute_b_step(b, req_b, ...)
  → Proposal<CompositePayload> (shared)       (c, req_c, pipeline) = advance_step<C>(dao, frame, pipeline, freeze, clock)
                                              execute_c_step(c, req_c, ...)
Voting: vote() × N on Proposal<CompositePayload>
                                              finalize_pipeline(pipeline)
```

### Key Structs

```move
/// Owned during submission, shared before voting begins.
/// Holds per-step payloads as dynamic fields keyed by StepKey { index }.
public struct CompositeFrame has key {
    id: UID,
    dao_id: ID,
    step_type_keys: vector<ascii::String>,
    step_types: vector<TypeName>,           // validated at advance_step
}

/// Stored inside Proposal<CompositePayload>.
/// References the frame by ID and records the effective config.
public struct CompositePayload has store {
    frame_id: ID,
    step_type_keys: vector<ascii::String>,
    step_types: vector<TypeName>,           // copied at submission; frame assertions use this
}

/// Hot-potato step sequencer. No abilities — must be consumed in same PTB.
public struct Pipeline {
    frame_id: ID,
    dao_id: ID,
    composite_proposal_id: ID,
    current_step: u64,
    total_steps: u64,
}
```

### Effective Config

`submit_composite` computes the effective `ProposalConfig` as the component-wise `max()`
across all step configs and the `"Composite"` type's own DAO config:

```
effective_quorum           = max(composite_config.quorum,        step_1.quorum, ...)
effective_threshold        = max(composite_config.threshold,     step_1.threshold, ...)
effective_execution_delay  = max(composite_config.delay,         step_1.delay, ...)
effective_cooldown_ms      = max(composite_config.cooldown,      step_1.cooldown, ...)
```

This is a safety invariant: a composite can never be approved under weaker requirements
than any constituent step would individually require.

### Composability Policy (Config-Driven)

Whether a proposal type may appear as a step in a composite is controlled by the
`composable_allowed` field on its `ProposalConfig` — a **deny-by-default** boolean
that defaults to `false` for all types. `add_step<P>` checks
`dao.proposal_configs().get(&type_key).composable_allowed` and aborts if `false`.
The `"Composite"` type itself is unconditionally blocked from self-nesting
(hardcoded check, independent of config).

Factory defaults set `composable_allowed = false` for all floor-gated types
(`UpdateProposalConfig`, `EnableProposalType`), governance-surface-modifying types
(`DisableProposalType`, `UnfreezeProposalType`, `TransferFreezeAdmin`, `SetBoard`),
stateful types (`SendSmallPayment`), and hierarchy-critical types (`SpawnDAO`,
`CreateSubDAO`, `SpinOutSubDAO`). Safe operational types (`SendCoin`, `AddMember`,
`RemoveMember`, `UpdateMetadata`, `TransferAssets`, `ProposeUpgrade`, etc.) default
to `true`.

This design eliminates the static blocklist maintenance risk: new proposal types
are excluded from composites by default, and the `UpdateProposalConfig` handler
enforces that `composable_allowed` cannot be set to `true` for types with hardcoded
execution floors.

### Per-Step Freeze and Cooldown Enforcement

`advance_step<P>` is the single choke point through which every step payload reaches a
handler. It therefore carries the same freeze and cooldown obligations that
`board_voting::authorize_execution` carries for single-action proposals.

**Freeze.** `authorize_execution<CompositePayload>` checks
`freeze.assert_not_frozen("Composite", clock)`. Without per-step checking, a step whose
individual type key is frozen — e.g. `"SendCoin"` frozen by the FreezeAdminCap holder
during a treasury incident — would execute anyway because the outer type key is
`"Composite"`, not `"SendCoin"`. `advance_step<P>` resolves this by checking the step's
own type key before extracting the payload:

```move
pub fun advance_step<P: store>(
    dao: &mut DAO,
    frame: &mut CompositeFrame,
    pipeline: Pipeline,
    freeze: &EmergencyFreeze,
    clock: &Clock,
    ctx: &TxContext,
): (P, ExecutionRequest<P>, Pipeline) {
    assert!(object::id(frame) == pipeline.frame_id, EFrameMismatch);
    let step_idx = pipeline.current_step;
    assert!(step_idx < pipeline.total_steps, EPipelineComplete);

    // Validate that caller supplied the correct P for this step position.
    let expected_type = frame.step_types[step_idx];
    assert!(type_name::with_defining_ids<P>().into_string() == expected_type, EStepTypeMismatch);

    let step_type_key = frame.step_type_keys[step_idx];

    // Composability check — deny-by-default via ProposalConfig.
    let step_config = dao.proposal_configs().get(&step_type_key);
    assert!(step_config.composable_allowed(), ETypeNotComposable);

    // Per-step freeze check — mirrors authorize_execution's freeze guard.
    freeze.assert_not_frozen(&step_type_key, clock);

    // Per-step cooldown check — mirrors proposal::execute's cooldown guard.
    if (step_config.cooldown_ms() > 0) {
        let last_at = dao.last_executed_at();
        if (last_at.contains(&step_type_key)) {
            let last = *last_at.get(&step_type_key);
            assert!(clock.timestamp_ms() >= last + step_config.cooldown_ms(), ECooldownActive);
        };
    };

    // Record the execution timestamp under the step's own type key so standalone
    // proposals of the same type see the correct cooldown state afterwards.
    dao.record_execution(step_type_key, clock.timestamp_ms());

    // Extract payload and issue a scoped ExecutionRequest.
    let payload: P = df::remove(&mut frame.id, StepKey { index: step_idx });
    let req = proposal::new_execution_request<P>(pipeline.dao_id, pipeline.composite_proposal_id);

    let next_pipeline = Pipeline {
        current_step: step_idx + 1,
        ..pipeline
    };

    (payload, req, next_pipeline)
}
```

Two notes:

- `freeze.assert_not_frozen`, `dao.proposal_configs()`, `dao.last_executed_at()`, and
  `dao.record_execution()` are all accessible from `composite.move` because both modules
  live in `armature_framework`.
- The max()-derived effective config still governs the composite proposal's own cooldown
  (tracked under the `"Composite"` type key in `last_executed_at`), providing an additional
  global limit on how frequently any composite proposal can execute. Per-step cooldowns
  and the composite-level cooldown are complementary: both are enforced.

### Handler Adapter Pattern

#### `proposal` module API split

`proposal::finalize(request, proposal)` currently does two things atomically: consumes
the `ExecutionRequest` hot potato and marks the `Proposal` as `Executed`. Composite
step handlers have no `Proposal<P>` to pass, so `finalize` is split into two primitives:

```move
/// Consumes the hot potato. Called by the canonical impl function.
public fun consume_execution_request<P>(request: ExecutionRequest<P>) { … }

/// Marks the proposal Executed and emits the event. Called by the single-action shim.
public fun mark_executed<P>(proposal: &mut Proposal<P>) { … }

/// Convenience wrapper — unchanged; existing handlers that call finalize directly keep working.
public fun finalize<P>(request: ExecutionRequest<P>, proposal: &mut Proposal<P>) {
    consume_execution_request(request);
    mark_executed(proposal);
}
```

#### Payload `drop` ability

Composable payload types must declare `drop` in addition to `store`. Pure-data payloads
(structs containing only primitive fields or other droppable types) can always carry `drop`
safely. Any payload that wraps a non-droppable value (e.g. a `Balance` or inner capability)
cannot have `drop` and must therefore set `composable_allowed = false` in its config —
which is the correct policy regardless, since such payloads represent resource transfers
that need explicit accounting and should not appear as steps in an arbitrary composite.

#### Unified implementation pattern

`execute_send_coin_step` is the canonical implementation. `execute_send_coin` is a thin
shim that extracts fields from the proposal reference and delegates:

```move
// Canonical implementation — receives payload by reference; consumes request.
// Private to the handler module.
fun send_coin_impl<T>(
    vault: &mut TreasuryVault,
    payload: &SendCoin<T>,
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    let coin = vault.withdraw(payload.amount(), &request, ctx);
    transfer::public_transfer(coin, payload.recipient());
    proposal::consume_execution_request(request);
}

// Single-action shim — reads from proposal reference, marks proposal executed.
pub fun execute_send_coin<T>(
    vault: &mut TreasuryVault,
    proposal: &mut Proposal<SendCoin<T>>,
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    send_coin_impl(vault, proposal.payload(), request, ctx);
    proposal::mark_executed(proposal);
}

// Step handler — payload arrives by value from advance_step; pass reference to impl,
// then let the value drop (requires SendCoin<T>: drop).
pub fun execute_send_coin_step<T>(
    vault: &mut TreasuryVault,
    payload: SendCoin<T>,
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    send_coin_impl(vault, &payload, request, ctx);
    // payload drops here — valid because SendCoin<T> has `drop`
}
```

Logic lives in one place (`send_coin_impl`). Adding, changing, or auditing the action
requires touching exactly one function. Third-party handlers that already call
`consume_execution_request` directly are automatically composite-compatible.

### Pros

- **No static dispatch table** — `advance_step<P>` is fully generic; the PTB itself
  sequences typed handler calls. Adding a new proposal type requires only a `_step`
  handler variant, not any change to the composable layer.
- **Single vote, single proposal object** — one `Proposal<CompositePayload>` with
  one effective config.
- **Full type safety** — `advance_step<P>` validates `type_name::get<P>()` against the
  recorded `TypeName` at that step index. Type substitution attacks abort at the Move
  level.
- **Approval floors preserved** — effective config is `max()` across all steps; no step
  can lower the bar for the bundle.
- **Step skipping is impossible** — the `Pipeline` hot potato can only advance forward
  via `advance_step`; step handlers only receive `ExecutionRequest<P>` through
  `advance_step`, so there is no other way to obtain one.
- **Frame is immutable after sharing** — `CompositeFrame` has no public mutators;
  `advance_step` only removes dynamic fields (cannot add or replace them).
- **Extends to third-party types** — any type enabled via `EnableProposalType` is
  composable without framework changes, provided it has a `_step` handler variant.
- **Single on-chain object** — one `CompositeFrame` + one `Proposal`, not N proposal
  objects.

### Cons

- **Framework changes required** — `composite.move` is a new module in
  `armature_framework`; `board_voting.move` gains `submit_composite`; `dao.move`
  gains `max_composite_steps` and the `"Composite"` default type.
- **New `_step` handler variants** — every composable proposal type needs a companion
  step handler, but logic duplication is eliminated by the canonical-impl pattern: one
  private `_impl` function holds the logic; `execute_foo` and `execute_foo_step` are
  thin wrappers. Payload types must carry `drop`, which is safe for all pure-data payloads
  and correctly excludes resource-holding payloads from composability.
- **`proposal::finalize` is split** — into `consume_execution_request` (called by the
  canonical impl) and `mark_executed` (called by the single-action shim). The combined
  `finalize` wrapper is kept for handlers that don't adopt the canonical-impl pattern,
  preserving backwards compatibility.
- **Two shared objects per composite** — `CompositeFrame` + `Proposal<CompositePayload>`
  vs. one object for single-action proposals. Minor storage overhead.
- **PTB construction is more complex** — the client must call `advance_step<P>` and the
  step handler in sequence for each step, correctly threading the `Pipeline` value
  between calls.
- **`advance_step` requires `&mut DAO` and `&EmergencyFreeze`** — per-step freeze and
  cooldown enforcement (see above) means the execution PTB must pass `dao`, `freeze`, and
  `clock` to every `advance_step` call. This slightly increases PTB verbosity but is
  mechanically equivalent to what `authorize_execution` already requires for single-action
  proposals.

### Verdict

The strongest overall option. It resolves the core objection to Option A (dispatch
table) without introducing the security trade-offs of Option D (`ActionCap` with
`store`) or the multi-object overhead of Option B. Framework changes are meaningful
but bounded; the `_step` handler adaptation is mechanical. The two previously
unaddressed gaps — freeze bypass and per-step cooldown bypass — are closed by
`advance_step`'s per-step freeze check and cooldown check/record (see
[Per-Step Freeze and Cooldown Enforcement](#per-step-freeze-and-cooldown-enforcement)).
This is the most complete specification of a general-purpose composable proposal system
for Armature. See `specs/stretch/09_proposal_composition_design.md` for the full
module-level design.

---

## Comparison Matrix

| Criterion                          | A: Envelope | B: Receipt Chain | C: Macro-Actions | D: Capability Tokens | E: Frame + Pipeline  |
| ---------------------------------- | :---------: | :--------------: | :---------------: | :------------------: | :------------------: |
| Framework changes                  | Low         | Medium           | **None**          | High                 | Medium               |
| Open-ended composability           | Medium      | High             | **None**          | **High**             | **High**             |
| Handler changes required           | New dispatch| **None**         | New per macro     | New `_composable`    | New `_step` variants |
| Approval floor enforcement         | Manual      | Automatic        | Automatic         | Manual               | **Automatic (max)**  |
| Type-safety guarantees             | Weak (erased)| **Strong**      | **Strong**        | Medium               | **Strong**           |
| Atomic execution guarantee         | Yes         | Yes (with receipt)| Yes              | Yes (with receipt)   | Yes                  |
| Auditor comprehensibility          | Medium      | Medium           | **High**          | Low                  | Medium               |
| Voter comprehensibility (UX)       | High        | Medium           | **High**          | High                 | High                 |
| On-chain storage efficiency        | Good (1 obj)| Poor (N objs)    | **Good (1 obj)**  | Good (1 obj)         | Good (2 objs)        |
| Maintenance burden                 | High (dispatch table) | Low    | Medium (per macro)| High (dual handlers) | Low (generic core)   |
| Backwards compatible               | Yes         | **Yes**          | **Yes**           | Yes                  | **Yes**              |
| Client/PTB construction complexity | Low         | High             | **Low**           | High                 | Medium               |

---

## Recommendation

**Option E** (Frame + Pipeline) as the primary composable proposal mechanism, with
**Option C** (Macro-Actions) as complementary sugar for the most common patterns.

### Primary — Option E for General-Purpose Composition

Option E resolves the core failure modes of all other options:
- Eliminates Option A's static dispatch table by pushing dispatch into the PTB.
- Avoids Option B's N-proposal overhead and shared-vote coupling complexity.
- Avoids Option D's weakened security model (`ActionCap` with `store`).
- Provides stronger type safety and approval-floor guarantees than any other option.

The framework changes are bounded and additive: one new module (`composite.move`),
two extended modules (`board_voting.move`, `dao.move`), and `_step` handler variants
that are a mechanical transformation of existing handlers. No existing code changes.

See `specs/stretch/09_proposal_composition_design.md` for the full module contracts,
lifecycle flows, security analysis, and migration checklist.

### Complementary — Option C for High-Frequency Patterns

For the most common recurring bundles, purpose-built macro-action types remain
valuable: they require zero framework machinery, have purpose-tuned approval configs,
and are maximally auditable. Ship these alongside Option E, not instead of it:

| Macro-Action          | Bundled Actions                              |
| --------------------- | -------------------------------------------- |
| `SwapBoardMember`     | Remove member + Add member                   |
| `FundSubDAO<T>`       | Send coins to SubDAO + Transfer capability   |
| `BatchSend<T>`        | Send coins to multiple recipients            |
| `ReconfigureGovernance` | Update config + Update metadata            |
| `BootstrapSubDAO`     | Create SubDAO + Fund + Transfer caps + Enable types |

### Why Not Option B?

Option B's `ComposableBatch` receipt is still useful for **atomically executing multiple
already-passed proposals** in a single PTB (e.g., two independently-voted proposals
that must not execute out of order). But it is not a substitute for single-vote
composition — it still requires N separate proposal objects and N separate vote cycles.
If Tier 2 ad-hoc batching of pre-voted proposals is needed, Option B can be added as a
separate lightweight utility without conflicting with Option E.

### Why Not Option D?

Option D is the most architecturally elegant but introduces the highest risk:
- The `store` ability on `ActionCap` weakens the security model.
- Dual handler surfaces double the audit surface.
- BCS-encoded params defer validation to execution time.

Option E achieves the same open-ended composability without these trade-offs.

### Why Not Option A alone?

The static dispatch table in Option A is a maintenance anti-pattern. Option E supersedes
it entirely — same single-vote, single-object structure, but with the dispatch problem
solved by the `advance_step<P>` generic and PTB-side sequencing.

---

## Implementation Sketches

### Option C — `SwapBoardMember` Macro-Action Example

### Payload

```move
// packages/armature_proposals/sources/board/swap_board_member.move
module armature_proposals::swap_board_member;

public struct SwapBoardMember has store {
    remove_member: address,
    add_member: address,
}

public fun new(remove: address, add: address): SwapBoardMember {
    SwapBoardMember { remove_member: remove, add_member: add }
}

public fun remove_member(self: &SwapBoardMember): address { self.remove_member }
public fun add_member(self: &SwapBoardMember): address { self.add_member }
```

### Handler

```move
// In board_ops.move (or a new swap_board_ops.move)
public fun execute_swap_board_member(
    dao: &mut DAO,
    proposal: &Proposal<SwapBoardMember>,
    request: ExecutionRequest<SwapBoardMember>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();

    // Remove first, then add — order matters if same address (no-op guard).
    assert!(payload.remove_member() != payload.add_member(), ESameAddress);
    dao.remove_member(payload.remove_member(), &request);
    dao.add_member(payload.add_member(), &request);

    event::emit(BoardSwapped {
        dao_id: dao.id(),
        removed: payload.remove_member(),
        added: payload.add_member(),
    });

    proposal::finalize(request, proposal);
}
```

### Registration

The DAO enables `SwapBoardMember` via an `EnableProposalType` proposal with an
appropriate config (e.g., same quorum/threshold as `SetBoard`).

---

### Option B — `ComposableBatch` (Ad-Hoc Batch Receipt)

#### Framework Addition

```move
// packages/armature_framework/sources/composable.move
module armature::composable;

/// Hot-potato batch receipt. Must be sealed in the same PTB.
public struct ComposableBatch {
    dao_id: ID,
    batch_id: ID,
    expected_count: u64,
    executed_ids: vector<ID>,
}

/// Begin a batch. Returns a hot-potato receipt.
public fun begin_batch(dao: &DAO, expected_count: u64, ctx: &mut TxContext): ComposableBatch {
    assert!(expected_count > 1, EBatchTooSmall);
    ComposableBatch {
        dao_id: dao.id(),
        batch_id: object::id_from_address(ctx.fresh_object_address()),
        expected_count,
        executed_ids: vector::empty(),
    }
}

/// Record a completed action in the batch.
public fun record(batch: &mut ComposableBatch, proposal_id: ID, dao_id: ID) {
    assert!(dao_id == batch.dao_id, EDaoMismatch);
    assert!(!batch.executed_ids.contains(&proposal_id), EDuplicateProposal);
    batch.executed_ids.push_back(proposal_id);
}

/// Seal the batch. Aborts if not all actions executed.
public fun seal_batch(batch: ComposableBatch) {
    let ComposableBatch { dao_id: _, batch_id: _, expected_count, executed_ids } = batch;
    assert!(executed_ids.length() == expected_count, EBatchIncomplete);
}
```

#### Usage in a PTB

```
// Client constructs a PTB:
let batch = composable::begin_batch(dao, 2);

let req1 = board_voting::authorize_execution(dao, proposal_1, freeze, clock);
board_ops::execute_add_member(dao, proposal_1, req1);
composable::record(&mut batch, proposal_1.id(), dao.id());

let req2 = board_voting::authorize_execution(dao, proposal_2, freeze, clock);
treasury_ops::execute_send_coin(vault, proposal_2, req2, ctx);
composable::record(&mut batch, proposal_2.id(), dao.id());

composable::seal_batch(batch);
```

The `ComposableBatch` ensures that if any action aborts, the entire PTB reverts,
giving atomic multi-proposal execution without changing any existing handlers.

---

## Open Questions

1. ~~**`finalize` vs `consume_execution_request` for step handlers** — Step handlers
   call `consume_execution_request` rather than `proposal::finalize`, losing the
   per-step proposal-ID validation that `finalize` provides. Is the `Pipeline` ordering
   guarantee sufficient, or should `advance_step` perform an additional proposal-ID
   check?~~ **Resolved.** `proposal::finalize` is split into `consume_execution_request`
   (consumes the hot potato, called by the canonical `_impl` function) and `mark_executed`
   (marks the proposal `Executed`, called by the single-action shim). The combined
   `finalize` wrapper is preserved for existing handlers. Step handlers never need to
   validate against a `Proposal<P>` object — proposal-ID correctness is guaranteed by
   `advance_step` (which reads `pipeline.composite_proposal_id` to construct the
   `ExecutionRequest`) and `finalize_pipeline` (which closes out `Proposal<CompositePayload>`).
   The `Pipeline` hot potato's forward-only ordering makes step skipping impossible, so
   no additional per-step proposal-ID check is needed in `advance_step`.

2. ~~**Per-step cooldown enforcement** — Should individual step type cooldowns be checked
   during composite execution, or only the `"Composite"` type's own cooldown?~~ **Resolved.**
   `advance_step<P>` checks per-step cooldowns using the step type key's `cooldown_ms` from
   `dao.proposal_configs()` and records execution via `dao.record_execution(step_type_key, ...)`.
   The max()-derived composite cooldown continues to apply as a separate global limit.
   Per-step freeze enforcement (which was not in the original design) is resolved identically:
   `advance_step<P>` calls `freeze.assert_not_frozen(&step_type_key, clock)` before
   returning each step.

3. **`SetBoard` composability** — Currently blocked. Should it be allowed if the composite
   also requires the `SetBoard` config threshold (effectively raising the bar for the whole
   bundle)? Or is the risk of a board-replacement-plus-treasury-drain bundle too high
   regardless of threshold?

4. **`max_composite_steps` upper bound** — Default is 5. Should a hard ceiling be enforced
   in the framework (e.g., 10) to bound PTB gas costs, or left entirely to per-DAO config?

5. **`StepExecuted` event** — Should `advance_step` emit a per-step event for indexer
   auditability, or is a single `CompositeExecuted` event at `finalize_pipeline` sufficient?

6. **Option B utility** — Should the `ComposableBatch` receipt (Option B) be implemented
   as a separate lightweight utility for atomically executing multiple pre-voted proposals
   in one PTB, independently of Option E? The two patterns serve different governance
   workflows and do not conflict.

7. **Macro-action directory convention** — Should Option C macro-actions live in
   `sources/composable/` or be co-located with their domain (e.g., `SwapBoardMember`
   in `sources/board/`)?

---

## References

- Existing multi-action precedents: `TransferAssets`, `SpinOutSubDAO`, `SendSmallPayment`
- Hot-potato pattern: `ExecutionRequest<P>`, `CapLoan`
- Privileged cascading: `controller::privileged_submit`
- Sui PTB documentation: https://docs.sui.io/concepts/transactions/prog-txn-blocks
- `ADR_SUBMISSION_TIME_FLOOR_ENFORCEMENT.md` — moves floor enforcement to proposal submission, enabling `UpdateProposalConfig` and `EnableProposalType` composite participation while keeping floors as hardcoded constants
