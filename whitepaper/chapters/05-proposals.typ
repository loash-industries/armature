= The Proposal System

#import "../lib/template.typ": aside, defbox

Every change to a DAO's state goes through the proposal system. There are no admin backdoors, no owner keys, no special paths. This is not a design preference --- it is a security guarantee.

== Proposal Lifecycle

A proposal moves through a strict, forward-only sequence of states. No transition is reversible. The governance record is an append-only log of organizational decisions.

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

A proposal is created by an eligible member. At creation, the framework snapshots the current governance state --- the full board membership and their weights.

This snapshot becomes the fixed electorate for this proposal. Members added after creation cannot vote. Members removed after creation keep their vote.

=== Voting

Each eligible member may cast exactly one vote: yes or no. Votes map from address to boolean, and there is no way to change a vote once cast.

This keeps the governance record clear. It also removes race conditions around vote changes.

When a vote pushes the result past the approval threshold, the proposal transitions to `Passed` immediately. There is no separate tallying step.

=== Execution

Execution is separate from passage. A passed proposal may be executed by any current board member, subject to three constraints:

+ *Execution delay* --- a mandatory waiting period after passage, giving the organization time to react to a proposal that passed unexpectedly.
+ *Cooldown* --- a minimum interval since the last execution of the same proposal type, preventing rapid repeated actions.
+ *Freeze check* --- the proposal type must not be currently frozen by the emergency system.

On execution, the framework produces an `ExecutionRequest<P>` hot potato. The handler function for type `P` consumes this token and performs the authorized state changes. If the handler aborts, the PTB reverts, the proposal stays `Passed`, and execution can be retried.

== Typed Proposals as Permissions

Armature has no role-based permission system. The set of enabled proposal types defines what the organization can do.

A DAO that has not enabled `CreateSub-DAO` cannot create Sub-DAOs. A DAO that has not enabled `AmendCharter` cannot change its constitution. The enabled proposal set _is_ the permission set.

Adding a new capability requires passing an `EnableProposalType` proposal with a 66% supermajority floor. Disabling a capability is governed the same way, with safeguards that prevent disabling critical types (`EnableProposalType` itself, `TransferFreezeAdmin`, `UnfreezeProposalType`).

== Proposal Type Catalog

The framework ships with eighteen proposal types across five domains.

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
    [Treasury], [`SendCoinToDAO<T>`], [Opt-in],
    [Board], [`SetBoard`], [Enabled],
    [Sub-DAO], [`CreateSub-DAO`], [Opt-in],
    [Sub-DAO], [`SpinOutSub-DAO`], [Opt-in],
    [Sub-DAO], [`TransferCapToSub-DAO`], [Opt-in],
    [Sub-DAO], [`ReclaimCapFromSub-DAO`], [Opt-in],
    [Sub-DAO], [`PauseSub-DAOExecution`], [Privileged],
    [Sub-DAO], [`UnpauseSub-DAOExecution`], [Privileged],
    [Charter], [`AmendCharter`], [Opt-in],
    [Charter], [`RenewCharterStorage`], [Opt-in],
    [Emergency], [`UpdateFreezeConfig`], [Opt-in],
  ),
  caption: [Eighteen proposal types across five domains. "Privileged" types are only available through `privileged_submit` from a controller DAO.],
)

#aside[
  The distinction between "Enabled" and "Opt-in" types reflects a security-first posture. A newly created DAO has the minimal set of capabilities needed to govern itself. Expanding that set is an explicit, high-threshold governance action.
]

== Open Proposal Type Set

The proposal system is extensible by design. The `ExecutionRequest<P>` hot potato is parameterized by a phantom type `P`, so any package can define new proposal types.

The framework's treasury and capability vault APIs accept any `ExecutionRequest<P>` as authorization. The type parameter `P` is phantom and does not restrict which resources can be accessed.

A third-party developer can define a `PayBounty` proposal type, implement its handler, and any DAO that enables it through `EnableProposalType` gains that functionality. The framework handles voting, thresholds, delays, and freeze checks for _any_ type. Whether a handler is correct is the governance's decision --- enabling a type is the trust gate.

This turns the DAO from a closed product into an open protocol. The governance engine is a platform. Proposal types are its applications.
