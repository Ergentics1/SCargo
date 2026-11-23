# SCargo

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

**Compartmentalized Rust `1.100.0` / Open-Source Swift `6.4.3` / Lean `v4.36.0` Research, Modeling & Verification Laboratory**

`SCargo` is the clean-room, multi-language engineering laboratory and foundational modeling platform for:
1. **Primary-source mathematical & systems modeling** (strictly separating Bernhard Riemann's analytic number theory `RIEM-A`, Bernhard Riemann's differential geometry `RIEM-B`, Hugo Riemann's harmonic/metric theory `RIEM-C` / `RIEM-C-ALG`, and their shared late-1730s Leonhard Euler trunk in the **Import-Style Riemann Lattice** `RIEM-LATTICE`);
2. **Independent static tracing, formulary synthesis, and gated proof-size reduction** for [`Ergentics1/Riemannian`](https://github.com/Ergentics1/Riemannian) (the Lean 4 formalization of RH / GRH).

`SCargo`'s primary-source vaults, formal models, verification architecture, and documentation advance and commit **independently** — they do not wait on `Ergentics1/Riemannian`, which remains strictly untouched across the separation plane until explicit ICD-gated transfer.

---

## Core Thesis & Engineering Principles

> **The Correspondence Principle (Governing Thesis)**: *Every deeper theory must smoothly contain the older theory inside its proven dimensionless regime, with a quantifiable error bound on the mismatch.*

Built on the **SpaceX Falcon Payload User's Guide (Rev. 8, May 2025)**, the **NASA ISS Reference Guide (NP-2010-09-682-HQ, Nov 2010)**, peer-reviewed verification literature (`data/sources/methodology_literature_v1.json`), and retrospective/RCT empirical rigor:

1. **Zero-Trust Helper-Pathology Defense**: *"Build nothing whose truth depends on it not being copied/modified."* Every check is an **atomic, fail-closed boolean guard** inside an independent compartment (no monolithic gates), paired with an explicit healing path and tracked transparently in [`data/audits/live_self_audit_v1.json`](data/audits/live_self_audit_v1.json) (`AUD-01`–`AUD-07` and `OBS-01` verified).
2. **Strict Separation of Code, Data, Policy, Audits & Lineage**:
   - Executable engines live in `compartments/`;
   - Immutable primary-source registries, baselines, traces, and trials live in `data/sources/`, `data/baselines/`, `data/traces/`, and `data/trials/`;
   - Normative rules live in `data/manifests/`, strictly separate from live audit state in `data/audits/`;
   - Formal mathematical and architectural models live in `models/`;
   - Papers, reproducible figures (verified by SHA-256 manifest), and upstream bug reports live in `research/`.
3. **Standalone Per-Language Execution ("No Combo")**: Each language compartment (**Rust**, **Swift**, **Lean**) compiles, tests, and executes **strictly on its own** with warnings-as-errors enabled and zero cross-language wrapper scripts.
4. **Primary Archives & Peer-Reviewed Venues Only**: All source vaults exclude crowdsourced wikis and anchor directly to national libraries (DNB GND / Deutsche Biographie), digitized first editions, university presses, peer-reviewed journals, and arXiv preprints.

---

## Repository Layout

```text
SCargo/
├── ARCHITECTURE.md                   # Compartment philosophy, Correspondence Principle & zero-trust invariants
├── compartments/
│   ├── rust/                         # Rust 1.100.0 workspace: scargo-probe, scargo-trace, scargo-qualify, scargo-riem-lattice (zero-dep, forbid(unsafe_code))
│   ├── swift/                        # Open-Source Swift 6.4.3: SCargoModel, RiemLattice, scargo-audit, scargo-riem-lattice, Swift Testing suites
│   └── lean/                         # Lean v4.36.0: SCargoLean.Contract, SCargoLean.RiemLattice (pure-kernel Graph-RH proofs), riem_lattice_test
├── models/
│   ├── reduction_model.md            # Quantitative proof mass-budget & reduction equations
│   ├── verification_methodology_model.md   # Deterministic / runtime / probabilistic SWE-sweep model
│   ├── conflation_and_boolean_guard_analysis.md  # Helper-pathology taxonomy, AUD-01..07 & atomic guard spec
│   ├── riemannian_disambiguation_model.md  # Authority-controlled RIEM-A / RIEM-B / RIEM-C / RIEM-LATTICE map
│   └── riemann_lattice_graph_rh_model.md   # Euler 1735-1739 root & exact proof: G_PLR satisfies Graph RH
├── data/
│   ├── README.md                     # Code/data/policy/audit separation contract
│   ├── sources/                      # 6 disjoint primary-source vaults (RIEM-A, RIEM-C [88 works], RIEM-LATTICE, SWE lit, lexicon, Paper 001 presentation)
│   ├── manifests/                    # Normative policies (swe_sweep_policy_v1.json, transfer_zones_v1.json, upstream_requirements_v1.json)
│   ├── audits/                       # Live self-audit ledger & remediation receipts (live_self_audit_v1.json)
│   ├── baselines/                    # Read-only telemetry snapshots (riemannian_51d9b1a280_inventory.json)
│   ├── traces/                       # Independent dominator/reachability traces (riemannian_51d9b1a280_trace.json)
│   └── trials/                       # Deterministic RCT allocations & clean-room dry-run qualification reports
├── experiments/
│   ├── retrospective/                # Observational baseline census (STUDY-001)
│   └── rct/                          # Pre-registered RCT templates & qualification baselines (DRYRUN-001, RCT-001)
├── research/
│   ├── papers/001-riemannian-formulary-and-reduction-architecture/  # IMRaD paper, guarded figure renderer + tests, PNGs, HTML
│   └── upstream_reports/             # Upstream Swift swift-build ElapsedTimer SIGILL report & minimal patch
└── transfer/
    └── ICD-RIEMANNIAN.md             # Interface Control Document & flight-readiness gates for Riemannian
```

---

## Standalone Per-Language Verification Commands

Each compartment runs independently with zero cross-language combo wrappers:

### 1. Lean (`v4.36.0`, `warningAsError = true`, `LEAN_ABORT_ON_PANIC=1`, zero `sorry` / `native_decide`)
```bash
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean build
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean test
LEAN_PATH=compartments/lean/.lake/build/lib/lean leanchecker SCargoLean SCargoLean.Contract SCargoLean.RiemLattice
```

### 2. Rust (`1.100.0`, zero external crates, `-D warnings`, `#![forbid(unsafe_code)]`)
```bash
RUSTFLAGS="-D warnings" cargo clippy --manifest-path compartments/rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path compartments/rust/Cargo.toml
cargo build --release --manifest-path compartments/rust/Cargo.toml
compartments/rust/target/release/scargo-riem-lattice \
  --vault data/sources/riemann_lattice_graph_rh_v1.json
```

### 3. Open-Source Swift (`6.4.3`, `.treatAllWarnings(as: .error)`, guarded default `swiftbuild`)
```bash
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- test --package-path compartments/swift
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- build -c release --package-path compartments/swift
compartments/swift/.build/release/scargo-riem-lattice \
  --vault data/sources/riemann_lattice_graph_rh_v1.json
```

---

## Key Foundational Documents

- Architecture & Zero-Trust Invariants: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Disambiguation of Bernhard vs. Hugo Riemann: [`models/riemannian_disambiguation_model.md`](models/riemannian_disambiguation_model.md)
- Euler 1730s Root & Neo-Riemannian *Tonnetz* Dual Graph-RH Proof: [`models/riemann_lattice_graph_rh_model.md`](models/riemann_lattice_graph_rh_model.md)
- Verification Methodology & Conflation Guard Analysis: [`models/verification_methodology_model.md`](models/verification_methodology_model.md) · [`models/conflation_and_boolean_guard_analysis.md`](models/conflation_and_boolean_guard_analysis.md)
- Interface Control Document (`Riemannian` airlock): [`transfer/ICD-RIEMANNIAN.md`](transfer/ICD-RIEMANNIAN.md)
- Paper 001 (Formulary & Reduction Architecture): [`research/papers/001-riemannian-formulary-and-reduction-architecture/paper.md`](research/papers/001-riemannian-formulary-and-reduction-architecture/paper.md)

