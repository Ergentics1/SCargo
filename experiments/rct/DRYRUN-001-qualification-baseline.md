# Clean-Room Dry-Run Qualification Report (`DRYRUN-001` & `DRYRUN-002`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)  
**Status**: Completed (Read-Only Clean-Room Simulation — Reference Proof Untouched)  
**Engine**: `scargo-qualify/0.1.0` (`compartments/rust/crates/scargo-qualify`)  
**Immutable Datasets**: [`data/trials/dryrun_001_dead_leaves.json`](../../data/trials/dryrun_001_dead_leaves.json) · [`data/trials/dryrun_002_rct001_wrappers.json`](../../data/trials/dryrun_002_rct001_wrappers.json) · [`data/manifests/upstream_requirements_v1.json`](../../data/manifests/upstream_requirements_v1.json)

---

## 1. Purpose

Before building automated proof-compression machinery or installing local verification toolchains, we ran two zero-mutation clean-room dry runs directly against the untouched verified reference proof (`51d9b1a280`). The objective was twofold:

1. **Validate upstream compliance** against the hard acceptance rules extracted directly from upstream verification and CI configuration (`upstream_requirements_v1.json`, rules `UP-01`–`UP-08`).
2. **Surface hidden structural confounders** on both Tier 1 (unreferenced leaf modules) and Tier 2 (pre-allocated stratified forwarding-wrapper trial, 162 balanced units) before writing any mutating transformation code.

---

## 2. Dry-Run 1: Unreferenced Leaf Modules (`DRYRUN-001`)

| Metric | Measured Value |
|---|---:|
| Unreferenced modules outside the main theorem closure | **112 modules** |
| Subtree concentration | 100% inside one isolated subtree (`FlagMeasures`) |
| Reclaimable source lines | **8,060 lines** |
| Reclaimable source bytes | **468,760 bytes** (468.8 KB) |
| Active modules importing any of the 112 files | **0** |
| Explicit references in `lakefile.toml` | **0** (covered by wildcard library glob) |
| Upstream `lakefile.toml` edit required? | **No** (satisfies `UP-05`) |
| Upstream CI routing (`UP-07`) | Full runner pool (112 deleted files exceed small-runner 8-root quick-check cap) |

**Qualification Verdict**: **PASS (Ready for Machinery & Verification)**. Zero active importers, zero build-config changes required, and 100% compliant with upstream rules `UP-01`–`UP-06`.

---

## 3. Dry-Run 2: Stratified Forwarding-Wrapper Trial (`DRYRUN-002` / `RCT-001`)

Evaluated across the **162 pre-allocated units** (81 Treatment / 81 Control, balanced across mathematical domain and file-length strata, seed `20261122`):

### 3.1 Critical Confounder Caught by the Clean-Room Dry Run
Our initial static template scan (`first | exact @... <;> assumption)`) matched both short single-declaration forwarding wrappers *and* larger multi-declaration proof files that merely append a forwarding theorem at the end.
- **51 of 81 treatment units** (`996 lines` / `96,575 bytes`) are **true single-declaration forwarding wrappers**.
- **30 of 81 treatment units** (`7,479 lines`, ranging from 2 to 39 declarations per file) are **multi-declaration proof files** automatically protected from destructive whole-file replacement by our `decl_count == 1` safety guard.

*Engineering takeaway for machinery design*: Any future automated wrapper rewriter **must** parse declaration boundaries (or verify AST single-declaration status in Lean/Rust) rather than relying on substring pattern matching alone.

### 3.2 Safety, Interface Exposure & Upstream Quick-Check Fit (Treatment Arm, n = 81)

| Qualification Check | Result |
|---|---:|
| Treatment units importing or imported by Protected Verification Core | **0 / 81** (100% clear) |
| Treatment units touching High-Impact Shared Modules (≥ 500 direct users) | **0 / 81** (100% clear) |
| Total direct importers across all 81 treatment units | **202** (max **30** on a single unit) |
| Units fitting upstream small-runner quick-check budget (≤ 8 roots) | **77 / 81 (95.1%)** |

### 3.3 Simulated Compression Strategies (on the 51 Pure Forwarding Wrappers)

| Strategy | Mechanism | Eligible Pure Wrappers | Projected Line Savings | Projected Byte Savings | Files Eliminated | Downstream Edits |
|---|---|---:|---:|---:|---:|---|
| **Strategy A — Minimal In-Place Alias** | Replace duplicated signature + fallback tactic with a concise `alias` preserving public import closure | **46 / 51** (90.2%) | **−478 lines (−48.0%)** | **−64,032 B (−66.3%)** | 0 | **0** |
| **Strategy B — Wrapper Collapse & Importer Rewire** | Append `alias` to paired implementation file, rewrite direct importers, delete wrapper file (only where wrapper public imports are a subset of implementation public imports) | **30 / 51** (58.8%) | **−509 lines (−51.1% of all 51; ~95% of the 30 collapsed files)** | **−47,170 B** | **−30 modules** | Rewire direct importers only (avg ~1.8 files/wrapper) |

The remaining **5 / 51** single-declaration wrappers excluded from Strategy A carry universe parameters or non-standard header structure and will be inspected before enabling them in any automated rewriter.

---

## 4. Readiness Gate for Machinery Construction

Both dry runs completed in under **9 seconds combined** with **8/8 unit tests passing** across `scargo-probe`, `scargo-trace`, and `scargo-qualify`. We now have a verified clean-room baseline and an encoded upstream compliance contract (`UP-01`–`UP-08`) ready to guide whichever compression approach you want to design and prototype next.
