= The DAO Primitive

#import "../lib/template.typ": defbox, aside

A DAO is a composable, self-governing primitive on the SUI blockchain.

#aside[
  *A note on status.* This paper describes both what Armature does today and where it is going. Features that are implemented in the current framework are described in the present tense. Features that are designed but not yet implemented are explicitly marked as _planned_. The core primitive --- the five objects, the proposal engine, board governance, the vaults, composite proposals, and the Sub-DAO hierarchy --- is implemented today. Federation and the addressing scheme are planned.
]

Traditional governance frameworks treat the organization as a single contract. Armature does the opposite: it breaks the DAO into independent shared objects that can be accessed at the same time, upgraded separately, and combined in any configuration.

== Architecture Overview

Every DAO is made of five shared objects. Each one exists independently on-chain.

#defbox[DAO][The governance root. It holds the governance configuration, tracks which proposal types are enabled, stores per-type parameters and cooldown timestamps, and keeps references to all associated objects. It is the identity of the organization.]

#defbox[TreasuryVault][Multi-coin asset storage under governance control. Anyone can deposit any coin type. All withdrawals require governance approval. Dynamic fields store individual coin balances, and a registry tracks which types have non-zero balances.]

#defbox[CapabilityVault][Storage for any SUI object with `key + store` abilities --- gate controller caps, upgrade caps, admin tokens. It supports immutable borrow, mutable borrow, temporary loan with guaranteed return, and permanent extraction. All under governance custody.]

#defbox[Charter][The organization's constitution. Today the Charter is a lightweight on-chain object holding the DAO's name and a metadata URI --- a link to the human-readable constitution, by convention an IPFS reference such as `ipfs://…`. Amendments update this pointer through a governance proposal, and the on-chain proposal log records every change. _Planned:_ the Charter will additionally carry an integrity hash, explicit versioning, and codified rules --- governance parameters, membership constraints, proposal thresholds --- that parametrize proposals directly, so the constitution is one the system reads and enforces, not just one humans interpret.]

#defbox[EmergencyFreeze][The circuit breaker. It allows selective, time-bounded freezing of individual proposal types. Freezing is triggered by a `FreezeAdminCap`, issued to the DAO at creation and transferable or placeable under governance custody. Unfreezing, transferring the admin cap, and changing freeze configuration all require governance proposals. Freezes auto-expire after a configurable maximum duration (7 days by default), and the unfreeze and transfer-admin proposal types are permanently exempt from freezing, so the emergency system can never lock out governance.]

Why five separate objects?

This is a direct consequence of SUI's object model. Each object can appear in a different transaction at the same time. A treasury deposit does not block a proposal vote. A charter amendment does not wait for a capability loan to finish.

This parallelism matters for organizations with active operations.

== Package Architecture

The framework is split into two layers. The core layer defines the DAO's shared objects, the proposal lifecycle, and the governance engine. It is designed to be stable. The proposal layer contains the built-in handlers --- the logic that executes each type of governance action. It is designed to be upgradable.

New proposal types can be added and existing handlers improved without touching the core.
