# Ergodic DAO Protocol — Document Index

**A composable on-chain governance framework for player organizations in EVE Frontier, built on Sui Move.**

> *DAO as organizational primitive — not a product, but a substrate on which every form of player coordination can be encoded.*

---

## Document Map

| # | Document | What It Covers | Hackathon Scope |
|---|---|---|---|
| 01 | [Vision](01_vision.md) | Problem statement, design thesis, design pillars | ✅ Core |
| 02 | [Demo Flows](02_demo_flows.md) | **Three Testnet demos** — step-by-step scenarios with PTBs and mockups | ✅ Core — implementation target |
| 03 | [Core Spec](03_core_spec.md) | DAO object, treasury, cap vault, proposals, Board governance, invariants | ✅ Core |
| 04 | [SubDAO Hierarchy](04_subdao_hierarchy.md) | SubDAOControl, delegation, atomic reclaim, spinout | ✅ Core |
| 05 | [Charter](05_charter.md) | Charter object, Walrus integration, amendment process | ✅ Core |
| 06 | [Security](06_security.md) | Threat model, resolved threats, accepted risks | ✅ Core |
| 07 | [Roadmap](07_roadmap.md) | P0–P4 phases aligned to [armature](https://github.com/loash-industries/armature) issues | ✅ Core |
| 08 | [Stretch Features](stretch/00_index.md) | Federation, governance models, project funding, charter parametrization, open type set | ⏳ Post-hackathon |
| 09 | [Issue Breakdown](09_issue_breakdown.md) | ~27 issues across 5 phases, mapped to armature repo issues #2–#10 | ✅ Core |
| 10 | [Formal Verification](10_formal_verification.md) | sui-prover strategy, spec coverage tracker, CI integration | ✅ Core |

---

## Reading Paths

### For Implementers (Start Here)
1. **[02 Demo Flows](02_demo_flows.md)** — See exactly what we're building (15 min)
2. **[07 Roadmap](07_roadmap.md)** — Understand the P0–P4 phasing (5 min)
3. **[03 Core Spec](03_core_spec.md)** — Full object and proposal reference (deep read)
4. **[04 SubDAO Hierarchy](04_subdao_hierarchy.md)** — Composition mechanics (10 min)
5. **[05 Charter](05_charter.md)** — Walrus integration details (5 min)

### For Hackathon Evaluators
1. **[01 Vision](01_vision.md)** — Understand the problem and thesis (5 min)
2. **[02 Demo Flows](02_demo_flows.md)** — The protocol in action (15 min)
3. **[07 Roadmap](07_roadmap.md)** — What ships at hackathon, what comes next (5 min)
4. **[Stretch Features](stretch/00_index.md)** — The full vision beyond hackathon (skim)

### For Security Reviewers
1. **[03 Core Spec](03_core_spec.md)** — Invariants and type safety
2. **[06 Security](06_security.md)** — Threat model and mitigations
3. **[04 SubDAO Hierarchy](04_subdao_hierarchy.md)** — Hierarchy controls and reclaim
4. **[10 Formal Verification](10_formal_verification.md)** — Prover specs covering all 41 invariants
5. **[specs/](../specs/00_overview.md)** — 71 spec functions across 9 categories

---

## Glossary

| Term | Definition |
|---|---|
| **DAO** | A shared on-chain object representing a governed organization. Holds references to its treasury, capability vault, charter, and emergency freeze system. |
| **Charter** | A constitutional document stored on Walrus, referenced on-chain via blob ID and content hash. Defines a DAO's purpose, rules, and operating agreements in human-readable form. |
| **SubDAO** | A DAO controlled by another DAO via a `SubDAOControl` capability. Always uses Board governance. Analogous to a department within an organization. |
| **Proposal** | A typed on-chain object (`Proposal<P>`) that encodes a governance action. Must be voted on and pass quorum + approval thresholds before execution. |
| **ExecutionRequest** | A hot-potato object emitted when a proposal is executed. Must be consumed by the correct handler in the same PTB. Proves governance authorization. |
| **TreasuryVault** | A separate shared object holding multi-coin balances via dynamic fields. Each DAO has its own treasury. |
| **CapabilityVault** | A separate shared object holding arbitrary `key + store` capabilities (e.g., `UpgradeCap`, `SubDAOControl`, `TreasuryCap`). Accessed only through governance. |
| **SubDAOControl** | A capability stored in a *controller* DAO's vault, granting authority over a SubDAO's board and operations. |
| **Hot Potato** | A Sui Move object with no `drop`, `store`, or `copy` abilities. Must be consumed in the same PTB it was created. Used for `ExecutionRequest` and `CapLoan`. |
| **PTB** | Programmable Transaction Block — Sui's atomic transaction unit. All operations in a PTB succeed or all revert. |
| **Walrus** | Sui's decentralized blob storage layer. Used to store Charter content and other human-readable documents. |

### Stretch Feature Terms

| Term | Definition |
|---|---|
| **Federation** | *(Stretch)* A peer association of independent DAOs, formed by mutual consent. Each member holds a `FederationSeat` capability. No member controls another. See [stretch/01](stretch/01_federation.md). |
| **FederationSeat** | *(Stretch)* A capability stored in a *member* DAO's vault, proving membership in a federation. Non-transferable. |
| **Stock Ticker Registry** | *(Stretch)* An on-chain registry for unique 1–4 character token symbols, using commit-reveal to prevent front-running. See [stretch/04](stretch/04_project_funding.md). |
| **Charter Param** | *(Stretch)* An on-chain dynamic field on the Charter encoding a governance constraint (floor, ceiling, value) that proposals must respect. See [stretch/10](stretch/10_charter_parametrization.md). |
| **Open Type Set** | *(Stretch)* The ability for third-party packages to define custom proposal types that interact with DAO assets via hot-potato-gated public APIs. See [stretch/11](stretch/11_open_proposal_type_set.md). |
