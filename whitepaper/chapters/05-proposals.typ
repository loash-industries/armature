= Proposal System and Extensibility

#import "../lib/template.typ": aside, principle

== What Is a Proposal

A proposal is a statement of intent backed by a governance vote. It is the only mechanism through which a DAO's state changes. There are no admin backdoors, no owner keys, no special paths.

Every action a DAO takes --- spending from its treasury, delegating a capability, amending its charter, creating a department, changing its own rules --- is expressed as a proposal. Members issue proposals; members vote on them; the system executes the result.

Proposals are the vocabulary of the DAO. Each proposal type is a word in that vocabulary --- a specific kind of action the organization knows how to perform. The set of enabled proposal types defines the full range of what the organization can do.

A DAO that has not enabled charter amendments cannot amend its charter. A DAO that has not enabled Sub-DAO creation cannot create departments. The vocabulary is the permission set.

== How Proposals Work

A proposal moves through a strict, forward-only sequence: it is created, voted on, and either passes or expires. If it passes, it is executed. No transition is reversible. The governance record is an append-only log of organizational decisions.

=== Creation and Voting

A proposal is created by an eligible member. At creation, the framework snapshots the current membership --- this becomes the fixed electorate for this proposal. Members added after creation cannot vote on it. Members removed after creation keep their vote.

Each member casts one vote: yes or no. Votes are final. When enough votes are cast to meet the approval threshold, the proposal passes immediately.

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

*Self-referential floor.* Changing the rules for how governance rules are changed requires near-unanimity. A slim majority cannot lower the bar for future governance changes.

*Enable floor.* Adding new proposal types to the DAO's vocabulary requires a supermajority. Expanding what the organization can do expands its attack surface and requires broad consent.

These floors are _framework-enforced_ --- they cannot be bypassed by governance configuration. They are the protocol's minimum guarantees about governance integrity.

== Extending the Vocabulary

The proposal system is open by design. Armature ships with a built-in set of proposal types covering administration, treasury operations, board management, Sub-DAO operations, charter amendments, and emergency controls. But this set is not closed.

Any developer can define new proposal types. A bounty payment, a token distribution, a custom access control action --- each can be implemented as a proposal type and adopted by any DAO that chooses to enable it. The framework handles voting, thresholds, timing, and authorization for all types equally. Enabling a new type is the trust gate; the governance decides what vocabulary it adopts.

This turns the DAO from a closed product into an open protocol. The governance engine is a platform. Proposal types are its applications.

== Proposal Composition

Many governance operations are naturally multi-step. Creating a department, funding it, and delegating a capability to it is a single logical decision expressed as three separate votes under a simple proposal model. This fragmentation creates coordination risk: what if the funding vote fails after the department already exists?

Proposal composition solves this. Taking inspiration from SUI's Programmable Transaction Blocks, composite proposals bundle a sequence of actions into a single governance decision. Members vote once on a coherent plan --- not on isolated sentences, but on a full text that describes a meaningful rotation of resources.

"Create the logistics department, fund it with 1000 EVE, and delegate the gate controller capability" becomes one proposal, one vote, one atomic execution. If any step fails, everything reverts.

This shifts governance from approving individual operations to approving organizational intent. The proposal becomes a document that describes what the organization wants to achieve, and the system executes it as a whole.

// ? What are the composition rules --- which proposal types can be bundled, and are there ordering constraints?
// ? How does the voting threshold work for a composite --- does it inherit the highest threshold among its parts?
// ? How are composite proposals displayed to voters so they can understand the full scope of what they are approving?
