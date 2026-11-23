-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.RiemLattice

/-!
# SCargo Lean Compartment: Standalone Runtime & Adversarial Test Driver (`lake test`)

Exercises `SCargoLean.RiemLattice` at runtime against the external primary data vault
`data/sources/riemann_lattice_graph_rh_v1.json` (strict code/data separation) AND runs
adversarial negative-control pressure tests verifying fail-closed behavior.
-/

open SCargoLean
open SCargoLean.RiemLattice

private def containsSubstr (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

private def intListJsonString (xs : List Int) : String :=
  "[" ++ String.intercalate ", " (xs.map toString) ++ "]"

private def buildFull12GramMat : List (List Int) :=
  (List.finRange 12).map (fun i =>
    (List.finRange 12).map (fun j => gramM i j))

private def isZeroMat (M : List (List Int)) : Bool :=
  M.all (fun row => row.all (fun x => x == 0))

private def verifyVaultText (raw : String) : List GuardVerdict :=
  let (fullCharPoly, fullRem) := faddeevLeVerrierMat buildFull12GramMat
  let (circCharPoly, circRem) := faddeevLeVerrierCirc12 gramCircRow
  let nw := computeClosedNBWalks zetaInverse_poly 20
  let tradOk :=
    containsSubstr raw "\"tradition_id\": \"RIEM-LATTICE\"" &&
    containsSubstr raw "\"anti_conflation_guard\"" &&
    !(containsSubstr (raw.toLower) "wikipedia.org") &&
    !(containsSubstr (raw.toLower) "wikisource.org")
  let charpolyStr := intListJsonString fullCharPoly
  let charpolyOk :=
    fullCharPoly == circCharPoly &&
    fullCharPoly == factoredCharPolyDesc &&
    isZeroMat fullRem &&
    circRem == List.replicate 12 0 &&
    containsSubstr raw charpolyStr
  let schurOk :=
    schurSubstituteBassIhara fullCharPoly == bassIharaD_poly &&
    containsSubstr raw "\"exact_integer_squared_margin\": 3" &&
    containsSubstr raw "\"satisfies_graph_riemann_hypothesis\": true"
  let primesOk :=
    nw.getD 2 0 == 0 &&
    nw.getD 4 0 == 0 &&
    nw.getD 6 0 == 192 &&
    orientedPrimes nw 6 == 32 &&
    orientedPrimes nw 16 == 8196 &&
    orientedPrimes nw 20 == 105096 &&
    containsSubstr raw "\"LPRLPR_pitch_class_dual_faces\": 12" &&
    containsSubstr raw "\"LPLPLP_hexatonic_cycles\": 4" &&
    containsSubstr raw "\"oriented_primes\": 8196" &&
    containsSubstr raw "\"oriented_primes\": 105096"
  [ guardZeroViolations "vault_tradition_and_no_wiki" (if tradOk then 0 else 1)
  , guardNTetConnected 12 7 4
  , guardZeroViolations "full_12x12_faddeev_charpoly_vault_parity" (if charpolyOk then 0 else 1)
  , guardZeroViolations "bass_ihara_schur_and_margin_parity" (if schurOk then 0 else 1)
  , guardExactRamanujanMargin 5 8
  , guardZeroViolations "prime_cycles_and_16_hexagons_parity" (if primesOk then 0 else 1)
  ]

private def resolveVaultPath (args : List String) : IO (Option System.FilePath) := do
  match args with
  | [p] =>
    let fp := System.FilePath.mk p
    if ← fp.pathExists then return some fp else return none
  | _ =>
    let candidates :=
      [ System.FilePath.mk "data/sources/riemann_lattice_graph_rh_v1.json"
      , System.FilePath.mk "../../data/sources/riemann_lattice_graph_rh_v1.json"
      ]
    for fp in candidates do
      if ← fp.pathExists then return some fp
    return none

def main (args : List String) : IO UInt32 := do
  let some vaultPath ← resolveVaultPath args
    | do
        IO.eprintln "[FAIL] vault_file_missing: pass explicit path to riemann_lattice_graph_rh_v1.json"
        return 2

  let raw ← IO.FS.readFile vaultPath
  let verdicts := verifyVaultText raw

  IO.println "=== SCargoLean.RiemLattice Standalone Verification ==="
  for v in verdicts do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"

  -- Adversarial negative controls (must fail closed!)
  let poisonedCharpoly := raw.replace "2025" "2026"
  let neg1Failed := failedCompartments (verifyVaultText poisonedCharpoly) == ["full_12x12_faddeev_charpoly_vault_parity"]

  let poisonedWiki := raw.replace "\"verification_status\"" "\"poisoned_host\": \"synthetic.wikipedia.org\", \"verification_status\""
  let neg2Failed := failedCompartments (verifyVaultText poisonedWiki) == ["vault_tradition_and_no_wiki"]

  let neg24Disconnected := !(guardNTetConnected 24 14 8).passed && (guardNTetConnected 24 14 8).violationCount == 2

  let neg17Ramanujan := !(guardExactRamanujanMargin 820791 800000).passed
  let neg53Ramanujan := !(guardExactRamanujanMargin 815980 800000).passed
  let pos31Ramanujan := (guardExactRamanujanMargin 797852 800000).passed

  let negControls :=
    [ guardZeroViolations "neg_ctrl_poisoned_charpoly_rejected" (if neg1Failed then 0 else 1)
    , guardZeroViolations "neg_ctrl_wikipedia_url_rejected" (if neg2Failed then 0 else 1)
    , guardZeroViolations "neg_ctrl_24tet_disconnected_rejected" (if neg24Disconnected then 0 else 1)
    , guardZeroViolations "neg_ctrl_17tet_ramanujan_violation_rejected" (if neg17Ramanujan then 0 else 1)
    , guardZeroViolations "neg_ctrl_53tet_ramanujan_violation_rejected" (if neg53Ramanujan then 0 else 1)
    , guardZeroViolations "pos_ctrl_31tet_razor_boundary_accepted" (if pos31Ramanujan then 0 else 1)
    ]

  IO.println "=== Adversarial & Correspondence Boundary Controls ==="
  for v in negControls do
    let tag := if v.passed then "PASS" else "FAIL"
    IO.println s!"[{tag}] {v.compartment} (violations={v.violationCount})"

  let allVerdicts := verdicts ++ negControls ++ canonical12TETVerdicts
  if allCompartmentGuardsHold allVerdicts then
    IO.println s!"ALL {allVerdicts.length} LEAN ATOMIC GUARDS PASSED (0 violations)"
    return 0
  else
    IO.eprintln s!"FAILED COMPARTMENTS: {failedCompartments allVerdicts}"
    return 1
