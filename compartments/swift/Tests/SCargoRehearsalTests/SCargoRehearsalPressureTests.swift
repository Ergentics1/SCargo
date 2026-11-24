// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoRehearsal

@Suite("SCargo Swift 6.4 Arc 7 G4-G5 CI Receipt Ingestor & Airlock Rehearsal")
struct SCargoRehearsalPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pure-Swift rehearsal SHA-256 matches FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(rehearsalSha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(rehearsalSha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Arc 7 G4-G5 airlock rehearsal passes all 6 guards (RG-1..RG-6) and rejects 8 negative controls")
    func rehearsalVerifiesAll6GuardsAnd8Negatives() throws {
        let rep = try verifyArc7Rehearsal(repoRoot: repoRootURL())
        #expect(rep.allPassed)
        #expect(rep.rehearsalMode)
        #expect(!rep.remoteCiAttestation)
        #expect(!rep.targetRepoMutationAllowed)
        #expect(rep.rg1ZoneAPinsAndUp08Clean)
        #expect(rep.rg2QuickCheckAndDeferralValid)
        #expect(rep.rg3CiBuildReceiptValid)
        #expect(rep.rg4G5ComparatorAndAxiomsValid)
        #expect(rep.rg5Arc6BindingAndHonestyValid)
        #expect(rep.rg6NegativeControlsValid)
        #expect(rep.quickCheckEligibleShards == 3)
        #expect(rep.fullBuildDeferredShards == 15)
        #expect(rep.linkedArc6Files == 137)
        #expect(rep.linkedArc6SavedLines == 32166)
        #expect(rep.negativeControlsRejected == 8)
    }

    @Test("Upstream quick-check.py:80 deletion deferral and G5 anti-spoof guards fail closed")
    func upstreamRulesAndAntiSpoofFailClosed() throws {
        #expect(classifyUpstreamQuickCheck(changedRoots: 8, closureModules: 12, hasDeletedFiles: false).0 == "quick_check")
        #expect(classifyUpstreamQuickCheck(changedRoots: 8, closureModules: 12, hasDeletedFiles: true).0 == "full_rh_build")
        #expect(classifyUpstreamQuickCheck(changedRoots: 1, closureModules: 127_440, hasDeletedFiles: false).0 == "full_rh_build")
        let spoof = try parseRehearsalJSON(
            "{\"rehearsal_mode\":true,\"remote_ci_attestation\":true,\"remote_workflow_run_id\":42,\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}"
        )
        #expect(throws: RehearsalError.self) {
            try validateG5ComparatorReceipt(spoof, requireRemoteAttestation: true)
        }
        #expect(throws: RehearsalError.self) {
            try validateG5ComparatorReceipt(spoof, requireRemoteAttestation: false)
        }
    }
}
