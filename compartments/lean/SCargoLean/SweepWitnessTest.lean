-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness

/-!
# SCargo Lean Compartment: Standalone Rung 1 Witness & Blind-Spot Test Driver

Dynamically reads `data/manifests/swe_sweep_policy_v1.json`,
`data/fixtures/rung1_negative_controls_v1.json`, and
`data/trials/rct_r1_config_v1.json`, verifies the 13-witness contract,
21 poisoned fixture IDs, exact integer Sylvester SPD, typed P -> D seam
admission, D -> P replay exactness, and RCT-R1 promotion decision rules.
-/

open SCargoLean
open SCargoLean.SweepWitness

private def containsSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def required21PoisonIds : List String :=
  [ "poison_suppression_rust_allow_dead_code"
  , "poison_suppression_swift_try_optional_and_suppress_flag"
  , "poison_suppression_lean_set_option_linter_false"
  , "poison_backdoor_rust_unsafe_and_build_rs"
  , "poison_backdoor_swift_unchecked_sendable_and_silgen_name"
  , "poison_backdoor_lean_sorry_axiom_native_decide_skipKernelTC"
  , "poison_trojan_source_unicode_bidi_override"
  , "poison_symlink_out_of_tree_escape"
  , "poison_hidden_dependency_unpinned_manifest"
  , "poison_deprecation_warning_unflagged"
  , "poison_parity_drift_injected_off_by_one"
  , "poison_leaker_covert_env_exfil"
  , "poison_monolithic_self_certifying_gate"
  , "poison_correspondence_unbounded_drift"
  , "poison_det_fp_catastrophic_cancellation"
  , "poison_rt_spd_offdiag_indefinite"
  , "poison_rt_nan_state_poisoning"
  , "poison_rt_aggregate_conservation_breach"
  , "poison_prob_naive_gaussian_miscalibrated"
  , "poison_seam_p_to_d_uncalibrated_ood_actuator"
  , "poison_seam_d_to_p_unkeyed_global_prng" ]

private def required14DefectIds : List String :=
  [ "DEF-SUPP", "DEF-BACK", "DEF-HDEP", "DEF-SYML", "DEF-WARN"
  , "DEF-COMP", "DEF-PAR", "DEF-LEAK", "DEF-MONO", "DEF-CORR"
  , "DEF-FP", "DEF-RTINV", "DEF-CAL", "DEF-SEAM" ]

private def verifyRung1Vaults (policyRaw fixturesRaw rctRaw : String) : List GuardVerdict :=
  let all13PresentInPolicy :=
    allWitnessIds.all (fun w => containsSubstr policyRaw s!"\"{w.asString}\"")
  let all14DefectsPresent :=
    required14DefectIds.all (fun d => containsSubstr policyRaw s!"\"{d}\"")
  let all21InPolicyAndFixtures :=
    required21PoisonIds.all (fun f =>
      containsSubstr policyRaw s!"\"{f}\"" && containsSubstr fixturesRaw s!"\"{f}\"")
  let rctConfigOk :=
    containsSubstr rctRaw "\"trial_id\": \"RCT-R1\"" &&
    containsSubstr rctRaw "\"replicates_per_stratum\": 32" &&
    containsSubstr rctRaw "\"STRAT-D-CANCEL\"" &&
    containsSubstr rctRaw "\"STRAT-R-SPD\"" &&
    containsSubstr rctRaw "\"STRAT-R-NAN\"" &&
    containsSubstr rctRaw "\"STRAT-R-CAP\"" &&
    containsSubstr rctRaw "\"STRAT-P-CAL\"" &&
    containsSubstr rctRaw "\"STRAT-SEAM-P2D\"" &&
    containsSubstr rctRaw "\"STRAT-SEAM-D2P\""

  -- Build a clean 13-witness suite and verify completeness.
  let cleanSuite : List CompartmentWitness :=
    allWitnessIds.map (fun wid =>
      { witnessId := wid
        policyDigestPresent := true
        inputDigestsPresent := true
        replayCmdPresent := true
        violationCount := 0 })
  let suiteOk := suiteAllPass cleanSuite && (failedWitnessIds cleanSuite).isEmpty

  -- Clean numeric/SPD/conservation/calibration/seam checks.
  let spdCleanOk := (guardSylvesterSPD3 cleanSpdMat3).passed
  let fpCleanOk := (guardScaledCancellation 2 16 10 1000000).passed
  let capCleanOk := (guardScaledConservation 0 100 100).passed
  let calCleanOk := (guardScaledCalibration
    { sampleCount := 256, minSamples := 200
      dkwStatScaled := 45, dkwBoundScaled := 102
      crpsRatioScaled := 1020, maxCrpsRatioScaled := 1250
      brierScaled := 120, maxBrierScaled := 250
      coverageViolations := 0
      oodMahalanobisScaled := 1250, maxOodScaled := 3500 }).passed
  let seamCleanAdmit :=
    match admitToDeterministic
      { valueScaled := 100, calibrated := true, inDomain := true
        finiteOk := true, sampleCount := 256, minSamples := 200 } with
    | some _ => true
    | none => false
  let replayCleanOk :=
    (guardReplayExact "deadbeef" "deadbeef").passed
  let rctCleanOk := (guardRctR1Promotion 30 950
    [ { stratumId := "STRAT-D-CANCEL", replicates := 32, controlKills := 0, treatmentKills := 32
        cleanReplicates := 32, treatmentFalsePositives := 0, isProbabilistic := false
        a12ScaledPer1000 := 1000, pSignificant := true }
    , { stratumId := "STRAT-R-SPD", replicates := 32, controlKills := 0, treatmentKills := 32
        cleanReplicates := 32, treatmentFalsePositives := 0, isProbabilistic := false
        a12ScaledPer1000 := 1000, pSignificant := true }
    , { stratumId := "STRAT-P-CAL", replicates := 32, controlKills := 0, treatmentKills := 32
        cleanReplicates := 32, treatmentFalsePositives := 0, isProbabilistic := true
        a12ScaledPer1000 := 1000, pSignificant := true } ]).passed

  -- Adversarial negative controls: every poisoned case MUST fail closed!
  let negMonolith :=
    !(witnessPassed
      { witnessId := .w_correspondence
        policyDigestPresent := false
        inputDigestsPresent := false
        replayCmdPresent := false
        violationCount := 0 })
  let negSpd :=
    allDiagonalsPositiveMat3 poisonSpdMat3 &&
    !(guardSylvesterSPD3 poisonSpdMat3).passed
  let negFpCancel :=
    !(guardScaledCancellation 10000 16 20000000 1000000).passed
  let negCapBreach :=
    !(guardScaledConservation 0 180 100).passed
  let negCalMiscal :=
    !(guardScaledCalibration
      { sampleCount := 256, minSamples := 200
        dkwStatScaled := 350, dkwBoundScaled := 102
        crpsRatioScaled := 2100, maxCrpsRatioScaled := 1250
        brierScaled := 340, maxBrierScaled := 250
        coverageViolations := 3
        oodMahalanobisScaled := 1000, maxOodScaled := 3500 }).passed
  let negSeamOod :=
    match admitToDeterministic
      { valueScaled := 5, calibrated := false, inDomain := false
        finiteOk := true, sampleCount := 12, minSamples := 200 } with
    | some _ => false
    | none => true
  let negSeamNonFinite :=
    match admitToDeterministic
      { valueScaled := 0, calibrated := true, inDomain := true
        finiteOk := false, sampleCount := 256, minSamples := 200 } with
    | some _ => false
    | none => true
  let negReplayDrift :=
    !(guardReplayExact "aaaa" "bbbb").passed
  let negRctUnderpowered :=
    !(guardRctR1Promotion 30 950
      [ { stratumId := "STRAT-R-SPD", replicates := 10, controlKills := 0, treatmentKills := 10
          cleanReplicates := 10, treatmentFalsePositives := 0, isProbabilistic := false
          a12ScaledPer1000 := 1000, pSignificant := true } ]).passed
  let negRctDetFpr :=
    !(guardRctR1Promotion 30 950
      [ { stratumId := "STRAT-R-SPD", replicates := 32, controlKills := 0, treatmentKills := 32
          cleanReplicates := 32, treatmentFalsePositives := 1, isProbabilistic := false
          a12ScaledPer1000 := 1000, pSignificant := true } ]).passed

  [ guardZeroViolations "policy_13_witnesses_declared" (if all13PresentInPolicy then 0 else 1)
  , guardZeroViolations "policy_14_defects_declared" (if all14DefectsPresent then 0 else 1)
  , guardZeroViolations "fixtures_21_poison_ids_match" (if all21InPolicyAndFixtures then 0 else 1)
  , guardZeroViolations "rct_r1_config_strata_valid" (if rctConfigOk then 0 else 1)
  , guardZeroViolations "witness_suite_13_complete" (if suiteOk then 0 else 1)
  , guardZeroViolations "clean_sylvester_spd" (if spdCleanOk then 0 else 1)
  , guardZeroViolations "clean_fp_cancellation_bound" (if fpCleanOk then 0 else 1)
  , guardZeroViolations "clean_aggregate_conservation" (if capCleanOk then 0 else 1)
  , guardZeroViolations "clean_calibration_guard" (if calCleanOk then 0 else 1)
  , guardZeroViolations "clean_seam_p_to_d_admit" (if seamCleanAdmit then 0 else 1)
  , guardZeroViolations "clean_seam_d_to_p_replay" (if replayCleanOk then 0 else 1)
  , guardZeroViolations "clean_rct_r1_promotion" (if rctCleanOk then 0 else 1)
  , guardZeroViolations "neg_monolithic_missing_provenance" (if negMonolith then 0 else 1)
  , guardZeroViolations "neg_spd_positive_diag_indefinite" (if negSpd then 0 else 1)
  , guardZeroViolations "neg_fp_catastrophic_cancellation" (if negFpCancel then 0 else 1)
  , guardZeroViolations "neg_aggregate_cap_breach" (if negCapBreach then 0 else 1)
  , guardZeroViolations "neg_calibration_miscalibrated" (if negCalMiscal then 0 else 1)
  , guardZeroViolations "neg_seam_ood_uncalibrated" (if negSeamOod then 0 else 1)
  , guardZeroViolations "neg_seam_nonfinite_rejected" (if negSeamNonFinite then 0 else 1)
  , guardZeroViolations "neg_seam_replay_drift_rejected" (if negReplayDrift then 0 else 1)
  , guardZeroViolations "neg_rct_underpowered_rejected" (if negRctUnderpowered then 0 else 1)
  , guardZeroViolations "neg_rct_det_fpr_rejected" (if negRctDetFpr then 0 else 1) ]

def main (args : List String) : IO UInt32 := do
  let policyPath := args.getD 0 "data/manifests/swe_sweep_policy_v1.json"
  let fixturesPath := args.getD 1 "data/fixtures/rung1_negative_controls_v1.json"
  let rctPath := args.getD 2 "data/trials/rct_r1_config_v1.json"
  let policyRaw ← IO.FS.readFile policyPath
  let fixturesRaw ← IO.FS.readFile fixturesPath
  let rctRaw ← IO.FS.readFile rctPath
  let verdicts := verifyRung1Vaults policyRaw fixturesRaw rctRaw
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"
  let failed := failedCompartments verdicts
  if failed.isEmpty then
    IO.println s!"LEAN SWEEP WITNESS SUITE PASS ({verdicts.length}/{verdicts.length} guards)"
    return 0
  else
    IO.eprintln s!"LEAN SWEEP WITNESS SUITE FAIL: {failed}"
    return 1
