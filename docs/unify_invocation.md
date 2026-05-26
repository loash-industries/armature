### Summary

Composition is currently opt-in **per proposal type** at the source level: a type can only appear as a step in a composite if a maintainer hand-writes a `_step` sister handler for it. Today **7 of ~25** proposal types have one. This makes composability a privilege the framework grants type-by-type rather than an ambient property of *being* a proposal type — friction that grows linearly with the proposal set and works against the goal of giving DAOs an open, expressive governance language.

This issue proposes consolidating the three execution paths behind a single `ExecutionTicket<P>` hot potato so that **writing one handler per type makes it standalone-, composite-, and external-executable simultaneously**, with no `_step` twin.

This is **not** a criticism of #137, which is correct and should merge as-is. This is a follow-up framework refactor.

### Background: how execution works today

There are three sanctioned ways to mint an `ExecutionRequest<P>` (the constructor is `public(package)`):

1. **Vote** — `board_voting::authorize_execution` -> `proposal::execute`. Payload stays *borrowed* inside the persistent `Proposal<P>`; handler reads `proposal.payload()`; request discharged by `finalize(req, &proposal)` (asserts status `Executed`).
2. **External / bypass** — `external_execution::external_executed_create`, authorized by `ExternalExecutionCap<P>`. Already takes `payload: P` **by value** and routes through `privileged_create` (builds an audit `Proposal<P>` in `Executed` status).
3. **Composite step** — `composite::advance_step` calls `new_execution_request` directly after per-step freeze + cooldown checks; payload is `df::remove`'d from the frame and handed to the handler **by value**; request discharged by `consume_execution_request(req)`.

The `_step` twin exists purely to reconcile two ownership facts between paths 1 and 3:
- **payload**: borrowed (`&P` from the proposal) vs. owned (`P` from the frame), and
- **discharge**: `finalize(req, &proposal)` vs. `consume_execution_request(req)`.

```move
// today — two functions, identical effect, differing only in ownership/discharge
public fun execute_add_member(dao, proposal: &Proposal<AddMember>, request) {
    add_member_impl(dao, proposal.payload(), &request);   // borrow
    proposal::finalize(request, proposal);                // strict close-out
}
public fun execute_add_member_step(dao, payload: AddMember, request) {
    add_member_impl(dao, &payload, &request);             // owned
    proposal::consume_execution_request(request);         // light close-out
}
```

### Pain points

- **Linear maintenance tax:** every type a DAO might want to bundle needs a `_step` twin authored, reviewed, and kept in sync with its primary handler. (Plus `composable_allowed` opt-in and SDK/PTB-builder support — but those are intrinsic; the twin is not.)
- **Composition is gated by us, not expressed by DAOs:** a DAO cannot compose a perfectly valid proposal type simply because no one wrote its twin. This contradicts the design goal that proposal-set expansion should *automatically* grant composition.
- **Twins aren't always trivial:** some carry type params and per-type subtleties (`execute_enable_proposal_type_step<NewType>`), so "mechanical boilerplate" undersells the risk surface.

### Proposal: `ExecutionTicket<P>`

Wrap the existing request (which must survive — see Constraint C4) together with the owned payload and a close-out tag:

```move
public struct ExecutionTicket<P> {           // hot potato — no abilities
    request: ExecutionRequest<P>,            // UNCHANGED; still the vault-auth token
    payload: P,                              // owned, moved in at mint time
    closeout: Closeout,
}
public enum Closeout has drop { Standalone { proposal_id: ID }, Composite, External }

// Three mints (authorization differs intrinsically — see C2), one ticket type:
public fun ticket_from_vote<P>(dao, prop: &mut Proposal<P>, freeze, clock, ctx): ExecutionTicket<P>
public fun ticket_from_cap<P>(cap, dao, freeze, type_key, payload, clock, ctx): ExecutionTicket<P>
public fun ticket_from_step<P>(...): ExecutionTicket<P>   // called by composite::advance_step

// ONE handler per type — borrows req for vault auth, consumes ticket at the end:
public fun execute_add_member(dao: &mut DAO, ticket: ExecutionTicket<AddMember>) {
    let (payload, req) = ticket.borrow_for_exec();   // &req available for vault calls
    add_member_impl(dao, &payload, &req);
    ticket.discharge();                              // finalize-or-consume by closeout tag
}
```

A new proposal type writes **one** `execute_*` and is immediately usable in all three paths. No twin.

### Key design decision: where does the executed payload live?

The vote path currently keeps the payload borrowed inside the persistent `Proposal<P>`. A ticket *owns* `P`, so the standalone mint must move the payload **out** of the proposal. Recommended approach: store the proposal payload as **`Option<P>`**, `take()` it at ticket mint, leaving `None`.

- Preserves the `Proposal` object as an audit record (events already capture effects).
- A `None` payload is an unforgeable "already executed / consumed" marker — strictly *better* replay protection than today.
- Imposes **no** `copy` bound (ruling out the naive "keep a copy" approach, which `SendCoin` et al. can't satisfy).
- `privileged_create` already demonstrates the "audit proposal that owns its payload, status Executed" pattern, so this generalizes an existing precedent.

### Constraints verified against the code

- **C1 — handlers only read the payload.** No handler takes `&mut Proposal` or uses the proposal post-extraction, so moving the payload out is behaviorally safe.
- **C2 — authorization differs per path and cannot be unified.** Vote (delay + cooldown + board-member), external (capability), composite (per-step freeze + cooldown vs. snapshot) are genuinely different. Unification is at the **handler** boundary, not the mint boundary — there will still be three constructors. This proposal does **not** claim "one path to rule them all."
- **C3 — external path already fits.** `external_executed_create` already takes `payload: P` by value.
- **C4 — `ExecutionRequest` is a load-bearing authz token, not just a lifecycle marker.** `treasury_vault::withdraw`, `capability_vault` store/send/receive, and `spend_guard` take `&ExecutionRequest<P>` and check `req_dao_id()`. **Therefore the request must remain a distinct, borrowable value** — the ticket *contains* and exposes `&request`; it does not replace it.

### Migration

Can land **additively**, no flag-day:
1. Add `ExecutionTicket<P>`, the `Option<P>` payload slot, and the three `ticket_from_*` constructors alongside the existing `ExecutionRequest` API.
2. Add unified `execute_*` handlers; keep the old `execute_*` / `execute_*_step` pair as thin shims that build a ticket internally.
3. Migrate `composite::advance_step` to return `ExecutionTicket<P>`.
4. Deprecate and remove the `_step` twins type-by-type.

Scope: ~8 mint/handler sites in `armature_proposals`, plus `composite.move`, `external_execution.move`, and `proposal.move` in the framework. `armature_world_bridge` (Autojoin) uses the external path and gets the benefit for free.

### Open questions for maintainers

1. **`Option<P>` slot vs. move-out-and-drop:** keep the executed `Proposal` as a `None`-payload audit record (recommended), or drop the proposal entirely on execute? Affects indexers that read historical payloads.
2. **`finalize`'s status assertion:** the strict `status == Executed` check moves into `discharge()` for the standalone closeout; confirm no external tooling depends on calling `finalize` directly.
3. **Nesting & dataflow:** this unifies *execution* but deliberately keeps the "ordered independent actions" model (no inter-step dataflow, no nested composites). If DAO-expressible dataflow is a future goal, it's a separate, larger design — flag now so we don't design ourselves into a corner.
4. **Should `composable_allowed` survive at all?** If composition becomes automatic, the deny-by-default gate (from #137) becomes the *only* remaining per-type opt-in. Is that gate still wanted as a safety valve, or does unification make it redundant for non-floor-gated types?

### Acceptance criteria

- One `execute_*` handler per proposal type; no `_step` twins.
- A newly added proposal type is composite-executable with zero composition-specific code (only `composable_allowed`, if that gate is retained).
- All three execution paths produce `ExecutionTicket<P>`; `ExecutionRequest<P>` remains the vault-auth token, borrowable from the ticket.
- Existing test suite passes; new tests cover the same type used standalone, in a composite, and via external cap through the *same* handler.
