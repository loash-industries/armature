_Some Claude-provided feedback after some back and forth_


# Review: `ExecutionTicket<P>` Proposal

## Overview

This document reviews the `ExecutionTicket<P>` proposal, which consolidates the three
sanctioned execution paths (vote, external cap, composite step) behind a single hot-potato
type so that one handler per proposal type is simultaneously standalone-, composite-, and
external-executable, eliminating the `_step` twin pattern.

---

## Factual Accuracy

All core claims check out against the source.

**Scope of the problem is accurate.** Exactly 7 `_step` twins exist:
`execute_add_member_step`, `execute_remove_member_step`, `execute_set_board_step`,
`execute_enable_proposal_type_step<NewType>`, `execute_update_metadata_step`,
`execute_send_coin_step<T>`, `execute_send_coin_to_dao_step<T>`. Every one is `public`.

**The three execution paths are described correctly.**
- Vote path: `board_voting::authorize_execution` → `proposal::execute`, payload borrowed
  from the persistent `Proposal<P>`, discharged via `finalize(req, &proposal)`.
- External path: `external_execution::external_executed_create`, authorized by
  `ExternalExecutionCap<P>`, takes `payload: P` by value, routes through `privileged_create`
  which shares an audit `Proposal<P>` in Executed status.
- Composite path: `composite::advance_step` calls `new_execution_request` directly after
  per-step freeze and cooldown checks; payload is `df::remove`'d by value from the frame;
  discharged via `consume_execution_request(req)`.

**The `_step` twin code example matches the source exactly.** Both handlers delegate to a
shared `_impl` function; the only differences are `&P` vs `P` and `finalize` vs
`consume_execution_request`.

**Constraints C1–C4 all verify.**
- C1 (handlers only read payload): every handler passes `proposal.payload()` (returns `&P`)
  or `&payload` to its `_impl`; none take `&mut Proposal`.
- C2 (authorization paths genuinely differ): vote checks board membership + delay + cooldown
  inside `proposal::execute`; external checks `ExternalExecutionCap` scoping; composite
  snapshots `last_executed_at` before the pipeline begins and checks per-step against that.
- C3 (external path already by-value): `external_executed_create` takes `payload: P`.
- C4 (`ExecutionRequest` is load-bearing): `treasury_vault::withdraw`, `capability_vault`
  store/extract, and `dao::init_type_state` / `dao::borrow_type_state_mut` all take
  `&ExecutionRequest<P>` and check `req_dao_id()`. The request must remain a distinct,
  borrowable value inside the ticket.

---

## Issues and Risks

### 1. `borrow_for_exec` / `discharge` API relies on implicit lifetime discipline

The proposed handler pattern:

```move
let (payload, req) = ticket.borrow_for_exec();
do_work(dao, &payload, &req);
ticket.discharge();
```

works in Move 2024 because borrows end at last use. For a simple handler this is fine. For a
complex handler — one with branching logic, multiple uses of `req` across conditionals, or
intermediate calls that interleave `&payload` and `&req` — authors will encounter borrow
errors whose cause is non-obvious. Any use of `payload` or `req` after `discharge` is
intended to be called will fail to compile without a clear diagnostic.

**Recommendation:** a destructuring API makes the lifetime contract explicit:

```move
let (payload, req, closeout) = ticket.unpack();   // consumes ticket, yields owned fields
do_work(dao, &payload, &req);
armature::close(req, payload, closeout);          // package-private; enforces closeout logic
```

`unpack` is `public`, `close` is `public(package)`. The handler author can never defer the
close-out accidentally, and the borrow checker has nothing subtle to enforce.

### 2. `composable_allowed` remains a necessary safety gate, not a redundant one

The proposal's open question 4 leans toward treating `composable_allowed` as redundant once
unification removes the need for `_step` twins. It is not redundant.

`compute_effective_config` raises the composite's approval threshold to the max across all
steps, which prevents a weak composite from laundering a high-threshold action. But
`composable_allowed = false` provides a second, independent line of defence: it prevents
governance-sensitive types (e.g. `SpinOutSubDAO`, `PauseSubDAOExecution`) from being
bundled into composites at all, guarding against a misconfigured `UpdateProposalConfig`
accidentally opening them. The two mechanisms protect against different failure modes.
`composable_allowed` should be retained.

### 3. `finalize`'s status assertion is already vacuous

`finalize` asserts `proposal.status.is_executed()` as defence-in-depth. This check can
never fail if the request was legitimately minted, because `proposal::execute` sets status
to `Executed` before returning the request. Moving equivalent logic into `discharge()` for
the `Closeout::Standalone` variant carries no security regression. The `None` payload in
`Proposal<P>` (set at ticket mint time) is strictly better replay protection than the status
check, because it is unforgeable and eliminates the payload from the persistent object.

---

## Agreed Open Questions

### OQ1 — External-path audit proposals will carry `None` payload

Today `external_executed_create` calls `privileged_create` with the live `payload: P`,
which embeds it in the shared `Proposal<P>` that indexers read. Under the new design,
`ticket_from_cap` moves the payload into the ticket; the audit proposal is created with
`None` from the start. This silently changes indexer behaviour for the external path — not
only for future vote-path proposals.

**Recommendation:** emit a dedicated event containing the payload at `ticket_from_cap` mint
time. Indexers subscribe to this event for external-path payload data rather than reading
the `Proposal` object field.

### OQ2 — `composable_allowed` gate should be retained (see Risk 2 above)

If composition becomes automatic for all types, `composable_allowed = false` becomes the
sole per-type opt-in against composite inclusion. That gate is still wanted: it is the
governance-controlled safety valve for types whose combinatorial or repeated use in a
pipeline is undesirable regardless of threshold arithmetic.

---

## API Surface Reduction

The unified design creates a meaningful opportunity to narrow the public API.

### Functions that can be removed entirely

| Symbol | Current visibility | Reason removable |
|---|---|---|
| `proposal::consume_execution_request` | `public` | Exists solely for `_step` handlers. `ticket.discharge()` subsumes it. |
| 7 × `execute_*_step` handlers | `public` | Replaced by the unified handler for each type. |

### Functions that can be narrowed to `public(package)`

| Symbol | Current visibility | Reason narrowable |
|---|---|---|
| `proposal::finalize` | `public` | Only called from within `armature` via `discharge()` once `_step` twins are gone. |
| `proposal::req_dao_id` | `public` | External handlers use `ticket.dao_id()` instead; only `armature`-internal vault and DAO operations need the raw accessor. |
| `proposal::req_proposal_id` | `public` | Same rationale as `req_dao_id`. |
| `Closeout` enum | `public` | Opaque to handler authors; set at mint time by framework constructors; handlers only call `discharge()`. |

### Structural tightening without a visibility change

`composite::advance_step` currently returns a raw `ExecutionRequest<P>` to PTB callers.
Any PTB author holding that value could pass it to the wrong handler or call
`consume_execution_request` directly, discharging without executing. Returning
`ExecutionTicket<P>` instead means the request is unreachable by external code except as
`&ExecutionRequest<P>` via `borrow_for_exec` (or `unpack`). The only way to resolve the
ticket is to call a type-matched handler that calls `discharge`.

### The most security-relevant reduction

Removing `consume_execution_request` from the public API is the sharpest win. It is
currently a "light" discharge path — any package holding an `ExecutionRequest<P>` can call
it, skip the proposal-status check, and close out the request without executing anything. A
handler author can accidentally use it on a standalone request. Under the new design the
close-out variant is encoded in the ticket at mint time by the framework and is not a choice
available to the handler author. `ticket.discharge()` is the only close-out surface, and it
unconditionally runs the correct logic for the path that minted the ticket.

---

## Summary

The proposal's diagnosis and constraint analysis are correct. The `ExecutionTicket<P>`
direction is right. The actionable follow-ups are:

1. Prefer the destructuring / `unpack` API over `borrow_for_exec` / `discharge` to avoid
   implicit lifetime discipline in complex handlers.
2. Retain `composable_allowed` as an explicit opt-in gate independent of the twin removal.
3. Emit a payload event at `ticket_from_cap` mint time to preserve the external-path audit
   trail for indexers.
4. Carry the API surface reductions (remove `consume_execution_request`, narrow `finalize` /
   `req_dao_id` / `req_proposal_id` / `Closeout`) as part of the same changeset.
