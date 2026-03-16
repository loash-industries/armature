# Stretch: Lateral Composition — Multi-Membership

> Part of the [stretch features index](00_index.md). Not in hackathon scope.

---

A DAO can simultaneously occupy multiple positions in the organizational graph:
- Be a SubDAO of Tribe A
- Be a federation member of the Haulers' Alliance
- Be a controller of its own SubDAOs

These roles are not mutually exclusive because they are encoded in independent capability objects.

```
                    ┌──────────────────────┐
                    │  Haulers' Alliance   │  ← Federation DAO
                    │    (Federation)      │
                    └──┬──────────┬────────┘
                       │          │
              FedSeat  │          │  FedSeat
                       │          │
              ┌────────▼──┐   ┌──▼─────────┐
              │  Tribe A  │   │  Tribe B    │  ← Independent DAOs
              │  (DAO)    │   │  (DAO)      │
              └─────┬─────┘   └─────────────┘
                    │
           SubDAOCtl│
                    │
              ┌─────▼─────┐
              │ Logistics  │  ← SubDAO of Tribe A
              │ (SubDAO)   │
              └─────┬──────┘
                    │
           SubDAOCtl│
                    │
              ┌─────▼─────┐
              │ Fleet Ops  │  ← SubDAO of Logistics
              └────────────┘
```

The DAO Atom boundary (see [01 Vision](../01_vision.md) — The DAO Atom) is preserved at every node. Cross-atom operations — `SubDAOControl` edges downward, `FederationSeat` edges upward — require governance actions on both sides.

---

**See also:** [Federation System](01_federation.md) for upward composition, [SubDAO Hierarchy](../04_subdao_hierarchy.md) for downward composition.
