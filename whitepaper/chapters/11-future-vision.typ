= Future Vision

#import "../lib/template.typ": aside, principle

The current implementation of Armature establishes the foundational primitive: Board governance, Sub-POA hierarchy, treasury management, capability vaults, charter system, and emergency controls. This foundation is deliberately minimal --- it provides the substrate upon which a rich ecosystem of organizational patterns can emerge.

The features described in this section are specified but not yet implemented. They represent the protocol's roadmap toward a complete organizational infrastructure for Frontier.

== Federation

#principle[Upward Composition][
  Sub-POAs compose downward (parent controls child). Federations compose _upward_ (peers associate voluntarily). The combination enables organizations to exist simultaneously as departments of a larger entity, members of a peer alliance, and controllers of their own subsidiaries.
]

Peer POAs may voluntarily form federations --- associations that pool resources and coordinate policy without surrendering sovereignty. Unlike the Sub-POA relationship, federation membership is symmetric: no member controls another.

Federation formation is a two-phase process: one POA proposes the federation, others are invited and must accept through their own governance. Each member receives a `FederationSeat` --- a non-transferable capability stored in the member's vault that represents their participation.

Federations can maintain collective treasuries funded by member contributions, conduct two-layer voting for high-stakes decisions (representative vote followed by member POA ratification), and coordinate policy across member organizations. Crucially, any member can exit the federation through their own governance --- federation membership is voluntary and revocable.

The key constraint is that managed Sub-POAs cannot join federations. Federation is a right of sovereign entities. A department must be spun out to independence before it can enter peer relationships.

== Governance Model Expansion

The framework's governance model architecture supports Direct and Weighted governance in addition to the current Board model:

*Direct governance* introduces shareholder-style voting where each voter's weight reflects their share count. This model suits organizations where contribution is quantifiable --- a mining cooperative where voting power reflects resource contribution, or a trading consortium where power reflects capital commitment.

*Weighted governance* introduces delegation, enabling liquid democracy patterns. Stakeholders can delegate their voting power to representatives who are presumed to have relevant expertise. Delegation is revocable, creating a dynamic where representatives must continuously earn the trust of their delegators.

Because governance type is immutable after creation, transitioning from one model to another requires explicit migration through `SpawnPOA` --- creating a successor POA with the new model and transferring all assets. This constraint ensures that governance transitions are fully auditable events, not gradual drifts.

== Proposal Composition

Many governance operations are naturally multi-step. Creating a Sub-POA, funding it, and delegating a capability to it is a single logical action expressed as three separate proposals under the current model. This fragmentation creates coordination problems: what if the funding proposal fails after the Sub-POA is already created?

Composite proposals solve this by bundling multiple proposals into a single governance action, voted on once and executed atomically. The internal mechanism uses a _hot potato pipeline_ --- a chain of `ExecutionRequest` productions and consumptions that must all succeed or the entire PTB reverts.

This pattern enables governance actions like "create a department, fund it with 1000 SUI, and delegate the gate controller capability" to be expressed, voted on, and executed as a single atomic operation.

== Charter Parametrization

The current charter is a human-readable document --- expressive but not machine-enforceable. Charter parametrization bridges this gap by introducing structured, on-chain parameters alongside the document.

A `CharterParam` stores a numeric value with optional immutable floor and ceiling bounds. The framework can enforce these parameters at two levels:

- *Framework-enforced* parameters (minimum approval thresholds, minimum delays) apply to all proposal types and cannot be circumvented.
- *Handler-enforced* parameters (maximum single spend, board size bounds) are checked by individual proposal handlers and serve as configurable policy constraints.

This two-tier system preserves the charter's role as a constitutional document while enabling machine-enforceable policy constraints where appropriate.

== Project Funding

The Sub-POA mechanism naturally extends to project funding --- a Kickstarter-style model where:

- A project is proposed as a Sub-POA with defined funding tiers.
- Backers contribute to the project's treasury and receive governance tokens proportional to their stake.
- A campaign period limits the funding window.
- Revenue from the completed project flows back through the treasury, distributed according to a governance-defined formula.

A stock ticker registry (1--4 character symbols, allocated through commit-reveal to prevent front-running) provides a namespace for project tokens, enabling secondary market trading and portfolio management.

== Lateral Composition

The most ambitious aspect of Armature's vision is lateral composition: the ability for a POA to simultaneously participate in multiple organizational relationships.

A single POA might be:
- A controlled Sub-POA of a tribe (downward relationship).
- A member of a haulers' alliance federation (upward relationship).
- The controller of its own specialized Sub-POAs (downward relationship).

Each role is encoded in independent capabilities (`Sub-POAControl`, `FederationSeat`), and the relationships compose without interference. The only constraint is that the `Sub-POAControl` graph must remain acyclic --- an organization cannot be its own ancestor.

This multi-dimensional composition reflects the reality of organizational life, where entities participate in many relationships simultaneously. A logistics department is part of a tribe _and_ a member of a cross-tribe logistics alliance _and_ the controller of regional sub-offices. Armature's capability-based composition model supports this naturally.

== Smart Assembly Integration

The ultimate expression of the protocol's value is its integration with Frontier's world contracts. POAs can hold Smart Assembly capabilities in their CapabilityVaults, governing access to gates, storage units, mining rigs, and other infrastructure through the proposal system.

This integration transforms assemblies from individually owned assets into collectively governed infrastructure. A gate network becomes a public utility operated by a POA. A mining fleet becomes a cooperative's shared resource. A manufacturing pipeline becomes a department's production line.

The POA does not replace the assembly --- it provides the organizational layer that makes collective assembly ownership and operation viable. The governance engine mediates between the group's intent and the assembly's capabilities, ensuring that infrastructure serves the organization rather than any individual.
