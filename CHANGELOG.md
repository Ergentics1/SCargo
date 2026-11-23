# Changelog

All notable changes to SCargo are documented in this file.
This project follows Semantic Versioning.

## [0.1.0] - 2026-11-23

### Added
- Standalone language compartments with strict warnings-as-errors and zero third-party dependencies:
  - **Lean (`v4.36.0`)**: `SCargoLean.Contract` atomic guards and `SCargoLean.RiemLattice` pure-kernel proofs plus `riem_lattice_test` (`lake test`).
  - **Rust (`1.100.0`)**: `scargo-probe`, `scargo-trace`, `scargo-qualify`, and `scargo-riem-lattice`.
  - **Swift (`6.4.3`)**: `SCargoModel`, `RiemLattice`, `scargo-audit`, `scargo-riem-lattice`, guarded default `swiftbuild` runner, and Swift Testing suites.
- Disjoint versioned data vaults (`data/sources/`, `data/manifests/`, `data/audits/`, `data/baselines/`, `data/traces/`, `data/trials/`), including:
  - Primary-source Hugo Riemann catalog (`88` verified entries) and Bernhard vs. Hugo Riemann disambiguation specification.
  - Euler late-1730s root and exact Graph Riemann Hypothesis vault and model for the Neo-Riemannian *Tonnetz* dual.
  - Live self-audit ledger (`AUD-01` through `AUD-07` and `OBS-01`) kept separate from normative policy manifests.
- Paper 001 with guarded dynamic figure renderer, regression test suite, offline HTML reader, and SHA-256 figure manifest.
- Public open-source release files (`LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CITATION.cff`, and automated public-hygiene workflow).
