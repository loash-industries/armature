# Changelog

## 2026-11-21 — version gating in armature_framework (ARMATURE-45)

New `armature::version` module (`VERSION`, `MIN_SUPPORTED`, `EVersionRetired`, `VersionFloorRaised`). All 8 shared framework types (`OU`, `CapabilityVault`, `TreasuryVault`, `Charter`, `EmergencyFreeze`, `Proposal`, `CompositeFrame`, `EncryptedEntry`) carry `min_version: u64`; `ExecutionRequest`, `CapLoan` and `Pipeline` carry the floor of the object that minted them (a ticket and an `AssetTransfer` through their request). New objects start at `MIN_SUPPORTED`, or the parent's floor for SubOUs, SpawnOU successors and companions (`ou::create_with_floor`, `ou::create_subou_configured_with_floor`; the package-only `create_*returning_vault*` constructors and `proposal::create/execute/execute_single_vote/privileged_execute/new_ticket_composite` take the floor as a new parameter). Every public function that changes state checks `VERSION >= min_version` first, and `&mut` paths raise the floor to `MIN_SUPPORTED`; each module has a permissionless `enforce_version` (`proposal::enforce_proposal_version`) that only raises it. Getters stay ungated. `scripts/check_version_gates.py` (in `pr.yml`) fails on an ungated state-changing function; `tests/version_tests.move` covers the module, creation floors, `enforce` and hot-potato stamps; `docs/version-gating.md` is the upgrade runbook. Public signatures used by dependents are unchanged.

## 2026-11-21 — `ou::share_subou` is framework-only (ARMATURE-45)

`ou::share_subou` is now `public(package)`. Through Cycle 7 it was `public`, and because Sui lets a transaction take an already-shared object by value as long as it re-shares it, anyone could pass a live OU and overwrite its `controller_cap_id`: permanently marking a root OU as controlled (blocking SpawnOU, CreateSubOU, SpinOutSubOU and the bypass meta-types) or moving a SubOU's pointer off its bound control. Its only callers, `tribe` and `lifecycle_ops`, pass OUs they have just created. Tests outside the framework use the new `#[test_only] ou::share_subou_for_testing`. First step of the version-gating design; the gate itself follows.

## 2026-11-06 — actions pinned by SHA, GH_AUTH_TOKEN retired (DEVOPS-30, DEVOPS-22)

Every `uses:` in `.github/` is pinned to a full commit SHA with the version in a comment; the shared `workflows` calls point at v0.7.0 (`511ec50`), and `deploy.yml` stays on the `@v0.7.0` tag because the `github-deploy-*` role trusts only that tag. The cortex-ingest call no longer passes `GH_AUTH_TOKEN`, and checkouts in build and test jobs use `persist-credentials: false`.

## 2026-10-28 — re-pin armature_world_bridge to cycle-7 world and republish to testnet_stillness

- Re-pinned `armature_world_bridge`'s `world` dependency from world-contracts `32300a2` (cycle-6 stillness world `0x8b8a46ed…`) to `d33ff23` (cycle-7 stillness world `0x7be18d62…`), matching the pin already used by `armature_vault` and `warehouse_receipts`, and fresh-published to `testnet_stillness` at `0xc828b10fdabb0e7ae38e3d8c46942d5ab087f663a1b051c68e77aa6c0dbbc928` (tx `3ch8FKvrXg7L3xAKfemZbMujxJS2eAUCrSSiaDx1hRaf`, UpgradeCap `0x8eed2832b73c51f70e48ae92dd75ef7c6323a1bb941be2fa506f4fadd4b19509`, sui 1.74.1). Supersedes the earlier same-day publish at `0xd00fbd11…`, which linked the cycle-6 world and could therefore not autojoin cycle-7 Characters. No source changes; the world's character API is unchanged between the two revisions.

## 2026-10-28 — publish armature_world_bridge to testnet_stillness

- Published `armature_world_bridge` to Sui testnet under the `testnet_stillness` env at `0xd00fbd1136ebae2f58677adffbca0532a5be564226b706b8e0dc4e197470cebe` (tx `FkVJFFBYc5xty4GiYVSTLcGPQeUmEXwMD2x2rS6XWcwp`, UpgradeCap `0x4d8bdcc5b4926bb80c86fdb514036c017169795f6d6f741288353369e406b8a9`, sui 1.74.1). Added the generated `Published.toml` record for the package. No source changes.
