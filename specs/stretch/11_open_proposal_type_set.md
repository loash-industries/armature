# Stretch: Open Proposal Type Set

> Part of the [stretch features index](00_index.md). Not in hackathon scope.
>
> Tracks [Issue #5](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/5).

The DAO framework should support an **open proposal type set** — any Move struct with `store` ability can serve as a proposal payload, not just the 18 framework-defined types. Third-party packages define custom proposal types and handlers that interact with DAO treasury and vaults through `public` functions gated by `ExecutionRequest<P>` hot potatoes.

This makes the "expand / reduce set" arrow in the DAO Atom model (see [01 Vision](../01_vision.md) — The DAO Atom) a real extensibility mechanism rather than a toggle over a fixed menu.

---

## Problem

The current spec marks treasury and vault APIs as `public(friend)`:

```move
withdraw<T, P>(vault, amount, &ExecutionRequest<P>, ctx) -> Coin<T>  // public(friend)
borrow_cap<C, P>(vault, cap_id, &ExecutionRequest<P>) -> &C          // public(friend)
```

This means third-party packages cannot access DAO assets, making custom proposal types useless for anything beyond pure metadata operations.

## Proposed Change

Change treasury and vault operations from `public(friend)` to `public`, relying on `ExecutionRequest<P>` as the sole authorization:

```move
public fun withdraw<T, P>(vault: &mut TreasuryVault, amount: u64, req: &ExecutionRequest<P>, ctx: &mut TxContext): Coin<T>
public fun borrow_cap<C, P>(vault: &CapabilityVault, cap_id: ID, req: &ExecutionRequest<P>): &C
public fun loan_cap<C, P>(vault: &mut CapabilityVault, cap_id: ID, req: &ExecutionRequest<P>): (C, CapLoan)
```

### Why This Is Safe

`ExecutionRequest<P>` has **no abilities** (no `copy`, `drop`, `store`). The only way to obtain one is through `proposal::execute<P>`, which enforces voting, thresholds, delays, and freeze checks. The hot potato IS the authorization — `public(friend)` is redundant defense-in-depth that blocks extensibility.

## Third-Party Type Example

```move
// Third-party package
module bounty_ops::bounty {
    use dao_framework::treasury;
    use dao_framework::proposal::ExecutionRequest;

    struct PayBounty has store {
        recipient: address,
        amount: u64,
        description: String,
    }

    public fun execute_pay_bounty<T>(
        vault: &mut TreasuryVault,
        req: ExecutionRequest<PayBounty>,
        ctx: &mut TxContext,
    ) {
        let coin = treasury::withdraw<T, PayBounty>(vault, req.amount, &req, ctx);
        transfer::public_transfer(coin, req.recipient);
        proposal::consume_execution_request(req);
    }
}
```

### Lifecycle

1. Third-party publishes package with `PayBounty` struct + handler
2. DAO passes `EnableProposalType` for `PayBounty` (66% floor)
3. Member creates `Proposal<PayBounty>` (framework checks: type enabled, proposer eligible, snapshots config)
4. Board votes (framework checks: quorum, threshold)
5. After execution_delay, executor calls `proposal::execute<PayBounty>` -> `ExecutionRequest<PayBounty>`
6. Same PTB calls `bounty_ops::execute_pay_bounty` with the hot potato
7. Handler calls `treasury::withdraw` (public, gated by hot potato) and transfers funds
8. Handler consumes `ExecutionRequest` (hot potato destroyed)

Steps 3-5 are entirely framework-managed. The framework guarantees governance integrity for ANY type.

## Visibility Matrix

| Function | Visibility | Reason |
|---|---|---|
| `treasury::withdraw` | `public` | Gated by `ExecutionRequest` |
| `treasury::deposit` | `public` | Already permissionless |
| `capability_vault::borrow_cap` | `public` | Gated by `ExecutionRequest` |
| `capability_vault::loan_cap` | `public` | Gated by `ExecutionRequest` |
| `capability_vault::extract_cap` | `public` | Gated by `ExecutionRequest` |
| `capability_vault::privileged_extract` | `public(friend)` | Gated by `SubDAOControl`, framework-internal |
| `capability_vault::store_cap_init` | `public(friend)` | DAO initialization only |
| `dao::enable_proposal_type` | `public(friend)` | State mutation, framework-internal |

## New API: `consume_execution_request`

```move
/// Consume the ExecutionRequest hot potato. The hot potato itself is the proof of authorization.
public fun consume_execution_request<P>(req: ExecutionRequest<P>) {
    let ExecutionRequest { dao_id: _, proposal_id: _ } = req;
}
```

## Trust Model

When a DAO enables a third-party type, the board makes a trust decision about that package.

**Framework guarantees (for all types):** voting, thresholds, delays, freeze, charter-enforced params (per [Issue #4](10_charter_parametrization.md))

**Framework does NOT guarantee:** handler correctness, handler honesty, type-specific charter enforcement

`EnableProposalType` with a 66% floor is the trust gate. The DAO's governance decides which packages to trust.

## Scope

- **Phase**: P0/P1 decision (affects module signatures before coding starts)
- **Breaking change**: `public(friend)` -> `public` on treasury/vault APIs
- **New API**: `proposal::consume_execution_request<P>`
- **Modules affected**: `treasury.move`, `capability_vault.move`, `proposal.move`

---

**See also:** [Charter Parametrization](10_charter_parametrization.md) — framework-enforced charter params apply universally. [Proposal Composition](09_proposal_composition.md) — third-party types compose naturally with the pipeline. [Advanced Proposals](05_advanced_proposals.md) for framework-defined advanced types.
