= Thesis

The tribe is the atom of civilization in Frontier. Not the individual player, not the alliance, not the market.

A tribe is a group of players bound by a shared vision and a willingness to pool their time and resources toward common goals. Everything larger --- trade networks, federations, civilization itself --- is composed from tribes.

For civilization to emerge, a tribal economy must come first.

Tribes must be able to capture and track the time and energy of their members, fund infrastructure projects, and share the returns. Only then can inter-tribe trade develop naturally. Only from inter-tribe trade can a Trinary-wide trading network arise.

== The Platform Gap

Today, tribes have no way to do any of this on-chain.

- They cannot *capture value* --- there is no way to track member contributions, issue shares, or share returns from group operations.
- They cannot *reward participation* --- without clear funding and reward structures, large projects depend entirely on the personal investment of a few individuals.
- They cannot *delegate authority* --- a tribe that grows beyond a handful of members has no way to create teams with their own budgets and responsibilities.
- They cannot *scale governance* --- decisions are informal, unrecorded, and unenforceable.

Tribes stay small, fragile, and short-lived.

The ambitious projects that would define Frontier's gameplay --- gate networks, logistics chains, manufacturing groups, research teams --- never happen. No group can sustain the organizational complexity they require.

== Our Solution: A Protocol, Not a Product

The solution cannot be another DApp. It must be a _protocol_.

A shared language that every player and group can speak. A baseline that handles organization, enables value capture, and supports the full range of governance styles that groups naturally adopt.

#import "../lib/template.typ": principle

#principle[Design Principle][
  Armature is not a product built on Frontier's primitives. It is a protocol that makes Frontier's primitives usable by organizations. The DAO is not a voting tool --- it is the organizational primitive for an entire player economy.
]

A tribe creates a DAO. The DAO holds a treasury, defines a charter, and governs itself through typed proposals.

As the tribe grows, it spawns Sub-DAOs as departments --- Engineering, Logistics, Diplomacy --- each with their own budgets and governance rules. Those departments run projects. Revenue flows back through treasury vaults.

The DAO framework is the governance layer. Everything else --- markets, logistics networks, registries, ticketing systems --- builds on top.

== The Four Pillars

Every organization, regardless of purpose, breaks down into four parts:

+ *Players* gather under a vision and a governance style. The specific model --- majority vote, weighted stake, delegated authority --- varies. The presence of a defined membership with defined rules is universal.

+ *Charter* --- the constitution. It encodes the vision, the rules of membership, the governance parameters, and how they can be changed. It is the DNA of the organization: the axioms from which all behavior follows.

+ *Treasury* --- the collective pool. Players contribute time and resources; the treasury holds them under shared custody. Accessing the treasury requires governance approval. The treasury is both the fuel and the measure of what the organization can do.

+ *Proposals* --- the inference engine. Every state change --- spending funds, changing the charter, adding members, creating departments --- flows through the proposal system. Proposals are the only way to change the organization's state.

These four form a closed loop.

The charter sets the rules for proposals. Proposals can change the charter. Proposals define which proposal types exist.

This self-referential structure is what makes a DAO self-governing. It can evolve its own rules without outside intervention.

#figure(
  image("../figures/DAO Primitive.pdf", width: 100%),
  caption: [Anatomy of a DAO --- Players issue and vote on Proposals, which give access to the Treasury and amend the Charter. The Charter parametrizes Proposals, and Proposals can expand or reduce their own set.],
)

