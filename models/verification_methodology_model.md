# Ground-Level Verification, Zero-Trust Compartments & Correspondence Methodology Model (`models/verification_methodology_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v2.0`

> **Separation Rule**: This document defines the **formal methodological model** only. All 37 primary-archive bibliographic records live in [`data/sources/methodology_literature_v1.json`](../data/sources/methodology_literature_v1.json) (`METH-01`–`METH-37`), all pure normative policy rules live in [`data/manifests/swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json) (`v1.1.0`), live audit findings and external platform waivers live separately in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json), and upstream target constraints live in [`data/manifests/upstream_requirements_v1.json`](../data/manifests/upstream_requirements_v1.json) (`UP-01`–`UP-08`). No executable engine, kernel, or sweep code is conflated into this specification.

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

Instead, every compartment $C \in \{\text{Rust},\; \text{Swift},\; \text{Lean}\}$ is audited by a set of **independent, minimally coupled Verification Compartments**, each emitting its own **Proof-Carrying Witness** $w_j$:

$$\mathcal{W}(C, S) = \bigl\{\; w_{\text{compiler}},\; w_{\text{suppression}},\; w_{\text{backdoor}},\; w_{\text{confinement}},\; w_{\text{deps}},\; w_{\text{topology}},\; w_{\text{parity}},\; w_{\text{kernel}},\; w_{\text{correspondence}} \;\bigr\}$$

### Proof-Carrying Compartment Witness Contract
Every individual witness $w_j$ is an immutable JSON (or Lean kernel export) artifact whose validity **does not depend on trusting the producer or keeping any file secret/unmodified**:
- `witness_compartment_id` & `schema_version`
- `input_content_digests`: SHA-256 hashes of every exact source file, manifest, and fixture evaluated (if any file is modified, the digest mismatch is immediately obvious to any external verifier)
- `policy_digest`: SHA-256 hash of [`swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json)
- `regime`: `deterministic` | `runtime` | `probabilistic`
- `findings`: explicit list of exact file/line/defect-class records (empty for pass)
- `active_waivers_observed`: explicit visible listing of every matched external waiver in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json) (zero silent waivers; stale waivers fail!)
- `correspondence_bound`: declared $\boldsymbol{\epsilon}$, measured $\Delta$, and bound $B(\boldsymbol{\epsilon})$ (for `w_correspondence`)
- `independent_replay_command`: exact offline command enabling any third party to copy the inputs onto a fresh machine and reproduce the witness byte-for-byte.

---

## 4. Eight-Pillar Literature Map (`METH-01`–`METH-37`)

| Pillar | Primary Archival Anchors | Operational Guarantee in `SCargo` |
| :--- | :--- | :--- |
| **PIL-I** Separation & Clean-Room | Parnas (1972), Mills–Dyer–Linger (1987) (`METH-01`–`METH-02`) | Disjoint `data/`, `models/`, `compartments/`; models precede code. |
| **PIL-II** Cross-Language Parity | Avizienis (1985), McKeeman (1998), Le–Afshari–Su (2014) (`METH-03`–`METH-05`) | Independent Rust, Swift 6.4, Lean 4.36 implementations cross-check identical canonical fixtures. |
| **PIL-III** Trusting Trust & Kernels | Thompson (1984), Pollack (1998), Barendregt–Wiedijk (2005), Wheeler (2009), Carneiro (2024) (`METH-06`–`METH-10`) | Official signed/source-built toolchains + de Bruijn replay (`leanexport` → `leanchecker` / `nanoda_bin`). |
| **PIL-IV** Warnings & Anti-Suppression | Bessey et al. (2010), Sadowski et al. (2018), Hu et al. (FSE 2025), Swift SE-0443/SE-0414 (`METH-11`–`METH-14`) | Warnings and deprecations are hard errors; zero blanket or stale suppressions (50.8% stale in FSE 2025). |
| **PIL-V** Supply Chain, Symlinks & BiDi | Ohm et al. (2020), Lamb–Zacchiroli (2022), Boucher–Anderson (2023), NIST SP 800-218, SLSA v1.0/v1.1 (`METH-15`–`METH-19`) | Offline pinned builds, zero undeclared deps, zero tracked symlinks, zero build hooks, zero BiDi controls. |
| **PIL-VI** Probabilistic & Adversarial Audits | Claessen–Hughes (2000), Arcuri–Briand (2014), Segura et al. (2016), Klees et al. (2018), Wang et al. (2026), Ludwig et al. (2026) (`METH-20`–`METH-25`) | Seeded QuickCheck/metamorphic/differential sweeps, $n \ge 30$ Wilcoxon–Mann–Whitney + $\hat{A}_{12}$, red-team harness audits. |
| **PIL-VII** Zero-Trust Helper Pathology & Confinement | Kerckhoffs (1883), Shannon (1949), Lampson (1973), Saltzer–Schroeder (1975), DeMillo–Lipton–Sayward (1978), Necula (1997), Skalse et al. (2022), Hu et al. (Oct 2026) (`METH-26`–`METH-33`) | Truth independent of non-copying/non-modification; no monolithic gates; zero leaker/exfil holes; mutation-qualified witnesses. |
| **PIL-VIII** The Correspondence Principle | Bohr (1920), Ehrenfest (1927), Nickles (1973), Bokulich (2008) (`METH-34`–`METH-37`) | Every deeper layer smoothly contains the older baseline inside $\Omega_k^{\text{valid}}$ with computable error bound $B(\boldsymbol{\epsilon})$. |

---

## 5. Tri-Regime SWE-Sweep Vector & 10-Class Defect Matrix

Each language compartment $C \in \{\text{Rust},\; \text{Swift},\; \text{Lean}\}$ is evaluated across three orthogonal verification regimes ($\mathbf{V}_{\text{det}}, \mathbf{V}_{\text{run}}, \mathbf{V}_{\text{prob}}$) targeting **10 hard-fail defect classes** codified in [`swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json):

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

### Adversarial Negative-Control Qualification (`14` Poisoned Fixtures)
Following DeMillo–Lipton–Sayward (`METH-31`) and *BenchJack* (`METH-24`), every SWE-sweep compartment is qualified against **14 deliberately poisoned negative-control fixtures** (covering all 10 defect classes and all 3 languages) and must achieve **100% TPR, 0% FNR, and 0% FPR on clean controls**—even when the fixture tree is copied to an arbitrary external directory and re-executed independently.

---

## 6. Lockstep Build-Up Ladder (Correspondence-Gated Rung Progression)

Every rung $k \to k+1$ must emit an explicit **Correspondence Witness** proving it smoothly contains Rung $k$ inside $\Omega_k^{\text{valid}}$ with quantifiable error bound $B(\boldsymbol{\epsilon})$:

| Rung | Layer Scope Across Rust, Swift 6.4, and Lean 4.36 | Mandatory Compartment Witnesses to Advance |
| :--- | :--- | :--- |
| **Rung 0** *(Current)* | **Literature, Data & Policy Floor** (`METH-01`–`METH-37`, `swe_sweep_policy_v1.json`, `upstream_requirements_v1.json`, formal models) | Referential integrity $= 100\%$; zero code/data conflation; live ground defects `AUD-01`–`AUD-06` repaired; user design sign-off. |
| **Rung 1** | **Compartmentalized SWE-Sweep & Negative-Control Floor** (independent micro-compartments across Rust, Swift, Lean; atomic fail-closed boolean guards) | All 9 independent witnesses green; **14/14** poisoned fixtures killed (100% TPR, 0% FPR); exact 3-way parity ($\Delta_{\text{parity}} = 0$). |
| **Rung 2** | **Shared Ground Models, Codecs & Probabilistic Parity Harnesses** (deterministic + runtime + seeded QuickCheck/metamorphic/differential fuzzing, $n \ge 30$) | Smooth containment of Rung 1 ($\Delta_{\text{logic}} = 0$); statistical bounds $B(n, \alpha)$ met across all 3 languages; zero warnings-as-errors. |
| **Rung 3** | **Reconciled Engines & Proof Kernels** (collaboratively designed with the user atop verified Rung 1–2 compartments) | Full Correspondence Witness against baseline `Riemannian` (`UP-01`–`UP-08`, $\Delta_{\text{logic}} = 0$, quantified mass ratios $\rho_i$, independent `leanchecker` + `nanoda_bin` replay). |

---

## 7. Honest Live Self-Audit & Upstream Guardrail Reconciliation

Live self-audit findings and immediate repairs are tracked strictly outside this policy model in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json) and analyzed in depth in [`models/conflation_and_boolean_guard_analysis.md`](conflation_and_boolean_guard_analysis.md):
- **Immediately Repaired & Verified (`AUD-01`–`AUD-06`)**: policy/audit separation; Rust `[workspace.lints]` + `#![forbid(unsafe_code)]` + 7 clippy `-D warnings` fixes + removal of all 3 ambient `Command::new("git")` subprocesses; Swift `.treatAllWarnings(as: .error)` + removal of `try?` stderr swallowing and raw `exit()` + 5 atomic `CompartmentGuardVerdict` guards; Lean `warningAsError = true` + strict linters + parameterized atomic boolean guards (`GuardVerdict`) with 6 kernel-exported soundness theorems.
- **Explicit Open Items**: `AUD-07` (hardcoded paths/labels in Paper 001's `render_figures.py`, queued for Paper 001 revision) and `OBS-01` (external VM/toolchain constraint where Swift `6.4.3` `swiftbuild` traps in `ElapsedTimer.elapsedTime()`, requiring `--build-system native` whose driver deprecation notice is visibly surfaced and never silenced).

### Upstream Guardrail Check (`UP-01`–`UP-08`)
- **Zero conflicts** with [`upstream_requirements_v1.json`](../data/manifests/upstream_requirements_v1.json). The Truth-Independence Axiom (`PRIN-06`) and Correspondence Principle (`PRIN-08`) strictly reinforce `UP-01`–`UP-03` (exporting proof terms that any independent third party can copy and replay without trusting the author).
- **Retained `UP-05` nuance**: `warningAsError = true` is enforced unconditionally in `SCargo/compartments/lean/lakefile.toml`, while upstream `Riemannian/lakefile.toml` stays unmodified (`UP-05`), applying warning-as-error checks specifically to our touched modules and direct importers during transfer qualification.
