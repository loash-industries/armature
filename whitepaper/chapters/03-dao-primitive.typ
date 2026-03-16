= The DAO Primitive

#import "../lib/template.typ": defbox, aside

Armature's core contribution is the DAO as a composable, self-governing primitive on the SUI blockchain. Unlike traditional DAO frameworks that treat governance as a monolithic contract, Armature decomposes the DAO into independent shared objects that can be accessed concurrently, upgraded independently, and composed in arbitrary configurations.

== Architecture Overview

Every DAO instance comprises five shared objects, each serving a distinct function and existing independently on-chain:

#defbox[DAO][The governance root. Holds the governance configuration, tracks enabled proposal types with per-type parameters, records cooldown timestamps, and maintains references to all associated objects. It is the identity of the organization.]

#defbox[TreasuryVault][Multi-coin asset storage under governance control. Accepts permissionless deposits of any coin type and enforces governance authorization on all withdrawals. Dynamic fields store individual coin balances, with a registry tracking which types have non-zero balances.]

#defbox[CapabilityVault][Arbitrary capability storage. Holds any SUI object with `key + store` abilities --- gate controller caps, upgrade caps, admin tokens --- under governance custody. Supports immutable borrow, mutable borrow, temporary loan with guaranteed return, and permanent extraction.]

#defbox[Charter][The constitutional document. References a human-readable document stored on Walrus (decentralized blob storage), with an on-chain content hash for integrity verification, a monotonically increasing version number, and a complete amendment history.]

#defbox[EmergencyFreeze][Circuit breaker. Allows selective, time-bounded freezing of individual proposal types. The `FreezeAdminCap` is itself stored in the CapabilityVault, accessible only through governance, and freezes auto-expire after a configurable maximum duration.]

The separation into independent shared objects is a deliberate architectural choice driven by SUI's object model. Because each object can be included in different transactions concurrently, a treasury deposit does not block a proposal vote, and a charter amendment does not serialize against a capability loan. This parallelism is essential for organizations with active operations.

== Package Architecture

The framework is organized into separate packages with distinct upgrade cadences:

#figure(
  table(
    columns: (auto, 1fr, auto),
    align: (left, left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*Package*][*Purpose*][*Stability*],
    [`armature_framework`], [Core objects: DAO, Treasury, CapVault, Charter, Proposal engine, governance models], [Stable],
    [`armature_proposals`], [Builtin proposal handlers (18 types across admin, treasury, board, SubDAO, charter)], [Upgradable],
  ),
  caption: [Package separation enables independent upgrade cycles.],
)

This separation means that new proposal types can be added, and existing handlers can be improved, without touching the core governance engine. The `armature_framework` defines the `ExecutionRequest<P>` hot potato and the proposal lifecycle but remains entirely agnostic to concrete proposal types.

== The Hot Potato Pattern

At the heart of Armature's security model is the _hot potato_ pattern --- a SUI-native technique where an object with no `drop`, `copy`, or `store` abilities must be consumed within the same Programmable Transaction Block (PTB) in which it was created.

#aside[
  A hot potato cannot be stored, cannot be discarded, and cannot be duplicated. It exists only for the duration of a single atomic transaction. The type system enforces this at compile time --- no runtime checks required.
]

When a proposal is executed, the framework produces an `ExecutionRequest<P>` --- a hot potato parameterized by the proposal's payload type. This request is the _sole authorization token_ for performing governance-gated operations. Treasury withdrawals, capability loans, charter amendments --- all require a reference to a valid `ExecutionRequest<P>`.

```rust
struct ExecutionRequest<phantom P> {
    dao_id: ID,
    proposal_id: ID,
}
// No abilities: not drop, not copy, not store
```

The handler function for proposal type `P` must consume this hot potato. If the handler aborts, the entire PTB reverts --- the proposal remains in `Passed` status and can be retried. If the handler succeeds, the `ExecutionRequest` is destroyed, the proposal transitions to `Executed`, and the state changes are committed atomically.

This design eliminates an entire class of authorization vulnerabilities. There is no capability token that can be stolen, no role that can be impersonated, no permission check that can be bypassed. The type system itself is the access control layer.
