# armature

Programmable DAO protocol on the Sui blockchain. Provides on-chain organizational primitives — governance, treasury, capability vaults, charters, and proposals — for decentralized communities to coordinate without admin keys or backdoors.

Built for the EVE Frontier ecosystem, but general-purpose by design. Organizations use Armature to represent tribes, alliances, and syndicates on-chain with code-backed guarantees.

## Architecture

```
Move contracts (Sui)  →  armature-indexer (Rust)  →  PostgreSQL  →  React UI
```

The `armature` repo owns the on-chain Move contracts and the React dashboard UI. Indexing and data persistence live in the separate `armature-indexer` service.

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

## UI

React 19 + Vite + TanStack + shadcn/ui dashboard at `ui/`. Provides a DAO management interface for proposal creation, voting, treasury, and membership.

## Dev Stack

Full local stack via `docker-compose.dev.yml`:
- `sui-localnet` — local Sui node
- Move packages deployed on startup
- PostgreSQL (for indexer)
- React UI at `http://localhost:5173`

```bash
make dev   # start full stack
```

## Notable Design Patterns

- **Hot-potato pattern** for proposal execution — proposals must be consumed in a single PTB, preventing partial execution
- **Forward-only status transitions** — proposals move `active → passed → executed` (or `active → expired`) with no reversals
- **`controller::privileged_submit`** — proposals bypass voting and go directly to `executed`; no `ProposalPassed` event emitted
