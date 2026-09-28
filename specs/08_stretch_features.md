# 08 — Stretch Features (Post-Hackathon)

Stretch features have been split into individual documents for easier navigation and maintenance. The documents are kept as originally written (March 2026). Several features have since been implemented, some differently from the design; the Status column below reflects the implementation, and the core specs ([03](03_core_spec.md), [04](04_subdao_hierarchy.md), [05](05_charter.md)) describe what shipped.

**See the [stretch features index](stretch/00_index.md) for the full list.**

---

## Quick Links

| Feature | Status | Document |
|---|---|---|
| Federation System | Not implemented | [stretch/01_federation.md](stretch/01_federation.md) |
| Governance Models (Direct, Weighted) | Superseded: removed; Board is the only model | [stretch/02_governance_models.md](stretch/02_governance_models.md) |
| Migration via SpawnDAO | Implemented (`SpawnDAO`, `TransferAssets`, `dao::destroy`); with Board the only model, it moves assets to a successor rather than changing governance model | [stretch/03_migration.md](stretch/03_migration.md) |
| Project Funding Lifecycle | Not implemented | [stretch/04_project_funding.md](stretch/04_project_funding.md) |
| Advanced Proposals | Implemented | [stretch/05_advanced_proposals.md](stretch/05_advanced_proposals.md) |
| EVE Infrastructure Integration | Partially implemented (autojoin, tribe constructors) | [stretch/06_eve_infrastructure.md](stretch/06_eve_infrastructure.md) |
| Lateral Composition | Partially implemented (downward only) | [stretch/07_lateral_composition.md](stretch/07_lateral_composition.md) |
| User Stories | Partially implemented | [stretch/08_user_stories.md](stretch/08_user_stories.md) |
| Proposal Composition ([#1](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/1)) | Implemented (`armature::composite`) | [stretch/09_proposal_composition.md](stretch/09_proposal_composition.md) |
| Charter Parametrization ([#4](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/4)) | Not implemented | [stretch/10_charter_parametrization.md](stretch/10_charter_parametrization.md) |
| Open Proposal Type Set ([#5](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/5)) | Implemented, differently from the proposal | [stretch/11_open_proposal_type_set.md](stretch/11_open_proposal_type_set.md) |
