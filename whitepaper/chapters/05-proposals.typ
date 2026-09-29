= Proposal System and Extensibility

#import "../lib/template.typ": aside, principle

== What Is a Proposal

A proposal is a statement of intent backed by a governance vote. It is the primary mechanism through which a DAO's state changes, and all authority is rooted in governance: there are no admin backdoors and no owner keys. Two additional execution paths exist --- a parent DAO's override of a Sub-DAO it controls, and an opt-in bypass gated by an external authority --- but both are themselves enabled and governed through the proposal system. The security chapter treats them in full.

Every action a DAO takes --- spending from its treasury, delegating a capability, amending its charter, creating a department, changing its own rules --- is expressed as a proposal. Members issue proposals; members vote on them; the system executes the result.

Proposals are the vocabulary of the DAO. Each proposal type is a word in that vocabulary --- a specific kind of action the organization knows how to perform. The set of enabled proposal types defines the full range of what the organization can do.

A DAO that has not enabled charter amendments cannot amend its charter. A DAO that has not enabled Sub-DAO creation cannot create departments. The vocabulary is the permission set.

== How Proposals Work

A proposal moves through a strict, forward-only sequence: it is created, voted on, and either passes or expires. If it passes, it is executed. No transition is reversible. The governance record is an append-only log of organizational decisions.

=== Creation and Voting

A proposal is created by an eligible member. At creation, the framework snapshots the current membership --- this becomes the fixed electorate for this proposal. Members added after creation cannot vote on it. Members removed after creation keep their vote.

Each member casts one vote: yes or no, weighted by the snapshot. Votes are final. A proposal passes the instant two conditions hold together: _quorum_ --- enough of the electorate's total weight has voted at all --- and the _approval threshold_ --- enough of the weight that did vote is in favor. Meeting the threshold on a handful of votes is not enough if quorum is unmet; a well-attended vote that falls short of the threshold does not pass either. Both bars are configured per proposal type.

=== Execution

Execution is separate from passage. A passed proposal may still be subject to timing constraints --- a mandatory waiting period, a cooldown since the last action of the same type, or a freeze check from the emergency system.

On execution, the framework produces a one-time authorization token --- a _hot potato_. This token must be consumed in the same atomic transaction in which it was created. It cannot be stored, copied, or discarded. If anything fails, the entire transaction reverts and nothing changes.

There is no capability token to steal. No role to impersonate. No permission check to bypass. The type system itself is the access control layer.

== Per-Type Governance Parameters

Different actions deserve different levels of scrutiny. Governance parameters in Armature are configured _per proposal type_.

A routine metadata update might need a simple majority with no execution delay. A charter amendment might require 80% approval, a 48-hour review window, and a 7-day cooldown to block rapid constitutional changes. A vault withdrawal might add a 24-hour delay so the organization can react if a proposal passed too quickly.

The governance configuration itself encodes the organization's risk model. High-stakes actions get higher bars.

== Safety Rails

Two safety rails prevent governance from weakening itself.

*Self-referential floor.* Changing a proposal type's own governance parameters requires a high supermajority --- an 80% approval floor. A slim majority cannot lower the bar for future governance changes.

*Enable floor.* Adding a new proposal type to the DAO's vocabulary requires a two-thirds supermajority --- a 66% approval floor. Expanding what the organization can do expands its attack surface and requires broad consent. Enabling the opt-in external-authorization bypass, which sidesteps voting entirely, carries the stricter 80% floor.

These floors are _framework-enforced_ constants --- they cannot be bypassed by governance configuration. They are the protocol's minimum guarantees about governance integrity.

== Extending the Vocabulary

The proposal system is open by design. Armature ships with a built-in set of proposal types covering administration and charter amendment, treasury operations, board and membership management, currency issuance (minting and burning DAO-controlled coins), package upgrades, Sub-DAO operations, and emergency controls. But this set is not closed.

Any developer can define new proposal types. A bounty payment, a token distribution, a custom access control action --- each can be implemented as a proposal type and adopted by any DAO that chooses to enable it. The framework handles voting, thresholds, timing, and authorization for all types equally. Enabling a new type is the trust gate; the governance decides what vocabulary it adopts.

This turns the DAO from a closed product into an open protocol. The governance engine is a platform. Proposal types are its applications.

== Proposal Composition

Many governance operations are naturally multi-step. Creating a department, funding it, and delegating a capability to it is a single logical decision expressed as three separate votes under a simple proposal model. This fragmentation creates coordination risk: what if the funding vote fails after the department already exists?

Proposal composition solves this. Taking inspiration from SUI's Programmable Transaction Blocks, composite proposals bundle a sequence of steps into a single governance decision. Members vote once on a coherent plan --- not on isolated sentences, but on a full text that describes a meaningful rotation of resources.

"Create the logistics department, fund it with 1000 EVE, and delegate the gate controller capability" becomes one proposal, one vote, one atomic execution. At execution the steps run in order through a hot-potato pipeline that must be completed in the same transaction; if any step fails, everything reverts.

The composition rules are framework-enforced. A composite bundles up to sixteen steps. Composites cannot nest --- a step may not itself be a composite. The effective governance configuration of the bundle is the component-wise _maximum_ of its steps' configurations: the strictest quorum, the highest approval threshold, the longest delay. Composition can only tighten the bar, never weaken it, and the enable and self-referential floors still apply at submission. Proposal types that carry a cooldown are excluded from composites unless their configuration explicitly marks them composable, preventing a bundle from being used to sidestep a rate limit.

This shifts governance from approving individual operations to approving organizational intent. The proposal becomes a document that describes what the organization wants to achieve, and the system executes it as a whole.
