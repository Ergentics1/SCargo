# Arc 6 Concrete AST-Aware Patch Generator & Dry-Run Unified-Diff Verifier Model (`models/arc6_ast_patch_generator_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v1.0`

> **Separation Rule**: This document defines the **formal Arc 6 AST-aware patch generation & dry-run unified-diff verification model** only. All committed patch records live in [`transfer/patches/arc6_patch_plan_v1.json`](../transfer/patches/arc6_patch_plan_v1.json) as zero-copy, content-addressed SHA-256 receipts (zero verbatim upstream Lean proof bodies per `UP-08`). Literal per-file `.patch` unified diffs are materialized strictly on demand into an out-of-tree `--out-dir` when `--riemannian` is provided, while offline three-language verification executes the full AST rewriters and pure in-memory unified-diff applier over clean-room synthetic fixtures. `Ergentics1/Riemannian` stays **100% untouched** (`0` dirty files).

---

## 1. Governing Correspondence Contract (Arc 5 → Arc 6)

Grounded in live read-only structural analysis of `Ergentics1/Riemannian` (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`), **Arc 6 (`v0.8.0`)** builds concrete deterministic AST-aware patch generators and a zero-dependency in-memory unified-diff verifier covering the three highest-yield, zero-binder-risk zones (`137` files, `~99%` of Arc 5 total yield; `Z-C1A` stays staged in Arc 5):

1. **`Z-C0` Dead-Leaf Deletion (`112` `FlagMeasures` files, `14` `quick_check` shards)**:
   - Verifies exact in-degree `0` from `Main.lean` reachability baseline (`riemannian_51d9b1a280_inventory.json`).
   - Emits canonical `git apply`-compatible delete unified diffs (`deleted file mode 100644`, `--- a/<path>`, `+++ /dev/null`, `@@ -1,N +0,0 @@`), removing `8,060` lines (`468,760` bytes).
2. **`Z-C4` Transitive Redundant `public import` Hub Pruning (`1` file: `EveryCharacterOfLiteratureOfVWin.lean`, `full_rh_build`)**:
   - Performs exact BFS over `Riemannian/src` `public import` edges to compute each direct import's depth $\ge 1$ reachable closure.
   - Prunes every direct `public import M` already reachable through another kept direct `public import`, verifying exact closure invariance ($\operatorname{Reach}(\text{kept}) = \operatorname{Reach}(\text{all})$) and removing `5,054` lines (`508,718` bytes).
3. **`Z-C2` Explicit `@`-Chain Balanced-AST Simplification (`24` `CapelliIdentities` files, `3` `quick_check` shards)**:
   - Live structural survey revealed that `100%` of heavy `@`-lines sit inside `public` declarations (`module` + `@[expose] public section`) and `361 / 391` repeated `@Class.toParent` subtrees capture declaration-local variables (`F, E, K, R, A, l, hl`).
   - Therefore, Arc 6 enforces two mathematically safe, scope-sound transforms:
     - **Primary Per-File Generator (`Z-C2-COMPACT`, `<= 160`-char wrap)**: Parses balanced multi-line `(...)` expressions containing explicit `@`-chains (`>= 2` `@`-markers or `@Class.toParent`/`@inst` head), **fail-closed skipping** every span containing comments (`--`, `/-`), string literals (`"`), backticks (`` ` ``), pattern bars (`|`), or Lean 4 layout-sensitive keywords (`by`, `do`, `match`, `where`, `let`, `have`, `show`, `fun`, `calc`, `conv`, `macro`, `syntax`, `notation`), then collapses internal multi-line indentation whitespace and wraps tokens cleanly at `<= 160` characters with 2-space continuation. This guarantees **100% identical Lean lexer token streams** ($\text{tok}(S_{\text{before}}) = \text{tok}(S_{\text{after}})$), zero `.eq_1` drift, zero typeclass-diamond risk, and `max_line_after <= 280` (reclaiming **`19,052` lines / `673,002` bytes** across `2,567` collapsed spans in all `24/24` files).
     - **Guarded Closed-Subtree `abbrev` CSE (`Z-C2-CLOSED-CSE`)**: Factors repeated balanced `(@...)` subtrees **only** when free local variables $= 0$ (verified fail-closed), proved `rfl`- and `.eq_1`-preserving inside a real Lean `v4.36.0` `module` + `@[expose] public section` fixture ([`CompactCse.lean`](../compartments/lean/SCargoLean/Preflight/CompactCse.lean)).

---

## 2. Pure In-Memory Unified-Diff Soundness & Real Lean `v4.36.0` Properties (`P1`–`P5`)

| Property | Scope | Formal Guarantee |
| :--- | :---: | :--- |
| **`P1` Exact Round-Trip Hunk Application** | All `137` files + Synthetic | Every emitted unified diff is immediately parsed and applied in RAM by a zero-dependency hunk applier: $\operatorname{apply}(\text{before}, \operatorname{diff}(\text{before}, \text{after})) = \text{after}$ byte-for-byte ($\text{SHA-256}$ match). |
| **`P2` Token-Stream Identity & Layout Safety** | `Z-C2-COMPACT` | Every collapsed `(@...)` span is delimiter-balanced and layout-keyword-free; whitespace-tokenized sequences match identically before and after rewrite, and `max_line_after <= 280`. |
| **`P3` Closed-Subtree `abbrev` CSE Visibility (`rfl` + `eq_1`)** | `Z-C2-CLOSED-CSE` | In Lean `v4.36.0` `module` + `@[expose] public section`, hoisting a `0`-free-variable `@`-instance subtree to a public `abbrev` preserves definitional equality (`rfl`) and `.eq_1` equation lemmas (`leanchecker` verified). |
| **`P4` Transitive Import-Closure Invariance** | `Z-C4` | Pruning redundant direct `public import` lines preserves exact transitive reachability ($\operatorname{Reach}(\text{kept}) = \operatorname{Reach}(\text{all})$) and strictly reduces lines and bytes. |
| **`P5` Smooth Correspondence Containment (`Arc 6 → Rung 1`)** | All | `arc6_smoothly_contains_all_prior_rungs`: any passing `Arc6PatchReceipt` smoothly implies passing Arc 5, Arc 4, Rung 3, Rung 2, and Rung 1 receipts ($\Delta_{\text{logic}} = 0$). |

---

## 3. Six Arc 6 Patch Guards (`PG-1`..`PG-6`) & Seven Adversarial Negative Controls (`NEG-P1`..`NEG-P7`)

Standalone Rust (`scargo-patch verify --root . --json`) and Swift (`scargo-patch --root . --json`) verify [`transfer/patches/arc6_patch_plan_v1.json`](../transfer/patches/arc6_patch_plan_v1.json) and execute the full offline synthetic AST + unified-diff round-trip suite, emitting **byte-identical** canonical JSON receipts ($\Delta_{\text{parity}} = 0$):

| Guard | Formal Requirement |
| :--- | :--- |
| **`PG-1` Provenance, Zone A & `UP-08` Zero-Copy** | Exact baseline commit (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`), `target_repo_mutation_allowed = false`, zero Zone A paths across all `137` patch entries, and zero verbatim upstream proof-body markers in `arc6_patch_plan_v1.json`. |
| **`PG-2` Exact `137`-File Bijection & SHA-256 Receipt Integrity** | Patch entries match the exact disjoint union of `Z-C0` (`112`), `Z-C2` (`24`), and `Z-C4` (`1`) paths from `arc5_preflight_bundles_v1.json` 1:1, with every recomputed `entry_sha256` and per-zone total matching identically. |
| **`PG-3` Strict Pareto Mass Reduction & Round-Trip Certificates** | Every entry satisfies `lines_after < lines_before`, `bytes_after < bytes_before`, `hunk_count >= 1`, `roundtrip_verified == true`, `invariant_verified == true`, and `max_line_after <= 280` for all `Z-C2` files. |
| **`PG-4` Offline Synthetic Unified-Diff & AST Round-Trip Suite** | Executes all 4 concrete generators (`Z-C0` delete, `Z-C2-COMPACT` `<= 160` wrap, `Z-C2-CLOSED-CSE` `0`-free-var hoist, `Z-C4` transitive import prune), emits real unified diffs, parses and applies them in RAM, verifies byte-exact SHA-256 round-trip, token identity, and closure invariance, producing deterministic `synthetic_patch_suite_sha256`. |
| **`PG-5` Lean `v4.36.0` `module` Pre-Flight Contract Alignment** | Confirms all 5 clean-room Lean `v4.36.0` `module` files (`Leaf`, `Mid`, `WrapAlias`, `HubPruned`, `CompactCse`) exist under `compartments/lean/SCargoLean/Preflight/`, declare `module` + `@[expose] public section`, and contain zero `sorry`/`native_decide`. |
| **`PG-6` Seven Adversarial Negative Controls Fail Closed** | Rejects all 7 poisoned inputs: `NEG-P1` corrupted unified-diff context mismatch, `NEG-P2` layout-keyword (`by`/`let`/`match`) span mutation attempt, `NEG-P3` free-variable capture in `abbrev` CSE, `NEG-P4` non-redundant `Z-C4` import drop, `NEG-P5` Zone A patch target (`src/Main.lean`), `NEG-P6` `UP-08` verbatim proof leak, and `NEG-P7` non-Pareto byte-inflating rewrite. |
