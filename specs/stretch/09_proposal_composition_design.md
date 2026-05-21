# Architectural Design: Composite / Atomic Multi-Step Proposals

> Implementation design for `specs/stretch/09_proposal_composition.md`.
> Covers all structural decisions, module contracts, handler migration patterns,
> DAO configuration, and security analysis needed to ship this feature.

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Current Architecture Constraints](#2-current-architecture-constraints)
3. [Design Goals and Non-Goals](#3-design-goals-and-non-goals)
4. [High-Level Architecture](#4-high-level-architecture)
5. [Object Model](#5-object-model)
6. [Module Contracts](#6-module-contracts)
   - 6.1 [composite.move (new)](#61-compositemove-new)
   - 6.2 [board_voting.move (extended)](#62-board_votingmove-extended)
   - 6.3 [composite_ops.move (new)](#63-composite_opsmove-new)
   - 6.4 [dao.move (extended)](#64-daomove-extended)
7. [Lifecycle Flows](#7-lifecycle-flows)
   - 7.1 [Submission PTB](#71-submission-ptb)
   - 7.2 [Voting](#72-voting)
   - 7.3 [Execution PTB](#73-execution-ptb)
8. [Effective ProposalConfig Derivation](#8-effective-proposalconfig-derivation)
9. [Handler Adapter Pattern](#9-handler-adapter-pattern)
10. [DAO Registration and Type Bindings](#10-dao-registration-and-type-bindings)
11. [Blocked and Restricted Types](#11-blocked-and-restricted-types)
12. [Security Analysis](#12-security-analysis)
13. [Testing Strategy](#13-testing-strategy)
14. [Migration Checklist](#14-migration-checklist)
15. [Open Questions](#15-open-questions)

---

## 1. Problem Statement

The current proposal system requires one `Proposal<P>` per logical operation. Operations
that are inherently atomic — like **CreateSubDAO + fund it + delegate a capability** — must be
split across three separate vote cycles. This creates two failure modes:

**Governance overhead**: N vote cycles × the voting window means multi-week delays for
operations that should be approved once.

**Consistency risk**: If votes 1 and 2 pass but vote 3 fails (quorum not reached, expired,
or vetoed), the DAO is left in an intermediate state. A SubDAO exists but is unfunded; a
charter amendment passed but the treasury allocation did not. Recovery requires additional
proposals, which themselves can fail.

Real-world governance operations that hit this today:

| Operation | Steps today | Consistency risk |
|---|---|---|
| CreateSubDAO + fund + delegate cap | 3 proposals | SubDAO unfunded if step 2/3 fails |
| Amend charter + treasury allocation | 2 proposals | Allocation orphaned if step 2 fails |
| Board restructure + freeze admin transfer | 2 proposals | Board restructured without safety cap |
| Federation formation + initial contribution | 2 proposals | Federation formed with no resources |

---

## 2. Current Architecture Constraints

Understanding why a naive solution doesn't work requires understanding the existing invariants.

### 2.1 `Proposal<P>` is bound to a single payload type

```move
public struct Proposal<P: store> has key {
    payload: P,
    ...
}
```

`Proposal` is generic over exactly one `P`. There is no native heterogeneous collection in
Move — `vector<P>` requires all elements to be the same type. Storing steps of different
types requires dynamic fields.

### 2.2 `proposal::create` shares the object immediately

`proposal::create<P>` calls `transfer::share_object` internally before returning. There is
no hook to attach dynamic fields to the proposal's UID after creation. Per-step payloads
cannot live on `Proposal<CompositePayload>.id`.

### 2.3 Existing handlers take `&Proposal<P>` to read payload data

```move
pub fun execute_create_subdao(
    vault: &mut CapabilityVault,
    proposal: &Proposal<CreateSubDAO>,   // reads .payload() internally
    request: ExecutionRequest<CreateSubDAO>,
    ctx: &mut TxContext,
)
```

In a composite, no `Proposal<CreateSubDAO>` exists. The step payload lives in a dynamic
field on a separate object. Existing handlers cannot be called unchanged without a
`Proposal<P>` to pass in.

### 2.4 `ExecutionRequest<P>` is a hot potato with no abilities

```move
public struct ExecutionRequest<phantom P> {
    dao_id: ID,
    proposal_id: ID,
}
```

It carries the composite proposal's ID as `proposal_id`. Handlers that call
`proposal::finalize(request, &Proposal<P>)` would fail because the referenced
`Proposal<CompositePayload>` has type `Proposal<CompositePayload>`, not `Proposal<P>`.
Step handlers must use `proposal::consume_execution_request` instead.

### 2.5 Shared objects cannot be used after `transfer::share_object` in the same PTB

Once `transfer::share_object(obj)` is called, `obj` is consumed. It can only be referenced
as a shared input to a *future* transaction, not within the same PTB. This forces a two-phase
design: build (owned) → share → execute (shared).

---

## 3. Design Goals and Non-Goals

### Goals

- **Single vote, atomic execution.** N steps are approved in one vote. If any step fails, the
  entire PTB aborts. No partial execution is possible.
- **Existing handlers unchanged.** Handler functions in `armature_proposals` that operate on
  single proposals are not modified.
- **Highest-threshold wins.** The effective voting requirements for a composite are the
  strictest across all component types — never weaker.
- **Type-safe step ordering.** The PTB executor cannot skip steps, reorder them, or substitute
  a different payload type for a step.
- **Extensible.** Third-party proposal types (enabled via `EnableProposalType`) compose with
  the pipeline without any changes to `composite.move`.
- **No nested composites.** Flat bundles only. A step cannot itself be a composite.

### Non-Goals

- Changing the voting UX, event structure, or indexer schema for single proposals.
- Supporting heterogeneous quorum (e.g., step 1 requires board vote, step 2 requires token vote).
- Supporting parallel (unordered) step execution.
- Supporting conditional branching ("only run step 3 if step 2 produced X").

---

## 4. High-Level Architecture

```
Submission PTB                          Voting                    Execution PTB
─────────────────────────────────────   ─────────────────────     ─────────────────────────────────
new_frame(dao_id)                       vote() × N                authorize_execution<CompositePayload>
  → CompositeFrame (owned)                                          → ExecutionRequest<CompositePayload>
add_step<A>(frame, dao, key, payload_a)                           begin_pipeline(prop, req, frame)
add_step<B>(frame, dao, key, payload_b)                             → Pipeline (hot potato)
add_step<C>(frame, dao, key, payload_c)
submit_composite(dao, frame, ...)                                  advance_step<A>(pipeline, frame)
  → CompositeFrame (shared)                                          → (payload_a: A, ExecutionRequest<A>, Pipeline)
  → Proposal<CompositePayload> (shared)                           handler_a_step(payload_a, req_a, ...)

                                                                  advance_step<B>(pipeline, frame)
                                                                    → (payload_b: B, ExecutionRequest<B>, Pipeline)
                                                                  handler_b_step(payload_b, req_b, ...)

                                                                  advance_step<C>(pipeline, frame)
                                                                    → (payload_c: C, ExecutionRequest<C>, Pipeline)
                                                                  handler_c_step(payload_c, req_c, ...)

                                                                  finalize_pipeline(pipeline)
                                                                  ── PTB aborts atomically if any step fails ──
```

---

## 5. Object Model

### 5.1 `CompositeFrame` (new shared object)

Holds per-step payloads as dynamic fields. Lives independently of the `Proposal` object,
which resolves the constraint in §2.2.

```
CompositeFrame (shared)
├─ id: UID                            ← dynamic fields attached here
├─ dao_id: ID
├─ step_type_keys: vector<ascii::String>   ← for DAO config lookups
├─ step_types: vector<TypeName>            ← for advance_step<P> validation
└─ dynamic fields:
   ├─ StepKey { index: 0 } → payload_a: A
   ├─ StepKey { index: 1 } → payload_b: B
   └─ StepKey { index: 2 } → payload_c: C
```

Dynamic fields are **consumed** (removed) by `advance_step` during execution. After
`finalize_pipeline`, the frame has no remaining dynamic fields and serves as an on-chain
audit record.

### 5.2 `Proposal<CompositePayload>` (existing shared object type)

Standard proposal object, no structural changes. The payload stores metadata needed to
validate the frame during execution.

```
Proposal<CompositePayload> (shared)
├─ id: UID
├─ dao_id: ID
├─ payload: CompositePayload
│   ├─ frame_id: ID               ← reference to CompositeFrame
│   ├─ step_type_keys: vector<ascii::String>
│   └─ step_types: vector<TypeName>
├─ vote_snapshot, votes_cast, ...  ← standard governance fields (unchanged)
└─ config: ProposalConfig          ← effective config (max-of-steps)
```

### 5.3 `Pipeline` (hot potato)

Enforces ordered step execution within the execution PTB. Has no abilities — cannot be
stored, copied, or dropped. Must be finalized in the same PTB.

```
Pipeline (no abilities)
├─ frame_id: ID                    ← asserted against CompositeFrame at each advance_step
├─ dao_id: ID
├─ composite_proposal_id: ID       ← carried into each ExecutionRequest<P>
├─ current_step: u64
└─ total_steps: u64
```

### 5.4 `StepKey` (dynamic field name)

```move
public struct StepKey has copy, drop, store { index: u64 }
```

Used as the dynamic field name on `CompositeFrame.id`. Step index matches position in
`step_types` / `step_type_keys` vectors.

---

## 6. Module Contracts

### 6.1 `composite.move` (new)

**Package**: `armature_framework`
**Path**: `packages/armature_framework/sources/composite.move`

#### Structs

```move
module armature::composite;

use armature::dao::DAO;
use armature::proposal::{Self, ExecutionRequest, Proposal};
use std::ascii;
use std::type_name::{Self, TypeName};
use sui::dynamic_field as df;

// Dynamic field key for step payloads
public struct StepKey has copy, drop, store { index: u64 }

/// Owned during the submission PTB; shared by submit_composite.
/// After sharing, serves as the mutable execution target for advance_step.
public struct CompositeFrame has key {
    id: UID,
    dao_id: ID,
    step_type_keys: vector<ascii::String>,
    step_types: vector<TypeName>,
}

/// Stored inside Proposal<CompositePayload>. References the frame by ID.
public struct CompositePayload has store {
    frame_id: ID,
    step_type_keys: vector<ascii::String>,
    step_types: vector<TypeName>,
}

/// Hot-potato state machine for the execution PTB.
/// Enforces forward-only step ordering. No abilities.
public struct Pipeline {
    frame_id: ID,
    dao_id: ID,
    composite_proposal_id: ID,
    current_step: u64,
    total_steps: u64,
}
```

#### Errors

| Code | Name | Condition |
|---|---|---|
| 0 | `EStepLimitExceeded` | `add_step` called when frame is at `max_steps` |
| 1 | `EStepTypeMismatch` | `advance_step<P>` called but current step recorded a different TypeName |
| 2 | `EPipelineIncomplete` | `finalize_pipeline` called before all steps consumed |
| 3 | `EIncomposableType` | Step type_key is on the blocked list |
| 4 | `EFrameDAOMismatch` | Frame's `dao_id` does not match the DAO or pipeline |
| 5 | `EFrameProposalMismatch` | Frame's ID does not match `CompositePayload.frame_id` |
| 6 | `ETypeNotEnabled` | Step type_key is not enabled in the DAO |
| 7 | `ETypeMismatch` | P does not match the DAO's type binding for the given type_key |
| 8 | `EEmptyComposite` | `submit_composite` called on a frame with zero steps |

#### Public API

```move
/// Create an owned CompositeFrame. Called at the start of the submission PTB.
/// The frame is mutable until submit_composite consumes it.
public fun new_frame(dao_id: ID, ctx: &mut TxContext): CompositeFrame;

/// Add a typed step to the frame.
///
/// Validates:
///   - type_key is enabled in the DAO
///   - If a type binding exists for type_key, P must match it
///   - type_key is not on the blocked list
///   - frame.step_types.length() < max_steps
///
/// Stores payload as a dynamic field keyed by StepKey { index }.
/// Records type_key and TypeName in the frame's vectors.
public fun add_step<P: store>(
    frame: &mut CompositeFrame,
    dao: &DAO,
    type_key: ascii::String,
    payload: P,
    max_steps: u64,
);

/// Begin pipeline execution. Called immediately after authorize_execution<CompositePayload>.
///
/// Validates:
///   - object::id(frame) == proposal.payload().frame_id
///   - frame.dao_id == proposal.dao_id()
///   - proposal.status is Executed (guaranteed by authorize_execution)
///
/// Consumes the CompositePayload ExecutionRequest (hot potato consumed here).
/// Returns a Pipeline hot potato.
public fun begin_pipeline(
    proposal: &Proposal<CompositePayload>,
    request: ExecutionRequest<CompositePayload>,
    frame: &CompositeFrame,
): Pipeline;

/// Advance to the next step.
///
/// Validates that type_name::get<P>() matches frame.step_types[pipeline.current_step].
/// Removes the step payload from the frame's dynamic fields.
/// Constructs an ExecutionRequest<P> carrying the composite_proposal_id.
/// Increments pipeline.current_step.
///
/// The returned ExecutionRequest<P> must be consumed by the step's handler.
/// The returned Pipeline must be passed to the next advance_step or finalize_pipeline.
public fun advance_step<P: store>(
    pipeline: Pipeline,
    frame: &mut CompositeFrame,
): (P, ExecutionRequest<P>, Pipeline);

/// Finalize the pipeline. Aborts if current_step != total_steps (steps remain unconsumed).
/// Consumes the pipeline hot potato. Must be the last call in the execution PTB.
public fun finalize_pipeline(pipeline: Pipeline);
```

#### Package-internal API

```move
/// Seal the frame into a CompositePayload and return the UID for sharing.
/// Only callable by board_voting::submit_composite within the same package.
public(package) fun seal_and_share_frame(frame: CompositeFrame): CompositePayload;
```

---

### 6.2 `board_voting.move` (extended)

**Package**: `armature_framework`
**Path**: `packages/armature_framework/sources/board_voting.move`

One new function is added. Existing `submit_proposal` and `authorize_execution` are unchanged.

```move
/// Submit a composite proposal.
///
/// Accepts an owned CompositeFrame from the submission PTB.
/// Computes the effective ProposalConfig (see §8).
/// Calls composite::seal_and_share_frame (shares the frame).
/// Calls proposal::create<CompositePayload> (shares the proposal).
///
/// The proposer must be a board member.
/// The frame must have at least one step (EEmptyComposite).
/// The "Composite" type_key must be enabled in the DAO.
#[allow(lint(share_owned, custom_state_change))]
public fun submit_composite(
    dao: &DAO,
    frame: CompositeFrame,
    metadata_ipfs: Option<String>,
    clock: &Clock,
    ctx: &mut TxContext,
);
```

`authorize_execution<CompositePayload>` works without modification — it treats
`CompositePayload` as any other proposal type. The frame validation happens inside
`begin_pipeline`.

---

### 6.3 `composite_ops.move` (new)

**Package**: `armature_proposals`
**Path**: `packages/armature_proposals/sources/composite/composite_ops.move`

Provides composite-compatible handler variants for each proposal type that reads
`proposal.payload()` in its existing handler. Existing handlers are not modified.

The adapter pattern is:

```
Existing handler (unchanged):
  execute_foo(dao, &Proposal<Foo>, ExecutionRequest<Foo>, ctx)
  └─ reads proposal.payload()
  └─ calls proposal::finalize(request, proposal)

New composite variant:
  execute_foo_step(dao, payload: Foo, ExecutionRequest<Foo>, ctx)
  └─ receives payload directly from advance_step
  └─ calls proposal::consume_execution_request(request)
```

The `ExecutionRequest<P>` returned by `advance_step` carries `proposal_id =
composite_proposal_id`. Calling `proposal::finalize` would require a `Proposal<P>` whose ID
matches — no such object exists. Composite handlers must use `consume_execution_request`.

#### Handlers to implement

**Treasury**

```move
pub fun execute_send_coin_step<T>(
    vault: &mut TreasuryVault,
    payload: SendCoin<T>,
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
);

pub fun execute_send_coin_to_dao_step<T>(
    source_vault: &mut TreasuryVault,
    target_vault: &mut TreasuryVault,
    payload: SendCoinToDAO<T>,
    request: ExecutionRequest<SendCoinToDAO<T>>,
    ctx: &mut TxContext,
);
```

Note: `SendSmallPayment` is **excluded from composite composition** (see §11). Its epoch-state
management interacts poorly with batch execution ordering; treat this as a blocked type.

**SubDAO**

```move
pub fun execute_create_subdao_step(
    vault: &mut CapabilityVault,
    payload: CreateSubDAO,
    request: ExecutionRequest<CreateSubDAO>,
    ctx: &mut TxContext,
);

pub fun execute_transfer_cap_step<T: key + store>(
    source_vault: &mut CapabilityVault,
    target_vault: &mut CapabilityVault,
    payload: TransferCapToSubDAO,
    request: ExecutionRequest<TransferCapToSubDAO>,
);
```

**Admin**

```move
pub fun execute_update_metadata_step(
    charter: &mut Charter,
    payload: UpdateMetadata,
    request: ExecutionRequest<UpdateMetadata>,
);
```

`DisableProposalType`, `EnableProposalType`, and `UpdateProposalConfig` are blocked (§11).

**Board**

```move
pub fun execute_add_member_step(
    dao: &mut DAO,
    payload: AddMember,
    request: ExecutionRequest<AddMember>,
);

pub fun execute_remove_member_step(
    dao: &mut DAO,
    payload: RemoveMember,
    request: ExecutionRequest<RemoveMember>,
);
```

`SetBoard` is blocked (§11) — full board replacement in a composite is too high-risk.

---

### 6.4 `dao.move` (extended)

**Package**: `armature_framework`

Two additions:

#### 6.4.1 `max_composite_steps` DAO config field

```move
public struct DAO has key, store {
    ...
    max_composite_steps: u64,   // default: 5
}
```

Read by `add_step` (passed in as `max_steps` parameter) and enforced at submission time.
Configurable via `UpdateProposalConfig` targeting `"Composite"`.

Alternative considered: store `max_steps` inside the `"Composite"` ProposalConfig as a
reuse of an existing field (e.g., `propose_threshold`). Rejected — semantic overloading of
`propose_threshold` for a conceptually different purpose is confusing.

#### 6.4.2 `"Composite"` default proposal type

`"Composite"` is added to `DEFAULT_PROPOSAL_TYPES` with a default config:

| Field | Default | Rationale |
|---|---|---|
| `quorum` | 5000 (50%) | Matches DAO default; effective config may raise it |
| `approval_threshold` | 6600 (66%) | Higher floor than standard 50%; composites affect multiple subsystems |
| `propose_threshold` | 0 | Unchanged — any board member may propose |
| `expiry_ms` | 604_800_000 (7d) | Standard window |
| `execution_delay_ms` | 0 | None by default |
| `cooldown_ms` | 0 | None by default |

The default `approval_threshold` of 66% is a floor. `submit_composite` computes the
effective config (§8) and may raise it further.

---

## 7. Lifecycle Flows

### 7.1 Submission PTB

```
// 1. Create owned frame
let frame = composite::new_frame(dao.id(), ctx);

// 2. Add steps (validates type_key, binding, blocked list, step count)
composite::add_step<CreateSubDAO>(
    &mut frame, dao, b"CreateSubDAO".to_ascii_string(),
    create_subdao::new(name, description, initial_board, metadata),
    dao.max_composite_steps(),
);
composite::add_step<SendCoinToDAO<SUI>>(
    &mut frame, dao, b"SendCoinToDAOSUI".to_ascii_string(),
    send_coin_to_dao::new<SUI>(target_treasury_id, amount),
    dao.max_composite_steps(),
);
composite::add_step<TransferCapToSubDAO>(
    &mut frame, dao, b"TransferCapToSubDAO".to_ascii_string(),
    transfer_cap_to_subdao::new(cap_id, subdao_id),
    dao.max_composite_steps(),
);

// 3. Submit (shares frame + proposal; voting begins)
board_voting::submit_composite(dao, frame, option::none(), clock, ctx);
```

After this PTB:
- `CompositeFrame` is shared with 3 dynamic fields
- `Proposal<CompositePayload>` is shared with `status: Active`
- Voting is open

### 7.2 Voting

Unchanged from the existing flow. Members call `proposal::vote<CompositePayload>` on
the shared proposal object. The effective ProposalConfig (see §8) governs quorum and
threshold. When the threshold is met, `status` transitions to `Passed`.

No changes to the voting module.

### 7.3 Execution PTB

After the execution delay elapses (if configured):

```
// 1. Authorize execution (standard flow — no changes)
let req = board_voting::authorize_execution<CompositePayload>(
    dao, composite_proposal, freeze, clock, ctx
);

// 2. Begin pipeline (validates frame matches proposal, consumes CompositePayload req)
let pipeline = composite::begin_pipeline(composite_proposal, req, composite_frame);

// 3. Step 1: CreateSubDAO
let (subdao_payload, subdao_req, pipeline) =
    composite::advance_step<CreateSubDAO>(pipeline, composite_frame);
composite_ops::execute_create_subdao_step(cap_vault, subdao_payload, subdao_req, ctx);

// 4. Step 2: SendCoinToDAO
let (fund_payload, fund_req, pipeline) =
    composite::advance_step<SendCoinToDAO<SUI>>(pipeline, composite_frame);
composite_ops::execute_send_coin_to_dao_step<SUI>(
    treasury, target_treasury, fund_payload, fund_req, ctx
);

// 5. Step 3: TransferCapToSubDAO
let (cap_payload, cap_req, pipeline) =
    composite::advance_step<TransferCapToSubDAO>(pipeline, composite_frame);
composite_ops::execute_transfer_cap_step<SomeCapType>(
    cap_vault, subdao_vault, cap_payload, cap_req
);

// 6. Finalize (aborts if steps remain)
composite::finalize_pipeline(pipeline);

// PTB atomicity: if any step above fails (Move abort or runtime error),
// the entire transaction is rolled back.
```

---

## 8. Effective ProposalConfig Derivation

`submit_composite` computes the effective `ProposalConfig` by taking the component-wise
maximum across all step configs and the `"Composite"` type's own config from the DAO.

```
effective_quorum           = max(composite_config.quorum,
                                 step_1_config.quorum,
                                 step_2_config.quorum, ...)

effective_threshold        = max(composite_config.approval_threshold,
                                 step_1_config.approval_threshold,
                                 step_2_config.approval_threshold, ...)

effective_propose_threshold = max(composite_config.propose_threshold,
                                  step_1_config.propose_threshold, ...)

effective_expiry_ms        = max(all)
effective_execution_delay  = max(all)
effective_cooldown_ms      = max(all)
```

This is a **safety property**: composites can never be approved under lower requirements
than any of their constituent operations would individually require.

**Cooldown semantics**: Each step type's individual cooldown is **not** checked during composite
execution (only the composite type's cooldown is tracked in `last_executed_at`). This is
intentional — the composite is one governance action, not N independent ones. If per-type
cooldown enforcement is needed, it must be implemented within the individual step handlers.

**Config storage**: The effective config is computed transiently in `submit_composite` and
written into the `Proposal<CompositePayload>` at creation time (via `proposal::create`). It
is not persisted separately; the proposal's config field holds the effective values.

---

## 9. Handler Adapter Pattern

This section documents the exact structural transformation from an existing single-proposal
handler to its composite-compatible counterpart.

### Pattern

| | Single-proposal handler | Composite step handler |
|---|---|---|
| Payload source | `proposal.payload()` (from `&Proposal<P>`) | `payload: P` (from `advance_step`) |
| Request consumption | `proposal::finalize(request, proposal)` | `proposal::consume_execution_request(request)` |
| DAO ID validation | `assert!(vault.dao_id() == request.req_dao_id())` | same |
| Object validation | via `proposal.payload()` accessors | via `payload` accessors (identical) |
| Event emission | identical | identical |

### Worked example: `execute_send_coin` → `execute_send_coin_step`

**Existing (unchanged):**

```move
pub fun execute_send_coin<T>(
    vault: &mut TreasuryVault,
    proposal: &Proposal<SendCoin<T>>,
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    let payload = proposal.payload();
    let coin = vault.withdraw<T, SendCoin<T>>(payload.amount(), &request, ctx);
    event::emit(CoinSent { ... });
    transfer::public_transfer(coin, payload.recipient());
    proposal::finalize(request, proposal);  // ← requires &Proposal<SendCoin<T>>
}
```

**New composite variant:**

```move
pub fun execute_send_coin_step<T>(
    vault: &mut TreasuryVault,
    payload: SendCoin<T>,               // ← from advance_step (by value)
    request: ExecutionRequest<SendCoin<T>>,
    ctx: &mut TxContext,
) {
    assert!(vault.dao_id() == request.req_dao_id(), EVaultDAOMismatch);
    let coin = vault.withdraw<T, SendCoin<T>>(payload.amount(), &request, ctx);
    event::emit(CoinSent { ... });
    transfer::public_transfer(coin, payload.recipient());
    proposal::consume_execution_request(request);  // ← no Proposal<P> needed
}
```

The transformation is mechanical. The only semantic change is request consumption.

### Third-party handler compatibility

Third-party handlers that already use `consume_execution_request` (the recommended
pattern for handlers that don't receive the Proposal object) are automatically composite-
compatible without any changes. They receive `ExecutionRequest<P>` from `advance_step`
and call `consume_execution_request` exactly as today.

Third-party handlers that use `finalize(request, proposal)` require a composite variant to
be authored by the third party — the framework cannot produce one automatically.

---

## 10. DAO Registration and Type Bindings

### 10.1 Enabling `"Composite"` as a proposal type

`"Composite"` is added to `DEFAULT_PROPOSAL_TYPES` in `dao.move`, so all new DAOs have it
enabled by default. Existing DAOs must vote to enable it via `EnableProposalType`.

The type binding for `"Composite"` is set to `armature::composite::CompositePayload` in
`execute_enable_proposal_type` (the same binding mechanism used for all other types).

### 10.2 Step type validation at `add_step` time

`add_step<P>` validates each step before the frame is submitted for voting:

```
1. assert type_key ∈ dao.enabled_proposal_types()
2. if dao.has_type_binding(type_key):
       assert dao.type_binding_for(type_key) == type_name::with_defining_ids<P>().into_string()
3. assert type_key ∉ BLOCKED_COMPOSITE_TYPE_KEYS
4. assert frame.step_types.length() < max_steps
```

This is the same type-spoofing protection from §3b of the open-proposal-type security work,
applied at the composite submission layer. A malicious board member cannot substitute a
different payload type under an approved type_key.

### 10.3 `max_composite_steps` configuration

The `DAO` gains a `max_composite_steps: u64` field (default `5`). It is passed to `add_step`
by the caller and enforced there. It is also re-validated in `submit_composite`.

Changing `max_composite_steps` requires an `UpdateProposalConfig` targeting `"Composite"`.
Since `UpdateProposalConfig` itself is a blocked composite step, this cannot be embedded in
a composite — it must be its own proposal.

---

## 11. Blocked and Restricted Types

The following type_keys are forbidden as composite steps. `add_step` aborts with
`EIncomposableType` if any is used.

| Type key | Reason for blocking |
|---|---|
| `"Composite"` | No nested composites. Flat bundles only. |
| `"UpdateProposalConfig"` | Could lower thresholds of step types mid-bundle, enabling threshold manipulation in a single vote. |
| `"EnableProposalType"` | Could enable a type, then immediately use it in the same bundle before governance reviews the new type. |
| `"DisableProposalType"` | Could disable a type, then use the now-absent config in the same bundle. |
| `"UnfreezeProposalType"` | Could unfreeze a frozen type and immediately use it. |
| `"TransferFreezeAdmin"` | Administrative safety cap — should require its own deliberate vote. |
| `"SetBoard"` | Full board replacement in a composite is too high-impact; must be deliberate. |
| `"SendSmallPayment"` | Epoch-state management is incompatible with composite ordering (see §6.3). |
| `"SpawnDAO"` | Puts the DAO into Migrating status; subsequent steps in the same composite would operate on a Migrating DAO, which is undefined behavior. |

Types not on this list are composable, including third-party types enabled via
`EnableProposalType`.

---

## 12. Security Analysis

### 12.1 Step type substitution (spoofed payload)

**Threat**: The PTB executor calls `advance_step<WrongType>` instead of the type recorded
for that step.

**Mitigation**: `advance_step<P>` asserts `type_name::get<P>() == frame.step_types[current_step]`.
TypeName comparison is collision-free in Move. An incorrect P causes an abort.

### 12.2 Step skipping or reordering

**Threat**: Executor skips `advance_step` for step 2 and calls step 3's handler directly.

**Mitigation**: Step handlers receive `ExecutionRequest<P>` only from `advance_step`. There
is no other way to obtain one for a composite proposal (the composite's ExecutionRequest is
consumed by `begin_pipeline`). Skipping `advance_step` means the handler has no
`ExecutionRequest<P>` to consume — the PTB cannot be constructed.

### 12.3 Finalize bypass

**Threat**: Executor calls all step handlers but omits `finalize_pipeline`, leaving the
pipeline hot potato uncollected.

**Mitigation**: `Pipeline` has no abilities. It cannot be dropped, stored, or transferred.
Move's hot-potato drop check enforces that all hot potatoes created in a PTB are consumed
by the end of the transaction. The PTB aborts if `Pipeline` is not consumed.

### 12.4 Partial execution via PTB failure injection

**Threat**: Executor crafts a PTB where one step handler always fails, then submits it
to claim execution but not actually execute all steps.

**Mitigation**: PTB atomicity is an invariant of the Sui execution engine. If any command
in the PTB fails, all state changes from that transaction are rolled back. The proposal
status remains `Passed` (not `Executed`), and the executor must retry with a correct PTB.

### 12.5 Frame mutation after voting begins

**Threat**: After the `CompositeFrame` is shared and the proposal is Active, a malicious
actor modifies the frame to change what steps will execute.

**Mitigation**: `CompositeFrame` has no public mutator functions. The only functions that
take `&mut CompositeFrame` are `add_step` (called before sharing) and `advance_step`
(which only removes dynamic fields — it cannot add or replace them). Once the frame is
shared, its step set is immutable.

The frame's `step_types` vector is also copied into `CompositePayload` at submission time.
`begin_pipeline` asserts that the live frame matches the proposal's recorded step_types.
An attacker who somehow managed to add dynamic fields to the frame could not cause
`advance_step` to use them — the step index is bounded by `total_steps` from the pipeline,
which is derived from the proposal's payload copy, not the live frame.

### 12.6 Threshold manipulation via composition blocking

**Threat**: A composite includes `UpdateProposalConfig` to lower the approval_threshold for
a step type, making it easier to pass composites containing that type in the future.

**Mitigation**: `UpdateProposalConfig` is on the blocked list. `add_step` rejects it.

### 12.7 Cross-DAO frame injection

**Threat**: Executor passes a `CompositeFrame` from DAO A into a composite proposal for
DAO B.

**Mitigation**: `begin_pipeline` asserts `frame.dao_id == proposal.dao_id()`. Frames are
created with `new_frame(dao_id)` and the dao_id is set at creation time and never mutable.

### 12.8 `ExecutionRequest<P>` reuse across composites

**Threat**: `ExecutionRequest<P>` from step 1 of composite X is used in step 1 of
composite Y (if the executor somehow has two concurrent composites in flight).

**Mitigation**: `ExecutionRequest<P>` carries `proposal_id = composite_proposal_id`. The
step handler receives the payload by value and calls `consume_execution_request`. There is
no `proposal::finalize` check for composites, so `proposal_id` is carried for audit
purposes only. The real guard is that each request is a hot potato — it cannot be stored
and reused across transactions.

---

## 13. Testing Strategy

### 13.1 Unit tests for `composite.move`

| Test | Validates |
|---|---|
| `test_frame_creation` | `new_frame` sets dao_id, empty step vectors |
| `test_add_step_validates_type_key` | ETypeNotEnabled on unknown key |
| `test_add_step_validates_binding` | ETypeMismatch on wrong P for bound key |
| `test_add_step_blocks_forbidden_type` | EIncomposableType for each blocked key |
| `test_add_step_respects_max_steps` | EStepLimitExceeded when at capacity |
| `test_advance_step_type_mismatch` | EStepTypeMismatch on wrong P |
| `test_finalize_pipeline_incomplete` | EPipelineIncomplete when steps remain |
| `test_finalize_pipeline_complete` | Success when all steps consumed |
| `test_begin_pipeline_frame_mismatch` | EFrameProposalMismatch on wrong frame |
| `test_begin_pipeline_dao_mismatch` | EFrameDAOMismatch on wrong DAO |

### 13.2 Integration tests for the full lifecycle

| Test | Scenario |
|---|---|
| `test_composite_2step_happy_path` | CreateSubDAO + SendCoinToDAO |
| `test_composite_3step_happy_path` | CreateSubDAO + SendCoinToDAO + TransferCap |
| `test_composite_fails_on_step_abort` | One handler fails → full rollback |
| `test_composite_effective_config` | Highest threshold across steps is used |
| `test_composite_execution_delay` | Respects max execution_delay_ms |
| `test_composite_cooldown` | Cooldown enforced on Composite type_key |
| `test_composite_blocked_type` | Rejects UpdateProposalConfig in bundle |
| `test_composite_empty_frame` | Rejects zero-step submission |

### 13.3 Regression tests for existing handlers

All existing handler tests must pass without modification. `composite_ops` handlers have
parallel tests that mirror existing test coverage but use the `_step` variants.

---

## 14. Migration Checklist

Changes are additive — no existing on-chain data structures change. Existing proposals
and DAOs continue to function without modification.

### Phase 1: Framework (`armature_framework`)

- [ ] Add `StepKey`, `CompositeFrame`, `CompositePayload`, `Pipeline` to `composite.move`
- [ ] Implement `new_frame`, `add_step`, `begin_pipeline`, `advance_step`, `finalize_pipeline`
- [ ] Implement `seal_and_share_frame` (package-internal)
- [ ] Add `submit_composite` to `board_voting.move`
- [ ] Add `max_composite_steps: u64` to `DAO` struct with default `5`
- [ ] Add `"Composite"` to `DEFAULT_PROPOSAL_TYPES` with 66% threshold default
- [ ] Add `max_composite_steps` accessor to `dao.move`
- [ ] Write unit tests for `composite.move`

### Phase 2: Proposal handlers (`armature_proposals`)

- [ ] Create `packages/armature_proposals/sources/composite/` directory
- [ ] Implement `composite_ops.move` with `_step` variants for all composable types
- [ ] Write integration tests for all `_step` handlers

### Phase 3: Integration tests

- [ ] Full lifecycle integration tests (submission → voting → execution)
- [ ] Negative tests (blocked types, type mismatches, step skipping attempts)
- [ ] Regression tests confirming existing handler tests pass unchanged

### Phase 4: Client / indexer

- [ ] Update PTB construction in client SDK to support composite submission flow
- [ ] Index `CompositeFrame` creation and step consumption events
- [ ] Display effective ProposalConfig (not the DAO's base Composite config) in proposal UI
- [ ] Emit per-step execution events for auditability (optional — may add `StepExecuted` event)

### Phase 5: Existing DAO enablement

- [ ] Existing DAOs must pass `EnableProposalType { type_key: "Composite", ... }` proposals
  to opt in. (New DAOs get it by default via `DEFAULT_PROPOSAL_TYPES`.)
- [ ] Document the `EnableProposalType` proposal config recommendation (66% threshold minimum)

---

## 15. Open Questions

| # | Question | Current position | Revisit trigger |
|---|---|---|---|
| 1 | **Should `finalize_pipeline` also delete the `CompositeFrame`?** | No — keep as audit record. Frame has no dynamic fields left after execution; storage cost is minimal. | If storage rebates become a significant concern. |
| 2 | **Should per-step `last_executed_at` cooldowns be enforced?** | No — composite is one governance event; cooldown tracked on `"Composite"` key only. | If a DAO needs per-type rate-limiting within composites. |
| 3 | **Should `SetBoard` be composable?** | Blocked — too high-impact. | If a clear use case emerges (e.g., board restructure + SubDAO delegation must be atomic). |
| 4 | **Should a `StepExecuted` event be emitted per step?** | Not in initial design. | If indexers need per-step granularity for audit logs. |
| 5 | **Can `max_composite_steps` be stored in `ProposalConfig` instead of `DAO` directly?** | No — semantic overloading of ProposalConfig fields is undesirable. | If the DAO struct field count becomes an issue. |
| 6 | **What is the correct max_steps upper bound?** | Enforcement via config (default 5). Hard ceiling TBD. | After PTB gas analysis; 10 is likely a practical ceiling given Move call overhead. |
| 7 | **Should composite submissions require a dedicated `CompositeConfig` object?** | No — the DAO's `ProposalConfig` for `"Composite"` + the `max_composite_steps` field is sufficient. | If new composite-specific config fields are needed beyond step count. |
