# Stretch Features — Index

All features documented here are explicitly **out of hackathon scope**. They preserve design work and show the protocol's full vision — but they are not implementation targets for the hackathon submission.

For hackathon-scope specs, see the [main document index](../00_index.md).

---

## Feature Map

| # | Feature | Summary | Issue |
|---|---|---|---|
| 01 | [Federation System](01_federation.md) | Peer associations — alliances, trade agreements, mutual defense pacts | — |
| 02 | [Governance Models](02_governance_models.md) | Direct and Weighted governance variants beyond Board | — |
| 03 | [Migration](03_migration.md) | `SpawnDAO` governance model migration with full asset transfer | — |
| 04 | [Project Funding](04_project_funding.md) | Kickstarter-style SubDAO lifecycle, revenue splits, ticker registry | — |
| 05 | [Advanced Proposals](05_advanced_proposals.md) | Rate-limited payments, package upgrade authorization | — |
| 06 | [EVE Infrastructure](06_eve_infrastructure.md) | Application-layer patterns: gates, minehaul, markets, ZK voting | — |
| 07 | [Lateral Composition](07_lateral_composition.md) | Multi-membership — a DAO as SubDAO, federation member, and controller simultaneously | — |
| 08 | [User Stories](08_user_stories.md) | Narrative scenarios: The Alliance, The Spinout, The Constitutional Crisis | — |
| 09 | [Proposal Composition](09_proposal_composition.md) | Bundle multiple proposals into atomic composite with hot potato pipeline | [#1](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/1) |
| 10 | [Charter Parametrization](10_charter_parametrization.md) | On-chain charter DFs that encode governance constraints for proposals | [#4](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/4) |
| 11 | [Open Proposal Type Set](11_open_proposal_type_set.md) | Third-party proposal types via public hot-potato-gated APIs | [#5](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/5) |

---

## Reading Order

For a quick skim of the full vision: 01 → 07 → 09 → 10 → 11 → 08

For security review: 01 (federation threats) → 04 (funding threats) → 10 (enforcement model) → 11 (trust model)
