= Members and Governance

#import "../lib/template.typ": aside, principle

== What Is a Member

A member is a recognized participant of a DAO. Membership is the boundary between those who have a voice and those who do not.

Being a member means two things: the right to issue proposals and the right to vote on them. These are the only two actions that change a DAO's state, and both are gated by membership. Everything a DAO does --- spending resources, amending its charter, creating departments, delegating authority --- flows from members exercising these rights.

Membership is not a passive status. It is an active relationship between a player and an organization.

== How Members Join

There is no single onboarding path. How members join a DAO is determined by the DAO's configuration --- specifically, its governance model and its enabled proposal set.

Under board governance, membership is managed through proposals: `AddMember`, `RemoveMember`, their batch variants, and `SetBoard` replace the roster wholesale. Which of these types a DAO enables, and the thresholds attached to each, determine the onboarding policy. A tribe might require an existing member to propose an addition, followed by a board vote. An open collective might set a low threshold so additions pass readily. The EVE Frontier bridge adds a further path: a DAO can opt a membership Sub-DAO into permissionless self-join, letting players whose in-game tribe is on an allowlist join without a vote (see the world bridge).

The protocol does not prescribe a single onboarding path. It provides the proposal primitives, and the DAO's enabled proposal set and thresholds determine the policy.

== Governance Style

A DAO's governance style defines how members participate --- who can propose, how votes are weighted, and what constitutes approval. The style is chosen at creation and is immutable.

#principle[Governance Immutability][
  A DAO's governance type is locked at creation. A Board DAO does not drift into a Direct DAO through incremental parameter changes. This constraint is deliberate: governance model changes are existential transformations that should require explicit migration to a new DAO instance, preserving full auditability of the transition.
]

Armature ships today with a single, production-ready governance style, and reserves two more in the governance model for future releases:

- *Board* (implemented) --- a defined set of members, each holding one equal vote. The natural fit for small teams and early-stage tribes. Every DAO created today is a Board DAO.
- *Direct* (planned) --- voting power reflects stake. Influence is proportional to contribution.
- *Weighted* (planned) --- members delegate their voting power to representatives. Liquid democracy where expertise rises through voluntary choice.

The governance model is a sealed, extensible enum: Direct and Weighted exist as reserved variants, and the immutability guarantee below already applies to whichever style a DAO is born with. These are starting points, not the full design space. The governance design space is wide --- from single-member autocracies to pure democracies, from meritocratic councils to delegated assemblies. We intend to study this space systematically, charting the sensible and orthogonal styles, and extending the framework to cover them.

The framework does not tell organizations how to govern themselves. It gives them a toolkit for expressing their style --- from autocracy to pure democracy and everything between. The right governance model is the one that fits the organization's purpose, culture, and stage of life.
