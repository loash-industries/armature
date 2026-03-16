# Stretch: Governance Models

> Part of the [stretch features index](00_index.md). Not in hackathon scope.
>
> Hackathon scope covers Board governance only — see [03 Core Spec](../03_core_spec.md) section 3.

---

## 1. Direct Governance

Shareholders vote directly. Weight proportional to share count in `VecMap<address, u64>`.

```rust
GovernanceConfig::Direct { voters: VecMap<address, u64>, total_shares: u64 }
```

Proposal types: `AddVoter`, `RemoveVoter`.

**Sybil risk:** Vote weight accumulation via multiple addresses. Mitigated by per-proposer concurrency caps, voter weight curves.

---

## 2. Weighted Governance

Shareholders stake governance tokens and delegate weight to delegates (capped at 20). Proposals snapshot delegate weights at creation.

```rust
GovernanceConfig::Weighted { delegates: VecMap<address, u64>, total_delegated: u64 }
```

Requires `staking.move` for `StakePosition` management.

**Flash-stake risk:** Governance capture via flash loans. Mitigated by minimum lock period, snapshot-time stake-age filtering.

---

**See also:** [Migration](03_migration.md) for how a DAO transitions between governance models via `SpawnDAO`.
