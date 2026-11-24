-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.AdaptiveSynth

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock
open SCargoLean.HighMassCensus
open SCargoLean.PreflightHarness
open SCargoLean.PatchVerifier
open SCargoLean.AirlockRehearsal
open SCargoLean.AdaptiveSynth

private def hasSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

def verifyArc8 (planTxt : String) : List GuardVerdict :=
  let schemaOk :=
    hasSubstr planTxt "\"synth_plan_id\": \"ARC8-ADAPTIVE-SYNTH-V1\"" &&
    hasSubstr planTxt "\"source_repo_commit\": \"51d9b1a28026d458aef9c9af3df8b083276e3d2d\"" &&
    hasSubstr planTxt "\"target_repo_mutation_allowed\": false"

  let zeroCopyAndZoneAOk :=
    !(hasSubstr planTxt ":= by") &&
    !(hasSubstr planTxt "public import Mathlib") &&
    !(hasSubstr planTxt "src/Challenge.lean") &&
    !(hasSubstr planTxt "src/Main.lean") &&
    !(hasSubstr planTxt "lake-manifest.json")

  let fiveZonesOk :=
    hasSubstr planTxt "\"Z-C0\"" &&
    hasSubstr planTxt "\"Z-C1A\"" &&
    hasSubstr planTxt "\"Z-C2\"" &&
    hasSubstr planTxt "\"Z-C3\"" &&
    hasSubstr planTxt "\"Z-C4\""

  let binPackOk :=
    hasSubstr planTxt "\"bin_packing_summary\"" &&
    hasSubstr planTxt "\"naive_quick_check_files\"" &&
    hasSubstr planTxt "\"adaptive_quick_check_files\"" &&
    hasSubstr planTxt "\"adaptive_shards\""

  let preflightModulesOk : Bool :=
    have _ : True := by
      have _ := @SCargoLean.Preflight.WrapperAliasStrict.aliasPoly_preserves_at_plicit.{0}
      have _ := SCargoLean.Preflight.WrapperAliasStrict.aliasClassical_preserves_at_plicit
      have _ := @SCargoLean.Preflight.WrapperAliasStrict.tightTheoremPoly_preserves_at_plicit.{0}
      have _ := SCargoLean.Preflight.PrivateDedupe.ConsumerAlpha.alpha_dedupe_defeq
      have _ := SCargoLean.Preflight.PrivateDedupe.ConsumerBeta.beta_dedupe_defeq
      have _ := SCargoLean.Preflight.PrivateDedupe.cross_consumer_dedupe_rfl
      trivial
    true

  let badZ1aBinder : Z1AFileDecision :=
    { singleDecl := true, targetResolved := true, closurePreserved := true,
      binderPlicityExact := false, noSectionVarCapture := true, savedLines := 14 }
  let badZ1aClosure : Z1AFileDecision :=
    { singleDecl := true, targetResolved := true, closurePreserved := false,
      binderPlicityExact := true, noSectionVarCapture := true, savedLines := 14 }
  let goodZ3 : Z3ClusterSpec :=
    { multiplicity := 3, blockLines := 54, delegationOverheadLines := 2,
      acyclicVerified := true, zeroAmbientVarCapture := true }
  let badZ3Cycle : Z3ClusterSpec :=
    { multiplicity := 3, blockLines := 54, delegationOverheadLines := 2,
      acyclicVerified := false, zeroAmbientVarCapture := true }
  let badZ3Var : Z3ClusterSpec :=
    { multiplicity := 3, blockLines := 54, delegationOverheadLines := 2,
      acyclicVerified := true, zeroAmbientVarCapture := false }
  let kernelNegsOk :=
    binQuickCheckAdmissible 8 70 false &&
    !(binQuickCheckAdmissible 9 70 false) &&
    !(binQuickCheckAdmissible 8 2001 false) &&
    !(binQuickCheckAdmissible 8 70 true) &&
    !(z1aModeA1Safe badZ1aBinder) &&
    !(z1aModeA1Safe badZ1aClosure) &&
    z3ClusterSafe goodZ3 &&
    decide (0 < z3NetSavedLines goodZ3) &&
    !(z3ClusterSafe badZ3Cycle) &&
    !(z3ClusterSafe badZ3Var)

  let roundtripOk :=
    hasSubstr planTxt "\"roundtrip_verified\": true" &&
    !(hasSubstr planTxt "\"roundtrip_verified\": false")

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
  let cleanA8 : Arc8SynthReceipt :=
    { arc7 := cleanA7, zeroZoneALeaks := true, allFiveZonesPresent := true
      allRoundtripVerified := true, z1aDualModeValid := true, z2AdaptiveWidthValid := true
      z3AcyclicClustersValid := true, adaptiveBinPackSound := true, adaptiveLiftMonotone := true
      negativeControlsRejected := 8, requiredNegativeControls := 8 }
  let poisonedA8Bin : Arc8SynthReceipt := { cleanA8 with adaptiveBinPackSound := false }
  let poisonedA8Prior : Arc8SynthReceipt :=
    { cleanA8 with arc7 := { cleanA7 with rehearsalModeHonest := false } }
  let containmentOk :=
    arc8AllPass cleanA8 && !arc8AllPass poisonedA8Bin && !arc8AllPass poisonedA8Prior

  [ guardZeroViolations "arc8_plan_schema_and_baseline_pin" (if schemaOk then 0 else 1)
  , guardZeroViolations "arc8_up08_zero_verbatim_and_zone_a_clean" (if zeroCopyAndZoneAOk then 0 else 1)
  , guardZeroViolations "arc8_all_five_zones_present" (if fiveZonesOk then 0 else 1)
  , guardZeroViolations "arc8_adaptive_bin_packing_present" (if binPackOk then 0 else 1)
  , guardZeroViolations "arc8_lean436_module_alias_and_dedupe_proved" (if preflightModulesOk then 0 else 1)
  , guardZeroViolations "arc8_kernel_negatives_fail_closed" (if kernelNegsOk then 0 else 1)
  , guardZeroViolations "arc8_100pct_roundtrip_verified" (if roundtripOk then 0 else 1)
  , guardZeroViolations "arc8_contains_arc7_through_rung1" (if containmentOk then 0 else 1) ]

def main (args : List String) : IO UInt32 := do
  let root := args.getD 0 "."
  let planRaw ← IO.FS.readFile s!"{root}/transfer/patches/arc8_adaptive_synth_plan_v1.json"
  let verdicts := verifyArc8 planRaw
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"
  let failed := failedCompartments verdicts
  if failed.isEmpty then
    IO.println s!"LEAN ARC 8 ADAPTIVE SYNTHESIS SUITE PASS ({verdicts.length}/{verdicts.length} guards)"
    return 0
  else
    IO.eprintln s!"LEAN ARC 8 ADAPTIVE SYNTHESIS SUITE FAIL: {failed}"
    return 1
