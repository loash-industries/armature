= Sub-DAO Hierarchy and Composition

#import "../lib/template.typ": aside, principle

Organizations are not flat. Growth creates internal structure: departments, task forces, working groups. Armature models this through Sub-DAOs --- full DAO instances in a parent-child relationship with a controlling DAO.

== The Sub-DAO as a Full Primitive

A Sub-DAO is not a lightweight proxy or a permission scope. It is a complete DAO instance with its own treasury, capability vault, charter, emergency freeze, governance configuration, and proposal set.

The only structural difference from a top-level DAO is the presence of a `controller_cap_id`. This is a reference to the `Sub-DAOControl` capability held by the parent.

A Sub-DAO can do everything a top-level DAO can do, _within the boundaries set by its controller_. It receives deposits, passes proposals, manages capabilities, and amends its own charter. It operates with genuine autonomy while remaining accountable to the parent.

== Controller Authority

The parent DAO exercises authority through the `Sub-DAOControl` capability. It is stored in the parent's CapabilityVault and accessed only through governance proposals.

The controller can:

+ *Replace the board instantly* --- via `privileged_submit`, the parent can create a `SetBoard` proposal in the Sub-DAO that enters `Passed` status directly, bypassing the Sub-DAO's voting process. This is the last resort for a rogue department.

+ *Pause execution* --- `PauseSub-DAOExecution` blocks all proposal execution in the Sub-DAO. Combined with board replacement, this enables atomic recovery from compromised governance.

+ *Reclaim capabilities* --- `privileged_extract` allows the controller to recover any capability from the Sub-DAO's vault. Delegated authority can always be recovered.

+ *Grant independence* --- `SpinOutSub-DAO` destroys the `Sub-DAOControl` capability, severing the parent-child relationship permanently. The former Sub-DAO becomes a fully independent top-level DAO.

#principle[Hierarchy Blocklist][
  Controlled Sub-DAOs cannot enable `CreateSub-DAO`, `SpinOutSub-DAO`, or `SpawnDAO`. A department cannot unilaterally create its own sub-departments or declare independence. These capabilities require the parent to explicitly grant them through spinout. This prevents hierarchical leaks and ensures that organizational structure is always a deliberate governance decision.
]

== Atomic Recovery

When a Sub-DAO's governance is compromised, the parent can recover it in a single transaction.

+ Pause all Sub-DAO execution --- freeze activity immediately.
+ Replace the compromised board with trusted members.
+ Extract sensitive capabilities back to the parent.
+ Unpause Sub-DAO execution --- resume operations.

All four steps execute in a single PTB. There is no window between the pause and the board replacement where the compromised board could act. The recovery is instantaneous and complete.

== Multi-Level Hierarchies

Sub-DAOs can be nested to arbitrary depth. A parent DAO can transfer its `Sub-DAOControl` for a grandchild to a child Sub-DAO, creating delegation chains.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*DAO*][*Controls*][*Level*],
    [Top-Level DAO], [Engineering, Logistics, Operations], [Root],
    [Engineering Sub-DAO], [Frontend Sub-DAO], [Depth 1],
    [Frontend Sub-DAO], [---], [Depth 2],
    [Logistics Sub-DAO], [---], [Depth 1],
    [Operations Sub-DAO], [---], [Depth 1],
  ),
  caption: [Multi-level hierarchy with delegated control. Engineering holds the `SubDAOControl` for Frontend, delegated by the top-level DAO.],
)

`Sub-DAOControl` can only be transferred downward --- the holder must itself control the target. This prevents lateral transfers that would create governance confusion.

== From Department to Sovereignty

The Sub-DAO lifecycle models a natural trajectory.

+ A tribe identifies a need for specialization and creates a Sub-DAO as a department.
+ The department develops its own expertise, culture, and operational patterns.
+ Over time, the department may grow large enough to warrant independence.
+ The parent passes a `SpinOutSub-DAO` proposal, granting full sovereignty.
+ The former Sub-DAO is now a top-level DAO, free to create its own Sub-DAOs, join federations, and forge independent relationships.

The protocol does not mandate this path. It provides the mechanisms for any trajectory the governance chooses.
