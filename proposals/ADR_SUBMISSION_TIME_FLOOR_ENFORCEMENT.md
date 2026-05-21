# ADR: Enforce Execution Floors at Proposal Submission

| Field          | Value                                         |
| -------------- | --------------------------------------------- |
| **Status**     | Proposed                                      |
| **Date**       | 2026-05-13                                    |
| **Authors**    | —                                             |
| **Package**    | `armature_framework` / `armature_proposals`   |
| **Depends on** | `ADR_COMPOSABLE_PROPOSALS` (Option E)         |
| **Supersedes** | `ADR_MONOTONIC_EXECUTION_FLOORS.md`           |

---

## Context

The Armature framework currently encodes two approval floors as **hardcoded constants**
enforced inside **execution-time handlers**:

| Type | Floor | Constant | Enforcement site |
|---|---|---|---|
| `EnableProposalType` | 66% of `total_snapshot_weight` | `ENABLE_APPROVAL_FLOOR_BPS = 6_600` | `execute_enable_proposal_type` |
| `UpdateProposalConfig` (self-targeting) | 80% of `total_snapshot_weight` | `SELF_UPDATE_APPROVAL_FLOOR_BPS = 8_000` | `execute_update_proposal_config` |

Both handlers assert:

```rust
assert!(
    proposal.yes_weight() * 10_000 / proposal.total_snapshot_weight() >= FLOOR_BPS,
    EApprovalFloorNotMet
);
```

This is safe and correct for **single-action proposals**, because `&Proposal<P>` is
always available in the handler.

### The Composability Conflict

`ADR_COMPOSABLE_PROPOSALS` (Option E) introduces `_step` handler variants:

```rust
pub fun execute_enable_proposal_type_step(
    dao: &mut DAO,
    payload: EnableProposalType,          // payload by value — no &Proposal<P>
    request: ExecutionRequest<EnableProposalType>,
    clock: &Clock,
) { ... }
```

The `_step` variant receives the payload by value and has **no `&Proposal<P>`
reference**. The floor `assert!` references `proposal.yes_weight()` and
`proposal.total_snapshot_weight()`, which are not available here. The assertion
physically cannot execute. This means both floor-gated types must be
`composable_allowed = false`, permanently blocking them from composite proposals.

### The Insight

The execution-time check exists to guarantee: *"the actual vote that passed this
proposal met the floor."*

But this guarantee holds equally well if enforced one step earlier — at **submission
time** — by asserting that the proposal's **configured `approval_threshold`** meets
the floor. Because:

> A proposal only executes if it passed. A proposal passes only if
> `yes_weight / total_snapshot_weight >= approval_threshold`. Therefore, if
> `approval_threshold >= FLOOR` is required at submission, then at execution time
> `yes_weight / total_snapshot_weight >= approval_threshold >= FLOOR` is guaranteed.

This means the floor can be fully enforced with no handler changes and no `&Proposal<P>`
reference in `_step` variants.

---

## Decision

Keep the hardcoded floor constants unchanged. Move the floor assertion from
execution-time handlers into **submission-time validation** (`propose()` for
single-action proposals, `submit_composite()` for composites). Remove the
execution-time `assert!` from `execute_enable_proposal_type` and the self-targeting
branch of `execute_update_proposal_config`. `_step` handlers require no changes.

---

## Constraints

Any solution must preserve:

1. **Self-referential attack immunity** — `UpdateProposalConfig` targeting itself must
   require supermajority approval. The floor check must apply to the proposal's own
   `approval_threshold`, not only to what it sets in the payload.
2. **Floor inviolability** — the constants `ENABLE_APPROVAL_FLOOR_BPS` and
   `SELF_UPDATE_APPROVAL_FLOOR_BPS` remain hardcoded; no governance action can change
   them.
3. **Backwards compatibility** — existing single-action proposals must behave
   identically; only the site of enforcement changes, not the outcome.
4. **Composable correctness** — `advance_step` must guarantee the floor was met for
   any composite step without needing access to the composite proposal's vote data.

---

## Proposed Design

### 1. Submission-Time Validation in `propose()`

`armature_framework::proposal` exposes a `propose<P>()` entry that creates a
`Proposal<P>` from a `ProposalConfig` snapshot. Add a hook allowing types to declare
a minimum `approval_threshold` requirement:

```rust
// armature_framework::floors (new module, or inline in proposal.move)

const ENABLE_APPROVAL_FLOOR_BPS:      u16 = 6_600;
const SELF_UPDATE_APPROVAL_FLOOR_BPS: u16 = 8_000;

/// Called by propose() before the Proposal is created.
/// Aborts if the proposal's configured approval_threshold is below the
/// hardcoded floor for this type + context combination.
public(package) fun assert_submission_floor<P: store>(
    config: &ProposalConfig,
    payload: &P,
) {
    // EnableProposalType: always requires floor
    if (type_name::get<P>() == type_name::get<EnableProposalType>()) {
        assert!(config.approval_threshold() >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
    };

    // UpdateProposalConfig: requires floor only when targeting itself
    if (type_name::get<P>() == type_name::get<UpdateProposalConfig>()) {
        let payload_ref = (payload as &UpdateProposalConfig);
        if (payload_ref.target_type() == type_name::get<UpdateProposalConfig>()) {
            assert!(
                config.approval_threshold() >= SELF_UPDATE_APPROVAL_FLOOR_BPS,
                EFloorNotMet
            );
        };
    };
}
```

`propose<P>()` calls `assert_submission_floor<P>(config, payload)` before constructing
the `Proposal<P>` object. No changes to any execution handler.

### 2. Submission-Time Validation in `submit_composite()`

When a composite proposal is submitted, the framework already computes an
**effective config** by taking `max()` over all step types' configs. Add a floor
check at the same point:

```rust
public fun submit_composite(
    dao: &mut DAO,
    frame: &CompositeFrame,
    config: ProposalConfig,
    clock: &Clock,
    ctx: &mut TxContext,
): Proposal<CompositePayload> {
    // Existing: effective approval_threshold = max over all step configs
    let effective_threshold = compute_effective_threshold(dao, frame, &config);

    // NEW: for each step type in the frame, assert the effective threshold
    // meets that step's hardcoded floor.
    assert_composite_floors(dao, frame, effective_threshold);

    // ... construct Proposal<CompositePayload> ...
}

fun assert_composite_floors(dao: &DAO, frame: &CompositeFrame, effective_threshold: u16) {
    let i = 0;
    while (i < frame.step_count()) {
        let step_type = frame.step_type_at(i);

        if (step_type == type_name::get<EnableProposalType>()) {
            assert!(effective_threshold >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
        };

        if (step_type == type_name::get<UpdateProposalConfig>()) {
            // For composites, the self-targeting check is conservative:
            // always apply the self-update floor if UpdateProposalConfig
            // appears as a step. The payload's target_type is inspected
            // from the frame's stored step data.
            let step_payload = frame.step_payload_at<UpdateProposalConfig>(i);
            if (step_payload.target_type() == type_name::get<UpdateProposalConfig>()) {
                assert!(effective_threshold >= SELF_UPDATE_APPROVAL_FLOOR_BPS, EFloorNotMet);
            };
        };

        i = i + 1;
    };
}
```

Because `effective_threshold` is already the `max()` of all step configs, asserting
`effective_threshold >= FLOOR` is equivalent to asserting the composite will only
execute (pass) with a vote that meets the floor. No changes to `advance_step`.

### 3. Remove Execution-Time Floor Checks

Once submission-time enforcement is in place, the execution-time assertions are
redundant. They can be removed from:

- `execute_enable_proposal_type` — remove the `ENABLE_APPROVAL_FLOOR_BPS` `assert!`
- `execute_update_proposal_config` — remove the self-targeting `SELF_UPDATE_APPROVAL_FLOOR_BPS` `assert!`

**Defense-in-depth option:** Keep the execution-time assertions as comments or behind
a `#[cfg(test)]` flag for invariant auditing, but do not abort in production. This
avoids double-maintenance while preserving the rationale in code.

### 4. `composable_allowed` Unblocked

With floor checks now in `submit_composite()` rather than `advance_step()`, the
framework invariant that previously blocked `composable_allowed = true` for floor-gated
types is no longer necessary. Remove:

```rust
// REMOVE from execute_update_proposal_config handler:
if (is_floor_gated(payload.target_type)) {
    assert!(!new_composable_allowed, ECannotEnableComposabilityForFloorGatedType);
};
```

`UpdateProposalConfig` and `EnableProposalType` can now be set to
`composable_allowed = true` by governance (default remains `false`).

---

## Correctness Proof

**Claim:** Submission-time enforcement of `approval_threshold >= FLOOR` guarantees
`yes_weight / total_snapshot_weight >= FLOOR` at execution time.

**Proof:**

1. `propose()` asserts `approval_threshold >= FLOOR` → proposal is created only if
   this holds.
2. The proposal's `approval_threshold` is **snapshotted** at creation time into the
   `Proposal<P>` object and cannot be changed post-creation.
3. A proposal only transitions to `Executable` state (and only reaches the handler)
   if `yes_weight / total_snapshot_weight >= approval_threshold` (standard passing
   condition, enforced by `close_vote()`).
4. Therefore at execution time: `yes_weight / total_snapshot_weight >= approval_threshold >= FLOOR`. QED.

The same chain holds for composites: `effective_threshold >= FLOOR` (step 1),
`effective_threshold` is fixed at composite creation (step 2), composite only passes
if `yes_weight / total_snapshot_weight >= effective_threshold` (step 3).

---

## Security Analysis

### Self-Referential Attack

**Attack:** Submit `UpdateProposalConfig` self-targeting with `approval_threshold = 51%`
to lower the self-update floor requirement.

**Old (execution-time):** The proposal can be *created* at 51%, but at execution the
hardcoded `assert!` checks `yes_weight >= 80%` and aborts if not met.

**New (submission-time):** `propose()` asserts `config.approval_threshold >= 8000`.
The proposal is **rejected at creation** if `approval_threshold < 80%`. It is
impossible to even submit the downgrade attack.

This is strictly stronger than execution-time enforcement: the malicious proposal
never enters the shared object graph, never consumes a proposal slot, and cannot be
voted on.

### Floor Constant Inviolability

The constants `ENABLE_APPROVAL_FLOOR_BPS` and `SELF_UPDATE_APPROVAL_FLOOR_BPS` remain
hardcoded in the framework package — no governance action touches them. `UpdateProposalConfig`
payloads set `approval_threshold` on `ProposalConfig`, not these constants. The constants
are pure code, not state.

### Can `approval_threshold` Be Lowered After Creation?

No. `ProposalConfig` has `copy, drop, store` but is snapshotted into the `Proposal<P>`
object at creation. The `Proposal<P>` object's config is immutable. Even if governance
lowers `approval_threshold` in `dao.proposal_configs()` after a proposal is created,
the in-flight proposal retains its original snapshotted config and its own passing
condition is unchanged.

### `composable_allowed` Governance Attack Revisited

With the framework block removed, governance can set `composable_allowed = true` for
`UpdateProposalConfig`. Could a malicious actor then include a self-targeting
`UpdateProposalConfig` step in a composite to weaken governance?

The composite submission check in `assert_composite_floors()` applies the same
`SELF_UPDATE_APPROVAL_FLOOR_BPS` floor against `effective_threshold`. A composite
containing `UpdateProposalConfig` self-target must have been submitted with
`effective_threshold >= 80%` and must pass with `yes_weight >= 80%`. The floor
is fully enforced.

---

## Differences from `ADR_MONOTONIC_EXECUTION_FLOORS`

| Aspect | ADR_MONOTONIC_EXECUTION_FLOORS | This ADR |
|---|---|---|
| Floor values | Configurable data in `ProposalConfig` | Hardcoded constants (unchanged) |
| Enforcement site | `advance_step` + handler, data-driven | `propose()` + `submit_composite()`, constant-driven |
| `ProposalConfig` changes | New `execution_floor_bps: u16` field | None |
| Handler changes | Remove execution-time assert, read from config | Remove execution-time assert |
| `advance_step` signature | Add `&Proposal<CompositePayload>` parameter | No change |
| Security model | Raise-only data invariant (audited code path) | Hardcoded constant (no mutable state) |
| Composability unblocked? | Yes | Yes |

---

## Alternatives Considered

### Keep Execution-Time Enforcement (Status Quo)

`_step` handlers could be given a `votes: VoteData` parameter (a lightweight struct
capturing `yes_weight` / `total_snapshot_weight` from the composite) as a stand-in
for `&Proposal<P>`. This keeps enforcement at execution time but requires passing
vote data through the hot-potato chain.

**Why not chosen:** Submission-time enforcement is simpler, requires no new types,
and is strictly stronger (malicious proposals are rejected before they exist, not at
execution).

### `ADR_MONOTONIC_EXECUTION_FLOORS` Approach

Move floors to configurable data with raise-only governance semantics. Unblocks
composability at the cost of making the security model depend on a mutable-but-monotonic
invariant rather than immutable code constants.

**Why not chosen:** The configurable floor introduces a new class of security
invariant (raise-only validation code) that must be audited and tested. The
submission-time approach achieves the same composability outcome while keeping
floors as constants, which are provably unmodifiable.

---

## Implementation Checklist

- [ ] Add `assert_submission_floor<P>()` call in `propose()` (framework)
- [ ] Add `assert_composite_floors()` call in `submit_composite()` (framework)
- [ ] Implement `assert_composite_floors()` with inspection of step type keys from `CompositeFrame`
- [ ] Remove `ENABLE_APPROVAL_FLOOR_BPS` assert from `execute_enable_proposal_type`
- [ ] Remove `SELF_UPDATE_APPROVAL_FLOOR_BPS` assert from `execute_update_proposal_config`
- [ ] Remove framework invariant blocking `composable_allowed = true` for `UpdateProposalConfig` and `EnableProposalType` in `execute_update_proposal_config`
- [ ] Update `composable_allowed` factory defaults: `UpdateProposalConfig` and `EnableProposalType` remain `false` (governance can raise to `true`)
- [ ] Add unit test: submit `UpdateProposalConfig` self-target with `approval_threshold = 51%` → assert abort
- [ ] Add unit test: submit `UpdateProposalConfig` self-target with `approval_threshold = 80%` → assert success
- [ ] Add unit test: submit `EnableProposalType` with `approval_threshold = 65%` → assert abort
- [ ] Add unit test: composite with `EnableProposalType` step and `effective_threshold = 65%` → assert abort at submission
- [ ] Add unit test: composite with `EnableProposalType` step and `effective_threshold = 67%` → assert success
- [ ] Update `guide_composable_blocking_audit.md` enforcement tiers
- [ ] Update `03_proposal_system.md` §7.3 `advance_step` description (no floor check needed)
- [ ] Update `01_core_architecture.md` §5.10a/§5.10b to reference submission-time floor enforcement

---

## Open Questions

1. **`UpdateProposalConfig` self-target detection in composites** — `assert_composite_floors()`
   must read the `UpdateProposalConfig` payload's `target_type` field from the
   `CompositeFrame`. This requires `CompositeFrame` to expose `step_payload_at<P>()`.
   If frame payloads are only extractable (not readable), an alternative is to apply
   the `SELF_UPDATE_APPROVAL_FLOOR_BPS` conservatively to *all* `UpdateProposalConfig`
   steps in composites (not just self-targeting ones). This over-constrains but avoids
   needing payload read access.

2. **Should `EnableProposalType` composability be gated further?** — Even with floor
   enforcement at submission, the "enable and immediately exploit in same composite"
   risk remains: step 1 enables type T, step 2 is type T. Voters agreed to both steps,
   but type T's handler was not enabled when the composite was reviewed. **Proposal:**
   `add_step<P>()` asserts `P` is already in `dao.enabled_proposals`. `EnableProposalType`
   steps can enable types, but those types cannot also appear as steps in the same
   composite.

3. **`_step` variant for `UpdateProposalConfig` and `EnableProposalType`** — Do these
   types even need `_step` variants in practice? The main composability use case is
   "enable multiple types and set their configs" in a DAO bootstrapping composite. If
   both types can appear as steps with floor enforcement at submission, the ergonomic
   goal is met.

---

## References

- `ADR_COMPOSABLE_PROPOSALS.md` — Option E Frame + Pipeline design
- `ADR_MONOTONIC_EXECUTION_FLOORS.md` — alternative (configurable floors; superseded by this ADR)
- `notes/dao/security/guide_composable_blocking_audit.md` — Category 1 floor-gated type analysis
- `notes/dao/03_proposal_system.md` §7.3 — `advance_step` choke point
- `notes/dao/01_core_architecture.md` §5.10a, §5.10b — floor invariants
- `notes/dao/security/security_review.md` #13 — ProposalConfig downgrade attack
