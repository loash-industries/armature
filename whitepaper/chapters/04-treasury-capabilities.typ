= Vaults and Resource Sovereignty

#import "../lib/template.typ": defbox, aside

An organization's power comes from what it controls. Armature separates organizational resources into two categories: fungible assets and capabilities. Each has its own vault, its own access patterns, and its own role in the system. Together they form the DAO's resource sovereignty layer --- everything the organization owns, holds, and can act with.

Both vaults share one principle: deposits are open; access requires governance approval.

== TreasuryVault

The TreasuryVault represents the organization's economic capacity. It holds fungible assets --- coins, tokens, any on-chain currency --- under collective custody.

Anyone can deposit into a DAO's treasury. Members, outside parties, revenue-producing contracts. No vote is needed. This makes the treasury a natural accumulation point: dues flow in, revenue flows in, grants flow in. The treasury grows as the organization creates value.

Withdrawals require a passed proposal. The treasury is not a wallet that members can draw from --- it is a shared pool that the organization governs collectively. Every spend is a decision.

This asymmetry is deliberate. It maximizes the organization's ability to accumulate resources while maintaining strict control over their disposition. A treasury that is easy to fill and hard to drain is a treasury that survives.

== CapabilityVault

The CapabilityVault represents the organization's operational authority. It holds capabilities --- gate controllers, upgrade caps, admin tokens, access badges --- any on-chain object that grants the power to act.

Where the treasury answers "what resources does the organization have?", the capability vault answers "what can the organization do?" A DAO that holds a gate controller cap can operate a gate network. A DAO that holds an upgrade cap can upgrade a smart contract. A DAO that holds an admin token can configure a protocol.

Capabilities can be accessed in four ways, from least to most permissive:

- *Inspect* --- read a capability's state without changing it.
- *Modify* --- update a capability's parameters.
- *Loan* --- temporarily extract a capability with a guaranteed return. The framework enforces that loaned capabilities always come back --- no matter what happens during the operation.
- *Extract* --- permanently remove a capability from the vault. Used for transfers to another DAO or decommissioning.

Each access pattern requires a passed proposal. The vault ensures that no capability is used, modified, or moved without governance authorization.

== What Vaults Enable

The two vaults together give a DAO full resource sovereignty. The treasury funds operations; capabilities authorize them. A department with a budget but no gate controller cap cannot operate gates. A department with the cap but no budget cannot pay for fuel. Both vaults must be provisioned for the organization to act.

This separation creates natural delegation patterns. A parent DAO can fund a Sub-DAO's treasury generously while keeping sensitive capabilities in its own vault. Or it can delegate a capability while keeping the budget tight. The two dimensions of resource control are independent.

== Inter-DAO Asset Flow

Open deposits and governed withdrawals create natural patterns for moving resources between DAOs.

- *Downward funding:* A parent DAO withdraws from its treasury and deposits into a Sub-DAO's treasury. The parent's governance approves the spend; the child's treasury accepts it without a vote.

- *Upward revenue:* A Sub-DAO withdraws from its treasury and sends to the parent. Revenue from departments flows back up naturally.

- *Lateral transfer:* Any DAO can fund any other DAO's treasury directly. This covers donations, grants, contract payments, and alliance dues.

These flows work naturally with the organizational hierarchy. The protocol provides the pipes; governance provides the policy.
