= Charter and Evolving Constitution

#import "../lib/template.typ": aside, principle

The Charter is the DAO's constitution. It declares the organization's vision and long-term intent, and it is the anchor for the invariants --- the rules by which the DAO mutates --- that the charter is designed to carry.

Every organization operates under assumptions its members care about preserving. A treasury spending cap. A minimum quorum for existential decisions. A requirement that certain capabilities never leave the vault. These are not preferences --- they are the organizational physics a constitution exists to encode. Today Armature enforces the universal ones through framework-level safety floors; the charter's role in encoding _per-organization_ invariants is the planned evolution described below.

#principle[The Charter Principle][
  The Charter is the DAO's highest authority. It defines what the DAO _should_ do. The proposal system defines what the DAO _can_ do. The tension between these two --- between aspiration and mechanism --- is productive. It ensures that governance operates within a framework of meaning, not merely of code.
]

== Two Faces of the Charter

The Charter is designed to have two aspects, each serving a different audience. One is implemented today; the other is planned.

=== The Document

The first aspect is a human-readable document. It expresses the organization's mission, its values, the social contract between members, and the intent behind its rules. This is what members read when they join, what they reference during disputes, and what they amend when the organization's direction changes.

Today, the on-chain Charter object is deliberately minimal: it holds the organization's name and a metadata URI --- an IPFS content identifier --- that points to the current document. The document itself lives off-chain. Amending the charter is a governance action that updates this pointer, and the on-chain proposal log records every amendment: which proposal changed the reference, when, and to what. Anyone can reconstruct the constitutional evolution of the organization from that log.

#aside[
  _Planned._ Future versions of the Charter object will hold a content hash for on-chain integrity verification and an explicit version number, so the object itself --- not just the surrounding event log --- attests to what the charter said at any point in time.
]

A charter might state that "the treasury shall not be used for personal expenses." No smart contract can fully enforce that, but the community can hold its governance accountable to it. The document is the voice of organizational intent.

=== The Invariants (Planned)

The second aspect, not yet implemented, is a set of on-chain invariants defined directly on the Charter object: structured, machine-readable parameters that proposals read and enforce.

Where the document expresses _what the organization believes_, the invariants would encode _what the organization protects_ --- what members care about maintaining throughout the current lifecycle of the DAO.

A charter invariant might set a maximum single treasury withdrawal. A proposal that attempts to exceed it would fail --- not because a voter caught it, but because the framework reads the invariant and enforces it. Another invariant might set a floor on the quorum for charter amendments, ensuring that constitutional changes always require broad participation regardless of how governance parameters evolve.

Invariants would parametrize proposals: the bridge between the charter's intent and the proposal system's execution, the mechanism by which organizational physics become enforceable. Until they land, the framework's fixed safety floors --- the enable and self-referential thresholds described in the proposal chapter --- provide the analogous non-negotiable guarantees.

== How the Two Aspects Will Compose

The document and the invariants are not meant to be separate systems. They are two expressions of the same constitution.

The document says: "We believe in conservative treasury management." The invariant encodes: maximum single withdrawal of 500 EVE. The document provides the reasoning; the invariant provides the enforcement. Members would amend both through the same governance process, and the amendment log records the changes together.

This duality is what will make the charter a living constitution rather than a static declaration. The human-readable layer evolves through debate and consensus. The machine-readable layer evolves alongside it, translating intent into constraints that the system respects.

== Amending the Charter

Amending the charter is one of the most consequential governance actions a DAO can take. Today an amendment is a proposal that updates the charter's document pointer; the recommended configuration reflects the gravity of a constitutional change:

- A high approval threshold --- reflecting constitutional significance.
- A multi-day execution delay --- ensuring the full membership has time to review and respond.
- A cooldown period --- preventing rapid-fire amendments that could destabilize the organization.
- An extended voting window --- allowing sufficient time for deliberation.

Once on-chain invariants land, changing an invariant will be a constitutional act in the same sense --- it changes the physics of the organization, and it should carry the same weight as rewriting the charter's text.

== Organizational DNA

The Charter is the source of truth from which the organization's stated mission derives, and the anchor around which its governance record accumulates.

That record is permanent. Because every amendment flows through a proposal, the on-chain log preserves how the rules changed, which proposals drove those changes, and --- through the document pointers it references --- what the organization declared at each step. Future members can trace the whole arc.

In a game world where civilizations rise and fall, this permanence matters. The charter is the DAO's contribution to the historical record of Frontier. DAO archaeology --- the study of organizational evolution through on-chain constitutional history --- becomes possible.
