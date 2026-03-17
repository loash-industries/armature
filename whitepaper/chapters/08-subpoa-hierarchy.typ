= Sub-POA Hierarchy and Composition

#import "../lib/template.typ": aside, principle

Organizations are not flat. Growth creates internal structure: departments, task forces, working groups. Armature models this through Sub-POAs --- full POA instances in a parent-child relationship with a controlling POA.

== The Sub-POA as a Full Primitive

A Sub-POA is not a lightweight proxy or a permission scope. It is a complete POA instance with its own treasury, capability vault, charter, emergency freeze, governance configuration, and proposal set.

The only structural difference from a top-level POA is the presence of a `controller_cap_id`. This is a reference to the `Sub-POAControl` capability held by the parent.

A Sub-POA can do everything a top-level POA can do, _within the boundaries set by its controller_. It receives deposits, passes proposals, manages capabilities, and amends its own charter. It operates with genuine autonomy while remaining accountable to the parent.

== Controller Authority

The parent POA exercises authority through the `Sub-POAControl` capability. It is stored in the parent's CapabilityVault and accessed only through governance proposals.

The controller can:

+ *Replace the board instantly* --- via `privileged_submit`, the parent can create a `SetBoard` proposal in the Sub-POA that enters `Passed` status directly, bypassing the Sub-POA's voting process. This is the last resort for a rogue department.

+ *Pause execution* --- `PauseSub-POAExecution` blocks all proposal execution in the Sub-POA. Combined with board replacement, this enables atomic recovery from compromised governance.

+ *Reclaim capabilities* --- `privileged_extract` allows the controller to recover any capability from the Sub-POA's vault. Delegated authority can always be recovered.

+ *Grant independence* --- `SpinOutSub-POA` destroys the `Sub-POAControl` capability, severing the parent-child relationship permanently. The former Sub-POA becomes a fully independent top-level POA.

#principle[Hierarchy Blocklist][
  Controlled Sub-POAs cannot enable `CreateSub-POA`, `SpinOutSub-POA`, or `SpawnPOA`. A department cannot unilaterally create its own sub-departments or declare independence. These capabilities require the parent to explicitly grant them through spinout. This prevents hierarchical leaks and ensures that organizational structure is always a deliberate governance decision.
]

== Atomic Recovery

When a Sub-POA's governance is compromised, the parent can recover it in a single transaction.

```
1. PauseSub-POAExecution    // freeze all activity
2. SetBoard                // replace compromised board
3. privileged_extract      // recover sensitive capabilities
4. UnpauseSub-POAExecution  // resume operations
```

All four steps execute in a single PTB. There is no window between the pause and the board replacement where the compromised board could act. The recovery is instantaneous and complete.

== Multi-Level Hierarchies

Sub-POAs can be nested to arbitrary depth. A parent POA can transfer its `Sub-POAControl` for a grandchild to a child Sub-POA, creating delegation chains.

#figure(
  align(center)[
    ```
    Top-Level POA
    +-- Engineering Sub-POA (controls Frontend)
    |   +-- Frontend Sub-POA
    +-- Logistics Sub-POA
    +-- Operations Sub-POA
    ```
  ],
  caption: [Multi-level hierarchy with delegated control.],
)

`Sub-POAControl` can only be transferred downward --- the holder must itself control the target. This prevents lateral transfers that would create governance confusion.

== From Department to Sovereignty

The Sub-POA lifecycle models a natural trajectory.

+ A tribe identifies a need for specialization and creates a Sub-POA as a department.
+ The department develops its own expertise, culture, and operational patterns.
+ Over time, the department may grow large enough to warrant independence.
+ The parent passes a `SpinOutSub-POA` proposal, granting full sovereignty.
+ The former Sub-POA is now a top-level POA, free to create its own Sub-POAs, join federations, and forge independent relationships.

The protocol does not mandate this path. It provides the mechanisms for any trajectory the governance chooses.
