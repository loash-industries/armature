# ADR: Default Non-Zero Execution Delays for Governance-Sensitive Proposal Types

| Field          | Value                                                       |
| -------------- | ----------------------------------------------------------- |
| **Status**     | Proposed                                                    |
| **Date**       | 2026-06-07                                                  |
| **Authors**    | —                                                           |
| **Package**    | `armature_framework` (`dao.move`, `board_voting.move`)      |
| **Depends on** | `ADR_SUBMIT_VOTE_EXECUTE` (introduces `submit_vote_execute`) |
| **Supersedes** | —                                                           |

---

## Context

### The Problem

`ADR_SUBMIT_VOTE_EXECUTE` introduces `board_voting::submit_vote_execute`, which allows a single
board member with sufficient voting weight to submit, vote, and execute a proposal atomically in
one PTB. The function is gated by a hard check:

```move
assert!(config.execution_delay_ms() == 0, EDelayForbidsAtomicExecution);
```

This means any proposal type whose stored `execution_delay_ms` is zero can be executed via the
atomic path — with no inter-PTB observation window and no opportunity for other board members to
vote NO or for a freeze admin to intervene.

The ADR's Constraint 6 states:

> governance-sensitive types (`SetBoard`, `AddMember`, `RemoveMember`, `UpdateProposalConfig`,
> `EnableProposalType`) MUST be configured with `execution_delay_ms > 0`. This is a configuration
> requirement, not a framework enforcement.

However, the current default — set by `dao.move::config_for_type` — is `DEFAULT_EXECUTION_DELAY_MS = 0`
for all types, including every governance-sensitive type. A newly created DAO is therefore immediately
vulnerable on all boards where a single member can meet quorum:

| Board size | Default quorum (50%) | Single-vote quorum met? |
|---|---|---|
| 1 member | `gte_bps(1, 1, 5000)` = `10000 ≥ 5000` | **Yes** |
| 2 members | `gte_bps(1, 2, 5000)` = `10000 ≥ 10000` | **Yes** (boundary) |
| 3 members | `gte_bps(1, 3, 5000)` = `10000 ≥ 15000` | No |

On a 1- or 2-member board (the primary use case for `submit_vote_execute`, per the ADR), a single
member can atomically execute `SetBoard` to replace the entire board with zero reaction window for
the other member, freeze admins, or monitoring tooling.

### Scope of Governance-Sensitive Types

The types that should carry a non-zero default delay are those whose execution can:

- Alter board membership (`SetBoard`, `AddMember`, `RemoveMember`, `BatchAddMembers`)
- Change the rules under which proposals are evaluated (`UpdateProposalConfig`)
- Expand the set of what can be proposed or bypassed (`EnableProposalType`, `EnableBypassType`,
  `DisableBypassType`, `DisableProposalType`)
- Transfer or remove security controls (`TransferFreezeAdmin`, `UnfreezeProposalType`)

Non-governance types — trading operations, treasury movements, and any application-specific
types added by deployers — have no such concern and correctly default to `execution_delay_ms = 0`.

### The Sync Obligation Problem

`ADR_SUBMIT_VOTE_EXECUTE` Constraint 7 notes that every submission-time floor check added to
`submit_proposal` must also be added to `submit_vote_execute`. Currently there is one such check
(the `EnableProposalType` 66% floor). This obligation is documented only in the ADR and in code
comments, with no co-location signal to alert a developer editing either function.

---

## Decision

### 1. Per-Type Execution Delay Defaults in `config_for_type`

Extend `dao.move::config_for_type` to assign a non-zero `execution_delay_ms` for each
governance-sensitive type. All other types retain `DEFAULT_EXECUTION_DELAY_MS = 0`.

The chosen default delay is **24 hours (86 400 000 ms)**. This matches common governance
best-practice and gives board members and freeze admins a meaningful observation window.

```move
// Governance-sensitive types get a 24-hour default delay so that
// submit_vote_execute cannot be used for them on freshly created DAOs.
// Deployers may reduce this via UpdateProposalConfig if their trust
// model explicitly permits shorter windows.
const GOVERNANCE_TYPE_EXECUTION_DELAY_MS: u64 = 86_400_000; // 24 hours
```

`config_for_type` becomes:

```move
fun config_for_type(type_key: &std::ascii::String): ProposalConfig {
    let approval_threshold = if (*type_key == b"EnableProposalType".to_ascii_string()) {
        ENABLE_PROPOSAL_TYPE_MIN_THRESHOLD
    } else if (*type_key == b"UpdateProposalConfig".to_ascii_string()) {
        UPDATE_PROPOSAL_CONFIG_MIN_THRESHOLD
    } else if (*type_key == b"EnableBypassType".to_ascii_string()) {
        ENABLE_BYPASS_TYPE_MIN_THRESHOLD
    } else {
        DEFAULT_APPROVAL_THRESHOLD
    };

    let execution_delay_ms = if (
        *type_key == b"SetBoard".to_ascii_string()
        || *type_key == b"AddMember".to_ascii_string()
        || *type_key == b"RemoveMember".to_ascii_string()
        || *type_key == b"BatchAddMembers".to_ascii_string()
        || *type_key == b"UpdateProposalConfig".to_ascii_string()
        || *type_key == b"EnableProposalType".to_ascii_string()
        || *type_key == b"EnableBypassType".to_ascii_string()
        || *type_key == b"DisableBypassType".to_ascii_string()
        || *type_key == b"DisableProposalType".to_ascii_string()
        || *type_key == b"TransferFreezeAdmin".to_ascii_string()
        || *type_key == b"UnfreezeProposalType".to_ascii_string()
    ) {
        GOVERNANCE_TYPE_EXECUTION_DELAY_MS
    } else {
        DEFAULT_EXECUTION_DELAY_MS
    };

    let composable = ...;

    proposal::new_config(
        DEFAULT_QUORUM,
        approval_threshold,
        DEFAULT_PROPOSE_THRESHOLD,
        DEFAULT_EXPIRY_MS,
        execution_delay_ms,
        DEFAULT_COOLDOWN_MS,
    ).with_composable_allowed(composable)
}
```

`Composite` is deliberately omitted from the governance-sensitive list. The composite pipeline
already enforces per-step type checks; its own execution delay should remain 0 to avoid
compounding delays with those of its constituent steps.

### 2. Sync-Obligation Comments in `submit_proposal` and `submit_vote_execute`

Add a comment block immediately before the submission-time floor check section in both functions.
The comment makes the sync obligation co-located with the code it governs rather than only in
the ADR:

```move
// === Submission-time floor checks ===
// SYNC OBLIGATION (ADR_GOVERNANCE_TYPE_DELAY_DEFAULTS, Constraint 7 of ADR_SUBMIT_VOTE_EXECUTE):
// Every check added here must also be added to the counterpart function in the same order.
// submit_proposal  ↔  submit_vote_execute
if (type_key == b"EnableProposalType".to_ascii_string()) {
    assert!((config.approval_threshold() as u64) >= ENABLE_APPROVAL_FLOOR_BPS, EFloorNotMet);
};
```

---

## Constraints

1. **Deployer override remains possible** — The 24-hour default can be reduced by any board member
   with sufficient weight via `UpdateProposalConfig`. The default protects freshly deployed DAOs;
   it does not permanently lock governance speed for all DAOs.

2. **Existing DAOs are unaffected** — This change only affects `config_for_type`, which is called
   at DAO creation time. Live DAOs already have their configs stored on-chain and are not
   retroactively updated.

3. **Single-operator trading sub-DAOs are unaffected** — The use case for `submit_vote_execute`
   is trading operation types (e.g., `PlaceLimitOrder`), which are not in the governance-sensitive
   list and retain `execution_delay_ms = 0`. The 24-hour delay only applies to the types that
   govern the DAO's own structure and security controls.

4. **SubDAO configs use the same `config_for_type`** — `subdao_proposal_configs` calls
   `build_proposal_configs` with the same function, so SubDAOs automatically inherit the
   non-zero delays for governance types.

5. **Test suite updates required** — Tests that create DAOs and immediately execute governance
   types (e.g., `SetBoard` tests that expect zero delay) will need to either: (a) advance the
   test clock past the delay, or (b) use `test_update_config` to set `execution_delay_ms = 0`
   in test-only setup, making the delay override explicit in each test.

---

## Correctness

### No New Functionality

This ADR introduces no new entry points, no new types, and no new Move constructs. It is purely
a default-value change in one internal function and two comment additions.

### Interaction with `submit_vote_execute`

The `EDelayForbidsAtomicExecution` check in `submit_vote_execute` fires against the live
`config.execution_delay_ms()` value for the type. With this ADR applied:

- `submit_vote_execute<SetBoard>(...)` → `config.execution_delay_ms() = 86_400_000 ≠ 0` → **aborts**
- `submit_vote_execute<PlaceLimitOrder>(...)` → `config.execution_delay_ms() = 0` → **proceeds**

This is the intended behavior: the atomic path is available only for types that have been
explicitly configured with `execution_delay_ms = 0`, which for governance types requires a
deliberate `UpdateProposalConfig` governance action.

### Interaction with `ticket_from_vote`

The standard two-PTB path (`submit_proposal` + `ticket_from_vote`) is also affected: governance
proposals submitted via `submit_proposal` will now require the delay to elapse before `ticket_from_vote`
can be called. This is intentional and desirable — it restores the observation window for all
governance types, not just those targeted via `submit_vote_execute`.

---

## Alternatives Considered

### A: Framework-Level Type Denylist in `submit_vote_execute`

Hardcode a list of governance-sensitive type keys inside `submit_vote_execute` and abort if the
caller attempts to use any of them:

```move
assert!(!dao::is_governance_sensitive_type(&type_key), EGovernanceTypeNotAllowed);
```

**Why not chosen:** A denylist requires ongoing maintenance as new governance types are added and
creates an implicit coupling between `submit_vote_execute` and DAO type taxonomy. The delay-based
approach is self-maintaining: any governance type correctly configured with a non-zero delay is
automatically blocked, and deployers who explicitly want to use the atomic path for a governance
type can do so by setting `execution_delay_ms = 0`.

### B: Leave as Configuration Requirement (Status Quo)

Keep the current `DEFAULT_EXECUTION_DELAY_MS = 0` for all types and rely on deployer discipline
to set non-zero delays for governance types, as specified in Constraint 6 of
`ADR_SUBMIT_VOTE_EXECUTE`.

**Why not chosen:** Zero-delay defaults create a misconfiguration trap for the exact use case
`submit_vote_execute` targets — small-board trading sub-DAOs that may not have dedicated
governance engineers reviewing their configs. A secure default is strictly better than a
documented manual step.

### C: Prevent `UpdateProposalConfig` from Setting Delay to Zero for Governance Types

Add a framework check in the `UpdateProposalConfig` handler that rejects configs with
`execution_delay_ms = 0` for governance-sensitive types.

**Why not chosen:** This removes legitimate flexibility for deployers who understand the
trade-offs and explicitly want zero-delay governance (e.g., a highly trusted single-operator
DAO that accepts the reduced observation window). The default approach preserves this flexibility
while securing the out-of-the-box experience.

---

## Implementation Checklist

- [ ] Add `GOVERNANCE_TYPE_EXECUTION_DELAY_MS: u64 = 86_400_000` constant to `dao.move`
- [ ] Extend `config_for_type` with the `execution_delay_ms` branch for the 11 governance types
- [ ] Add sync-obligation comment block before the floor check in `board_voting::submit_proposal`
- [ ] Add sync-obligation comment block before the floor check in `board_voting::submit_vote_execute`
- [ ] Update existing governance-type tests that expect zero execution delay:
  - Identify tests using `board_voting::ticket_from_vote` for governance types without advancing the clock
  - Either advance the test clock past `GOVERNANCE_TYPE_EXECUTION_DELAY_MS` or use `test_update_config` to override the delay
- [ ] Verify `submit_vote_execute` tests for `SetBoard`, `AddMember`, `RemoveMember` abort with `EDelayForbidsAtomicExecution` under the new defaults
- [ ] Update `ADR_SUBMIT_VOTE_EXECUTE.md` to mark Constraint 6 as framework-enforced by default (with override possible via `UpdateProposalConfig`)

---

## References

- `armature_framework/sources/dao.move` — `config_for_type`, `DEFAULT_EXECUTION_DELAY_MS`
- `armature_framework/sources/board_voting.move` — `submit_proposal`, `submit_vote_execute`
- `ADR_SUBMIT_VOTE_EXECUTE.md` — Constraint 6, Constraint 7, S4, S11
- `ADR_SUBMISSION_TIME_FLOOR_ENFORCEMENT.md` — precedent for moving enforcement into submission-time checks
