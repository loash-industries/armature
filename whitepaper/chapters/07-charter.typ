= Charter as Constitution

#import "../lib/template.typ": aside, principle

Every organization needs a constitution. The Charter is Armature's: a document on decentralized storage, with on-chain integrity guarantees and a permanent amendment history.

== Design Philosophy

The Charter is deliberately _not_ a smart contract. It is a document. This distinction is foundational.

Smart contracts enforce rules mechanically. Charters express intent, define boundaries, and establish the social contract between members.

A charter might state that "the treasury shall not be used for personal expenses." No smart contract can fully enforce that, but the community can hold its governance accountable to it.

The Charter is more than a document. Its rules will be codified directly on the Charter object itself, and those codified rules will parametrize proposals --- binding governance not just by social agreement, but by code. The Charter becomes a machine-readable constitution, not just a human-readable one.

#principle[The Charter Principle][
  The Charter is the POA's highest authority. It defines what the POA _should_ do. The proposal system defines what the POA _can_ do. The tension between these two --- between aspiration and mechanism --- is productive. It ensures that governance operates within a framework of meaning, not merely of code.
]

== Architecture

The Charter object lives on-chain as a shared object. The charter _content_ lives on Walrus, a decentralized blob storage network. This hybrid architecture combines the permanence of blockchain with the expressiveness of arbitrary documents.

The on-chain Charter object stores:

- A reference to the current Walrus blob (the active charter document).
- A SHA-256 content hash for integrity verification.
- A monotonically increasing version number.
- A complete amendment history recording every change: which proposal authorized it, the previous and new blob IDs, the content hash, and the timestamp.

The full history of an organization's constitutional evolution is permanently recorded on-chain. Anyone can trace the amendments, verify the content against the hash, and see how the rules changed over time.

== Amendment Process

Amending the charter is the most consequential governance action a POA can take. The recommended configuration reflects this gravity.

- *80% approval threshold* --- near-unanimity, reflecting constitutional significance.
- *48-hour execution delay* --- ensuring the full membership has time to review and respond.
- *7-day cooldown* --- preventing rapid-fire amendments that could destabilize the organization.
- *14-day voting window* --- allowing sufficient time for deliberation.

The `AmendCharter` proposal carries the new blob ID, the content hash, and a summary of changes. Voters fetch the blob, verify the hash, and read the proposed changes before casting a vote. The execution handler updates the Charter object and records the amendment.

== Storage Renewal

Walrus blobs have finite lifetimes. The `RenewCharterStorage` proposal type addresses this without conflating it with constitutional amendment.

A renewal updates the blob reference _without_ changing the content hash or version number. It is a storage operation, not a governance action, and can carry a lower approval threshold.

#aside[
  If a Walrus blob expires, the charter content becomes temporarily inaccessible, but the on-chain Charter object --- with its content hash --- survives. Anyone holding a copy of the content can re-upload it to Walrus and propose a renewal. The hash serves as a proof of authenticity: the re-uploaded content must match the on-chain hash.
]

== Charter as Organizational DNA

The Charter is the source of truth from which all organizational behavior derives. As its rules become codified on the object itself, it will directly govern what proposals can do and how they behave. This is more than policy --- it is executable law.

A POA's charter might define:

- The organization's mission and scope of operations.
- Membership criteria and the relationship to a controller POA.
- Governance procedures, including which proposal types should carry which thresholds.
- Treasury policies: sources of funding, spending rules, revenue distribution formulas.
- Organizational structure: Sub-POA relationships, delegation patterns, reporting requirements.
- Amendment procedures: how the charter itself can be changed.
- Dissolution conditions: when and how the organization should wind down.

The amendment history is permanent. Future members can trace how the rules changed, which proposals drove those changes, and what the organization looked like at any point in its history.

In a game world where civilizations rise and fall, this permanence matters. The charter is the POA's contribution to the historical record of Frontier. POA archaeology --- the study of organizational evolution through on-chain constitutional history --- becomes possible.
