# Changelog

## 2026-08-12 — automated whitepaper releases

- Added `.github/workflows/whitepaper-release.yml`, triggered by pushing a `whitepaper/v*` tag: it verifies the tag against the document version, compiles the PDF with Typst, and publishes a GitHub release with `armature-whitepaper.pdf` attached. Made the version single-sourced as `#let version` in `whitepaper/main.typ` (rendered on the title page and greped by CI, so a mismatched tag fails the build). Release notes are hand-written per version in `whitepaper/releases/<version>.md` and reviewed in the PR that bumps the version, falling back to auto-generated notes if absent. Documented the process in `docs/whitepaper-release.md` and repointed the README whitepaper link from the pinned v0.1.0 tag to `releases/latest`.

## 2026-08-09 — whitepaper accuracy revision (v0.2)

- Corrected the whitepaper to align with the implemented Move framework. Clarified governance as Board-only with Direct/Weighted reserved as planned variants. Corrected voting to require both quorum and approval threshold. Stated safety-floor constants accurately (66% enable, 80% config-change/bypass). Fixed emergency freeze mechanics: `FreezeAdminCap` issued to creator, unfreeze/config/transfer require proposals, 7-day auto-expiry, unfreeze/transfer-admin permanently exempt. Documented composite proposals as fully implemented (≤16 steps, no nesting, component-wise max config). Reframed the Charter as a name + IPFS metadata-URI pointer, and the addressing/ticker-registry chapter and upward federation, as planned/unimplemented. Acknowledged the two governance-gated non-vote execution paths. Added missing built-in proposal domains (currency mint/burn, package upgrades).

## 2026-06-13

- Initial Cortex onboarding: created `.cortex/manifest.yaml`, `overview.md`, and `CLAUDE.md`
