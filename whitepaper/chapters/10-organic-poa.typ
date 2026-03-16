= The Organic POA

#import "../lib/template.typ": aside

The POA as implemented in Armature is not merely a governance tool. It is an organizational _organism_ --- a self-amending, self-reproducing primitive that exhibits lifecycle dynamics analogous to living systems. This analogy is not decorative; it reveals structural properties of the design that are not obvious from a purely technical description.

== Birth

A POA is born with three constitutive elements:

- *Charter* --- the axioms. The foundational document that defines the organization's purpose, rules, and identity. Like DNA, the charter encodes the instructions from which all organizational behavior derives.
- *Treasury* --- the resources. The initial endowment that gives the organization the capacity to act. Like a cell's ATP stores, the treasury is both fuel and measure of vitality.
- *Proposal set* --- the inference rules. The enabled proposal types define the space of actions the POA can take. Like a cell's enzymatic machinery, the proposal set determines which transformations are possible.

A POA can begin as a single-member operation --- one founder, one vision, one wallet. The protocol imposes no minimum complexity. The atom of organization is genuinely atomic.

== Self-Amendment

The most remarkable property of the POA primitive is its self-referential governance. The rules that govern proposals are themselves subject to proposals:

- `UpdateProposalConfig` modifies the governance parameters for any proposal type, including itself.
- `EnableProposalType` and `DisableProposalType` expand or contract the space of possible actions.
- `AmendCharter` modifies the constitutional document that defines the organization's purpose and rules.
- `SetBoard` replaces the decision-making body entirely.

This self-referential loop is not a recursion bug --- it is the mechanism by which the POA evolves. An organization that cannot change its own rules is either static or dead. An organization that can change its rules without constraint is unstable. Armature's safety rails (threshold floors, timing controls, protected types) provide the guardrails that make self-amendment productive rather than destructive.

== Reproduction

POAs reproduce through `CreateSub-POA`. The offspring is a full instance of the same primitive --- same architecture, same governance engine, same proposal system. It is not a lightweight clone or a permission scope. It is a new organism, capable of independent action within the constraints set by its parent.

The parent retains control through the `Sub-POAControl` capability, analogous to a parent cell's regulatory influence over a daughter cell. This control is not absolute domination --- it is a governance relationship that can be exercised or relinquished.

== Emancipation

`SpinOutSub-POA` destroys the control relationship, granting the offspring full sovereignty. The former Sub-POA becomes a top-level POA, free to create its own Sub-POAs, join federations, and forge independent relationships.

This emancipation is irreversible. Once sovereignty is granted, it cannot be reclaimed. The organizational relationship has been permanently transformed from parent-child to peer-to-peer.

== Metabolism

The treasury system provides the POA's metabolic infrastructure. Resources flow in through permissionless deposits --- revenue, dues, donations. Resources flow out through governance-authorized withdrawals --- salaries, project funding, infrastructure investment. The treasury mediates between the organization's intake and its expenditure.

In hierarchical structures, metabolism extends across the organizational tree. Parent POAs fund child POAs (downward flow). Child POAs return revenue to parents (upward flow). Peer POAs exchange resources laterally. The protocol provides the circulatory system; governance provides the metabolic policy.

== Deliberate Death

A POA can die deliberately through migration. The `SpawnPOA` mechanism (specified for future implementation) creates a successor POA with a new governance model, transfers all assets and capabilities to the successor, and then destroys the original. This is not a failure mode --- it is a designed lifecycle transition.

The dying POA enters `Migrating` status, which blocks all proposal types except asset transfer. Once the vaults are empty, `poa::destroy` removes the POA from the chain. The successor carries the organization's history forward; the predecessor is permanently archived.

#aside[
  This lifecycle --- birth, self-amendment, reproduction, emancipation, metabolism, death --- is not imposed by the protocol. It is _enabled_ by the protocol. A POA may never reproduce. It may never amend its charter. It may persist indefinitely. The protocol provides the mechanisms; the governance provides the intent. The organism metaphor describes the space of possibilities, not a mandated trajectory.
]

== POA Archaeology

Because every state change is recorded on-chain --- every vote, every amendment, every treasury flow, every board change --- the POA becomes a substrate for history. The blockchain is a permanent record of organizational decisions and their consequences.

Future players can study the governance patterns of extinct organizations, trace the evolution of successful ones, and learn from the constitutional experiments of their predecessors. The POA protocol does not merely enable organization in the present --- it creates a permanent archaeological record of how Frontier's civilizations organized themselves.

This permanence transforms the POA from a gameplay tool into a contribution to the game world's culture. Every charter amendment, every treasury allocation, every Sub-POA creation is a decision that shapes the trajectory of Frontier's player-driven civilization and remains forever available for inspection by later generations.
