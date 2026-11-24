# Arc 7 G4–G5 CI Receipt Ingestor, Airlock Rehearsal Harness & Empirical Publication Model (`models/arc7_g4_g5_rehearsal_and_publication_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v1.0`

> **Separation Rule**: This document defines the **formal Arc 7 G4–G5 CI receipt ingestion, airlock rehearsal, and publication-consistency model** only. All declarative rehearsal records live in [`transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json`](../transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json) (zero copied upstream Lean proof bodies per `UP-08`), pure presentation metadata for Paper 002 lives in [`data/sources/paper_002_presentation_v1.json`](../data/sources/paper_002_presentation_v1.json) (zero baked empirical numerals per `AUD-07`), and `Ergentics1/Riemannian` stays **100% untouched** (`0` dirty files).

---

## 1. Upstream CI Controller Discovery (`scripts/quick-check.py:80` & `scripts/ci-build.py`)

Direct read-only inspection of `Ergentics1/Riemannian` (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`) establishes three hard upstream CI invariants that govern any future G4–G5 airlock crossing:

1. **Deletion Deferral Rule (`scripts/quick-check.py:80`)**: The small-runner `quick-check` controller checks `not (candidate/name).is_file()` for every changed `.lean` path and immediately defers PRs containing deleted files (`deleted/unsafe source requires full build`). Consequently:
   - **`Z-C2` (`SHARD-ZC2-01..03`, 24 files, in-place edits, `8` roots/shard, `8`–`12` closure modules `<= 2,000`)** are **genuinely `quick-check`-eligible** for fast G4 changed-module diagnostics (`−19,052` lines / `−673,002` bytes).
   - **`Z-C0` (`112` dead-leaf deletions)** and **`Z-C4` (`EveryCharacterOfLiteratureOfVWin.lean`, `127,440` closure modules `> 2,000`)** **must route to `full_rh_build`**.
2. **Diagnostic vs. Release Separation (`scripts/QUICK-CHECKS.md:7`)**: A `quick-check` pass (`scope = "changed-modules-only"`, `full_build = false`, `status = "changed_roots_pass"`) is strictly a **G4 changed-module diagnostic** and can **never** attest G5 release readiness.
3. **G5 Release Attestation Requirements (`comparator.json`, `export-targets.txt`, `scripts/ci-build.py`, `scripts/cache-baselines.json`)**:
   - Full `ci-build.py` `receipt.json` (`schema = 1`, `toolchain = "leanprover/lean4:v4.36.0"`, `build_exit_code = 0`, exact Zone A `lakefile_sha256` and `manifest_sha256`, valid 64-hex `map_sha256`, `module_manifest_sha256`, and `input_fingerprint`).
   - Exact five `Challenge.lean` theorem exports (`riemannHypothesis`, `riemannZeta_eq_zero_re`, `LFunction_ne_zero_of_half_lt_re`, `LFunction_eq_zero_re`, `LFunction_eq_zero_re_of_isPrimitive`).
   - Every theorem's `#print axioms` footprint strictly a subset of `{"propext", "Quot.sound", "Classical.choice"}`.
   - Zero exit code from **all three** kernel verifiers: Lean kernel, `leanchecker-paranoid`, and `nanoda_bin`.
   - Exact pinned Zone A SHA-256 digests (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`):
     - `lakefile.toml`: `e12dd96eb155851de5107571dbfc959e5d9b230ead90331b4778b55b048590bb`
     - `lake-manifest.json`: `ee003c5c7a9b2b2a82a142b6633916661c07117199dd143d94d1af63910237df`
     - `comparator.json`: `8ea890e6ccda9cf3983ada343af18a41d12542036875a3936e7925ed5b1582ff`
     - `export-targets.txt`: `9eeb2e5e55be4a78f6e983fc950dba915b45ad8aeb7a02a32341927a89e05e8`
     - `lean-toolchain`: `582a63f8f9c5128067b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9`

---

## 2. Anti-Theater Provenance Separation (`PRIN-06`)

To guarantee that an offline rehearsal can **never** masquerade as a remote CI pass:
- Every rehearsal artifact committed inside `SCargo` sets `"rehearsal_mode": true`, `"remote_ci_attestation": false`, and `"target_repo_mutation_allowed": false`.
- The Rust `scargo-rehearsal ingest` CLI separately ingests and validates live remote CI JSON receipts (`--quick-check`, `--ci-build`, `--comparator`) once an airlock crossing executes on a dedicated `Ergentics1/Riemannian` feature branch.

---

## 3. Six Rehearsal Guards (`RG-1`..`RG-6`) & Eight Adversarial Negative Controls (`NEG-R1`..`NEG-R8`)

Standalone Rust (`scargo-rehearsal verify --root . --json`) and Swift (`scargo-rehearsal --root . --json`) emit **byte-identical** canonical JSON receipts ($\Delta_{\text{parity}} = 0$):

| Guard | Formal Requirement |
| :--- | :--- |
| **`RG-1` Zone A Pins, Provenance & `UP-08` Cleanliness** | Exact baseline commit (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`), all 5 pinned Zone A file SHA-256 digests match, `target_repo_mutation_allowed == false`, and zero verbatim upstream proof-body markers appear in the rehearsal JSON. |
| **`RG-2` `quick-check.py` G4 Diagnostic Soundness** | All 3 `Z-C2` shards (`SHARD-ZC2-01..03`) satisfy `scope == "changed-modules-only"`, `full_build == false`, `1 <= targets <= 8`, `ancestor_modules <= 2000`, `has_deleted_files == false`, `exit_code == 0`, `status == "changed_roots_pass"`; all `Z-C0` deletion shards (`14`) and `Z-C4` hub (`1`) explicitly route to `full_rh_build`. |
| **`RG-3` Full `ci-build.py` G4 Receipt Integrity** | Rehearsed full-runner `receipt.json` satisfies `schema == 1`, `toolchain == "leanprover/lean4:v4.36.0"`, exact pinned `lakefile_sha256` and `manifest_sha256`, `build_exit_code == 0`, valid 64-hex `map_sha256` / `module_manifest_sha256` / `input_fingerprint`, and exact recomputed `entry_sha256`. |
| **`RG-4` G5 Comparator, Dual-Kernel & 3-Axiom Soundness** | `challenge_module == "Challenge"`, `solution_module == "Main"`, exact 5 `Challenge.lean` theorem names, every theorem's axioms `⊆ {"propext", "Quot.sound", "Classical.choice"}`, `lean_kernel_exit == 0`, `leanchecker_paranoid_exit == 0`, `nanoda_exit == 0`, pinned `challenge_export_sha256`, valid 64-hex `solution_export_sha256`. |
| **`RG-5` Arc 6 Dataset Binding & Anti-Theater Honesty** | Exact linkage to `arc6_patch_plan_v1.json` (`137` files, `32,166` saved lines, `1,650,480` saved bytes, `z2_max_line_after == 280`) and strict rehearsal honesty (`rehearsal_mode == true && remote_ci_attestation == false`). |
| **`RG-6` Eight Adversarial Negative Controls Fail Closed** | Rejects all 8 poisoned inputs: `NEG-R1` (`quick-check` claiming G5 release), `NEG-R2` (deleted file routed to `quick-check`), `NEG-R3` (forbidden axiom `Lean.ofReduceBool`/`sorryAx`), `NEG-R4` (`nanoda_bin` non-zero exit), `NEG-R5` (`lake-manifest.json` Zone A drift), `NEG-R6` (missing required theorem), `NEG-R7` (stale `base_head` ICD retest trigger), and `NEG-R8` (rehearsal spoofing `remote_ci_attestation: true`). |

---

## 4. Empirical Publication & Charting Consistency Contract (`AUD-07`)

Both Working Paper 001 (`v2.1` addendum) and Working Paper 002 (`002-clean-room-ast-reduction-and-g4-g5-rehearsal`) share one unified palette, typography stack (`DejaVu Sans` / `DejaVu Serif` / `DejaVu Sans Mono`), standardized vocabulary (`data/sources/standard_vocabulary_v1.json` `v1.1.0`), and strict `AUD-07` figure-rendering contract:
- Zero hardcoded empirical counts or commit SHAs inside `render_figures.py` or `paper_002_presentation_v1.json`.
- Five atomic fail-closed pre-render guards with explicit healing diagnostics.
- Deterministic SHA-256 `figures_manifest.json` receipt + full adversarial & metamorphic test suite (`test_render_figures.py`).
