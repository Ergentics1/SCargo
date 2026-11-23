# Swift 6.4 / Open-Source Swift Compartment (`compartments/swift`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

This compartment targets **Open-Source Swift `6.4.3`** (`swift-tools-version: 6.4`, Swift 6 strict concurrency / `Sendable` language mode, `.treatAllWarnings(as: .error)`) and maintains:
- **`SCargoModel`** & **`scargo-audit`**: Strongly-typed `Codable`/`Sendable` schemas, `ClockMonotonicityGuard` (`OBS-01`), and ICD/baseline/trace auditing (`SCargoModelTests`).
- **`RiemLattice`** & **`scargo-riem-lattice`**: Standalone Import-Style Riemann Lattice machine layer with exact $\mathbb{Z}/\mathbb{Q}$ (`ExactInt`/`ExactRat`) Faddeev–LeVerrier, 24×24 Bass–Ihara determinant & functional equation, Möbius prime-cycle enumerator, $N$-TET Correspondence-Principle sweep, and 8 atomic fail-closed `CompartmentGuardVerdict`s verified against `data/sources/riemann_lattice_graph_rh_v1.json` (`RiemLatticeTests`).
- **`SchwartzZippel`** & **`scargo-schwartz-zippel`**: Standalone coupled `PIT-SZ × PLR` cyclotomic torus engine (`F_p` for $p \equiv 1 \pmod{12}$), bilinear `P, L, R` involutions, dihedral holonomy (`rho_k`), 72-edge Hashimoto non-backtracking vs. SRW mixing, length-6 homology cycle sieving, low-entropy Ramanujan walk PIT, `G_PLR` Edmonds & Bass–Ihara PIT bridge, and 9 atomic fail-closed guards (`SchwartzZippelTests`).
- **`SCargoSweep`** & **`scargo-sweep`**: Standalone Rung 1 13-witness Proof-Carrying SWE-sweep (pure-Swift SHA-256), D/R/P/Seam blind-spot guards (Neumaier/Higham FP, Cholesky SPD, positive `isFinite`, conservation caps, Massart–DKW Calibration-PIT, Clopper–Pearson coverage, CRPS/Brier, OOD, typed `P -> D` admission, bit-exact `D -> P` replay), 21-poison + 5-clean out-of-tree fixture qualifier (`PRIN-06`), and Stratified `RCT-R1` engine (`SCargoSweepTests`).
- **`SCargoGround`** & **`scargo-ground`**: Standalone Rung 2 shared ground codec (canonical JSON encode/decode, Kahn cycle check, exact fixed-point dominators + cut oracle, AST wrapper classifier), deterministic 1-edge-minimal QuickCheck shrinker, `MR-1`..`MR-3` metamorphic invariance suite, and seeded 384-case differential parity harness matching Rust SHA-256 byte-for-byte (`SCargoGroundTests`).
- **`SCargoAirlock`** & **`scargo-airlock`**: Standalone Rung 3 reconciled proof-reduction & clean-room ICD airlock verifier (`AG-1`..`AG-5`, exact baseline/trace conservation, Pareto mass ratios $\rho_i$, deterministic `UP-07` $\le 8$-root batch schedules, RCT-001 Vargha–Delaney $\hat{A}_{12}$, synthetic clean-room transforms, and 7 adversarial airlock controls matching Rust SHA-256 byte-for-byte; `SCargoAirlockTests`).

## Standalone Verification Commands (Guarded Default `swiftbuild`, 0 Warnings)

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
```
