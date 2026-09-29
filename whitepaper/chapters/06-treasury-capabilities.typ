= Treasury and Capability Management

#import "../lib/template.typ": defbox, aside

An organization's power comes from the resources it controls and the capabilities it can use. Armature provides two vault systems --- the TreasuryVault for fungible assets and the CapabilityVault for arbitrary capabilities. Both are governed entirely through proposals.

== TreasuryVault

The TreasuryVault holds fungible assets under collective custody. Its core rule is simple: _deposits are open to anyone; withdrawals require governance approval_.

Anyone can deposit any coin type into a DAO's treasury --- members, outside parties, revenue-producing smart contracts. No vote is needed. The treasury tracks which coin types have non-zero balances, keeping a live registry of current holdings.

Withdrawals require a valid `ExecutionRequest<P>` from a passed proposal. The treasury checks that the request's `poa_id` matches its own, making cross-DAO withdrawal impossible. If a withdrawal brings a balance to zero, the dynamic field and registry entry are cleaned up automatically.

#aside[
  The permissionless deposit / governance-gated withdrawal pattern mirrors how real-world organizations operate. Anyone can contribute to a cause; spending from the collective fund requires authorization. This asymmetry is not a limitation but a feature --- it maximizes the organization's ability to accumulate resources while maintaining strict control over their disposition.
]

Sometimes coins are sent directly to the vault's address (via `transfer::public_transfer`) instead of through the `deposit` function. The `claim_coin` function recovers these misdirected transfers using SUI's `Receiving` pattern. It converts them into proper balance entries.

== CapabilityVault

The CapabilityVault stores arbitrary SUI objects. Any object with `key + store` abilities --- gate controllers, upgrade capabilities, admin tokens, access badges --- can be held in the vault and accessed through governance.

The vault provides four access patterns.

#figure(
  table(
    columns: (auto, 1fr, 1fr),
    align: (left, left, left),
    stroke: 0.5pt + luma(200),
    inset: 8pt,
    table.header[*Operation*][*Semantics*][*Use Case*],
    [`borrow_cap`], [Immutable reference to a stored capability.], [Read configuration, verify state.],
    [`borrow_cap_mut`], [Mutable reference to a stored capability.], [Update parameters, configure settings.],
    [`loan_cap`], [Temporary extraction with guaranteed return via `CapLoan` hot potato.], [Multi-step operations requiring the capability as an owned value.],
    [`extract_cap`], [Permanent removal from the vault.], [Transfer to another DAO, decommission.],
  ),
  caption: [Four access patterns for capabilities, from least to most permissive.],
)

When a capability is loaned, the vault produces both the capability and a `CapLoan` hot potato. The `CapLoan` has no abilities --- it must be consumed in the same PTB by calling `return_cap`, which checks that the returned capability's ID matches the loan. This guarantees loaned capabilities are always returned, no matter how many steps the handler takes.

#aside[
  During a loan, the vault's registries are _not_ updated. The capability is considered "held" rather than "removed." This prevents a subtle attack where a loaned capability could be re-stored under a different entry, corrupting the vault's internal state.
]

== Inter-DAO Asset Flow

Open deposits and governed withdrawals create natural patterns for moving assets between DAOs.

- *Downward funding:* A parent DAO passes a `SendCoinToDAO` proposal, withdrawing from its treasury and depositing into a Sub-DAO's treasury. The parent's governance approves the spend; the child's treasury accepts it without a vote.

- *Upward revenue:* A Sub-DAO passes a `SendCoin` proposal, withdrawing from its treasury and sending to the parent. Revenue from departments flows back up naturally.

- *Lateral transfer:* Any DAO can fund any other DAO's treasury directly. This covers donations, grants, contract payments, and alliance dues.

These flows work naturally with the Sub-DAO hierarchy. Organizations can build budgeting and revenue-sharing structures without any special-purpose tools. The protocol provides the pipes; governance provides the policy.
