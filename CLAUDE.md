# CLAUDE.md

## About This Repo

`armature` is the on-chain OU protocol for the Trinary Exchange platform — a programmable governance, treasury, and capability framework written in Move for the Sui blockchain. It also contains the React UI dashboard. For full context see `.cortex/overview.md`.

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
- Status transitions are **forward-only**: `Active → Passed` is the only stored transition. Execution (`ticket_from_vote`) deletes the `Proposal` and emits `ProposalExecuted`; `proposal::delete_expired_proposal` lets anyone delete an Active proposal past `expiry_ms`, or a Passed one whose execution window (`passed_at + execution_delay_ms + expiry_ms`) has closed, emitting `ProposalExpired`. The storage rebate goes to that transaction's gas payer
- Single-PTB executions (`submit_vote_execute`, `ticket_from_cap`, `controller::privileged_submit`) create **no** `Proposal` object — the `proposal_id` is minted via `ctx.fresh_object_address()` and the audit trail is events only. `privileged_submit` emits `ProposalCreated` + `ProposalPayloadCreated` + `ProposalExecuted` (no `ProposalPassed`)
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

---
<!-- cortex-managed: do not edit below this line -->
# Cortex: Org-Wide Instructions

> Managed by cortex-config (`standards/ai-tooling/org-claude.md`) and distributed to every service repo. Edit it there, not here. Write repo-specific notes above the marker line.

Cortex is the org's shared knowledge base: every service's docs and API specs, coding conventions, infrastructure, and runbooks. Claude Code reaches it through the Cortex MCP server.

**What to do when isn't written in this file.** It comes live from cortex-relay, so it stays current without editing this file:
- The Cortex MCP server's instructions say which tool fits which question.
- The SessionStart hook (`.claude/hooks/cortex-session-digest.mjs`) adds a digest for this repo's service at session start: the services it talks to and their latest changes, the services that use it, its infrastructure, and the skills for it.

**Rules that don't change:**
- **This repo:** read `.cortex/overview.md` locally. It's fresher than search results about this repo. `.cortex/manifest.yaml` has its `name`, the `service_id` for Cortex calls.
- **Anything outside this repo** (another service's API, infrastructure, environments, secrets): ask Cortex before reading or grepping sibling repos.
- **Before committing:** draft the changelog entry with `chronicle_changes` and commit the `.cortex/` changes with your code. The commit hook (`.claude/hooks/cortex-commit-check.mjs`) blocks a commit with no changelog entry.
- **Org facts you learn** (how an environment behaves, where something really points) belong in a Cortex document, not only in private memory.
- **If Cortex isn't connected,** say so instead of guessing.

**Setup, once per machine:** create a key on the docs app's `/api-keys` page (https://cortex.trinary.exchange/api-keys). Connect the MCP server at `https://cortex-relay-dev-api.trinary.exchange/mcp` with it, and `export CORTEX_MCP_KEY=<key>` in your shell profile so the session hook can fetch the digest.
