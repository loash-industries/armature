= Sub-OU Hierarchy and Composition

#import "../lib/template.typ": aside, principle

Organizations are not flat. Growth creates internal structure: departments, task forces, working groups. Armature models this through Sub-OUs --- full OU instances in a parent-child relationship with a controlling OU.

== The Sub-OU as a Full Primitive

A Sub-OU is not a lightweight proxy or a permission scope. It is a complete OU instance with its own treasury, capability vault, charter, emergency freeze, governance configuration, and proposal set.

The only structural difference from an org is the presence of a `controller_cap_id`. This is a reference to the `SubOUControl` capability held by the parent.

A Sub-OU can do everything an org can do, _within the boundaries set by its controller_. It receives deposits, passes proposals, manages capabilities, and amends its own charter. It operates with genuine autonomy while remaining accountable to the parent.

== Controller Authority

The parent OU exercises authority through the `SubOUControl` capability. It is stored in the parent's CapabilityVault and accessed only through governance proposals.

The controller can:

+ *Replace the board instantly* --- via `privileged_submit`, the parent can create a `SetBoard` proposal in the Sub-OU that enters `Passed` status directly, bypassing the Sub-OU's voting process. This is the last resort for a rogue department.

+ *Pause execution* --- `PauseSub-OUExecution` blocks all proposal execution in the Sub-OU. Combined with board replacement, this enables atomic recovery from compromised governance.

+ *Reclaim capabilities* --- `privileged_extract` allows the controller to recover any capability from the Sub-OU's vault. Delegated authority can always be recovered.

+ *Grant independence* --- `SpinOutSubOU` destroys the `SubOUControl` capability, severing the parent-child relationship permanently. The former Sub-OU becomes a fully independent org.

#principle[Hierarchy Blocklist][
  Controlled Sub-OUs cannot enable `CreateSub-OU`, `SpinOutSubOU`, or `SpawnOU`. A department cannot unilaterally create its own sub-departments or declare independence. These capabilities require the parent to explicitly grant them through spinout. This prevents hierarchical leaks and ensures that organizational structure is always a deliberate governance decision.
]

== Atomic Recovery

When a Sub-OU's governance is compromised, the parent can recover it in a single transaction.

+ Pause all Sub-OU execution --- freeze activity immediately.
+ Replace the compromised board with trusted members.
+ Extract sensitive capabilities back to the parent.
+ Unpause Sub-OU execution --- resume operations.

All four steps execute in a single PTB. There is no window between the pause and the board replacement where the compromised board could act. The recovery is instantaneous and complete.

== Multi-Level Hierarchies

Sub-OUs can be nested to arbitrary depth. A parent OU can transfer its `SubOUControl` for a grandchild to a child Sub-OU, creating delegation chains.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*OU*][*Controls*][*Level*],
    [Org], [Engineering, Logistics, Operations], [Root],
    [Engineering Sub-OU], [Frontend Sub-OU], [Depth 1],
    [Frontend Sub-OU], [---], [Depth 2],
    [Logistics Sub-OU], [---], [Depth 1],
    [Operations Sub-OU], [---], [Depth 1],
  ),
  caption: [Multi-level hierarchy with delegated control. Engineering holds the `SubOUControl` for Frontend, delegated by the org.],
)

`SubOUControl` can only be transferred downward --- the holder must itself control the target. This prevents lateral transfers that would create governance confusion.

== From Department to Sovereignty

The Sub-OU lifecycle models a natural trajectory.

+ A tribe identifies a need for specialization and creates a Sub-OU as a department.
+ The department develops its own expertise, culture, and operational patterns.
+ Over time, the department may grow large enough to warrant independence.
+ The parent passes a `SpinOutSubOU` proposal, granting full sovereignty.
+ The former Sub-OU is now an org, free to create its own Sub-OUs, join federations, and forge independent relationships.

The protocol does not mandate this path. It provides the mechanisms for any trajectory the governance chooses.
