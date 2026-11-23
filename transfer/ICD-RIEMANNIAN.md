# Interface Control Document (ICD): `SCargo` → `Riemannian`

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)  
**Document ID**: `ICD-SCARGO-RIEM-001`  
**Version**: `1.0.0`  
**Target Flight Article**: `Ergentics1/Riemannian` (baseline commit `51d9b1a28026d458aef9c9af3df8b083276e3d2d`, Lean `v4.36.0`)  
**Machine-Readable Manifest**: [`data/manifests/transfer_zones_v1.json`](../data/manifests/transfer_zones_v1.json)

---

## 1. Purpose & Separation Plane

Modelled on the SpaceX Falcon Payload Attach Fitting (PAF) separation plane (§4.1) and the ISS Pressurized Mating Adapter (PMA), this ICD defines the exact contract governing what may cross from `SCargo` into `Riemannian`, what zones in `Riemannian` are immutable, and what verification gates must pass prior to any commit or pull request.

## 2. Zone Classification in `Riemannian`

### Zone A — Protected Verification Core (**NO-TOUCH / WAIVER REQUIRED**)
Analogous to Falcon flight-termination & launch-vehicle safety boundaries (§11.1–11.3). Changes here invalidate comparability with upstream `leanprover-community/riemann-hypothesis`:
- `src/Main.lean` (exported 5-theorem interface)
- `src/Challenge.lean` (Mathlib-only statement challenge)
- `src/Statements.lean` (shared theorem signatures)
- `comparator.json` & `export-targets.txt`
- `lean-toolchain` (`leanprover/lean4:v4.36.0`)
- `lakefile.toml` & `lake-manifest.json`

### Zone B — Documentation & Verification Provenance (**LOW-RISK TRANSFER**)
No Lean recompilation required; preserves cache baselines (`scripts/cache-baselines.json`):
- `verification/` (audit notes, 1:1 primary-source theorem attribution tables, size-reduction logs)
- `README.md` (only factual updates synced with verified tree state)

### Zone C — High-Yield Structural & Proof Reduction Zones (**QUALIFIED TRANSFER**)
Ranked by measured mass in `data/baselines/riemannian_51d9b1a280_inventory.json`:

| Transfer Zone | Target Path in `Riemannian/src` | Current Mass | Primary Reduction Mechanisms |
|---|---|---:|---|
| **Z-C0 (Dead Leaves)** | Unreachable modules (e.g., `Development/AbelianVarietyTheory/Proofs/FlagMeasures/*`) | 112 modules | Zero-risk graph pruning after import-closure verification |
| **Z-C1 (Statement Wrappers)** | `Development/AbelianVarietyTheory/Proofs/*/*Statement.lean` (and project-wide fallback wrappers) | 36,255 files / 709,446 lines | `alias` replacement (cf. upstream `#168`) or collision-safe wrapper collapse |
| **Z-C2 (Explicit Typeclass Dumps)** | `Development/AutomorphicArithmetic/IntegralCasts/CapelliIdentities/*` | ~25k+ lines in top files | De-expand `pp.explicit` terms while preserving defeq & types |
| **Z-C3 (Duplicate Private/Public Lemmas)** | `Development/AbelianVarietyTheory/Proofs/{DivisorProofs,InertiaEigenvalues,TwistedOperators,IwasawaDecomposition}` | 6.56M lines | Factor repeated `private theorem` helpers & deduplicate identical proofs |
| **Z-C4 (Dominator Spine)** | `Development/AutomorphicArithmetic/ThetaCorrespondence/ThetaPairLifts/ThirdPlaceSeries/*`, `Foundations/GaloisRepresentations/IntegralStructures/RowSrc.lean`, `DenseThresholdCases/VwinOfRow.lean` | `RowSrc` 954.6kL (12,425m), `VwinOfRow` 685.3kL (6,810m), `SiegelEisensteinSecondTermHypotheses` 290.3kL (3,863m) (`scargo-trace`) | High-leverage dominator spine compression, fan-out refactoring (`EveryCharacterOfLiteratureOfVWin`, `fan_out=5,308`), & dead structure-field pruning |
| **Z-C5 (Formalism Monoliths)** | `Formalism/HermitianCurvature/`, `Formalism/SharpRestriction/`, `Formalism/LocalToGlobal/` | 127.3 MB / 2.55M lines | Shared analytic bounds, Mathlib reuse, proof golfing |

## 3. Flight-Readiness Verification Gates (Pre-Transfer)

Every candidate transfer package staged in `SCargo/transfer/` must satisfy **all** applicable gates before committing to a `Riemannian` feature branch:

| Gate | Stage | Check | Pass Criterion |
|---|---|---|---|
| **G1 — Static Integrity** | Qualification (`SCargo`) | `scargo-probe` + `scargo-trace` + `scargo-audit` | 0 dangling imports, `is_acyclic = true`, exact cross-tool reachability match, Zone A byte-identical |
| **G2 — Contract Preservation** | Qualification (`SCargo`) | Signature & visibility check | All externally referenced declaration names, universe params, and types preserved (or all callers updated atomically) |
| **G3 — RCT Efficacy** | Qualification (`SCargo`) | Stratified RCT pilot | Positive net reduction meeting pre-registered threshold with 0 safety regressions |
| **G4 — Lean Elaboration** | Acceptance (`Lean v4.36.0`) | Compile edited modules + all direct importers | 100% pass, no new `sorry`/`axiom`/`native_decide`/`set_option maxHeartbeats` |
| **G5 — End-to-End Axiom & Comparator Check** | Release (CI / Full Runner) | `#print axioms` + `lake comparator` | Only `{propext, Quot.sound, Classical.choice}`; Lean paranoid + `nanoda` accept |

## 4. Retest Triggers (Falcon Table 7-2 Equivalent)

A transfer package must be re-qualified if **any** of the following occur:
1. `Riemannian` upstream `main` advances past the pinned baseline SHA (`51d9b1a280`).
2. `lean-toolchain` changes (e.g., upstream PR `#185` bump to Lean `v4.37.0-rc1`).
3. An upstream PR modifies any module overlapping the package's edited set or direct importers.
