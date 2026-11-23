# Arc 4 High-Mass Zone Census & Lexical Provenance Model (`models/arc4_high_mass_zone_census_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v1.0`

> **Separation Rule**: This document defines the **formal Arc 4 census & Pareto ranking model** only. All empirical counts, SHA-256 structural fingerprints, and cluster histograms are emitted read-only by `scargo-census` into [`data/trials/arc4_high_mass_census_v1.json`](../data/trials/arc4_high_mass_census_v1.json) without copying any verbatim upstream Lean proof bodies (`UP-08`), while `Ergentics1/Riemannian` stays **100% untouched**.

---

## 1. Purpose & Governing Correspondence Contract (Rung 3 → Arc 4)

Rung 3 (`v0.5.0`) qualified Tier 1 structural reductions (`Z-C0` dead leaves and `Z-C1` forwarding wrappers). Before building Arc 5's clean-room Lean `v4.36.0` elaboration harness and deterministic patch emitter, **Arc 4 (`v0.6.0`)** conducts a unified, read-only empirical census across all three remaining high-mass Transfer Zones defined in [`data/manifests/transfer_zones_v1.json`](../data/manifests/transfer_zones_v1.json):

1. **Zone `Z-C2` — Machine-Dumped Explicit Typeclass Terms (`CapelliIdentities`)**:
   - Scope: `src/Development/AutomorphicArithmetic/IntegralCasts/CapelliIdentities/`.
   - Measures total files/lines/bytes, `@`-token count, explicit-heavy lines (`>= 2` `@`-tokens or expanded Mathlib instance coercions such as `@Semifield.toCommSemiring`, `@DivisionSemiring.toSemiring`, `@Field.toSemifield`, `@Semiring.toNonAssocSemiring`), and conservative de-expansion line/byte savings while flagging `defeq` / `*.eq_1` sensitivity (`noncomputable def` vs. `theorem`).
2. **Zone `Z-C3` — Cross-Tree & Private-Lemma Duplication (`AbelianVarietyTheory/Proofs`)**:
   - Scope: the four subtrees declared in `transfer_zones_v1.json` (`DivisorProofs`, `InertiaEigenvalues`, `TwistedOperators`, `IwasawaDecomposition`).
   - Computes exact SHA-256 structural fingerprints of normalized `private theorem` / `private lemma` blocks (whitespace-collapsed, comment-stripped; storing **only** cluster SHA-256 hashes, counts, line/byte spans, and module paths — zero copied proof bodies per reconciled `UP-08`).
   - Exact cluster accounting invariant: for every duplicate cluster $c$ with multiplicity $k_c \ge 2$ and canonical block mass $(L_c, B_c)$, the upper-bound reclaimable mass from factoring into one shared helper is:
     $$\Delta L_{\text{reclaim}}(c) = (k_c - 1) \cdot L_c < k_c \cdot L_c, \qquad \Delta B_{\text{reclaim}}(c) = (k_c - 1) \cdot B_c < k_c \cdot B_c.$$
3. **Zone `Z-C4` — Dominator Spine, High Fan-Out Import Hubs & Hypothesis Structures**:
   - Scope: `src/Development/AutomorphicArithmetic/ThetaCorrespondence/ThetaPairLifts/ThirdPlaceSeries/` and `src/Development/AutomorphicArithmetic/Foundations/GaloisRepresentations/IntegralStructures/`.
   - Measures:
     - Import-scaffolding lines vs. total lines across the zone and specifically on the 5,308-import fan-out hub `EveryCharacterOfLiteratureOfVWin.lean`;
     - Exact **transitively redundant imports** in `EveryCharacterOfLiteratureOfVWin.lean` (imports $m \in I(u)$ that are already reachable through another direct import $m' \in I(u) \setminus \{m\}$ within the project import DAG — zero semantic risk when pruned!);
     - Structure declarations and field counts along the dominator spine (`RowSrc`, `SiegelEisensteinSecondTermHypotheses`, `ThirdPlaceSeries/`, `IntegralStructures/`), reconciled directly against [`data/traces/riemannian_51d9b1a280_trace.json`](../data/traces/riemannian_51d9b1a280_trace.json).

---

## 2. Lexical Reconciliation of `UP-08` (Independent Derivation vs. Verbatim Copying)

Reconciled across [`data/manifests/upstream_requirements_v1.json`](../data/manifests/upstream_requirements_v1.json) (`UP-08`) and [`data/sources/standard_vocabulary_v1.json`](../data/sources/standard_vocabulary_v1.json) (`v1.1.0`):
- **Independent Clean-Room Derivation / Convergence**: Independently arriving at the same theorem, structural invariant, or reduction rule from primary specifications and empirical measurements is explicitly permitted and desired.
- **Empirical Structural Telemetry**: Recording factual read-only counts, file paths, import graphs, and SHA-256 fingerprints is factual measurement, not source copying.
- **Verbatim Proof-Body Copying**: Pasting unlicensed upstream `.lean` proof bodies into MIT-licensed `SCargo` remains strictly forbidden and is actively enforced by Guard `HG-1`.

---

## 3. Five Independent High-Mass Census Guards (`HG-1`..`HG-5`) & 6 Adversarial Controls

Standalone Rust (`scargo-census verify --root . --json`) and Swift (`scargo-census verify --root . --json`) verify the immutable census dataset against all upstream baselines/manifests and must emit **byte-identical** canonical JSON receipts ($\Delta_{\text{parity}} = 0$):

| Guard | Formal Requirement |
| :--- | :--- |
| **`HG-1` Provenance, SHA Alignment & `UP-08` Lexical Guard** | Exact baseline commit SHA (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`), zero Zone A paths in any scanned zone, reconciled `UP-08` entry present in both `upstream_requirements_v1.json` and `standard_vocabulary_v1.json`, and zero verbatim proof bodies (`theorem ... := by`, `private theorem ... := by`) embedded in the census JSON. |
| **`HG-2` Zone `Z-C2` Conservation & `@`-Dump Bounds** | Exact per-file line/byte sums match zone totals, `explicit_heavy_lines <= total_lines`, conservative reclaimable lines strictly `< total_lines` with Pareto ratio $\rho_L < 1$. |
| **`HG-3` Zone `Z-C3` Exact Duplicate-Cluster Accounting** | Every subtree sum matches zone totals; every reported duplicate cluster has `multiplicity >= 2`, `reclaimable_lines == (multiplicity - 1) * block_lines`, and total reclaimable lines strictly `< total_lines`. |
| **`HG-4` Zone `Z-C4` Dominator Spine & Import-Redundancy Bounds** | `import_lines <= total_lines`, `transitively_redundant_imports <= hub_import_count`, and dominator-spine metrics match `riemannian_51d9b1a280_trace.json` (`RowSrc` = `954,607` dominated lines, `EveryCharacterOfLiteratureOfVWin` = `5,308` fan-out, `SiegelEisensteinSecondTermHypotheses` = `290,311` dominated lines). |
| **`HG-5` Deterministic Pareto Yield Ranking & 6 Negative Controls** | Zones `Z-C2`, `Z-C3`, `Z-C4` deterministically ranked by verified reclaimable lines (tie-broken by zone ID); all **6** adversarial negative controls fail closed (`neg_up08_verbatim_proof_body`, `neg_zone_a_census_leak`, `neg_commit_sha_drift`, `neg_z3_inflated_cluster_sum`, `neg_z4_imports_exceed_lines`, `neg_missing_up08_lexicon`). |

Lean (`SCargoLean.HighMassCensus` + `high_mass_census_test`) formally proves duplicate-cluster reclaimability bounds, explicit de-expansion strict Pareto monotonicity, import-scaffolding bounds, `UP-08` verbatim-copy rejection, and smooth **Arc 4 → Rung 3 → Rung 2 → Rung 1** Correspondence containment (`leanchecker` verified, zero `sorry`, zero `native_decide`).
