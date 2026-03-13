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

## 6. Cross-DAO Validation Audit

An `ExecutionRequest<P>` carries a `dao_id` field. To prevent "shopping" — using a request obtained from DAO-A to authorize mutations on DAO-B — every consumer **must** assert `req.req_dao_id() == target.dao_id()`. The following audit covers every function that accepts an `ExecutionRequest<P>`.

> **`proposal::consume()`** performs **zero validation** — it simply destructs the token. All DAO-binding checks must happen _before_ consume is called.

### 6.1 Functions WITH dao_id validation (safe)

| Module | Function | Validation |
|--------|----------|------------|
| `charter` | `update_metadata<P>()` | `self.dao_id == req.req_dao_id()` |
| `emergency` | `governance_unfreeze_type<P>()` | `self.dao_id == _req.req_dao_id()` |
| `emergency` | `update_freeze_duration<P>()` | `self.dao_id == _req.req_dao_id()` |
| `emergency` | `unfreeze_all<P>()` | `self.dao_id == _req.req_dao_id()` |
| `board_voting` | `authorize_execution<P>()` | `prop.dao_id() == dao.id()` (at creation) |

Consumer-side checks in `armature_proposals`:

| Module | Function | Validation |
|--------|----------|------------|
| `admin_ops` | `execute_disable_proposal_type()` | `dao.id() == request.req_dao_id()` |
| `admin_ops` | `execute_enable_proposal_type()` | `dao.id() == request.req_dao_id()` |
| `admin_ops` | `execute_update_proposal_config()` | `dao.id() == request.req_dao_id()` |
| `admin_ops` | `execute_update_metadata()` | `charter.dao_id() == request.req_dao_id()` |
| `treasury_ops` | `execute_send_coin<T>()` | `vault.dao_id() == request.req_dao_id()` |
| `treasury_ops` | `execute_send_coin_to_dao<T>()` | `source_vault.dao_id() == request.req_dao_id()` |
| `security_ops` | `execute_transfer_freeze_admin()` | `freeze.dao_id() == request.req_dao_id()` + cap cross-check |
| `security_ops` | `execute_unfreeze_proposal_type()` | Delegated to `emergency::governance_unfreeze_type()` |
| `security_ops` | `execute_update_freeze_config()` | Delegated to `emergency::update_freeze_duration()` |
| `subdao_ops` | `execute_transfer_cap<T>()` | `source_vault.dao_id() == request.req_dao_id()` |
| `subdao_ops` | `execute_reclaim_cap<T>()` | `controller_vault.dao_id() == request.req_dao_id()` |
| `subdao_ops` | `execute_create_subdao()` | `vault.dao_id() == request.req_dao_id()` |
| `subdao_ops` | `execute_pause_subdao_execution()` | `dao.id() == request.req_dao_id()` |
| `subdao_ops` | `execute_unpause_subdao_execution()` | `dao.id() == request.req_dao_id()` |
| `subdao_ops` | `execute_spawn_dao()` | `dao.id() == request.req_dao_id()` |
| `subdao_ops` | `execute_spin_out_subdao()` | `vault.dao_id() == request.req_dao_id()` |
| `subdao_ops` | `execute_transfer_assets()` | `source_treasury.dao_id() == request.req_dao_id()` |
| `upgrade_ops` | `execute_propose_upgrade()` | `vault.dao_id() == request.req_dao_id()` |

### 6.2 Functions WITH dao_id validation at framework layer (fixed)

These framework functions now assert `req.req_dao_id()` against the target object's `dao_id` directly, providing defense-in-depth independent of the caller:

| Module | Function | Validation |
|--------|----------|------------|
| `dao` | `set_board_governance<P>()` | `self.id() == req.req_dao_id()` |
| `dao` | `enable_proposal_type<P>()` | `self.id() == req.req_dao_id()` |
| `dao` | `disable_proposal_type<P>()` | `self.id() == req.req_dao_id()` |
| `dao` | `update_proposal_config<P>()` | `self.id() == req.req_dao_id()` |
| `dao` | `set_execution_paused<P>()` | `self.id() == req.req_dao_id()` |
| `dao` | `set_migrating<P>()` | `self.id() == req.req_dao_id()` |
| `treasury_vault` | `withdraw<T, P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `store_cap<T, P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `borrow_cap<T, P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `borrow_cap_mut<T, P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `loan_cap<T, P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `extract_cap<T, P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `create_subdao_control<P>()` | `self.dao_id == req.req_dao_id()` |
| `capability_vault` | `destroy_subdao_control<P>()` | `self.dao_id == req.req_dao_id()` |

### 6.3 Fixed: `board_ops::execute_set_board()`

This handler now validates `dao.id() == request.req_dao_id()` before mutating the board:

```move
public fun execute_set_board(
    dao: &mut DAO,
    proposal: &Proposal<SetBoard>,
    request: ExecutionRequest<SetBoard>,
) {
    assert!(dao.id() == request.req_dao_id(), EDaoMismatch);
    let payload = proposal.payload();
    dao.set_board_governance(*payload.new_members(), &request);
    // ...
    proposal::consume(request);
}
```

### 6.4 Implementation (completed)

All framework-layer `ExecutionRequest`-gated functions now independently assert the `dao_id` match (defense-in-depth). Error constants added:

| Module | Error Constant | Code |
|--------|---------------|------|
| `dao` | `EDAOIdMismatch` | 2 |
| `treasury_vault` | `EDAOIdMismatch` | 1 |
| `capability_vault` | `EDAOIdMismatch` | 3 |
| `board_ops` | `EDaoMismatch` | 0 |

---

## 7. Privilege Escalation Prevention

- **No public constructors** for `ExecutionRequest` — only `proposal::execute()` (`public(package)`) can create one
- **Hot-potato enforcement** — the token _must_ be consumed in the same PTB; it cannot be stored or transferred
- **Snapshot isolation** — voting eligibility is fixed at proposal creation; later board changes don't affect in-flight proposals
- **Protected types** — `TransferFreezeAdmin` and `UnfreezeProposalType` cannot be frozen, preventing lockout
- **Cooldown tracking** — `dao.record_execution()` prevents rapid re-execution of the same proposal type

---

## 8. Intra-DAO Threshold Bypass Audit (Phantom Type `P` Safety)

### 8.1 Attack Vector

Within the **same DAO**, can a board member use a proposal type with a low approval threshold to execute an operation that should require a high threshold?

For example: If `SetBoard` requires 80% threshold but `UpdateMetadata` requires 50%, can a board member create an `ExecutionRequest<UpdateMetadata>` and use it to call `dao.set_board_governance<UpdateMetadata>()`?

### 8.2 Finding: Was exploitable — NOW FIXED

The phantom type `P` on `ExecutionRequest<P>` alone did not provide adequate security. The following issues were identified and resolved:

1. **Framework mutators accept any `P`**: Functions like `set_board_governance<P>()`, `withdraw<T, P>()`, etc. are `public` with unconstrained generic `P`. An `ExecutionRequest<AnyType>` works for every operation. *(Accepted risk — entry points now sealed.)*

2. ~~**`proposal::create()` is `public`** and accepts a caller-supplied `ProposalConfig` parameter. A third-party package can call it directly with arbitrarily low quorum/threshold, bypassing the DAO's registered configs entirely.~~ ✅ **Fixed**: `create()` is now `public(package)`.

3. ~~**`proposal::consume()` is `public`** — any package can destroy the hot potato after directly calling framework mutators, bypassing the typed handlers in `armature_proposals`.~~ ✅ **Fixed**: `consume()` is now `public(package)`. External callers use `finalize()` which validates dao_id, proposal_id, and executed status.

4. **`type_key` (string) and `P` (Move type) are decoupled** — there is no on-chain binding between them.

### 8.3 Attack Scenario

A **single malicious board member** could have taken full control:

> **⚠️ This attack is now blocked.** `proposal::create()` is `public(package)`, so Step 1 cannot be executed from a third-party package. `proposal::consume()` is `public(package)`, so Step 2's final line also fails from outside the framework.

**Step 1** — Third-party package creates a poisoned proposal (**BLOCKED — `create()` is `public(package)`**):
```move
public struct Dummy has store { x: u8 }

public fun create_poison(dao: &DAO, clock: &Clock, ctx: &mut TxContext) {
    let config = proposal::new_config(1, 5000, 0, 0, 0, 0); // quorum=0.01%, threshold=50%
    proposal::create<Dummy>(  // ERROR: public(package) — not callable from here
        dao.id(),
        b"x".to_ascii_string(),
        ctx.sender(),
        b"".to_string(),
        Dummy { x: 0 },
        config,              // custom config, not from DAO
        dao.governance(),    // public accessor
        clock,
        ctx,
    );
}
```

**Step 2** — Vote + execute + hijack in one PTB (**BLOCKED — `consume()` is `public(package)`**):
```move
public fun hijack(dao: &mut DAO, prop: &mut Proposal<Dummy>, clock: &Clock, ctx: &TxContext) {
    prop.vote(true, clock, ctx);  // passes immediately with quorum=1
    let req = board_voting::authorize_execution(dao, prop, clock, ctx);
    dao.set_board_governance(vector[ctx.sender()], &req);  // works — P is generic
    proposal::consume(req);  // ERROR: public(package) — not callable from here
    // proposal::finalize(req, prop) also fails: prop has wrong type, and Dummy is not store+key
}
```

### 8.4 What IS safe

| Mechanism | Status |
|-----------|--------|
| `proposal::execute()` | `public(package)` ✓ — cannot be called externally |
| `new_execution_request()` | `public(package)` ✓ |
| `board_voting::authorize_execution()` | Validates dao_id, checks board membership ✓ |
| Attacker must be a board member | Required for both voting and execution ✓ |

### 8.5 Vulnerability Summary

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | **CRITICAL** | `proposal::create()` was `public` — accepted caller-supplied `ProposalConfig`, bypassing DAO's stored governance rules | ✅ Fixed — now `public(package)` |
| 2 | **CRITICAL** | Framework mutators are generic over `P` — `ExecutionRequest<AnyType>` unlocks every operation | Accepted risk — entry points sealed |
| 3 | **HIGH** | `proposal::consume()` was `public` — any package could destroy the hot potato, bypassing typed handlers | ✅ Fixed — now `public(package)` with `finalize()` validation |
| 4 | **MEDIUM** | `proposal::create()` does not validate proposer is a board member (only `submit_proposal` does) | ✅ Fixed — `create()` is `public(package)`, only reachable via `submit_proposal()` |
| 5 | **MEDIUM** | `authorize_execution()` does not check if the proposal type is frozen or still enabled | Open |

### 8.6 Applied Fixes

**Fix 1 (blocks the attack)**: `proposal::create()` changed to `public(package) fun`. Forces all proposal creation through `board_voting::submit_proposal()`, which validates the type_key is enabled and uses the DAO's stored `ProposalConfig`.

**Fix 2 (defense-in-depth)**: `proposal::consume()` changed to `public(package) fun`. Added `public fun finalize<P: store>(req: ExecutionRequest<P>, proposal: &Proposal<P>)` as the validated public entry point. `finalize()` asserts: (1) `req.dao_id == proposal.dao_id`, (2) `req.proposal_id == object::id(proposal)`, (3) `proposal.status.is_executed()`. All 19 handler call sites in `armature_proposals` migrated from `proposal::consume(request)` to `proposal::finalize(request, proposal)`. New error constants: `ERequestMismatch` (13), `ENotExecuted` (14).

**Fix 3 (open — additional hardening for `authorize_execution`)**: Check that the proposal's `type_key` is still enabled and not frozen before authorizing execution.
