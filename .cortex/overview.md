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
| `armature_framework` | Core DAO primitive: lifecycle, governance, treasury vault, capability vault, charter, emergency freeze, board voting, proposal execution engine (11 modules) |
| `armature_proposals` | Concrete proposal types by domain: admin, board, security, sub-DAO, treasury, upgrades (25 modules) |

### Key Modules

- **`dao`** — DAO lifecycle and root object
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
