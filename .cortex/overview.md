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
- **`governance`** — Board roster: a `Table` of members with join/leave tenures and a `roster_version` that advances on every membership change
- **`treasury_vault`** — Coin storage and release
- **`capability_vault`** — Delegated capability management
- **`charter`** — Governance constitution document
- **`board_voting`** — Proposal submission, voting (`board_voting::vote`) and execution for board governance
- **`controller`** — Privileged execution path (bypasses voting)
- **`emergency`** — Protocol freeze and recovery

## Notable Design Patterns

- **Hot-potato pattern** for proposal execution — proposals must be consumed in a single PTB, preventing partial execution
- **Forward-only status transitions** — a live proposal moves `Active → Passed` only. Execution deletes it (`ProposalExecuted`), and anyone can delete it with `delete_expired_proposal` once voting expires (Active) or its execution window closes (Passed), emitting `ProposalExpired`
- **`controller::privileged_submit`** — proposals bypass voting and go directly to `executed`; no `ProposalPassed` event emitted
- **Event-only audit for single-PTB executions** — `submit_vote_execute`, `ticket_from_cap` and `privileged_submit` create no `Proposal` object; the proposal ID is minted like an object ID and the lifecycle events are the audit record. Only two-PTB `submit_proposal` shares a `Proposal<P>`
- **Read-only execution for cooldown-free types** — `submit_vote_execute_readonly` / `ticket_from_vote_readonly` / `ticket_from_cap_readonly` take `&DAO` and skip the last-executed write, so single-vote trades leave the DAO unmodified and do not serialise on it; `&mut DAO` variants remain for types with a cooldown
- **Snapshot by roster version** — a proposal records the roster version at creation instead of copying the board; its voters are the members at that version, so the Proposal object's size does not depend on board size. `SetBoard` is an add/remove diff because the roster table cannot be enumerated
- **Type-keyed registry** — `submit_proposal<P>` / `submit_vote_execute<P>` / `ticket_from_cap<P>` select the config by `P`'s slot; there is no caller-supplied type key to spoof. Display keys are human labels only, unique per DAO, and resolvable back to the type for admin operations

## Recent Changes

- **2026-09-26 — table-backed board roster and snapshot-by-version voting (ARMATURE-13, ARMATURE-14)**: the roster moves out of the DAO root into a versioned `Table`; proposals store `snapshot_version` instead of a roster copy; voting moves to `board_voting::vote(proposal, &DAO, …)`; `SetBoard` becomes `{ to_add, to_remove }`. See `changelog.md`.
- **2026-09-25 — executed proposals are deleted, expired ones can be deleted by anyone (ARMATURE-12)**: `ticket_from_vote` consumes and deletes the `Proposal`; `delete_expired_proposal` replaces `try_expire` and also covers passed proposals whose execution window has closed. See `changelog.md`.
- **2026-09-24 — event-only audit for single-PTB executions (ARMATURE-11)**: atomic, bypass and controller executions emit events instead of creating a shared `Proposal<P>`; `ProposalCreated` gains `metadata_ipfs`. See `changelog.md`.
- **2026-09-24 — read-only DAO on the atomic and bypass paths (ARMATURE-10)**: `&DAO` variants of `submit_vote_execute`, `ticket_from_vote` and `ticket_from_cap` for types with cooldown 0; no DAO write or write lock on the trading path. See `changelog.md`.
- **2026-09-24 — type-keyed proposal registry (ARMATURE-9)**: replaced the string-keyed proposal-type maps on `dao::DAO` with one dynamic-field slot per enabled type, keyed by the payload's canonical `TypeName`. Removes the per-transaction rewrite of a root that grew with every enabled type, and removes the caller-supplied `type_key` from submission and execution calls. See `changelog.md`.
