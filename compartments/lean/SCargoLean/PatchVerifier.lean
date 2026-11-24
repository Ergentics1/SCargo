-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec
import SCargoLean.TransferAirlock
import SCargoLean.HighMassCensus
import SCargoLean.PreflightHarness
import SCargoLean.Preflight.CompactCse

/-!
# SCargo Lean Compartment: Arc 6 Concrete AST Patch Generator & Unified-Diff Verifier

Pure-kernel Lean 4.36.0 formalization of:
1. Unified-diff hunk line conservation (`before - removed + added = after`) and strict Pareto line reduction.
2. Strict layout-free `Z-C2-COMPACT` span guard (`hasLayoutKeyword -> collapse disallowed`) and `<= 160` wrap line cap.
3. Strictly closed-subtree (`freeVarCount == 0`) `Z-C2-CLOSED-CSE` `abbrev` hoisting guard.
4. `Z-C4` transitive import-closure invariance under redundant `public import` pruning.
5. Real Lean 4.36 `module` elaboration witness (`CompactCse`) combining `rfl` and `.eq_1` proofs.
6. Correspondence Principle theorem proving Arc 6 smoothly contains Arc 5, Arc 4, Rung 3, Rung 2, and Rung 1 (`delta_logic = 0`).
-/

namespace SCargoLean.PatchVerifier

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock
open SCargoLean.HighMassCensus
open SCargoLean.Preflight
open SCargoLean.PreflightHarness

/-- Unified-diff hunk accounting record for a single file transform. -/
structure DiffHunkSummary where
  linesBefore : Nat
  linesRemoved : Nat
  linesAdded : Nat
  bytesBefore : Nat
  bytesAfter : Nat
  roundtripMatched : Bool
  deriving Repr, DecidableEq

/-- Resulting line count after applying a valid unified diff (`linesRemoved <= linesBefore`). -/
def linesAfterOf (h : DiffHunkSummary) : Nat :=
  h.linesBefore - h.linesRemoved + h.linesAdded

/-- Strict Pareto & round-trip acceptance guard for a unified diff. -/
def diffHunkParetoSafe (h : DiffHunkSummary) : Bool :=
  decide (h.linesRemoved ≤ h.linesBefore) &&
  decide (h.linesAdded < h.linesRemoved) &&
  decide (h.bytesAfter < h.bytesBefore) &&
  h.roundtripMatched

/-- Soundness (`P1`): any `diffHunkParetoSafe` unified diff strictly reduces file line count. -/
theorem diff_hunk_pareto_strict_line_reduction (h : DiffHunkSummary)
    (hs : diffHunkParetoSafe h = true) :
    linesAfterOf h < h.linesBefore ∧ h.bytesAfter < h.bytesBefore ∧ h.roundtripMatched = true := by
  simp [diffHunkParetoSafe, Bool.and_eq_true] at hs
  unfold linesAfterOf
  exact ⟨by omega, hs.1.2, hs.2⟩

/-- Guard predicate for `Z-C2-COMPACT` layout-free balanced S-expression collapse. -/
structure AtSpanFeatures where
  delimitersBalanced : Bool
  hasNewline : Bool
  hasTargetAtHead : Bool
  hasCommentOrString : Bool
  hasLayoutKeyword : Bool
  deriving Repr, DecidableEq

def z2CompactSpanEligible (f : AtSpanFeatures) : Bool :=
  f.delimitersBalanced &&
  f.hasNewline &&
  f.hasTargetAtHead &&
  !f.hasCommentOrString &&
  !f.hasLayoutKeyword

/-- Soundness (`P2`): any span containing a Lean 4 layout keyword (`by`/`do`/`match`/`let`/...) is NEVER collapsed. -/
theorem z2_compact_skips_layout_keyword_span (f : AtSpanFeatures) (hl : f.hasLayoutKeyword = true) :
    z2CompactSpanEligible f = false := by
  simp [z2CompactSpanEligible, hl]

/-- Soundness (`P2`): any span with comments/strings or unbalanced delimiters is NEVER collapsed. -/
theorem z2_compact_skips_comment_or_unbalanced (f : AtSpanFeatures)
    (h : f.delimitersBalanced = false ∨ f.hasCommentOrString = true) :
    z2CompactSpanEligible f = false := by
  rcases h with hb | hc
  · simp [z2CompactSpanEligible, hb]
  · simp [z2CompactSpanEligible, hc]

/-- Guard predicate for `Z-C2-CLOSED-CSE` `abbrev` hoisting (`0` free local variables required). -/
def z2ClosedCseSafe (freeVarCount occurrences spanBytes : Nat) : Bool :=
  decide (freeVarCount == 0) && decide (occurrences ≥ 2) && decide (spanBytes ≥ 80)

/-- Soundness (`P3`): any subtree capturing `>= 1` local variable (`F`, `K`, `l`, etc.) is rejected fail-closed. -/
theorem z2_closed_cse_rejects_free_vars (fv occ bytes : Nat) (h : fv > 0) :
    z2ClosedCseSafe fv occ bytes = false := by
  unfold z2ClosedCseSafe
  have hne : fv ≠ 0 := by omega
  simp [hne]

/-- Real Lean 4.36 `module` theorem combining `P2` (`z2Wrapped160`) and `P3` (`z2ClosedCse`) `rfl` + `.eq_1` witnesses. -/
theorem preflight_compact_and_closed_cse_sound (a b c : Nat) :
    (z2MultilineDump = z2Wrapped160) ∧
    (z2MultilineDump = z2ClosedCse) ∧
    (z2MultilineDump a b c = a * b + c) :=
  ⟨z2_compact_defeq_rfl, z2_closed_cse_defeq_rfl, z2_closed_cse_eq1_preserved a b c⟩

/-- `Z-C4` import-closure predicate: pruning `pruned` is safe iff every pruned import belongs to `closureOfKept`. -/
def z4PruneClosureSafe (kept pruned closureOfKept : List String) : Bool :=
  !pruned.isEmpty &&
  pruned.all (fun m => closureOfKept.contains m && !kept.contains m)

/-- Soundness (`P4`): if a module is not in `closureOfKept`, pruning it fails closed. -/
theorem z4_prune_rejects_uncovered_import (kept closureOfKept : List String) (m : String)
    (hnot : closureOfKept.contains m = false) :
    z4PruneClosureSafe kept [m] closureOfKept = false := by
  have hnm : m ∉ closureOfKept := by simpa using hnot
  simp [z4PruneClosureSafe, hnm]

/-- Arc 6 Patch Plan Receipt embedding Arc 5 (and transitively Arc 4, Rung 3, Rung 2, Rung 1). -/
structure Arc6PatchReceipt where
  arc5 : Arc5PreflightReceipt
  totalPatchedFiles : Nat
  expectedPatchedFiles : Nat
  allRoundtripsVerified : Bool
  allInvariantsVerified : Bool
  allParetoStrict : Bool
  z2MaxLineWithinBound : Bool
  syntheticPatchSuiteValid : Bool
  leanCompactCseElaborated : Bool
  negativeControlsRejected : Nat
  requiredNegativeControls : Nat
  deriving Repr, DecidableEq

def arc6AllPass (r : Arc6PatchReceipt) : Bool :=
  arc5AllPass r.arc5 &&
  decide (r.totalPatchedFiles == r.expectedPatchedFiles) &&
  r.allRoundtripsVerified &&
  r.allInvariantsVerified &&
  r.allParetoStrict &&
  r.z2MaxLineWithinBound &&
  r.syntheticPatchSuiteValid &&
  r.leanCompactCseElaborated &&
  decide (r.negativeControlsRejected ≥ r.requiredNegativeControls)

/-- Correspondence Principle (`P5`, Rung 1 -> ... -> Arc 5 -> Arc 6): smooth containment (`delta_logic = 0`). -/
theorem arc6_smoothly_contains_all_prior_rungs (r : Arc6PatchReceipt)
    (h : arc6AllPass r = true) :
    arc5AllPass r.arc5 = true ∧
    arc4AllPass r.arc5.arc4 = true ∧
    rung3AllPass r.arc5.arc4.rung3 = true ∧
    rung2AllPass r.arc5.arc4.rung3.rung2 = true ∧
    suiteAllPass r.arc5.arc4.rung3.rung2.rung1Witnesses = true := by
  simp [arc6AllPass, Bool.and_eq_true] at h
  have ha5 : arc5AllPass r.arc5 = true := h.1.1.1.1.1.1.1.1
  have hprior := arc5_smoothly_contains_all_prior_rungs r.arc5 ha5
  exact ⟨ha5, hprior.1, hprior.2.1, hprior.2.2.1, hprior.2.2.2⟩

end SCargoLean.PatchVerifier
