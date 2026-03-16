# 06 — Security Model and Threat Analysis

> **Scope**: This document covers hackathon-scope security concerns. For federation-specific threats, see [stretch/01 Federation](stretch/01_federation.md). For project-funding threats, see [stretch/04 Project Funding](stretch/04_project_funding.md).

## 1. Security Philosophy

The protocol's security model is built on **defense-in-depth** — no single mechanism is relied upon exclusively. Security arises from the interaction of multiple reinforcing layers:

| Layer | Mechanism | Protects Against |
|---|---|---|
| **Type system** | Hot potatoes (`ExecutionRequest`, `CapLoan`), `public(friend)` visibility, phantom type tags | Forgery, unauthorized access, capability theft |
| **Governance thresholds** | Per-type `approval_threshold`, 66% enable floor, 80% self-referential floor | Privilege escalation, config weakening, minority capture |
| **Timing controls** | `execution_delay_ms`, `cooldown_ms`, `expiry_ms` | Flash attacks, reaction-time attacks, rapid-fire drains |
| **Emergency circuit breaker** | `EmergencyFreeze` + `FreezeAdminCap`, auto-expiry, governance override | Discovered vulnerabilities, compromised members, active attacks |
| **Hierarchy controls** | `SubDAOControl`, `controller_cap_id`, `controller_paused`, blocklist enforcement | Rogue SubDAOs, lateral capability leaks, unauthorized independence |
| **Atomic reclaim** | Pause → SetBoard → privileged_extract → unpause (single PTB) | Race conditions, preemptive capability transfer |
| **Blast radius isolation** | Separate `TreasuryVault` per DAO, separate `CapabilityVault` per DAO | Cross-DAO contamination, cascading treasury drain |

---

## 2. Resolved Threats (from Original Security Review)

These threats were identified during the original design review and resolved with protocol changes:

### 2.1 No Emergency Recovery → Resolved

**Original risk:** No mechanism to pause operations during a vulnerability disclosure.

**Resolution:** `EmergencyFreeze` system with `FreezeAdminCap`. Cap holder can freeze specific proposal types for up to `max_freeze_duration_ms`. Auto-expiry prevents permanent lockout. `TransferFreezeAdmin` and `UnfreezeProposalType` are immune to freezing.

### 2.2 Permissionless Execution → Resolved

**Original risk:** Anyone could call `execute()` on passed proposals, enabling front-running.

**Resolution:** Executor eligibility restricted to governance participants (board members for Board DAOs).

### 2.3 `EnableProposalType` Escalation → Resolved

**Original risk:** Enabling dangerous types with weak governance parameters.

**Resolution:** `EnableProposalType` now requires mandatory `ProposalConfig` (atomic enablement + config) and enforces a 66% approval floor at execution.

### 2.4 Recursive Config Weakening → Resolved

**Original risk:** `UpdateProposalConfig` used to lower its own thresholds, then cascading to weaken all types.

**Resolution:** 80% super-majority floor when `UpdateProposalConfig` targets its own `TypeName`.

### 2.5 `is_managed` Flag Desync → Resolved

**Original risk:** Boolean flag could desync from actual `SubDAOControl` existence.

**Resolution:** Replaced `is_managed: bool` with `controller_cap_id: Option<ID>`, directly referencing the control capability.

### 2.6 No Capability Reclaim Path → Resolved

**Original risk:** Delegated capabilities required a two-step process with a race condition window.

**Resolution:** Atomic reclaim via pause → `SetBoard` → `privileged_extract` → unpause, all in a single PTB. Zero-time pause.

### 2.7 Multi-PTB Migration Window → Resolved

**Original risk:** Competing proposals could interfere during multi-batch asset migration.

**Resolution:** `DAOStatus = Migrating` blocks all proposal types except `TransferAssets`. Old DAO is governance-locked.

### 2.8 Inert DAO Persistence → Resolved

**Original risk:** Old DAOs remained on-chain with potentially exploitable governance.

**Resolution:** `dao::destroy` permanently deletes all companion objects after migration completes.

### 2.9 `TransferCapToSubDAO` Ambiguity → Resolved

**Original risk:** Ambiguous constraint allowed unintended lateral capability transfers.

**Resolution:** Unambiguous rule: transferring DAO must hold `SubDAOControl` for the target SubDAO.

---

## 3. Accepted Risks

### 3.1 No Balance Validation at Proposal Creation

**Risk:** `SendCoin` proposals can be created for amounts exceeding treasury balance, wasting governance bandwidth.

**Mitigation:** `propose_threshold` limits who can create proposals. Board governance (small trusted set) minimizes griefing surface. PTB atomicity prevents fund loss — failed execution reverts cleanly.

**Status:** Accepted for Board governance (MVP).

### 3.2 Concurrent Proposal Race Conditions

**Risk:** Multiple proposals targeting the same balance can produce first-come-first-served execution order.

**Mitigation:** This is a coordination concern, not a security vulnerability. No funds can be lost. Off-chain coordination is sufficient for Board DAOs.

### 3.3 No Vote Change / No Proposal Cancellation

**Risk:** Votes are write-once. Proposals cannot be cancelled once created.

**Mitigation:** `execution_delay_ms` provides post-passage cooling-off. Higher `approval_threshold` requires more consensus. Uncancelled proposals expire harmlessly.

---

## 4. Charter-Specific Threats

### 4.1 Blob Integrity / Content Substitution

**Attack:** An attacker uploads a different document to Walrus and proposes `AmendCharter` with the new blob ID, hoping voters approve without reading the actual content.

**Mitigations:**
- **Content hash verification.** `AmendCharter` includes `content_hash`. Voters should fetch the blob and verify `SHA-256(content) == content_hash` before voting. UI tooling should automate this verification and display the charter content inline.
- **On-chain audit trail.** `amendment_history` records every blob ID transition. Any discrepancy between what was proposed and what was stored is detectable.
- **Social defense.** Charter amendments should use high `execution_delay_ms` (e.g., 48 hours), giving the full membership time to review content before execution.

### 4.2 Rollback Attack

**Attack:** An attacker proposes `AmendCharter` with a `new_blob_id` pointing to a previous version of the charter, effectively rolling back recent amendments.

**Mitigations:**
- **Version monotonicity.** `Charter.version` always increments. A rollback-via-amendment is technically a new version with old content — it is visible as such in the `amendment_history`.
- **Summary field.** `AmendCharter` includes a `summary` field. A rollback attempt without a clear justification in the summary would be voted down by an attentive board.
- **Not a protocol-level concern.** If governance genuinely approves a rollback, the protocol should permit it.

### 4.3 Storage Expiry

**Attack:** A charter's Walrus blob expires. The charter content becomes inaccessible, though the on-chain `Charter` object (with `content_hash`) remains.

**Mitigations:**
- **`RenewCharterStorage`** proposal type allows updating `current_blob_id` without changing content. Low-threshold, routine maintenance.
- **Content hash recovery.** Anyone with a copy of the charter content can re-upload to Walrus and propose renewal. The hash guarantees authenticity.
- **Off-chain archival.** Long-lived DAOs should maintain backup copies of charter content.

---

## 5. General Protocol Guarantees

These guarantees hold across all threat scenarios:

1. **No admin keys.** The only admin-like capability (`FreezeAdminCap`) can pause but never execute, access treasury, or change governance. It auto-expires.
2. **No backdoors.** All authority flows through governance proposals. There is no function that bypasses the proposal system (except `privileged_submit`, which itself requires `SubDAOControl` — a governance-controlled capability).
3. **Atomic execution.** Every proposal execution is atomic (PTB). Partial execution is impossible. Failed execution reverts cleanly.
4. **Blast radius isolation.** Each DAO's treasury and capabilities are independent shared objects. Cross-DAO access requires explicit governance on both sides.
5. **On-chain auditability.** Every state change emits events. Every proposal payload is visible before voting. Every vote is recorded. Every execution is atomic and verifiable.
