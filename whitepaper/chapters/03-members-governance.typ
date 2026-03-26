= Members and Governance

#import "../lib/template.typ": aside, principle

== What Is a Member

A member is a recognized participant of a DAO. Membership is the boundary between those who have a voice and those who do not.

Being a member means two things: the right to issue proposals and the right to vote on them. These are the only two actions that change a DAO's state, and both are gated by membership. Everything a DAO does --- spending resources, amending its charter, creating departments, delegating authority --- flows from members exercising these rights.

Membership is not a passive status. It is an active relationship between a player and an organization.

== How Members Join

There is no single onboarding path. How members join a DAO is determined by the DAO's configuration --- specifically, its governance model and its enabled proposal set.

A tribe might require an existing member to propose a new addition, followed by a board vote. A cooperative might accept anyone who deposits a minimum stake. A guild might gate entry on holding a specific capability or token. An open collective might let anyone join without approval.

// ? How does the framework represent these different onboarding paths --- is it through proposal types (e.g. AddMember), governance model hooks, or a dedicated membership module?
// ? Can a DAO define custom membership criteria beyond what the built-in governance models provide?

The protocol does not prescribe how membership works. It provides the primitives, and the DAO's configuration determines the policy.

== Governance Style

A DAO's governance style defines how members participate --- who can propose, how votes are weighted, and what constitutes approval. The style is chosen at creation and is immutable.

#principle[Governance Immutability][
  A DAO's governance type is locked at creation. A Board DAO does not drift into a Direct DAO through incremental parameter changes. This constraint is deliberate: governance model changes are existential transformations that should require explicit migration to a new DAO instance, preserving full auditability of the transition.
]

Armature will initially ship with a focused set of governance styles:

- *Board* --- a defined set of members, each holding one equal vote. The natural fit for small teams and early-stage tribes.
- *Direct* --- voting power reflects stake. Influence is proportional to contribution.
- *Weighted* --- members delegate their voting power to representatives. Liquid democracy where expertise rises through voluntary choice.

These are starting points, not the full design space. The governance design space is wide --- from single-member autocracies to pure democracies, from meritocratic councils to delegated assemblies. We intend to study this space systematically, charting the sensible and orthogonal styles, and extending the framework to cover them.

The framework does not tell organizations how to govern themselves. It gives them a toolkit for expressing their style --- from autocracy to pure democracy and everything between. The right governance model is the one that fits the organization's purpose, culture, and stage of life.
