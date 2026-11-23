# Conflation Analysis, Fail-Closed Boolean Guards & SWE Risk/Consequence Matrix (`models/conflation_and_boolean_guard_analysis.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

> **Purpose**: Analyzes the five concrete forms of conflation exposed during our own ground-level audit, explains the real-world Software Engineering (SWE) risks and failure cascades of missing each defect class, defines the **Fail-Closed Atomic Boolean Guard** architecture (combining crisp boolean enforcement with compartmentalized visibility), and records the immediate live repairs verified across Rust `1.100.0`, Swift `6.4.3`, and Lean `4.36.0`.

---

## 1. Honest Diagnosis: Five Concrete Conflations Exposed in Practice

Even in a small, newly initialized laboratory, five classic SWE conflations surfaced immediately once we audited live files instead of trusting prose summaries:

| # | Conflation Axis | What Actually Happened in `SCargo` | Why It Is Dangerous in SWE | Immediate Structural Fix |
| :--- | :--- | :--- | :--- | :--- |
| **C-1** | **Normative Policy vs. Live Runtime Audit State** | Mutable live findings (`OBS-01`–`OBS-03`) were placed directly inside [`swe_sweep_policy_v1.json`](../data/manifests/swe_sweep_policy_v1.json). | Mutating a policy file whenever a bug opens/closes destroys content-addressed policy hashing and lets temporary waivers harden silently into permanent policy. | Split strictly: normative rules stay immutable in `data/manifests/`; live findings and waivers live in [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json). |
| **C-2** | **Executable Code vs. Dataset Literals** | Early [`SCargoLean/Contract.lean`](../compartments/lean/SCargoLean/Contract.lean) hardcoded theorem/axiom strings; [`render_figures.py`](../research/papers/001-riemannian-formulary-and-reduction-architecture/render_figures.py) embedded commit paths and label dictionaries. | When data lives inside code, changing a baseline or target forces code edits, breaks cross-language parity, and hides whether a regression came from logic or data (`METH-01`). | Parameterize code strictly over explicit data inputs (`guardPermittedAxioms (allowed used : List String)` in Lean; CLI-passed JSON paths in Rust/Swift). |
| **C-3** | **Advisory Warnings vs. Hard Compiler Errors** | `cargo test` passed (`8/8`, "0 warnings"), yet running `cargo clippy --all-targets -- -D warnings` immediately caught **7 live lint failures**; Lean lacked `warningAsError = true` and immediately caught 2 proof-tactic lints once enabled. | Warnings left non-fatal suffer immediate **warning blindness** (`METH-11`, `METH-12`) and invite inline suppressions (`METH-13`: 50.8% stale in FSE 2025), masking real deprecations and logic bugs. | Bake strict errors into manifests: Rust `[workspace.lints]` + `#![forbid(unsafe_code)]`, Swift `.treatAllWarnings(as: .error)`, Lean `warningAsError = true` + `linter.deprecated = true`. |
| **C-4** | **Opaque Monolithic Gate vs. Fail-Closed Atomic Boolean Guards** | Early `SafetyGate.passes : Bool` collapsed 4 orthogonal invariants into a single opaque bit; conversely, rejecting boolean guards altogether leaves checks advisory instead of fail-closed. | An opaque monolith hides *which* check tripped and creates a single-point proxy target (`METH-29`, `METH-32`); an advisory ledger without a fail-closed boolean guard lets broken code merge. | Use **Atomic Per-Compartment Boolean Guards**: every compartment produces a fail-closed `(compartment, passed : Bool, violationCount)` verdict AND an explicit `failedCompartments` list. |
| **C-5** | **Ambient Host Tooling vs. Pure Hermetic Reads** | All 3 Rust crates invoked `Command::new("git")` via ambient `PATH` just to read `HEAD`. | Relying on ambient host binaries introduces PATH-hijack vectors, hidden runtime dependencies, and non-reproducible failures across stripped sandboxes (`METH-15`, `METH-16`, `METH-28`). | Replaced all 3 `Command::new("git")` calls with a pure zero-subprocess `.git/HEAD` + `.git/<ref>` + `.git/packed-refs` file reader. |

---

## 2. Fail-Closed Atomic Boolean Guard Architecture

To satisfy **both** *fail-closed enforcement* (nothing passes if any guard is `false`) **and** *no monolithic gates* (every compartment stands alone and exposes exact failure identity), every check $j$ is structured as an **Atomic Boolean Guard**:

$$g_j(S) = \bigl(\text{id}_j,\;\; b_j \in \{\text{false}, \text{true}\},\;\; v_j \in \mathbb{N}\bigr) \qquad \text{with} \qquad b_j = \text{true} \iff v_j = 0$$

For the Correspondence Principle (`PRIN-08`), exact regimes use $b_{\text{exact}} = (\Delta = 0)$ and bounded dimensionless regimes use $b_{\text{bounded}} = (\Delta \le B(\boldsymbol{\epsilon}))$.

Over a set of independent compartment guards $\mathcal{G} = [g_1, \dots, g_k]$:
- **Diagnostic Extractor (Non-Opacity)**: $\text{Failed}(\mathcal{G}) = \{\text{id}_j \mid b_j = \text{false}\}$.
- **Fail-Closed Boolean Guard**: $G(\mathcal{G}) = \bigwedge_{j=1}^k b_j$.

This exact guard algebra is now **machine-checked in Lean 4.36.0** ([`SCargoLean/Contract.lean`](../compartments/lean/SCargoLean/Contract.lean)) and independently verified via `leanexport` → `leanchecker --from-export`:
1. `guardZeroViolations_passed_iff`: `(guardZeroViolations c n).passed = true ↔ n = 0`
2. `guardCorrespondenceExact_passed_iff`: `(guardCorrespondenceExact c m).passed = true ↔ m = 0`
3. `guardCorrespondenceBounded_passed_iff`: `(guardCorrespondenceBounded c m b).passed = true ↔ m ≤ b`
4. `allCompartmentGuardsHold_iff_forall`: `allCompartmentGuardsHold vs = true ↔ ∀ v ∈ vs, v.passed = true`
5. `failedCompartments_empty_iff`: `failedCompartments vs = [] ↔ allCompartmentGuardsHold vs = true`
6. `single_failure_rejects`: any single failing compartment forces `allCompartmentGuardsHold vs = false` (cannot be masked or outvoted).

---

## 3. SWE Risk, Consequence, Instant-ID & Immediate-Repair Matrix

What actually goes wrong in real-world software engineering and formal verification when each defect class is missed, how to detect it deterministically in seconds, and how to repair it immediately:

| Defect Class | Real-World SWE Risk & Downstream Consequence if Missed | Fast Deterministic ID Method | Immediate Repair Protocol |
| :--- | :--- | :--- | :--- |
| **`DEF-SUPP` Suppressions** (`#[allow]`, `try?`, `linter.* false`) | **Silent Defect Accumulation**: 50.8% of suppressions rot into stale masks (`METH-13`, FSE 2025) that quietly swallow newly introduced bugs, swallowed I/O errors (`OBS-02`), and skipped regression tests until production failure. | Token/AST sweep excluding comments for `allow(`, `#[ignore]`, `try?`, `-suppress-warnings`, `set_option linter.* false`, `sorry`/`admit`. | Delete the suppression and fix the root defect (e.g., propagate typed `throws` / `Result`, remove dead code, fix tactic). Never silence. |
| **`DEF-BACK` Backdoors & Escapes** (`unsafe`, `extern`, `axiom`, BiDi) | **Total Soundness / Security Collapse**: Memory corruption, unverified `axiom`/`native_decide` proving `False` (`UP-02`), build-time Trojan execution (`build.rs`, `METH-15`), or visually invisible *Trojan Source* logic flips (`METH-17`). | `#![forbid(unsafe_code)]`; token scan for `extern`, `@_silgen_name`, `@unchecked Sendable`, `axiom`/`native_decide`/`debug.skipKernelTC`; UTF-8 codepoint scan for BiDi controls (`U+202A`–`U+202E`, `U+2066`–`U+2069`). | Remove escape hatch immediately; replace with safe checked API or pure kernel-verified Lean term; strip/reject any BiDi codepoint. |
| **`DEF-HDEP` Hidden Dependencies** (ambient `git`, unpinned pkgs) | **Supply-Chain Compromise & Non-Reproducibility**: Builds silently pick up trojanized `PATH` tools, unpinned upstream drift, or undeclared transitive crates (`METH-15`, `METH-16`, `UP-04`). | Offline build gate (`cargo --locked --offline`), manifest dependency diff, scan for `Command::new`, `Process(`, `dlopen`, ambient `env::var`. | Replace subprocess calls with pure file/API reads (done in `AUD-03`), pin exact lockfiles, require explicit CLI arguments. |
| **`DEF-SYML` Symlinks & Path Escapes** | **Containment Breach & Test Hijacking**: Symlinks escape read-only sandbox boundaries into host files/credentials or inject shadow test hooks (`conftest.py`, `METH-24`, `UP-06`). | Filesystem `lstat` walk verifying `0` symlinks in tracked trees and `0` out-of-build-root targets in `.build`/`.lake`/`target`; check `.gitattributes` for `export-subst`. | Delete tracked symlink or replace with explicit manifest path; canonicalize and prefix-verify all CLI file paths against authorized roots. |
| **`DEF-WARN` Warnings & Deprecations** | **Bit-Rot & Upgrade Cliff**: Ignored deprecation warnings turn into sudden multi-thousand-line breakages on compiler upgrades and hide real logic bugs (`METH-12`). | Bake `-D warnings` + `clippy -D warnings` (Rust), `.treatAllWarnings(as: .error)` (Swift), `warningAsError = true` (Lean) into build configs. | Fix every warning immediately before moving on (7 Rust clippy errors + 2 Lean linter errors fixed in `AUD-02`/`AUD-05`). |
| **`DEF-LEAK` Confinement & Exfiltration Holes** | **Credential / IP Exfiltration & Covert Channels**: Sloppy helper hooks or telemetry endpoints leak secrets, git history, or private code (`METH-28`, `METH-33`). | Static ban on `std::net`, `URLSession`, `IO.Process`, credential paths; runtime offline/read-only containment check (`Riemannian` dirty count $= 0$). | Strip all network/telemetry/ambient-env code; confine I/O strictly to explicitly passed read-only inputs and output file arguments. |
| **`DEF-MONO` Monolithic Gates & Unverified Trust** | **False Integrity & Reward-Hacking Target**: Single-bit pass/fail gates invite helper shortcuts and hide partial check failures (`METH-29`, `METH-32`, `METH-33`). | Audit for omnibus booleans lacking per-compartment verdict lists, missing input SHA-256 digests, or checks that cannot be re-run after copying out-of-tree. | Decompose into atomic per-compartment `GuardVerdict` structs with explicit `failedCompartments` reporting (done in `AUD-04`/`AUD-06`). |
| **`DEF-COMP` Code/Data Conflation & Shortcuts** | **Silent Parity Drift & Unreproducible Claims**: Hardcoded tables drift out of sync across languages; unseeded RNGs and HashMap ordering produce flaky, irreproducible diffs (`METH-01`, `METH-21`). | Scan code for baseline/commit literals, `HashMap` serialization without sort, unseeded RNGs, or `n < 30` statistical claims. | Extract data to `data/`, sort keys deterministically (`BTreeMap`, `.sortedKeys`), record PRNG seeds in `data/`. |
| **`DEF-PAR` Cross-Language Parity Drift** | **Semantic Split-Brain**: Rust, Swift, and Lean silently disagree on counts, graph reachability, or safety verdicts, invalidating downstream reduction decisions (`METH-03`, `METH-04`). | Differential execution of Rust, Swift, and Lean on identical canonical fixtures + seeded fuzzed corpora; compare canonical output hashes. | Shrink failing counterexample, identify which compartment diverges from formal specification, fix and lock as permanent regression fixture. |
| **`DEF-CORR` Correspondence Violation** | **Regressive "Improvements"**: A deeper engine or compressed proof silently breaks a theorem statement, changes axioms, or crosses a singular limit without bounded error (`METH-34`–`METH-37`). | Execute `guardCorrespondenceExact` ($\Delta = 0$ on logical/kernel invariants) and `guardCorrespondenceBounded` ($\Delta \le B(\boldsymbol{\epsilon})$) at every rung transition. | Reject deeper candidate immediately; tighten validity domain $\Omega_k^{\text{valid}}$ or fix proof/algorithm until correspondence inequality holds. |

---

## 4. Verified Live Before-vs-After Repair Summary (2026-11-23)

All live defects controllable inside `SCargo` were repaired immediately and re-verified under strict compiler/kernel enforcement:

| Audit ID | Compartment | Live Defect Caught | Immediate Repair Applied | Verified Status |
| :--- | :--- | :--- | :--- | :--- |
| `AUD-01` | `data/manifests` | Mutable live ledger embedded in policy manifest | Split live audit state into [`data/audits/live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json) | **REPAIRED & VERIFIED** |
| `AUD-02` | Rust `1.100.0` | **7** live `clippy -D warnings` errors + missing `forbid(unsafe_code)` | Added `[workspace.lints]` + `#![forbid(unsafe_code)]`; fixed all 7 errors with `0` `#[allow]` | **REPAIRED & VERIFIED** (`0` warnings, `8/8` tests) |
| `AUD-03` | Rust `1.100.0` | **3** ambient `Command::new("git")` subprocess calls | Replaced with pure zero-subprocess `.git/HEAD` + `packed-refs` reader | **REPAIRED & VERIFIED** (`0` `Command::new` hits) |
| `AUD-04` | Swift `6.4.3` | `try?` stderr suppression, 6 raw `exit()`, missing `Package.swift` warnings-as-errors | Added `.treatAllWarnings(as: .error)`, throwing stderr write, typed `SCargoAuditError`, 5 atomic `CompartmentGuardVerdict` guards | **REPAIRED & VERIFIED** (`0` `swiftc` warnings, `5/5` `[PASS]`) |
| `AUD-05` | Lean `4.36.0` | Missing `warningAsError = true` & strict linters in `lakefile.toml` | Enabled `warningAsError = true`, `linter.deprecated = true`, `linter.unusedVariables = true`; fixed 2 caught tactic lints | **REPAIRED & VERIFIED** (`6/6` jobs, `0` warnings) |
| `AUD-06` | Lean `4.36.0` | Monolithic `SafetyGate.passes` + hardcoded theorem tables in `Contract.lean` | Refactored to parameterized atomic `GuardVerdict` boolean guards + 6 machine-checked soundness/correspondence theorems | **REPAIRED & VERIFIED** (`leanchecker` + `leanexport` → `leanchecker --from-export` accepted) |
| `AUD-07` | `research/001` | Hardcoded paths & label dictionary in `render_figures.py` | Logged explicitly in [`live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json) for next Paper 001 pass | **OPEN (EXPLICIT)** |
| `OBS-01` | Swift VM Driver | Swift 6.4.3 `swiftbuild` VM `SIGILL`; `--build-system native` deprecation notice | External VM/toolchain issue; visibly logged in [`live_self_audit_v1.json`](../data/audits/live_self_audit_v1.json), never silenced | **EXTERNAL PLATFORM WAIVER** |
