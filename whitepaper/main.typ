#import "lib/template.typ": armature-paper

#show: armature-paper.with(
  title: [Armature Project],
  subtitle: [A Programmable Organization Framework\ for Frontier Civilization],
  authors: (
    (
      name: "Ergod",
      affiliation: "ergod@awar.dev",
    ),
    (
      name: "Hecate",
      affiliation: "michael@loash.xyz",
    ),
  ),
  date: [Draft --- March 2026],
  abstract: [
    EVE Frontier provides powerful programmable primitives --- Smart Assemblies ---
    designed to be the backbone of player-driven gameplay, yet players lack the
    organizational infrastructure to wield them collectively. Trust is informal,
    ownership is individual, delegation is challenging, and value capture is difficult.
    We present Armature, a Decentralized Autonomous Organization (DAO) protocol on the SUI blockchain that
    addresses these structural barriers. Every DAO comprises a governance root, a
    multi-coin treasury, a capability vault, a constitutional charter, and an emergency
    circuit breaker --- five independent shared objects that can be accessed concurrently
    and composed in arbitrary configurations. The proposal system, secured through SUI's
    hot potato pattern, serves as the sole mechanism of state change: there are no admin
    keys, no backdoors, and no special-case pathways. DAOs reproduce by spawning Sub-DAOs with delegated authority
    that can be atomically reclaimed by the parent, self-amend through proposals that can
    modify their own rules, and federate with peers without surrendering sovereignty.
    Because organizational primitives are shared rather than reimplemented per application,
    higher-level utilities --- markets, logistics tools, registries --- inherit common
    revenue routing and access control without custom integration.
    The protocol establishes the organizational substrate from which tribal economies,
    inter-tribe trade, and civilization-scale coordination can emerge.
  ],
)

#include "chapters/01-motivation.typ"
#include "chapters/02-dao-primitive.typ"
#include "chapters/03-members-governance.typ"
#include "chapters/04-treasury-capabilities.typ"
#include "chapters/05-proposals.typ"
#include "chapters/06-charter.typ"
#include "chapters/07-security.typ"
#include "chapters/08-depth-abstraction.typ"
#include "chapters/09-addressing.typ"
#include "chapters/10-organic-lifecycle.typ"
