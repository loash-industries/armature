# Armature OU Protocol — Document Index

**A composable on-chain governance framework for player organizations in EVE Frontier, built on Sui Move.**

> *OU as organizational primitive — not a product, but a substrate on which every form of player coordination can be encoded.*

These specs began as the hackathon design (March 2026) and have been updated to describe the framework as implemented. Where a spec describes something not built, it says so. The stretch documents under `stretch/` are kept as originally written; [08](08_stretch_features.md) records which of them have since been implemented.

---

## Document Map

| # | Document | What It Covers | Status |
|---|---|---|---|
| 01 | [Vision](01_vision.md) | Problem statement, design thesis, design pillars | Current |
| 02 | [Demo Flows](02_demo_flows.md) | **Three Testnet demos** — step-by-step scenarios with PTBs and mockups | Current API; gate/SSU contracts mocked |
| 03 | [Core Spec](03_core_spec.md) | Objects, packages, Board governance, proposal lifecycle and execution paths, permissions, type registry, invariants, events | Current |
| 04 | [SubOU Hierarchy](04_subdao_hierarchy.md) | SubOUControl, controller operations, delegation, reclaim, spinout | Current |
| 05 | [Charter](05_charter.md) | Charter object and `UpdateMetadata`; planned Walrus-backed amendments | Part A current, Part B planned |
| 06 | [Data Layer](06_data_layer.md) | How the UI reads state: indexer, direct RPC, event polling | Current |
| 06 | [Security](06_security.md) | Threat model, resolved threats, accepted risks | Current |
| 07 | [Roadmap](07_roadmap.md) | Phases, what shipped, what's next | Current |
| 08 | [Stretch Features](08_stretch_features.md) | Federation, governance models, project funding, charter parametrization, open type set, composition | Original designs; implementation status in 08 |
| 09 | [Issue Breakdown](09_issue_breakdown.md) | The original hackathon issue breakdown, annotated with outcomes | Historical |
| 10 | [Formal Verification](10_formal_verification.md) | sui-prover plan and invariant list | Plan (not implemented) |
| — | [Tests](tests/00_conventions.md) | Test plans per module and their coverage in the real suites | Current |

Companion references outside `specs/`:

- [`docs/package-boundaries.md`](../docs/package-boundaries.md) — which package a proposal type lives in, and why the package boundary is the trust boundary
- [`docs/proposal-types.md`](../docs/proposal-types.md) — every proposal type with its permission bits, borrow scope and approval floor
- [`packages/armature_framework/internal_workings.md`](../packages/armature_framework/internal_workings.md) — mint paths, the per-function gate table, the permission model
- [`docs/tribe-creation.md`](../docs/tribe-creation.md) — the Tribe → Officers → Members hierarchy

---

## Reading Paths

### For Implementers (Start Here)
1. **[03 Core Spec](03_core_spec.md)** — Full object and proposal reference (deep read)
2. **[`docs/package-boundaries.md`](../docs/package-boundaries.md)** — Where a new proposal type goes (5 min)
3. **[`docs/proposal-types.md`](../docs/proposal-types.md)** — Bits, scopes and floors per type, and integrator guidance (10 min)
4. **[02 Demo Flows](02_demo_flows.md)** — The protocol in action (15 min)
5. **[04 SubOU Hierarchy](04_subdao_hierarchy.md)** — Composition mechanics (10 min)

### For Evaluators
1. **[01 Vision](01_vision.md)** — Understand the problem and thesis (5 min)
2. **[02 Demo Flows](02_demo_flows.md)** — The protocol in action (15 min)
3. **[07 Roadmap](07_roadmap.md)** — What has shipped, what comes next (5 min)
4. **[Stretch Features](stretch/00_index.md)** — The full vision beyond what is built (skim)

### For Security Reviewers
1. **[03 Core Spec](03_core_spec.md)** — Execution paths, permissions, invariants
2. **[06 Security](06_security.md)** — Threat model and mitigations
3. **[`internal_workings.md`](../packages/armature_framework/internal_workings.md)** — Every gated function and the bit it requires
4. **[`docs/package-boundaries.md`](../docs/package-boundaries.md)** — The trust boundary between the framework and extension packages
5. **[04 SubOU Hierarchy](04_subdao_hierarchy.md)** — Hierarchy controls and reclaim
6. **[10 Formal Verification](10_formal_verification.md)** — Planned prover coverage; today's enforcement is unit tests and the CI gate check

---

## Glossary

| Term | Definition |
|---|---|
| **OU** | A shared on-chain object representing a governed organization. Holds its board roster, lifecycle flags, and the IDs of its treasury, capability vault, charter, and emergency freeze. Its enabled proposal types live in dynamic fields on it. |
| **Charter** | The OU's name and a metadata URI (typically an IPFS CID) pointing at its human-readable constitution. Changed by the `UpdateMetadata` proposal type. A Walrus-backed charter with amendment history is planned. |
| **SubOU** | An OU controlled by another OU via a `SubOUControl` capability. Always uses Board governance. Analogous to a department within an organization. |
| **Proposal** | A typed governance action with payload `P`. On the vote path it is a shared `Proposal<P>` object that must pass quorum and approval thresholds; execution or expiry deletes it. Single-PTB paths execute without creating an object, and their events are the record. |
| **Proposal type / type slot** | A payload type the OU has enabled. Its slot, keyed by the Move type, holds the type's display key, `ProposalConfig` (thresholds, timing, permission bits, borrow scope) and last-executed time. |
| **Display key** | A human-readable label for an enabled type (e.g. `CharterUpdate` for `UpdateMetadata`). Unique per OU; carries no authority. |
| **ExecutionRequest** | The hot-potato authorization minted when a proposal executes. It names its OU and carries its type's permission bits and borrow scope; every framework mutator checks it. |
| **ExecutionTicket** | What a handler receives: the payload plus its `ExecutionRequest`. Only the module that defines the payload type can spend or close it (`std::internal::Permit<P>`). |
| **Permission bits** | The OU-wide mutations a proposal type may perform (`BOARD_ADD`, `TREASURY_WITHDRAW`, `VAULT_BORROW`, …). Deny-by-default; high-impact bits require an 80% approval threshold. |
| **Borrow scope** | The capability types a `VAULT_BORROW` type may borrow or loan from the vault. |
| **Bypass type** | A proposal type an OU has opted into executing without a vote (`EnableBypassType`, 80%). Its own module authenticates the caller before minting a ticket with the OU's `ExternalExecutionCap`. |
| **Composite proposal** | Up to 16 typed steps approved by one vote and executed in order in one PTB. |
| **TreasuryVault** | A separate shared object holding coin balances (dynamic fields keyed by coin type) and multicoin balances. Each OU has its own treasury. |
| **CapabilityVault** | A separate shared object holding arbitrary `key + store` capabilities (e.g., `UpgradeCap`, `SubOUControl`, `TreasuryCap`). Accessed only through governance requests carrying the vault bits. |
| **SubOUControl** | A capability stored in a *controller* OU's vault, granting authority over a SubOU's board and operations. |
| **FreezeAdminCap** | The emergency circuit breaker's key: its holder can freeze proposal types for a bounded time. Held by an address (or a parent's vault for some SubOUs); governance can transfer it. |
| **Extension package** | A package outside the framework that defines proposal types and their handlers — first-party (`armature_proposals`, `armature_world_bridge`) or third-party. The framework treats them all alike. |
| **Hot Potato** | A Sui Move object with no `drop`, `store`, or `copy` abilities. Must be consumed in the same PTB it was created. Used for `ExecutionRequest`, `ExecutionTicket`, `CapLoan` and the composite `Pipeline`. |
| **PTB** | Programmable Transaction Block — Sui's atomic transaction unit. All operations in a PTB succeed or all revert. |
| **Walrus** | Sui's decentralized blob storage layer. Planned home of Walrus-backed charters; Seal-encrypted board entries reference off-chain ciphertext blobs. |

### Stretch Feature Terms

| Term | Definition |
|---|---|
| **Federation** | *(Stretch)* A peer association of independent OUs, formed by mutual consent. Each member holds a `FederationSeat` capability. No member controls another. See [stretch/01](stretch/01_federation.md). |
| **FederationSeat** | *(Stretch)* A capability stored in a *member* OU's vault, proving membership in a federation. Non-transferable. |
| **Stock Ticker Registry** | *(Stretch)* An on-chain registry for unique 1–4 character token symbols, using commit-reveal to prevent front-running. See [stretch/04](stretch/04_project_funding.md). |
| **Charter Param** | *(Stretch)* An on-chain dynamic field on the Charter encoding a governance constraint (floor, ceiling, value) that proposals must respect. See [stretch/10](stretch/10_charter_parametrization.md). |
| **Open Type Set** | Third-party packages defining their own proposal types, enabled by vote and bounded by permission bits. Implemented, by a stronger mechanism than the original proposal in [stretch/11](stretch/11_open_proposal_type_set.md); see [`docs/package-boundaries.md`](../docs/package-boundaries.md). |
