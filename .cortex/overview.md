# armature

Programmable DAO protocol on the Sui blockchain. Provides on-chain organizational primitives — governance, treasury, capability vaults, charters, and proposals — for decentralized communities to coordinate without admin keys or backdoors.

Built for the EVE Frontier ecosystem, but general-purpose by design. Organizations use Armature to represent tribes, alliances, and syndicates on-chain with code-backed guarantees.

## Architecture

```
Move contracts (Sui)  →  armature-indexer (separate repo)  →  PostgreSQL  →  UI (separate repo)
```

This repo contains only the on-chain Move smart contracts. Indexing lives in `armature-indexer`; the dashboard UI lives in `ui`.

## Move Packages

| Package | Purpose |
|---------|---------|
| `armature_framework` | Core DAO primitive: lifecycle, governance, treasury vault, capability vault, charter, emergency freeze, board voting, proposal execution engine, plus the default/classification payload types under `sources/types/` (33 modules) |
| `armature_proposals` | Handlers and domain-specific payload types: admin, board, security, sub-DAO, treasury, currency, upgrades (27 modules) |
| `armature_world_bridge` | EVE Frontier world bridge: tribe-allowlisted AutojoinDAO self-join via the bypass path (3 modules) |

### Key Modules

- **`dao`** — DAO lifecycle, root object, and the proposal-type registry (one dynamic-field slot per enabled type, keyed by the payload's `TypeName`; the root never grows with enabled types)
- **`proposal`** — Hot-potato proposal execution engine
- **`governance`** — Voting thresholds, quorum, and config
- **`treasury_vault`** — Coin storage and release
- **`capability_vault`** — Delegated capability management
- **`charter`** — Governance constitution document
- **`board_voting`** — Board member weighted voting
- **`controller`** — Privileged execution path (bypasses voting)
- **`emergency`** — Protocol freeze and recovery

## Notable Design Patterns

- **Hot-potato pattern** for proposal execution — proposals must be consumed in a single PTB, preventing partial execution
- **Forward-only status transitions** — proposals move `active → passed → executed` (or `active → expired`) with no reversals
- **`controller::privileged_submit`** — proposals bypass voting and go directly to `executed`; no `ProposalPassed` event emitted
- **Type-keyed registry** — `submit_proposal<P>` / `submit_vote_execute<P>` / `ticket_from_cap<P>` select the config by `P`'s slot; there is no caller-supplied type key to spoof. Display keys are human labels only, unique per DAO, and resolvable back to the type for admin operations

## Recent Changes

- **2026-09-24 — type-keyed proposal registry (ARMATURE-9)**: replaced the string-keyed proposal-type maps on `dao::DAO` with one dynamic-field slot per enabled type, keyed by the payload's canonical `TypeName`. Removes the per-transaction rewrite of a root that grew with every enabled type, and removes the caller-supplied `type_key` from submission and execution calls. See `changelog.md`.
