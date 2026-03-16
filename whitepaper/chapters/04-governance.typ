= Governance

#import "../lib/template.typ": aside, principle

Governance in Armature is not a monolithic mechanism but a configurable parameter of each POA instance. The framework enforces a critical invariant: the governance _type_ is sealed at creation, but the _state_ within that type is mutable through proposals. This separation prevents governance model changes from being used as attack vectors while preserving the organization's ability to evolve its membership and parameters.

== Governance Models

The current implementation provides Board governance, with Direct and Weighted models specified for future releases.

=== Board Governance

Board governance is the foundational model, designed for tribes and working groups where a defined set of members holds equal voting power. A board is defined by its member set and a seat count.

Each board member holds exactly one vote. Proposals are submitted by board members and voted on by the board as it existed at the moment the proposal was created --- a _snapshot_ that prevents membership changes from retroactively affecting in-flight votes.

The pass condition for any proposal is conjunctive:

$ "participation" >= "quorum" quad and quad "yes" / ("yes" + "no") >= "threshold" $

Where participation and thresholds are expressed in basis points (0--10000), enabling precise fractional governance without floating-point arithmetic. A quorum of 5000 requires at least 50% of the board to cast votes. An approval threshold of 6600 requires at least 66% of cast votes to be affirmative.

=== Future: Direct Governance

Direct governance extends the model to shareholder-style voting, where each voter holds a weight proportional to their share count. This model suits organizations where contribution is quantifiable and voting power should reflect stake.

=== Future: Weighted Governance

Weighted governance introduces delegation, where stakeholders can delegate their voting power to representatives. This model supports liquid democracy patterns where expertise is surfaced through voluntary delegation rather than imposed hierarchy.

#principle[Governance Immutability][
  A POA's governance type cannot change after creation. A Board POA cannot become a Direct POA through a proposal. This constraint is deliberate: governance model changes are existential transformations that should require explicit migration to a new POA instance, preserving full auditability of the transition.
]

== Per-Type Governance Parameters

A distinguishing feature of Armature is that governance parameters are not global --- they are configured _per proposal type_. This reflects the reality that different actions warrant different levels of scrutiny.

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*Parameter*][*Purpose*],
    [`quorum`], [Minimum participation (basis points) required for a vote to be valid.],
    [`approval_threshold`], [Minimum approval ratio (basis points, 5000--10000) among cast votes.],
    [`propose_threshold`], [Minimum weight or role required to submit a proposal of this type.],
    [`expiry_ms`], [Duration after which an unresolved proposal expires (minimum: 1 hour).],
    [`execution_delay_ms`], [Mandatory waiting period after a proposal passes before it can be executed.],
    [`cooldown_ms`], [Minimum interval between executions of the same proposal type.],
  ),
  caption: [Per-type governance parameters enable fine-grained control.],
)

A routine metadata update might require a simple majority with no execution delay. A charter amendment might demand 80% approval, a 48-hour delay for review, and a 7-day cooldown to prevent rapid-fire constitutional changes. A treasury withdrawal might impose a 24-hour delay to allow the board to react if a proposal was passed hastily.

This granularity means that the governance configuration itself encodes the organization's risk model. High-stakes actions carry proportionally higher bars for authorization.

== Safety Rails

Two critical safety rails prevent governance from being weakened through its own mechanisms:

+ *Self-referential floor.* When `UpdateProposalConfig` targets its own type, an 80% approval threshold floor is enforced. This prevents a slim majority from lowering the bar for future governance changes.

+ *Enable floor.* `EnableProposalType` enforces a 66% approval threshold floor. Adding new capabilities to the POA is treated as a significant expansion of the organization's attack surface and requires supermajority consent.

These floors are _framework-enforced_ --- they cannot be circumvented by governance configuration. They represent the protocol's minimal guarantees about governance integrity.
