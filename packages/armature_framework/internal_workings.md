# Armature Framework — Internal Workings

## Privilege Model Overview

The framework enforces a **proposal-gated, per-type permission model**. Every state-mutating operation on OU objects requires one of:

- an `ExecutionRequest<P>` hot potato **for that OU** whose permission bits include the bit the mutator names (see §9). The bits are those `P`'s type slot held when the request was minted;
- a **privileged** `ExecutionRequest<P>` (minted only by `controller::privileged_submit` for a SubOU), which passes every bit check on that SubOU;
- a `FreezeAdminCap` (emergency freeze/unfreeze) or the SubOU's registered `SubOUControl` (`controller::privileged_extract`);
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
    ou_id: ID,
    proposal_id: ID,
    permissions: u64, // P's slot bits when the request was minted
    privileged: bool, // true only for controller::privileged_submit
}
```

A **hot-potato** (no `drop`, `copy`, or `store`). Handlers receive it inside an `ExecutionTicket<P>` (read with `ticket_request(permit)`), and `ticket.discharge(permit)` destroys it. Both take `std::internal::Permit<P>`, which only the module defining `P` can mint, so only `P`'s handler can spend or close the ticket. The phantom `P` binds the request to a payload type; `permissions` binds it to what that type may do.

**Mint paths** — every path reads `P`'s slot on the OU at mint time:

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
- `assert_permitted(req, bits)` — aborts `proposal::EPermissionDenied` (21). Called by modules that `ou` depends on (treasury_vault, capability_vault, charter, emergency, tribe), which cannot take `&OU`; they check the OU id against their own object first.
- `ou::assert_permitted(ou, bits, req)` — `EOUIdMismatch` (2) for another OU's request, then the request check. Used by OU mutators.
- `ou::assert_controller(ou, req)` — `EOUIdMismatch`, then `ENotPrivileged` (24) unless the request is privileged. No bit grants it.

**Two-PTB lifecycle:**
1. Board member calls `board_voting::submit_proposal<P>()` → shared `Proposal<P>` created with the slot's config
2. Members who were on the board at `snapshot_version` call `board_voting::vote()` until quorum + threshold met → `Passed`
3. A current board member calls `board_voting::ticket_from_vote()` → the `Proposal` is deleted and an `ExecutionTicket<P>` returned
4. Handler (in `P`'s own package) calls gated mutators with `ticket.ticket_request(permit)`, taking their arguments from the payload, and then `ticket.discharge(permit)`

---

## 2. Proposal-Gated Functions by Module

Every function below that takes an `ExecutionRequest` checks the request's OU, then its bits. `packages/armature_framework/tests/gate_tests.move` has one denial test per gated function (a request holding every bit except the required one), and `scripts/check_request_gates.py` (run in CI) fails if a `public fun` in `armature_framework/sources` takes an `ExecutionRequest` without calling `assert_permitted` / `assert_controller` and is not on its reviewed allowlist.

### 2.1 ou.move

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
| `set_migrating<P>()` | `MIGRATE` | Transition OU to `Migrating` (irreversible) |
| `set_controller_paused<P>()` | privileged (`assert_controller`) | Controller pause of a SubOU |
| `clear_controller<P>()` | privileged (`assert_controller`) | Drop the controller relationship (SpinOutSubOU) |
| `init_type_state` / `borrow_type_state_mut` / `remove_type_state<P>()` | OU id only | Type-state keyed by the request's own `P`; no bit needed |

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
| `create_subou_control<P>()` | `VAULT_EXTRACT`; `public(package)` | Create `SubOUControl` for a parent–child relationship (only caller: `CreateSubOU`, for the SubOU it just created) |
| `destroy_subou_control<P>()` | `VAULT_EXTRACT` | Destroy `SubOUControl`, relinquishing parent authority |
| `receive_cap<T, P>()` | `VAULT_EXTRACT` on the **sending** OU's request; `public(package)` | Cross-OU receive; no receiver OU check, so each caller ties sender to vault (SpinOutSubOU's own SubOU, TransferAssets' voted target, `controller::receive_cap_from_controller`) |
| `receive_cap_authorized<T, Send, Recv>()` | `VAULT_EXTRACT` on sender, `VAULT_STORE` on receiver | Dual-authorized receive; asserts the vault belongs to `Recv`'s OU |
| `borrow_external_cap<P>()` | **None** (vault must match `ou_id`) | Borrow an `ExternalExecutionCap<P>` for bypass execution |
| `privileged_extract<T>()` | `SubOUControl` bound to the vault's OU; `public(package)` | Parent OU reclaims capability from child vault; reached through `controller::privileged_extract` |
| `controller::privileged_extract<T>()` | The SubOU's registered `&SubOUControl`; vault is the SubOU's | Extract a cap from the SubOU's vault (controller reclaim) |
| `controller::receive_cap_from_controller<T, P>()` | `VAULT_EXTRACT` on `req`; `controller_vault` is `req`'s OU's and holds the SubOU's registered control | Push a cap into the SubOU's vault from its controller |
| `store_cap_init<T>()` | `public(package)` | Store capability during OU creation only |

### 2.4 charter.move

| Function | Requires | Effect |
|----------|----------|--------|
| `update_metadata<P>()` | `METADATA` | Update the OU's metadata URI |

### 2.5 emergency.move

| Function | Requires | Effect |
|----------|----------|--------|
| `freeze_type<P>()` | `FreezeAdminCap` | Freeze type `P` for up to `max_freeze_duration_ms` |
| `unfreeze_type<P>()` | `FreezeAdminCap` | Admin-unfreeze a frozen type immediately |
| `governance_unfreeze_type<P>()` | `FREEZE` | Governance-authorized unfreeze |
| `update_freeze_duration<P>()` | `FREEZE` | Change max freeze duration for future freezes |
| `unfreeze_all<P>()` | `FREEZE` | Bulk-unfreeze all currently frozen types |
| `add_freeze_exempt_type<P>()` / `remove_freeze_exempt_type<P>()` | `FREEZE` | Edit the exempt set |

Frozen and exempt entries are keyed by the payload's canonical `TypeName` (`with_defining_ids`), the same key as the OU's type slots. Freezing `PlaceLimitOrder<CRED>` blocks that instantiation on the atomic, bypass, composite and two-PTB paths and leaves other instantiations alone.

**Protected types** (cannot be frozen, cannot be removed from the exempt set): `armature::transfer_freeze_admin::TransferFreezeAdmin`, `armature::unfreeze_proposal_type::UnfreezeProposalType`. They are matched by Move type, so a same-named type in another package gets no exemption.

### 2.6 tribe.move

| Function | Requires | Effect |
|----------|----------|--------|
| `create_wired_subou<P>()` | `VAULT_STORE` + `VAULT_EXTRACT` | Create a SubOU and store its `SubOUControl` in the parent vault |

### 2.7 board_voting.move / external_execution.move / composite.move / controller.move

These mint requests rather than consume them:

| Function | Gate | Effect |
|----------|------|--------|
| `board_voting::submit_proposal<P>()` | Board member; type enabled; EnableProposalType config ≥ 80% | Create a shared `Proposal<P>` |
| `board_voting::vote<P>()` | Member at `snapshot_version`; no double vote; voting period open | Cast vote; may transition to `Passed` |
| `board_voting::ticket_from_vote<P>()` | Current board member; type enabled, not frozen, not paused | Delete the proposal, return a ticket carrying the slot's bits |
| `board_voting::submit_vote_execute<P>()` | Board member whose single vote passes | Submit, vote and execute in one PTB |
| `external_execution::ticket_from_cap<P>()` | `&ExternalExecutionCap<P>` for this OU (no sender check) | Bypass ticket carrying the slot's bits |
| `composite::advance_step<P>()` | Passed composite pipeline; `ou` is the pipeline's, not paused, step type still enabled and not frozen | Step ticket carrying the step type's bits |
| `controller::privileged_submit<P>()` | The SubOU's registered `&SubOUControl` (`assert_registered_control`) | Privileged request (0 bits, passes every check on that SubOU) |
| `proposal::delete_expired_proposal<P>()` | Voting period or execution window closed | Delete the proposal (anyone) |

---

## 3. public(package) Functions — Framework-Internal Only

These are callable only from within the `armature_framework` package and are used during OU construction or internal orchestration:

| Module | Function | Purpose |
|--------|----------|---------|
| `governance` | `new_board()` | Construct Board governance config from init payload |
| `governance` | `assert_board_member()` | Assert address is a current board member (aborts if not) |
| `governance` | `set_board()` / `add_board_member(s)()` / `remove_board_member(s)()` | Roster changes (reached via the gated `ou` mutators) |
| `ou` | `governance_mut()` | Mutable access to governance config |
| `ou` | `record_execution()` | Track last execution timestamp for cooldown |
| `proposal` | `create()` / `record_vote()` | Create a proposal, record a vote (via `board_voting`) |
| `proposal` | `execute()` / `execute_single_vote()` / `privileged_execute()` | Mint an `ExecutionRequest` carrying the given bits |
| `proposal` | `new_execution_request()` | Factory for an unprivileged request holding **no** bits |
| `proposal` | `new_external_execution_cap()` / `destroy_external_execution_cap()` | Only `external_execution`'s bypass handlers |
| `charter` | `new()` / `share()` | Construct and share Charter during OU creation |
| `emergency` | `new()` / `new_admin_cap()` / `share()` / `transfer_admin_cap()` | Construct and distribute emergency objects |
| `treasury_vault` | `new()` / `share()` | Construct and share TreasuryVault |
| `capability_vault` | `new()` / `share()` / `store_cap_init()` / `new_subou_control()` | Construct, share, and seed CapabilityVault |
| `capability_vault` | `create_subou_control()` / `receive_cap()` / `privileged_extract()` | Callers establish the cross-OU link the function cannot check (rows above in §2.3) |

---

## 4. Board Member Assertions

Board membership is checked at three points:

1. **Proposal creation** — `board_voting::submit_proposal()` (and `submit_vote_execute()`) calls `ou.governance().assert_board_member(ctx.sender())`
2. **Voting** — `board_voting::vote()` requires the voter was a member at the proposal's `snapshot_version` (`was_member_at`)
3. **Proposal execution** — `proposal::execute()` calls `governance.is_board_member(executor)` and aborts with `ENotEligible` if false

Membership is the gate for *who* may act; the type's permission bits are the gate for *what* the resulting request may do. The bypass and controller paths skip membership (the cap is the authority), which is why a bypass type's bits need care (§7).

---

## 5. How Handlers Consume These Gates

Handlers for framework types live in `armature_framework/sources/handlers` (only the framework can mint their `Permit`); handlers for extension types live beside their payload types in `armature_proposals` and `armature_world_bridge`. Which types belong where is decided by `docs/package-boundaries.md`. Each type must hold the bits its handler's mutators need, or the handler aborts with `proposal::EPermissionDenied`. Framework types hold fixed bits and a fixed borrow scope (§9.1, §9.1a); the rest take theirs from the config that enabled them, as listed by `armature_proposals::type_permissions`.

| Handler Module | Payload Type | Framework Function(s) Called | Bits (`type_permissions`) |
|-----------------|-------------|------------------------------|------|
| `board_ops` (framework) | `SetBoard` | `ou::set_board_governance()` | fixed |
| `member_ops` (framework) | `AddMember`, `BatchAddMembers`, `RemoveMember`, `BatchRemoveMembers` | `ou::add/remove_board_member(s)_governance()` | fixed |
| `admin_ops` (framework) | `EnableProposalType`, `DisableProposalType`, `UpdateProposalConfig` | `ou::enable/disable_proposal_type()`, `ou::update_proposal_config()` | fixed |
| `admin_ops` (framework) | `UpdateMetadata` | `charter::update_metadata()` | fixed |
| `treasury_ops` | `SendCoin<T>`, `SendCoinToOU<T>`, `SendSmallPayment<T>`, `SendBatchMulticoinTo{Address,OU}` | `treasury_vault::withdraw()` / `withdraw_multicoin()` (+ `deposit`) | `treasury_spend()` = TREASURY_WITHDRAW |
| `currency_ops` | `AdoptCurrency<T>` | `capability_vault::store_cap()` | `adopt_currency()` = VAULT_STORE |
| `currency_ops` | `MintCoin<T>`, `MintAllowance<T>` | `capability_vault::borrow_cap_mut()` | `mint()` = VAULT_BORROW, scope `currency_scope<T>()` = [`TreasuryCap<T>`] |
| `configure_mint_allowance` | `ConfigureMintAllowance<T>` | own type-state (minter allowlist read by `currency_ops::mint_allowance_bypass`) | none |
| `currency_ops` | `BurnCoin<T>` | `treasury_vault::withdraw()` + `borrow_cap_mut()` | `burn_coin()` = TREASURY_WITHDRAW + VAULT_BORROW, scope [`TreasuryCap<T>`] |
| `currency_ops` | `ReturnCurrencyCap<T>` | `capability_vault::extract_cap()` | `return_currency_cap()` = VAULT_EXTRACT |
| `freeze_ops` (framework) | `TransferFreezeAdmin` | `emergency::unfreeze_all()` | fixed |
| `freeze_ops` (framework) | `UnfreezeProposalType` | `emergency::governance_unfreeze_type()` | fixed |
| `freeze_ops` (framework) | `UpdateFreezeConfig`, `UpdateFreezeExemptTypes` | `emergency::update_freeze_duration()`, `add/remove_freeze_exempt_type()` | fixed |
| `subou_ops` | `TransferCapToSubOU` | `extract_cap()` + `controller::receive_cap_from_controller()` | `transfer_cap_to_subou()` = VAULT_EXTRACT |
| `subou_ops` | `ReclaimCapFromSubOU` | `loan_cap()` + `controller::privileged_extract()` + `store_cap()` | `reclaim_cap_from_subou()` = VAULT_BORROW + VAULT_STORE, scope `subou_control_scope()` = [`SubOUControl`] |
| `subou_ops` | `PauseSubOUExecution`, `UnpauseSubOUExecution`, `ControllerBatch{Add,Remove}Members` | `loan_cap()` (SubOUControl), then SubOU mutators on a privileged request | `subou_control()` = VAULT_BORROW, scope [`SubOUControl`] |
| `lifecycle_ops` (framework) | `CreateSubOU`, `SpawnOU`, `SpinOutSubOU`, `TransferAssets` | vault / `set_migrating` / controller calls | fixed |
| `upgrade_ops` | `ProposeUpgrade` | `capability_vault::loan_cap()` (UpgradeCap) | `propose_upgrade()` = VAULT_BORROW, scope `propose_upgrade_scope()` = [`UpgradeCap`] |

Every handler follows the same pattern:
1. Accept `ExecutionTicket<P>` from a mint path (§1)
2. Assert the target objects belong to `ticket.ticket_ou_id()`
3. Read the payload with `ticket.ticket_payload()` and call gated framework function(s) with `ticket.ticket_request(permit)`, where `permit` is `internal::permit()` in the module defining `P` (or that module's `public(package) fun permit()`)
4. Call `ticket.discharge(permit)` (or `discharge_returning_payload(permit)`) to destroy the hot potato

Controller-side handlers hold two requests at once: the controller OU's own (which must carry VAULT_BORROW to loan the `SubOUControl`) and the SubOU's privileged request from `privileged_submit`.

---

## 6. Cross-OU Validation

An `ExecutionRequest<P>` carries a `ou_id`. To prevent "shopping" — using a request from OU-A to mutate OU-B — every framework mutator asserts the request's OU against its target **before** checking bits:

| Module | Check | Error |
|--------|-------|-------|
| `ou` | `self.id() == req.req_ou_id()` (in `ou::assert_permitted` / `assert_controller`) | `EOUIdMismatch` (2) |
| `treasury_vault` | `self.ou_id == req.req_ou_id()` | `EOUIdMismatch` (1) |
| `capability_vault` | `self.ou_id == req.req_ou_id()` | `EOUIdMismatch` (3) |
| `charter` | `self.ou_id == req.req_ou_id()` | `EOuMismatch` (0) |
| `emergency` | `self.ou_id == req.req_ou_id()` | `EOUMismatch` (0) |

Exceptions, by design: `capability_vault::receive_cap` does not check the receiving vault's OU, so it is `public(package)` and each framework caller ties the sender to the receiving vault (SpinOutSubOU: its own SubOU; TransferAssets: the voted target; `controller::receive_cap_from_controller`: the sender's vault holds the SubOU's registered control). Other packages use `receive_cap_from_controller` for parent→child moves and `receive_cap_authorized` for anything else. Also by design, `tribe::create_wired_subou` relies on `store_cap`'s vault check. Handlers in `armature_proposals` additionally assert their target objects' OU against the ticket.

Tickets are closed with `proposal::discharge()`, which takes a `Permit<P>` that only `P`'s handler module can create, so a ticket cannot be discharged without running its handler. `proposal::consume()` is `public(package)`; `controller::privileged_consume()` checks the request's OU against the `SubOUControl`.

---

## 7. Privilege Escalation Prevention

- **No public constructors** for `ExecutionRequest` — only framework `public(package)` mint functions (§1) create one
- **Hot-potato enforcement** — the token _must_ be consumed in the same PTB; it cannot be stored or transferred
- **Per-type permission bits** — a request authorizes only the mutations its type's slot held bits for when it was minted; every framework mutator checks, and CI fails on an ungated one (§2)
- **Handler authority** — `ticket_request`, `discharge` and `ticket_from_cap` take `std::internal::Permit<P>`, so only `P`'s own module can mint, spend or close its tickets, and it spends the request with arguments read from the payload. CI fails if any of them drops the permit (`scripts/check_request_gates.py`)
- **Floors in `ou`** — every stored config must meet the type's own floor and `permission_floor(bits)` (80% for TYPE_ADMIN, MIGRATE, TREASURY_WITHDRAW, VAULT_BORROW, VAULT_EXTRACT). `assert_config_floors` runs on `enable_proposal_type`, `update_proposal_config` and creation-time overrides, so no handler can skip it (`EThresholdBelowMinimum`, 12)
- **Fixed framework bits** — framework types always hold exactly `ou::framework_permissions` (`EFixedPermissions`, 23)
- **Controlled grants** — only EnableProposalType, EnableBypassType and UpdateProposalConfig (all 80%) or a privileged request may change a type's bits (`EPermissionChangeNotAllowed`, 19; `EGrantFloorNotMet`, 21); grants cannot ride in a composite (`EUseTypedStep`, `EGrantInComposite`)
- **Snapshot isolation** — voting eligibility is fixed at the proposal's `snapshot_version`; later board changes don't affect in-flight proposals
- **Protected types** — `TransferFreezeAdmin` and `UnfreezeProposalType` cannot be frozen, preventing lockout
- **Cooldown tracking** — `ou.record_execution()` prevents rapid re-execution of the same proposal type

**Bypass caveat.** `capability_vault::borrow_external_cap` is public and `external_execution::ticket_from_cap` does not check the sender, but it does take `Permit<P>`: only `P`'s own module can mint a bypass ticket, so the extension's authorization check (character ownership, token balance, an allowlist in type-state) runs there. The cap in the vault is the OU's opt-in, not a bearer credential. `MintAllowance<T>` is minted only by `currency_ops::mint_allowance_bypass`, which checks the sender against the `ConfigureMintAllowance<T>` allowlist and per-call cap (ARMATURE-21 / ARMATURE-31). Grant a bypass type only the bits and scope its handler needs, and never a bit in `bypass_forbidden_bits` (§9.1b). Placement rules for types and handlers: `docs/package-boundaries.md`.

---

## 8. Intra-OU Threshold Bypass Audit (Phantom Type `P` Safety)

### 8.1 Attack Vector

Within the **same OU**, can a board member use a proposal type with a low approval threshold to execute an operation that should require a high threshold?

For example: If `SetBoard` requires 80% threshold but `UpdateMetadata` requires 50%, can a board member create an `ExecutionRequest<UpdateMetadata>` and use it to call `ou.set_board_governance<UpdateMetadata>()`?

### 8.2 Finding: Was exploitable — NOW FIXED

The phantom type `P` on `ExecutionRequest<P>` alone did not provide adequate security. The following issues were identified and resolved:

1. ~~**Framework mutators accept any `P`**: Functions like `set_board_governance<P>()`, `withdraw<T, P>()`, etc. are `public` with unconstrained generic `P`. An `ExecutionRequest<AnyType>` works for every operation.~~ ✅ **Fixed (ROAD-39)**: mutators are still generic over `P`, but each checks the request's permission bits, so `ExecutionRequest<UpdateMetadata>` (METADATA only) aborts `EPermissionDenied` in `set_board_governance`.

2. ~~**`proposal::create()` is `public`** and accepts a caller-supplied `ProposalConfig` parameter. A third-party package can call it directly with arbitrarily low quorum/threshold, bypassing the OU's registered configs entirely.~~ ✅ **Fixed**: `create()` is now `public(package)`.

3. ~~**`proposal::consume()` is `public`** — any package can destroy the hot potato after directly calling framework mutators, bypassing the typed handlers in `armature_proposals`.~~ ✅ **Fixed**: `consume()` is now `public(package)`. External handlers close tickets with `discharge()`.

4. ~~**`type_key` (string) and `P` (Move type) are decoupled**~~ ✅ **Fixed**: type slots are keyed by `P`'s canonical `TypeName`; the display key is looked up from the slot.

### 8.3 Attack Scenario (historical)

A **single malicious board member** could have taken full control:

> **⚠️ This attack is now blocked** three times over: `proposal::create()` and `proposal::consume()` are `public(package)`, and even a request obtained legitimately for a low-threshold type carries only that type's bits.

**Step 1** — Third-party package creates a poisoned proposal (**BLOCKED — `create()` is `public(package)`**):
```move
public struct Dummy has store { x: u8 }

public fun create_poison(ou: &OU, clock: &Clock, ctx: &mut TxContext) {
    let config = proposal::new_config(1, 5000, 0, 0, 0, 0); // quorum=0.01%, threshold=50%
    proposal::create<Dummy>(  // ERROR: public(package) — not callable from here
        ou.id(),
        b"x".to_ascii_string(),
        ctx.sender(),
        b"".to_string(),
        Dummy { x: 0 },
        config,              // custom config, not from OU
        ou.governance(),    // public accessor
        clock,
        ctx,
    );
}
```

**Step 2** — Vote + execute + hijack in one PTB (**BLOCKED — the request carries no BOARD_SET**):
```move
public fun hijack(ou: &mut OU, ticket: ExecutionTicket<Dummy>, ctx: &TxContext) {
    // Dummy was enabled with no bits, so its request carries 0.
    ou.set_board_governance(vector[ctx.sender()], vector[], ticket.ticket_request(internal::permit()));
    // ERROR: proposal::EPermissionDenied — Dummy does not hold BOARD_SET
    ticket.discharge(internal::permit());
}
```

### 8.4 What IS safe

| Mechanism | Status |
|-----------|--------|
| `proposal::execute()` / `privileged_execute()` / `new_execution_request()` | `public(package)` ✓ |
| `board_voting::ticket_from_vote()` | Validates ou_id, type enabled, not frozen, board membership ✓ |
| Framework mutators | Check OU id and permission bits ✓ |
| `ticket_request` / `discharge` / `ticket_from_cap` | Require `Permit<P>`: only `P`'s module can mint, spend or close a ticket ✓ |
| Attacker must be a board member | Required for voting and vote-path execution ✓ (not for bypass — see §7) |

### 8.5 Vulnerability Summary

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | **CRITICAL** | `proposal::create()` was `public` — accepted caller-supplied `ProposalConfig`, bypassing OU's stored governance rules | ✅ Fixed — now `public(package)` |
| 2 | **CRITICAL** | Framework mutators are generic over `P` — `ExecutionRequest<AnyType>` unlocks every operation | ✅ Fixed (ROAD-39) — per-type permission bits checked by every mutator |
| 3 | **HIGH** | `proposal::consume()` was `public` — any package could destroy the hot potato, bypassing typed handlers | ✅ Fixed — now `public(package)`; tickets close with `discharge()` |
| 4 | **MEDIUM** | `proposal::create()` does not validate proposer is a board member (only `submit_proposal` does) | ✅ Fixed — `create()` is `public(package)`, only reachable via `board_voting` |
| 5 | **MEDIUM** | Execution did not check if the proposal type is frozen or still enabled | ✅ Fixed — `ticket_from_vote` asserts the type is enabled and `assert_not_frozen<P>` against the OU's own freeze |
| 6 | **HIGH** | Bypass type's bits are usable by any caller who can build its payload; `MintAllowance` bypass is open minting | ✅ Fixed — `ticket_from_cap` requires `Permit<P>`; only `P`'s module can mint a bypass ticket |
| 7 | **CRITICAL** | A ticket's request is spendable by whoever holds the ticket, with arguments of their choosing: an autojoin player adds any addresses under `BOARD_ADD`; the executor of an approved payment withdraws the whole treasury under `TREASURY_WITHDRAW`; `TransferAssets` hands the withdrawn coins and caps to the executor | ✅ Fixed — `ticket_request` / `discharge` require `Permit<P>`; framework-type handlers moved into the framework; `TransferAssets` moves each listed asset itself |
| 8 | **HIGH** | Handler trusted caller-chosen objects: `execute_mint_coin` / `execute_mint_allowance` deposited into any treasury passed; `execute_propose_upgrade` returned the raw `UpgradeCap` | ✅ Fixed — treasury checked against the request's OU; the cap stays in a `PendingUpgrade` hot potato |
| 9 | **CRITICAL** | `create_subou_control` accepted any `subou_id` and `privileged_submit` / `privileged_extract` compared only `control.subou_id`: any OU could mint a control for another OU and drive it | ✅ Fixed — `create_subou_control` and `capability_vault::privileged_extract` are `public(package)`; `controller::assert_registered_control` requires the control to be the SubOU's `controller_cap_id` (`ENotController`) |
| 10 | **HIGH** | `assert_not_frozen<P>` did not check the freeze object's OU: passing another OU's unfrozen freeze skipped the check | ✅ Fixed — `assert_not_frozen<P>(freeze, ou_id, clock)` aborts `EOUMismatch` on every execution path |
| 11 | **MEDIUM** | `receive_cap` was `public` and checked no receiving OU: any request with VAULT_EXTRACT could push caps into any vault; `TransferCapToSubOU` did not check the target was the sender's SubOU | ✅ Fixed — `receive_cap` is `public(package)`; parent→child moves use `controller::receive_cap_from_controller` |
| 12 | **HIGH** | `begin_pipeline` / `advance_step` did not bind the passed `OU` to the ticket / pipeline, so a step could run with another OU's type config and bits; steps ignored pauses and disabled types | ✅ Fixed — `composite::EOUIdMismatch`, `EExecutionPaused`, `EControllerPaused`, `ETypeNotEnabled` |

### 8.6 Applied Fixes

**Fix 1 (blocks the attack)**: `proposal::create()` changed to `public(package) fun`. Forces all proposal creation through `board_voting`, which validates the type is enabled and uses the OU's stored `ProposalConfig`.

**Fix 2 (defense-in-depth)**: `proposal::consume()` changed to `public(package) fun`. Handlers receive an `ExecutionTicket<P>` and close it with `discharge()`, which requires a `Permit<P>` from `P`'s handler module.

**Fix 3 (ROAD-39)**: per-type permission bits (§9). `ExecutionRequest` carries the bits of its type's slot; every mutator checks them; floors live in `ou`; framework types have fixed bits; only the 80% meta-types may grant.

## 9. Permission Bits (ROAD-39)

Each proposal type's `ProposalConfig.permissions` names the OU-wide mutations a request of that type may perform. The request carries the bits its slot held when it was minted, and every mutator checks them (`ou::assert_permitted` for OU mutators, `proposal::assert_permitted` for the vault, charter, emergency and tribe modules; see §2). Bits are defined in `armature::permissions`. A config holding any bit marked 80% needs `approval_threshold >= 8000` (`ou::permission_floor`), on every path that stores a config.

| Bit | Floor | Guards |
|---|---|---|
| `BOARD_ADD` | — | add board members |
| `BOARD_REMOVE` | — | remove board members |
| `BOARD_SET` | — | apply a SetBoard diff |
| `TYPE_ADMIN` | 80% | enable, disable, reconfigure proposal types |
| `PAUSE` | — | pause or resume execution |
| `MIGRATE` | 80% | move the OU to Migrating |
| `METADATA` | — | charter metadata |
| `TREASURY_WITHDRAW` | 80% | withdraw from the TreasuryVault |
| `VAULT_STORE` | — | store a capability |
| `VAULT_BORROW` | 80% | borrow or loan a capability whose type is in the config's `borrow_scope` (a mutable TreasuryCap borrow mints; a loaned SubOUControl controls the SubOU) |
| `VAULT_EXTRACT` | 80% | extract a capability; create or destroy a SubOUControl |
| `FREEZE` | — | governance changes to the EmergencyFreeze |

### 9.1 Framework types: fixed bits

Framework payload types always hold exactly these bits (`ou::framework_permissions`), whatever config enabled them; `UpdateProposalConfig` cannot change them (`EFixedPermissions`). Default slots are seeded with them at OU creation, with thresholds raised to the floor they need.

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
| SpawnOU | MIGRATE | `set_migrating` |
| CreateSubOU | VAULT_STORE, VAULT_EXTRACT | creates and stores a SubOUControl, stores the SubOU's FreezeAdminCap |
| SpinOutSubOU | VAULT_BORROW (scope: SubOUControl), VAULT_EXTRACT | loans the SubOUControl, extracts the FreezeAdminCap, destroys the control |
| TransferAssets | TREASURY_WITHDRAW, VAULT_EXTRACT | moves coins and caps to the successor |
| CompositePayload | none | its ticket is consumed by `begin_pipeline` |

Other types (e.g. `armature_proposals`' `SendCoin<T>`) hold the bits in the config that enabled them: a `ProposalTypeInit` override at creation, or an `EnableProposalType` / `EnableBypassType` payload. Both default to none.

### 9.1a Borrow scope

`ProposalConfig.borrow_scope` (a `vector<TypeName>`, `with_borrow_scope`) names the capability types a VAULT_BORROW request may borrow or loan. Deny-by-default: empty borrows nothing. `ExecutionRequest.borrow_scope` copies it at mint time on every path (two-PTB, atomic, bypass, composite step; a controller request carries none and is privileged). `capability_vault::borrow_cap`, `borrow_cap_mut` and `loan_cap` call `proposal::assert_may_borrow(req, &type_name::with_defining_ids<T>())` after the bit check (`EBorrowScopeDenied`, 22); a privileged request passes. Framework types hold a fixed scope (`ou::framework_borrow_scope`: SpinOutSubOU → [SubOUControl], all others empty), enforced with the fixed bits (`EFixedPermissions`). A scope change is a grant: `assert_may_change_permissions` treats it as adding VAULT_BORROW, so only the three meta-types (or a privileged request) may set or change it, and the composite typed steps refuse it (`EGrantInComposite`). `UpdateProposalConfig` carries it as `Option<vector<TypeName>>` (`with_borrow_scope`). Extension packages publish scopes beside bits (`armature_proposals::type_permissions::*_scope`).

### 9.1b Bypass-safe bits

`external_execution::bypass_forbidden_bits()` = TYPE_ADMIN | MIGRATE | VAULT_EXTRACT | FREEZE. `execute_enable_bypass_type` refuses a config holding any of them, and `ticket_from_cap_core` refuses to mint for a slot holding any of them (`EBypassForbiddenBits`, 15), so a later grant via `UpdateProposalConfig` cannot open a no-vote path to the authority graph either.

### 9.2 Who may change bits

Only a request of type EnableProposalType, EnableBypassType or UpdateProposalConfig may change a non-framework type's bits, or a privileged (controller) request. All three meta-types sit at the 80% floor, so every grant is approved by an 80% vote. Grants are standalone-only: `composite::add_step` refuses EnableProposalType and UpdateProposalConfig steps, and the typed `add_enable_proposal_type_step` / `add_update_proposal_config_step` refuse any step that would change bits.
