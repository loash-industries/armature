<p align="center">
  <img src="assets/armature-logo.svg" width="120" alt="Armature logo">
</p>

# Armature Project

Armature service repository — a monorepo containing a Node.js API, React UI, Rust indexer, and Sui Move contracts.

## Structure

```
├── api/                # Express API server
│   ├── src/
│   │   └── index.ts
│   ├── Dockerfile
│   └── package.json
├── ui/                 # React frontend (Vite)
│   ├── src/
│   │   ├── App.tsx
│   │   └── main.tsx
│   └── package.json
├── crates/
│   ├── indexer/        # Rust event indexer (Sui checkpoint processor)
│   │   ├── src/
│   │   │   ├── main.rs
│   │   │   ├── lib.rs
│   │   │   ├── models.rs
│   │   │   ├── traits.rs
│   │   │   └── handlers/
│   │   └── Cargo.toml
│   └── schema/         # Diesel ORM schema & migrations
│       ├── src/
│       │   ├── lib.rs
│       │   ├── models.rs
│       │   └── schema.rs
│       ├── migrations/
│       └── Cargo.toml
├── packages/
│   ├── armature_framework/        # DAO Framework code
│   │   ├── sources/
│   │   │   ├── *.move
│   │   └── Move.toml
│   └── armature_proposals/       # DAO Proposal code
│       ├── sources/
│   │   │   ├── *.move
│       └── Move.toml
├── docker-compose.yml  # PostgreSQL for indexer
├── Cargo.toml          # Rust workspace root
└── package.json        # Node workspace root
```

## Development

Install all dependencies:

```bash
npm install
```

Run both API and UI in development mode:

```bash
npm run dev
```

Or run them individually:

```bash
# API only (port 3000)
npm run dev:api

# UI only (port 5173)
npm run dev:ui
```

## Building

Build all packages:

```bash
npm run build
```

## Docker

Build the API image:

```bash
cd api
docker build -t test-api .
docker run -p 3000:3000 test-api
```

## Rust Indexer

Start PostgreSQL:

```bash
docker compose up -d
```

Build and run the indexer:

```bash
cargo build
cargo run --bin armature-indexer -- --db-url postgres://postgres:postgrespw@localhost:5432/armature
```

Run tests:

```bash
cargo test
```

## Move Contracts

Build:

```bash
sui move build --path packages/armature_framework
```

Test:

```bash
sui move test --path packages/armature_framework
```

Format:

```bash
bunx prettier-move -c packages/armature_framework/sources/**/*.move --write
```