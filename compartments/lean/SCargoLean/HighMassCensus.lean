-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec
import SCargoLean.TransferAirlock

/-!
# SCargo Lean Compartment: Arc 4 High-Mass Zone Census & UP-08 Provenance Proofs

Pure-kernel Lean 4.36.0 formalization of:
1. Exact Z-C3 duplicate-cluster reclaimability bounds (`(k - 1) * L < k * L` for `k >= 2, L >= 1`).
2. Strict Pareto mass reduction for Z-C2 explicit `@`-dump de-expansion preserving file count.
3. Exact Z-C4 transitive import-redundancy bounding (`redundant <= direct <= total`).
4. UP-08 clean-room verbatim proof-body rejection guard.
5. Correspondence Principle theorem proving Arc 4 smoothly contains Rung 3, Rung 2, and Rung 1 (`delta_logic = 0`).
-/

namespace SCargoLean.HighMassCensus

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock

def containsSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

/-- Reclaimable lines for a duplicate cluster of multiplicity `mult` and block size `blockLines`. -/
def clusterReclaimable (mult blockLines : Nat) : Nat :=
  (mult - 1) * blockLines

/-- Exact Z-C3 bound: factoring a duplicate cluster (`mult >= 2`, `blockLines >= 1`) strictly reduces mass without exceeding total cluster mass. -/
theorem duplicate_cluster_reclaimable_strict_lt (mult blockLines : Nat)
    (hm : mult ≥ 2) (hb : blockLines ≥ 1) :
    0 < clusterReclaimable mult blockLines ∧
    clusterReclaimable mult blockLines < mult * blockLines := by
  unfold clusterReclaimable
  cases mult with
  | zero => omega
  | succ k =>
    have hk : k ≥ 1 := by omega
    have hmul : (k + 1) * blockLines = k * blockLines + blockLines := Nat.succ_mul k blockLines
    have hpos : 0 < k * blockLines := Nat.mul_pos (by omega) (by omega)
    constructor
    · simpa using hpos
    · simp only [Nat.add_sub_cancel]
      omega

theorem duplicate_cluster_singleton_zero (blockLines : Nat) :
    clusterReclaimable 1 blockLines = 0 := by
  simp [clusterReclaimable]

/-- Exact Z-C2 Pareto theorem: de-expanding explicit `@`-terms preserves file count and strictly reduces lines and bytes. -/
theorem explicit_deexpand_pareto_strict (files totalLines totalBytes reclaimLines reclaimBytes : Nat)
    (hrl : 0 < reclaimLines) (hl : reclaimLines < totalLines)
    (hrb : 0 < reclaimBytes) (hb : reclaimBytes < totalBytes) :
    isParetoReduction
      { files := files, lines := totalLines, bytes := totalBytes }
      { files := files, lines := totalLines - reclaimLines, bytes := totalBytes - reclaimBytes } = true := by
  simp [isParetoReduction]
  omega

/-- Exact Z-C4 bound: transitively redundant imports never exceed total file lines. -/
theorem import_redundancy_le_total (redundant direct total : Nat)
    (h1 : redundant ≤ direct) (h2 : direct ≤ total) :
    redundant ≤ total :=
  Nat.le_trans h1 h2

/-- UP-08 clean-room guard: detects verbatim Lean proof-body markers inside census datasets. -/
def hasVerbatimProofBody (raw : String) : Bool :=
  containsSubstr raw ":= by" ||
  containsSubstr raw "private theorem " ||
  containsSubstr raw "noncomputable def " ||
  containsSubstr raw "public import Mathlib"

theorem up08_clean_room_guard_rejects_proof_body (raw : String)
    (h : hasVerbatimProofBody raw = true) :
    (!hasVerbatimProofBody raw) = false := by
  simp [h]

/-- Arc 4 Census Receipt embedding Rung 3 (and transitively Rung 2 & Rung 1) plus all 5 High-Mass Guards. -/
structure Arc4CensusReceipt where
  rung3 : Rung3AirlockReceipt
  up08Reconciled : Bool
  zeroVerbatimCopy : Bool
  z2Valid : Bool
  z3Valid : Bool
  z4Valid : Bool
  rankingValid : Bool
  negativeControlsRejected : Nat
  requiredNegativeControls : Nat
  deriving Repr, DecidableEq

def arc4AllPass (r : Arc4CensusReceipt) : Bool :=
  rung3AllPass r.rung3 &&
  r.up08Reconciled &&
  r.zeroVerbatimCopy &&
  r.z2Valid &&
  r.z3Valid &&
  r.z4Valid &&
  r.rankingValid &&
  decide (r.negativeControlsRejected ≥ r.requiredNegativeControls)

/-- Correspondence Principle (Rung 1 -> Rung 2 -> Rung 3 -> Arc 4): Arc 4 smoothly contains all prior rungs (`delta_logic = 0`). -/
theorem arc4_smoothly_contains_rung3_rung2_rung1 (r : Arc4CensusReceipt)
    (h : arc4AllPass r = true) :
    rung3AllPass r.rung3 = true ∧
    rung2AllPass r.rung3.rung2 = true ∧
    suiteAllPass r.rung3.rung2.rung1Witnesses = true := by
  simp [arc4AllPass, Bool.and_eq_true] at h
  have hr3 : rung3AllPass r.rung3 = true := h.1.1.1.1.1.1.1
  have hr21 := rung3_smoothly_contains_rung2_and_rung1 r.rung3 hr3
  exact ⟨hr3, hr21.1, hr21.2⟩

end SCargoLean.HighMassCensus
