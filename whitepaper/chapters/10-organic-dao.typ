= The Organic DAO

#import "../lib/template.typ": aside

The DAO is not a governance tool. It is an organizational _organism_.

This analogy reveals structural properties of the design that a purely technical description obscures. The DAO self-amends, self-reproduces, and exhibits lifecycle dynamics analogous to living systems. These are not decorations --- they are consequences of the architecture.

== Birth

A DAO is born with three constitutive elements:

- *Charter* --- the axioms. The foundational document that defines purpose, rules, and identity. Like DNA, the charter encodes the instructions from which all organizational behavior derives.
- *Treasury* --- the resources. The initial endowment that gives the organization the capacity to act. Like a cell's ATP stores, the treasury is both fuel and measure of vitality.
- *Proposal set* --- the inference rules. The enabled proposal types define the space of actions the DAO can take. Like a cell's enzymatic machinery, the proposal set determines which transformations are possible.

A DAO can begin as a single-member operation --- one founder, one vision, one wallet. The protocol imposes no minimum complexity. The atom of organization is genuinely atomic.

== Self-Amendment

The rules that govern proposals are themselves subject to proposals:

- `UpdateProposalConfig` modifies the governance parameters for any proposal type, including itself.
- `EnableProposalType` and `DisableProposalType` expand or contract the space of possible actions.
- `AmendCharter` modifies the constitutional document that defines the organization's purpose and rules.
- `SetBoard` replaces the decision-making body entirely.

This self-referential loop is not a recursion bug --- it is the mechanism by which the DAO evolves.

An organization that cannot change its own rules is static. An organization that can change its rules without constraint is unstable. Armature's safety rails (threshold floors, timing controls, protected types) make self-amendment productive rather than destructive.

== Reproduction

DAOs reproduce through `CreateSub-DAO`. The offspring is a full instance of the same primitive --- same architecture, same governance engine, same proposal system.

It is not a lightweight clone or a permission scope. It is a new organism, capable of independent action within the constraints set by its parent.

The parent retains control through the `Sub-DAOControl` capability. This control is not absolute domination --- it is a governance relationship that can be exercised or relinquished.

== Emancipation

`SpinOutSub-DAO` destroys the control relationship, granting the offspring full sovereignty. The former Sub-DAO becomes a top-level DAO, free to create its own Sub-DAOs, join federations, and forge independent relationships.

This emancipation is irreversible. Once sovereignty is granted, it cannot be reclaimed. The relationship transforms permanently from parent-child to peer-to-peer.

== Metabolism

The treasury system provides the DAO's metabolic infrastructure. Resources flow in through permissionless deposits --- revenue, dues, donations. Resources flow out through governance-authorized withdrawals --- salaries, project funding, infrastructure investment.

In hierarchical structures, metabolism extends across the organizational tree. Parent DAOs fund child DAOs downward. Child DAOs return revenue to parents upward. Peer DAOs exchange resources laterally.

The protocol provides the circulatory system. Governance provides the metabolic policy.

== Deliberate Death

A DAO can die deliberately through migration. The `SpawnDAO` mechanism creates a successor DAO with a new governance model, transfers all assets and capabilities, and destroys the original.

This is not a failure mode --- it is a designed lifecycle transition.

The dying DAO enters `Migrating` status, which blocks all proposal types except asset transfer. Once the vaults are empty, `poa::destroy` removes the DAO from the chain. The successor carries the organization's history forward; the predecessor is permanently archived.

#aside[
  This lifecycle --- birth, self-amendment, reproduction, emancipation, metabolism, death --- is not imposed by the protocol. It is _enabled_ by the protocol.

  A DAO may never reproduce. It may never amend its charter. It may persist indefinitely.

  The protocol provides the mechanisms; governance provides the intent. The organism metaphor describes the space of possibilities, not a mandated trajectory.
]

== DAO Archaeology

Every state change is recorded on-chain --- every vote, every amendment, every treasury flow, every board change. The DAO becomes a substrate for history.

Future players can study the governance patterns of extinct organizations and trace the evolution of successful ones. The protocol creates a permanent archaeological record of how Frontier's civilizations organized themselves.

This permanence transforms the DAO from a gameplay tool into a contribution to the game world's culture. Every charter amendment, every treasury allocation, every Sub-DAO creation shapes Frontier's trajectory. These decisions remain forever available for inspection by later generations.
