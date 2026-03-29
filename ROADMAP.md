# ROADMAP

> *"Civilization advances by extending the number of important operations which we can perform without thinking about them."*
> — Alfred North Whitehead

Armature exists to make this literal. Every primitive we ship should disappear into the background of organizational life — governance, treasury, delegation, federation — until coordinating a thousand-player alliance feels no harder than running a five-person crew.

---

## Phase 0 — Foundation (complete)

Core protocol implemented and deployed to testnet.

- Board governance model with snapshot voting, quorum, and approval thresholds
- Proposal lifecycle: create, vote, pass/expire, execute with hot-potato authorization
- Treasury vault with multi-coin deposits, governance-gated withdrawals, and auto-cleanup
- Capability vault with borrow, loan (hot-potato return), and extract patterns
- Charter as on-chain metadata with governance-gated amendments
- Emergency freeze system with selective type freezing and auto-expiry
- Sub-DAO hierarchy: creation, controller authority, pause/unpause, spin-out to sovereignty
- 20 proposal types across admin, board, security, treasury, sub-DAO, and upgrade categories
- Per-type governance parameters (quorum, threshold, delay, cooldown, expiry)
- Safety rails: 80% floor for self-referential changes, 66% floor for enabling new types
- Rust checkpoint indexer, PostgreSQL schema, React UI, REST API

## Phase 1 — Governance Depth

Expand governance beyond board voting to support organizations of different shapes.

- [ ] **Direct governance** — share-based voting where weight matches stake; suited for cooperatives and mining pools
- [ ] **Weighted governance** — delegation-based liquid democracy; expertise surfaces through trust
- [ ] **Proposal composition** — bundle multiple proposals into a single atomic governance action voted on once and executed as a pipeline (hot-potato chain; any step fails, all revert)

## Phase 2 — Developer Experience

Chart the programmable surface and make proposal extension writing frictionless.

- [ ] **Proposal extension guide** — document the `ExecutionRequest<P>` hot-potato pattern, type-state storage, and the full lifecycle a third-party proposal type must implement
- [ ] **Proposal template scaffold** — minimal working example that developers can clone: payload struct, handler module, enable flow, and integration test
- [ ] **Programmable surface map** — published reference of every governance-gated entry point, what each `ExecutionRequest` unlocks, and the capability/vault APIs available to handlers
- [ ] **Type-state cookbook** — patterns for proposals that need persistent state across executions (following the `SmallPaymentState` model: lazy init, epoch reset, cap recalculation)
- [ ] **Extension test harness** — reusable test utilities for creating mock DAOs, submitting proposals, and exercising the full vote-execute cycle without boilerplate
- [ ] **Published Move interface package** — stable importable package exposing only the types and functions extension authors need, decoupled from framework internals

## Phase 3 — Charter Invariants

Evolve the charter from a purely human-readable document into a two-tier constitutional system.

- [ ] **Framework-enforced invariants** — on-chain structured parameters (maximum single withdrawal, quorum floors) that proposals read and the framework enforces at execution time
- [ ] **Handler-enforced invariants** — configurable policy constraints (max board size, spending caps) checked by proposal handlers
- [ ] **Invariant amendment process** — governed alongside the document aspect, with matching approval bars and cooldown periods
- [ ] **Walrus integration** — store charter document on decentralized blob storage with on-chain content hash and version history

## Phase 4 — Federation

Enable peer-to-peer alliances between sovereign DAOs without surrendering autonomy.

- [ ] **Federation formation** — two-phase propose-and-accept flow between sovereign DAOs
- [ ] **FederationSeat capability** — non-transferable membership token granting voice in collective governance
- [ ] **Collective treasury** — shared resource pool with multi-layer voting (representative vote + member DAO ratification for high-stakes decisions)
- [ ] **Voluntary exit** — any member can leave through its own governance process
- [ ] **Sovereignty gate** — only sovereign DAOs (not controlled sub-DAOs) can join; sub-DAOs must spin out first

## Phase 5 — Ticker Registry

Give organizations stable, human-readable identities in a shared namespace.

- [ ] **Protocol-level ticker registry** — short identifiers (up to 5 characters) mapping to DAO object IDs
- [ ] **Recursive addressing** — hierarchical tickers reflecting organizational structure (e.g. `TRIB/ENG/UI`)
- [ ] **Ticker portability** — ticker capability travels with vault contents during DAO migration, preserving identity across successor transitions
- [ ] **Registration economics** — scarce namespace with registration fees funding protocol revenue

## Phase 6 — UX: The Disappearing Interface

The protocol succeeds when players stop noticing it. Following Whitehead, the goal is not a powerful dashboard — it's the absence of one.

- [ ] **Intent-driven proposals** — players describe what they want ("fund the gate expansion, cap it at 500 SUI, let engineering run it") and the UI assembles the correct proposal composition, parameters, and routing
- [ ] **Contextual governance** — surface only the decisions that matter to the current player in the current moment; hide the machinery of quorum math, cooldown timers, and type registries
- [ ] **Notification-as-governance** — votes and approvals arrive where players already are (in-game, mobile, chat); acting on them requires minimal context-switching
- [ ] **Progressive disclosure** — a new tribe with three members sees a simple interface; a hundred-member alliance with sub-DAOs and federation seats sees exactly the additional complexity it needs, no more
- [ ] **Operational templates** — common organizational patterns (founding a tribe, spinning up a department, proposing a trade agreement) packaged as one-click flows that expand into correct proposal sequences
- [ ] **Ambient status** — treasury health, active proposals, and organizational posture visible at a glance without requiring navigation; the DAO's vital signs, not its internal organs

## Phase 7 — Smart Assembly Integration

Connect Armature governance to EVE Frontier's on-chain game primitives.

- [ ] **Gate controller governance** — DAOs hold gate Smart Assembly capabilities in the capability vault; access, tolling, and permissions governed by proposal
- [ ] **Mining and storage cooperatives** — collectively owned extraction and logistics infrastructure managed through DAO treasury flows
- [ ] **Infrastructure-as-commons** — individual player assets contributed to DAOs become collectively governed public utilities

## Phase 8 — Civilizational Mesh

Compose all primitives into the multi-scale organizational fabric.

- [ ] **Lateral composition** — a single DAO simultaneously acts as sub-DAO (downward control), federation member (upward membership), and parent of its own sub-DAOs
- [ ] **Tempo gradient** — governance parameters naturally vary by organizational depth: fast and loose at the edges (small teams), slow and deliberate at higher layers (tribes, alliances)
- [ ] **Project funding** — Kickstarter-style sub-DAO model where backers contribute to a campaign, receive proportional governance tokens, and share in revenue
- [ ] **Revenue mesh** — parents fund children down, children return revenue up, peers exchange laterally; protocol provides pipes, governance provides policy
