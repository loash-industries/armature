# Stretch: User Stories

> Part of the [stretch features index](00_index.md). Narrative scenarios demonstrating stretch features in action.

---

## Story: The Alliance

Three sovereign tribes form a federation. Each passes `FormFederation`/`JoinFederation` through their own governance. The federation has its own treasury (funded by member contributions), its own charter, and its own proposals. Critical decisions use `CastFederationVote` — each tribe's own governance must approve. Any member can leave at any time via `LeaveFederation`.

**Features exercised:** [Federation System](01_federation.md), [Lateral Composition](07_lateral_composition.md)

---

## Story: The Spinout

A successful project SubOU is spun out to independence via `SpinOutSubOU`. The `SubOUControl` is destroyed, the SubOU becomes fully independent, and it can now join federations (which managed SubOUs cannot do per invariant F-1).

**Features exercised:** [SubOU Hierarchy](../04_subou_hierarchy.md), [Federation System](01_federation.md), [Project Funding](04_project_funding.md)

---

## Story: The Constitutional Crisis

A federation dispute over charter amendment is resolved through constitutional process. High `AmendCharter` threshold (80%) forces compromise. The threat of `LeaveFederation` keeps the majority honest. The charter's amendment history records the entire episode on-chain.

**Features exercised:** [Federation System](01_federation.md), [Charter](../05_charter.md), [Charter Parametrization](10_charter_parametrization.md)
