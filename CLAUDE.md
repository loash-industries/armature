# CLAUDE.md

## About This Repo

`armature` is the on-chain DAO protocol for the Trinary Exchange platform — a programmable governance, treasury, and capability framework written in Move for the Sui blockchain. It also contains the React UI dashboard. For full context see `.cortex/overview.md`.

The Rust indexer lives in the separate `armature-indexer` repo.

## Cortex Integration

This repo is managed by Cortex. For full service context, conventions, and org-wide standards, connect to the Cortex MCP server:

**MCP Server:** `https://cortex-relay-dev-api.trinary.exchange/mcp`

### Key Commands

- To get this repo's full context: use `search_context` with `service_id: "armature"`
- To get general org conventions: use `get_conventions` with `scope: "general"`
- To get TypeScript/React conventions: use `get_conventions` with `language: "typescript"`

## Before Committing

**Always call `chronicle_changes` before committing.** This updates `.cortex/changelog.md` and patches `overview.md` if the change is significant. Include the updated `.cortex/` files in your commit alongside the code changes.

```
chronicle_changes({
  service_id: "armature",
  change_summary: "brief description of what changed",
  changed_files: ["packages/armature_framework/sources/..."]
})
```

## Repo-Specific Notes

- Move packages: `armature_framework` (core primitives) and `armature_proposals` (concrete proposal types)
- Proposal execution uses the **hot-potato pattern** — proposals must be consumed in a single PTB
- Status transitions are **forward-only**: `active → passed → executed` (or `active → expired`)
- `controller::privileged_submit` proposals go directly `active → executed` — no `ProposalPassed` event is emitted
- UI is at `ui/` — React 19 + Vite + TanStack + shadcn/ui

## Build & Run

```bash
# Full local stack (sui-localnet + Move deploy + UI)
make dev

# Move contracts only
sui move build --path packages/armature_framework
sui move test --path packages/armature_framework

# UI only
cd ui && npm install && npm run dev
```

---

> **This file is managed by cortex-config and distributed automatically.**
> Do not edit the section below — changes belong in `cortex-config/standards/ai-tooling/org-claude.md`.

---

# Cortex AI Tooling — Org-Wide Instructions

All AI coding agents in this org have access to a shared knowledge base via the Cortex MCP server. **Use it before reading source files or writing new code.**

**MCP Server:** `https://cortex-relay-dev-api.trinary.exchange/mcp`

## When to use Cortex tools

| Situation | Tool to call |
|---|---|
| Understanding how any service in the org works | `search_context` |
| Before writing code in any framework we use | `get_conventions` |
| Before committing any change | `chronicle_changes` |
| Finding which service owns a domain, endpoint, or topic | `search_context` |
| Checking org-wide security, logging, or git standards | `get_conventions` with `scope: "general"` |

## Tool reference

**`search_context`** — semantic search across all service docs, conventions, and infra docs
```
search_context({ query: "how does auth work", service_id?: "signer-api" })
```

**`get_conventions`** — fetch coding conventions by framework, language, or scope
```
get_conventions({ framework: "nestjs" })
get_conventions({ language: "typescript" })
get_conventions({ scope: "general" })
```

**`chronicle_changes`** — generate a changelog entry before committing. Always call this.
```
chronicle_changes({
  service_id: "<name from .cortex/manifest.yaml>",
  change_summary: "brief description of what changed",
  changed_files: ["src/foo/bar.rs"]
})
```

## What NOT to do

- Do not read source files to answer architectural questions about other services — use `search_context` instead
- Do not write new code without first calling `get_conventions` for that language/framework
- Do not commit without calling `chronicle_changes` and including the updated `.cortex/` files

## Service-specific context

Each repo has a `.cortex/manifest.yaml` with its `name` (the `service_id` for MCP calls) and a `.cortex/overview.md` describing what it does. Read those first if Cortex search doesn't answer your question.
