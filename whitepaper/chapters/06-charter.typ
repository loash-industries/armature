= Charter and Evolving Constitution

#import "../lib/template.typ": aside, principle

The Charter is the DAO's constitution. It declares the organization's vision and long-term intent, and it defines the invariants --- the rules by which the DAO mutates.

Every organization operates under assumptions its members care about preserving. A treasury spending cap. A minimum quorum for existential decisions. A requirement that certain capabilities never leave the vault. These are not preferences --- they are the organizational physics that the charter encodes.

#principle[The Charter Principle][
  The Charter is the DAO's highest authority. It defines what the DAO _should_ do. The proposal system defines what the DAO _can_ do. The tension between these two --- between aspiration and mechanism --- is productive. It ensures that governance operates within a framework of meaning, not merely of code.
]

== Two Faces of the Charter

The Charter has two aspects, each serving a different audience.

=== The Document

The first aspect is a human-readable document hosted on a decentralized storage platform. It expresses the organization's mission, its values, the social contract between members, and the intent behind its rules. This is what members read when they join, what they reference during disputes, and what they amend when the organization's direction changes.

The document lives off-chain on Walrus, a decentralized blob storage network. The on-chain Charter object holds a reference to the current blob, a content hash for integrity verification, a version number, and a complete amendment history. Anyone can trace the full constitutional evolution of the organization --- which proposals drove which changes, and what the charter said at any point in time.

A charter might state that "the treasury shall not be used for personal expenses." No smart contract can fully enforce that, but the community can hold its governance accountable to it. The document is the voice of organizational intent.

=== The Invariants

The second aspect is a set of on-chain invariants defined directly on the Charter object. These are structured, machine-readable parameters that proposals can read and enforce.

Where the document expresses _what the organization believes_, the invariants encode _what the organization protects_. They capture what members care about maintaining throughout the current lifecycle of the DAO.

A charter invariant might set a maximum single treasury withdrawal. A proposal that attempts to exceed it would fail --- not because a voter caught it, but because the framework reads the invariant and enforces it. Another invariant might set a floor on the quorum for charter amendments, ensuring that constitutional changes always require broad participation regardless of how governance parameters evolve.

Invariants parametrize proposals. They are the bridge between the charter's intent and the proposal system's execution --- the mechanism by which organizational physics become enforceable.

== How the Two Aspects Compose

The document and the invariants are not separate systems. They are two expressions of the same constitution.

The document says: "We believe in conservative treasury management." The invariant encodes: maximum single withdrawal of 500 EVE. The document provides the reasoning; the invariant provides the enforcement. Members amend both through the same governance process, and the amendment history records both changes together.

This duality is what makes the charter a living constitution rather than a static declaration. The human-readable layer evolves through debate and consensus. The machine-readable layer evolves alongside it, translating intent into constraints that the system respects.

== Amending the Charter

Amending the charter is the most consequential governance action a DAO can take. The recommended configuration reflects this gravity:

- Near-unanimous approval --- reflecting constitutional significance.
- A multi-day execution delay --- ensuring the full membership has time to review and respond.
- A cooldown period --- preventing rapid-fire amendments that could destabilize the organization.
- An extended voting window --- allowing sufficient time for deliberation.

Both the document and the invariants can be amended through proposals. Changing an invariant is a constitutional act --- it changes the physics of the organization, and it should carry the same weight as rewriting the charter's text.

== Organizational DNA

The Charter is the source of truth from which all organizational behavior derives. It defines the mission, encodes the constraints, and records every mutation.

The amendment history is permanent. Future members can trace how the rules changed, which proposals drove those changes, and what the organization looked like at any point in its history.

In a game world where civilizations rise and fall, this permanence matters. The charter is the DAO's contribution to the historical record of Frontier. DAO archaeology --- the study of organizational evolution through on-chain constitutional history --- becomes possible.

// ? What is the full taxonomy of invariant types --- numeric bounds, boolean flags, capability constraints, membership rules?
// ? How do invariants interact with proposal composition --- can a composite proposal read invariants from multiple sources?
// ? How does the framework handle conflicts between invariants set at different levels of the organizational hierarchy (parent charter vs Sub-DAO charter)?
