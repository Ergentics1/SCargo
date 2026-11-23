-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

/-!
# SCargo Lean Compartment: Atomic Fail-Closed Boolean Guards & Correspondence Invariants

This zero-dependency Lean 4.36.0 module provides pure, parameterized, fail-closed
boolean guards for independent verification compartments, separating logic from
dataset literals (no hardcoded target tables or monolithic opaque gates).
-/

namespace SCargoLean

/-- Atomic verdict produced by one independent verification compartment. -/
structure GuardVerdict where
  compartment : String
  passed : Bool
  violationCount : Nat
  deriving Repr, DecidableEq

/-- Generic fail-closed boolean guard: passes if and only if zero violations exist. -/
def guardZeroViolations (compartment : String) (violations : Nat) : GuardVerdict :=
  { compartment := compartment
    passed := violations == 0
    violationCount := violations }

/-- Parameterized axiom allowlist guard (allowlist passed as data, not hardcoded). -/
def guardPermittedAxioms (allowed used : List String) : GuardVerdict :=
  let disallowed := used.filter (fun ax => !allowed.contains ax)
  { compartment := "kernel_axiom_allowlist"
    passed := disallowed.isEmpty
    violationCount := disallowed.length }

/-- Exact Correspondence Principle guard (`Reduction1`, dimensionless mismatch `delta = 0`). -/
def guardCorrespondenceExact (compartment : String) (mismatchCount : Nat) : GuardVerdict :=
  { compartment := compartment
    passed := mismatchCount == 0
    violationCount := mismatchCount }

/-- Bounded Correspondence Principle guard (`Reduction2`, scaled mismatch `delta <= bound`). -/
def guardCorrespondenceBounded (compartment : String) (mismatchScaled boundScaled : Nat) : GuardVerdict :=
  { compartment := compartment
    passed := decide (mismatchScaled ≤ boundScaled)
    violationCount := if mismatchScaled ≤ boundScaled then 0 else mismatchScaled - boundScaled }

/-- Returns every failing compartment identifier without collapsing failures into an opaque bit. -/
def failedCompartments (verdicts : List GuardVerdict) : List String :=
  (verdicts.filter (fun v => !v.passed)).map (·.compartment)

/-- Conjunctive guard summary over an explicit list of independent compartment verdicts. -/
def allCompartmentGuardsHold (verdicts : List GuardVerdict) : Bool :=
  verdicts.all (·.passed)

/-- Soundness of `guardZeroViolations`: passes iff `violations = 0`. -/
theorem guardZeroViolations_passed_iff (c : String) (n : Nat) :
    (guardZeroViolations c n).passed = true ↔ n = 0 := by
  simp [guardZeroViolations]

/-- Soundness of `guardCorrespondenceExact`: exact correspondence passes iff mismatch is zero. -/
theorem guardCorrespondenceExact_passed_iff (c : String) (m : Nat) :
    (guardCorrespondenceExact c m).passed = true ↔ m = 0 := by
  simp [guardCorrespondenceExact]

/-- Soundness of `guardCorrespondenceBounded`: passes iff `mismatchScaled <= boundScaled`. -/
theorem guardCorrespondenceBounded_passed_iff (c : String) (m b : Nat) :
    (guardCorrespondenceBounded c m b).passed = true ↔ m ≤ b := by
  simp [guardCorrespondenceBounded]

/-- Soundness of `allCompartmentGuardsHold`: true iff every independent compartment passed. -/
theorem allCompartmentGuardsHold_iff_forall (vs : List GuardVerdict) :
    allCompartmentGuardsHold vs = true ↔ ∀ v ∈ vs, v.passed = true := by
  simp [allCompartmentGuardsHold]

/-- Non-opacity theorem: no failing compartment IDs exist iff every compartment guard passed. -/
theorem failedCompartments_empty_iff (vs : List GuardVerdict) :
    failedCompartments vs = [] ↔ allCompartmentGuardsHold vs = true := by
  simp [failedCompartments, allCompartmentGuardsHold]

/-- Negative-control theorem: any single failing compartment causes conjunctive rejection. -/
theorem single_failure_rejects (vs : List GuardVerdict) (v : GuardVerdict)
    (hmem : v ∈ vs) (hfail : v.passed = false) :
    allCompartmentGuardsHold vs = false := by
  cases h : allCompartmentGuardsHold vs with
  | false => rfl
  | true =>
    have hall := (allCompartmentGuardsHold_iff_forall vs).mp h v hmem
    rw [hfail] at hall
    contradiction

end SCargoLean
