# Armature Framework — Internal Workings

## Privilege Model Overview

The framework enforces a **proposal-gated, per-type permission model**. Every state-mutating operation on DAO objects requires one of:

- an `ExecutionRequest<P>` hot potato **for that DAO** whose permission bits include the bit the mutator names (see §9). The bits are those `P`'s type slot held when the request was minted;
- a **privileged** `ExecutionRequest<P>` (minted only by `controller::privileged_submit` for a SubDAO), which passes every bit check on that SubDAO;
- a `FreezeAdminCap` (emergency freeze/unfreeze) or `SubDAOControl` (`privileged_extract`);
- `public(package)` visibility (framework-internal only).

Holding a request for one type does **not** authorize mutations that type was never granted. Permissions are deny-by-default: a type holds no bits unless seeded (framework types, §9.1), set in a creation-time override, or granted by an 80% meta-type vote (§9.2).

The only permissionless operations are:
- **Reading** accessors on all objects
- **Depositing** into the treasury vault (`deposit`, `deposit_multicoin`)
- **Claiming** coins directly transferred to the vault address
- **Voting** (if a board member at the proposal's `snapshot_version`)
- **Deleting** an expired proposal (`proposal::delete_expired_proposal`)
- **Calling an extension's bypass entry point** (e.g. `autojoin_ops::autojoin`), which runs the extension's own authorization check before minting a bypass ticket through `ticket_from_cap` (see §7, bypass caveat)

---

## 1. ExecutionRequest<P> — The Core Gate

**Module:** `proposal`

```move
public struct ExecutionRequest<phantom P> {
    dao_id: ID,
    proposal_id: ID,
    permissions: u64, // P's slot bits when the request was minted
    privileged: bool, // true only for controller::privileged_submit
}
```

A **hot-potato** (no `drop`, `copy`, or `store`). Handlers receive it inside an `ExecutionTicket<P>` (read with `ticket_request(permit)`), and `ticket.discharge(permit)` destroys it. Both take `std::internal::Permit<P>`, which only the module defining `P` can mint, so only `P`'s handler can spend or close the ticket. The phantom `P` binds the request to a payload type; `permissions` binds it to what that type may do.

**Mint paths** — every path reads `P`'s slot on the DAO at mint time:

| Path | Function | `permissions` | `privileged` |
|------|----------|---------------|--------------|
| Two-PTB vote | `board_voting::ticket_from_vote(_readonly)` → `proposal::execute` | slot bits | false |
| Atomic single vote | `board_voting::submit_vote_execute(_readonly)` → `proposal::execute_single_vote` | slot bits | false |
| Bypass | `external_execution::ticket_from_cap(_readonly)` → `proposal::privileged_execute` | slot bits | false |
| Composite step | `composite::advance_step` → `proposal::new_ticket_composite` | the step type's slot bits | false |
| Controller override | `controller::privileged_submit` → `proposal::privileged_execute` | 0 | **true** |

Because bits are read when the request is minted (execution time, not submission time), a grant or revocation applies to the next request minted after it. A composite's steps do not pool bits: each step's ticket carries only its own type's bits, and `CompositePayload` itself holds none.

**Checks** (`proposal.move`):
- `req_permissions(req)`, `req_is_privileged(req)` — accessors.
- `req_has_permission(req, bits)` — `privileged || contains(permissions, bits)`.
- `assert_permitted(req, bits)` — aborts `proposal::EPermissionDenied` (21). Called by modules that `dao` depends on (treasury_vault, capability_vault, charter, emergency, tribe), which cannot take `&DAO`; they check the DAO id against their own object first.
- `dao::assert_permitted(dao, bits, req)` — `EDAOIdMismatch` (2) for another DAO's request, then the request check. Used by DAO mutators.
- `dao::assert_controller(dao, req)` — `EDAOIdMismatch`, then `ENotPrivileged` (24) unless the request is privileged. No bit grants it.

**Two-PTB lifecycle:**
1. Board member calls `board_voting::submit_proposal<P>()` → shared `Proposal<P>` created with the slot's config
2. Members who were on the board at `snapshot_version` call `board_voting::vote()` until quorum + threshold met → `Passed`
3. A current board member calls `board_voting::ticket_from_vote()` → the `Proposal` is deleted and an `ExecutionTicket<P>` returned
4. Handler (in `P`'s own package) calls gated mutators with `ticket.ticket_request(permit)`, taking their arguments from the payload, and then `ticket.discharge(permit)`

---

## 2. Proposal-Gated Functions by Module

Every function below that takes an `ExecutionRequest` checks the request's DAO, then its bits. `packages/armature_framework/tests/gate_tests.move` has one denial test per gated function (a request holding every bit except the required one), and `scripts/check_request_gates.py` (run in CI) fails if a `public fun` in `armature_framework/sources` takes an `ExecutionRequest` without calling `assert_permitted` / `assert_controller` and is not on its reviewed allowlist.

### 2.1 dao.move

| Function | Requires | Effect |
|----------|----------|--------|
| `set_board_governance<P>()` | `BOARD_SET` | Apply a SetBoard add/remove diff; rotates `encrypt_epoch` if anyone is removed |
| `add_board_member_governance<P>()` | `BOARD_ADD` | Add one member |
| `add_board_members_governance<P>()` | `BOARD_ADD` | Add many; skips existing members |
| `remove_board_member_governance<P>()` | `BOARD_REMOVE` | Remove one member; rotates `encrypt_epoch` |
| `remove_board_members_governance<P>()` | `BOARD_REMOVE` | Remove many atomically; rotates `encrypt_epoch` |
| `enable_proposal_type<NewType, P>()` | `TYPE_ADMIN` | Add a type slot; runs floors and grant rules (§9) |
| `disable_proposal_type<P>()` | `TYPE_ADMIN` | Remove a type slot |
| `update_proposal_config<P>()` | `TYPE_ADMIN` | Replace a slot's config; runs floors and grant rules |
| `set_execution_paused<P>()` | `PAUSE` | Pause or resume all proposal execution |
| `set_migrating<P>()` | `MIGRATE` | Transition DAO to `Migrating` (irreversible) |
| `set_controller_paused<P>()` | privileged (`assert_controller`) | Controller pause of a SubDAO |
| `clear_controller<P>()` | privileged (`assert_controller`) | Drop the controller relationship (SpinOutSubDAO) |
| `init_type_state` / `borrow_type_state_mut` / `remove_type_state<P>()` | DAO id only | Type-state keyed by the request's own `P`; no bit needed |

### 2.2 treasury_vault.move

| Function | Requires | Effect |
|----------|----------|--------|
| `withdraw<T, P>()` | `TREASURY_WITHDRAW` | Extract coin from treasury; auto-cleans zero balances |
| `withdraw_multicoin<P>()` | `TREASURY_WITHDRAW` | Extract a multicoin balance |
| `deposit<T>()`, `deposit_multicoin()` | **None (permissionless)** | Anyone can deposit |
| `claim_coin<T>()` | **None (permissionless)** | Recover coins directly transferred to vault address |

### 2.3 capability_vault.move

| Function | Requires | Effect |
|----------|----------|--------|
| `store_cap<T, P>()` | `VAULT_STORE` | Store capability object in vault |
| `borrow_cap<T, P>()` | `VAULT_BORROW` + `T` in scope | Immutable borrow of stored capability |
| `borrow_cap_mut<T, P>()` | `VAULT_BORROW` + `T` in scope | Mutable borrow (a `TreasuryCap` borrow mints) |
| `loan_cap<T, P>()` | `VAULT_BORROW` + `T` in scope | Temporary extract; returns `(T, CapLoan)` hot-potato |
| `extract_cap<T, P>()` | `VAULT_EXTRACT` | Permanently remove capability from vault |
| `create_subdao_control<P>()` | `VAULT_EXTRACT` | Create `SubDAOControl` for a parent–child relationship |
| `destroy_subdao_control<P>()` | `VAULT_EXTRACT` | Destroy `SubDAOControl`, relinquishing parent authority |
| `receive_cap<T, P>()` | `VAULT_EXTRACT` on the **sending** DAO's request | Cross-DAO receive; no receiver DAO check (source vote is the authority) |
| `receive_cap_authorized<T, Send, Recv>()` | `VAULT_EXTRACT` on sender, `VAULT_STORE` on receiver | Dual-authorized receive; asserts the vault belongs to `Recv`'s DAO |
| `borrow_external_cap<P>()` | **None** (vault must match `dao_id`) | Borrow an `ExternalExecutionCap<P>` for bypass execution |
| `privileged_extract<T>()` | `SubDAOControl` | Parent DAO reclaims capability from child vault |
| `store_cap_init<T>()` | `public(package)` | Store capability during DAO creation only |

### 2.4 charter.move

| Function | Requires | Effect |
|----------|----------|--------|
| `update_metadata<P>()` | `METADATA` | Update the DAO's metadata URI |

### 2.5 emergency.move

| Function | Requires | Effect |
|----------|----------|--------|
| `freeze_type<P>()` | `FreezeAdminCap` | Freeze type `P` for up to `max_freeze_duration_ms` |
| `unfreeze_type<P>()` | `FreezeAdminCap` | Admin-unfreeze a frozen type immediately |
| `governance_unfreeze_type<P>()` | `FREEZE` | Governance-authorized unfreeze |
| `update_freeze_duration<P>()` | `FREEZE` | Change max freeze duration for future freezes |
| `unfreeze_all<P>()` | `FREEZE` | Bulk-unfreeze all currently frozen types |
| `add_freeze_exempt_type<P>()` / `remove_freeze_exempt_type<P>()` | `FREEZE` | Edit the exempt set |

Frozen and exempt entries are keyed by the payload's canonical `TypeName` (`with_defining_ids`), the same key as the DAO's type slots. Freezing `PlaceLimitOrder<CRED>` blocks that instantiation on the atomic, bypass, composite and two-PTB paths and leaves other instantiations alone.

**Protected types** (cannot be frozen, cannot be removed from the exempt set): `armature::transfer_freeze_admin::TransferFreezeAdmin`, `armature::unfreeze_proposal_type::UnfreezeProposalType`. They are matched by Move type, so a same-named type in another package gets no exemption.

### 2.6 tribe.move

| Function | Requires | Effect |
|----------|----------|--------|
| `create_wired_subdao<P>()` | `VAULT_STORE` + `VAULT_EXTRACT` | Create a SubDAO and store its `SubDAOControl` in the parent vault |

### 2.7 board_voting.move / external_execution.move / composite.move / controller.move

These mint requests rather than consume them:

| Function | Gate | Effect |
|----------|------|--------|
| `board_voting::submit_proposal<P>()` | Board member; type enabled; EnableProposalType config ≥ 80% | Create a shared `Proposal<P>` |
| `board_voting::vote<P>()` | Member at `snapshot_version`; no double vote; voting period open | Cast vote; may transition to `Passed` |
| `board_voting::ticket_from_vote<P>()` | Current board member; type enabled, not frozen, not paused | Delete the proposal, return a ticket carrying the slot's bits |
| `board_voting::submit_vote_execute<P>()` | Board member whose single vote passes | Submit, vote and execute in one PTB |
| `external_execution::ticket_from_cap<P>()` | `&ExternalExecutionCap<P>` for this DAO (no sender check) | Bypass ticket carrying the slot's bits |
| `composite::advance_step<P>()` | Passed composite pipeline | Step ticket carrying the step type's bits |
| `controller::privileged_submit<P>()` | `&SubDAOControl` for the SubDAO | Privileged request (0 bits, passes every check on that SubDAO) |
| `proposal::delete_expired_proposal<P>()` | Voting period or execution window closed | Delete the proposal (anyone) |

---

## 3. public(package) Functions — Framework-Internal Only

These are callable only from within the `armature_framework` package and are used during DAO construction or internal orchestration:

| Module | Function | Purpose |
|--------|----------|---------|
| `governance` | `new_board()` | Construct Board governance config from init payload |
| `governance` | `assert_board_member()` | Assert address is a current board member (aborts if not) |
| `governance` | `set_board()` / `add_board_member(s)()` / `remove_board_member(s)()` | Roster changes (reached via the gated `dao` mutators) |
| `dao` | `governance_mut()` | Mutable access to governance config |
| `dao` | `record_execution()` | Track last execution timestamp for cooldown |
| `proposal` | `create()` / `record_vote()` | Create a proposal, record a vote (via `board_voting`) |
| `proposal` | `execute()` / `execute_single_vote()` / `privileged_execute()` | Mint an `ExecutionRequest` carrying the given bits |
| `proposal` | `new_execution_request()` | Factory for an unprivileged request holding **no** bits |
| `proposal` | `new_external_execution_cap()` / `destroy_external_execution_cap()` | Only `external_execution`'s bypass handlers |
| `charter` | `new()` / `share()` | Construct and share Charter during DAO creation |
| `emergency` | `new()` / `new_admin_cap()` / `share()` / `transfer_admin_cap()` | Construct and distribute emergency objects |
| `treasury_vault` | `new()` / `share()` | Construct and share TreasuryVault |
| `capability_vault` | `new()` / `share()` / `store_cap_init()` / `new_subdao_control()` | Construct, share, and seed CapabilityVault |

---

## 4. Board Member Assertions

Board membership is checked at three points:

1. **Proposal creation** — `board_voting::submit_proposal()` (and `submit_vote_execute()`) calls `dao.governance().assert_board_member(ctx.sender())`
2. **Voting** — `board_voting::vote()` requires the voter was a member at the proposal's `snapshot_version` (`was_member_at`)
3. **Proposal execution** — `proposal::execute()` calls `governance.is_board_member(executor)` and aborts with `ENotEligible` if false

Membership is the gate for *who* may act; the type's permission bits are the gate for *what* the resulting request may do. The bypass and controller paths skip membership (the cap is the authority), which is why a bypass type's bits need care (§7).

---

## 5. How Handlers Consume These Gates

Handlers for framework types live in `armature_framework/sources/handlers` (only the framework can mint their `Permit`); handlers for extension types live beside their payload types in `armature_proposals` and `armature_world_bridge`. Which types belong where is decided by `docs/package-boundaries.md`. Each type must hold the bits its handler's mutators need, or the handler aborts with `proposal::EPermissionDenied`. Framework types hold fixed bits and a fixed borrow scope (§9.1, §9.1a); the rest take theirs from the config that enabled them, as listed by `armature_proposals::type_permissions`.

| Handler Module | Payload Type | Framework Function(s) Called | Bits (`type_permissions`) |
|-----------------|-------------|------------------------------|------|
| `board_ops` (framework) | `SetBoard` | `dao::set_board_governance()` | fixed |
| `member_ops` (framework) | `AddMember`, `BatchAddMembers`, `RemoveMember`, `BatchRemoveMembers` | `dao::add/remove_board_member(s)_governance()` | fixed |
| `admin_ops` (framework) | `EnableProposalType`, `DisableProposalType`, `UpdateProposalConfig` | `dao::enable/disable_proposal_type()`, `dao::update_proposal_config()` | fixed |
| `admin_ops` (framework) | `UpdateMetadata` | `charter::update_metadata()` | fixed |
| `treasury_ops` | `SendCoin<T>`, `SendCoinToDAO<T>`, `SendSmallPayment<T>`, `SendBatchMulticoinTo{Address,DAO}` | `treasury_vault::withdraw()` / `withdraw_multicoin()` (+ `deposit`) | `treasury_spend()` = TREASURY_WITHDRAW |
| `currency_ops` | `AdoptCurrency<T>` | `capability_vault::store_cap()` | `adopt_currency()` = VAULT_STORE |
| `currency_ops` | `MintCoin<T>`, `MintAllowance<T>` | `capability_vault::borrow_cap_mut()` | `mint()` = VAULT_BORROW, scope `currency_scope<T>()` = [`TreasuryCap<T>`] |
| `configure_mint_allowance` | `ConfigureMintAllowance<T>` | own type-state (minter allowlist read by `currency_ops::mint_allowance_bypass`) | none |
| `currency_ops` | `BurnCoin<T>` | `treasury_vault::withdraw()` + `borrow_cap_mut()` | `burn_coin()` = TREASURY_WITHDRAW + VAULT_BORROW, scope [`TreasuryCap<T>`] |
| `currency_ops` | `ReturnCurrencyCap<T>` | `capability_vault::extract_cap()` | `return_currency_cap()` = VAULT_EXTRACT |
| `freeze_ops` (framework) | `TransferFreezeAdmin` | `emergency::unfreeze_all()` | fixed |
| `freeze_ops` (framework) | `UnfreezeProposalType` | `emergency::governance_unfreeze_type()` | fixed |
| `freeze_ops` (framework) | `UpdateFreezeConfig`, `UpdateFreezeExemptTypes` | `emergency::update_freeze_duration()`, `add/remove_freeze_exempt_type()` | fixed |
| `subdao_ops` | `TransferCapToSubDAO` | `extract_cap()` + `receive_cap()` | `transfer_cap_to_subdao()` = VAULT_EXTRACT |
| `subdao_ops` | `ReclaimCapFromSubDAO` | `loan_cap()` + `privileged_extract()` + `store_cap()` | `reclaim_cap_from_subdao()` = VAULT_BORROW + VAULT_STORE, scope `subdao_control_scope()` = [`SubDAOControl`] |
| `subdao_ops` | `PauseSubDAOExecution`, `UnpauseSubDAOExecution`, `ControllerBatch{Add,Remove}Members` | `loan_cap()` (SubDAOControl), then SubDAO mutators on a privileged request | `subdao_control()` = VAULT_BORROW, scope [`SubDAOControl`] |
| `lifecycle_ops` (framework) | `CreateSubDAO`, `SpawnDAO`, `SpinOutSubDAO`, `TransferAssets` | vault / `set_migrating` / controller calls | fixed |
| `upgrade_ops` | `ProposeUpgrade` | `capability_vault::loan_cap()` (UpgradeCap) | `propose_upgrade()` = VAULT_BORROW, scope `propose_upgrade_scope()` = [`UpgradeCap`] |

Every handler follows the same pattern:
1. Accept `ExecutionTicket<P>` from a mint path (§1)
2. Assert the target objects belong to `ticket.ticket_dao_id()`
3. Read the payload with `ticket.ticket_payload()` and call gated framework function(s) with `ticket.ticket_request(permit)`, where `permit` is `internal::permit()` in the module defining `P` (or that module's `public(package) fun permit()`)
4. Call `ticket.discharge(permit)` (or `discharge_returning_payload(permit)`) to destroy the hot potato

Controller-side handlers hold two requests at once: the controller DAO's own (which must carry VAULT_BORROW to loan the `SubDAOControl`) and the SubDAO's privileged request from `privileged_submit`.

---

## 6. Cross-DAO Validation

An `ExecutionRequest<P>` carries a `dao_id`. To prevent "shopping" — using a request from DAO-A to mutate DAO-B — every framework mutator asserts the request's DAO against its target **before** checking bits:

| Module | Check | Error |
|--------|-------|-------|
| `dao` | `self.id() == req.req_dao_id()` (in `dao::assert_permitted` / `assert_controller`) | `EDAOIdMismatch` (2) |
| `treasury_vault` | `self.dao_id == req.req_dao_id()` | `EDAOIdMismatch` (1) |
| `capability_vault` | `self.dao_id == req.req_dao_id()` | `EDAOIdMismatch` (3) |
| `charter` | `self.dao_id == req.req_dao_id()` | `EDaoMismatch` (0) |
| `emergency` | `self.dao_id == req.req_dao_id()` | `EDAOMismatch` (0) |

Exceptions, by design: `capability_vault::receive_cap` does not check the receiving vault's DAO (the sending DAO's VAULT_EXTRACT request is the authority; third-party cross-DAO handlers should use `receive_cap_authorized`), and `tribe::create_wired_subdao` relies on `store_cap`'s vault check. Handlers in `armature_proposals` additionally assert their target objects' DAO against the ticket.

Tickets are closed with `proposal::discharge()`, which checks a vote-path ticket's request against the proposal it came from (`ERequestMismatch`, 13). `proposal::consume()` is `public(package)`; `controller::privileged_consume()` checks the request's DAO against the `SubDAOControl`.

---

## 7. Privilege Escalation Prevention

- **No public constructors** for `ExecutionRequest` — only framework `public(package)` mint functions (§1) create one
- **Hot-potato enforcement** — the token _must_ be consumed in the same PTB; it cannot be stored or transferred
- **Per-type permission bits** — a request authorizes only the mutations its type's slot held bits for when it was minted; every framework mutator checks, and CI fails on an ungated one (§2)
- **Handler authority** — `ticket_request`, `discharge` and `ticket_from_cap` take `std::internal::Permit<P>`, so only `P`'s own module can mint, spend or close its tickets, and it spends the request with arguments read from the payload. CI fails if any of them drops the permit (`scripts/check_request_gates.py`)
- **Floors in `dao`** — every stored config must meet the type's own floor and `permission_floor(bits)` (80% for TYPE_ADMIN, MIGRATE, TREASURY_WITHDRAW, VAULT_BORROW, VAULT_EXTRACT). `assert_config_floors` runs on `enable_proposal_type`, `update_proposal_config` and creation-time overrides, so no handler can skip it (`EThresholdBelowMinimum`, 12)
- **Fixed framework bits** — framework types always hold exactly `dao::framework_permissions` (`EFixedPermissions`, 23)
- **Controlled grants** — only EnableProposalType, EnableBypassType and UpdateProposalConfig (all 80%) or a privileged request may change a type's bits (`EPermissionChangeNotAllowed`, 19; `EGrantFloorNotMet`, 21); grants cannot ride in a composite (`EUseTypedStep`, `EGrantInComposite`)
- **Snapshot isolation** — voting eligibility is fixed at the proposal's `snapshot_version`; later board changes don't affect in-flight proposals
- **Protected types** — `TransferFreezeAdmin` and `UnfreezeProposalType` cannot be frozen, preventing lockout
- **Cooldown tracking** — `dao.record_execution()` prevents rapid re-execution of the same proposal type

**Bypass caveat.** `capability_vault::borrow_external_cap` is public and `external_execution::ticket_from_cap` does not check the sender, but it does take `Permit<P>`: only `P`'s own module can mint a bypass ticket, so the extension's authorization check (character ownership, token balance, an allowlist in type-state) runs there. The cap in the vault is the DAO's opt-in, not a bearer credential. `MintAllowance<T>` is minted only by `currency_ops::mint_allowance_bypass`, which checks the sender against the `ConfigureMintAllowance<T>` allowlist and per-call cap (ARMATURE-21 / ARMATURE-31). Grant a bypass type only the bits and scope its handler needs, and never a bit in `bypass_forbidden_bits` (§9.1b). Placement rules for types and handlers: `docs/package-boundaries.md`.

---

## 8. Intra-DAO Threshold Bypass Audit (Phantom Type `P` Safety)

### 8.1 Attack Vector

Within the **same DAO**, can a board member use a proposal type with a low approval threshold to execute an operation that should require a high threshold?

For example: If `SetBoard` requires 80% threshold but `UpdateMetadata` requires 50%, can a board member create an `ExecutionRequest<UpdateMetadata>` and use it to call `dao.set_board_governance<UpdateMetadata>()`?

### 8.2 Finding: Was exploitable — NOW FIXED

The phantom type `P` on `ExecutionRequest<P>` alone did not provide adequate security. The following issues were identified and resolved:

1. ~~**Framework mutators accept any `P`**: Functions like `set_board_governance<P>()`, `withdraw<T, P>()`, etc. are `public` with unconstrained generic `P`. An `ExecutionRequest<AnyType>` works for every operation.~~ ✅ **Fixed (ROAD-39)**: mutators are still generic over `P`, but each checks the request's permission bits, so `ExecutionRequest<UpdateMetadata>` (METADATA only) aborts `EPermissionDenied` in `set_board_governance`.

2. ~~**`proposal::create()` is `public`** and accepts a caller-supplied `ProposalConfig` parameter. A third-party package can call it directly with arbitrarily low quorum/threshold, bypassing the DAO's registered configs entirely.~~ ✅ **Fixed**: `create()` is now `public(package)`.

3. ~~**`proposal::consume()` is `public`** — any package can destroy the hot potato after directly calling framework mutators, bypassing the typed handlers in `armature_proposals`.~~ ✅ **Fixed**: `consume()` is now `public(package)`. External handlers close tickets with `discharge()`.

4. ~~**`type_key` (string) and `P` (Move type) are decoupled**~~ ✅ **Fixed**: type slots are keyed by `P`'s canonical `TypeName`; the display key is looked up from the slot.

### 8.3 Attack Scenario (historical)

A **single malicious board member** could have taken full control:

> **⚠️ This attack is now blocked** three times over: `proposal::create()` and `proposal::consume()` are `public(package)`, and even a request obtained legitimately for a low-threshold type carries only that type's bits.

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

**Step 2** — Vote + execute + hijack in one PTB (**BLOCKED — the request carries no BOARD_SET**):
```move
public fun hijack(dao: &mut DAO, ticket: ExecutionTicket<Dummy>, ctx: &TxContext) {
    // Dummy was enabled with no bits, so its request carries 0.
    dao.set_board_governance(vector[ctx.sender()], vector[], ticket.ticket_request(internal::permit()));
    // ERROR: proposal::EPermissionDenied — Dummy does not hold BOARD_SET
    ticket.discharge(internal::permit());
}
```

### 8.4 What IS safe

| Mechanism | Status |
|-----------|--------|
| `proposal::execute()` / `privileged_execute()` / `new_execution_request()` | `public(package)` ✓ |
| `board_voting::ticket_from_vote()` | Validates dao_id, type enabled, not frozen, board membership ✓ |
| Framework mutators | Check DAO id and permission bits ✓ |
| `ticket_request` / `discharge` / `ticket_from_cap` | Require `Permit<P>`: only `P`'s module can mint, spend or close a ticket ✓ |
| Attacker must be a board member | Required for voting and vote-path execution ✓ (not for bypass — see §7) |

### 8.5 Vulnerability Summary

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | **CRITICAL** | `proposal::create()` was `public` — accepted caller-supplied `ProposalConfig`, bypassing DAO's stored governance rules | ✅ Fixed — now `public(package)` |
| 2 | **CRITICAL** | Framework mutators are generic over `P` — `ExecutionRequest<AnyType>` unlocks every operation | ✅ Fixed (ROAD-39) — per-type permission bits checked by every mutator |
| 3 | **HIGH** | `proposal::consume()` was `public` — any package could destroy the hot potato, bypassing typed handlers | ✅ Fixed — now `public(package)`; tickets close with `discharge()` |
| 4 | **MEDIUM** | `proposal::create()` does not validate proposer is a board member (only `submit_proposal` does) | ✅ Fixed — `create()` is `public(package)`, only reachable via `board_voting` |
| 5 | **MEDIUM** | Execution did not check if the proposal type is frozen or still enabled | ✅ Fixed — `ticket_from_vote` asserts the type is enabled and `assert_not_frozen<P>` |
| 6 | **HIGH** | Bypass type's bits are usable by any caller who can build its payload; `MintAllowance` bypass is open minting | ✅ Fixed — `ticket_from_cap` requires `Permit<P>`; only `P`'s module can mint a bypass ticket |
| 7 | **CRITICAL** | A ticket's request is spendable by whoever holds the ticket, with arguments of their choosing: an autojoin player adds any addresses under `BOARD_ADD`; the executor of an approved payment withdraws the whole treasury under `TREASURY_WITHDRAW`; `TransferAssets` hands the withdrawn coins and caps to the executor | ✅ Fixed — `ticket_request` / `discharge` require `Permit<P>`; framework-type handlers moved into the framework; `TransferAssets` moves each listed asset itself |
| 8 | **HIGH** | Handler trusted caller-chosen objects: `execute_mint_coin` / `execute_mint_allowance` deposited into any treasury passed; `execute_propose_upgrade` returned the raw `UpgradeCap` | ✅ Fixed — treasury checked against the request's DAO; the cap stays in a `PendingUpgrade` hot potato |

### 8.6 Applied Fixes

**Fix 1 (blocks the attack)**: `proposal::create()` changed to `public(package) fun`. Forces all proposal creation through `board_voting`, which validates the type is enabled and uses the DAO's stored `ProposalConfig`.

**Fix 2 (defense-in-depth)**: `proposal::consume()` changed to `public(package) fun`. Handlers receive an `ExecutionTicket<P>` and close it with `discharge()`, which checks a vote-path ticket's request against its proposal (`ERequestMismatch`, 13).

**Fix 3 (ROAD-39)**: per-type permission bits (§9). `ExecutionRequest` carries the bits of its type's slot; every mutator checks them; floors live in `dao`; framework types have fixed bits; only the 80% meta-types may grant.

## 9. Permission Bits (ROAD-39)

Each proposal type's `ProposalConfig.permissions` names the DAO-wide mutations a request of that type may perform. The request carries the bits its slot held when it was minted, and every mutator checks them (`dao::assert_permitted` for DAO mutators, `proposal::assert_permitted` for the vault, charter, emergency and tribe modules; see §2). Bits are defined in `armature::permissions`. A config holding any bit marked 80% needs `approval_threshold >= 8000` (`dao::permission_floor`), on every path that stores a config.

| Bit | Floor | Guards |
|---|---|---|
| `BOARD_ADD` | — | add board members |
| `BOARD_REMOVE` | — | remove board members |
| `BOARD_SET` | — | apply a SetBoard diff |
| `TYPE_ADMIN` | 80% | enable, disable, reconfigure proposal types |
| `PAUSE` | — | pause or resume execution |
| `MIGRATE` | 80% | move the DAO to Migrating |
| `METADATA` | — | charter metadata |
| `TREASURY_WITHDRAW` | 80% | withdraw from the TreasuryVault |
| `VAULT_STORE` | — | store a capability |
| `VAULT_BORROW` | 80% | borrow or loan a capability whose type is in the config's `borrow_scope` (a mutable TreasuryCap borrow mints; a loaned SubDAOControl controls the SubDAO) |
| `VAULT_EXTRACT` | 80% | extract a capability; create or destroy a SubDAOControl |
| `FREEZE` | — | governance changes to the EmergencyFreeze |

### 9.1 Framework types: fixed bits

Framework payload types always hold exactly these bits (`dao::framework_permissions`), whatever config enabled them; `UpdateProposalConfig` cannot change them (`EFixedPermissions`). Default slots are seeded with them at DAO creation, with thresholds raised to the floor they need.

| Type | Bits | Why |
|---|---|---|
| SetBoard | BOARD_SET | applies an add/remove diff |
| AddMember, BatchAddMembers | BOARD_ADD | adds members |
| RemoveMember, BatchRemoveMembers | BOARD_REMOVE | removes members |
| UpdateMetadata | METADATA | `charter::update_metadata` |
| EnableProposalType, DisableProposalType, UpdateProposalConfig | TYPE_ADMIN | type registry |
| EnableBypassType | TYPE_ADMIN, VAULT_STORE | enables the type and stores its ExternalExecutionCap |
| DisableBypassType | TYPE_ADMIN, VAULT_EXTRACT | extracts the cap to destroy it, disables the type |
| TransferFreezeAdmin, UnfreezeProposalType, UpdateFreezeConfig, UpdateFreezeExemptTypes | FREEZE | `unfreeze_all`, `governance_unfreeze_type`, `update_freeze_duration`, `add/remove_freeze_exempt_type` |
| SpawnDAO | MIGRATE | `set_migrating` |
| CreateSubDAO | VAULT_STORE, VAULT_EXTRACT | creates and stores a SubDAOControl, stores the SubDAO's FreezeAdminCap |
| SpinOutSubDAO | VAULT_BORROW (scope: SubDAOControl), VAULT_EXTRACT | loans the SubDAOControl, extracts the FreezeAdminCap, destroys the control |
| TransferAssets | TREASURY_WITHDRAW, VAULT_EXTRACT | moves coins and caps to the successor |
| CompositePayload | none | its ticket is consumed by `begin_pipeline` |

Other types (e.g. `armature_proposals`' `SendCoin<T>`) hold the bits in the config that enabled them: a `ProposalTypeInit` override at creation, or an `EnableProposalType` / `EnableBypassType` payload. Both default to none.

### 9.1a Borrow scope

`ProposalConfig.borrow_scope` (a `vector<TypeName>`, `with_borrow_scope`) names the capability types a VAULT_BORROW request may borrow or loan. Deny-by-default: empty borrows nothing. `ExecutionRequest.borrow_scope` copies it at mint time on every path (two-PTB, atomic, bypass, composite step; a controller request carries none and is privileged). `capability_vault::borrow_cap`, `borrow_cap_mut` and `loan_cap` call `proposal::assert_may_borrow(req, &type_name::with_defining_ids<T>())` after the bit check (`EBorrowScopeDenied`, 22); a privileged request passes. Framework types hold a fixed scope (`dao::framework_borrow_scope`: SpinOutSubDAO → [SubDAOControl], all others empty), enforced with the fixed bits (`EFixedPermissions`). A scope change is a grant: `assert_may_change_permissions` treats it as adding VAULT_BORROW, so only the three meta-types (or a privileged request) may set or change it, and the composite typed steps refuse it (`EGrantInComposite`). `UpdateProposalConfig` carries it as `Option<vector<TypeName>>` (`with_borrow_scope`). Extension packages publish scopes beside bits (`armature_proposals::type_permissions::*_scope`).

### 9.1b Bypass-safe bits

`external_execution::bypass_forbidden_bits()` = TYPE_ADMIN | MIGRATE | VAULT_EXTRACT | FREEZE. `execute_enable_bypass_type` refuses a config holding any of them, and `ticket_from_cap_core` refuses to mint for a slot holding any of them (`EBypassForbiddenBits`, 15), so a later grant via `UpdateProposalConfig` cannot open a no-vote path to the authority graph either.

### 9.2 Who may change bits

Only a request of type EnableProposalType, EnableBypassType or UpdateProposalConfig may change a non-framework type's bits, or a privileged (controller) request. All three meta-types sit at the 80% floor, so every grant is approved by an 80% vote. Grants are standalone-only: `composite::add_step` refuses EnableProposalType and UpdateProposalConfig steps, and the typed `add_enable_proposal_type_step` / `add_update_proposal_config_step` refuse any step that would change bits.
