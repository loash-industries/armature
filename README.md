<p align="center">
  <img src="assets/armature-cover.png" alt="Armature Project banner">
</p>

# Armature

A programmable DAO protocol on the [Sui](https://sui.io) blockchain. Armature provides the organizational primitives — governance, treasury, capability vaults, charters, and proposals — for decentralized communities to coordinate without admin keys or backdoors.

Built for the [EVE Frontier](https://evefrontier.com) ecosystem, but general-purpose by design.

Players use Armature to represent their tribes, alliances, and syndicates on-chain. It gives organizations the tools to scale, capture player-generated value, and build relationships backed by code guarantees — no handshake deals, no trust assumptions. The goal: a civilizational mesh woven from one repeated, powerful primitive.

> **[Watch the demo →](https://youtu.be/P60Oe7JcIio)** | **[Read the whitepaper →](https://github.com/loash-industries/armature/releases/tag/whitepaper/v0.1.0)** | **[View the roadmap →](ROADMAP.md)**

## Architecture

```
Move contracts (Sui)  →  Rust indexer  →  PostgreSQL  →  React UI
```

This repo contains the on-chain Move packages only. The indexer lives in `armature-indexer` (separate repo).

## Repository Structure

```
├── packages/
│   ├── armature_framework/     # Core Move modules (15)
│   │   └── sources/            #   dao, proposal, governance, treasury_vault,
│   │                           #   capability_vault, charter, emergency,
│   │                           #   board_voting, controller, tribe, composite,
│   │                           #   encrypted_entry, external_execution,
│   │                           #   spend_guard, utils
│   ├── armature_proposals/     # Proposal type modules
│   │   └── sources/
│   │       ├── admin/          #   metadata, proposal config, enable/disable types
│   │       ├── board/          #   set board
│   │       ├── currency/       #   mint, burn, allowances, currency ops
│   │       ├── security/       #   freeze config, exemptions, admin transfer
│   │       ├── subdao/         #   create, spawn, spin-out, pause, asset/cap transfer
│   │       ├── treasury/       #   send coin, small payments, inter-DAO transfers
│   │       └── upgrade/        #   package upgrades
│   └── armature_world_bridge/  # EVE Frontier world integration
├── specs/                      # Design docs, ADRs, and formal spec
├── proposals/                  # Proposal design docs and e2e tests
├── testing/                    # Test utilities
├── docs/                       # Development guides
├── scripts/                    # Deploy and utility scripts
├── docker/                     # Dockerfiles and deploy scripts
├── whitepaper/                 # Typst source and compiled PDF
├── docker-compose.dev.yml      # Full dev stack
├── Makefile                    # Dev task automation
└── package.json                # Node workspace root
```

## Quick Start

### Prerequisites

- Docker and Docker Compose v2+
- ~2 GB disk (for the Sui tools image)
- Ports 9000, 9123 available

### Run the full stack

```bash
make dev
```

This starts sui-localnet, deploys Armature packages, and creates a test DAO.

To include EVE Frontier world-contracts (requires `make dev-deps` first):

```bash
docker compose -f docker-compose.dev.yml --profile world up
```

See [docs/local-dev.md](docs/local-dev.md) for the full development guide and troubleshooting.

### Makefile targets

| Target | Description |
|--------|-------------|
| `make dev` | Start the full stack (foreground) |
| `make dev-up` | Start the full stack (detached) |
| `make dev-down` | Stop all services |
| `make dev-reset` | Wipe volumes and redeploy from scratch |
| `make dev-logs` | Tail logs for all services |
| `make dev-ps` | Show running services |
| `make dev-deps` | Clone world-contracts (needed for `--profile world`) |
| `make dev-deps-update` | Update world-contracts to latest |
| `make deploy-world` | Re-run world-contracts deployment only |
| `make deploy-armature` | Re-run Armature deployment only |
| `make dev-docs` | Watch and recompile the whitepaper |
| `make build-docs` | Build the whitepaper PDF for release |
| `make clean` | Remove all Docker volumes and generated config |

## Move Contracts

The protocol is split into three packages:

- **armature_framework** — Core DAO primitive: lifecycle, governance config, treasury vault, capability vault, charter, emergency freeze, board voting, tribe management, and the proposal execution engine (hot-potato pattern).
- **armature_proposals** — Concrete proposal types organized by domain: admin, board, currency, security, sub-DAO, treasury, and upgrades.
- **armature_world_bridge** — Integration layer for the EVE Frontier world-contracts.

```bash
# Build
sui move build --path packages/armature_framework

# Test
sui move test --path packages/armature_framework

# Format
bunx prettier-move -c packages/armature_framework/sources/**/*.move --write
```

## License

See [LICENSE](LICENSE) for details.
