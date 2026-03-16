# Stretch: Proposal Composition

> Part of the [stretch features index](00_index.md). Not in hackathon scope.
>
> Tracks [Issue #1](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/1).

Enable bundling multiple proposals into a single **Composite Proposal** that is voted on once and executed atomically via a **hot potato pipeline** pattern. The pipeline acts as a state machine enforcing valid execution order — if any step fails, the entire PTB aborts.

---

## Motivation

Many real governance operations are inherently multi-step:

- **Create SubDAO + fund it + delegate capability** — 3 separate votes today, with risk of partial completion (SubDAO exists but unfunded)
- **Amend charter + allocate treasury for implementation** — meaningless if only half passes
- **Board restructuring + freeze admin transfer** — dangerous in isolation
- **Federation formation + initial contribution** — incomplete if done separately

Sequential voting creates **governance overhead** (N vote cycles x voting window) and **consistency risk** (partial execution leaves DAO in intermediate state).

## Design

### Core Mechanism

Layer on top of the existing `ExecutionRequest<P>` hot potato without modifying any existing proposal handlers.

```move
/// Stored as the composite proposal's payload
struct CompositePayload has store {
    step_types: vector<TypeName>,  // ordered execution sequence
    // per-step payloads stored as dynamic fields on the Proposal, keyed by step index
}

/// Hot potato pipeline — returned when the composite proposal passes vote
struct Pipeline /* no abilities */ {
    composite_id: ID,
    dao_id: ID,
    current_step: u64,
    total_steps: u64,
}

/// Advance pipeline: validates current step matches type P, returns typed ExecutionRequest
public fun advance_step<P>(pipeline: Pipeline, ...): (ExecutionRequest<P>, Pipeline) {
    assert!(step_types[pipeline.current_step] == type_name::get<P>());
    // extract step payload from dynamic field
    // construct ExecutionRequest<P>
    // advance current_step
}

/// Consume pipeline after final step — aborts if steps remain
public fun finalize(pipeline: Pipeline) {
    assert!(pipeline.current_step == pipeline.total_steps);
    let Pipeline { composite_id: _, dao_id: _, current_step: _, total_steps: _ } = pipeline;
}
```

### Execution Flow (PTB)

```
1. execute_composite(proposal)     -> Pipeline
2. advance_step<CreateSubDAO>(p)   -> (ExecutionRequest<CreateSubDAO>, Pipeline)
3. handle_create_subdao(req, ...)  -> () [existing handler, unchanged]
4. advance_step<SendCoinToDAO>(p)  -> (ExecutionRequest<SendCoinToDAO>, Pipeline)
5. handle_send_coin_to_dao(req,..) -> () [existing handler, unchanged]
6. finalize(pipeline)              -> () [pipeline consumed, all steps verified]
```

If any step fails or `finalize` is not called, the PTB aborts atomically.

### Composition Rules

DAOs should be able to configure which compositions are valid:

```move
struct CompositionConfig has store, copy, drop {
    max_steps: u64,                                  // cap bundle size (e.g., 5)
    allowed_combinations: vector<vector<TypeName>>,  // explicit allowlist, OR
    blocked_pairs: vector<(TypeName, TypeName)>,     // incompatible pairs
}
```

Options to explore:
1. **Unrestricted** — any enabled proposal types can compose (simplest)
2. **Allowlist** — only pre-approved bundles (safest, least flexible)
3. **Blocklist** — any combination except incompatible pairs (balanced)
4. **Template-based** — named recipes like "SubDAO Setup" = [CreateSubDAO, SendCoinToDAO, TransferCapToSubDAO]

### Why Hot Potato Is the Right Pattern

- **Move-native** — hot potatoes are the idiomatic way to enforce ordered state machines in Sui
- **Composable** — the Pipeline doesn't know about handler internals; each `advance_step` produces a standard `ExecutionRequest<P>` that existing handlers consume unchanged
- **Safe** — no abilities on Pipeline means it cannot be stored, copied, or dropped; must be finalized in the same PTB
- **Extensible** — adding new proposal types to compositions requires zero changes to the pipeline module

## Challenges and Open Questions

1. **Type erasure for payloads** — Composite stores heterogeneous payloads via dynamic fields keyed by step index. The PTB executor must know types at construction time. This is a client-side concern, not a Move limitation.

2. **PTB size limits** — A 5-step composite means 5+ Move calls in one PTB. Should be fine for typical bundles but may hit gas limits for very complex compositions. `max_steps` config mitigates this.

3. **Voting threshold** — Should composites use the *highest* threshold among component types? The *average*? A separate composite-specific threshold? Highest-of-components is safest.

4. **Self-referential compositions** — Can a composite include `UpdateProposalConfig` alongside other types? Probably should be blocked to avoid threshold manipulation within the same vote.

5. **Nested composition** — Can a composite contain another composite? Probably not — flat bundles only, enforced at creation time.

## Scope

- **Phase**: Post-MVP enhancement (requires stable single-proposal flow first)
- **Dependencies**: Core proposal system, ExecutionRequest pattern
- **Modules affected**: New `composite.move` module; minor additions to `proposal.move` for composite creation; zero changes to existing handlers

---

**See also:** [Open Proposal Type Set](11_open_proposal_type_set.md) — third-party types compose naturally with the pipeline since `advance_step` is generic over `P`.
