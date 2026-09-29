# 06 — Security Model and Threat Analysis

> **Scope**: This document covers the implemented framework and its first-party extensions. For federation-specific threats, see [stretch/01 Federation](stretch/01_federation.md). For project-funding threats, see [stretch/04 Project Funding](stretch/04_project_funding.md). The per-function gate table is in [`internal_workings.md`](../packages/armature_framework/internal_workings.md) §2; the package trust boundary in [`docs/package-boundaries.md`](../docs/package-boundaries.md).

## 1. Security Philosophy

The protocol's security model is built on **defense-in-depth** — no single mechanism is relied upon exclusively. Security arises from the interaction of multiple reinforcing layers:

| Layer | Mechanism | Protects Against |
|---|---|---|
| **Type system** | Hot potatoes (`ExecutionRequest`, `ExecutionTicket`, `CapLoan`, `Pipeline`, `AssetTransfer`), `public(package)` constructors, phantom type tags | Forgery, replay, skipped handlers |
| **Handler binding** | `ticket_request`, `discharge` and `ticket_from_cap` take `std::internal::Permit<P>`: only `P`'s own module can spend, close or bypass-mint its tickets | A ticket holder spending the request with arguments of their own choosing |
| **Per-type permissions** | `ProposalConfig.permissions` bits and `borrow_scope`, carried on every request and checked by every framework mutator; fixed bits for framework types; CI gate check | Cross-type privilege escalation; a type reaching resources it was never granted |
| **Governance thresholds** | Per-type `approval_threshold`; 80% floors for `EnableProposalType`, `UpdateProposalConfig`, `EnableBypassType` and for any config holding a high-impact bit; grants only by the 80% meta-types, never in a composite | Privilege escalation, config weakening, minority capture |
| **Timing controls** | `execution_delay_ms`, `cooldown_ms`, `expiry_ms` (voting deadline and execution window) | Flash attacks, reaction-time attacks, rapid-fire drains, stale approvals |
| **Emergency circuit breaker** | `EmergencyFreeze` + `FreezeAdminCap`, per-type freezes with auto-expiry, governance override | Discovered vulnerabilities, compromised members, active attacks |
| **Hierarchy controls** | `SubOUControl` (must be the SubOU's registered `controller_cap_id`), `controller_paused`, SubOU blocklist | Rogue SubOUs, forged controllers, unauthorized independence, self-granted bypass |
| **Blast radius isolation** | Separate `TreasuryVault` and `CapabilityVault` per OU; gated mutators check the request's OU (a cross-OU cap move needs both OUs' requests or the receiver's registered controller) | Cross-OU contamination, cascading treasury drain |

---

## 2. Resolved Threats

These threats were identified in design or security review and resolved with protocol changes. References are to `.cortex/changelog.md` tickets where one exists.

### 2.1 No Emergency Recovery → Resolved

**Original risk:** No mechanism to pause operations during a vulnerability disclosure.

**Resolution:** `EmergencyFreeze` with `FreezeAdminCap`. The cap holder can freeze specific proposal types for up to `max_freeze_duration_ms`. Auto-expiry prevents permanent lockout. `TransferFreezeAdmin` and `UnfreezeProposalType` are immune to freezing, matched by the framework's own types so a look-alike type in another package gets no exemption.

### 2.2 Permissionless Execution → Resolved

**Original risk:** Anyone could call `execute()` on passed proposals, enabling front-running.

**Resolution:** On the vote path the executor must be a current board member (`ENotEligible`). The atomic path executes as the proposer, who must be a member. Paths that execute without a member are opt-ins: bypass types, which authenticate in their own mint entry (§2.12), and the controller override.

### 2.3 `EnableProposalType` Escalation → Resolved

**Original risk:** Enabling dangerous types with weak governance parameters, or with a type other than the one voters approved.

**Resolution:** `EnableProposalType` carries a mandatory `ProposalConfig` (atomic enablement + config), requires 80% (at submission, on its own config, and in composites), and pins the Move type the board approved (`type_name`; `ETypeMismatch` if the executor names another). Every config it stores must meet the new type's floors.

### 2.4 Recursive Config Weakening → Resolved

**Original risk:** `UpdateProposalConfig` used to lower its own thresholds, then cascading to weaken all types.

**Resolution:** `ou` enforces floors on every config it stores (`assert_config_floors`): `UpdateProposalConfig`'s own config can never drop below 80%, and no config can drop below the floor of the bits it holds. `admin_ops::propose_update_proposal_config` additionally refuses a self-targeting proposal at submission.

### 2.5 `is_managed` Flag Desync → Resolved

**Original risk:** Boolean flag could desync from actual `SubOUControl` existence.

**Resolution:** Replaced `is_managed: bool` with `controller_cap_id: Option<ID>`, recording the control capability's ID.

### 2.6 No Capability Reclaim Path → Resolved

**Original risk:** Delegated capabilities required a two-step process with a race condition window.

**Resolution:** `ReclaimCapFromSubOU` loans the `SubOUControl`, calls `controller::privileged_extract` and stores the capability in the controller's vault in one handler. Pause, board changes and reclaim can run in a single PTB (see [04](04_subdao_hierarchy.md) §5).

### 2.7 Multi-PTB Migration Window → Resolved

**Original risk:** Competing proposals could interfere during multi-batch asset migration.

**Resolution:** `OUStatus = Migrating` blocks every proposal type except `TransferAssets`, and the bypass path requires `Active`. The old OU is governance-locked.

### 2.8 Inert OU Persistence → Resolved

**Original risk:** Old OUs remained on-chain with potentially exploitable governance.

**Resolution:** `ou::destroy` (permissionless) deletes the OU and its companion objects once it is `Migrating` and its vaults are empty.

### 2.9 Cross-Type Request Reuse → Resolved (ROAD-39, ARMATURE-22 – 29)

**Original risk:** Framework mutators were generic over `P`, so a request for any type (say `UpdateMetadata`, 50%) could call any mutator (`set_board_governance`, `withdraw`).

**Resolution:** Each request carries its type's permission bits from mint time, and every framework mutator checks its bit (`proposal::EPermissionDenied`). Framework types hold fixed bits. `gate_tests.move` has a denial test per gated mutator, and `scripts/check_request_gates.py` fails CI on an ungated one.

### 2.10 Ticket Holder Chooses the Arguments → Resolved (ROAD-39)

**Original risk:** Whoever held a ticket could hand its request to a mutator with arguments of their choosing. The executor of an approved payment could withdraw the whole treasury under `TREASURY_WITHDRAW`. An autojoin player could add any address under `BOARD_ADD`. `TransferAssets` handed the withdrawn coins and caps to the executor.

**Resolution:** `ticket_request` and `discharge` require `Permit<P>`, so only `P`'s own module can spend or close its ticket, and it spends the request with arguments read from the approved payload. Handlers for framework types moved into the framework. `TransferAssets` became a hot potato that moves each listed asset straight to the payload's targets.

### 2.11 `VAULT_BORROW` Reaching Unrelated Capabilities → Resolved (ROAD-39)

**Original risk:** A type allowed to borrow one capability (a `MintCoin<T>` borrowing `TreasuryCap<T>`) could borrow any other in the same vault: the `UpgradeCap`, a `SubOUControl`.

**Resolution:** `ProposalConfig.borrow_scope` lists the capability types a request may borrow or loan; the vault checks it after the bit (`EBorrowScopeDenied`). A scope change is a grant under the same rules as bits.

### 2.12 Open Bypass Minting → Resolved (ARMATURE-21, ARMATURE-31)

**Original risk:** `borrow_external_cap` is public and `ticket_from_cap` does not check the sender, so anyone could mint a bypass ticket with a payload of their choosing. Once an OU enabled `MintAllowance<T>` as a bypass type, anyone could mint.

**Resolution:** `ticket_from_cap` takes `Permit<P>`, so only `P`'s module can mint a bypass ticket, and its mint entry authenticates the caller first. The `ExternalExecutionCap` is the OU's opt-in, not a bearer credential. `MintAllowance<T>` is minted only by `currency_ops::mint_allowance_bypass`, which checks a board-voted minter allowlist and per-call cap (`ConfigureMintAllowance<T>`).

### 2.13 No-Vote Path to the Authority Graph → Resolved (ROAD-39)

**Original risk:** A bypass type granted `TYPE_ADMIN`, `MIGRATE`, `VAULT_EXTRACT` or `FREEZE`, now or by a later `UpdateProposalConfig`, would let a path with no vote change who may do what.

**Resolution:** `external_execution::bypass_forbidden_bits` are refused when the bypass is enabled and again at every `ticket_from_cap` (`EBypassForbiddenBits`).

### 2.14 Type-Key Spoofing → Resolved (ARMATURE-9)

**Original risk:** Submission and execution named a type by a caller-supplied string key, decoupled from the payload's Move type, so a payload could run under another type's config.

**Resolution:** The registry is keyed by the payload's canonical `TypeName`; `P` selects the slot on every path. Display keys are labels with no authority.

### 2.15 Freeze Evasion → Resolved (ARMATURE-15)

**Original risk:** Freezes keyed by display key could be sidestepped by disabling and re-enabling a type under a new key, and could not target one instantiation of a generic type.

**Resolution:** Freezes are keyed by `TypeName` and checked with `assert_not_frozen<P>` on the two-PTB, atomic, bypass and composite paths, against the executing OU's own freeze (§2.20).

### 2.16 Stale Approvals → Resolved (ARMATURE-12)

**Original risk:** A passed proposal stayed executable forever, and a late vote could pass an expired proposal and open a fresh execution window.

**Resolution:** Voting closes at `created_at + expiry_ms` (`EVotingClosed`). A passed proposal executes only within `passed_at + execution_delay_ms + expiry_ms` (`EExecutionWindowClosed`). Anyone may delete an expired proposal (`delete_expired_proposal`). Execution deletes the proposal, which is also the replay protection.

### 2.17 Unbounded Object Growth → Resolved (ARMATURE-9, ARMATURE-11, ARMATURE-13)

**Original risk:** The OU root grew with every enabled type and board member, and each proposal copied the roster, so every transaction rewrote a growing object. Single-PTB executions left undeletable audit objects.

**Resolution:** Type slots are dynamic fields; the roster is a versioned `Table`; proposals record `snapshot_version`. Single-PTB executions create no object.

### 2.18 Handlers Trusting Caller-Chosen Objects → Resolved (ROAD-39)

**Original risk:** `execute_mint_coin` / `execute_mint_allowance` deposited into any treasury passed in, and `execute_propose_upgrade` returned the raw `UpgradeCap` to the caller.

**Resolution:** The treasury is checked against the request's OU, and the `UpgradeCap` stays inside a `PendingUpgrade` hot potato until `commit_upgrade` returns it to the vault.

### 2.19 Forged `SubOUControl` → Resolved (ARMATURE-37)

**Original risk:** `create_subou_control` accepted any `subou_id`, and `privileged_submit` / `privileged_extract` compared only `control.subou_id` with the target. Any OU could mint a control naming another OU and drive or drain it; a spun-out SubOU's old control kept working.

**Resolution:** `controller::assert_registered_control` also requires the control to be the target's `controller_cap_id` (`controller::ENotController`). `privileged_submit` and the public `controller::privileged_extract` call it; `capability_vault::privileged_extract` and `create_subou_control` are `public(package)`. `clear_controller` at spin-out retires the old control.

### 2.20 Foreign Freeze Object → Resolved (ARMATURE-38)

**Original risk:** `assert_not_frozen<P>` did not check which OU the freeze object belonged to, so an executor could pass another OU's unfrozen `EmergencyFreeze` and run a frozen type.

**Resolution:** `assert_not_frozen<P>(freeze, ou_id, clock)` aborts `emergency::EOUMismatch` unless the freeze is the executing OU's, on the two-PTB, atomic, bypass and composite-step paths.

### 2.21 Unscoped Cross-OU Capability Receive → Resolved (ARMATURE-39)

**Original risk:** `capability_vault::receive_cap` was public and did not check the receiving OU, so any request carrying `VAULT_EXTRACT` could push caps into any vault, and `TransferCapToSubOU` could target an OU that was not the sender's SubOU.

**Resolution:** `receive_cap` is `public(package)`; its framework callers (SpinOutSubOU, TransferAssets) tie the sender to the target themselves. Parent→child moves go through `controller::receive_cap_from_controller`, which requires the sender's vault to hold the SubOU's registered control; `TransferCapToSubOU` uses it. Other cross-OU moves use `receive_cap_authorized`, which needs a request from both sides.

### 2.22 Composite Steps Against Another OU → Resolved (ARMATURE-40)

**Original risk:** `begin_pipeline` and `advance_step` did not bind the `OU` argument to the ticket or pipeline, so a step could take another OU's type config and bits. Steps also ran after the OU was paused or the step's type was disabled.

**Resolution:** `begin_pipeline` and `advance_step` assert the OU (`composite::EOUIdMismatch`); each step also checks `EExecutionPaused`, `EControllerPaused` and `ETypeNotEnabled`.

---

## 3. Accepted Risks

### 3.1 No Balance Validation at Proposal Creation

**Risk:** `SendCoin` proposals can be created for amounts exceeding treasury balance, wasting governance bandwidth.

**Mitigation:** `propose_threshold` limits who can create proposals. Board governance (small trusted set) minimizes griefing surface. PTB atomicity prevents fund loss — failed execution reverts cleanly.

**Status:** Accepted for Board governance.

### 3.2 Concurrent Proposal Race Conditions

**Risk:** Multiple proposals targeting the same balance can produce first-come-first-served execution order.

**Mitigation:** This is a coordination concern, not a security vulnerability. No funds can be lost. Off-chain coordination is sufficient for Board OUs.

### 3.3 No Vote Change / No Proposal Cancellation

**Risk:** Votes are write-once. Proposals cannot be cancelled once created.

**Mitigation:** `execution_delay_ms` provides post-passage cooling-off. Higher `approval_threshold` requires more consensus. Uncancelled proposals expire, and anyone can then delete them.

### 3.4 The Atomic Path Removes the Reaction Window

**Risk:** `submit_vote_execute` lets one member submit and execute in a single PTB when their vote alone passes, with no window for other members to vote NO or for the freeze admin to react. Default configs have `execution_delay_ms = 0`.

**Mitigation:** Configure governance-sensitive types (board changes, config changes, type enablement) with `execution_delay_ms > 0`, which statically rules the atomic path out for them, and a quorum one vote cannot meet. Making non-zero delays the default is a proposed ADR, not implemented.

### 3.5 Extension Package Upgrade Authority

**Risk:** An upgrade can rewrite how every type defined in a package spends its requests, and an OU cannot pin a package version. Whoever holds an extension's `UpgradeCap` can use every bit and scope any OU has granted that package's types.

**Mitigation:** Keep the `UpgradeCap` in an OU vault governed by `ProposeUpgrade`, or make the package immutable per release. An 80% enable vote is a vote on that package's code and its upgrade authority.

### 3.6 Bits Bound What, Not How Much

**Risk:** `TREASURY_WITHDRAW` reaches every coin at any amount; `VAULT_BORROW` reaches every cap type in the scope. A bug in a type's own handler can use all of its type's grant.

**Mitigation:** Grant only the bits and scope a handler needs. Amount limits are handler logic (`spend_guard`, `SendSmallPayment`'s rolling cap, `MintAllowance`'s per-call cap).

### 3.7 Bypass Types Are Only as Safe as Their Mint Entry

**Risk:** The framework cannot see what a bypass type's mint entry checks before calling `ticket_from_cap`.

**Mitigation:** `EnableBypassType` needs 80% on actual vote weights and is a vote on that module's code. Bypass-safe bits and borrow scope limit the damage a flawed mint entry can do.

### 3.8 Freeze vs. Execution Window

**Risk:** With the default 7-day expiry and 7-day maximum freeze, freezing a type right after one of its proposals passes can run out that proposal's execution window.

**Status:** Accepted (ARMATURE-12). The proposal must be resubmitted after the freeze.

### 3.9 Saturating Deadlines

**Risk:** `new_config` has no upper bound on `expiry_ms` or `execution_delay_ms`; deadlines saturate at `u64::MAX`, so such a config never expires and its passed proposals can only leave the chain by execution.

**Status:** Accepted by design.

### 3.10 Re-enabled Types Lose Cooldown State

**Risk:** `disable_proposal_type` removes the slot's last-executed time, so a re-enabled type's first execution is not rate-limited.

**Status:** Accepted: re-enabling needs an 80% `EnableProposalType` or `EnableBypassType` vote.

---

## 4. Charter-Specific Threats

### 4.1 Metadata Substitution

**Attack:** A proposer submits `UpdateMetadata` with a CID pointing at a document that differs from what they describe, hoping voters approve without reading it.

**Mitigations:**
- **Content addressing.** An IPFS CID pins the content: the approved CID is exactly the document that will be referenced. UI tooling should fetch and display the document at the proposed CID before voting.
- **Governance parameters.** OUs that treat the document as their constitution should raise `UpdateMetadata`'s threshold, delay and cooldown.
- **Audit trail.** Every change emits `MetadataUpdated` with the new CID.

### 4.2 Planned Walrus Charter

The planned Walrus-backed charter ([05 Charter](05_charter.md) Part B) adds threats that apply only once it exists. **Blob substitution** is handled by the content hash, UI verification and a long execution delay. **Rollback** is handled by version monotonicity, which makes a rollback visible as a new version with old content. **Storage expiry** is handled by `RenewCharterStorage`, hash-verified re-upload and off-chain archival.

---

## 5. General Protocol Guarantees

The protocol is designed to provide these guarantees:

1. **No admin keys over assets or governance.** The only admin-like capability, `FreezeAdminCap`, is held by an address or a vault. It can freeze and unfreeze proposal types (each freeze expires on its own) but cannot execute, access the treasury, or change governance.
2. **Execution requires an authorization path.** Every governed mutation (roster, type registry, lifecycle, treasury withdrawals, vault custody, charter, freeze governance) requires an `ExecutionRequest`. That request comes from a vote, from a bypass type the OU opted into by an 80% vote, or from the controller override for SubOUs (`privileged_submit`, which requires the target's registered `SubOUControl`). The exceptions are permissionless deposits and claims, voting, deleting expired proposals, the freeze admin's own freeze and unfreeze, and `controller::privileged_extract` with the registered `SubOUControl`.
3. **A request does only what its type was granted.** Its permission bits and borrow scope come from its type's slot, and only its type's own module can spend it.
4. **Atomic execution.** Every proposal execution is atomic (PTB). Partial execution is impossible. Failed execution reverts cleanly.
5. **Blast radius isolation.** Each OU's treasury and capabilities are independent shared objects, and gated mutators check the request's OU. Capabilities enter an OU's vault from another OU only with both OUs' requests (`receive_cap_authorized`), from its registered controller (`receive_cap_from_controller`), or through the framework's SpinOutSubOU / TransferAssets handlers. Assets leave an OU only on its own request or, for a SubOU, through its controller's `SubOUControl`.
6. **On-chain auditability.** Every proposal, including single-PTB executions that create no object, emits `ProposalCreated`, `ProposalPayloadCreated` (with the payload's BCS bytes) and `ProposalExecuted` or `ProposalExpired`. On the vote path every payload is visible before voting and every vote is recorded. Handlers emit their own events for what they changed.
