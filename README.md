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
│   ├── rust/                         # Rust 1.100.0 workspace: scargo-probe, scargo-trace, scargo-qualify, scargo-riem-lattice, scargo-schwartz-zippel, scargo-sweep, scargo-ground, scargo-airlock, scargo-census, scargo-emit, scargo-patch, scargo-rehearsal (zero-dep, forbid(unsafe_code))
│   ├── swift/                        # Open-Source Swift 6.4.3: SCargoModel, RiemLattice, SchwartzZippel, SCargoSweep, SCargoGround, SCargoAirlock, SCargoCensus, SCargoEmit, SCargoPatch, SCargoRehearsal, CLIs & Swift Testing suites
│   └── lean/                         # Lean v4.36.0: SCargoLean.Contract, RiemLattice, SchwartzZippel, SweepWitness, GroundCodec, TransferAirlock, HighMassCensus, Preflight.* (`module`), PreflightHarness, PatchVerifier, AirlockRehearsal + standalone test drivers
├── models/
│   ├── reduction_model.md            # Quantitative proof mass-budget & reduction equations
│   ├── verification_methodology_model.md   # Deterministic / runtime / probabilistic SWE-sweep & D<->R<->P seam model (13 witnesses, 14 defects)
│   ├── rung2_ground_codec_and_parity_model.md  # Rung 2 shared ground codec, QuickCheck shrinking, MR-1..3 metamorphic invariance & parity model
│   ├── rung3_reconciled_reduction_and_airlock_model.md  # Rung 3 reconciled proof-reduction airlock, AG-1..AG-5 & UP-07 batching model
│   ├── arc4_high_mass_zone_census_model.md  # Arc 4 Z-C2/Z-C3/Z-C4 high-mass census, UP-08 lexical reconciliation & Pareto ranking model
│   ├── arc5_elaboration_and_emitter_model.md  # Arc 5 Lean 4.36 `module` pre-flight elaboration harness & dual-route UP-07 patch emitter model
│   ├── arc6_ast_patch_generator_model.md  # Arc 6 concrete AST-aware patch generator (`Z-C0`/`Z-C2`/`Z-C4`) & pure in-memory unified-diff verifier model
│   ├── arc7_g4_g5_rehearsal_and_publication_model.md  # Arc 7 G4-G5 CI receipt ingestor, quick-check.py:80 routing refinement & Paper 002 publication model
│   ├── conflation_and_boolean_guard_analysis.md  # Helper-pathology taxonomy, AUD-01..07 & atomic guard spec
│   ├── riemannian_disambiguation_model.md  # Authority-controlled RIEM-A / RIEM-B / RIEM-C / RIEM-LATTICE map
│   ├── riemann_lattice_graph_rh_model.md   # Euler 1735-1739 root & exact proof: G_PLR satisfies Graph RH
│   └── schwartz_zippel_lattice_model.md    # ODLSZ / Schwartz-Zippel lineage, coupled PLR torus, ring bounds & G_PLR PIT bridge
├── data/
│   ├── README.md                     # Code/data/policy/audit separation contract
│   ├── sources/                      # 8 disjoint primary-source vaults (RIEM-A, RIEM-C [88 works], RIEM-LATTICE, PIT-SZ [38 works], SWE lit [55 works], lexicon v1.1.0, Paper 001 & Paper 002 presentations)
│   ├── fixtures/                     # Declarative negative-control & clean-control recipe vault (21 poisoned + 5 clean)
│   ├── manifests/                    # Normative policies (swe_sweep_policy_v1.json v1.2.0, transfer_zones_v1.json, upstream_requirements_v1.json)
│   ├── audits/                       # Live self-audit ledger & remediation receipts (live_self_audit_v1.json)
│   ├── baselines/                    # Read-only telemetry snapshots (riemannian_51d9b1a280_inventory.json)
│   ├── traces/                       # Independent dominator/reachability traces (riemannian_51d9b1a280_trace.json)
│   └── trials/                       # Deterministic RCT allocations, RCT-R1 config, Rung 2 fuzz corpus config, Arc 4 high-mass census & dry-run reports
├── experiments/
│   ├── retrospective/                # Observational baseline census (STUDY-001)
│   └── rct/                          # Pre-registered RCT templates & qualification protocols (DRYRUN-001, RCT-001, RCT-R1)
├── research/
│   ├── papers/
│   │   ├── 001-riemannian-formulary-and-reduction-architecture/  # Working Paper 001 (v2.1), guarded figure renderer + 9 tests, PNGs, HTML
│   │   └── 002-clean-room-ast-reduction-and-g4-g5-rehearsal/     # Working Paper 002 (v1.0), guarded figure renderer + 8 tests, PNGs & SHA-256 manifest
│   └── upstream_reports/             # Upstream Swift swift-build ElapsedTimer SIGILL report & minimal patch
└── transfer/
    ├── ICD-RIEMANNIAN.md             # Interface Control Document & flight-readiness gates for Riemannian
    ├── README.md                     # Clean-room separation plane & G1-G3 vs G4-G5 sign-off contract
    ├── packages/                     # Declarative staged clean-room transfer package manifests (rung3_airlock_manifest_v1.json)
    ├── bundles/                      # Declarative Arc 5 dual-route UP-07 pre-flight shard & full-runner bundles (arc5_preflight_bundles_v1.json)
    ├── patches/                      # Zero-copy content-addressed Arc 6 per-file AST patch plan & SHA-256 receipts (arc6_patch_plan_v1.json)
    └── rehearsal/                    # Arc 7 G4-G5 CI receipt ingestor & airlock rehearsal bundle (arc7_g4_g5_rehearsal_v1.json)
```

---

## Standalone Per-Language Verification Commands

Each compartment runs independently with zero cross-language combo wrappers:

### 1. Lean (`v4.36.0`, `warningAsError = true`, `LEAN_ABORT_ON_PANIC=1`, zero `sorry` / `native_decide`)
```bash
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean build SCargoLean riem_lattice_test sz_lattice_test sweep_witness_test ground_codec_test transfer_airlock_test high_mass_census_test preflight_harness_test patch_verifier_test airlock_rehearsal_test
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe riem_lattice_test
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe sz_lattice_test
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe sweep_witness_test
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe ground_codec_test
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe transfer_airlock_test .
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe high_mass_census_test .
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe preflight_harness_test .
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe patch_verifier_test .
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean exe airlock_rehearsal_test .
LEAN_PATH=compartments/lean/.lake/build/lib/lean leanchecker SCargoLean SCargoLean.Contract SCargoLean.RiemLattice SCargoLean.SchwartzZippel SCargoLean.SweepWitness SCargoLean.GroundCodec SCargoLean.TransferAirlock SCargoLean.HighMassCensus SCargoLean.Preflight.Leaf SCargoLean.Preflight.Mid SCargoLean.Preflight.WrapAlias SCargoLean.Preflight.HubPruned SCargoLean.Preflight.CompactCse SCargoLean.PreflightHarness SCargoLean.PatchVerifier SCargoLean.AirlockRehearsal
```

### 2. Rust (`1.100.0`, zero external crates, `-D warnings`, `#![forbid(unsafe_code)]`)
```bash
RUSTFLAGS="-D warnings" cargo clippy --manifest-path compartments/rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path compartments/rust/Cargo.toml
cargo build --release --manifest-path compartments/rust/Cargo.toml
compartments/rust/target/release/scargo-riem-lattice \
  --vault data/sources/riemann_lattice_graph_rh_v1.json
compartments/rust/target/release/scargo-schwartz-zippel \
  --sz-vault data/sources/schwartz_zippel_research_v1.json \
  --rl-vault data/sources/riemann_lattice_graph_rh_v1.json
compartments/rust/target/release/scargo-sweep all --root .
compartments/rust/target/release/scargo-ground --root .
compartments/rust/target/release/scargo-airlock --root .
compartments/rust/target/release/scargo-census verify --root .
compartments/rust/target/release/scargo-emit verify --root .
compartments/rust/target/release/scargo-patch verify --root .
compartments/rust/target/release/scargo-rehearsal verify --root .
```

### 3. Open-Source Swift (`6.4.3`, `.treatAllWarnings(as: .error)`, guarded default `swiftbuild`)
```bash
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- test --package-path compartments/swift
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- build -c release --package-path compartments/swift
compartments/swift/.build/release/scargo-riem-lattice \
  --vault data/sources/riemann_lattice_graph_rh_v1.json
compartments/swift/.build/release/scargo-schwartz-zippel \
  --sz-vault data/sources/schwartz_zippel_research_v1.json \
  --rl-vault data/sources/riemann_lattice_graph_rh_v1.json
compartments/swift/.build/release/scargo-sweep all --root .
compartments/swift/.build/release/scargo-ground --root .
compartments/swift/.build/release/scargo-airlock --root .
compartments/swift/.build/release/scargo-census --root .
compartments/swift/.build/release/scargo-emit --root .
compartments/swift/.build/release/scargo-patch --root .
compartments/swift/.build/release/scargo-rehearsal --root .
```

---

## Key Foundational Documents

- Architecture & Zero-Trust Invariants: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Disambiguation of Bernhard vs. Hugo Riemann: [`models/riemannian_disambiguation_model.md`](models/riemannian_disambiguation_model.md)
- Euler 1730s Root & Neo-Riemannian *Tonnetz* Dual Graph-RH Proof: [`models/riemann_lattice_graph_rh_model.md`](models/riemann_lattice_graph_rh_model.md)
- Schwartz–Zippel (ODLSZ) Lattice Module & PIT Integration: [`models/schwartz_zippel_lattice_model.md`](models/schwartz_zippel_lattice_model.md)
- Verification Methodology & Conflation Guard Analysis: [`models/verification_methodology_model.md`](models/verification_methodology_model.md) · [`models/conflation_and_boolean_guard_analysis.md`](models/conflation_and_boolean_guard_analysis.md)
- Rung 2 Ground Codec, QuickCheck Shrinking & Differential Parity Model: [`models/rung2_ground_codec_and_parity_model.md`](models/rung2_ground_codec_and_parity_model.md)
- Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock Model: [`models/rung3_reconciled_reduction_and_airlock_model.md`](models/rung3_reconciled_reduction_and_airlock_model.md)
- Arc 4 High-Mass Zone Census (`Z-C2`/`Z-C3`/`Z-C4`) & `UP-08` Lexical Provenance Model: [`models/arc4_high_mass_zone_census_model.md`](models/arc4_high_mass_zone_census_model.md)
- Arc 5 Lean `v4.36.0` `module` Pre-Flight Elaboration & Dual-Route `UP-07` Emitter Model: [`models/arc5_elaboration_and_emitter_model.md`](models/arc5_elaboration_and_emitter_model.md)
- Arc 6 Concrete AST-Aware Patch Generator & Unified-Diff Verifier Model: [`models/arc6_ast_patch_generator_model.md`](models/arc6_ast_patch_generator_model.md)
- Arc 7 G4–G5 CI Receipt Ingestor, Airlock Rehearsal & Publication Model: [`models/arc7_g4_g5_rehearsal_and_publication_model.md`](models/arc7_g4_g5_rehearsal_and_publication_model.md)
- Interface Control Document (`Riemannian` airlock): [`transfer/ICD-RIEMANNIAN.md`](transfer/ICD-RIEMANNIAN.md)
- Paper 001 (v2.1 — Formulary & Reduction Architecture): [`research/papers/001-riemannian-formulary-and-reduction-architecture/paper.md`](research/papers/001-riemannian-formulary-and-reduction-architecture/paper.md)
- Paper 002 (v1.0 — Concrete 137-File AST Reduction & G4–G5 Rehearsal): [`research/papers/002-clean-room-ast-reduction-and-g4-g5-rehearsal/paper.md`](research/papers/002-clean-room-ast-reduction-and-g4-g5-rehearsal/paper.md)

