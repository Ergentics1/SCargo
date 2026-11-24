-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness
import SCargoLean.GroundCodec
import SCargoLean.TransferAirlock
import SCargoLean.HighMassCensus
import SCargoLean.PreflightHarness
import SCargoLean.PatchVerifier

/-!
# SCargo Lean Compartment: Arc 7 G4–G5 CI Receipt Ingestor & Airlock Rehearsal Soundness

Pure-kernel Lean 4.36.0 formalization of:
1. Exact upstream `scripts/quick-check.py:80` eligibility rule (`1 <= roots <= 8`,
   `closureSize <= 2000`, AND `hasDeletions = false`).
2. Strict G5 release-gate acceptance (`fullBuild = true`, `buildExitCode = 0`,
   `leanKernelExit = 0`, `leanParanoidExit = 0`, `nanodaExit = 0`, exact 5
   `Challenge.lean` theorems, permitted 3-axiom subset, Zone A pins intact,
   fresh `baseHead`, and genuine `remoteAttested = true`).
3. Anti-theater (`PRIN-06`) proofs: `quick-check` cannot attest G5, deleted files
   cannot route to `quick-check`, `nanoda` failures reject G5, forbidden axioms
   reject G5, Zone A drift rejects G5, and rehearsals cannot spoof remote G5.
4. Correspondence Principle theorem proving Arc 7 smoothly contains Arc 6, Arc 5,
   Arc 4, Rung 3, Rung 2, and Rung 1 (`delta_logic = 0`).
-/

namespace SCargoLean.AirlockRehearsal

open SCargoLean
open SCargoLean.SweepWitness
open SCargoLean.GroundCodec
open SCargoLean.TransferAirlock
open SCargoLean.HighMassCensus
open SCargoLean.PreflightHarness
open SCargoLean.PatchVerifier

/-- Exact upstream `scripts/quick-check.py:80` small-runner eligibility predicate. -/
def quickCheckEligible (roots closureSize : Nat) (hasDeletions : Bool) : Bool :=
  !hasDeletions && decide (1 ≤ roots) && decide (roots ≤ 8) && decide (closureSize ≤ 2000)

/-- Upstream `scripts/quick-check.py:80`: any deleted `.lean` file MUST defer to `full_rh_build`. -/
theorem quick_check_rejects_deleted_files (roots closureSize : Nat) :
    quickCheckEligible roots closureSize true = false := by
  simp [quickCheckEligible]

/-- Upstream `scripts/quick-check.py:62`: closure `> 2000` MUST defer to `full_rh_build`. -/
theorem quick_check_rejects_large_closure (roots closureSize : Nat) (h : closureSize > 2000) :
    quickCheckEligible roots closureSize false = false := by
  unfold quickCheckEligible
  have hnot : ¬ (closureSize ≤ 2000) := by omega
  simp [hnot]

/-- Concrete witness: `SHARD-ZC2-01` (8 roots, 12 closure, in-place) passes, while `Z-C0` (deleted) and `Z-C4` (127,440 closure) defer. -/
theorem arc7_concrete_quick_check_eligibility :
    quickCheckEligible 8 12 false = true ∧
    quickCheckEligible 8 1594 true = false ∧
    quickCheckEligible 1 127440 false = false := by
  decide

/-- Full G5 release-gate attestation record matching `ci-build.py` + `comparator.json`. -/
structure G5ReleaseEvidence where
  fullBuild : Bool
  buildExitCode : Nat
  leanKernelExit : Nat
  leanParanoidExit : Nat
  nanodaExit : Nat
  allFiveTheoremsPresent : Bool
  axiomsSubsetPermitted : Bool
  zoneAPinsMatched : Bool
  baseHeadFresh : Bool
  remoteAttested : Bool
  deriving Repr, DecidableEq

/-- G5 release acceptance predicate (strict conjunction of all upstream release requirements). -/
def g5ReleaseAccepted (e : G5ReleaseEvidence) : Bool :=
  e.fullBuild &&
  decide (e.buildExitCode == 0) &&
  decide (e.leanKernelExit == 0) &&
  decide (e.leanParanoidExit == 0) &&
  decide (e.nanodaExit == 0) &&
  e.allFiveTheoremsPresent &&
  e.axiomsSubsetPermitted &&
  e.zoneAPinsMatched &&
  e.baseHeadFresh &&
  e.remoteAttested

/-- `scripts/QUICK-CHECKS.md:7`: a `quick-check` (`fullBuild = false`) can NEVER attest G5 release. -/
theorem quick_check_cannot_attest_g5 (e : G5ReleaseEvidence) (h : e.fullBuild = false) :
    g5ReleaseAccepted e = false := by
  simp [g5ReleaseAccepted, h]

/-- `UP-03`: a non-zero `nanoda_bin` exit code ALWAYS rejects G5 even if Lean paranoid passes. -/
theorem nanoda_failure_rejects_g5 (e : G5ReleaseEvidence) (h : e.nanodaExit ≠ 0) :
    g5ReleaseAccepted e = false := by
  simp [g5ReleaseAccepted, h]

/-- `UP-02`: any axiom outside `{propext, Quot.sound, Classical.choice}` ALWAYS rejects G5. -/
theorem forbidden_axiom_rejects_g5 (e : G5ReleaseEvidence) (h : e.axiomsSubsetPermitted = false) :
    g5ReleaseAccepted e = false := by
  simp [g5ReleaseAccepted, h]

/-- `UP-04`/`UP-05`: any Zone A SHA-256 pin drift ALWAYS rejects G5. -/
theorem zone_a_pin_drift_rejects_g5 (e : G5ReleaseEvidence) (h : e.zoneAPinsMatched = false) :
    g5ReleaseAccepted e = false := by
  simp [g5ReleaseAccepted, h]

/-- `PRIN-06` anti-theater: a local rehearsal (`remoteAttested = false`) can NEVER spoof remote G5. -/
theorem rehearsal_cannot_spoof_remote_g5 (e : G5ReleaseEvidence) (h : e.remoteAttested = false) :
    g5ReleaseAccepted e = false := by
  simp [g5ReleaseAccepted, h]

/-- Arc 7 Airlock Rehearsal Receipt embedding Arc 6 (and transitively Arc 5..Rung 1). -/
structure Arc7RehearsalReceipt where
  arc6 : Arc6PatchReceipt
  zoneAPinsVerified : Bool
  quickCheckDiagnosticsValid : Bool
  fullBuildReceiptValid : Bool
  comparatorAxiomsValid : Bool
  rehearsalModeHonest : Bool
  negativeControlsRejected : Nat
  requiredNegativeControls : Nat
  deriving Repr, DecidableEq

def arc7AllPass (r : Arc7RehearsalReceipt) : Bool :=
  arc6AllPass r.arc6 &&
  r.zoneAPinsVerified &&
  r.quickCheckDiagnosticsValid &&
  r.fullBuildReceiptValid &&
  r.comparatorAxiomsValid &&
  r.rehearsalModeHonest &&
  decide (r.negativeControlsRejected ≥ r.requiredNegativeControls)

/-- Correspondence Principle (Rung 1 -> ... -> Arc 6 -> Arc 7): smooth containment (`delta_logic = 0`). -/
theorem arc7_smoothly_contains_all_prior_rungs (r : Arc7RehearsalReceipt)
    (h : arc7AllPass r = true) :
    arc6AllPass r.arc6 = true ∧
    arc5AllPass r.arc6.arc5 = true ∧
    arc4AllPass r.arc6.arc5.arc4 = true ∧
    rung3AllPass r.arc6.arc5.arc4.rung3 = true ∧
    rung2AllPass r.arc6.arc5.arc4.rung3.rung2 = true ∧
    suiteAllPass r.arc6.arc5.arc4.rung3.rung2.rung1Witnesses = true := by
  simp [arc7AllPass, Bool.and_eq_true] at h
  have ha6 : arc6AllPass r.arc6 = true := h.1.1.1.1.1.1
  have hprior := arc6_smoothly_contains_all_prior_rungs r.arc6 ha6
  exact ⟨ha6, hprior.1, hprior.2.1, hprior.2.2.1, hprior.2.2.2.1, hprior.2.2.2.2⟩

end SCargoLean.AirlockRehearsal
