= Charter as Constitution

#import "../lib/template.typ": aside, principle

Every organization needs a constitution --- a document that defines its purpose, establishes its rules, and binds its members to a shared set of principles. In Armature, this role is filled by the Charter: a human-readable document stored on decentralized infrastructure, with on-chain integrity guarantees and a permanent amendment history.

== Design Philosophy

The Charter is deliberately _not_ a smart contract. It is a document. This distinction is foundational.

Smart contracts enforce rules mechanically. Charters express intent, define boundaries, and establish the social contract between members. A charter might state that "the treasury shall not be used for personal expenses" --- a principle that no smart contract can fully enforce but that the community can hold its governance accountable to.

#principle[The Charter Principle][
  The Charter is the DAO's highest authority. It defines what the DAO _should_ do. The proposal system defines what the DAO _can_ do. The tension between these two --- between aspiration and mechanism --- is productive. It ensures that governance operates within a framework of meaning, not merely of code.
]

== Architecture

The Charter object lives on-chain as a shared object, but the charter _content_ lives on Walrus --- a decentralized blob storage network. This hybrid architecture combines the permanence of blockchain with the expressiveness of arbitrary documents.

The on-chain Charter object stores:

- A reference to the current Walrus blob (the active charter document).
- A SHA-256 content hash for integrity verification.
- A monotonically increasing version number.
- A complete amendment history recording every change: which proposal authorized it, the previous and new blob IDs, the content hash, and the timestamp.

This design means that the full history of an organization's constitutional evolution is permanently recorded on-chain. Anyone can trace the amendments, verify the content against the hash, and understand how the organization's rules have changed over time.

== Amendment Process

Amending the charter is the most consequential governance action an organization can take. The recommended configuration reflects this gravity:

- *80% approval threshold* --- near-unanimity, reflecting the constitutional significance.
- *48-hour execution delay* --- ensuring the full membership has time to review and respond.
- *7-day cooldown* --- preventing rapid-fire amendments that could destabilize the organization.
- *14-day voting window* --- allowing sufficient time for deliberation.

The `AmendCharter` proposal carries the new blob ID (uploaded to Walrus by the proposer), the content hash, and a summary of changes. Voters are expected to fetch the blob, verify the hash, read the proposed changes, and cast an informed vote. The execution handler updates the Charter object with the new reference and records the amendment.

== Storage Renewal

Walrus blobs have finite lifetimes. The `RenewCharterStorage` proposal type addresses this operational need without conflating it with constitutional amendment. A renewal updates the blob reference _without_ changing the content hash or version number --- it is a storage operation, not a governance action, and can carry a lower approval threshold.

#aside[
  If a Walrus blob expires, the charter content becomes temporarily inaccessible, but the on-chain Charter object --- with its content hash --- survives. Anyone holding a copy of the content can re-upload it to Walrus and propose a renewal. The hash serves as a proof of authenticity: the re-uploaded content must match the on-chain hash.
]

== Charter as Organizational DNA

The Charter is more than a policy document. It is the organization's DNA --- the axioms from which all behavior derives. A DAO's charter might define:

- The organization's mission and scope of operations.
- Membership criteria and the relationship to a controller DAO.
- Governance procedures, including which proposal types should carry which thresholds.
- Treasury policies: sources of funding, spending rules, revenue distribution formulas.
- Organizational structure: SubDAO relationships, delegation patterns, reporting requirements.
- Amendment procedures: how the charter itself can be changed.
- Dissolution conditions: when and how the organization should wind down.

Because the amendment history is permanent, the charter becomes a historical record --- an archaeological artifact of the organization's evolution. Future members can trace how the rules changed, which proposals drove those changes, and what the organization looked like at any point in its history.

In a game world where civilizations rise and fall, this permanence has particular significance. The charter is the DAO's contribution to the historical record of Frontier. DAO archaeology --- the study of organizational evolution through on-chain constitutional history --- becomes possible.
