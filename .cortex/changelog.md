# Changelog

## 2026-08-09 — whitepaper accuracy revision (v0.2)

- Corrected the whitepaper to align with the implemented Move framework. Clarified governance as Board-only with Direct/Weighted reserved as planned variants. Corrected voting to require both quorum and approval threshold. Stated safety-floor constants accurately (66% enable, 80% config-change/bypass). Fixed emergency freeze mechanics: `FreezeAdminCap` issued to creator, unfreeze/config/transfer require proposals, 7-day auto-expiry, unfreeze/transfer-admin permanently exempt. Documented composite proposals as fully implemented (≤16 steps, no nesting, component-wise max config). Reframed the Charter as a name + IPFS metadata-URI pointer, and the addressing/ticker-registry chapter and upward federation, as planned/unimplemented. Acknowledged the two governance-gated non-vote execution paths. Added missing built-in proposal domains (currency mint/burn, package upgrades).

## 2026-06-13

- Initial Cortex onboarding: created `.cortex/manifest.yaml`, `overview.md`, and `CLAUDE.md`
