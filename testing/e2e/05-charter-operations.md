# 05 — Charter Operations

> **Tool:** Playwright (Chromium)
> **Network:** Sui localnet
> **Route:** `/dao/$daoId/charter`, `/dao/$daoId/proposals/new?type=CharterUpdate`

## Prerequisites

- DAO created with charter (name, description, image_url set at creation)
- Board members [A, B, C]
- CharterUpdate (UpdateMetadata) proposal type enabled (default)

## Scenarios

### 5.1 — View charter

1. Navigate to `/dao/$daoId/charter`

**Expected:**

- Charter page shows:
  - DAO name (as set during creation)
  - Description (with preserved whitespace/newlines)
  - Image (if URL was provided)

### 5.2 — Update charter metadata

1. Connect as wallet A
2. Navigate to `/dao/$daoId/proposals/new?type=CharterUpdate`
3. Fill form:
   - New IPFS CID or image URL
   - Proposal description
4. Submit proposal
5. Vote Yes with A and B → Passed
6. Execute

**Expected:**

- Transaction succeeds
- Charter page reflects updated image_url / IPFS CID
- `MetadataUpdated` event emitted with new_ipfs_cid
- Dashboard activity feed shows the update event

### 5.3 — Charter update with empty image URL

1. Submit CharterUpdate with empty/blank image URL
2. Vote + execute

**Expected:**

- Charter image_url cleared (or set to empty string)
- Charter page shows no image

### 5.4 — Sequential charter updates

1. Execute CharterUpdate to set CID "abc123"
2. Submit another CharterUpdate to set CID "def456"
3. Vote + execute

**Expected:**

- Charter page shows "def456" (latest update wins)
- Both MetadataUpdated events recorded

### 5.5 — Negative: Non-board-member submits charter update

1. Connect as wallet X (not a board member)
2. Attempt to submit CharterUpdate proposal

**Expected:**

- Transaction fails — caller not a board member
