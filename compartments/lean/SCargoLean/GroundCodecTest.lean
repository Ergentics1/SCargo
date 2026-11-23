-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec

/-!
# SCargo Lean Compartment: Standalone Rung 2 Ground Codec & Parity Test Driver

Dynamically reads `data/trials/rung2_fuzz_corpus_v1.json`, verifies Rung 2
corpus parameters, metamorphic relations (MR-1, MR-2), wrapper AST classification,
cycle/malformed rejection, mass conservation, and Rung 1 smooth containment.
-/

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec

private def containsSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def verifyRung2 (corpusRaw : String) : List GuardVerdict :=
  let cfgOk :=
    containsSubstr corpusRaw "\"rung\": 2" &&
    containsSubstr corpusRaw "\"master_seed\": 2026112302" &&
    containsSubstr corpusRaw "\"cases_per_family\": 64" &&
    containsSubstr corpusRaw "\"FAM-DAG-CLEAN\"" &&
    containsSubstr corpusRaw "\"FAM-CYCLE-INJECTED\"" &&
    containsSubstr corpusRaw "\"FAM-DIAMOND-DOM\"" &&
    containsSubstr corpusRaw "\"FAM-DEAD-LEAVES\"" &&
    containsSubstr corpusRaw "\"FAM-WRAPPER-AST\"" &&
    containsSubstr corpusRaw "\"FAM-METAMORPHIC-INV\""

  let dagOk :=
    graphValid diamondDag &&
    !hasCycle diamondDag &&
    !hasCycle diamondDagReversed &&
    (reachableFromRoot diamondDag).length == 4 &&
    (reachableFromRoot diamondDagReversed).length == 4 &&
    (deadLeaves diamondDag).length == 1 &&
    (deadLeaves diamondDagReversed).length == 1 &&
    reachableMassLines diamondDag == 100 &&
    deadMassLines diamondDag == 50 &&
    totalMassLines diamondDag == 150

  let cycleOk := graphValid selfLoopGraph && hasCycle selfLoopGraph

  let pureWrapLines := ["import Base", "export Base (foo)"]
  let commentedWrapLines := ["-- comment", "", "import Base", "-- trailing", "export Base (foo)"]
  let hubLines := ["public import A", "public import B"]
  let substLines := ["import Base", "theorem t : True := trivial"]
  let wrapperOk :=
    classifyWrapperLines pureWrapLines == .pure_wrapper &&
    classifyWrapperLines commentedWrapLines == .pure_wrapper &&
    classifyWrapperLines hubLines == .reexport_hub &&
    classifyWrapperLines substLines == .substantive

  -- Malformed negative controls must all be rejected fail-closed.
  let missingRoot : GroundGraph := { root := "Missing", modules := diamondDag.modules }
  let dupMod : GroundGraph :=
    { root := "A", modules := [{ name := "A", lines := 1, bytes := 10, imports := [] },
                               { name := "A", lines := 2, bytes := 20, imports := [] }] }
  let danglingImp : GroundGraph :=
    { root := "A", modules := [{ name := "A", lines := 1, bytes := 10, imports := ["Ghost"] }] }
  let malformedRejected :=
    !graphValid missingRoot && !graphValid dupMod && !graphValid danglingImp

  let cleanR1 : List CompartmentWitness :=
    allWitnessIds.map (fun wid =>
      { witnessId := wid, policyDigestPresent := true, inputDigestsPresent := true
        replayCmdPresent := true, violationCount := 0 })
  let r2Clean : Rung2Receipt :=
    { rung1Witnesses := cleanR1, corpusCasesPerFamily := 64, minCasesRequired := 30
      metamorphicMismatches := 0, shrinkingViolations := 0
      malformedEscapes := 0, parityMismatches := 0 }
  let r2PoisonedR1 : Rung2Receipt :=
    { r2Clean with rung1Witnesses := cleanR1.map (fun w =>
        if w.witnessId == .w_seam_integrity then { w with violationCount := 1 } else w) }
  let containmentOk := rung2AllPass r2Clean && !rung2AllPass r2PoisonedR1

  [ guardZeroViolations "rung2_corpus_config_valid" (if cfgOk then 0 else 1)
  , guardZeroViolations "rung2_diamond_dag_mr1_and_mass" (if dagOk then 0 else 1)
  , guardZeroViolations "rung2_cycle_detection_self_loop" (if cycleOk then 0 else 1)
  , guardZeroViolations "rung2_wrapper_ast_and_mr2" (if wrapperOk then 0 else 1)
  , guardZeroViolations "rung2_malformed_negative_controls" (if malformedRejected then 0 else 1)
  , guardZeroViolations "rung2_contains_rung1_correspondence" (if containmentOk then 0 else 1) ]

def main (args : List String) : IO UInt32 := do
  let corpusPath := args.getD 0 "data/trials/rung2_fuzz_corpus_v1.json"
  let corpusRaw ← IO.FS.readFile corpusPath
  let verdicts := verifyRung2 corpusRaw
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"
  let failed := failedCompartments verdicts
  if failed.isEmpty then
    IO.println s!"LEAN RUNG 2 GROUND CODEC SUITE PASS ({verdicts.length}/{verdicts.length} guards)"
    return 0
  else
    IO.eprintln s!"LEAN RUNG 2 GROUND CODEC SUITE FAIL: {failed}"
    return 1
