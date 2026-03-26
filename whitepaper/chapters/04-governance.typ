= Governance

#import "../lib/template.typ": aside, principle

Governance in Armature is a configurable parameter of each DAO instance, not a single fixed mechanism.

The framework enforces one key rule: the governance _type_ is locked at creation, but the _state_ within that type can change through proposals. This prevents governance model swaps from becoming attack vectors. It also preserves the organization's ability to update its membership and parameters.

== Governance Models

The current implementation provides Board governance. Direct and Weighted models are planned for future releases.

=== Board Governance

Board governance is the starting model. It is built for teams and working groups where a defined set of members holds equal voting power.

Each board member holds exactly one vote. Proposals are voted on by the board as it existed when the proposal was created --- a _snapshot_ that prevents membership changes from affecting votes already in progress.

The pass condition for any proposal is conjunctive:

$ "participation" >= "quorum" quad and quad "yes" / ("yes" + "no") >= "threshold" $

Participation and thresholds are expressed in basis points (0--10000), giving precise fractional governance without floating-point math. A quorum of 5000 means at least 50% of the board must vote. An approval threshold of 6600 means at least 66% of votes cast must be "yes."

=== Future: Direct Governance

Direct governance extends the model to share-based voting, where each voter's weight matches their share count. This fits organizations where contribution is measurable and voting power should match stake.

=== Future: Weighted Governance

Weighted governance adds delegation. Stakeholders can hand their voting power to representatives. This supports liquid democracy, where expertise rises through voluntary choice rather than fixed hierarchy.

#principle[Governance Immutability][
  A DAO's governance type cannot change after creation. A Board DAO cannot become a Direct DAO through a proposal. This constraint is deliberate: governance model changes are existential transformations that should require explicit migration to a new DAO instance, preserving full auditability of the transition.
]

== Per-Type Governance Parameters

Governance parameters in Armature are not global. They are configured _per proposal type_, because different actions deserve different levels of scrutiny.

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

A routine metadata update might need a simple majority with no execution delay. A charter amendment might require 80% approval, a 48-hour review window, and a 7-day cooldown to block rapid constitutional changes. A treasury withdrawal might add a 24-hour delay so the board can react if a proposal passed too quickly.

The governance configuration itself encodes the organization's risk model. High-stakes actions get higher bars.

== Safety Rails

Two safety rails prevent governance from weakening itself.

*Self-referential floor.* When `UpdateProposalConfig` targets its own type, an 80% approval threshold floor is enforced. A slim majority cannot lower the bar for future governance changes.

*Enable floor.* `EnableProposalType` enforces a 66% approval threshold floor. Adding new capabilities to the DAO expands its attack surface and requires supermajority consent.

These floors are _framework-enforced_ --- they cannot be bypassed by governance configuration. They are the protocol's minimum guarantees about governance integrity.
