-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec
import SCargoLean.TransferAirlock
import SCargoLean.HighMassCensus
import SCargoLean.PreflightHarness

/-!
# SCargo Lean Compartment: Standalone Arc 5 Pre-Flight Elaboration & Bundle Test Driver

Dynamically reads `transfer/bundles/arc5_preflight_bundles_v1.json`, verifies
clean-room UP-08 zero-copy hygiene, dual-route UP-07 rules, binder-plicity
rejection, real Lean 4.36 `module` E1-E3 elaboration properties, and
Arc 5 -> Arc 4 -> Rung 3 -> Rung 2 -> Rung 1 smooth containment.
-/

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock
open SCargoLean.HighMassCensus
open SCargoLean.Preflight
open SCargoLean.PreflightHarness

private def verifyArc5 (bundleRaw : String) : List GuardVerdict :=
  let bundleSchemaOk :=
    containsSubstr bundleRaw "\"bundle_suite_id\": \"ARC5-PREFLIGHT-BUNDLES-V1\"" &&
    containsSubstr bundleRaw "\"source_repo_commit\": \"51d9b1a28026d458aef9c9af3df8b083276e3d2d\"" &&
    containsSubstr bundleRaw "\"target_repo_mutation_allowed\": false" &&
    containsSubstr bundleRaw "\"Z-C0\"" &&
    containsSubstr bundleRaw "\"Z-C1A\"" &&
    containsSubstr bundleRaw "\"Z-C2\"" &&
    containsSubstr bundleRaw "\"Z-C4\"" &&
    containsSubstr bundleRaw "\"quick_check\"" &&
    containsSubstr bundleRaw "\"full_rh_build\""

  let zeroCopyOk := !hasVerbatimProofBody bundleRaw

  let noZoneALeak :=
    !containsSubstr bundleRaw "\"src/Main.lean\"" &&
    !containsSubstr bundleRaw "\"lakefile.toml\""

  let up07RoutingOk :=
    classifyUp07Route 8 4 == .quick_check &&
    classifyUp07Route 1 127439 == .full_rh_build &&
    classifyUp07Route 9 0 == .full_rh_build &&
    classifyUp07Route 1 2001 == .full_rh_build

  let binderGuardOk :=
    z1aSafeAlias { explicitCount := 1, implicitCount := 1, instanceCount := 0, universeParamCount := 0 }
                 { explicitCount := 1, implicitCount := 1, instanceCount := 0, universeParamCount := 0 } &&
    !z1aSafeAlias { explicitCount := 2, implicitCount := 0, instanceCount := 0, universeParamCount := 0 }
                  { explicitCount := 1, implicitCount := 1, instanceCount := 0, universeParamCount := 0 } &&
    !z1aSafeAlias { explicitCount := 1, implicitCount := 1, instanceCount := 0, universeParamCount := 1 }
                  { explicitCount := 1, implicitCount := 1, instanceCount := 0, universeParamCount := 1 }

  let e1e2e3RuntimeOk :=
    z2ExplicitDump 3 4 5 == 17 &&
    z2CleanDeexpanded 3 4 5 == 17 &&
    leafScaled (n := 7) 10 == 17

  let negControlsOk :=
    hasVerbatimProofBody "{\"patch\": \"private theorem leak : True := by trivial\"}" &&
    (classifyUp07Route 1 127439 != .quick_check)

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
  let poisonedA5Up07 : Arc5PreflightReceipt := { cleanA5 with dualRouteUp07Sound := false }
  let poisonedA5R1 : Arc5PreflightReceipt :=
    { cleanA5 with arc4 := { cleanA4 with rung3 := { cleanR3 with zoneAClean := false } } }
  let containmentOk :=
    arc5AllPass cleanA5 && !arc5AllPass poisonedA5Up07 && !arc5AllPass poisonedA5R1

  [ guardZeroViolations "arc5_bundle_manifest_schema_valid" (if bundleSchemaOk then 0 else 1)
  , guardZeroViolations "arc5_up08_zero_verbatim_copy_in_bundles" (if zeroCopyOk then 0 else 1)
  , guardZeroViolations "arc5_zero_zone_a_targets_in_bundles" (if noZoneALeak then 0 else 1)
  , guardZeroViolations "arc5_up07_dual_route_soundness" (if up07RoutingOk then 0 else 1)
  , guardZeroViolations "arc5_z1a_binder_plicity_and_univ_guard" (if binderGuardOk then 0 else 1)
  , guardZeroViolations "arc5_lean436_module_e1_e2_e3_elaborated" (if e1e2e3RuntimeOk then 0 else 1)
  , guardZeroViolations "arc5_negative_controls_fail_closed" (if negControlsOk then 0 else 1)
  , guardZeroViolations "arc5_contains_arc4_rung3_rung2_rung1" (if containmentOk then 0 else 1) ]

def main (args : List String) : IO UInt32 := do
  let root := args.getD 0 "."
  let bundleRaw ← IO.FS.readFile s!"{root}/transfer/bundles/arc5_preflight_bundles_v1.json"
  let verdicts := verifyArc5 bundleRaw
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"
  let failed := failedCompartments verdicts
  if failed.isEmpty then
    IO.println s!"LEAN ARC 5 PREFLIGHT HARNESS SUITE PASS ({verdicts.length}/{verdicts.length} guards)"
    return 0
  else
    IO.eprintln s!"LEAN ARC 5 PREFLIGHT HARNESS SUITE FAIL: {failed}"
    return 1
