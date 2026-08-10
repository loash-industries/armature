= Security and Emergency Short Circuits

#import "../lib/template.typ": aside, principle

Armature's security is defense-in-depth. Six independent layers, each addressing distinct threats. No single layer is sufficient alone. Their composition provides the guarantees.

== Type System as Foundation

Authorization tokens produced during proposal execution cannot be forged, stored, copied, or discarded. The type system enforces this at compile time --- not by convention, but by construction. A malicious contract cannot fabricate authorization because the language itself makes it impossible.

== Governance Thresholds

Every action carries an approval threshold, a quorum requirement, and timing constraints. Critical actions carry higher bars --- expanding the DAO's vocabulary requires a two-thirds supermajority (a 66% floor), while changing a proposal type's own governance parameters, or enabling the external-authorization bypass, requires an 80% supermajority.

These floors are framework-enforced constants. Governance cannot lower them below the protocol minimums. Governance cannot be captured through its own mechanisms.

== Timing Controls

Three timing mechanisms prevent velocity-based attacks.

- *Execution delay* --- a mandatory waiting period after passage. Even if an attacker controls the board, the delay gives the minority time to observe and invoke emergency measures.
- *Cooldown* --- a minimum interval between executions of the same type. Prevents rapid-fire vault drains or governance reconfiguration.
- *Expiry* --- proposals that do not pass within their voting window are automatically expired. Stale proposals cannot be resurrected.

== Emergency Circuit Breaker

Individual proposal types can be frozen while all other DAO operations continue unaffected. The freeze is targeted, not total.

Freezing is deliberately asymmetric. A freeze is triggered fast, by holding the `FreezeAdminCap` --- issued to the DAO at creation and transferable to or held under governance custody --- so a trusted responder can halt a suspect proposal type without waiting for a vote. Undoing a freeze is slower and always collective: unfreezing, transferring the admin cap, and changing freeze configuration each require a governance proposal. Freezes auto-expire after a configurable duration (7 days by default), and the unfreeze and transfer-admin proposal types are permanently exempt from freezing, so the emergency system can never permanently lock out governance.

== Hierarchy Controls

The organizational hierarchy provides isolation between parent and child DAOs.

A parent can pause a controlled child's execution, add or remove its board members, and reclaim delegated capabilities. Each is an atomic governance action on the parent side, and several can be bundled into a single composite proposal --- pause, reshuffle the board, and reclaim a capability in one vote and one execution. Controlled Sub-DAOs cannot create their own Sub-DAOs, spawn successors, or declare independence: those hierarchy-altering proposal types are framework-blocked for a controlled DAO and can only be unlocked when the parent spins it out.

Delegation does not mean loss of control.

== Blast Radius Isolation

Each DAO holds its own vaults as independent objects. There is no shared state between DAOs at the framework level.

A compromised DAO cannot access another DAO's resources. Cross-DAO interaction requires governance authorization on both sides. A vulnerability in one organization cannot propagate to others.

== Protocol Guarantees

These layers compose into unconditional invariants:

+ *No admin keys.* No entity holds privileged access outside the governance system.
+ *No backdoors.* All authority is rooted in governance. The two non-vote execution paths --- a parent's override of a Sub-DAO it controls, and the opt-in external-authorization bypass --- are not escape hatches: the first exists only for a DAO the parent already governs, and the second must be switched on by an 80% supermajority proposal and can be frozen or disabled the same way.
+ *Atomic execution.* Every proposal executes as a single transaction. If any step fails, everything reverts.
+ *Blast radius isolation.* A vulnerability in one DAO cannot reach another.
+ *On-chain auditability.* Every state change, every vote, every amendment is recorded permanently.
