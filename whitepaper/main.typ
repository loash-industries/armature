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
  date: [Draft (v0.2) --- August 2026],
  abstract: [
    EVE Frontier provides powerful programmable primitives --- Smart Assemblies ---
    designed to be the backbone of player-driven gameplay, yet players lack the
    organizational infrastructure to wield them collectively. Trust is informal,
    ownership is individual, delegation is challenging, and value capture is difficult.
    We present Armature, a Decentralized Autonomous Organization (DAO) protocol on the SUI blockchain that
    addresses these structural barriers. Every DAO comprises a governance root, a
    multi-coin treasury, a capability vault, a constitutional charter, and an emergency
    circuit breaker --- five independent shared objects that can be accessed concurrently
    and composed in arbitrary configurations. Governance is the root of all authority:
    the proposal system, secured through SUI's hot potato pattern, is the primary
    mechanism of state change, and there are no admin keys and no backdoors outside it.
    Two additional execution paths --- a parent's override of a controlled Sub-DAO and an
    opt-in external-authorization bypass --- are themselves gated by governance. DAOs
    reproduce by spawning Sub-DAOs with delegated authority that the parent can reclaim,
    and self-amend through proposals that can modify their own rules. Multi-step decisions
    are expressed as composite proposals that execute atomically. A planned federation layer
    will let sovereign DAOs associate as peers without surrendering sovereignty.
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
