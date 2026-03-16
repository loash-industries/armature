= SubDAO Hierarchy and Composition

#import "../lib/template.typ": aside, principle

Organizations are not flat. A tribe that grows beyond a handful of members inevitably develops internal structure: departments, task forces, working groups, each with their own scope of responsibility and degree of autonomy. Armature models this structure through SubDAOs --- full DAO instances that exist in a parent-child relationship with a controlling DAO.

== The SubDAO as a Full Primitive

A SubDAO is not a lightweight proxy or a permission scope. It is a complete DAO instance with its own treasury, capability vault, charter, emergency freeze, governance configuration, and proposal set. The only structural difference from a top-level DAO is the presence of a `controller_cap_id` --- a reference to the `SubDAOControl` capability held by the parent.

This design choice has a critical implication: a SubDAO can do everything a top-level DAO can do, _within the boundaries set by its controller_. It can receive deposits, pass proposals, manage capabilities, and amend its own charter. It operates with genuine autonomy in its domain while remaining accountable to the parent.

== Controller Authority

The parent DAO's authority over its SubDAO is exercised through the `SubDAOControl` capability, stored in the parent's CapabilityVault and accessed only through governance proposals.

The controller can:

+ *Replace the board instantly* --- via `privileged_submit`, the parent can create a `SetBoard` proposal in the SubDAO that enters `Passed` status directly, bypassing the SubDAO's voting process. This is the nuclear option for a rogue department.

+ *Pause execution* --- `PauseSubDAOExecution` blocks all proposal execution in the SubDAO. Combined with board replacement, this enables atomic recovery from compromised governance.

+ *Reclaim capabilities* --- `privileged_extract` allows the controller to recover any capability from the SubDAO's vault. This ensures that delegated authority can always be recovered.

+ *Grant independence* --- `SpinOutSubDAO` destroys the `SubDAOControl` capability, severing the parent-child relationship permanently. The former SubDAO becomes a fully independent top-level DAO.

#principle[Hierarchy Blocklist][
  Controlled SubDAOs cannot enable `CreateSubDAO`, `SpinOutSubDAO`, or `SpawnDAO`. A department cannot unilaterally create its own sub-departments or declare independence. These capabilities require the parent to explicitly grant them through spinout. This prevents hierarchical leaks and ensures that organizational structure is always a deliberate governance decision.
]

== Atomic Recovery

The combination of pause, board replacement, and capability reclaim enables a powerful recovery pattern when a SubDAO's governance is compromised:

```
1. PauseSubDAOExecution    // freeze all activity
2. SetBoard                // replace compromised board
3. privileged_extract      // recover sensitive capabilities
4. UnpauseSubDAOExecution  // resume operations
```

All four steps execute in a single PTB --- atomically. There is no window between the pause and the board replacement where the compromised board could act. There is no race condition between reclaiming a capability and the SubDAO attempting to use it. The recovery is instantaneous and complete.

== Multi-Level Hierarchies

SubDAOs can be nested to arbitrary depth. A parent DAO can transfer its `SubDAOControl` for a grandchild SubDAO to a child SubDAO, creating delegation chains:

#figure(
  align(center)[
    ```
    Top-Level DAO
    +-- Engineering SubDAO (controls Frontend)
    |   +-- Frontend SubDAO
    +-- Logistics SubDAO
    +-- Operations SubDAO
    ```
  ],
  caption: [Multi-level hierarchy with delegated control.],
)

The constraint is that `SubDAOControl` can only be transferred downward --- the holder must itself control the target. This prevents lateral transfers that would create governance confusion.

== From Department to Sovereignty

The SubDAO lifecycle models a natural organizational trajectory:

+ A tribe identifies a need for specialization and creates a SubDAO as a department.
+ The department develops its own expertise, culture, and operational patterns.
+ Over time, the department may grow large enough to warrant independence.
+ The parent passes a `SpinOutSubDAO` proposal, granting full sovereignty.
+ The former SubDAO is now a top-level DAO, free to create its own SubDAOs, join federations, and forge independent relationships.

This lifecycle mirrors how real organizations spawn subsidiaries that eventually become independent entities. The protocol does not mandate a trajectory --- it provides the mechanisms for any path the governance chooses.
