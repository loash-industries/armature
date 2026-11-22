# Version gating (ARMATURE-45)

Every published version of a Sui package stays callable forever, and an object made by one version is the same type in all of them. `armature_framework` therefore carries a version floor on each object, so a newer publish can switch older code off, object by object. The design and the trade-offs behind it are in the [design doc](https://claude.ai/artifact/VqhSPvHj59kgfJzUkXHKRt).

## How it works

| Piece | Where | What it does |
|---|---|---|
| `VERSION`, `MIN_SUPPORTED` | `sources/version.move` | This release's version, and the oldest version it still trusts. |
| `min_version: u64` | `OU`, `CapabilityVault`, `TreasuryVault`, `Charter`, `EmergencyFreeze`, `Proposal`, `CompositeFrame`, `EncryptedEntry` | The oldest version allowed to act on the object. Starts at `MIN_SUPPORTED`, or the parent's floor for a SubOU, a SpawnOU successor and an OU's companions. |
| Stamp | `ExecutionRequest`, `CapLoan`, `Pipeline` (and `ExecutionTicket`, `AssetTransfer` through the request they wrap) | The highest floor among the objects that minted it, raised to the minting release's `MIN_SUPPORTED`. Every consumer checks it both ways (`version::assert_stamp_supported`). |
| Check | 89 public functions that change state, `encrypted_entry::seal_approve`, and the `enforce` functions | `VERSION >= min_version`, else `version::EVersionRetired`. `&mut` paths also raise the floor to `MIN_SUPPORTED`. A hot-potato stamp below `MIN_SUPPORTED` aborts with `version::EMintedByRetiredVersion`. |
| `enforce_version` / `enforce_proposal_version` | each object module | Permissionless. Raises the floor to `MIN_SUPPORTED`, never lowers it, and emits `version::VersionFloorRaised` when it moves. |

Why stamps are checked both ways: an object's floor only rises when something touches it, so right after a security upgrade an OU can still sit at the old floor while its treasury has already been raised (anyone can call `deposit`). Without the lower bound, retired code could mint a ticket from the unswept OU, and current code would accept it and spend it against the raised treasury. Only a retired release can mint a stamp below the current `MIN_SUPPORTED`, so current code refuses it.

An unsealed `CompositeFrame` is an owned object, so the sweep can't reach it. Its floor is never raised while it is unsealed. `add_step*`, `submit_composite` and `enforce_version` refuse a frame below `MIN_SUPPORTED` (`EMintedByRetiredVersion`), so a frame whose steps a retired `add_step` checked has to be rebuilt. Sealed frames are shared and are raised like any other object.

`encrypted_entry::seal_approve` is gated even though it only reads: Seal key servers accept `seal_approve` from any version of the package, so without the check a retired version's key-release policy would hold forever.

Getters stay ungated, so dependents linked to an older framework can always read. `scripts/check_version_gates.py` (run in CI) fails if a public function that takes a gated object `&mut` or by value, takes a hot potato by value, or is one of the read-only authority paths (vault borrows, ticket mints, `ticket_request`) skips the check.

Root OUs (`ou::create`, `tribe::create_tribe*`) and composite frames (`composite::new_frame`) take no gated object, so retired code can still create one after a sweep. Run the sweep until no object reads below the floor.

## Routine upgrade (no security fix)

1. Bump `VERSION` in `version.move`. Leave `MIN_SUPPORTED` alone.
2. Upgrade the framework.
3. Relink dependents when convenient: their old linkage keeps working on every object.

## Security upgrade

1. Fix the bug, or make the buggy function abort. Set `MIN_SUPPORTED = VERSION`.
2. Build relinked upgrades of every dependent that calls gated functions (`armature_proposals`, `armature_world_bridge`, `armature-trading`). Tell third-party extension authors the date.
3. Upgrade the framework, then the dependents straight after.
4. Sweep: list every live shared framework object from the indexer and call its `enforce_*` function, in batches sized by a dry run.
5. Check every object reads `min_version >= MIN_SUPPORTED` (the indexer can track `VersionFloorRaised`). Re-sweep objects created since step 4.
6. Point the SDK and apps at the new package ID, and map `version::EVersionRetired` to "update the app".

Sweep OUs, proposals and companions together. Until an OU is swept, retired code can still mint requests from it, though current code refuses them and retired code can't use them on objects that are already swept.

Until an object is swept, retired code can still act on it. Any object used in the meantime moves forward on its own, because gated `&mut` paths raise the floor. Dependents linked below the new floor abort on swept objects until they relink, which is why they upgrade straight after the framework.

## UpgradeCap custody during a security upgrade (interim)

`ProposeUpgrade` and its handler live in `armature_proposals`, which is linked to one framework version. After a security upgrade, anyone can call `enforce_version` on the governing OU or its vault, and so can ordinary traffic to the new package. From then on the old-linked handler aborts in `ticket_request` and `loan_cap`. The relink vote can't start before the new framework exists, because the upgrade digest names it. So an UpgradeCap held in an OU vault would be stuck behind a handler that can't run.

Until the handler moves into the framework (ARMATURE-48), keep package UpgradeCaps (the framework's and every dependent's) outside OU vaults, for example in a multisig. If one is already vault-held, move it out of the vault before you publish a security upgrade. Routine upgrades are unaffected, because they leave `MIN_SUPPORTED` alone.

## Rehearsal

`scripts/rehearse_version_gating.sh` runs both upgrade kinds end to end on a throwaway localnet, with its own client config (your `~/.sui` config and the repo's packages are not touched). It publishes the framework at v1, publishes `armature_proposals` and a one-function probe package linked to v1, creates two OUs, then:

- routine upgrade (VERSION 2, MIN_SUPPORTED 1): v1, v2 and the v1-linked probe all work; floors stay at 1;
- security upgrade (VERSION 3, MIN_SUPPORTED 3), sweeping only OU A: v1, v2 and the probe abort in `version::assert_supported` on A but still work on B; v3 works on both and raises B's floor to 3 as it goes, after which v1 aborts on B too.

`armature_world_bridge` needs world-contracts on localnet, so the rehearsal uses the probe to observe old linkage at run time; old linkage behaves the same for every dependent. Run it before every security upgrade, with the real fix in place.

