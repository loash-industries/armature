= Sub-POA Hierarchy and Composition

#import "../lib/template.typ": aside, principle

Organizations are not flat. A tribe that grows beyond a handful of members inevitably develops internal structure: departments, task forces, working groups, each with their own scope of responsibility and degree of autonomy. Armature models this structure through Sub-POAs --- full POA instances that exist in a parent-child relationship with a controlling POA.

== The Sub-POA as a Full Primitive

A Sub-POA is not a lightweight proxy or a permission scope. It is a complete POA instance with its own treasury, capability vault, charter, emergency freeze, governance configuration, and proposal set. The only structural difference from a top-level POA is the presence of a `controller_cap_id` --- a reference to the `Sub-POAControl` capability held by the parent.

This design choice has a critical implication: a Sub-POA can do everything a top-level POA can do, _within the boundaries set by its controller_. It can receive deposits, pass proposals, manage capabilities, and amend its own charter. It operates with genuine autonomy in its domain while remaining accountable to the parent.

== Controller Authority

The parent POA's authority over its Sub-POA is exercised through the `Sub-POAControl` capability, stored in the parent's CapabilityVault and accessed only through governance proposals.

The controller can:

+ *Replace the board instantly* --- via `privileged_submit`, the parent can create a `SetBoard` proposal in the Sub-POA that enters `Passed` status directly, bypassing the Sub-POA's voting process. This is the nuclear option for a rogue department.

+ *Pause execution* --- `PauseSub-POAExecution` blocks all proposal execution in the Sub-POA. Combined with board replacement, this enables atomic recovery from compromised governance.

+ *Reclaim capabilities* --- `privileged_extract` allows the controller to recover any capability from the Sub-POA's vault. This ensures that delegated authority can always be recovered.

+ *Grant independence* --- `SpinOutSub-POA` destroys the `Sub-POAControl` capability, severing the parent-child relationship permanently. The former Sub-POA becomes a fully independent top-level POA.

#principle[Hierarchy Blocklist][
  Controlled Sub-POAs cannot enable `CreateSub-POA`, `SpinOutSub-POA`, or `SpawnPOA`. A department cannot unilaterally create its own sub-departments or declare independence. These capabilities require the parent to explicitly grant them through spinout. This prevents hierarchical leaks and ensures that organizational structure is always a deliberate governance decision.
]

== Atomic Recovery

The combination of pause, board replacement, and capability reclaim enables a powerful recovery pattern when a Sub-POA's governance is compromised:

```
1. PauseSub-POAExecution    // freeze all activity
2. SetBoard                // replace compromised board
3. privileged_extract      // recover sensitive capabilities
4. UnpauseSub-POAExecution  // resume operations
```

All four steps execute in a single PTB --- atomically. There is no window between the pause and the board replacement where the compromised board could act. There is no race condition between reclaiming a capability and the Sub-POA attempting to use it. The recovery is instantaneous and complete.

== Multi-Level Hierarchies

Sub-POAs can be nested to arbitrary depth. A parent POA can transfer its `Sub-POAControl` for a grandchild Sub-POA to a child Sub-POA, creating delegation chains:

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

The constraint is that `Sub-POAControl` can only be transferred downward --- the holder must itself control the target. This prevents lateral transfers that would create governance confusion.

== From Department to Sovereignty

The Sub-POA lifecycle models a natural organizational trajectory:

+ A tribe identifies a need for specialization and creates a Sub-POA as a department.
+ The department develops its own expertise, culture, and operational patterns.
+ Over time, the department may grow large enough to warrant independence.
+ The parent passes a `SpinOutSub-POA` proposal, granting full sovereignty.
+ The former Sub-POA is now a top-level POA, free to create its own Sub-POAs, join federations, and forge independent relationships.

This lifecycle mirrors how real organizations spawn subsidiaries that eventually become independent entities. The protocol does not mandate a trajectory --- it provides the mechanisms for any path the governance chooses.
