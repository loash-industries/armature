#import "lib/template.typ": armature-paper

#show: armature-paper.with(
  title: [Armature.NETWORK],
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
    ownership is individual, delegation is nonexistent, and value capture is difficult.
    We present Armature, a Programmable Organizational Assembly (POA) protocol on the SUI blockchain that
    addresses these structural barriers. Every POA comprises a governance root, a
    multi-coin treasury, a capability vault, a constitutional charter, and an emergency
    circuit breaker --- five independent shared objects that can be accessed concurrently
    and composed in arbitrary configurations. The proposal system, secured through SUI's
    hot potato pattern, serves as the sole mechanism of state change: there are no admin
    keys, no backdoors, and no special-case pathways. POAs reproduce by spawning Sub-POAs with delegated authority
    that can be atomically reclaimed by the parent, self-amend through proposals that can
    modify their own rules, and federate with peers without surrendering sovereignty.
    The protocol establishes the organizational primitive from which tribal economies,
    inter-tribe trade, and civilization-scale coordination can emerge.
  ],
)

#include "chapters/01-introduction.typ"
#include "chapters/02-thesis.typ"
#include "chapters/03-poa-primitive.typ"
#include "chapters/04-governance.typ"
#include "chapters/05-proposals.typ"
#include "chapters/06-treasury-capabilities.typ"
#include "chapters/07-charter.typ"
#include "chapters/08-subpoa-hierarchy.typ"
#include "chapters/09-security.typ"
#include "chapters/10-organic-poa.typ"
#include "chapters/11-future-vision.typ"
#include "chapters/12-conclusion.typ"
