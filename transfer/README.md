# SCargo Clean-Room Transfer Airlock (`transfer/`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

This directory defines the separation plane between `SCargo` and the target flight article (`Ergentics1/Riemannian`).

## Contents

- [`ICD-RIEMANNIAN.md`](ICD-RIEMANNIAN.md): Interface Control Document (`ICD-SCARGO-RIEM-001`) defining Zone A (no-touch verification core), Zone B (documentation), Zone C0–C5 (qualified proof-reduction zones), Gates G1–G5, and retest triggers.
- [`packages/rung3_airlock_manifest_v1.json`](packages/rung3_airlock_manifest_v1.json): Declarative Rung 3 clean-room airlock manifest staging `PKG-R3-Z0-DEAD-LEAVES`, `PKG-R3-Z1A-ALIAS-INPLACE`, and `PKG-R3-Z1B-WRAPPER-COLLAPSE`, along with `UP-07` batching constraints and 7 adversarial airlock negative controls.
- [`bundles/arc5_preflight_bundles_v1.json`](bundles/arc5_preflight_bundles_v1.json): Declarative Arc 5 dual-route `UP-07` pre-flight shard and full-runner bundle receipt covering `Z-C0` (112 dead leaves), `Z-C1A` (46 Strategy A wrappers), `Z-C2` (24 explicit-heavy `CapelliIdentities` files), and `Z-C4` (`EveryCharacterOfLiteratureOfVWin.lean` transitive import hub prune) — 24 shards (`18` `quick_check`, `6` `full_rh_build`) + 4 full bundles with SHA-256 receipts, zero Zone A paths, and zero verbatim proof bodies (`target_repo_mutation_allowed = false`).

## Separation Invariant (`UP-08` & Flight-Article Protection)

1. Zero verbatim Lean proof files from `Ergentics1/Riemannian` are copied into `SCargo` (`UP-08`).
2. `Ergentics1/Riemannian` stays **100% untouched** during all clean-room G1–G3 qualification runs (`target_repo_mutation_allowed = false`).
3. Crossing the airlock into G4–G5 flight-article elaboration (`leanchecker-paranoid` + `nanoda_bin`) requires explicit user sign-off on a dedicated feature branch of `Ergentics1/Riemannian`.
