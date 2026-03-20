= Security Model

#import "../lib/template.typ": aside, principle

Armature's security is defense-in-depth: six independent layers, each addressing distinct threats. No single layer is sufficient alone. Their composition provides the guarantees.

== Layer 1: Type System Enforcement

The Sui Move type system is the foundation. `ExecutionRequest<P>` and `CapLoan` hot potatoes have no abilities --- they cannot be stored, copied, or dropped. They must be consumed within the same PTB in which they were created.

This is not a convention. It is a compile-time guarantee.

A malicious contract _cannot_ forge an `ExecutionRequest` because the type has no `store` ability and the constructor is `public(friend)`. The attack surface is zero.

== Layer 2: Governance Thresholds

Every action carries an approval threshold, a quorum requirement, and timing constraints. Critical actions carry higher bars.

- `EnableProposalType`: 66% floor (supermajority for capability expansion).
- `UpdateProposalConfig` (self-referential): 80% floor (near-unanimity for governance changes).
- `AmendCharter`: recommended 80% threshold, 48-hour delay, 7-day cooldown.

These floors are _framework-enforced_. A governance proposal cannot lower them below the protocol minimums. Governance cannot be captured through its own mechanisms.

== Layer 3: Timing Controls

Three timing mechanisms prevent velocity-based attacks.

- *Execution delay* --- a mandatory waiting period after passage. Even if an attacker controls the board, the delay gives the minority time to observe and invoke emergency measures.
- *Cooldown* --- a minimum interval between executions of the same type. Prevents rapid-fire treasury drains or governance reconfiguration.
- *Expiry* --- proposals that do not pass within their voting window are automatically expired. Stale proposals cannot be resurrected.

== Layer 4: Emergency Circuit Breaker

Individual proposal types can be frozen while all other POA operations continue unaffected. The freeze is targeted, not total.

#aside[
  The freeze system is itself governed. The `FreezeAdminCap` is stored in the POA's CapabilityVault, accessible only through a governance proposal that loans it temporarily. Freezes auto-expire after a configurable maximum duration. And two types --- `TransferFreezeAdmin` and `UnfreezeProposalType` --- can _never_ be frozen, ensuring that the emergency system cannot be used to permanently lock out governance.
]

== Layer 5: Hierarchy Controls

The Sub-POA hierarchy provides organizational isolation.

- *Controller pause* --- a parent can halt all execution in a child POA instantly.
- *Board replacement* --- a parent can replace a compromised child board without the child's consent.
- *Capability reclaim* --- delegated capabilities can always be recovered.
- *Hierarchy blocklist* --- controlled Sub-POAs cannot create their own Sub-POAs or declare independence without explicit authorization.

Delegation does not mean loss of control.

== Layer 6: Blast Radius Isolation

Each POA has its own TreasuryVault and CapabilityVault as separate shared objects. There is no shared state between POAs at the framework level.

A compromised POA cannot access another POA's treasury. A vulnerability in one proposal handler cannot drain another POA's assets.

Cross-POA interaction requires governance on _both_ sides. The sending POA authorizes the outflow; the receiving POA accepts deposits permissionlessly. This bilateral model prevents supply-chain attacks through the governance layer.

== Protocol Guarantees

These six layers compose into unconditional invariants.

+ *No admin keys.* The only privileged capability is `FreezeAdminCap`, which cannot execute proposals, access the treasury, or modify governance. It can only freeze and unfreeze specific proposal types, and it auto-expires.

+ *No backdoors.* All authority flows through governance proposals. There is no `owner` field, no `admin` role, no escape hatch that bypasses the proposal system.

+ *Atomic execution.* Every proposal execution is a single PTB. If any step fails, the entire transaction reverts. No partial state updates. No interruptible workflows.

+ *Blast radius isolation.* Cross-POA access requires bilateral governance authorization. A vulnerability in one POA cannot propagate to others.

+ *On-chain auditability.* Every state change emits events. Every vote is recorded. Every amendment is logged. The governance history is permanent and tamper-proof.
