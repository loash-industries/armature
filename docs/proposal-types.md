# Proposal Types

All governance actions in Armature are encoded as typed proposal payloads. Each type must be enabled on the DAO before it can be submitted, and is subject to the `ProposalConfig` (approval threshold, cooldown, quorum, permission bits) for that type.

Each entry lists the **permission bits** the type needs (see [Permissions](#permissions) below) and its **floor**, the minimum `approval_threshold` any config for the type must meet. Framework types hold **fixed** bits (`dao::framework_permissions`) that no config can change. `armature_proposals` types must be enabled with the bits named by `armature_proposals::type_permissions`, or their handler aborts with `proposal::EPermissionDenied`.

---

## Admin

### `UpdateMetadata`
Update the DAO's metadata IPFS CID. Used to reflect off-chain changes to the DAO's name, description, or logo.

**Bits:** `METADATA` (fixed). **Floor:** none.

### `UpdateProposalConfig`
Update one or more `ProposalConfig` fields (approval threshold, cooldown, quorum, composability, and permission bits via `with_permissions(bits)`) for a given proposal type. Every config it stores must meet the target type's floors. Bit changes are standalone-only: a composite step that changes bits aborts (`EGrantInComposite`).

**Bits:** `TYPE_ADMIN` (fixed). **Floor:** 80%.

### `EnableProposalType`
Add a new proposal type to the DAO's enabled set and bind the canonical Move type to the type key, preventing future substitution. The payload's config sets the new type's bits. Enforces an 80% approval floor (on its own config, and at submission). Cannot be disabled. Composites must use `add_enable_proposal_type_step`, which refuses a config with bits.

**Bits:** `TYPE_ADMIN` (fixed). **Floor:** 80%.

### `DisableProposalType`
Remove a proposal type from the DAO's enabled set. The handler rejects attempts to disable undisableable types (`EnableProposalType`, `DisableProposalType`, `EnableBypassType`, `DisableBypassType`, `TransferFreezeAdmin`, `UnfreezeProposalType`).

**Bits:** `TYPE_ADMIN` (fixed). **Floor:** 80%.

### `EnableBypassType` / `DisableBypassType`
Enable a type and mint its `ExternalExecutionCap` into the vault (so it executes without a vote via `ticket_from_cap`), or extract and destroy the cap and disable the type. `EnableBypassType` sets the new type's bits from its payload config and checks 80% on the actual vote weights. Not available on SubDAOs.

**Bits:** `TYPE_ADMIN` + `VAULT_STORE` / `TYPE_ADMIN` + `VAULT_EXTRACT` (fixed). **Floor:** 80%.

---

## Board

### `AddMember`
Add a single address to the DAO's board. Lighter-weight alternative to `SetBoard` when only one address needs to be added.

**Bits:** `BOARD_ADD` (fixed). **Floor:** none.

### `RemoveMember`
Remove a single address from the DAO's board. Lighter-weight alternative to `SetBoard` when only one address needs to be removed.

**Bits:** `BOARD_REMOVE` (fixed). **Floor:** none.

### `BatchAddMembers`
Add multiple addresses to the board in a single proposal. Silently skips addresses already on the board (both `added` and `skipped` are reported in the `MembersBatchAdded` event). Aborts on duplicates within the batch, an empty batch, or a batch exceeding the per-proposal cap (100 addresses).

**Bits:** `BOARD_ADD` (fixed). **Floor:** none.

### `BatchRemoveMembers`
Remove multiple addresses from the board in a single proposal. Aborts atomically if any address is not on the board, the batch contains duplicates, or removal would leave the board empty.

**Bits:** `BOARD_REMOVE` (fixed). **Floor:** none.

### `SetBoard`
Apply an add/remove diff to the board in one operation. Used when restructuring the board or bootstrapping initial membership.

**Bits:** `BOARD_SET` (fixed). **Floor:** none.

---

## Currency

### `AdoptCurrency<T>`
Take custody of a `TreasuryCap<T>`, granting the DAO mint/burn authority over `Coin<T>`. The cap is passed by value in the execution PTB, not named in the payload. Vote-gated to prevent anyone from pushing an arbitrary cap into the vault.

**Bits:** `type_permissions::adopt_currency()` = `VAULT_STORE`. **Floor:** none.

### `MintCoin<T>`
Mint `amount` of `Coin<T>` using the DAO's custodied `TreasuryCap<T>`. With `recipient = none`, coins are routed into the DAO's `TreasuryVault`; with `recipient = some(addr)`, they are issued directly to an address.

**Bits:** `type_permissions::mint()` = `VAULT_BORROW`, scoped to `TreasuryCap<T>` (`type_permissions::currency_scope<T>()`). **Floor:** 80%.

### `MintAllowance<T>`
Operationally identical to `MintCoin<T>`, but kept as a distinct type so a DAO can `EnableBypassType` on it — allowing delegated minting without a fresh vote each time, while `MintCoin` remains fully vote-gated. The bypass entry is `currency_ops::mint_allowance_bypass<T>`: it checks the sender against the DAO's `ConfigureMintAllowance<T>` allowlist and per-call cap before minting the ticket, and the ticket never leaves that function. Nobody else can mint a bypass ticket for this type, because `ticket_from_cap` takes `Permit<MintAllowance<T>>` (ARMATURE-31). Throttled by the per-call cap and `cooldown_ms`.

**Bits:** `type_permissions::mint()` = `VAULT_BORROW`, scoped to `TreasuryCap<T>` (`type_permissions::currency_scope<T>()`). **Floor:** 80%.

### `ConfigureMintAllowance<T>`
Board-voted allowlist for `MintAllowance<T>` bypass minting: add or remove minter addresses, set the per-call cap, and flip a kill-switch. Stored as DAO type-state keyed by this type; the state starts disabled and empty. A DAO enables the bypass in two votes: `EnableBypassType` for `MintAllowance<T>` and a `ConfigureMintAllowance<T>` naming the minters.

**Bits:** none (`type_permissions::configure_mint_allowance()` = 0; writes only its own type-state). **Floor:** none.

### `BurnCoin<T>`
Burn `amount` of `Coin<T>` using the DAO's custodied `TreasuryCap<T>`. Coins are withdrawn from the `TreasuryVault` before burning, keeping supply contraction on the same accountable path as spend proposals.

**Bits:** `type_permissions::burn_coin()` = `TREASURY_WITHDRAW` + `VAULT_BORROW`, scoped to `TreasuryCap<T>`. **Floor:** 80%.

### `ReturnCurrencyCap<T>`
Extract the `TreasuryCap<T>` from the DAO's `CapabilityVault` and transfer it to a recipient, relinquishing the DAO's mint/burn authority. The escape hatch for migrations and sub-DAO spin-outs. Vote-gated and symmetric to `AdoptCurrency`.

**Bits:** `type_permissions::return_currency_cap()` = `VAULT_EXTRACT`. **Floor:** 80%.

---

## Security

All four freeze-governance types are framework types handled by `armature::freeze_ops`. The emergency freeze is the framework's last line of defence, so the types that reconfigure it are not left to an extension package.

### `UpdateFreezeConfig`
Update the `max_freeze_duration_ms` on the `EmergencyFreeze` object, controlling how long an admin-initiated freeze can last.

**Bits:** `FREEZE` (fixed). **Floor:** none.

### `UpdateFreezeExemptTypes`
Add or remove proposal types from the freeze-exempt set on `EmergencyFreeze`. Exempt types continue to be executable even when the DAO is frozen.

**Bits:** `FREEZE` (fixed). **Floor:** none.

### `TransferFreezeAdmin`
Transfer the `FreezeAdminCap` to a new address. Unfreezes all currently frozen types as a side effect. Cannot itself be frozen.

**Bits:** `FREEZE` (fixed). **Floor:** none.

### `UnfreezeProposalType`
Governance-initiated unfreeze of a specific proposal type. Overrides an admin freeze without requiring the `FreezeAdminCap`. Cannot itself be frozen.

**Bits:** `FREEZE` (fixed). **Floor:** none.

---

## SubDAO

### `CreateSubDAO`
Create a new board-governance SubDAO controlled by this DAO. The new DAO is born with a `SubDAOControl` relationship making this DAO its controller.

**Bits:** `VAULT_STORE` + `VAULT_EXTRACT` (fixed). **Floor:** 80%.

### `SpawnDAO`
Create a successor DAO and transition this DAO to `Migrating` status. Used for protocol migrations where continuity of identity matters.

**Bits:** `MIGRATE` (fixed). **Floor:** 80%.

### `SpinOutSubDAO`
Destroy the `SubDAOControl` relationship and grant a SubDAO full independence. Irreversible — the controller DAO loses all privileged access to the spun-out DAO.

**Bits:** `VAULT_BORROW` + `VAULT_EXTRACT` (fixed), scoped to `SubDAOControl` (fixed). **Floor:** 80%.

### `TransferCapToSubDAO`
Transfer a capability from this DAO's `CapabilityVault` to a SubDAO's vault. Used to delegate specific authorities (e.g. a `TreasuryCap`) to a subordinate DAO.

**Bits:** `type_permissions::transfer_cap_to_subdao()` = `VAULT_EXTRACT`. **Floor:** 80%.

### `ReclaimCapFromSubDAO`
Reclaim a capability from a SubDAO's vault using `SubDAOControl` authority. Proposed on the controller DAO, not the SubDAO.

**Bits:** `type_permissions::reclaim_cap_from_subdao()` = `VAULT_BORROW` + `VAULT_STORE`, scoped to `SubDAOControl` (`type_permissions::subdao_control_scope()`). **Floor:** 80%.

### `ControllerBatchAddMembers`
Add multiple members to a managed SubDAO's board via `SubDAOControl` authority. Proposed on the controller DAO; executes atomically on the target SubDAO using the `privileged_submit` pattern.

**Bits:** `type_permissions::subdao_control()` = `VAULT_BORROW`, scoped to `SubDAOControl` (on the controller; the SubDAO side runs on a privileged request). **Floor:** 80%.

### `ControllerBatchRemoveMembers`
Remove multiple members from a managed SubDAO's board via `SubDAOControl` authority. Proposed on the controller DAO; executes atomically on the target SubDAO.

**Bits:** `type_permissions::subdao_control()` = `VAULT_BORROW`, scoped to `SubDAOControl`. **Floor:** 80%.

### `PauseSubDAOExecution`
Pause all proposal execution on a SubDAO. Requires `privileged_submit` (controller only).

**Bits:** `type_permissions::subdao_control()` = `VAULT_BORROW`, scoped to `SubDAOControl`. **Floor:** 80%.

### `UnpauseSubDAOExecution`
Resume proposal execution on a paused SubDAO. Requires `privileged_submit` (controller only).

**Bits:** `type_permissions::subdao_control()` = `VAULT_BORROW`, scoped to `SubDAOControl`. **Floor:** 80%.

### `TransferAssets`
Move treasury coin balances and capability vault contents to a target DAO. Subject to a per-call combined asset limit of 50.

**Bits:** `TREASURY_WITHDRAW` + `VAULT_EXTRACT` (fixed). **Floor:** 80%.

---

## Treasury

All treasury types need `type_permissions::treasury_spend()` = `TREASURY_WITHDRAW`, so every config for them needs an **80%** approval threshold.

### `SendCoin<T>`
Transfer `amount` of `Coin<T>` from the DAO's `TreasuryVault` to an address.

### `SendCoinToDAO<T>`
Transfer `amount` of `Coin<T>` from the DAO's `TreasuryVault` directly into another DAO's `TreasuryVault`.

### `SendSmallPayment<T>`
Rate-limited withdrawal from the treasury. Uses `SmallPaymentState` (a dynamic field on the DAO, keyed per coin type) to enforce a cumulative spend cap within rolling time epochs. Designed for recurring operational expenses without a fresh vote per payment.

### `SendBatchMulticoinToAddress`
Transfer a batch of multicoin (collection/asset) balances from the treasury to a player address in a single proposal.

### `SendBatchMulticoinToDAO`
Transfer a batch of multicoin balances from the treasury directly into another DAO's `TreasuryVault`.

---

## Upgrade

### `ProposeUpgrade`
Authorize a package upgrade using a stored `UpgradeCap`. Step 1 of a two-step PTB flow: loans the `UpgradeCap` from the vault, calls `package::authorize_upgrade`, and returns the `UpgradeTicket` plus a `PendingUpgrade` hot potato holding the cap. The caller must follow with `commit_upgrade(vault, pending, receipt)` in the same PTB after the `Upgrade` command. The cap never reaches the caller.

**Bits:** `type_permissions::propose_upgrade()` = `VAULT_BORROW`, scoped to `UpgradeCap` (`type_permissions::propose_upgrade_scope()`). **Floor:** 80%.

---

## Permissions

A type's `ProposalConfig.permissions` is a bitmask from `armature::permissions` naming the DAO-wide mutations its requests may perform. It is deny-by-default: a type holds no bits unless given them. Every framework mutator checks its bit (`proposal::EPermissionDenied`, 21, if missing). The full per-function table is in `packages/armature_framework/internal_workings.md` §2 and §9.

| Bit | Floor | Guards |
|---|---|---|
| `BOARD_ADD` / `BOARD_REMOVE` / `BOARD_SET` | — | add members / remove members / apply a SetBoard diff |
| `TYPE_ADMIN` | 80% | enable, disable, reconfigure types |
| `PAUSE` | — | `set_execution_paused` |
| `MIGRATE` | 80% | `set_migrating` |
| `METADATA` | — | `charter::update_metadata` |
| `TREASURY_WITHDRAW` | 80% | `treasury_vault::withdraw`, `withdraw_multicoin` |
| `VAULT_STORE` | — | `store_cap`; receiving side of `receive_cap_authorized` |
| `VAULT_BORROW` | 80% | `borrow_cap`, `borrow_cap_mut`, `loan_cap`, further limited to the cap types in the config's `borrow_scope` |
| `VAULT_EXTRACT` | 80% | `extract_cap`, `create/destroy_subdao_control`; sending side of `receive_cap(_authorized)` |
| `FREEZE` (`permissions::emergency_freeze()`) | — | governance changes to the `EmergencyFreeze` |

A config holding any 80% bit must have `approval_threshold >= 8000` (`dao::permission_floor`); `dao` checks this on every config it stores (`EThresholdBelowMinimum`).

### Borrow scope

`VAULT_BORROW` says a type may borrow from the vault; `ProposalConfig.borrow_scope` says which capability types. It is a list of `std::type_name::with_defining_ids` names, set with `with_borrow_scope(scope)`, and deny-by-default: an empty scope borrows nothing. The vault checks it on `borrow_cap`, `borrow_cap_mut` and `loan_cap` after the bit (`proposal::EBorrowScopeDenied`, 22). It rides on the request exactly like the bits, and changing it follows the same grant rules: only the three type-admin meta-types or a privileged request may set or change a scope, never inside a composite, and framework types hold a fixed scope (`dao::framework_borrow_scope`; only `SpinOutSubDAO` borrows, and only `SubDAOControl`). A scope names cap types per instantiation, so `MintCoin<T>` scoped to `TreasuryCap<T>` cannot borrow another coin's cap, the `UpgradeCap` or a `SubDAOControl` in the same vault, whatever its handler does. `armature_proposals::type_permissions` publishes each built-in type's scope beside its bits.

### Bypass-safe bits

A bypass-enabled type may never hold `TYPE_ADMIN`, `MIGRATE`, `VAULT_EXTRACT` or `FREEZE` (`external_execution::bypass_forbidden_bits`, `EBypassForbiddenBits`, 15). Each changes who may do what, and a path that executes without a vote must not change that. `EnableBypassType` refuses such a config, and `ticket_from_cap` refuses to mint for a slot that holds one, so a later `UpdateProposalConfig` grant cannot open it either.

### For integrators (third-party types)

- **Request bits, and a borrow scope, in the enabling config.** Set them with `proposal::new_config(...).with_permissions(bits).with_borrow_scope(caps)` in the `EnableProposalType` / `EnableBypassType` payload, or in a `ProposalTypeInit` override at DAO creation. Ask for exactly what your handler's mutators need, list exactly the cap types it borrows, and set `approval_threshold` to at least `dao::permission_floor(bits)`. Publish functions returning your bits and scope, as `type_permissions` and `autojoin_ops::autojoin_permissions()` (= `BOARD_ADD`) do.
- **Who can grant.** Only `EnableProposalType`, `EnableBypassType` and `UpdateProposalConfig` may set or change a type's bits (`EPermissionChangeNotAllowed` otherwise), plus a controller's privileged request. All three sit at 80%, so they can grant any bit. A third-party type holding `TYPE_ADMIN` can enable or reconfigure types but cannot change anyone's bits. Grants are standalone-only: `composite::add_step` refuses `EnableProposalType` / `UpdateProposalConfig` (`EUseTypedStep`), and the typed `add_enable_proposal_type_step` / `add_update_proposal_config_step` refuse bit changes (`EGrantInComposite`). Framework types' bits are fixed (`EFixedPermissions`).
- **Bits are read at mint time.** A request carries the bits its type's slot held when it was minted (at execution, on every path). A grant or revocation applies from the next execution; a proposal already passed executes with whatever bits the slot holds when it runs.
- **Handlers must live beside the payload type.** `ticket_request`, `discharge` and `discharge_returning_payload` take `std::internal::Permit<P>`, which only the module defining `P` can mint. Put the handler in that module, or expose `public(package) fun permit(): Permit<P> { internal::permit() }` from it and call that from a handler module in the same package. Anyone else holding the ticket can read its payload but cannot spend or close it, so the only way out of the PTB is through your handler, with the arguments your handler reads from the payload.
- **Bypass tickets are minted by your module.** `ticket_from_cap` / `ticket_from_cap_readonly` also take `Permit<P>`. `borrow_external_cap` is public, so your module is the only authorization point: run your external check (character ownership, token balance, ...) before minting. Returning the ticket to the caller is safe, since they can do nothing with it except pass it to your handler; `autojoin_ops::autojoin` mints, spends and discharges in one call.
- **Bits bound your own handler.** A bit covers the whole resource: `TREASURY_WITHDRAW` reaches every coin, any amount, and `VAULT_BORROW` every cap type in the scope. The permit keeps outsiders from using your request, but a bug in your handler can use every bit and every scoped cap your type holds. Grant only the bits the handler needs, scope borrows to the cap types it uses, and check every object argument the caller passes (target treasury, vault, DAO) against the payload or the request's DAO.
- **Bypass types authenticate in their mint entry.** The `ExternalExecutionCap` in the vault is the DAO's opt-in, not a bearer credential: `borrow_external_cap` is public. Your mint entry is the only place that can call `ticket_from_cap<P>`, so run your check there (`ctx.sender()` against an allowlist in your own type-state, character ownership, a token balance) before minting, and keep the ticket inside the function. `currency_ops::mint_allowance_bypass` and `autojoin_ops::autojoin` are the templates. See `docs/package-boundaries.md`.
- **Never pass a request to a mutator your type was not granted.** It aborts with `EPermissionDenied`, reverting the whole PTB. Composite steps do not pool bits: each step's request carries only its own type's bits.
