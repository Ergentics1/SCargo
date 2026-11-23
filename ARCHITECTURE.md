# SCargo Architecture & Compartment Philosophy

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

## 1. Mission Statement & Governing Core Thesis

`SCargo` is an isolated, clean-room, multi-language laboratory (**Rust `1.100.0`**, **Open-Source Swift `6.4.3`**, **Lean `v4.36.0`**) that separates **primary-source mathematical foundations, empirical data, normative policy, live audits, and executable compartments** before any artifact crosses into [`Ergentics1/Riemannian`](https://github.com/Ergentics1/Riemannian) (a 149,397-file, 15.17M-line formal Lean 4 proof).

`SCargo`'s research vaults, disambiguation specs, mathematical models, and verification tooling advance and commit **independently** — they do not wait on `Riemannian`.

### 1.1 The Correspondence Principle (Governing Core Thesis)
> **Every deeper theory must smoothly contain the older theory inside its proven dimensionless regime, with a quantifiable error bound on the mismatch.**

This thesis governs every layer of `SCargo`:
- **Mathematical foundations**: Passing from Euler/Oettingen/Hugo Riemann's infinite 5-limit just-intonation *Tonnetz* ($\mathbb{Z}^2$) to 12-TET ($\mathbb{T}^2$) exposes exact syntonic-comma ($81/80 \approx 21.506\text{ cents}$) and diesis ($128/125 \approx 41.059\text{ cents}$) bounds; refining $N$-TET toward flat $\mathbb{Z}^2$ crosses a quantifiable Alon–Boppana Graph-RH boundary (`models/riemann_lattice_graph_rh_model.md`).
- **Verification & reduction**: Every refactored or reduced proof module must preserve exact kernel statement/axiom equivalence (`epsilon = 0`) and explicitly bounded resource envelopes (`SCargoLean.Contract`).
- **Visualization & telemetry**: Re-rendering Paper 001 figures on scaled synthetic corpora must preserve exact correspondence between plotted quantities and dynamic prose captions (`epsilon = 0`, verified in `test_render_figures.py`).

## 2. Foundational Systems-Engineering Reference Lineage

Our architectural philosophy synthesizes two primary aerospace systems-engineering specifications:

### 2.1 SpaceX Falcon Payload User's Guide (Rev. 8, May 2025)
*Source: Space Exploration Technologies Corp., `falcon-users-guide-2025-05-09.pdf`.*

| Aerospace Principle | Falcon Guide Reference | Translation in `SCargo` → `Riemannian` |
|---|---|---|
| **Separation Plane & PAF Interface** | §2.4, §4.1, Appendix A–B (Payload Attach Fitting) | Strict boundary between `SCargo` (laboratory / payload integration) and `Riemannian` (flight article). Transfers cross only via [`transfer/ICD-RIEMANNIAN.md`](transfer/ICD-RIEMANNIAN.md). |
| **Keep-In Volumes & Mass–CG Envelopes** | §4.2, Appendix C (Keep-In Volumes) | Hard quantitative envelopes tracked in [`data/manifests/transfer_zones_v1.json`](data/manifests/transfer_zones_v1.json): file count, source lines, raw bytes, import graph acyclicity, and exported theorem signatures. |
| **Qualification vs. Acceptance Verification** | §7.1–7.4, Table 7-1 | **Qualification** runs in `SCargo` on stratified RCT samples and micro-benchmarks; **Acceptance** verifies every changed module + direct importers + axiom/comparator invariance before `Riemannian` merge. |
| **Lot Acceptance & Retest Triggers** | §7.3, Table 7-2, Appendix I | Any upstream `Riemannian` SHA change, toolchain bump (e.g., Lean `4.36.0` → `4.37.0`), or interface signature change invalidates prior trial receipts and triggers deterministic re-measurement. |
| **Customer Deliverables & Model Contracts** | §9.5, Table 9-2, Appendices E–G (CAD/Dynamic/Thermal Models) | Every reduction pass delivers (a) a machine-readable JSON measurement artifact, (b) a dependency/closure impact model, and (c) an explicit diff manifest — never ad-hoc edits. |
| **Formal Waiver Protocol** | §11.3 | Protected core files (`Challenge.lean`, `Statements.lean`, `Main.lean`, `comparator.json`, `export-targets.txt`, `lean-toolchain`) may never be modified without an explicit written waiver. |

### 2.2 NASA International Space Station Reference Guide (Assembly Complete Edition, Nov 2010)
*Source: NASA `NP-2010-09-682-HQ`, ISBN `0-16-086517-4`, `508318main_iss_ref_guide_nov2010.pdf`.*

| Aerospace Principle | ISS Guide Reference | Translation in `SCargo` |
|---|---|---|
| **Pressurized Modular Compartments** | pp. 13–17 (`Destiny`, `Kibo`, `Columbus`, `Zvezda`) | Dedicated standalone language compartments (`compartments/rust/`, `compartments/swift/`, `compartments/lean/`) with clean build boundaries and zero cross-compartment state leakage. |
| **ISPR & EXPRESS Standard Racks** | pp. 19, 23–25 (International Standard Payload Racks) | Standardized experiment rack layout (`experiments/retrospective/`, `experiments/rct/`): each study plugs into common input schemas (`data/`) and emits standardized telemetry JSON. |
| **Microgravity Science Glovebox (MSG / PGB)** | p. 24 (Two- and three-level containment) | Multi-level containment for potentially destructive source transformations: Level 1 read-only scan → Level 2 isolated scratch/copy dry-run → Level 3 gated transfer branch. |
| **Active Rack Isolation System (ARIS)** | p. 19 (Vibration damping from host structure) | Active decoupling prevents experimental churn, hanging scripts, or speculative refactoring from perturbing `Riemannian`'s verified tree. |
| **Pressurized Mating Adapter (PMA)** | p. 15 | Explicit transfer bay (`transfer/`) documenting exact transfer areas, mapping `SCargo` models and proofs onto target directories in `Riemannian/src/`. |

---

## 3. Non-Negotiable Architectural Invariants

### 3.1 Strict Separation of Code, Data, Policy, Audits & Presentation
- **Code (`compartments/`, `render_figures.py`)** contains pure algorithms, parsers, graph analyzers, theorem harnesses, and figure renderers. It contains **no hardcoded dataset tables or baked empirical numerals** (remediated in `AUD-06` and `AUD-07`).
- **Primary Sources (`data/sources/`)** hold immutable, schema-versioned archival registries strictly partitioned by tradition (`formulary_lineage_v1.json`, `hugo_riemann_works_v1.json`, `riemann_lattice_graph_rh_v1.json`, `methodology_literature_v1.json`, `standard_vocabulary_v1.json`, `paper_001_presentation_v1.json`). Zero crowdsourced encyclopedia URLs.
- **Normative Policy (`data/manifests/`)** holds immutable acceptance contracts (`swe_sweep_policy_v1.json`, `transfer_zones_v1.json`, `upstream_requirements_v1.json`).
- **Live Audit State (`data/audits/`)** holds live findings, remediation receipts, and time-bounded waivers (`live_self_audit_v1.json`) — strictly separated from normative policy so recording or closing a defect never mutates policy provenance (`AUD-01`).
- **Measurements (`data/baselines/`, `data/traces/`, `data/trials/`)** hold immutable tool outputs tagged with `schema_version`, `generated_at_utc`, `source_repo_commit`, and `tool_version`.
- **Models (`models/`)** state formal hypotheses, algebraic proofs, cost functions, and disambiguation contracts linking data to behavior.
- **Research (`research/`)** synthesizes models + data + primary literature into IMRaD papers, cryptographically manifested PNG figures, interactive HTML companions, and upstream toolchain bug reports (`research/upstream_reports/`).

### 3.2 Zero-Trust Helper-Pathology Defense & Atomic Boolean Guards
Guided by [`models/conflation_and_boolean_guard_analysis.md`](models/conflation_and_boolean_guard_analysis.md) and [`models/verification_methodology_model.md`](models/verification_methodology_model.md):
- **"Build nothing whose truth depends on it not being copied/modified"**: No gate relies on hidden trust, silent suppression (`#[allow]`, `try?`, disabled linters), or opaque single booleans.
- **Atomic, Fail-Closed Guards**: Every compartment evaluates named, independent `Bool` predicates paired with explicit diagnostic witnesses and concrete healing paths so contributors never face incentives to suppress warnings or cheat checks.
- **SWE-Sweep Coverage (Deterministic, Runtime, Probabilistic)**: Sweeps explicitly target lint suppressions, backdoors, hidden host subprocesses (`AUD-03`), symlinks, compiler warnings/deprecations (`AUD-02`, `AUD-04`, `AUD-05`), KVM cross-vCPU clock skew (`OBS-01`), and baked metrics (`AUD-07`).

### 3.3 Standalone Per-Language Execution ("No Combo")
- **Rust (`compartments/rust/`)**, **Open-Source Swift (`compartments/swift/`)**, and **Lean (`compartments/lean/`)** each build, test, and verify **strictly standalone** via their native build systems (`cargo`, `swift` via guarded default `swiftbuild`, `lake` + `leanchecker`).
- No cross-language combo wrapper scripts conflate compartment verdicts or hide a single language's compiler diagnostics.

### 3.4 Strict Intellectual Lineage Disambiguation (`RIEM-A` / `RIEM-B` / `RIEM-C` / `RIEM-LATTICE`)
Governed by [`models/riemannian_disambiguation_model.md`](models/riemannian_disambiguation_model.md) and [`models/riemann_lattice_graph_rh_model.md`](models/riemann_lattice_graph_rh_model.md):
- **Bernhard Riemann** (DNB GND `118600869`: `RIEM-A` analytic number theory, `RIEM-B` differential geometry) and **Hugo Riemann** (DNB GND `118600877`: `RIEM-C` music theory, distinct from 20th-century Neo-Riemannian formalizers `RIEM-C-ALG`) live in disjoint data vaults and disjoint language namespaces (`riem_analytic` / `riem_geometry` / `riem_harmonic` / `riem_lattice`).
- Their verifiable historical convergence lies in **Leonhard Euler's late-1730s St. Petersburg work** (`E53` 1735/1741, `E72` 1737/1744, `E33` 1739), expressed cleanly via the **Import-Style Riemann Lattice** (`RIEM-LATTICE`) without conflating finite-graph Ihara RH with classical RH for $\zeta(s)$.

### 3.5 Empirical Rigor: Retrospective + RCT Dual Design
1. **Retrospective Observational Studies (`experiments/retrospective/`)**:
   - Mine historical commits (`40e56bab` → `51d9b1a280`), upstream PR outcomes, and full-tree static inventories read-only.
   - Discover candidate reduction mechanisms, quantify base rates, and identify confounders (binder-plicity collisions, `open` shadowing, `*.eq_1` equation-lemma pinning, tactic-referenced dead declarations).
2. **Stratified Randomized Controlled Trials (`experiments/rct/`)**:
   - Before deploying any automated or semi-automated reduction pass across `Riemannian`, randomly assign eligible modules (stratified by library, file size quartile, and import-graph depth using a fixed PRNG seed recorded in `data/`) to **Treatment** vs. **Control**.
   - Pre-register **primary efficacy endpoints** ($\Delta$ lines, $\Delta$ bytes, $\Delta$ files, $\Delta$ compile time/heartbeats) and **hard safety endpoints** (0 dangling imports, DAG acyclicity, 0 statement/axiom drift, 100% direct-importer pass rate).

### 3.6 Bounded Execution & Watchdog Discipline
- All tools processing the 149,397-file tree must be compiled (Rust `scargo-probe` / `scargo-trace` / `scargo-qualify`) or strictly time-bounded (`timeout`), deterministic, and single-pass where possible. Hanging background scans are treated as test-rig faults.

