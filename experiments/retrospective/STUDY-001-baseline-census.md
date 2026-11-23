# Retrospective Study 001 (`STUDY-001`): Baseline Census & Historical Evolution of `Riemannian`

- **Organization**: Ergentics (© 2026 Ergentics, LLC)
- **Study Design**: Retrospective Observational Cohort & Cross-Sectional Census (`retrospective_observational`)
- **Exposure Cohort**: `leanprover-community/riemann-hypothesis` / `Ergentics1/Riemannian` from inception archive `40e56bab` (2026-11-20, Lean `v4.33.1`) to current baseline `51d9b1a280` (Lean `v4.36.0`)
- **Telemetry Instrument**: `compartments/rust/scargo-probe` v0.1.0 (read-only zero-side-effect full-tree scan)
- **Raw Data Artifact**: [`data/baselines/riemannian_51d9b1a280_inventory.json`](../../data/baselines/riemannian_51d9b1a280_inventory.json)

## 1. Research Questions
1. How much mass was removed between the original submission (`40e56bab`) and current `main` (`51d9b1a280`), and where does the remaining mass concentrate?
2. What fraction of current line/file mass is mechanical scaffolding and generated fallback wrappers vs. substantive mathematical proof content?
3. What confounders caused regressions or failures in prior community PRs (`#44`, `#55`, `#68`, `#120`, `#138`, `#151`, `#173`, `#178`, `#208`)?

## 2. Longitudinal Comparison (Retrospective Cohort)

| Metric | Original `40e56bab` (v4.33.1) | Current `51d9b1a280` (v4.36.0) | Observed $\Delta$ |
|---|---:|---:|---:|
| Tracked `.lean` files | 175,187 | 149,397 | −25,790 (−14.7%) |
| Raw source bytes | 1,030.53 MB | 871.37 MB | −159.16 MB (−15.4%) |
| Total source lines | 17,374,215 | 15,168,601 | −2,205,614 (−12.7%) |
| Non-blank lines | 15,531,759 | 13,287,641 | −2,244,118 (−14.4%) |

## 3. Key Retrospective Confounders Identified
1. **Kernel-export vs. Tactic-source mismatch** (`#178`, `#55`, `#173`): Pruning declarations solely from `lean4export` breaks elaboration because tactics (`simp`, `aesop`, `linarith`) reference lemmas whose constants are unfolded or discarded in the final kernel term.
2. **Binder-plicity load-order sensitivity** (`#138`, `#120`): 3,645 duplicated theorem/lemma names exist across 3,150 files, with at least 21 syntactic binder-plicity mismatches; bundling or reordering imports silently flips elaboration semantics.
3. **Namespace shadowing under consolidation** (`#120`): Merging modules brings nearer namespaces into scope that shadow existing `open` directives.
4. **Equation-lemma (`foo.eq_1`) pinning** (`#178`): Downstream `simp [foo]` calls depend on Lean's auto-generated equation lemmas, constraining def-body rewrites.
5. **Import-minimization vs. line-count tradeoff** (`#98`, `#134`, `#185`): Privatizing and minimizing `Mathlib` imports speeds compilation by ~11–22% CPU while *increasing* raw import lines from ~842k to ~6.47M — proving that file count, line count, export size, and compile time are distinct axes on a Pareto frontier.

## 4. Hypotheses Forwarded to Prospective RCTs
- **H1 (`RCT-001`)**: Replacing generated `first | exact @...` fallback wrappers with single-line `alias` declarations (or collision-safe collapsing) reduces wrapper lines by >80% with zero statement/axiom drift when stratified across all libraries.
- **H2 (`RCT-002`)**: Factoring repeated `private theorem` helpers within high-density directories (`DivisorProofs`, `InertiaEigenvalues`, `TwistedOperators`) yields significant net line reduction without altering any public module interface.
- **H3 (`RCT-003`)**: De-expanding `pp.explicit` terms in `CapelliIdentities` achieves >60% per-file byte reduction while preserving definitional equality.
