= Addressing Scheme

#import "../lib/template.typ": aside, principle

Organizations need names. On-chain object IDs are precise but meaningless to humans. A DAO that wants to be found, recognized, and trusted needs an identity that is stable, scarce, and legible.

== The Ticker Registry

Armature provides a protocol-level Ticker Registry. A ticker is a short identifier --- five characters maximum --- that maps to a DAO's object ID. Think of it as a domain name for organizations.

`TRIB` maps to a DAO. `FORGE` maps to another. The registry is the canonical lookup: given a ticker, anyone can resolve the DAO behind it.

Tickers are scarce by design. Five characters means a finite namespace. This scarcity gives tickers value --- and legitimacy. A DAO that holds `TRIB` is the one and only `TRIB`. There is no impersonation, no spoofing, no confusion. The ticker is a verified identity.

Registration is optional. Not every DAO needs a public name. Small working groups, temporary task forces, internal departments --- these can operate without a ticker. But for organizations that want to be addressable, discoverable, and recognized, the ticker is the entry point.

#principle[Protocol Revenue][
  Ticker registration is one of the ways the protocol generates revenue. Scarce names in a shared namespace are a natural economic primitive --- valuable to the organizations that hold them, and a sustainable funding mechanism for the protocol that maintains them.
]

== Recursive Addressing

The ticker system scales with organizational depth. Sub-DAOs are addressed relative to their parent, using path syntax:

`TRIB/ENG` --- the Engineering department of TRIB.\
`TRIB/ENG/UI` --- the UI team within Engineering.\
`TRIB/LOG/EAST` --- the Eastern regional office of the Logistics department.

Each segment is a ticker within its parent's namespace. The top-level ticker comes from the protocol registry. Sub-tickers are managed by the parent DAO --- creating a sub-ticker is a governance action, just like any other organizational decision.

This gives the addressing scheme the same recursive structure as the organizational hierarchy itself. Depth is reflected in the path. A glance at the address tells you where an organization sits in the hierarchy.

== Upward Addressing

Federations and super-DAOs draw their tickers from the same top-level registry. A federation of tribes might register as `AXIS`. Its members --- `TRIB`, `FORGE`, `NOMAD` --- retain their own tickers. The federation's identity is independent of its members, just as its governance is.

There is no special syntax for upward composition. Super-DAOs are top-level entities with top-level tickers. The relationship between a federation and its members is expressed through governance, not through the address.

== Identity Across Time

Organizations change. They migrate to new governance models, spawn successors, merge with peers. Object IDs change with each migration. But the ticker persists.

Access to the ticker is handled through a capability stored in the DAO's vault. When a DAO migrates --- creating a successor and transferring all vault contents --- the ticker capability moves with everything else. The new DAO resolves to the same ticker. The address is stable even as the underlying identity shifts.

This means external systems, other DAOs, and players can reference `TRIB` and know that the reference will resolve correctly regardless of how many times the organization has migrated, restructured, or evolved. The ticker is the stable handle in a world of mutable state.

== The Address as Meaning

The full addressing scheme --- `TRIB/ENG/UI` --- is more than a lookup mechanism. It is a legible representation of organizational structure.

It tells you that UI is a team within Engineering, which is a department of TRIB. It tells you the depth. It tells you the chain of accountability. And because each segment is a ticker governed by the segment above it, it tells you that the structure was deliberate --- each level was named by its parent through governance.

// ? What are the rules for ticker syntax --- allowed characters, case sensitivity, reserved names?
// ? How are ticker disputes resolved --- first-come-first-served, auction, governance vote?
// ? Can tickers be transferred between unrelated DAOs, or only through migration?
// ? How does the registry handle expired or abandoned tickers --- do they return to the pool?
