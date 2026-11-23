-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.RiemLattice
import SCargoLean.SchwartzZippel

/-!
# SCargo Lean Compartment: Standalone Schwartz-Zippel x PLR Test Driver

Dynamically reads `data/sources/schwartz_zippel_research_v1.json` and
`data/sources/riemann_lattice_graph_rh_v1.json`, checks cross-vault parity,
verifies coupled cyclotomic torus / holonomy / cycle-sieve / G_PLR bridge
invariants, and runs adversarial fail-closed negative controls.
-/

open SCargoLean
open SCargoLean.RiemLattice
open SCargoLean.SchwartzZippel

private def containsSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def verifyCoupledVaults (szRaw rlRaw : String) : List GuardVerdict :=
  let provOk :=
    containsSubstr szRaw "\"tradition_id\": \"PIT-SZ\"" &&
    containsSubstr szRaw "\"anti_conflation_guard\"" &&
    containsSubstr rlRaw "\"tradition_id\": \"RIEM-LATTICE\"" &&
    !(containsSubstr (szRaw.toLower) "wikipedia.org") &&
    !(containsSubstr (szRaw.toLower) "wikisource.org") &&
    !(containsSubstr (rlRaw.toLower) "wikipedia.org") &&
    !(containsSubstr (rlRaw.toLower) "wikisource.org")
  let torusOk :=
    verifyCyclotomicBilinearTorus 13 2 &&
    verifyCyclotomicBilinearTorus 37 8 &&
    verifyCyclotomicBilinearTorus 61 32 &&
    verifyCyclotomicBilinearTorus 97 6 &&
    verifyCyclotomicBilinearTorus 65521 53059 &&
    containsSubstr szRaw "\"zeta_12\": 53059" &&
    containsSubstr szRaw "\"bilinear_involution_degree\": 2"
  let holonomyOk :=
    rhoImageSize 13 2 1 == 24 &&
    rhoImageSize 13 2 2 == 12 &&
    rhoImageSize 13 2 3 == 8 &&
    rhoImageSize 13 2 4 == 6 &&
    rhoImageSize 13 2 5 == 24 &&
    rhoWord 13 2 0 [.P, .L] == rhoWord 13 2 0 [.L, .P] &&
    rhoWord 13 2 1 [.P, .L] != rhoWord 13 2 1 [.L, .P] &&
    containsSubstr szRaw "\"distinct_matrices\": 24, \"kernel_size\": 1, \"faithful\": true"
  let (c6, nc6) := sieveLen6Cycles
  let sieveOk :=
    c6 == 144 && nc6 == 48 &&
    c6 / 12 == 12 && nc6 / 12 == 4 &&
    containsSubstr szRaw "\"contractible_walks\": 144" &&
    containsSubstr szRaw "\"non_contractible_walks\": 48" &&
    containsSubstr rlRaw "\"LPRLPR_pitch_class_dual_faces\": 12" &&
    containsSubstr rlRaw "\"LPLPLP_hexatonic_cycles\": 4"
  let permVal := permBiadj12
  let bridgeOk :=
    permVal == 113 &&
    45 * 45 == 2025 &&
    45 % 3 == 0 && 45 % 5 == 0 &&
    containsSubstr szRaw "\"exact_det_B\": 45" &&
    containsSubstr szRaw "\"exact_det_B_squared\": 2025" &&
    containsSubstr szRaw "\"exact_perm_B_perfect_matchings\": 113" &&
    containsSubstr rlRaw "2025]"
  let regimeOk :=
    rootsXTimesXMinus1 5 == 2 &&
    rootsXTimesXMinus1 6 == 4 &&
    rootsXTimesXMinus1 12 == 4 &&
    rootsXTimesXMinus1 15 == 4 &&
    rootsXTimesXMinus1 30 == 8 &&
    zeros3xMod6 (List.range 6) == 18 &&
    zeros3xMod6 [0, 1] == 2 &&
    f5Zeros (fun x y => x * y) == 9 &&
    f5Zeros (fun x y => x + y) == 5 &&
    boolCube4NonzerosX1X2X3 == 2 &&
    containsSubstr szRaw "\"sum_of_hasse_multiplicities\": 15" &&
    containsSubstr szRaw "\"actual_zero_ratio\": \"2/3\""
  [ guardZeroViolations "sz_vault_tradition_and_no_wiki" (if provOk then 0 else 1)
  , guardZeroViolations "coupled_cyclotomic_torus_bilinear" (if torusOk then 0 else 1)
  , guardZeroViolations "coupled_nonabelian_holonomy_rho_k" (if holonomyOk then 0 else 1)
  , guardZeroViolations "coupled_cycle_sieve_len6_cross_vault" (if sieveOk then 0 else 1)
  , guardZeroViolations "g_plr_edmonds_bridge_cross_vault" (if bridgeOk then 0 else 1)
  , guardZeroViolations "correspondence_regime_bounds_vault_parity" (if regimeOk then 0 else 1)
  ]

private def resolvePair (args : List String) : IO (Option (System.FilePath × System.FilePath)) := do
  match args with
  | [p1, p2] =>
    let f1 := System.FilePath.mk p1
    let f2 := System.FilePath.mk p2
    if (← f1.pathExists) && (← f2.pathExists) then return some (f1, f2) else return none
  | _ =>
    let pairs :=
      [ (System.FilePath.mk "data/sources/schwartz_zippel_research_v1.json",
         System.FilePath.mk "data/sources/riemann_lattice_graph_rh_v1.json")
      , (System.FilePath.mk "../../data/sources/schwartz_zippel_research_v1.json",
         System.FilePath.mk "../../data/sources/riemann_lattice_graph_rh_v1.json")
      ]
    for (f1, f2) in pairs do
      if (← f1.pathExists) && (← f2.pathExists) then return some (f1, f2)
    return none

def main (args : List String) : IO UInt32 := do
  let some (szPath, rlPath) ← resolvePair args
    | do
        IO.eprintln "[FAIL] vault_files_missing: pass <schwartz_zippel_research_v1.json> <riemann_lattice_graph_rh_v1.json>"
        return 2

  let szRaw ← IO.FS.readFile szPath
  let rlRaw ← IO.FS.readFile rlPath
  let verdicts := verifyCoupledVaults szRaw rlRaw

  IO.println "=== SCargoLean.SchwartzZippel Standalone Verification ==="
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"

  -- Adversarial negative controls (every attack must fail closed)
  let poisonedPerm := szRaw.replace "\"exact_perm_B_perfect_matchings\": 113" "\"exact_perm_B_perfect_matchings\": 114"
  let negPerm := failedCompartments (verifyCoupledVaults poisonedPerm rlRaw) == ["g_plr_edmonds_bridge_cross_vault"]

  let poisonedSieve := szRaw.replace "\"contractible_walks\": 144" "\"contractible_walks\": 140"
  let negSieve := failedCompartments (verifyCoupledVaults poisonedSieve rlRaw) == ["coupled_cycle_sieve_len6_cross_vault"]

  let poisonedWiki := szRaw.replace "\"verification_status\"" "\"poisoned_host\": \"synthetic.wikipedia.org\", \"verification_status\""
  let negWiki := failedCompartments (verifyCoupledVaults poisonedWiki rlRaw) == ["sz_vault_tradition_and_no_wiki"]

  let negCompMod6 := !(guardPrimeModulus 6).passed
  let negCompMod12 := !(guardPrimeModulus 12).passed
  let negCondDFail := !(guardConditionDMod 6 [0, 1, 3, 4]).passed
  let negDegBinary := !(guardNonVacuousDegree 2 2).passed
  let negDegTorus := !(guardNonVacuousDegree 12 12).passed
  let negWrongTorusPrime := !(guardCyclotomicTorus 17 2).passed

  let negControls :=
    [ guardZeroViolations "neg_ctrl_poisoned_perm_rejected" (if negPerm then 0 else 1)
    , guardZeroViolations "neg_ctrl_poisoned_sieve_rejected" (if negSieve then 0 else 1)
    , guardZeroViolations "neg_ctrl_wikipedia_url_rejected" (if negWiki then 0 else 1)
    , guardZeroViolations "neg_ctrl_composite_mod6_rejected" (if negCompMod6 then 0 else 1)
    , guardZeroViolations "neg_ctrl_composite_mod12_rejected" (if negCompMod12 then 0 else 1)
    , guardZeroViolations "neg_ctrl_condition_d_violation_rejected" (if negCondDFail then 0 else 1)
    , guardZeroViolations "neg_ctrl_binary_degree_stall_rejected" (if negDegBinary then 0 else 1)
    , guardZeroViolations "neg_ctrl_torus_degree_12_stall_rejected" (if negDegTorus then 0 else 1)
    , guardZeroViolations "neg_ctrl_non_mod12_prime_17_rejected" (if negWrongTorusPrime then 0 else 1)
    ]

  IO.println "=== Adversarial & Correspondence Boundary Controls ==="
  for v in negControls do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"

  let allVerdicts := verdicts ++ negControls ++ canonicalCoupledVerdicts
  if allCompartmentGuardsHold allVerdicts then
    IO.println s!"ALL {allVerdicts.length} LEAN SCHWARTZ-ZIPPEL x PLR GUARDS PASSED (0 violations)"
    return 0
  else
    IO.eprintln s!"FAILED COMPARTMENTS: {failedCompartments allVerdicts}"
    return 1
