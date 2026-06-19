# Proposal Types

All governance actions in Armature are encoded as typed proposal payloads. Each type must be enabled on the DAO before it can be submitted, and is subject to the `ProposalConfig` (approval threshold, cooldown, quorum) for that type.

---

## Admin

### `UpdateMetadata`
Update the DAO's metadata IPFS CID. Used to reflect off-chain changes to the DAO's name, description, or logo.

### `UpdateProposalConfig`
Update one or more `ProposalConfig` fields (approval threshold, cooldown, quorum, composability) for a given proposal type. When the target type is `UpdateProposalConfig` itself, an 80% super-majority is enforced at execution time.

### `EnableProposalType`
Add a new proposal type to the DAO's enabled set and bind the canonical Move type to the type key, preventing future substitution. Enforces a 66% approval floor at execution time. Cannot be disabled.

### `DisableProposalType`
Remove a proposal type from the DAO's enabled set. The handler rejects attempts to disable undisableable types (`EnableProposalType`, `DisableProposalType`, `TransferFreezeAdmin`, `UnfreezeProposalType`).

---

## Board

### `AddMember`
Add a single address to the DAO's board. Lighter-weight alternative to `SetBoard` when only one address needs to be added.

### `RemoveMember`
Remove a single address from the DAO's board. Lighter-weight alternative to `SetBoard` when only one address needs to be removed.

### `BatchAddMembers`
Add multiple addresses to the board in a single proposal. Silently skips addresses already on the board (both `added` and `skipped` are reported in the `MembersBatchAdded` event). Aborts on duplicates within the batch, an empty batch, or a batch exceeding the per-proposal cap (100 addresses).

### `BatchRemoveMembers`
Remove multiple addresses from the board in a single proposal. Aborts atomically if any address is not on the board, the batch contains duplicates, or removal would leave the board empty.

### `SetBoard`
Replace the entire board member set in one operation. Used when restructuring the board or bootstrapping initial membership.

---

## Currency

### `AdoptCurrency<T>`
Take custody of a `TreasuryCap<T>`, granting the DAO mint/burn authority over `Coin<T>`. The cap is passed by value in the execution PTB, not named in the payload. Vote-gated to prevent anyone from pushing an arbitrary cap into the vault.

### `MintCoin<T>`
Mint `amount` of `Coin<T>` using the DAO's custodied `TreasuryCap<T>`. With `recipient = none`, coins are routed into the DAO's `TreasuryVault`; with `recipient = some(addr)`, they are issued directly to an address.

### `MintAllowance<T>`
Operationally identical to `MintCoin<T>`, but kept as a distinct type so a DAO can `EnableBypassType` on it — allowing delegated minting via `ExternalExecutionCap<MintAllowance<T>>` without a fresh vote each time, while `MintCoin` remains fully vote-gated. Throttled by `cooldown_ms` and per-call `amount`.

### `BurnCoin<T>`
Burn `amount` of `Coin<T>` using the DAO's custodied `TreasuryCap<T>`. Coins are withdrawn from the `TreasuryVault` before burning, keeping supply contraction on the same accountable path as spend proposals.

### `ReturnCurrencyCap<T>`
Extract the `TreasuryCap<T>` from the DAO's `CapabilityVault` and transfer it to a recipient, relinquishing the DAO's mint/burn authority. The escape hatch for migrations and sub-DAO spin-outs. Vote-gated and symmetric to `AdoptCurrency`.

---

## Security

### `UpdateFreezeConfig`
Update the `max_freeze_duration_ms` on the `EmergencyFreeze` object, controlling how long an admin-initiated freeze can last.

### `UpdateFreezeExemptTypes`
Add or remove proposal types from the freeze-exempt set on `EmergencyFreeze`. Exempt types continue to be executable even when the DAO is frozen.

### `TransferFreezeAdmin`
Transfer the `FreezeAdminCap` to a new address. Unfreezes all currently frozen types as a side effect. Cannot itself be frozen.

### `UnfreezeProposalType`
Governance-initiated unfreeze of a specific proposal type. Overrides an admin freeze without requiring the `FreezeAdminCap`. Cannot itself be frozen.

---

## SubDAO

### `CreateSubDAO`
Create a new board-governance SubDAO controlled by this DAO. The new DAO is born with a `SubDAOControl` relationship making this DAO its controller.

### `SpawnDAO`
Create a successor DAO and transition this DAO to `Migrating` status. Used for protocol migrations where continuity of identity matters.

### `SpinOutSubDAO`
Destroy the `SubDAOControl` relationship and grant a SubDAO full independence. Irreversible — the controller DAO loses all privileged access to the spun-out DAO.

### `TransferCapToSubDAO`
Transfer a capability from this DAO's `CapabilityVault` to a SubDAO's vault. Used to delegate specific authorities (e.g. a `TreasuryCap`) to a subordinate DAO.

### `ReclaimCapFromSubDAO`
Reclaim a capability from a SubDAO's vault using `SubDAOControl` authority. Proposed on the controller DAO, not the SubDAO.

### `ControllerBatchAddMembers`
Add multiple members to a managed SubDAO's board via `SubDAOControl` authority. Proposed on the controller DAO; executes atomically on the target SubDAO using the `privileged_submit` pattern.

### `ControllerBatchRemoveMembers`
Remove multiple members from a managed SubDAO's board via `SubDAOControl` authority. Proposed on the controller DAO; executes atomically on the target SubDAO.

### `PauseSubDAOExecution`
Pause all proposal execution on a SubDAO. Requires `privileged_submit` (controller only).

### `UnpauseSubDAOExecution`
Resume proposal execution on a paused SubDAO. Requires `privileged_submit` (controller only).

### `TransferAssets`
Move treasury coin balances and capability vault contents to a target DAO. Subject to a per-call combined asset limit of 50.

---

## Treasury

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
Authorize a package upgrade using a stored `UpgradeCap`. Step 1 of a two-step PTB flow: loans the `UpgradeCap` from the vault, calls `package::authorize_upgrade`, and returns a ticket. The caller must follow with `commit_upgrade` in the same PTB after the `Upgrade` command.
