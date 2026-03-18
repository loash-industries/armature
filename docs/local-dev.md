# Local Development with Docker

Run the full Armature stack locally with a single command.

## Architecture

```
┌──────────────────────────────────────────────────┐
│  make dev                                        │
│                                                  │
│  ┌───────────────┐   ┌────────────────────────┐  │
│  │ sui-localnet  │   │ postgres               │  │
│  │ :9000 (RPC)   │   │ :5432                  │  │
│  │ :9123 (faucet)│   │                        │  │
│  └───────┬───────┘   └────────────────────────┘  │
│          │                                       │
│  ┌───────▼────────┐                              │
│  │ armature-deploy│  (init — runs once)          │
│  │ publishes Move packages, creates test DAO     │
│  └───────┬────────┘                              │
│          │                                       │
│  ┌───────▼───────┐                               │
│  │ ui (Vite)    │                               │
│  │ :5173        │                               │
│  └──────────────┘                                │
└──────────────────────────────────────────────────┘
```

With the `world` profile, world-contracts are also deployed before Armature:

```
  sui-localnet → world-deploy → armature-deploy → ui
```

## Prerequisites

- Docker and Docker Compose v2+
- ~2 GB disk (Sui tools image)
- Ports 9000, 9123, 5173, 5432 available

## Quick Start

```bash
# Armature only (no world-contracts)
make dev

# With EVE Frontier world-contracts
make dev-deps    # clones world-contracts to .world-contracts/
docker compose -f docker-compose.dev.yml --profile world up --build

# Open the UI
open http://localhost:5173
```

## Makefile Targets

| Target              | Description                                    |
| ------------------- | ---------------------------------------------- |
| `make dev`          | Start the full stack (foreground)              |
| `make dev-up`       | Start the full stack (detached)                |
| `make dev-down`     | Stop all services                              |
| `make dev-reset`    | Wipe all volumes and redeploy from scratch     |
| `make dev-logs`     | Tail logs for all services                     |
| `make dev-ps`       | Show running service status                    |
| `make dev-deps`     | Clone world-contracts (for world profile)      |
| `make db`           | Start only PostgreSQL (for local indexer dev)  |
| `make clean`        | Remove all Docker volumes and generated config |

## How It Works

### Boot Sequence

1. **sui-localnet** starts a Sui v1.67.2 node with `--force-regenesis` and a faucet
2. *(world profile only)* **world-deploy** clones and deploys EVE Frontier world-contracts, configures fuel/energy/gates
3. **armature-deploy** publishes `armature_framework` + `armature_proposals` (36 modules), creates 3 test wallets and a test DAO
4. **ui** copies the generated `.env.local` and starts Vite with hot reload
5. **postgres** runs independently for the indexer

### Shared Volume

Deployment artifacts pass between containers via the `shared-data` volume:

```
/shared/
├── .env.world          # (world profile) WORLD_PACKAGE_ID, governor key
├── .env.armature       # ARMATURE_PACKAGE_ID, test DAO IDs, wallet addresses
├── ui.env.local        # Ready-to-use VITE_* env vars for the UI
└── world-deployment.json  # (world profile) Full publish transaction output
```

## Sui Version Alignment

The `sui-tools` image tag must match the Sui framework revision pinned in the world-contracts `Move.lock`. Currently:

| Component | Version |
|---|---|
| `sui-tools` Docker image | `testnet-v1.67.2` |
| world-contracts Move.lock framework rev | `b38bca86f...` (~v1.67.1) |

If world-contracts updates their Move.lock to a newer Sui framework, bump the image tag in `docker-compose.dev.yml` and `docker/Dockerfile.sui-deploy` accordingly.

## Development Workflow

- **Move contracts** — Edit files under `packages/`. Run `make dev-reset` to redeploy after changes.
- **UI** — Edit files under `ui/`. Vite hot-reloads automatically.
- **Indexer** — Not in the dev compose (requires Rust build). Run on the host:
  ```bash
  cargo run --bin armature-indexer -- \
    --db-url postgres://postgres:postgrespw@localhost:5432/armature \
    --remote-store-url http://localhost:9000
  ```

## Troubleshooting

### View deployed package IDs

```bash
docker run --rm -v armature_shared-data:/shared alpine cat /shared/.env.armature
```

### Connect Sui CLI to the Docker localnet

```bash
sui client new-env --alias docker-localnet --rpc http://127.0.0.1:9000
sui client switch --env docker-localnet
```

### Port conflicts

```bash
lsof -i :9000  # Check what's using a port
```

### Re-deploy contracts only

```bash
make dev-reset && make dev
```

## Technical Notes

- Deploy containers use `network_mode: host` to avoid gnutls TLS issues when the Move package manager fetches Sui framework dependencies via git inside Docker bridge networks.
- The `Dockerfile.sui-deploy` extends `mysten/sui-tools` with Node.js 24 and pnpm for JSON parsing and world-contracts TypeScript scripts.
- The API service (`api/`) is a CI/CD pipeline placeholder and is not included in the dev compose. The UI talks directly to Sui RPC via `@mysten/dapp-kit`.
