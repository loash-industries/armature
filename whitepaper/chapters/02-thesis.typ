= Thesis

Our thesis is structural: the tribe is the atom of civilization in Frontier. Not the individual player, not the alliance, not the market --- the tribe. A tribe is a group of players bound by a shared vision and a willingness to pool their time and resources toward common goals. Everything larger --- trade networks, federations, civilization itself --- is composed from tribes.

For civilization to emerge, a tribal economy must come first. Tribes must be able to capture and tokenize the time and energy of their members, fund infrastructure projects, and distribute the returns. Only then can inter-tribe trade develop organically, and only from inter-tribe trade can a Trinary-wide trading network arise.

== The Platform Gap

At present, tribes lack the platform to perform any of these functions on-chain:

- They cannot *capture value* --- there is no mechanism to account for member contributions, issue shares, or distribute dividends from collective operations.
- They cannot *incentivize participation* --- without formalized funding and reward structures, mid-to-large-scale infrastructure projects depend entirely on the goodwill and personal investment of a few individuals.
- They cannot *delegate authority* --- a tribe that grows beyond a handful of members has no way to create departments with scoped budgets and defined responsibilities.
- They cannot *scale governance* --- decision-making remains informal, unrecorded, and unenforceable.

The consequence is that tribes remain small, fragile, and short-lived. The ambitious projects that would define Frontier's emergent gameplay --- gate networks, logistics chains, manufacturing conglomerates, research institutions --- remain unrealized because no group can sustain the organizational complexity they require.

== Our Solution: A Protocol, Not a Product

The insight that drives Armature is that the solution cannot be another DApp. It must be a _protocol_ --- a shared language that every player and group can speak. A baseline that addresses organization, enables value capture, and supports the full spectrum of governance schemes that groups naturally adopt.

#import "../lib/template.typ": principle

#principle[Design Principle][
  Armature is not a product built on Frontier's primitives. It is a protocol that makes Frontier's primitives usable by organizations. The POA is not a voting tool --- it is the organizational primitive for an entire player economy.
]

A tribe creates a POA. The POA holds a treasury, defines a charter, and governs itself through typed proposals. As the tribe grows, it spawns Sub-POAs as departments --- Engineering, Logistics, Diplomacy --- each with their own budgets and governance parameters. Those departments run projects. Revenue flows back through treasury vaults. The POA framework is the governance layer; everything else --- markets, logistics networks, ticker registries, ticketing systems --- builds on top.

== The Four Pillars

We observe that every organization, regardless of its specific purpose, can be decomposed into four indivisible components:

+ *Players* gather under a vision and a governance style. The specific governance model --- whether majority vote, weighted stake, or delegated authority --- varies, but the presence of a defined membership with defined rules is universal.

+ *Charter* --- the constitution. It encodes the vision, the rules of membership, the governance parameters, and the amendment procedures. It is the DNA of the organization: the axioms from which all behavior derives.

+ *Treasury* --- the collective pool. Players contribute time and resources; the treasury holds them under shared custody. Accessing the treasury requires governance authorization. The treasury is both the fuel and the measure of the organization's capacity.

+ *Proposals* --- the inference engine. Every state change --- spending funds, amending the charter, adding members, creating departments --- flows through the proposal system. Proposals are the only way to mutate the organization's state, and the rules governing proposals are themselves subject to proposals.

These four components form a closed loop. The charter parametrizes proposals. Proposals can amend the charter. Proposals define which proposal types exist. This self-referential structure is not a bug --- it is the mechanism by which a POA becomes self-governing and self-amending, capable of evolving its own rules without external intervention.
