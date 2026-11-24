# Arc 8 Adaptive Multi-Zone AST Synthesis, Min-Closure Bin-Packing & Paper 002 Publication Model (`models/arc8_adaptive_synthesis_and_sharding_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License) · **Model Revision**: `v1.0`

> **Separation Rule**: This document specifies the **formal Arc 8 adaptive multi-zone AST synthesis, greedy min-closure-union bin-packing, and offline Paper 002 interactive-reader contract** only. All zero-copy content-addressed synthesis receipts live in [`transfer/patches/arc8_adaptive_synth_plan_v1.json`](../transfer/patches/arc8_adaptive_synth_plan_v1.json) (`UP-08`), pure presentation metadata lives in [`data/sources/paper_002_presentation_v1.json`](../data/sources/paper_002_presentation_v1.json) (`AUD-07`), and `Ergentics1/Riemannian` stays **100% untouched** (`0` dirty files).

---

## 1. Five-Zone Adaptive Multi-Strategy AST Dispatch (`Z-C0`–`Z-C4`)

Arc 8 generalizes Arc 6's 3-zone generator (`137` files) into a unified adaptive multi-zone AST synthesis engine (`scargo-synth` in Rust `1.100.0`, `SCargoSynth` in Swift `6.4.3`, and `SCargoLean.AdaptiveSynth` in Lean `v4.36.0`) covering **all five Zone C reduction tracks** while leaving Zone A **100% untouched**:

1. **Zone `Z-C0` (Unreachable Dead Leaves)**: Static in-degree-zero module deletions (`112` `FlagMeasures` files); automatically deferred to `full_rh_build` per `scripts/quick-check.py:80`.
2. **Zone `Z-C1A` (Dual-Mode Forwarding-Wrapper Synthesizer)**:
   - Targets pure single-declaration forwarding wrappers across `CompanionTheory`, `PositivityTheory`, and `RCT-001` whose proof body matches `first | exact @Target | exact Target | (intros; apply Target <;> assumption)`.
   - **Mode `A1-alias`**: When the paired implementation module declares `Target` with exact matching binder-plicity and type signature (zero section `variable` capture), collapses the wrapper to minimal `public import`s (`closure(after) == closure(before)`) plus `alias _root_.X := _root_.FQTarget` (Mathlib-enabled `Riemannian`, preserving `theoremInfo` per `ICD-RIEMANNIAN.md` §2; formally modeled in core Lean `v4.36.0` `module` via `abbrev _root_.X := @_root_.Target` in `WrapperAliasStrict.lean`).
   - **Mode `A2-tight-theorem`**: When binder-plicity differs or ambient section variables are active, retains the exact restated `theorem _root_.X : <sig>` header while stripping transitively redundant `public import`s, empty `namespace ... end ...` stubs, `set_option maxHeartbeats 1000000 in`, and replacing the 3-branch fallback tactic with a clean single-branch proof.
   - **Fail-Closed Rule**: Any multi-declaration file or unresolved target is skipped (`0` speculative rewrites).
3. **Zone `Z-C2` (Expanded Adaptive-Width Balanced-AST Collapse)**:
   - Expands from Arc 6's top `24` files across all `CapelliIdentities` modules containing `≥ 2` `@`-tokens.
   - Adaptively selects wrap width `≤ 160` bounded strictly by `baseline_max_line`, preserving exact whitespace-tokenized stream identity (`tok(before) == tok(after)`), balanced delimiters, and fail-closed layout-keyword/comment/bar exclusion.
4. **Zone `Z-C3` (Acyclic Self-Contained Private-Lemma Cluster Deduplicator)**:
   - Scans exact normalized `private theorem` / `private lemma` duplicate clusters (`≥ 4` lines, multiplicity `≥ 2`).
   - Enforces **strict self-containment** (zero ambient `variable` references, identical namespace/import preamble, balanced delimiters) and **Kahn DAG acyclicity** before synthesizing `C3-Promote` (promoting a single canonical topologically-minimal member's helper and delegating sibling copies in-place with zero new files) or skipping context-entangled clusters cleanly.
5. **Zone `Z-C4` (Multi-Hub Transitive Import-Closure Pruner)**:
   - Generalizes Arc 6's single-file `EveryCharacterOfLiteratureOfVWin.lean` hub pruner to automatically discover and prune non-Zone-A hubs across `ThirdPlaceSeries` and `IntegralStructures` containing `≥ 20` strictly transitively redundant `public import`s while proving exact closure invariance (`closure(retained) == closure(original)`).

---

## 2. Adaptive Min-Closure-Union Bin-Packing Sharder (`UP-07` + `quick-check.py:80`)

Naive alphabetical chunking of up to `8` roots per shard suffers severe closure-cone contamination: a single module with `> 2,000` project ancestors disqualifies all `7` light siblings in its chunk. Arc 8 replaces alphabetical chunking with a deterministic **Greedy Min-Closure-Union Bin-Packer**:

1. Partition synthesized files into `deletion` files (`full_rh_build` per `quick-check.py:80`), `heavy` in-place files (`|A(m)| > 2,000` → `full_rh_build`), and `light` in-place files (`|A(m)| ≤ 2,000`).
2. Sort `light` modules ascending by `(|A(m)|, module_name)`.
3. Seed each shard $S$ with the smallest remaining `light` module; repeatedly add the unassigned `light` candidate $m$ minimizing $|S_{\text{closure}} \cup A(m)|$ subject to $|S| < 8$ and $|S_{\text{closure}} \cup A(m)| \le 2{,}000$.
4. Emit side-by-side **Naive vs. Adaptive** telemetry proving strict monotonicity (`adaptive_quick_check_files >= naive_quick_check_files`).

---

## 3. Seven Adaptive Synthesis Guards (`SG-1`..`SG-7`) & Eight Negative Controls (`NEG-S1`..`NEG-S8`)

Standalone Rust (`scargo-synth verify --root . --json`) and Swift (`scargo-synth --root . --json`) emit **byte-identical** canonical JSON receipts ($\Delta_{\text{parity}} = 0$, completing **septuple `7/7` Rust ↔ Swift parity**):

| Guard | Formal Requirement |
| :--- | :--- |
| **`SG-1` Baseline, Zone A & `UP-08` Cleanliness** | Exact baseline commit (`51d9b1a28026d458aef9c9af3df8b083276e3d2d`), `0` Zone A paths, `target_repo_mutation_allowed == false`, and zero verbatim upstream proof bodies in JSON. |
| **`SG-2` 5-Zone Round-Trip & Pareto Conservation** | All 5 zones (`Z-C0`, `Z-C1A`, `Z-C2`, `Z-C3`, `Z-C4`) present with `100%` pure in-memory unified-diff round-trip verification and exact per-zone/total line & byte conservation (`saved_lines > 0`, `saved_bytes > 0`). |
| **`SG-3` `Z-C1A` Dual-Mode & Closure Soundness** | Every `Z-C1A` entry declares mode (`A1-alias` or `A2-tight-theorem`), resolves `_root_.` target cleanly, preserves transitive import closure, and strictly reduces file mass. |
| **`SG-4` `Z-C2` Adaptive-Width & Token Identity** | Every `Z-C2` entry preserves `tok(before) == tok(after)`, balanced delimiters, layout-keyword exclusion, and `max_line_after <= max(280, baseline_max_line)`. |
| **`SG-5` `Z-C3` Acyclic Private-Lemma Deduplication** | Every synthesized `Z-C3` cluster has multiplicity `≥ 2`, `acyclic_verified == true`, `zero_ambient_var_capture == true`, and strict positive net line reduction. |
| **`SG-6` Adaptive Bin-Packing & `quick-check.py:80` Soundness** | Every `quick_check` shard satisfies `1 <= changed_roots <= 8`, `closure_modules <= 2000`, `has_deleted_files == false`, and `adaptive_quick_check_files >= naive_quick_check_files`. |
| **`SG-7` Eight Adversarial Negative Controls Fail Closed** | Rejects `NEG-S1` (`Z-C1A` binder-plicity mismatch), `NEG-S2` (`Z-C1A` broken import closure), `NEG-S3` (`Z-C2` token drift), `NEG-S4` (`Z-C3` cyclic import injection), `NEG-S5` (`Z-C3` ambient variable capture), `NEG-S6` (bin exceeding `2,000` closure), `NEG-S7` (deletion routed to `quick_check`), and `NEG-S8` (Zone A path injection). |
