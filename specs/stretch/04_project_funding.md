# Stretch: Project Funding Lifecycle

> Part of the [stretch features index](00_index.md). Not in hackathon scope.

A project is a SubDAO with Kickstarter-style lifecycle.

---

## 1. The Pattern

| Primitive | Role in Project |
|---|---|
| **SubDAO** | Project entity, controlled by parent tribe |
| **Board governance** | PO + backers form the board |
| **Charter** | Defines scope, funding target, milestones, revenue splits |
| **TreasuryVault** | Holds project funds, receives revenue |

## 2. Revenue Distribution

```rust
struct DistributeRevenue<phantom T> has store { }

struct RevenueDistributionState has store {
    splits:                vector<RevenueSplit>,
    last_distribution:     u64,
    distribution_interval_ms: u64,
    total_distributed:     u64,
}

struct RevenueSplit has copy, drop, store {
    recipient: address,
    bps:       u16,
    label:     String,
}
```

## 3. Stock Ticker Registry

On-chain registry for unique token symbols. Commit-reveal registration to prevent front-running.

```rust
struct TickerRegistry has key {
    id:          UID,
    tickers:     Table<String, TickerEntry>,
    commitments: Table<address, MaskedBid>,
}
```

Pricing tiers: 1-char = 500 SUI, 2-char = 100 SUI, 3-char = 25 SUI, 4-char = 0.75 SUI.

Token deployment via browser-based bytecode templating (`@mysten/move-bytecode-template`).

## 4. Project Funding Threats

- **PO Rug Pull:** Mitigated by `SubDAOControl` (parent can pause/replace board/reclaim funds), board expansion as backers join, `execution_delay_ms`.
- **Token Manipulation:** `TreasuryCap` in `CapabilityVault` — minting requires governance proposal.

---

**See also:** [SubDAO Hierarchy](../04_subdao_hierarchy.md) for the control mechanisms that protect backers.
