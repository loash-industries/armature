= Motivation, Thesis and Vision

Civilization in EVE Frontier does not emerge from individuals. It emerges from the coordination of groups.

Tribes, syndicates, and alliances form the social layer of the game world. Yet there is a gap: the game gives players powerful programmable primitives --- Smart Assemblies --- meant to drive player-run gameplay, but players have no way to use them together.

Groups rely on informal coordination tools to manage operations that involve real on-chain assets. Trust is social, ownership is individual, delegation is challenging.

When leaders leave or groups break apart, disputes are difficult to resolve. Who contributed what, and what they are owed, is rarely recorded and rarely enforced.

These are not minor problems. They are the reason a player economy has not emerged.

Smart Assemblies are composable, programmable, and powerful --- the building blocks exist for players to build empires. But the problem is not what the technology can do. It is what players can organize. Building applications on top of assemblies is necessary but not enough. Players need tools that fit how they already organize --- tools that solve problems they already have.

== What Players Are Missing

- *Trust infrastructure* --- a way to define who can do what and enforce it, without relying on personal trust.
- *Shared ownership* --- assets that belong to the group, not to one person's wallet.
- *Delegation* --- the ability to create teams and departments with clear, limited authority.
- *Value capture* --- a way to track contribution, share revenue, and fund group projects from a common pool.

These needs are the same across every tribe, syndicate, and alliance in Frontier.

When each builder solves these problems independently, the result is an ecosystem of isolated systems that struggle to interoperate. Revenue routing, access control, treasury management --- every application reinvents them from scratch. Players end up with a dozen tools that each work alone but compose with nothing.

These problems must be solved at the protocol level --- not inside individual applications, but as a shared substrate that every group can build on and every application can assume.

== Thesis

The tribe is the atom of civilization in Frontier. Not the individual player, not the alliance, not the market.

A tribe is a group of players bound by a shared vision and a willingness to pool their time and resources toward common goals. Everything larger --- trade networks, federations, civilization itself --- is composed from tribes.

For civilization to emerge, a tribal economy must come first.

Tribes must be able to capture and track the time and energy of their members, fund infrastructure projects, and share the returns. Only then can inter-tribe trade develop naturally. Only from inter-tribe trade can a Trinary-wide trading network arise.

=== The Platform Gap

The on-chain tooling has not caught up. Tribes that want to capture value, reward participation, delegate authority, or scale their governance must build these systems from scratch --- if they build them at all.

Without this foundation, tribes plateau early. The ambitious projects that would define Frontier's gameplay --- gate networks, logistics chains, manufacturing groups --- require organizational complexity that few groups can sustain on their own.

== Our Solution: A Protocol, Not a Product

The solution cannot be another DApp. It must be a _protocol_.

A shared language that every player and group can speak. A baseline that handles organization, enables value capture, and supports the full range of governance styles that groups naturally adopt.

#import "../lib/template.typ": principle

#principle[Design Principle][
  Armature is not a product built on Frontier's primitives. It is a protocol that makes Frontier's primitives usable by organizations. The DAO is not a voting tool --- it is the organizational primitive for an entire player economy.
]

== Vision: The Four Pillars

Every organization, regardless of purpose, breaks down into four parts:

+ *Members* gather under a vision and a governance style. The specific model --- majority vote, weighted stake, delegated authority --- varies. The presence of a defined membership with defined rules is universal.

+ *Charter* --- the constitution. It encodes the vision, the rules of membership, the governance parameters, and how they can be changed. It is the DNA of the organization: the axioms from which all behavior follows.

+ *Vault* --- resource sovereignty. Players contribute time, energy, and assets; the vault holds them under shared custody. Capabilities --- gate controllers, upgrade caps, admin tokens --- sit alongside fungible assets. Accessing any resource requires governance approval. The vault is both the fuel and the measure of what the organization can do.

+ *Proposals* --- the inference engine. Every state change --- spending funds, changing the charter, adding members, creating departments --- flows through the proposal system. Proposals are the only way to change the organization's state.

These four form a closed loop.

The charter sets the rules for proposals. Proposals can change the charter. Proposals give access to the vault. Proposals define which proposal types exist.

This self-referential structure is what makes a DAO self-governing. It can evolve its own rules without outside intervention.

#figure(
  image("../figures/DAO Primitive.pdf", width: 100%),
  caption: [Anatomy of a DAO --- Players issue and vote on Proposals, which give access to the Vaults and amend the Charter. The Charter parametrizes Proposals, and Proposals can expand or reduce their own set.],
)

A tribe creates a DAO. The DAO holds vaults, defines a charter, and governs itself through typed proposals.

As the tribe grows, it spawns Sub-DAOs as departments --- Engineering, Logistics, Diplomacy --- each with their own budgets and governance rules. Those departments run projects. Revenue flows back through the vaults.

The DAO framework is the governance layer. Everything else --- markets, logistics networks, registries, ticketing systems --- builds on top.
