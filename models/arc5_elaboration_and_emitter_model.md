# Arc 5 Clean-Room Lean 4.36 Elaboration Harness & Deterministic Patch Emitter Model (`models/arc5_elaboration_and_emitter_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v1.0`

> **Separation Rule**: This document defines the **formal Arc 5 clean-room pre-flight elaboration & patch-emission model** only. All declarative shard manifests and pre-flight receipts live in [`transfer/bundles/arc5_preflight_bundles_v1.json`](../transfer/bundles/arc5_preflight_bundles_v1.json) (zero copied upstream Lean proof bodies per reconciled `UP-08`), all real Lean `v4.36.0` `module` elaboration tests run on original clean-room modules inside `compartments/lean/SCargoLean/Preflight/`, and `Ergentics1/Riemannian` stays **100% untouched** (`0` dirty files) until explicit G4–G5 flight-article sign-off.

---

## 1. Governing Correspondence Contract (Arc 4 → Arc 5)

Driven directly by Arc 4's empirical Pareto census ([`data/trials/arc4_high_mass_census_v1.json`](../data/trials/arc4_high_mass_census_v1.json)), **Arc 5 (`v0.7.0`)** constructs:
1. A **real Lean `v4.36.0` `module` + `@[expose] public section` + `leanchecker` clean-room elaboration harness** testing every subtle Lean 4.36 soundness boundary locally with zero Mathlib dependency; and
2. A **deterministic dual-route patch-plan & synthetic diff emitter** (`scargo-emit` in Rust `1.100.0` and `SCargoEmit`/`scargo-emit` in Swift `6.4.3`, byte-for-byte identical, $\Delta_{\text{parity}} = 0$) covering:
   - **Tier 1 (`Z-C0` Dead-Leaf Prune)**: `112` unreachable `FlagMeasures` modules → **14** `<= 8`-root shards + 1 full-runner bundle (`−8,060` lines / `−468,760` bytes).
   - **Tier 1 (`Z-C1A` Fail-Closed In-Place `alias`)**: `46` single-declaration pure wrappers (`0` downstream edits, `30` multi-decl files protected) → **6** `<= 8`-root shards + 1 full-runner bundle (`−478` lines / `−64,032` bytes).
   - **#1 High-Mass Winner (`Z-C2` `CapelliIdentities` Explicit `@`-Term De-Expansion)**: `24` heavy files (`14,221` conservative reclaimable lines / `1,334,494` bytes) → **3** `<= 8`-root shards + 1 full-runner bundle; **Shard 1 (top 8 heaviest files)** reclaims **10,878 conservative lines** with only **4 project ancestors** (500× under `UP-07`'s 2,000-ancestor quick-check cap!).
   - **#2 High-Mass Bonus (`Z-C4` Single-File Transitive Import Pruner)**: `EveryCharacterOfLiteratureOfVWin.lean` (`−5,054` transitively redundant `public import` lines / `−508,718` bytes in 1 file, exact transitive closure preserved) → explicitly routed to **`full_rh_build`** (NOT `quick_check`) because its `127,439` project ancestors exceed `UP-07`'s 2,000-ancestor small-runner limit!

---

## 2. Clean-Room Lean `v4.36.0` `module` Pre-Flight Verification Properties (`E1`–`E5`)

Every transform family is pressure-tested on compiled Lean `v4.36.0` modules (`autoImplicit = false`, `relaxedAutoImplicit = false`, `warningAsError = true`, `LEAN_ABORT_ON_PANIC=1`, zero `sorry`, zero `native_decide`, replayed by `leanchecker`):

| Test ID | Target Zone | Lean `v4.36.0` Pre-Flight Invariant Proved | Fail-Closed Guard |
| :--- | :---: | :--- | :--- |
| **`E1` Binder-Plicity & `alias` Visibility** | `Z-C1A` | `module` + `@[expose] public section` `alias` preserves exact `@`-application type, implicit/explicit/instance binder-plicity, and cross-module visibility (`rfl`). | Reject any wrapper with mismatched binder-plicity, explicit universe params, or `decl_count != 1`. |
| **`E2` `defeq` (`rfl`) & `*.eq_1` Stability** | `Z-C2` | De-expanding nested explicit `@`-coercion chains into clean implicit terms preserves definitional equality (`rfl`) and exact `*.eq_1` equation-lemma witness with zero extra axioms. | Reject any rewrite touching a `defeq`-pinned symbol without exact `rfl` parity or with unbalanced delimiters. |
| **`E3` Transitive `public import` Closure** | `Z-C4` | Pruning a transitively implied `public import Leaf` from `Hub` (when `Mid` already `public import`s `Leaf`) preserves 100% visibility of `Leaf` symbols and proofs across module boundaries. | Reject dropping any direct import not strictly covered in depth $\ge 1$ transitive closure of remaining direct imports. |
| **`E4` Unreachable Leaf Removal** | `Z-C0` | Deleting an unreachable leaf module leaves reachable theorem elaboration, axiom footprint, and `Main` closure strictly invariant. | Reject removing any module with in-degree $> 0$ from the reachable closure or explicit `lakefile.toml` reference. |
| **`E5` Smooth Containment (`Arc 5 → Rung 1`)** | All | `arc5_smoothly_contains_all_prior_rungs`: any passing `Arc5PreflightReceipt` smoothly implies passing Arc 4, Rung 3, Rung 2, and Rung 1 receipts ($\Delta_{\text{logic}} = 0$). | Any prior rung regression or `UP-07` misrouting fails closed immediately. |

---

## 3. Dual-Route `UP-07` Packaging & Six Emitter Guards (`EG-1`..`EG-6`)

Standalone Rust (`scargo-emit verify --root . --json`) and Swift (`scargo-emit --root . --json`) verify [`transfer/bundles/arc5_preflight_bundles_v1.json`](../transfer/bundles/arc5_preflight_bundles_v1.json) and execute deterministic clean-room synthetic patch-diff dry runs across all 4 transform classes, emitting **byte-identical** JSON receipts ($\Delta_{\text{parity}} = 0$):

| Guard | Formal Requirement |
| :--- | :--- |
| **`EG-1` Provenance, Zone A & `UP-08` Cleanliness** | Exact baseline commit SHA (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`), `target_repo_mutation_allowed = false`, zero Zone A targets across all shards/bundles, and zero verbatim upstream proof bodies inside the bundle JSON (`UP-08`). |
| **`EG-2` Dual-Route `UP-07` Routing Soundness** | Every `quick_check` shard strictly satisfies `roots <= 8` AND `ancestors <= 2000`; every bundle with `roots > 8` OR `ancestors > 2000` (including `Z-C4` hub with `127,439` ancestors and combined full-zone bundles) is strictly routed to `full_rh_build`. |
| **`EG-3` Exact Module Conservation & SHA-256 Shard Integrity** | For each zone (`Z-C0`, `Z-C1A`, `Z-C2`, `Z-C4`), shard unions match exact qualified module counts (`112`, `46`, `24`, `1`), shard sets are pairwise disjoint, and recomputed deterministic shard SHA-256 digests match the bundle manifest identically. |
| **`EG-4` Clean-Room Synthetic Diff Emission (`Z-C0`, `Z-C1A`, `Z-C2`, `Z-C4`)** | Executes all 4 deterministic text/graph rewriters on synthetic Lean `v4.36.0` `module` fixtures, verifying strict line/byte reduction ($\rho_L < 1, \rho_B < 1$), balanced delimiters, preserved `module` / `@[expose] public section` headers, and exact deterministic unified-diff SHA-256 parity across Rust & Swift. |
| **`EG-5` Lean `v4.36.0` Pre-Flight Contract Alignment** | Confirms all 4 clean-room Lean `v4.36.0` `module` test files (`Leaf.lean`, `Mid.lean`, `WrapAlias.lean`, `HubPruned.lean`) exist in `compartments/lean/SCargoLean/Preflight/`, carry zero `sorry`/`native_decide`, and declare `module` + `@[expose] public section`. |
| **`EG-6` Six Adversarial Negative Controls Fail Closed** | Rejects all 6 poisoned emission attempts: `neg_binder_plicity_mismatch_alias`, `neg_defeq_unsafe_rewrite`, `neg_non_redundant_import_pruned`, `neg_up07_high_ancestor_misrouted_quick_check`, `neg_zone_a_patch_target`, and `neg_up08_verbatim_code_in_bundle`. |
