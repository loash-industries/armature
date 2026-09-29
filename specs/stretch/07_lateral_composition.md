# Stretch: Lateral Composition — Multi-Membership

> Part of the [stretch features index](00_index.md). Not in hackathon scope.

---

An OU can simultaneously occupy multiple positions in the organizational graph:
- Be a SubOU of Tribe A
- Be a federation member of the Haulers' Alliance
- Be a controller of its own SubOUs

These roles are not mutually exclusive because they are encoded in independent capability objects.

```
                    ┌──────────────────────┐
                    │  Haulers' Alliance   │  ← Federation OU
                    │    (Federation)      │
                    └──┬──────────┬────────┘
                       │          │
              FedSeat  │          │  FedSeat
                       │          │
              ┌────────▼──┐   ┌──▼─────────┐
              │  Tribe A  │   │  Tribe B    │  ← Independent OUs
              │  (OU)    │   │  (OU)      │
              └─────┬─────┘   └─────────────┘
                    │
           SubOUCtl│
                    │
              ┌─────▼─────┐
              │ Logistics  │  ← SubOU of Tribe A
              │ (SubOU)   │
              └─────┬──────┘
                    │
           SubOUCtl│
                    │
              ┌─────▼─────┐
              │ Fleet Ops  │  ← SubOU of Logistics
              └────────────┘
```

The OU Atom boundary (see [01 Vision](../01_vision.md) — The OU Atom) is preserved at every node. Cross-atom operations — `SubOUControl` edges downward, `FederationSeat` edges upward — require governance actions on both sides.

---

**See also:** [Federation System](01_federation.md) for upward composition, [SubOU Hierarchy](../04_subou_hierarchy.md) for downward composition.
