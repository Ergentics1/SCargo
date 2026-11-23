-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec
import SCargoLean.TransferAirlock
import SCargoLean.HighMassCensus

/-!
# SCargo Lean Compartment: Standalone Arc 4 High-Mass Census Test Driver

Dynamically reads `data/trials/arc4_high_mass_census_v1.json`,
`data/manifests/upstream_requirements_v1.json`, and
`data/sources/standard_vocabulary_v1.json`; verifies UP-08 lexical
reconciliation, zero copied proof bodies, Z-C2/Z-C3/Z-C4 bounds,
adversarial negative controls, and Arc 4 -> Rung 3 -> Rung 2 -> Rung 1 containment.
-/

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock
open SCargoLean.HighMassCensus

private def verifyArc4 (censusRaw upRaw vocabRaw : String) : List GuardVerdict :=
  let up08LexOk :=
    containsSubstr upRaw "\"allowed_clean_room_activities\"" &&
    containsSubstr upRaw "\"UP-08\"" &&
    containsSubstr vocabRaw "\"Independent Clean-Room Derivation vs. Verbatim Copying\"" &&
    containsSubstr vocabRaw "\"schema_version\": \"1.1.0\""

  let censusHeaderOk :=
    containsSubstr censusRaw "\"census_id\": \"ARC4-HIGHMASS-CENSUS-V1\"" &&
    containsSubstr censusRaw "\"source_repo_commit\": \"51d9b1a28026d458aef9c9af3df8b083276e3d2d\"" &&
    containsSubstr censusRaw "\"target_repo_mutation_allowed\": false" &&
    containsSubstr censusRaw "\"zone_z_c2_explicit_dumps\"" &&
    containsSubstr censusRaw "\"zone_z_c3_private_duplicates\"" &&
    containsSubstr censusRaw "\"zone_z_c4_dominator_and_hub\"" &&
    containsSubstr censusRaw "\"pareto_zone_ranking\""

  let zeroCopyOk := !hasVerbatimProofBody censusRaw

  let negCopyRejected :=
    hasVerbatimProofBody "{\"snippet\": \"private theorem bad : True := by trivial\"}" &&
    hasVerbatimProofBody "{\"snippet\": \"noncomputable def bad := 0\"}"

  let clusterBoundsOk :=
    clusterReclaimable 1 20 == 0 &&
    clusterReclaimable 4 12 == 36 &&
    clusterReclaimable 4 12 < 4 * 12

  let paretoZ2Ok :=
    isParetoReduction
      { files := 100, lines := 10000, bytes := 500000 }
      { files := 100, lines := 7000, bytes := 350000 } &&
    !isParetoReduction
      { files := 100, lines := 10000, bytes := 500000 }
      { files := 100, lines := 10001, bytes := 350000 }

  let noZoneALeak :=
    !containsSubstr censusRaw "\"src/Main.lean\"" &&
    !containsSubstr censusRaw "\"lakefile.toml\""

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
  let poisonedA4Copy : Arc4CensusReceipt := { cleanA4 with zeroVerbatimCopy := false }
  let poisonedA4R3 : Arc4CensusReceipt :=
    { cleanA4 with rung3 := { cleanR3 with targetRepoUntouched := false } }
  let containmentOk :=
    arc4AllPass cleanA4 && !arc4AllPass poisonedA4Copy && !arc4AllPass poisonedA4R3

  [ guardZeroViolations "arc4_up08_lexical_reconciled" (if up08LexOk then 0 else 1)
  , guardZeroViolations "arc4_census_schema_and_sha_valid" (if censusHeaderOk then 0 else 1)
  , guardZeroViolations "arc4_up08_zero_verbatim_copy_in_census" (if zeroCopyOk then 0 else 1)
  , guardZeroViolations "arc4_neg_verbatim_proof_body_rejected" (if negCopyRejected then 0 else 1)
  , guardZeroViolations "arc4_z3_cluster_reclaimability_bounds" (if clusterBoundsOk then 0 else 1)
  , guardZeroViolations "arc4_z2_pareto_strict_guard" (if paretoZ2Ok then 0 else 1)
  , guardZeroViolations "arc4_zero_zone_a_leak_in_census" (if noZoneALeak then 0 else 1)
  , guardZeroViolations "arc4_contains_rung3_rung2_rung1" (if containmentOk then 0 else 1) ]

def main (args : List String) : IO UInt32 := do
  let root := args.getD 0 "."
  let censusRaw ← IO.FS.readFile s!"{root}/data/trials/arc4_high_mass_census_v1.json"
  let upRaw ← IO.FS.readFile s!"{root}/data/manifests/upstream_requirements_v1.json"
  let vocabRaw ← IO.FS.readFile s!"{root}/data/sources/standard_vocabulary_v1.json"
  let verdicts := verifyArc4 censusRaw upRaw vocabRaw
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"
  let failed := failedCompartments verdicts
  if failed.isEmpty then
    IO.println s!"LEAN ARC 4 HIGH-MASS CENSUS SUITE PASS ({verdicts.length}/{verdicts.length} guards)"
    return 0
  else
    IO.eprintln s!"LEAN ARC 4 HIGH-MASS CENSUS SUITE FAIL: {failed}"
    return 1
