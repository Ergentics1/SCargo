-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec

/-!
# SCargo Lean Compartment: Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock

Pure-kernel Lean 4.36.0 formalization of:
1. Zone A protected verification core immutability (`UP-01`, `UP-04`, `UP-05`).
2. Permitted axiom subset enforcement (`UP-02`: `{propext, Quot.sound, Classical.choice}`).
3. Pareto mass-vector strict reduction and single-declaration Strategy B wrapper safety guards.
4. `UP-07` bounded quick-check batch partitioning (`<= 8` roots per batch) with exact flatten conservation.
5. Dead-leaf pruning mass reduction theorem using Rung 2 `mass_lines_conserved`.
6. Correspondence Principle theorem proving Rung 3 smoothly contains Rung 2 and Rung 1 (`delta_logic = 0`).
-/

namespace SCargoLean.TransferAirlock

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec

/-- Zone A immutable protected core paths declared in `transfer_zones_v1.json`. -/
def zoneAPaths : List String :=
  [ "src/Main.lean"
  , "src/Challenge.lean"
  , "src/Statements.lean"
  , "comparator.json"
  , "export-targets.txt"
  , "lean-toolchain"
  , "lakefile.toml"
  , "lake-manifest.json" ]

/-- Permitted axioms declared in `upstream_requirements_v1.json` (`UP-02`). -/
def permittedAxioms : List String :=
  ["propext", "Quot.sound", "Classical.choice"]

/-- Returns true if any path in `paths` overlaps Zone A protected core. -/
def touchesZoneA (paths : List String) : Bool :=
  paths.any (fun p => zoneAPaths.contains p)

/-- Soundness (`AG-1`): any touched path inside Zone A is caught fail-closed. -/
theorem zoneA_immutable_rejects_protected_path (paths : List String) (p : String)
    (hp : p ∈ paths) (hza : zoneAPaths.contains p = true) :
    touchesZoneA paths = true := by
  simp [touchesZoneA]
  exact ⟨p, hp, by simpa using hza⟩

/-- Returns true iff every declared axiom belongs to the permitted 3-axiom set (`UP-02`). -/
def axiomsPermitted (axs : List String) : Bool :=
  axs.all (fun a => permittedAxioms.contains a)

/-- Soundness (`UP-02`): any custom or non-permitted axiom is rejected fail-closed. -/
theorem axioms_subset_rejects_custom_axiom (axs : List String) (a : String)
    (ha : a ∈ axs) (hbad : permittedAxioms.contains a = false) :
    axiomsPermitted axs = false := by
  cases h : axiomsPermitted axs with
  | false => rfl
  | true =>
    simp [axiomsPermitted] at h
    have h1 := h a ha
    have hnot : a ∉ permittedAxioms := by simpa using hbad
    exact absurd h1 hnot

/-- Three-component observable source mass vector `(files, lines, bytes)`. -/
structure MassVector where
  files : Nat
  lines : Nat
  bytes : Nat
  deriving Repr, DecidableEq

/-- Pareto safety-gated mass reduction: no file inflation and strictly fewer lines and bytes. -/
def isParetoReduction (before after : MassVector) : Bool :=
  decide (after.files ≤ before.files) &&
  decide (after.lines < before.lines) &&
  decide (after.bytes < before.bytes)

theorem pareto_reduction_strictly_shrinks_lines_and_bytes (before after : MassVector)
    (h : isParetoReduction before after = true) :
    after.files ≤ before.files ∧ after.lines < before.lines ∧ after.bytes < before.bytes := by
  simp [isParetoReduction, Bool.and_eq_true] at h
  exact ⟨h.1.1, h.1.2, h.2⟩

/-- Strategy B wrapper-collapse eligibility record (`DRYRUN-002` confounder guard). -/
structure WrapperCollapseCandidate where
  declCount : Nat
  pairedImplExists : Bool
  importsSubsetOfImpl : Bool
  touchesCore : Bool
  deriving Repr, DecidableEq

def strategyBEligible (c : WrapperCollapseCandidate) : Bool :=
  (c.declCount == 1) && c.pairedImplExists && c.importsSubsetOfImpl && (!c.touchesCore)

theorem strategyB_rejects_multi_decl (c : WrapperCollapseCandidate) (h : c.declCount ≠ 1) :
    strategyBEligible c = false := by
  simp [strategyBEligible, h]

theorem strategyB_rejects_missing_imports (c : WrapperCollapseCandidate)
    (h : c.importsSubsetOfImpl = false) :
    strategyBEligible c = false := by
  simp [strategyBEligible, h]

/-- Fuel-bounded deterministic batch splitter for `UP-07` quick-check caps. -/
def chunkByFuel {α : Type} (cap : Nat) : Nat → List α → List (List α)
  | 0, [] => []
  | 0, xs => [xs]
  | _ + 1, [] => []
  | fuel + 1, xs =>
    if xs.length ≤ cap then [xs]
    else xs.take cap :: chunkByFuel cap fuel (xs.drop cap)

def splitBatches {α : Type} (cap : Nat) (xs : List α) : List (List α) :=
  chunkByFuel cap xs.length xs

private theorem chunkByFuel_flatten {α : Type} (cap : Nat) :
    ∀ (fuel : Nat) (xs : List α), (chunkByFuel cap fuel xs).flatten = xs
  | 0, [] => by simp [chunkByFuel]
  | 0, x :: xs => by simp [chunkByFuel]
  | _ + 1, [] => by simp [chunkByFuel]
  | fuel + 1, x :: xs => by
    unfold chunkByFuel
    split
    · simp
    · simp [chunkByFuel_flatten cap fuel ((x :: xs).drop cap)]

private theorem chunkByFuel_bound {α : Type} (cap : Nat) (hcap : 1 ≤ cap) :
    ∀ (fuel : Nat) (xs : List α), xs.length ≤ fuel →
      ∀ b ∈ chunkByFuel cap fuel xs, b.length ≤ cap
  | 0, [], _, b, hb => by simp [chunkByFuel] at hb
  | 0, x :: xs, hlen, _, _ => by simp at hlen
  | _ + 1, [], _, b, hb => by simp [chunkByFuel] at hb
  | fuel + 1, x :: xs, hlen, b, hb => by
    unfold chunkByFuel at hb
    split at hb
    · rename_i hle
      simp at hb
      subst hb
      exact hle
    · rename_i hgt
      simp at hb
      rcases hb with rfl | htail
      · simp
        omega
      · have hdrop : ((x :: xs).drop cap).length ≤ fuel := by
          simp only [List.length_drop, List.length_cons] at hlen ⊢
          omega
        exact chunkByFuel_bound cap hcap fuel ((x :: xs).drop cap) hdrop b htail

/-- Exact `UP-07` batching conservation and bound theorem (`cap = 8`). -/
theorem splitBatches_preserves_elements_and_up07_cap {α : Type} (xs : List α) :
    (splitBatches 8 xs).flatten = xs ∧
    ∀ b ∈ splitBatches 8 xs, b.length ≤ 8 := by
  constructor
  · exact chunkByFuel_flatten 8 xs.length xs
  · exact chunkByFuel_bound 8 (by decide) xs.length xs (Nat.le_refl _)

/-- Clean-room Zone C0 dead-leaf pruning operator on a `GroundGraph`. -/
def pruneDeadLeaves (g : GroundGraph) : GroundGraph :=
  let reach := reachableFromRoot g
  { root := g.root
    modules := g.modules.filter (fun m => reach.contains m.name) }

theorem pruneDeadLeaves_totalLines_eq_reachable (g : GroundGraph) :
    totalMassLines (pruneDeadLeaves g) = reachableMassLines g := rfl

theorem pruneDeadLeaves_totalBytes_eq_reachable (g : GroundGraph) :
    totalMassBytes (pruneDeadLeaves g) = reachableMassBytes g := rfl

/-- Dead-leaf pruning strictly reduces total line mass whenever unreachable line mass is positive. -/
theorem pruneDeadLeaves_strictly_reduces_lines (g : GroundGraph) (hdead : 0 < deadMassLines g) :
    totalMassLines (pruneDeadLeaves g) < totalMassLines g := by
  rw [pruneDeadLeaves_totalLines_eq_reachable]
  have hcons := mass_lines_conserved g
  omega

/-- Concrete clean-room verification on the canonical diamond DAG (`Dead` = 50 lines pruned). -/
theorem diamondDag_prune_valid_and_strict_pareto :
    graphValid (pruneDeadLeaves diamondDag) = true ∧
    hasCycle (pruneDeadLeaves diamondDag) = false ∧
    (reachableFromRoot (pruneDeadLeaves diamondDag)).length = 4 ∧
    totalMassLines (pruneDeadLeaves diamondDag) = 100 ∧
    totalMassLines (pruneDeadLeaves diamondDag) < totalMassLines diamondDag := by
  decide

/-- Rung 3 Airlock Receipt embedding Rung 2 (and transitively Rung 1) plus all 5 Airlock Guards. -/
structure Rung3AirlockReceipt where
  rung2 : Rung2Receipt
  baselineShaMatched : Bool
  zoneAClean : Bool
  axiomsClean : Bool
  paretoStrictAllPackages : Bool
  up07BatchesValid : Bool
  negativeControlsRejected : Nat
  requiredNegativeControls : Nat
  targetRepoUntouched : Bool
  deriving Repr, DecidableEq

def rung3AllPass (r : Rung3AirlockReceipt) : Bool :=
  rung2AllPass r.rung2 &&
  r.baselineShaMatched &&
  r.zoneAClean &&
  r.axiomsClean &&
  r.paretoStrictAllPackages &&
  r.up07BatchesValid &&
  decide (r.negativeControlsRejected ≥ r.requiredNegativeControls) &&
  r.targetRepoUntouched

/-- Correspondence Principle (Rung 1 -> Rung 2 -> Rung 3): Rung 3 smoothly contains Rung 2 and Rung 1 (`delta_logic = 0`). -/
theorem rung3_smoothly_contains_rung2_and_rung1 (r : Rung3AirlockReceipt)
    (h : rung3AllPass r = true) :
    rung2AllPass r.rung2 = true ∧ suiteAllPass r.rung2.rung1Witnesses = true := by
  simp [rung3AllPass, Bool.and_eq_true] at h
  have hr2 : rung2AllPass r.rung2 = true := h.1.1.1.1.1.1.1
  exact ⟨hr2, rung2_smoothly_contains_rung1 r.rung2 hr2⟩

end SCargoLean.TransferAirlock
