# armature
armature service repository


A monorepo containing a Node.js API, React UI, rust indexer, and sui move contracts.

## Structure

```
├── api/          # Express API server
│   ├── src/
│   │   └── index.ts
│   ├── Dockerfile
│   └── package.json
├── ui/           # React frontend (Vite)
│   ├── src/
│   │   ├── App.tsx
│   │   └── main.tsx
│   └── package.json
├── crates/           # Rust indexer
└── package.json  # Workspace root
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