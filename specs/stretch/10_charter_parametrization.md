# Stretch: Charter as Programmable Constitution

> Part of the [stretch features index](00_index.md). Not in hackathon scope.
>
> Tracks [Issue #4](https://github.com/0xErgod/eve-x-sui-hackathon-scratchpad/issues/4).

Extend the `Charter` object with **dynamic fields encoding machine-readable governance parameters** that proposal handlers read and enforce at execution time. The Charter becomes a dual-layer object: a human-readable constitution on Walrus *and* an on-chain programmable policy engine that directly shapes proposal behavior.

This makes the "Charter parametrizes Proposals" arrow in the DAO Atom model (see [01 Vision](../01_vision.md) — The DAO Atom) a real on-chain data dependency.

---

## Charter Parameter Storage

```move
struct CharterParam has copy, drop, store {
    value_u64:     u64,          // numeric value (bps, amounts, counts, durations)
    floor:         Option<u64>,  // immutable minimum (set at creation)
    ceiling:       Option<u64>,  // immutable maximum (set at creation)
    amended_at_ms: u64,
}

// Stored as dynamic fields on Charter, keyed by parameter name:
// dynamic_field::add<String, CharterParam>(&mut charter.id, string::utf8(key), param)
```

## Two-Tier Enforcement

| Tier | Enforced in | What | Guarantee |
|---|---|---|---|
| **Framework-enforced** | `proposal.move` (`create` / `execute`) | Type-agnostic params: `min_execution_delay_ms`, `min_approval_threshold_bps`, `min_quorum_bps` | Applies to ALL proposal types, including third-party |
| **Handler-enforced** | `treasury_ops.move`, `board_ops.move`, etc. | Type-specific params: `max_single_treasury_spend`, `min_board_size`, `max_board_size` | Applies to framework handlers; advisory for third-party |

Framework-enforced params are checked in `proposal::execute` (or `proposal::create`) because they are type-agnostic — they constrain `ProposalConfig` values, not payload contents. Handler-enforced params require type knowledge and are checked in individual handlers.

## Example Charter Parameters

```
"min_approval_threshold_bps"   -> 6000     // no proposal type can go below 60% (framework-enforced)
"min_execution_delay_ms"       -> 86400000 // 24h floor on all execution delays (framework-enforced)
"max_single_treasury_spend"    -> 10000    // per-proposal spend cap in SUI (handler-enforced)
"min_board_size"               -> 3        // SetBoard floor (handler-enforced)
"max_board_size"               -> 9        // SetBoard ceiling (handler-enforced)
"max_subdao_depth"             -> 3        // CreateSubDAO depth limit (handler-enforced)
```

## Amendment Flow

New proposal type `AmendCharterParam` (high threshold, same governance rigor as `AmendCharter`):

```move
struct AmendCharterParam has store {
    key:       String,
    new_value: u64,
    summary:   String,
}
```

Handler validates `new_value` is within the param's immutable `floor..ceiling` bounds. Floor/ceiling are set at parameter creation and cannot be amended — changing bounds requires `SpawnDAO` migration (see [Migration](03_migration.md)). This avoids infinite meta-governance recursion.

## Template Proposals (Extension)

Charter params could define proposal archetypes:

```
"template:small_payment:max_amount"    -> 100 SUI
"template:small_payment:threshold_bps" -> 5000
"template:large_payment:min_delay_ms"  -> 172_800_000
```

A `SendCoin` is classified at creation time based on its amount against charter-defined thresholds. Same Move type, different governance treatment based on the constitution.

## Constitution / Statute Mental Model

| | Constitution (Charter Params) | Statutes (ProposalConfig) |
|---|---|---|
| **Lives on** | `Charter` dynamic fields | `DAO.proposal_configs` table |
| **Amend via** | `AmendCharterParam` (~80% threshold) | `UpdateProposalConfig` (lower threshold) |
| **Enforces** | Floors, ceilings, hard limits | Operational settings within bounds |
| **Bounds** | Immutable floor/ceiling per param | Bounded by charter params |

## Technical Feasibility

**What works cleanly:**
- Sui DFs are cheap — 10-30 `u64` params are negligible gas/storage
- Charter is already a separate shared object — no new architectural primitives
- `get_param_or_default` pattern — `dynamic_field::exists_` + `borrow`, standard Sui
- Backward compatible — DAOs without charter params get permissive defaults

**Known limitations:**
1. **Handler-enforced params are opt-in.** Third-party types are not bound unless their handler checks. Mirrors real constitutions.
2. **Shared object contention.** Adding `&Charter` to `proposal::execute` is a new sequencing constraint. Manageable since amendments are rare.
3. **Ex post facto risk.** Charter param changes between creation and execution can strand proposals. Recommended: hybrid approach (snapshot governance params, live-read execution constraints).
4. **String-keyed DF footguns.** Mitigated by `charter_params.move` constants module or phantom-typed DF keys.
5. **`proposal::execute` signature change.** Must be decided before coding starts.

## Scope

- **Phase**: Stretch feature (post-hackathon)
- **Dependencies**: Core proposal system, Charter object, stable handler pattern
- **Modules affected**: `charter.move`, `proposal.move`, all `proposals/*.move` handlers, new `charter_params.move`
- **New proposal types**: `AmendCharterParam`, `CreateCharterParam`

---

**See also:** [Open Proposal Type Set](11_open_proposal_type_set.md) — framework-enforced charter params apply universally to third-party types. [Charter spec](../05_charter.md) for the existing human-layer design.
