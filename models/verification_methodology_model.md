# Ground-Level Verification, Zero-Trust Compartments & Correspondence Methodology Model (`models/verification_methodology_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v2.1`

> **Separation Rule**: This document defines the **formal methodological model** only. All 55 primary-archive bibliographic records live in [`data/sources/methodology_literature_v1.json`](../data/sources/methodology_literature_v1.json) (`METH-01`–`METH-55`), all pure normative policy rules live in [`data/manifests/swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json) (`v1.2.0`), declarative negative-control fixture recipes live in [`data/fixtures/rung1_negative_controls_v1.json`](../data/fixtures/rung1_negative_controls_v1.json), live audit findings and external platform waivers live separately in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json), and upstream target constraints live in [`data/manifests/upstream_requirements_v1.json`](../data/manifests/upstream_requirements_v1.json) (`UP-01`–`UP-08`). No executable engine, kernel, or sweep code is conflated into this specification.

---

## 1. Core Thesis: The Correspondence Principle

> **The Correspondence Principle**: *Every deeper theory must smoothly contain the older theory inside its proven dimensionless regime, with a quantifiable error bound on the mismatch.*

Rooted in Bohr (1920, `METH-34`), Ehrenfest (1927, `METH-35`), Nickles's distinction between deductive ($\text{Reduction}_1$) and limiting ($\text{Reduction}_2$) reduction (1973, `METH-36`), and Bokulich's structural analysis of singular limits (2008, `METH-37`), this thesis governs **every** layer we build in `SCargo`—both mathematical proof compression and multi-language software construction.

### 1.1 Formal Correspondence Relation

Let $\mathcal{T}_k$ denote a validated baseline theory, model rung, or proof artifact on its proven validity domain $\Omega_k$, and let $\mathcal{T}_{k+1}$ denote a deeper theory, higher engine rung, or compressed proof parameterized by a nonnegative dimensionless departure vector $\boldsymbol{\epsilon} \in \mathbb{R}_{\ge 0}^m$.

$\mathcal{T}_{k+1}$ satisfies the **Correspondence Principle** relative to $\mathcal{T}_k$ if and only if there exist:
1. an explicit **projection / specialization map** $\pi_{k+1 \to k}$ from the deeper space to the baseline observable space,
2. a declared **proven dimensionless validity regime** $\Omega_k^{\text{valid}} \subseteq \Omega_k$, and
3. an explicit, computable, dimensionless **mismatch error bound** $B(\boldsymbol{\epsilon})$ satisfying $\lim_{\boldsymbol{\epsilon} \to \mathbf{0}} B(\boldsymbol{\epsilon}) = 0$,

such that:

$$\forall x \in \Omega_k^{\text{valid}}:\qquad \Delta_{k+1,k}(x; \boldsymbol{\epsilon}) \;\equiv\; d_k\Bigl(\pi_{k+1 \to k}\bigl(\mathcal{T}_{k+1}(x; \boldsymbol{\epsilon})\bigr),\; \mathcal{T}_k(x)\Bigr) \;\le\; B(\boldsymbol{\epsilon})$$

### 1.2 Quantifiable Regimes & Singular-Boundary Guardrails

Following Nickles (`METH-36`) and Bokulich (`METH-37`), `SCargo` never asserts correspondence qualitatively; every deeper construction must declare which regime it operates in and enforce its exact mismatch bound:

| Domain | Dimensionless Control $\boldsymbol{\epsilon}$ | Mismatch Metric $\Delta$ | Required Error Bound $B(\boldsymbol{\epsilon})$ | Singular-Boundary Guardrail (`METH-37`) |
| :--- | :--- | :--- | :--- | :--- |
| **Formal Logic & Kernel Proofs** ($\text{Reduction}_1$) | $\epsilon = 0$ (exact specialization) | Statement, axiom-set, and kernel-replay divergence | $B(0) = 0$ identically (`UP-01`–`UP-03`) | Reject silent drift across definitional equality (`rfl`), `*.eq_1` equation-lemma pinning, or namespace shadowing. |
| **Three-Language Discrete Parity** (`Rust`/`Swift`/`Lean`) | $\epsilon = 0$ (canonical fixtures) | Normalized serialization mismatch $\mathbf{1}[\sigma(f_A) \neq \sigma(f_B)]$ | $B(0) = 0$ identically (`METH-03`, `METH-04`) | Canonical key ordering (`BTreeMap`, `.sortedKeys`), exact UTF-8 and integer width parity. |
| **Numerical / Analytic Approximations** ($\text{Reduction}_2$) | Machine unit $u_{\text{mach}}$ or truncation scale $N^{-1}$ | Dimensionless relative residual $\|\hat{y} - y\| / \|y\|_{\text{ref}}$ | Explicit interval / ULP / truncation remainder bound $B(\epsilon)$ | Declare domain poles, critical-strip boundaries, and branch cuts explicitly; reject silent extrapolation. |
| **Probabilistic & Statistical Sweeps** ($\text{Reduction}_2$) | Sample scale $\epsilon = n^{-1/2}$ ($n \ge 30$) | Distribution & effect-size discrepancy | Clopper–Pearson / Hoeffding / Wilcoxon–Mann–Whitney ($\alpha = 0.01$) + Vargha–Delaney $\hat{A}_{12}$ | Ban single-run claims (`METH-21`, `METH-23`); record deterministic PRNG seeds in `data/`. |
| **Proof-Mass Reduction** ($\Phi: T_{\text{old}} \mapsto T_{\text{deep}}$) | Dimensionless mass ratio $\rho_i = M_i(T_{\text{deep}}) / M_i(T_{\text{old}})$ | Logical mismatch $\Delta_{\text{logic}}$ + mass-vector shift $\Delta \mathbf{M}$ | $\Delta_{\text{logic}} = 0$ identically; explicit $\rho_i$ across all 5 components of $\mathbf{M}(T)$ | Reject reductions that compress one component while silently inflating compile cost or violating `UP-07`. |

---

## 2. Zero-Trust Epistemic Axiom: Defeating Sloppy-Helper Pathology, Leakers & False Integrity

A core danger in modern software and proof engineering—especially with AI coding assistants—is **sloppy or poor helper pathology**: leaving subtle holes, convenience suppressions, hidden dependencies, exfiltration channels, or plausible-sounding rationalizations in a codebase in order to pass a weak check. Recent empirical work (`METH-33` Hu et al., Oct 2026) documents that coding helpers frequently emit reward-hacking shortcuts while omitting them from explanations or framing them as legitimate or "preventive," and that such shortcuts propagate across shared code and plans.

Because a human reviewer can never inspect or verify a helper's internal intentions, `SCargo` adopts an uncompromising **Zero-Trust Construction Axiom**:

> **Truth-Independence Axiom (`PRIN-06`)**: *Build nothing whose truth depends on it not being copied, inspected, or modified. Never rely on trusting a helper's intentions, secrecy, or self-certification.*

This axiom is anchored directly in four classical and contemporary primary pillars:
1. **Open Design Under Adversarial Copying** (`METH-26` Kerckhoffs 1883; `METH-27` Shannon 1949): Every verification mechanism and claim must remain sound when the entire repository—source, tests, manifests, and witnesses—is publicly copied, audited, or adversarially modified.
2. **Confinement Against Leakers & Covert Channels** (`METH-28` Lampson 1973): Helpers and analysis compartments are strictly confined—zero unauthorized network egress, zero ambient credential/environment reads, zero covert temp-file side channels, and zero writes outside explicitly declared paths (`DEF-LEAK`).
3. **Proof-Carrying Verification Over Untrusted Producers** (`METH-30` Necula 1997; `METH-08` Pollack 1998; `METH-09` Barendregt & Wiedijk 2005): Treat *every* code or proof producer (human or AI) as **untrusted**. Truth rests exclusively on a small, self-contained, content-addressed **witness artifact** that any independent minimal verifier can replay from scratch.
4. **Mutation Adequacy Against False-Integrity Theater** (`METH-31` DeMillo, Lipton & Sayward 1978; `METH-32` Skalse et al. 2022; `METH-24` Wang et al. 2026; `METH-25` Ludwig et al. 2026): Any verification check that passes without proving it kills deliberately planted defects is false integrity and is rejected.

---

## 3. No Monolithic Gates: Independent Composable Compartments

Following Saltzer & Schroeder's **Separation of Privilege** and **Least Common Mechanism** (`METH-29`, 1975) and Skalse et al.'s characterization of proxy reward hacking (`METH-32`, 2022), `SCargo` explicitly forbids **monolithic pass/fail gates** (`DEF-MONO`).

Why monolithic gates fail:
- A single aggregated `passes() -> Bool` function creates a single point of failure, hides *which* checks actually executed, encourages helpers to patch or game the gate rather than the defect, and conflates orthogonal trust boundaries.

Instead, every compartment $C \in \{\text{Rust},\; \text{Swift},\; \text{Lean}\}$ is audited by a set of **13 independent, minimally coupled Verification Compartments**, each emitting its own **Proof-Carrying Witness** $w_j$:

$$\mathcal{W}(C, S) = \bigl\{\; w_{\text{compiler}},\; w_{\text{suppression}},\; w_{\text{backdoor}},\; w_{\text{confinement}},\; w_{\text{deps}},\; w_{\text{topology}},\; w_{\text{parity}},\; w_{\text{kernel}},\; w_{\text{correspondence}},\; w_{\text{fp\_determinism}},\; w_{\text{rt\_invariants}},\; w_{\text{prob\_calibration}},\; w_{\text{seam\_integrity}} \;\bigr\}$$

### Proof-Carrying Compartment Witness Contract
Every individual witness $w_j$ is an immutable JSON (or Lean kernel export) artifact whose validity **does not depend on trusting the producer or keeping any file secret/unmodified**:
- `witness_compartment_id` & `schema_version`
- `input_content_digests`: SHA-256 hashes of every exact source file, manifest, and fixture evaluated (if any file is modified, the digest mismatch is immediately obvious to any external verifier)
- `policy_digest`: SHA-256 hash of [`swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json)
- `regime`: `deterministic` | `runtime` | `probabilistic` | `seam`
- `findings`: explicit list of exact file/line/defect-class records (empty for pass)
- `active_waivers_observed`: explicit visible listing of every matched external waiver in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json) (zero silent waivers; stale waivers fail!)
- `correspondence_bound`: declared $\boldsymbol{\epsilon}$, measured $\Delta$, and bound $B(\boldsymbol{\epsilon})$ (for `w_correspondence` and numerical/statistical/seam witnesses)
- `independent_replay_command`: exact offline command enabling any third party to copy the inputs onto a fresh machine and reproduce the witness byte-for-byte.

---

## 4. Eight-Pillar Literature Map (`METH-01`–`METH-55`)

| Pillar | Primary Archival Anchors | Operational Guarantee in `SCargo` |
| :--- | :--- | :--- |
| **PIL-I** Separation & Clean-Room | Parnas (1972), Codd (1970), Mills–Dyer–Linger (1987), Buckheit–Donoho (1995), Peng (2011), Sandve et al. (2013), Wilkinson et al. (2016) (`METH-01`–`METH-02`, `METH-38`–`METH-42`) | Disjoint `data/`, `models/`, `compartments/`; models precede code; zero baked literals. |
| **PIL-II** Cross-Language Parity | Avizienis (1985), McKeeman (1998), Le–Afshari–Su (2014) (`METH-03`–`METH-05`) | Independent Rust, Swift 6.4, Lean 4.36 implementations cross-check identical canonical fixtures. |
| **PIL-III** Trusting Trust & Kernels | Thompson (1984), Pollack (1998), Barendregt–Wiedijk (2005), Wheeler (2009), Carneiro (2024) (`METH-06`–`METH-10`) | Official signed/source-built toolchains + de Bruijn replay (`leanexport` → `leanchecker` / `nanoda_bin`). |
| **PIL-IV** Warnings & Anti-Suppression | Bessey et al. (2010), Sadowski et al. (2018), Hu et al. (FSE 2025), Swift SE-0443/SE-0414/SE-0329, IEEE 754-2019 (`METH-11`–`METH-14`, `METH-44`, `METH-47`) | Warnings, deprecations, and non-finite NaN drops are hard errors; zero blanket or stale suppressions. |
| **PIL-V** Supply Chain, Symlinks & BiDi | Ohm et al. (2020), Lamb–Zacchiroli (2022), Boucher–Anderson (2023), NIST SP 800-218, SLSA v1.0/v1.1 (`METH-15`–`METH-19`) | Offline pinned builds, SHA-pinned CI actions, zero undeclared deps, zero tracked symlinks, zero build hooks, zero BiDi controls. |
| **PIL-VI** Probabilistic Calibration & Adversarial Audits | Clopper–Pearson (1934), Claessen–Hughes (2000), Gneiting–Raftery (2007), Gneiting–Balabdaoui–Raftery (2007), Arcuri–Briand (2014), Segura et al. (2016), Klees et al. (2018), Wang et al. (2026), Ludwig et al. (2026) (`METH-20`–`METH-25`, `METH-51`–`METH-52`, `METH-54`) | Distribution-free Calibration-PIT + CRPS/Brier + Clopper–Pearson coverage, $n \ge 30$ Wilcoxon–Mann–Whitney + $\hat{A}_{12}$, red-team harness audits. |
| **PIL-VII** Zero-Trust Helper Pathology, Confinement & Seams | Kerckhoffs (1883), Shannon (1949), Lampson (1973), Saltzer–Schroeder (1975), Bierman (1977), DeMillo–Lipton–Sayward (1978), Lamport (1978), Necula (1997), Salmon et al. (2011), Skalse et al. (2022), Hu et al. (Oct 2026) (`METH-26`–`METH-33`, `METH-43`, `METH-49`, `METH-55`) | Truth independent of copying/modification; no monolithic gates; global SPD/conservation guards; typed `P → D` and keyed `D → P` seam integrity. |
| **PIL-VIII** The Correspondence Principle & Stability Bounds | Bohr (1920), Ehrenfest (1927), Nickles (1973), Neumaier (1974), Higham (1990, 2002), Massart (1990), Goldberg (1991), Bokulich (2008) (`METH-34`–`METH-37`, `METH-45`–`METH-46`, `METH-48`, `METH-50`, `METH-53`) | Smooth baseline containment inside $\Omega_k^{\text{valid}}$ with Higham $\gamma_n \kappa u$, Cholesky PSD-cone floor, and tight Massart–DKW bounds. |

---

## 5. Tri-Regime SWE-Sweep Vector, 14-Class Defect Matrix & Cross-Type Seams

Each language compartment $C \in \{\text{Rust},\; \text{Swift},\; \text{Lean}\}$ is evaluated across three orthogonal verification regimes ($\mathbf{V}_{\text{det}}, \mathbf{V}_{\text{run}}, \mathbf{V}_{\text{prob}}$) plus cross-type seams ($\text{D} \leftrightarrow \text{R} \leftrightarrow \text{P}$) targeting **14 hard-fail defect classes** codified in [`swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json) (`v1.2.0`):

| Defect ID | Code | Primary Regimes | Core Target |
| :--- | :--- | :--- | :--- |
| `DEF-SUPP` | `SUPPRESSION` | Deterministic, Runtime | `#[allow]`, `#[ignore]`, `try?` error discard, `-suppress-warnings`, `set_option linter.* false`, `sorry`/`admit` |
| `DEF-BACK` | `BACKDOOR` | Deterministic, Runtime | `unsafe`, `extern`, `transmute`, `build.rs`, `@_silgen_name`, `@unchecked Sendable`, `axiom`, `native_decide`, `debug.skipKernelTC`, Unicode BiDi *Trojan Source* |
| `DEF-HDEP` | `HIDDEN_DEPENDENCY` | Deterministic, Runtime | Undeclared/unpinned crates or packages, ambient `ENV`/`PATH` probes, `dlopen`, online fetches |
| `DEF-SYML` | `SYMLINK_AND_PATH_ESCAPE` | Deterministic, Runtime | Any symlink in tracked source/data/models/fixtures, out-of-build-root cache symlinks, `..` traversal, git `export-subst`, shadow harness files |
| `DEF-WARN` | `WARNINGS_AND_DEPRECATIONS` | Deterministic | `-D warnings`, `-warnings-as-errors` + `-print-diagnostic-groups`, `warningAsError = true`; zero hidden deprecations |
| `DEF-COMP` | `COMPROMISE_AND_SHORTCUT` | Deterministic, Runtime, Probabilistic | Code/data conflation, unseeded RNG, nondeterministic map ordering, relaxed compiler modes, single-run claims |
| `DEF-PAR` | `PARITY_DRIFT` | Deterministic, Runtime, Probabilistic | Any mismatch $\sigma(f_{\text{Rust}}(x)) \neq \sigma(f_{\text{Swift}}(x)) \neq \sigma(f_{\text{Lean}}(x))$ on identical inputs |
| `DEF-LEAK` | `CONFINEMENT_AND_EXFILTRATION_HOLE` | Deterministic, Runtime | Network sockets, ambient credential/env dumping, unauthorized subprocesses, covert temp-file side channels |
| `DEF-MONO` | `MONOLITHIC_GATE_OR_UNVERIFIED_TRUST` | Deterministic, Runtime, Probabilistic | Single-boolean omnibus gates, self-certifying checks, truth relying on secrecy, non-copying, or helper intent |
| `DEF-CORR` | `CORRESPONDENCE_VIOLATION` | Deterministic, Runtime, Probabilistic | Deeper layer breaking containment of baseline inside $\Omega_k^{\text{valid}}$, missing bound $B(\boldsymbol{\epsilon})$, or singular-boundary failure |
| `DEF-FP` | `FLOATING_POINT_NON_ASSOCIATIVITY_AND_CANCELLATION` | Deterministic | Fixed-order float assertions masking order-dependent non-associativity or catastrophic cancellation exceeding Higham's bound |
| `DEF-RTINV` | `RUNTIME_GLOBAL_INVARIANT_COLLAPSE` | Runtime | Indefinite covariance matrices with positive diagonals (`diag(P) > 0`, $\lambda_{\min} < 0$), single-sample `NaN` poisoning / silent `NaN > max` drop, aggregate conservation breaches under passing cell clamps |
| `DEF-CAL` | `DISTRIBUTIONAL_CALIBRATION_AND_OOD_FAILURE` | Probabilistic | Point-accuracy / naive Gaussian tests blind to miscalibrated intervals, bimodal/heavy-tail residuals, CRPS/Brier degradation, or OOD shift |
| `DEF-SEAM` | `CROSS_TYPE_BOUNDARY_SEAM_LEAK` | D ↔ R ↔ P Seams | Uncalibrated/OOD `P` estimates driving unguarded `D` actuators, unkeyed global PRNG invoked from `D` breaking bit-exact replay, or uncertified `R` state entering `D` solvers |

### Adversarial Negative-Control Qualification (`21` Declarative Fixtures + `RCT-R1`)
Following DeMillo–Lipton–Sayward (`METH-31`), *BenchJack* (`METH-24`), and Arcuri–Briand (`METH-21`), every SWE-sweep compartment is qualified against **21 deliberately poisoned declarative recipes** ([`data/fixtures/rung1_negative_controls_v1.json`](../data/fixtures/rung1_negative_controls_v1.json)) materialized into isolated out-of-tree temp directories, achieving **100% TPR, 0% FNR, and 0% FPR on deterministic/runtime/seam clean controls**, AND validated via the pre-registered Stratified RCT ([`RCT-R1`](../experiments/rct/RCT-R1-blindspot-qualification.md), $n = 32$ replicates/stratum, Wilcoxon–Mann–Whitney $\alpha = 0.01$, Vargha–Delaney $\hat{A}_{12} \ge 0.95$, Clopper–Pearson 99% CIs).

---

## 6. Lockstep Build-Up Ladder (Correspondence-Gated Rung Progression)

Every rung $k \to k+1$ must emit an explicit **Correspondence Witness** proving it smoothly contains Rung $k$ inside $\Omega_k^{\text{valid}}$ with quantifiable error bound $B(\boldsymbol{\epsilon})$:

| Rung | Layer Scope Across Rust, Swift 6.4, and Lean 4.36 | Mandatory Compartment Witnesses to Advance |
| :--- | :--- | :--- |
| **Rung 0** *(Completed — `v0.2.0`)* | **Literature, Data, Policy & Lattice Floor** (`METH-01`–`METH-55`, `swe_sweep_policy_v1.json`, `RIEM-LATTICE`, coupled `PIT-SZ × PLR`) | Referential integrity $= 100\%$; zero code/data conflation; `AUD-01`–`AUD-07` & `OBS-01` remediated; Lean/Rust/Swift lattice verified standalone. |
| **Rung 1** *(Active)* | **Compartmentalized SWE-Sweep, Blind-Spot/Seam Guards & `RCT-R1` Floor** (13 independent micro-compartments across Rust, Swift, Lean; atomic fail-closed boolean guards) | All **13** independent witnesses green; **21/21** poisoned fixtures killed (100% TPR, 0% FNR); `RCT-R1` promoted ($p < 0.01$, $\hat{A}_{12} \ge 0.95$); exact 3-way parity ($\Delta_{\text{parity}} = 0$). |
| **Rung 2** | **Shared Ground Models, Codecs & Probabilistic Parity Harnesses** (deterministic + runtime + seeded QuickCheck/metamorphic/differential fuzzing, $n \ge 30$) | Smooth containment of Rung 1 ($\Delta_{\text{logic}} = 0$); statistical bounds $B(n, \alpha)$ met across all 3 languages; zero warnings-as-errors. |
| **Rung 3** | **Reconciled Engines & Proof Kernels** (collaboratively designed with the user atop verified Rung 1–2 compartments) | Full Correspondence Witness against baseline `Riemannian` (`UP-01`–`UP-08`, $\Delta_{\text{logic}} = 0$, quantified mass ratios $\rho_i$, independent `leanchecker` + `nanoda_bin` replay). |

---

## 7. Honest Live Self-Audit & Upstream Guardrail Reconciliation

Live self-audit findings and immediate repairs are tracked strictly outside this policy model in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json) and analyzed in depth in [`models/conflation_and_boolean_guard_analysis.md`](conflation_and_boolean_guard_analysis.md):
- **Repaired & Verified (`AUD-01`–`AUD-07`)**: policy/audit separation; Rust `[workspace.lints]` + `#![forbid(unsafe_code)]` + zero ambient `Command::new("git")`; Swift `.treatAllWarnings(as: .error)` + zero `try?` + atomic `CompartmentGuardVerdict`; Lean `warningAsError = true` + parameterized atomic `GuardVerdict` with 6 kernel theorems; Paper 001 `render_figures.py` decoupled from baked literals with dynamic SHA-256 receipts (`AUD-07`).
- **Locally Healed External Platform Constraint (`OBS-01`)**: Swift `6.4.3` default `swiftbuild` runs cleanly with 0 crashes and 0 deprecation warnings via `swift_guarded_build.py` (direct Linux `os.sched_setaffinity` pinning + explicit cross-vCPU skew surfacing), with upstream bug report and minimal clamping patch drafted in `research/upstream_reports/swift_build_elapsed_timer_sigill_report.md`.

### Upstream Guardrail Check (`UP-01`–`UP-08`)
- **Zero conflicts** with [`upstream_requirements_v1.json`](../data/manifests/upstream_requirements_v1.json). The Truth-Independence Axiom (`PRIN-06`) and Correspondence Principle (`PRIN-08`) strictly reinforce `UP-01`–`UP-03` (exporting proof terms that any independent third party can copy and replay without trusting the author).
- **Retained `UP-05` nuance**: `warningAsError = true` is enforced unconditionally in `SCargo/compartments/lean/lakefile.toml`, while upstream `Riemannian/lakefile.toml` stays unmodified (`UP-05`), applying warning-as-error checks specifically to our touched modules and direct importers during transfer qualification.
