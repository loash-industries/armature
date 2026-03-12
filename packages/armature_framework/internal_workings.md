# Armature Framework — Internal Workings

## Privilege Model Overview

The framework enforces a **proposal-gated privilege model**: all state-mutating operations on DAO objects require either an `ExecutionRequest<P>` hot-potato token (proving a governance proposal passed and was executed), a `FreezeAdminCap` (for emergency operations), or `public(package)` visibility (framework-internal only).

The only permissionless operations are:
- **Reading** accessors on all objects
- **Depositing** into the treasury vault
- **Claiming** coins directly transferred to the vault address
- **Voting** (if in the governance snapshot)

---

## 1. ExecutionRequest<P> — The Core Gate

**Module:** `proposal`

```move
public struct ExecutionRequest<phantom P> {
    dao_id: ID,
    proposal_id: ID,
}
```

A **hot-potato** (no `drop`, `copy`, or `store`) emitted by `proposal::execute()` and consumed by `proposal::consume()`. Because it cannot be dropped, any PTB that creates one _must_ pass it into a handler that consumes it, ensuring the governance decision is actually carried out. The phantom type `P` binds the request to a specific proposal payload type.

**Lifecycle:**
1. Board member calls `board_voting::submit_proposal<P>()` → shared `Proposal<P>` created
2. Board members call `proposal::vote()` until quorum + threshold met → status becomes `Passed`
3. Board member calls `board_voting::authorize_execution()` → `ExecutionRequest<P>` returned
4. Handler in `armature_proposals` consumes the request via `proposal::consume()`

---

## 2. Proposal-Gated Functions by Module

### 2.1 dao.move

All DAO state mutations require `&ExecutionRequest<P>`:

| Function | Effect |
|----------|--------|
| `set_board_governance<P>()` | Replace board members and seat count |
| `enable_proposal_type<P>()` | Add a new proposal type with config |
| `disable_proposal_type<P>()` | Remove a proposal type and its config |
| `update_proposal_config<P>()` | Replace config for an existing type |
| `set_execution_paused<P>()` | Pause or resume all proposal execution |
| `set_migrating<P>()` | Transition DAO to `Migrating` status (irreversible) |

### 2.2 treasury_vault.move

| Function | Gate | Effect |
|----------|------|--------|
| `withdraw<T, P>()` | `ExecutionRequest<P>` | Extract coin from treasury; auto-cleans zero balances |
| `deposit<T>()` | **None (permissionless)** | Anyone can deposit |
| `claim_coin<T>()` | **None (permissionless)** | Recover coins directly transferred to vault address |

### 2.3 capability_vault.move

| Function | Gate | Effect |
|----------|------|--------|
| `store_cap<T, P>()` | `ExecutionRequest<P>` | Store capability object in vault |
| `borrow_cap<T, P>()` | `ExecutionRequest<P>` | Immutable borrow of stored capability |
| `borrow_cap_mut<T, P>()` | `ExecutionRequest<P>` | Mutable borrow of stored capability |
| `loan_cap<T, P>()` | `ExecutionRequest<P>` | Temporary extract; returns `(T, CapLoan)` hot-potato |
| `extract_cap<T, P>()` | `ExecutionRequest<P>` | Permanently remove capability from vault |
| `create_subdao_control<P>()` | `ExecutionRequest<P>` | Create `SubDAOControl` for parent–child DAO relationship |
| `destroy_subdao_control<P>()` | `ExecutionRequest<P>` | Destroy `SubDAOControl`, relinquishing parent authority |
| `privileged_extract<T>()` | `SubDAOControl` | Parent DAO reclaims capability from child vault |
| `store_cap_init<T>()` | `public(package)` | Store capability during DAO creation only |

### 2.4 charter.move

| Function | Gate | Effect |
|----------|------|--------|
| `update_metadata<P>()` | `ExecutionRequest<P>` | Update the DAO's metadata IPFS CID |

### 2.5 emergency.move

| Function | Gate | Effect |
|----------|------|--------|
| `freeze_type()` | `FreezeAdminCap` | Freeze a proposal type for up to `max_freeze_duration_ms` |
| `unfreeze_type()` | `FreezeAdminCap` | Admin-unfreeze a frozen type immediately |
| `governance_unfreeze_type<P>()` | `ExecutionRequest<P>` | Governance-authorized unfreeze |
| `update_freeze_duration<P>()` | `ExecutionRequest<P>` | Change max freeze duration for future freezes |
| `unfreeze_all<P>()` | `ExecutionRequest<P>` | Bulk-unfreeze all currently frozen types |

**Protected types** (cannot be frozen): `TransferFreezeAdmin`, `UnfreezeProposalType`

### 2.6 board_voting.move

| Function | Gate | Effect |
|----------|------|--------|
| `submit_proposal<P>()` | Board member assertion | Create a new governance proposal |
| `authorize_execution<P>()` | Board member (via `proposal::execute`) | Produce `ExecutionRequest<P>` for a passed proposal |

### 2.7 proposal.move

| Function | Gate | Effect |
|----------|------|--------|
| `vote<P>()` | Snapshot membership + no double-vote | Cast vote; may transition to `Passed` |
| `execute<P>()` | `public(package)` + board member check | Emit `ExecutionRequest<P>` |
| `try_expire<P>()` | Timestamp past expiry | Transition `Active` → `Expired` |

---

## 3. public(package) Functions — Framework-Internal Only

These are callable only from within the `armature_framework` package and are used during DAO construction or internal orchestration:

| Module | Function | Purpose |
|--------|----------|---------|
| `governance` | `new_board()` | Construct Board governance config from init payload |
| `governance` | `assert_board_member()` | Assert address is board member (aborts if not) |
| `governance` | `board_vote_snapshot()` | Snapshot board members for proposal voting |
| `governance` | `set_board()` | Replace board members atomically |
| `dao` | `governance_mut()` | Mutable access to governance config |
| `dao` | `record_execution()` | Track last execution timestamp for cooldown |
| `proposal` | `execute()` | Execute proposal and return `ExecutionRequest` |
| `proposal` | `new_execution_request()` | Factory for `ExecutionRequest` (test-only in practice) |
| `charter` | `new()` / `share()` | Construct and share Charter during DAO creation |
| `emergency` | `new()` / `new_admin_cap()` / `share()` / `transfer_admin_cap()` | Construct and distribute emergency objects |
| `treasury_vault` | `new()` / `share()` | Construct and share TreasuryVault |
| `capability_vault` | `new()` / `share()` / `store_cap_init()` / `new_subdao_control()` | Construct, share, and seed CapabilityVault |

---

## 4. Board Member Assertions

Board membership is checked at two critical points:

1. **Proposal creation** — `board_voting::submit_proposal()` calls `dao.governance().assert_board_member(ctx.sender())`
2. **Proposal execution** — `proposal::execute()` calls `governance.is_board_member(executor)` and aborts with `ENotEligible` if false

This means only current board members can _create_ proposals and _trigger_ execution of passed proposals. Voting is limited to the **snapshot** taken when the proposal was created.

---

## 5. How armature_proposals Consumes These Gates

The `armature_proposals` package contains the concrete proposal handlers that bridge `ExecutionRequest<P>` into framework mutations:

| Proposal Module | Payload Type | Framework Function(s) Called |
|-----------------|-------------|------------------------------|
| `board_ops` | `SetBoard` | `dao::set_board_governance()` |
| `admin_ops` | `DisableProposalType` | `dao::disable_proposal_type()` |
| `admin_ops` | `EnableProposalType` | `dao::enable_proposal_type()` |
| `admin_ops` | `UpdateProposalConfig` | `dao::update_proposal_config()` |
| `admin_ops` | `UpdateMetadata` | `charter::update_metadata()` |
| `treasury_ops` | `SendCoin<T>` | `treasury_vault::withdraw()` |
| `treasury_ops` | `SendCoinToDAO<T>` | `treasury_vault::withdraw()` + `deposit()` |
| `security_ops` | `TransferFreezeAdmin` | `emergency::transfer_admin_cap()` |
| `security_ops` | `UnfreezeProposalType` | `emergency::governance_unfreeze_type()` |
| `security_ops` | `UpdateFreezeConfig` | `emergency::update_freeze_duration()` |
| `subdao_ops` | `TransferCapToSubDAO` | `capability_vault::extract_cap()` + `store_cap()` |
| `upgrade_ops` | `ProposeUpgrade` | `capability_vault::loan_cap()` (UpgradeCap) |

Every handler follows the same pattern:
1. Accept `ExecutionRequest<P>` from `board_voting::authorize_execution()`
2. Read payload from `&Proposal<P>`
3. Call gated framework function(s) with `&req`
4. Call `proposal::consume(request)` to destroy the hot-potato

---

## 6. Privilege Escalation Prevention

- **No public constructors** for `ExecutionRequest` — only `proposal::execute()` (`public(package)`) can create one
- **Phantom type binding** — `ExecutionRequest<SetBoard>` cannot be used where `ExecutionRequest<SendCoin<T>>` is expected
- **Hot-potato enforcement** — the token _must_ be consumed in the same PTB; it cannot be stored or transferred
- **Snapshot isolation** — voting eligibility is fixed at proposal creation; later board changes don't affect in-flight proposals
- **Protected types** — `TransferFreezeAdmin` and `UnfreezeProposalType` cannot be frozen, preventing lockout
- **Cooldown tracking** — `dao.record_execution()` prevents rapid re-execution of the same proposal type
