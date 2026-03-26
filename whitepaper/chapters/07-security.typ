= Security and Emergency Short Circuits

#import "../lib/template.typ": aside, principle

Armature's security is defense-in-depth. Six independent layers, each addressing distinct threats. No single layer is sufficient alone. Their composition provides the guarantees.

== Type System as Foundation

Authorization tokens produced during proposal execution cannot be forged, stored, copied, or discarded. The type system enforces this at compile time --- not by convention, but by construction. A malicious contract cannot fabricate authorization because the language itself makes it impossible.

== Governance Thresholds

Every action carries an approval threshold, a quorum requirement, and timing constraints. Critical actions carry higher bars --- expanding the DAO's vocabulary requires a supermajority, changing governance rules requires near-unanimity.

These floors are framework-enforced. Governance cannot lower them below the protocol minimums. Governance cannot be captured through its own mechanisms.

== Timing Controls

Three timing mechanisms prevent velocity-based attacks.

- *Execution delay* --- a mandatory waiting period after passage. Even if an attacker controls the board, the delay gives the minority time to observe and invoke emergency measures.
- *Cooldown* --- a minimum interval between executions of the same type. Prevents rapid-fire vault drains or governance reconfiguration.
- *Expiry* --- proposals that do not pass within their voting window are automatically expired. Stale proposals cannot be resurrected.

== Emergency Circuit Breaker

Individual proposal types can be frozen while all other DAO operations continue unaffected. The freeze is targeted, not total.

The freeze capability is itself governed --- it lives in the DAO's vault and can only be accessed through a proposal. Freezes auto-expire after a configurable duration. And the ability to unfreeze can never itself be frozen, ensuring the emergency system cannot permanently lock out governance.

== Hierarchy Controls

The organizational hierarchy provides isolation between parent and child DAOs.

A parent can pause a compromised child's execution instantly, replace its board, and reclaim delegated capabilities --- all in a single atomic transaction. Controlled Sub-DAOs cannot create their own Sub-DAOs or declare independence without explicit authorization from the parent.

Delegation does not mean loss of control.

== Blast Radius Isolation

Each DAO holds its own vaults as independent objects. There is no shared state between DAOs at the framework level.

A compromised DAO cannot access another DAO's resources. Cross-DAO interaction requires governance authorization on both sides. A vulnerability in one organization cannot propagate to others.

== Protocol Guarantees

These layers compose into unconditional invariants:

+ *No admin keys.* No entity holds privileged access outside the governance system.
+ *No backdoors.* All authority flows through proposals. There is no escape hatch.
+ *Atomic execution.* Every proposal executes as a single transaction. If any step fails, everything reverts.
+ *Blast radius isolation.* A vulnerability in one DAO cannot reach another.
+ *On-chain auditability.* Every state change, every vote, every amendment is recorded permanently.
