-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec
import SCargoLean.TransferAirlock
import SCargoLean.HighMassCensus
import SCargoLean.PreflightHarness
import SCargoLean.PatchVerifier
import SCargoLean.AirlockRehearsal

/-!
# SCargo Lean Compartment: Standalone Arc 7 G4–G5 Airlock Rehearsal Test Driver

Dynamically reads `transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json`, verifies
exact Zone A SHA-256 pins, zero-copy `UP-08` hygiene, `quick-check.py:80`
deletion deferral, G5 comparator/axiom fail-closed guards, `PRIN-06` anti-theater
rehearsal honesty, and Arc 7 -> ... -> Rung 1 smooth containment.
-/

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock
open SCargoLean.HighMassCensus
open SCargoLean.PreflightHarness
open SCargoLean.PatchVerifier
open SCargoLean.AirlockRehearsal

private def verifyArc7 (rehRaw : String) : List GuardVerdict :=
  let schemaAndPinsOk :=
    containsSubstr rehRaw "\"rehearsal_suite_id\": \"ARC7-G4-G5-REHEARSAL-V1\"" &&
    containsSubstr rehRaw "\"source_repo_commit\": \"51d9b1a28026d458aef9c9af3df8b083276e3d2d\"" &&
    containsSubstr rehRaw "\"rehearsal_mode\": true" &&
    containsSubstr rehRaw "\"remote_ci_attestation\": false" &&
    containsSubstr rehRaw "\"target_repo_mutation_allowed\": false" &&
    containsSubstr rehRaw "e12dd96eb155851de5107571dbfc959e5d9b230ead90331b4778b55b048590bb" &&
    containsSubstr rehRaw "ee003c5c7a9b2b2a82a142b6633916661c07117199dd143d94d1af63910237df"

  let zeroCopyOk := !hasVerbatimProofBody rehRaw

  let quickCheckDeferralOk :=
    quickCheckEligible 8 12 false &&
    quickCheckEligible 8 8 false &&
    quickCheckEligible 8 10 false &&
    !quickCheckEligible 8 1594 true &&
    !quickCheckEligible 1 127440 false &&
    containsSubstr rehRaw "\"deleted/unsafe source requires full build\""

  let g5AllTheoremsOk :=
    containsSubstr rehRaw "\"riemannHypothesis\"" &&
    containsSubstr rehRaw "\"riemannZeta_eq_zero_re\"" &&
    containsSubstr rehRaw "\"LFunction_ne_zero_of_half_lt_re\"" &&
    containsSubstr rehRaw "\"LFunction_eq_zero_re\"" &&
    containsSubstr rehRaw "\"LFunction_eq_zero_re_of_isPrimitive\""

  let baseG5 : G5ReleaseEvidence :=
    { fullBuild := true, buildExitCode := 0, leanKernelExit := 0
      leanParanoidExit := 0, nanodaExit := 0, allFiveTheoremsPresent := true
      axiomsSubsetPermitted := true, zoneAPinsMatched := true
      baseHeadFresh := true, remoteAttested := true }
  let g5NegativeControlsOk :=
    g5ReleaseAccepted baseG5 &&
    !g5ReleaseAccepted { baseG5 with fullBuild := false } &&
    !g5ReleaseAccepted { baseG5 with nanodaExit := 1 } &&
    !g5ReleaseAccepted { baseG5 with axiomsSubsetPermitted := false } &&
    !g5ReleaseAccepted { baseG5 with zoneAPinsMatched := false } &&
    !g5ReleaseAccepted { baseG5 with baseHeadFresh := false } &&
    !g5ReleaseAccepted { baseG5 with remoteAttested := false }

  let arc6BindingOk :=
    containsSubstr rehRaw "\"total_files\": 137" &&
    containsSubstr rehRaw "\"total_saved_lines\": 32166" &&
    containsSubstr rehRaw "\"total_saved_bytes\": 1650480"

  let antiTheaterOk :=
    containsSubstr rehRaw "\"rehearsal_mode\": true" &&
    containsSubstr rehRaw "\"remote_ci_attestation\": false" &&
    !g5ReleaseAccepted { baseG5 with remoteAttested := false }

  let cleanR1 : List CompartmentWitness :=
    allWitnessIds.map (fun wid =>
      { witnessId := wid, policyDigestPresent := true, inputDigestsPresent := true
        replayCmdPresent := true, violationCount := 0 })
  let cleanR2 : Rung2Receipt :=
    { rung1Witnesses := cleanR1, corpusCasesPerFamily := 64, minCasesRequired := 30
      metamorphicMismatches := 0, shrinkingViolations := 0
      malformedEscapes := 0, parityMismatches := 0 }
  let cleanR3 : Rung3AirlockReceipt :=
    { rung2 := cleanR2, baselineShaMatched := true, zoneAClean := true, axiomsClean := true
      paretoStrictAllPackages := true, up07BatchesValid := true
      negativeControlsRejected := 7, requiredNegativeControls := 7, targetRepoUntouched := true }
  let cleanA4 : Arc4CensusReceipt :=
    { rung3 := cleanR3, up08Reconciled := true, zeroVerbatimCopy := true
      z2Valid := true, z3Valid := true, z4Valid := true, rankingValid := true
      negativeControlsRejected := 6, requiredNegativeControls := 6 }
  let cleanA5 : Arc5PreflightReceipt :=
    { arc4 := cleanA4, leanModulesElaborated := true, dualRouteUp07Sound := true
      shardsConserved := true, syntheticDiffsValid := true, zeroZoneATouch := true
      zeroVerbatimCopy := true, negativeControlsRejected := 6, requiredNegativeControls := 6 }
  let cleanA6 : Arc6PatchReceipt :=
    { arc5 := cleanA5, totalPatchedFiles := 137, expectedPatchedFiles := 137
      allRoundtripsVerified := true, allInvariantsVerified := true, allParetoStrict := true
      z2MaxLineWithinBound := true, syntheticPatchSuiteValid := true
      leanCompactCseElaborated := true, negativeControlsRejected := 7, requiredNegativeControls := 7 }
  let cleanA7 : Arc7RehearsalReceipt :=
    { arc6 := cleanA6, zoneAPinsVerified := true, quickCheckDiagnosticsValid := true
      fullBuildReceiptValid := true, comparatorAxiomsValid := true, rehearsalModeHonest := true
      negativeControlsRejected := 8, requiredNegativeControls := 8 }
  let poisonedA7Honest : Arc7RehearsalReceipt := { cleanA7 with rehearsalModeHonest := false }
  let poisonedA7Prior : Arc7RehearsalReceipt := { cleanA7 with arc6 := { cleanA6 with allRoundtripsVerified := false } }
  let containmentOk :=
    arc7AllPass cleanA7 && !arc7AllPass poisonedA7Honest && !arc7AllPass poisonedA7Prior

  [ guardZeroViolations "arc7_rehearsal_schema_and_zone_a_pins" (if schemaAndPinsOk then 0 else 1)
  , guardZeroViolations "arc7_up08_zero_verbatim_copy_in_rehearsal" (if zeroCopyOk then 0 else 1)
  , guardZeroViolations "arc7_quick_check_py80_deletion_deferral" (if quickCheckDeferralOk then 0 else 1)
  , guardZeroViolations "arc7_g5_five_challenge_theorems_declared" (if g5AllTheoremsOk then 0 else 1)
  , guardZeroViolations "arc7_g5_release_gate_negatives_fail_closed" (if g5NegativeControlsOk then 0 else 1)
  , guardZeroViolations "arc7_arc6_137_file_dataset_binding" (if arc6BindingOk then 0 else 1)
  , guardZeroViolations "arc7_prin06_anti_theater_rehearsal_honesty" (if antiTheaterOk then 0 else 1)
  , guardZeroViolations "arc7_contains_arc6_through_rung1" (if containmentOk then 0 else 1) ]

def main (args : List String) : IO UInt32 := do
  let root := args.getD 0 "."
  let rehRaw ← IO.FS.readFile s!"{root}/transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json"
  let verdicts := verifyArc7 rehRaw
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"
  let failed := failedCompartments verdicts
  if failed.isEmpty then
    IO.println s!"LEAN ARC 7 AIRLOCK REHEARSAL SUITE PASS ({verdicts.length}/{verdicts.length} guards)"
    return 0
  else
    IO.eprintln s!"LEAN ARC 7 AIRLOCK REHEARSAL SUITE FAIL: {failed}"
    return 1
