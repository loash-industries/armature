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

The framework is split into two layers. The core layer defines the DAO's shared objects, the proposal lifecycle, and the governance engine. It is designed to be stable. The proposal layer contains the built-in handlers --- the logic that executes each type of governance action. It is designed to be upgradable.

New proposal types can be added and existing handlers improved without touching the core.
