= The Proposal System

#import "../lib/template.typ": aside, defbox

Every mutation to a POA's state flows through the proposal system. There are no administrative backdoors, no owner keys, no special-case pathways. This is not merely a design preference --- it is a security invariant. The proposal system is the POA's sole mechanism of action.

== Proposal Lifecycle

A proposal progresses through a strictly monotonic sequence of states. No transitions are reversible, ensuring that the governance record is an append-only log of organizational decisions.

#figure(
  table(
    columns: (auto, 1fr),
    align: (left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*State*][*Semantics*],
    [`Active`], [Open for voting. Board members may cast one vote each. The vote snapshot (membership at creation time) is immutable.],
    [`Passed`], [Approval threshold met. Awaiting execution. Execution delay and cooldown constraints may apply.],
    [`Executed`], [Handler has successfully consumed the `ExecutionRequest`. State changes committed atomically.],
    [`Expired`], [Voting window elapsed without reaching approval threshold. Terminal state.],
  ),
  caption: [Proposal states are monotonically ordered with no reversals.],
)

=== Creation

A proposal is created by an eligible member (board member, in Board governance). At creation, the framework snapshots the current governance state --- the full board membership and their weights. This snapshot becomes the immutable electorate for this proposal. Members added after creation cannot vote; members removed after creation retain their vote.

=== Voting

Each eligible member may cast exactly one vote: yes or no. Votes are recorded in a map from address to boolean. There is no vote change mechanism --- once cast, a vote is permanent. This simplicity is intentional: it makes the governance record unambiguous and eliminates race conditions around vote manipulation.

When a vote causes the approval condition to be met, the proposal transitions to `Passed` immediately. There is no separate "tallying" step.

=== Execution

Execution is a distinct step from passage. A passed proposal may be executed by any current board member, subject to three constraints:

+ *Execution delay* --- a mandatory waiting period after passage, giving the organization time to react to a proposal that passed unexpectedly.
+ *Cooldown* --- a minimum interval since the last execution of the same proposal type, preventing rapid-fire actions.
+ *Freeze check* --- the proposal type must not be currently frozen by the emergency system.

Upon execution, the framework produces an `ExecutionRequest<P>` hot potato. The handler function for type `P` consumes this token while performing the authorized state changes. If the handler aborts, the PTB reverts, the proposal remains `Passed`, and execution can be retried.

== Typed Proposals as Permissions

Armature does not have a role-based permission system. Instead, _the set of enabled proposal types defines the organization's capabilities_. A POA that has not enabled `CreateSub-POA` cannot create Sub-POAs. A POA that has not enabled `AmendCharter` cannot modify its constitution. The enabled proposal set _is_ the permission set.

This design has profound implications for security. Adding a new capability to the POA requires passing an `EnableProposalType` proposal with a 66% supermajority floor. Disabling a capability is similarly governed, with safeguards preventing the disabling of critical types (`EnableProposalType` itself, `TransferFreezeAdmin`, `UnfreezeProposalType`).

== Proposal Type Catalog

The framework ships with eighteen proposal types organized across five domains:

#figure(
  table(
    columns: (auto, auto, auto),
    align: (left, left, center),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*Domain*][*Type*][*Default*],
    [Admin], [`UpdateProposalConfig`], [Enabled],
    [Admin], [`EnableProposalType`], [Enabled],
    [Admin], [`DisableProposalType`], [Enabled],
    [Admin], [`UpdateMetadata`], [Enabled],
    [Admin], [`TransferFreezeAdmin`], [Enabled],
    [Admin], [`UnfreezeProposalType`], [Enabled],
    [Treasury], [`SendCoin<T>`], [Enabled],
    [Treasury], [`SendCoinToPOA<T>`], [Opt-in],
    [Board], [`SetBoard`], [Enabled],
    [Sub-POA], [`CreateSub-POA`], [Opt-in],
    [Sub-POA], [`SpinOutSub-POA`], [Opt-in],
    [Sub-POA], [`TransferCapToSub-POA`], [Opt-in],
    [Sub-POA], [`ReclaimCapFromSub-POA`], [Opt-in],
    [Sub-POA], [`PauseSub-POAExecution`], [Privileged],
    [Sub-POA], [`UnpauseSub-POAExecution`], [Privileged],
    [Charter], [`AmendCharter`], [Opt-in],
    [Charter], [`RenewCharterStorage`], [Opt-in],
    [Emergency], [`UpdateFreezeConfig`], [Opt-in],
  ),
  caption: [Eighteen proposal types across five domains. "Privileged" types are only available through `privileged_submit` from a controller POA.],
)

#aside[
  The distinction between "Enabled" and "Opt-in" types reflects a security-first posture. A newly created POA has the minimal set of capabilities needed to govern itself. Expanding that set is an explicit, high-threshold governance action.
]

== Open Proposal Type Set

The proposal system is designed for extensibility. Because the `ExecutionRequest<P>` hot potato is parameterized by a phantom type `P`, any package can define new proposal types. The framework's treasury and capability vault APIs accept any `ExecutionRequest<P>` as authorization --- the type parameter `P` is phantom and does not constrain which resources can be accessed.

A third-party developer can define a `PayBounty` proposal type, implement its handler, and any POA that enables it via `EnableProposalType` gains access to that functionality. The framework guarantees voting, thresholds, delays, and freeze checks for _any_ type. Handler correctness is the governance's decision --- enabling a type is the trust gate.

This extensibility transforms the POA from a closed product into an open protocol. The governance engine is a platform; proposal types are its applications.
