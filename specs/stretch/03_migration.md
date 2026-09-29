# Stretch: Migration via SpawnOU

> Part of the [stretch features index](00_index.md). Not in hackathon scope.

---

Creates successor OU with new governance model. Old OU enters `Migrating` status — only `TransferAssets` executable. After all assets transferred, `ou::destroy` deletes all companion objects.

```rust
struct SpawnOU has store { ... }     // creates successor
struct TransferAssets has store { ... } // moves assets batch-by-batch
```

Recommended limit: ~50 assets per `TransferAssets` call.

This is the only mechanism for changing an OU's governance type (Board → Direct, Direct → Weighted, etc.), enforcing the immutable-governance-model principle from [01 Vision](../01_vision.md) Pillar 2.

---

**Related invariants** (from [03 Core Spec](../03_core_spec.md)):

| Invariant |
|---|
| `OUStatus` transitions: `Active → Migrating`. No path back. |
| While `Migrating`, only `TransferAssets` can be created/executed. |
| `ou::destroy` requires `Migrating` status AND empty vaults. |
| After destruction, in-flight proposals are unexecutable (OU object gone). |
