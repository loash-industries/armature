= The DAO Primitive

#import "../lib/template.typ": defbox, aside

A DAO is a composable, self-governing primitive on the SUI blockchain.

Traditional governance frameworks treat the organization as a single contract. Armature does the opposite: it breaks the DAO into independent shared objects that can be accessed at the same time, upgraded separately, and combined in any configuration.

== Architecture Overview

Every DAO is made of five shared objects. Each one exists independently on-chain.

#defbox[DAO][The governance root. It holds the governance configuration, tracks which proposal types are enabled, stores per-type parameters and cooldown timestamps, and keeps references to all associated objects. It is the identity of the organization.]

#defbox[TreasuryVault][Multi-coin asset storage under governance control. Anyone can deposit any coin type. All withdrawals require governance approval. Dynamic fields store individual coin balances, and a registry tracks which types have non-zero balances.]

#defbox[CapabilityVault][Storage for any SUI object with `key + store` abilities --- gate controller caps, upgrade caps, admin tokens. It supports immutable borrow, mutable borrow, temporary loan with guaranteed return, and permanent extraction. All under governance custody.]

#defbox[Charter][More than a document. Today, the Charter references a human-readable document stored on Walrus (decentralized blob storage), with an on-chain content hash for integrity and a full amendment history. In the future, the Charter will carry codified rules directly on-chain --- governance parameters, membership constraints, proposal thresholds --- and these rules will be used to parametrize proposals. The Charter becomes the constitution that the system reads and enforces, not just one that humans interpret.]

#defbox[EmergencyFreeze][The circuit breaker. It allows selective, time-bounded freezing of individual proposal types. The `FreezeAdminCap` is itself stored in the CapabilityVault, so it can only be accessed through governance. Freezes auto-expire after a configurable maximum duration.]

Why five separate objects?

This is a direct consequence of SUI's object model. Each object can appear in a different transaction at the same time. A treasury deposit does not block a proposal vote. A charter amendment does not wait for a capability loan to finish.

This parallelism matters for organizations with active operations.

== Package Architecture

The framework is split into two packages with different upgrade speeds:

#figure(
  table(
    columns: (auto, 1fr, auto),
    align: (left, left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*Package*][*Purpose*][*Stability*],
    [`armature_framework`], [Core objects: DAO, Treasury, CapVault, Charter, Proposal engine, governance models], [Stable],
    [`armature_proposals`], [Built-in proposal handlers (18 types across admin, treasury, board, Sub-DAO, charter)], [Upgradable],
  ),
  caption: [Package separation enables independent upgrade cycles.],
)

New proposal types can be added and existing handlers improved without touching the core governance engine.

The `armature_framework` defines the `ExecutionRequest<P>` hot potato and the proposal lifecycle. It knows nothing about specific proposal types.

== The Hot Potato Pattern

At the heart of Armature's security model is the _hot potato_ pattern.

A hot potato is a SUI-native technique. An object with no `drop`, `copy`, or `store` abilities must be consumed within the same Programmable Transaction Block (PTB) in which it was created.

#aside[
  A hot potato cannot be stored, cannot be discarded, and cannot be duplicated. It exists only for the duration of a single atomic transaction. The type system enforces this at compile time.
]

When a proposal is executed, the framework produces an `ExecutionRequest<P>` --- a hot potato typed to the proposal's payload. This is the _only_ authorization token for governance-gated operations.

Treasury withdrawals, capability loans, charter amendments --- all require a valid `ExecutionRequest<P>`.

The `ExecutionRequest<P>` carries only the DAO and proposal identifiers, and has no abilities --- the type system enforces it cannot be stored, copied, or dropped.

The handler for proposal type `P` must consume the hot potato. If it fails, the entire PTB reverts and the proposal stays in `Passed` status, ready to be retried.

If it succeeds, the `ExecutionRequest` is destroyed, the proposal moves to `Executed`, and all state changes are committed as one atomic operation.

There is no capability token to steal. No role to impersonate. No permission check to bypass.

The type system itself is the access control layer.
