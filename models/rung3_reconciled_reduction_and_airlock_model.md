# Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock Model (`models/rung3_reconciled_reduction_and_airlock_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v1.0`

> **Separation Rule**: This document defines the **formal Rung 3 airlock model** only. All empirical measurements remain immutable in [`data/baselines/riemannian_51d9b1a280_inventory.json`](../data/baselines/riemannian_51d9b1a280_inventory.json), [`data/traces/riemannian_51d9b1a280_trace.json`](../data/traces/riemannian_51d9b1a280_trace.json), [`data/trials/dryrun_001_dead_leaves.json`](../data/trials/dryrun_001_dead_leaves.json), and [`data/trials/dryrun_002_rct001_wrappers.json`](../data/trials/dryrun_002_rct001_wrappers.json); normative boundaries live in [`data/manifests/transfer_zones_v1.json`](../data/manifests/transfer_zones_v1.json) and [`data/manifests/upstream_requirements_v1.json`](../data/manifests/upstream_requirements_v1.json); and staged clean-room package declarations live in [`transfer/packages/rung3_airlock_manifest_v1.json`](../transfer/packages/rung3_airlock_manifest_v1.json). `Ergentics1/Riemannian` stays **100% untouched** across the separation plane until explicit ICD transfer sign-off.

---

## 1. Governing Correspondence Contract (Rung 2 → Rung 3)

Under **The Correspondence Principle**, Rung 3 must smoothly contain both Rung 1 (13 independent Proof-Carrying SWE-sweep witnesses + 21/21 negative controls + Stratified `RCT-R1`) and Rung 2 (canonical ground codec + QuickCheck shrinking + `MR-1`..`MR-3` metamorphic invariance + 384-case byte-identical Rust ↔ Swift parity) with zero logical drift ($\Delta_{\text{logic}} = 0$, $\Delta_{\text{parity}} = 0$), while reconciling candidate proof-reduction packages against the baseline `Riemannian` snapshot (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`).

For any candidate reduction operator $\Phi: T_{\text{old}} \mapsto T_{\text{deep}}$ targeting a transfer zone $Z \in \{\text{Z-C0}, \text{Z-C1}\}$, let the observable source mass vector from [`models/reduction_model.md`](reduction_model.md) be:

$$\mathbf{M}_{\text{src}}(T) = \bigl(F(T),\; L(T),\; B(T)\bigr), \qquad \rho_k(\Phi) = \frac{M_k(\Phi(T))}{M_k(T)} \quad (k \in \{F, L, B\}).$$

A clean-room transfer package is **Airlock Qualified (G1–G3 PASS; G4–G5 Airlock Hold)** if and only if all five independent Airlock Guards pass fail-closed:

| Guard | Regime | Formal Requirement | Upstream Rule Link |
| :--- | :--- | :--- | :--- |
| **`AG-1` Zone A Immutability** | Deterministic ($\epsilon = 0$) | Touch set $S(\Phi) \cap \text{Zone A} = \emptyset$; zero edits to `src/Main.lean`, `src/Challenge.lean`, `src/Statements.lean`, `comparator.json`, `export-targets.txt`, `lean-toolchain`, `lakefile.toml`, `lake-manifest.json`. | `UP-01`, `UP-04`, `UP-05` |
| **`AG-2` Cross-Tool Baseline & Trace Conservation** | Deterministic ($\epsilon = 0$) | Exact SHA match (`51d9b1a280...`), `is_acyclic = true`, exact global mass conservation across `reachable + unreachable + Challenge.lean = totals` (`files`, `lines`, `bytes`), and `15/15` primary lineage targets (`SRC-01`..`SRC-15`) verified reachable. | `G1_STATIC_INTEGRITY` |
| **`AG-3` Pareto Monotonicity, Unit Reconciliation & RCT Efficacy** | Deterministic + Probabilistic | $\Delta F \le 0$, $\Delta L < 0$, $\Delta B < 0$ ($\rho_L < 1, \rho_B < 1$); exact per-unit reconciliation of `dryrun_002_rct001_wrappers.json` (`decl_count == 1` guard protects all multi-declaration files); Wilcoxon–Mann–Whitney ($p < 0.01$) and Vargha–Delaney ($\hat{A}_{12} > 0.70$) confirm strictly positive treatment savings vs. 0-change control arm. | `G2`, `G3_RCT_EFFICACY` |
| **`AG-4` `UP-07` Bounded Batching & Axiom/Provenance Cleanliness** | Deterministic ($\epsilon = 0$) | Partition every package's qualified modules into pairwise-disjoint deterministic batches of size $\le 8$ (`UP-07` quick-check cap), verify union equals exact eligible module set, restrict axioms strictly to `{propext, Quot.sound, Classical.choice}`, and preserve `UP-08` clean-room provenance (zero verbatim upstream Lean proof source copied into `SCargo`). | `UP-02`, `UP-03`, `UP-06`, `UP-07`, `UP-08` |
| **`AG-5` Synthetic Clean-Room Transform & Adversarial Airlock Controls** | Deterministic ($\epsilon = 0$) | Execute clean-room transforms (`Z-C0` dead-leaf prune, `Z-C1A` in-place `alias`, `Z-C1B` wrapper collapse + importer rewire) on synthetic `GroundGraph` fixtures (verifying post-transform validity, acyclicity, preserved core reachability, and strict mass drop), AND verify **7/7** poisoned transfer packages fail closed. | `PRIN-06`, `G1`–`G2` |

---

## 2. Clean-Room Staged Transfer Packages (`G1`–`G3` Qualified, `G4`–`G5` Hold)

1. **`PKG-R3-Z0-DEAD-LEAVES`** (`Z-C0`, Unreachable Project Modules):
   - Targets the unreachable `FlagMeasures` leaf closure measured in `dryrun_001_dead_leaves.json` and `riemannian_51d9b1a280_inventory.json`.
   - Zero reachable importers, zero explicit `lakefile.toml` references, zero Zone A overlap.
   - Partitioned into deterministic `<= 8`-root quick-check batches (`ceil(112 / 8) = 14` batches) for `UP-07` optional small-runner verification or single full-runner PR.
2. **`PKG-R3-Z1A-ALIAS-INPLACE`** (`Z-C1`, Strategy A Minimal In-Place Alias):
   - Targets all single-declaration pure wrappers in the `RCT-001` treatment arm that pass `decl_count == 1`, `touches_core == false`, and `strategy_a_eligible == true` (`46` eligible modules, `0` downstream importer edits, `30` multi-declaration files strictly protected).
   - Partitioned into `ceil(46 / 8) = 6` deterministic `<= 8`-root batches under `UP-07`.
3. **`PKG-R3-Z1B-WRAPPER-COLLAPSE`** (`Z-C1`, Strategy B Wrapper Collapse + Importer Rewire):
   - Targets single-declaration pure wrappers in the `RCT-001` treatment arm satisfying `decl_count == 1`, `paired_impl_exists == true`, `imports_subset_of_impl == true`, `touches_core == false`, and `strategy_b_eligible == true` (`30` eligible modules eliminating `30` files).
   - Partitioned into `ceil(30 / 8) = 4` deterministic `<= 8`-root batches under `UP-07`.

---

## 3. Adversarial Negative-Control Airlock Suite (7 Must Fail Closed)

Every standalone Rung 3 compartment (`Lean v4.36.0`, `Rust 1.100.0`, `Swift 6.4.3`) must fail closed on all seven poisoned transfer attempts:
1. `neg_zone_a_protected_touch`: package modifies `src/Main.lean` or `lakefile.toml` (`UP-01`/`UP-05`).
2. `neg_commit_sha_drift`: manifest commit SHA disagrees with baseline/trace SHA (Retest Trigger §4.1).
3. `neg_multi_decl_wrapper_unsafe_collapse`: Strategy B attempts to collapse a module with `decl_count > 1` (`DRYRUN-002` confounder).
4. `neg_missing_transitive_import_collapse`: Strategy B attempts to collapse a wrapper with `imports_subset_of_impl = false` (`missing_transitive_imports > 0`).
5. `neg_up07_oversized_quick_check_batch`: quick-check batch contains `9 > 8` changed Lean roots (`UP-07`).
6. `neg_up02_custom_axiom_or_native_decide`: package introduces a non-permitted axiom outside `{propext, Quot.sound, Classical.choice}` (`UP-02`).
7. `neg_pareto_mass_inflation`: candidate transform increases line or byte mass ($\Delta L > 0$ or $\Delta B > 0$).

---

## 4. Cross-Language Differential Parity Contract

Standalone Rust (`scargo-airlock --root . --json`) and Swift (`scargo-airlock --root . --json`) reconcile identical inputs from `data/` and `transfer/packages/`, compute exact SHA-256 provenance digests across all 7 input files and all deterministic batch schedules, execute the synthetic clean-room transforms + 7 adversarial airlock controls, and must emit **byte-identical** canonical JSON receipts ($\Delta_{\text{parity}} = 0$). Lean (`SCargoLean.TransferAirlock` + `transfer_airlock_test`) formally proves the Zone A immutability, axiom subset, Pareto strictness, `decl_count == 1` Strategy B guard, `UP-07` batch bound, dead-leaf reachability preservation, and Rung 3 → Rung 2 → Rung 1 Correspondence containment theorems in the pure Lean kernel (`leanchecker` verified, zero `sorry`, zero `native_decide`).
