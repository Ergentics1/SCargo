# Swift 6.4 / Open-Source Swift Compartment (`compartments/swift`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

This compartment targets **Open-Source Swift `6.4.3`** (`swift-tools-version: 6.4`, Swift 6 strict concurrency / `Sendable` language mode, `.treatAllWarnings(as: .error)`) and maintains:
- **`SCargoModel`** & **`scargo-audit`**: Strongly-typed `Codable`/`Sendable` schemas, `ClockMonotonicityGuard` (`OBS-01`), and ICD/baseline/trace auditing (`SCargoModelTests`).
- **`RiemLattice`** & **`scargo-riem-lattice`**: Standalone Import-Style Riemann Lattice machine layer with exact $\mathbb{Z}/\mathbb{Q}$ (`ExactInt`/`ExactRat`) Faddeev–LeVerrier, 24×24 Bass–Ihara determinant & functional equation, Möbius prime-cycle enumerator, $N$-TET Correspondence-Principle sweep, and 8 atomic fail-closed `CompartmentGuardVerdict`s verified against `data/sources/riemann_lattice_graph_rh_v1.json` (`RiemLatticeTests`).

## Standalone Verification Commands (Guarded Default `swiftbuild`, 0 Warnings)

```bash
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- test --package-path compartments/swift
python3 compartments/swift/scripts/swift_guarded_build.py --check-zero-warnings -- build -c release --package-path compartments/swift
compartments/swift/.build/release/scargo-riem-lattice \
  --vault data/sources/riemann_lattice_graph_rh_v1.json
```
