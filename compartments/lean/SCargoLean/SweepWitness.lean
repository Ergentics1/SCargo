-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract

/-!
# SCargo Lean Compartment: Rung 1 13-Witness Contract, Blind-Spot Proofs & Seam Soundness

Zero-dependency pure-kernel formalization of:
1. The 13 independent Proof-Carrying Compartment Witnesses (anti-monolith contract).
2. Exact integer Sylvester leading-principal-minor SPD soundness (DEF-RTINV).
3. Exact scaled-integer cancellation and aggregate conservation guards (DEF-FP, DEF-RTINV).
4. Distribution-free calibration guard soundness (DEF-CAL).
5. Typed P -> D CertifiedEstimate seam admission and D -> P replay exactness (DEF-SEAM).
6. Stratified RCT-R1 promotion rule soundness.
-/

namespace SCargoLean.SweepWitness

open SCargoLean

/-- All 13 independent Rung 1 verification compartment witnesses. -/
inductive WitnessId where
  | w_compiler
  | w_suppression
  | w_backdoor
  | w_confinement
  | w_deps
  | w_topology
  | w_parity
  | w_kernel
  | w_correspondence
  | w_fp_determinism
  | w_rt_invariants
  | w_prob_calibration
  | w_seam_integrity
  deriving Repr, DecidableEq

def WitnessId.asString : WitnessId → String
  | .w_compiler => "w_compiler"
  | .w_suppression => "w_suppression"
  | .w_backdoor => "w_backdoor"
  | .w_confinement => "w_confinement"
  | .w_deps => "w_deps"
  | .w_topology => "w_topology"
  | .w_parity => "w_parity"
  | .w_kernel => "w_kernel"
  | .w_correspondence => "w_correspondence"
  | .w_fp_determinism => "w_fp_determinism"
  | .w_rt_invariants => "w_rt_invariants"
  | .w_prob_calibration => "w_prob_calibration"
  | .w_seam_integrity => "w_seam_integrity"

def allWitnessIds : List WitnessId :=
  [ .w_compiler, .w_suppression, .w_backdoor, .w_confinement,
    .w_deps, .w_topology, .w_parity, .w_kernel, .w_correspondence,
    .w_fp_determinism, .w_rt_invariants, .w_prob_calibration, .w_seam_integrity ]

theorem allWitnessIds_length : allWitnessIds.length = 13 := rfl

/-- Proof-Carrying Compartment Witness receipt (non-monolithic, content-addressed). -/
structure CompartmentWitness where
  witnessId : WitnessId
  policyDigestPresent : Bool
  inputDigestsPresent : Bool
  replayCmdPresent : Bool
  violationCount : Nat
  deriving Repr, DecidableEq

/-- A witness passes iff provenance digests, replay command, and zero violations all hold. -/
def witnessPassed (w : CompartmentWitness) : Bool :=
  w.policyDigestPresent && w.inputDigestsPresent && w.replayCmdPresent && (w.violationCount == 0)

def toGuardVerdict (w : CompartmentWitness) : GuardVerdict :=
  let provenanceMissing :=
    (if w.policyDigestPresent then 0 else 1) +
    (if w.inputDigestsPresent then 0 else 1) +
    (if w.replayCmdPresent then 0 else 1)
  { compartment := w.witnessId.asString
    passed := witnessPassed w
    violationCount := w.violationCount + provenanceMissing }

/-- Anti-monolith theorem: omitting policy digest, input digests, or replay command always fails closed. -/
theorem witness_requires_full_provenance (w : CompartmentWitness) :
    witnessPassed w = true ↔
      w.policyDigestPresent = true ∧
      w.inputDigestsPresent = true ∧
      w.replayCmdPresent = true ∧
      w.violationCount = 0 := by
  simp [witnessPassed, Bool.and_eq_true, and_assoc]

theorem monolithic_missing_provenance_rejected (w : CompartmentWitness)
    (h : w.policyDigestPresent = false ∨ w.inputDigestsPresent = false ∨ w.replayCmdPresent = false) :
    witnessPassed w = false := by
  rcases h with hp | hi | hr
  · simp [witnessPassed, hp]
  · simp [witnessPassed, hi]
  · simp [witnessPassed, hr]

/-- Checks that every required witness ID appears in the suite and passes independently. -/
def suiteCoversAll13 (ws : List CompartmentWitness) : Bool :=
  allWitnessIds.all (fun wid => ws.any (fun w => w.witnessId == wid))

def suiteAllPass (ws : List CompartmentWitness) : Bool :=
  suiteCoversAll13 ws && ws.all witnessPassed

def failedWitnessIds (ws : List CompartmentWitness) : List WitnessId :=
  (ws.filter (fun w => !witnessPassed w)).map (·.witnessId)

theorem suiteAllPass_rejects_any_failing_witness (ws : List CompartmentWitness)
    (w : CompartmentWitness) (hmem : w ∈ ws) (hfail : witnessPassed w = false) :
    suiteAllPass ws = false := by
  cases h : suiteAllPass ws with
  | false => rfl
  | true =>
    simp [suiteAllPass, Bool.and_eq_true] at h
    have hpass : witnessPassed w = true := h.2 w hmem
    rw [hfail] at hpass
    contradiction

-- =============================================================================
-- 2. Exact Integer Sylvester Leading-Principal-Minor SPD Soundness (DEF-RTINV)
-- =============================================================================

/-- Exact 3x3 integer matrix for kernel-checked Sylvester SPD correspondence. -/
structure Mat3Int where
  a11 : Int
  a12 : Int
  a13 : Int
  a21 : Int
  a22 : Int
  a23 : Int
  a31 : Int
  a32 : Int
  a33 : Int
  deriving Repr, DecidableEq

def isSymmetricMat3 (m : Mat3Int) : Bool :=
  (m.a12 == m.a21) && (m.a13 == m.a31) && (m.a23 == m.a32)

def allDiagonalsPositiveMat3 (m : Mat3Int) : Bool :=
  decide (m.a11 > 0) && decide (m.a22 > 0) && decide (m.a33 > 0)

def minor1 (m : Mat3Int) : Int := m.a11

def minor2 (m : Mat3Int) : Int := m.a11 * m.a22 - m.a12 * m.a21

def minor3 (m : Mat3Int) : Int :=
  m.a11 * (m.a22 * m.a33 - m.a23 * m.a32) -
  m.a12 * (m.a21 * m.a33 - m.a23 * m.a31) +
  m.a13 * (m.a21 * m.a32 - m.a22 * m.a31)

def guardSylvesterSPD3 (m : Mat3Int) : GuardVerdict :=
  let vSym := if isSymmetricMat3 m then 0 else 1
  let vM1 := if decide (minor1 m > 0) then 0 else 1
  let vM2 := if decide (minor2 m > 0) then 0 else 1
  let vM3 := if decide (minor3 m > 0) then 0 else 1
  guardZeroViolations "w_rt_invariants_sylvester_spd" (vSym + vM1 + vM2 + vM3)

theorem sylvester_spd3_sound (m : Mat3Int) :
    (guardSylvesterSPD3 m).passed = true ↔
      isSymmetricMat3 m = true ∧ minor1 m > 0 ∧ minor2 m > 0 ∧ minor3 m > 0 := by
  unfold guardSylvesterSPD3 guardZeroViolations
  simp only [beq_iff_eq]
  by_cases hs : isSymmetricMat3 m = true <;>
  by_cases h1 : minor1 m > 0 <;>
  by_cases h2 : minor2 m > 0 <;>
  by_cases h3 : minor3 m > 0 <;>
  simp [hs, h1, h2, h3]

/-- Canonical clean 3x3 scaled integer SPD matrix from data/fixtures/rung1_negative_controls_v1.json. -/
def cleanSpdMat3 : Mat3Int :=
  { a11 := 16, a12 := 4, a13 := 2,
    a21 := 4,  a22 := 12, a23 := 1,
    a31 := 2,  a32 := 1,  a33 := 8 }

/-- Canonical poisoned indefinite matrix with positive diagonals (diag = [1, 1, 1], minor2 = -3). -/
def poisonSpdMat3 : Mat3Int :=
  { a11 := 1, a12 := 2, a13 := 0,
    a21 := 2, a22 := 1, a23 := 0,
    a31 := 0, a32 := 0, a33 := 1 }

theorem clean_spd_matrix_certified :
    isSymmetricMat3 cleanSpdMat3 = true ∧
    minor1 cleanSpdMat3 = 16 ∧
    minor2 cleanSpdMat3 = 176 ∧
    minor3 cleanSpdMat3 = 1360 ∧
    (guardSylvesterSPD3 cleanSpdMat3).passed = true := by
  decide

theorem positive_diag_insufficient_witness :
    isSymmetricMat3 poisonSpdMat3 = true ∧
    allDiagonalsPositiveMat3 poisonSpdMat3 = true ∧
    minor2 poisonSpdMat3 = -3 ∧
    (guardSylvesterSPD3 poisonSpdMat3).passed = false := by
  decide

-- =============================================================================
-- 3. Scaled-Integer Cancellation & Aggregate Conservation Guards (DEF-FP / DEF-RTINV)
-- =============================================================================

/-- Fail-closed guard for order-permutation spread and Higham summation condition number. -/
def guardScaledCancellation
    (spreadScaled highamBoundScaled condScaled maxCondScaled : Nat) : GuardVerdict :=
  let vSpread := if decide (spreadScaled ≤ highamBoundScaled) then 0 else 1
  let vCond := if decide (condScaled ≤ maxCondScaled) then 0 else 1
  guardZeroViolations "w_fp_determinism" (vSpread + vCond)

theorem guardScaledCancellation_sound
    (spread highamBound cond maxCond : Nat) :
    (guardScaledCancellation spread highamBound cond maxCond).passed = true ↔
      spread ≤ highamBound ∧ cond ≤ maxCond := by
  unfold guardScaledCancellation guardZeroViolations
  simp only [beq_iff_eq]
  by_cases h1 : spread ≤ highamBound <;> by_cases h2 : cond ≤ maxCond <;> simp [h1, h2]

/-- Fail-closed guard requiring both per-cell bounds and global aggregate conservation cap. -/
def guardScaledConservation
    (cellViolations l1Scaled capScaled : Nat) : GuardVerdict :=
  let vCap := if decide (l1Scaled ≤ capScaled) then 0 else 1
  guardZeroViolations "w_rt_invariants_conservation" (cellViolations + vCap)

theorem cell_pass_aggregate_breach_rejected (l1Scaled capScaled : Nat)
    (hbreach : l1Scaled > capScaled) :
    (guardScaledConservation 0 l1Scaled capScaled).passed = false := by
  unfold guardScaledConservation guardZeroViolations
  have hnot : ¬ (l1Scaled ≤ capScaled) := Nat.not_le_of_gt hbreach
  simp [hnot]

-- =============================================================================
-- 4. Distribution-Free Calibration Guard Soundness (DEF-CAL)
-- =============================================================================

structure CalibrationMetricsScaled where
  sampleCount : Nat
  minSamples : Nat
  dkwStatScaled : Nat
  dkwBoundScaled : Nat
  crpsRatioScaled : Nat
  maxCrpsRatioScaled : Nat
  brierScaled : Nat
  maxBrierScaled : Nat
  coverageViolations : Nat
  oodMahalanobisScaled : Nat
  maxOodScaled : Nat
  deriving Repr, DecidableEq

def guardScaledCalibration (m : CalibrationMetricsScaled) : GuardVerdict :=
  let vN := if decide (m.sampleCount ≥ m.minSamples) then 0 else 1
  let vDkw := if decide (m.dkwStatScaled ≤ m.dkwBoundScaled) then 0 else 1
  let vCrps := if decide (m.crpsRatioScaled ≤ m.maxCrpsRatioScaled) then 0 else 1
  let vBrier := if decide (m.brierScaled ≤ m.maxBrierScaled) then 0 else 1
  let vOod := if decide (m.oodMahalanobisScaled ≤ m.maxOodScaled) then 0 else 1
  guardZeroViolations "w_prob_calibration"
    (vN + vDkw + vCrps + vBrier + m.coverageViolations + vOod)

theorem calibration_guard_sound (m : CalibrationMetricsScaled) :
    (guardScaledCalibration m).passed = true ↔
      m.sampleCount ≥ m.minSamples ∧
      m.dkwStatScaled ≤ m.dkwBoundScaled ∧
      m.crpsRatioScaled ≤ m.maxCrpsRatioScaled ∧
      m.brierScaled ≤ m.maxBrierScaled ∧
      m.coverageViolations = 0 ∧
      m.oodMahalanobisScaled ≤ m.maxOodScaled := by
  unfold guardScaledCalibration guardZeroViolations
  simp only [beq_iff_eq]
  by_cases h1 : m.sampleCount ≥ m.minSamples <;>
  by_cases h2 : m.dkwStatScaled ≤ m.dkwBoundScaled <;>
  by_cases h3 : m.crpsRatioScaled ≤ m.maxCrpsRatioScaled <;>
  by_cases h4 : m.brierScaled ≤ m.maxBrierScaled <;>
  by_cases h5 : m.oodMahalanobisScaled ≤ m.maxOodScaled <;>
  simp [h1, h2, h3, h4, h5]

-- =============================================================================
-- 5. Typed P -> D CertifiedEstimate Seam & D -> P Keyed Replay (DEF-SEAM)
-- =============================================================================

/-- Raw probabilistic estimator output prior to crossing the P -> D seam. -/
structure RawProbEstimate where
  valueScaled : Int
  calibrated : Bool
  inDomain : Bool
  finiteOk : Bool
  sampleCount : Nat
  minSamples : Nat
  deriving Repr, DecidableEq

/-- Proof-carrying admission token required before any deterministic actuator consumes P output. -/
structure CertifiedEstimate (est : RawProbEstimate) : Type where
  certifiedValueScaled : Int
  h_calibrated : est.calibrated = true
  h_inDomain : est.inDomain = true
  h_finite : est.finiteOk = true
  h_samples : est.sampleCount ≥ est.minSamples

/-- Fail-closed P -> D seam admission function. -/
def admitToDeterministic (est : RawProbEstimate) : Option (CertifiedEstimate est) :=
  if h1 : est.calibrated = true then
    if h2 : est.inDomain = true then
      if h3 : est.finiteOk = true then
        if h4 : est.sampleCount ≥ est.minSamples then
          some { certifiedValueScaled := est.valueScaled,
                 h_calibrated := h1, h_inDomain := h2, h_finite := h3, h_samples := h4 }
        else none
      else none
    else none
  else none

theorem uncalibrated_never_admitted (est : RawProbEstimate) (h : est.calibrated = false) :
    admitToDeterministic est = none := by
  unfold admitToDeterministic
  simp [h]

theorem ood_never_admitted (est : RawProbEstimate) (h : est.inDomain = false) :
    admitToDeterministic est = none := by
  unfold admitToDeterministic
  by_cases h1 : est.calibrated = true <;> simp [h1, h]

theorem nonfinite_never_admitted (est : RawProbEstimate) (h : est.finiteOk = false) :
    admitToDeterministic est = none := by
  unfold admitToDeterministic
  by_cases h1 : est.calibrated = true <;> by_cases h2 : est.inDomain = true <;> simp [h1, h2, h]

theorem undersampled_never_admitted (est : RawProbEstimate) (h : est.sampleCount < est.minSamples) :
    admitToDeterministic est = none := by
  unfold admitToDeterministic
  have hnot : ¬ (est.sampleCount ≥ est.minSamples) := Nat.not_le_of_gt h
  by_cases h1 : est.calibrated = true <;>
  by_cases h2 : est.inDomain = true <;>
  by_cases h3 : est.finiteOk = true <;>
  simp [h1, h2, h3, hnot]

/-- Exact bit-for-bit D -> P keyed replay guard (delta_replay = 0). -/
def guardReplayExact (digestRunA digestRunB : String) : GuardVerdict :=
  guardCorrespondenceExact "w_seam_integrity_replay" (if digestRunA == digestRunB then 0 else 1)

theorem guardReplayExact_sound (a b : String) :
    (guardReplayExact a b).passed = true ↔ a = b := by
  unfold guardReplayExact guardCorrespondenceExact
  by_cases h : a = b <;> simp [h]

-- =============================================================================
-- 6. Stratified RCT-R1 Promotion Decision-Rule Soundness
-- =============================================================================

structure StratumOutcome where
  stratumId : String
  replicates : Nat
  controlKills : Nat
  treatmentKills : Nat
  cleanReplicates : Nat
  treatmentFalsePositives : Nat
  isProbabilistic : Bool
  a12ScaledPer1000 : Nat
  pSignificant : Bool
  deriving Repr, DecidableEq

def stratumPromoted (minReps minA12Scaled : Nat) (s : StratumOutcome) : Bool :=
  decide (s.replicates ≥ minReps) &&
  decide (s.cleanReplicates ≥ minReps) &&
  decide (s.treatmentKills == s.replicates) &&
  decide (s.treatmentKills > s.controlKills) &&
  (if s.isProbabilistic then true else decide (s.treatmentFalsePositives == 0)) &&
  decide (s.a12ScaledPer1000 ≥ minA12Scaled) &&
  s.pSignificant

def guardRctR1Promotion (minReps minA12Scaled : Nat) (strata : List StratumOutcome) : GuardVerdict :=
  let failed := strata.filter (fun s => !stratumPromoted minReps minA12Scaled s)
  let emptyPenalty := if strata.isEmpty then 1 else 0
  guardZeroViolations "rct_r1_promotion" (failed.length + emptyPenalty)

theorem rct_promotion_rejects_any_failing_stratum
    (minReps minA12Scaled : Nat) (strata : List StratumOutcome)
    (s : StratumOutcome) (hmem : s ∈ strata)
    (hfail : stratumPromoted minReps minA12Scaled s = false) :
    (guardRctR1Promotion minReps minA12Scaled strata).passed = false := by
  unfold guardRctR1Promotion guardZeroViolations
  simp only [beq_eq_false_iff_ne, ne_eq, Nat.add_eq_zero_iff, List.length_eq_zero_iff,
    List.filter_eq_nil_iff, Bool.not_eq_true', not_and]
  intro hall
  have htrue : stratumPromoted minReps minA12Scaled s = true := by
    have := hall s hmem
    cases h : stratumPromoted minReps minA12Scaled s with
    | true => rfl
    | false => simp [h] at this
  rw [hfail] at htrue
  contradiction

end SCargoLean.SweepWitness
