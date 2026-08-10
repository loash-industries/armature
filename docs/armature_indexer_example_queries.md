# Armature Indexer — Example Queries (phase 1)

Runnable SQL against the phase-1 tables in `triex-book/crates/schema/geyser/002_armature.sql`. Companion to [`armature_indexer_handler_inventory.md`](./armature_indexer_handler_inventory.md) and [`armature_indexer_phase1_plan.md`](./armature_indexer_phase1_plan.md).

## Conventions

- **`$1` is the address/DAO id**, in the exact stored form: `0x` + **lowercase 64-hex** (what `hex32` writes). Normalize inputs to that before binding, or the equality won't match.
- Membership is **board = governance membership** (`is_governance_member` == `is_board_member`; every DAO is Board-governed). That's the only membership tier the indexer tracks; finer capability roles (deposit/withdraw/edit, grant/read/write) live in the ACL tables and are covered by query 3.
- All state tables carry `is_active` / `is_member` — **always filter on it**; the tables retain revoked/removed rows (last-writer-wins), they are not deleted.

Relevant tables: `dao_members`, `daos`, `subdao_edges`, `vault_acl`, `keyspace_acl`, `dao_receipt_vaults`, `keyspaces`, `encrypted_entries` (+ views `trading_accounts`, `keyspace_versions`, `encrypted_entry_epochs`).

---

## 1. Current membership of an organization

Board members currently in DAO `$1`:

```sql
SELECT member_addr
FROM dao_members
WHERE dao_id = $1
  AND is_member
ORDER BY member_addr;
```

With a member count and the org's status/name for context:

```sql
SELECT d.dao_id,
       d.name,
       d.status,
       count(*) FILTER (WHERE m.is_member) AS member_count,
       array_agg(m.member_addr ORDER BY m.member_addr) FILTER (WHERE m.is_member) AS members
FROM daos d
LEFT JOIN dao_members m ON m.dao_id = d.dao_id
WHERE d.dao_id = $1
GROUP BY d.dao_id, d.name, d.status;
```

---

## 2. What organizations (and role) an address belongs to

Every org `$1` is a current member of. `role` is `governance_member` because board membership is the only membership tier; for capability roles see query 3.

```sql
SELECT m.dao_id,
       d.name,
       d.status,
       'governance_member' AS role,
       m.last_checkpoint
FROM dao_members m
LEFT JOIN daos d ON d.dao_id = m.dao_id
WHERE m.member_addr = $1
  AND m.is_member
ORDER BY d.status NULLS LAST, m.dao_id;
```

Enriched with the sub-DAO hierarchy — shows, for each org the address belongs to, whether it is a controlled sub-DAO and of which parent:

```sql
SELECT m.dao_id,
       d.name,
       d.status,
       se.parent_dao AS controller_dao,   -- NULL if the org is a top-level DAO
       'governance_member' AS role
FROM dao_members m
LEFT JOIN daos d  ON d.dao_id = m.dao_id
LEFT JOIN subdao_edges se
       ON se.child_dao = m.dao_id
      AND se.edge_kind = 'control'
      AND se.is_active
WHERE m.member_addr = $1
  AND m.is_member
ORDER BY controller_dao NULLS FIRST, m.dao_id;
```

---

## 3. What ACLs an address can access (direct `player:` + derived `ou:`)

An address's effective access is the union of:
- **direct** grants to it as a `Player` principal (`principal_kind = 'player'`), and
- **inherited** grants to any org it is a board member of, as an `Ou` principal (`principal_kind = 'ou'`) — the `Ou` expansion that `is_governance_member` performs on-chain.

Across both receipt vaults and keyspaces, with a `via` column so the caller sees *why* they have each grant, and `owner_org` (the DAO that owns the resource, from the registries):

```sql
WITH me AS (
    SELECT $1::text AS addr
),
my_orgs AS (                          -- orgs the address is a current board member of
    SELECT m.dao_id
    FROM dao_members m, me
    WHERE m.member_addr = me.addr
      AND m.is_member
)
SELECT 'vault'  AS resource_kind,
       va.vault_id AS resource_id,
       va.role,
       va.principal_kind AS via,      -- 'player' = direct, 'ou' = inherited via org
       CASE WHEN va.principal_kind = 'ou' THEN va.principal_value END AS via_org,
       drv.registrant_dao_id AS owner_org   -- DAO that owns the vault
FROM vault_acl va
CROSS JOIN me
LEFT JOIN dao_receipt_vaults drv ON drv.vault_id = va.vault_id
WHERE va.is_active
  AND (
        (va.principal_kind = 'player' AND va.principal_value = me.addr)
     OR (va.principal_kind = 'ou'     AND va.principal_value IN (SELECT dao_id FROM my_orgs))
      )

UNION ALL

SELECT 'keyspace' AS resource_kind,
       ka.keyspace_id AS resource_id,
       ka.role,
       ka.principal_kind AS via,
       CASE WHEN ka.principal_kind = 'ou' THEN ka.principal_value END AS via_org,
       ks.registrant_dao_id AS owner_org    -- NULL for personal keyspaces
FROM keyspace_acl ka
CROSS JOIN me
LEFT JOIN keyspaces ks ON ks.keyspace_id = ka.keyspace_id
WHERE ka.is_active
  AND (
        (ka.principal_kind = 'player' AND ka.principal_value = me.addr)
     OR (ka.principal_kind = 'ou'     AND ka.principal_value IN (SELECT dao_id FROM my_orgs))
      )
ORDER BY resource_kind, owner_org, resource_id, role;
```

### Variants

**Keyspaces only, `Read` role** (e.g. "which private-location keyspaces can I decrypt?"):

```sql
WITH me AS (SELECT $1::text AS addr),
     my_orgs AS (SELECT dao_id FROM dao_members WHERE member_addr = $1 AND is_member)
SELECT ka.keyspace_id, ka.principal_kind AS via
FROM keyspace_acl ka
WHERE ka.is_active
  AND ka.role = 'read'
  AND (
        (ka.principal_kind = 'player' AND ka.principal_value = (SELECT addr FROM me))
     OR (ka.principal_kind = 'ou'     AND ka.principal_value IN (SELECT dao_id FROM my_orgs))
      );
```

**Direct grants only** (drop the `ou:` expansion — just what was granted to the wallet itself):

```sql
SELECT 'vault' AS resource_kind, vault_id AS resource_id, role
FROM vault_acl
WHERE is_active AND principal_kind = 'player' AND principal_value = $1
UNION ALL
SELECT 'keyspace', keyspace_id, role
FROM keyspace_acl
WHERE is_active AND principal_kind = 'player' AND principal_value = $1;
```

---

## 4. Capability roles an address holds, grouped by organization

Bridges queries 2 and 3: rolls the accessible ACLs up to their **owning org** (via the vault/keyspace registries), so you get "for each org, which capability roles does this address effectively hold." This is the richer answer to "orgs *and roles*" that the ACL side couldn't give before the registries existed.

```sql
WITH me AS (SELECT $1::text AS addr),
     my_orgs AS (
         SELECT dao_id FROM dao_members WHERE member_addr = $1 AND is_member
     ),
     access AS (
         SELECT drv.registrant_dao_id AS org, 'vault' AS resource_kind, va.role
         FROM vault_acl va
         CROSS JOIN me
         JOIN dao_receipt_vaults drv ON drv.vault_id = va.vault_id
         WHERE va.is_active AND drv.registrant_dao_id IS NOT NULL
           AND ( (va.principal_kind = 'player' AND va.principal_value = me.addr)
              OR (va.principal_kind = 'ou'     AND va.principal_value IN (SELECT dao_id FROM my_orgs)) )
         UNION ALL
         SELECT ks.registrant_dao_id, 'keyspace', ka.role
         FROM keyspace_acl ka
         CROSS JOIN me
         JOIN keyspaces ks ON ks.keyspace_id = ka.keyspace_id
         WHERE ka.is_active AND ks.registrant_dao_id IS NOT NULL
           AND ( (ka.principal_kind = 'player' AND ka.principal_value = me.addr)
              OR (ka.principal_kind = 'ou'     AND ka.principal_value IN (SELECT dao_id FROM my_orgs)) )
     )
SELECT a.org,
       d.name,
       a.resource_kind,
       array_agg(DISTINCT a.role ORDER BY a.role) AS roles
FROM access a
LEFT JOIN daos d ON d.dao_id = a.org
GROUP BY a.org, d.name, a.resource_kind
ORDER BY a.org, a.resource_kind;
```

---

## 5. Encrypted entries an address can read

The concrete payload behind query 3's keyspace grants: every encrypted entry in a keyspace the address holds a `Read` grant on (direct `player:` or inherited `ou:`). This is the join to run when "fetch ACLs by player" needs to return the actual decryptable content pointers, not just the keyspace ids.

```sql
WITH me AS (SELECT $1::text AS addr),
     my_orgs AS (
         SELECT dao_id FROM dao_members WHERE member_addr = $1 AND is_member
     ),
     readable_keyspaces AS (
         SELECT DISTINCT ka.keyspace_id
         FROM keyspace_acl ka
         CROSS JOIN me
         WHERE ka.is_active
           AND ka.role = 'read'
           AND ( (ka.principal_kind = 'player' AND ka.principal_value = me.addr)
              OR (ka.principal_kind = 'ou'     AND ka.principal_value IN (SELECT dao_id FROM my_orgs)) )
     )
SELECT e.entry_id,
       e.keyspace_id,
       ks.name            AS keyspace_name,
       ks.registrant_dao_id AS owner_org,   -- NULL for personal keyspaces
       e.uri,                                -- Walrus/IPFS pointer to the AES-GCM blob
       e.description,
       e.epoch,                             -- NULL until the entry's first re-encryption
       e.updated_at_cp
FROM encrypted_entries e
JOIN readable_keyspaces rk ON rk.keyspace_id = e.keyspace_id
LEFT JOIN keyspaces ks ON ks.keyspace_id = e.keyspace_id
ORDER BY e.keyspace_id, e.entry_id;
```

Count of readable entries per keyspace (a lighter summary):

```sql
WITH me AS (SELECT $1::text AS addr),
     my_orgs AS (SELECT dao_id FROM dao_members WHERE member_addr = $1 AND is_member)
SELECT e.keyspace_id, ks.name, count(*) AS readable_entries
FROM keyspace_acl ka
CROSS JOIN me
JOIN encrypted_entries e ON e.keyspace_id = ka.keyspace_id
LEFT JOIN keyspaces ks   ON ks.keyspace_id = ka.keyspace_id
WHERE ka.is_active AND ka.role = 'read'
  AND ( (ka.principal_kind = 'player' AND ka.principal_value = me.addr)
     OR (ka.principal_kind = 'ou'     AND ka.principal_value IN (SELECT dao_id FROM my_orgs)) )
GROUP BY e.keyspace_id, ks.name
ORDER BY readable_entries DESC;
```

---

## 6. Encrypted entries owned by an organization

Org-scoped rollup — every entry in every keyspace the DAO owns. Falls straight out of the registries (`keyspaces.registrant_dao_id`), no extra machinery. Same shape works for vaults via `dao_receipt_vaults.registrant_dao_id`.

```sql
SELECT e.entry_id,
       e.keyspace_id,
       ks.name AS keyspace_name,
       e.uri,
       e.description,
       e.epoch,
       e.updated_at_cp
FROM encrypted_entries e
JOIN keyspaces ks ON ks.keyspace_id = e.keyspace_id
WHERE ks.registrant_dao_id = $1        -- the org's dao_id
ORDER BY e.keyspace_id, e.entry_id;
```

Personal keyspaces (`registrant_dao_id IS NULL`) are naturally excluded. Both sides are indexed (`keyspaces_by_registrant_dao`, `encrypted_entries_by_keyspace`), so this is cheap. Count per org:

```sql
SELECT count(*) AS org_entries
FROM encrypted_entries e
JOIN keyspaces ks ON ks.keyspace_id = e.keyspace_id
WHERE ks.registrant_dao_id = $1;
```

---

## 7. Keyspace version & stale entries (re-encryption)

`keyspace.version` is exposed as the **`keyspace_versions`** view — it counts post-creation `Read`-role grant/revoke events, excluding the creation-time grants (matched via `creation_tx`). Fetch the keyspaces a player can read *with* their current version, so a client can tell a read-set rotation happened since last fetch:

```sql
WITH me AS (SELECT $1::text AS addr),
     my_orgs AS (SELECT dao_id FROM dao_members WHERE member_addr = $1 AND is_member)
SELECT ka.keyspace_id, ks.name, kv.version
FROM keyspace_acl ka
CROSS JOIN me
LEFT JOIN keyspaces          ks ON ks.keyspace_id = ka.keyspace_id
LEFT JOIN keyspace_versions  kv ON kv.keyspace_id = ka.keyspace_id
WHERE ka.is_active AND ka.role = 'read'
  AND ( (ka.principal_kind = 'player' AND ka.principal_value = me.addr)
     OR (ka.principal_kind = 'ou'     AND ka.principal_value IN (SELECT dao_id FROM my_orgs)) )
GROUP BY ka.keyspace_id, ks.name, kv.version;
```

Entries **pending re-encryption** (encrypted for an older read-set than the keyspace's current one) — the re-encryption worker's query, via the **`encrypted_entry_epochs`** view, which reconstructs the publish epoch for entries that have never been re-encrypted:

```sql
SELECT entry_id, keyspace_id, entry_epoch, keyspace_version
FROM encrypted_entry_epochs
WHERE entry_epoch < keyspace_version
ORDER BY keyspace_id, entry_id;
```

Stale entries within a single keyspace:

```sql
SELECT entry_id, entry_epoch, keyspace_version
FROM encrypted_entry_epochs
WHERE keyspace_id = $1 AND entry_epoch < keyspace_version;
```

---

## Notes & caveats

- **`Ou` grants are always a live join, never a cached flatten.** A `MemberAdded` to an org silently changes who can access every vault/keyspace granted to that org — no ACL event fires. Query 3 recomputes this each call by joining `*_acl` against `dao_members`; do not materialize a per-address access list.
- **Owning-org can be stale after a vault re-key.** `dao_receipt_vaults.registrant_dao_id` reflects the vault's **init-time** owner. `dao_receipt_vault::update_registry_key` re-assigns a vault to a new DAO on-chain but emits no event, so `owner_org` won't reflect a migration until that module grows an event. Personal keyspaces have `registrant_dao_id = NULL` (no owning org) — expected, not a gap.
- **Keyspace `version` / entry `epoch` are derived, and absolute only if indexed from creation.** `keyspace_versions` and `encrypted_entry_epochs` reconstruct version as the count of post-creation `Read` grant/revoke events (creation grants excluded via `creation_tx`), and fill in the publish epoch for never-re-encrypted entries. A keyspace first indexed from a checkpoint *after* its creation has a NULL `creation_tx` and no pre-window Read events, so its version is a **relative** counter — monotonic and correct for changes observed, but not equal to the on-chain absolute value. Index the `armature_vault` package from its publish checkpoint (via `INCLUDE_HANDLER_IDS` + `START_CHECKPOINT`) for absolute epochs. `encrypted_entries.epoch` itself is still only populated by `EntryUpdated`; the view supplies the reconstructed value where the column is NULL.
- **Bounded staleness.** These read whatever checkpoint the pipelines have committed to; `last_checkpoint` on each row tells you how fresh a given fact is.
