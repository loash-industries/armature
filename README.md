<p align="center">
  <img src="assets/armature-cover.png" alt="Armature Project banner">
</p>

# Armature

A programmable DAO protocol on the [Sui](https://sui.io) blockchain. Armature provides the organizational primitives — governance, treasury, capability vaults, charters, and proposals — for decentralized communities to coordinate without admin keys or backdoors.

Built for the [EVE Frontier](https://evefrontier.com) ecosystem, but general-purpose by design.

Players use Armature to represent their tribes, alliances, and syndicates on-chain. It gives organizations the tools to scale, capture player-generated value, and build relationships backed by code guarantees — no handshake deals, no trust assumptions. The goal: a civilizational mesh woven from one repeated, powerful primitive.

> **[Watch the demo →](https://youtu.be/FaZUX4C_6is)** | **[Read the whitepaper →](https://github.com/loash-industries/armature/releases/tag/whitepaper/v0.1.0)**

## Architecture

```
Move contracts (Sui)  →  Rust indexer  →  PostgreSQL  →  React UI
```

| Layer | Location | Purpose |
|-------|----------|---------|
| **Smart contracts** | `packages/` | On-chain DAO primitive, proposal execution, governance |
| **Indexer** | `crates/indexer/` | Processes Sui checkpoints, indexes DAO events |
| **Schema** | `crates/schema/` | Diesel ORM models and PostgreSQL migrations |
| **UI** | `ui/` | React dashboard for DAO management |
| **API** | `api/` | Express server (CI/CD placeholder) |

## Repository Structure

```
├── packages/
│   ├── armature_framework/     # Core Move modules (11)
│   │   └── sources/            #   dao, proposal, governance, treasury_vault,
│   │                           #   capability_vault, charter, emergency,
│   │                           #   board_voting, controller, utils
│   └── armature_proposals/     # Proposal type modules (25)
│       └── sources/
│           ├── admin/          #   metadata, proposal config, enable/disable types
│           ├── board/          #   set board
│           ├── security/       #   freeze config, exemptions, admin transfer
│           ├── subdao/         #   create, spawn, spin-out, pause, asset/cap transfer
│           ├── treasury/       #   send coin, small payments, inter-DAO transfers
│           └── upgrade/        #   package upgrades
├── crates/
│   ├── indexer/                # Rust event indexer + Axum REST API
│   └── schema/                 # Diesel schema & migrations
├── ui/                         # React 19 + Vite + TanStack + shadcn/ui
├── api/                        # Express API server
├── docker/                     # Dockerfiles and deploy scripts
├── whitepaper/                 # Typst source and compiled PDF
├── docs/                       # Development guides
├── .github/workflows/          # CI/CD pipelines
├── docker-compose.dev.yml      # Full dev stack
├── docker-compose.yml          # PostgreSQL only
├── Cargo.toml                  # Rust workspace root
├── Makefile                    # Dev task automation
└── package.json                # Node workspace root
```

## Quick Start

### Prerequisites

- Docker and Docker Compose v2+
- ~2 GB disk (for the Sui tools image)
- Ports 9000, 9123, 5173, 5432 available

### Run the full stack

```bash
make dev
```

This starts sui-localnet, deploys Move packages, creates a test DAO, starts PostgreSQL, and launches the UI at **http://localhost:5173**.

See [docs/local-dev.md](docs/local-dev.md) for the full development guide, including the world-contracts profile and troubleshooting.

### Makefile targets

| Target | Description |
|--------|-------------|
| `make dev` | Start the full stack (foreground) |
| `make dev-up` | Start the full stack (detached) |
| `make dev-down` | Stop all services |
| `make dev-reset` | Wipe volumes and redeploy from scratch |
| `make dev-logs` | Tail logs for all services |
| `make db` | Start only PostgreSQL (for local indexer dev) |
| `make dev-docs` | Watch and recompile the whitepaper |
| `make clean` | Remove all Docker volumes and generated config |

## Move Contracts

The protocol is split into two packages:

- **armature_framework** — Core DAO primitive: lifecycle, governance config, treasury vault, capability vault, charter, emergency freeze, board voting, and the proposal execution engine (hot-potato pattern).
- **armature_proposals** — Concrete proposal types organized by domain: admin, board, security, sub-DAO, treasury, and upgrades.

```bash
# Build
sui move build --path packages/armature_framework

# Test
sui move test --path packages/armature_framework

# Format
bunx prettier-move -c packages/armature_framework/sources/**/*.move --write
```

## Rust Indexer

The indexer processes Sui checkpoint data, filters for Armature events across the core modules (`dao`, `proposals`, `governance`, `treasury`), and writes indexed state to PostgreSQL via Diesel.

```bash
# Start PostgreSQL
make db

# Run the indexer
cargo run --bin armature-indexer -- \
  --db-url postgres://postgres:postgrespw@localhost:5432/armature \
  --remote-store-url http://localhost:9000
```

## License

See [LICENSE](LICENSE) for details.