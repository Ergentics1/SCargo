// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoSweep

@Suite("SCargo Swift 6.4 Rung 1 13-Witness Sweep, Blind-Spots & Stratified RCT-R1")
struct SCargoSweepPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pure-Swift SHA-256 matches NIST FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(PureSHA256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(PureSHA256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Live SCargo self-sweep passes all 13 independent Proof-Carrying Witnesses")
    func liveSelfSweepAll13Pass() throws {
        let root = repoRootURL()
        let witnesses = try runLiveSelfSweep(
            repoRoot: root,
            policyURL: root.appendingPathComponent("data/manifests/swe_sweep_policy_v1.json"),
            fixturesURL: root.appendingPathComponent("data/fixtures/rung1_negative_controls_v1.json")
        )
        #expect(witnesses.count == 13)
        for w in witnesses {
            #expect(w.passed, "Witness \(w.witness_compartment_id) failed: \(w.findings)")
            #expect(w.policy_digest.count == 64)
            #expect(!w.input_content_digests.isEmpty)
        }
    }

    @Test("All 21 poisoned fixtures killed, 5 clean controls pass, and PRIN-06 copy-invariant")
    func qualify21Poisoned5CleanCopyInvariant() throws {
        let root = repoRootURL()
        let sum = try qualifyNegativeControls(
            policyURL: root.appendingPathComponent("data/manifests/swe_sweep_policy_v1.json"),
            fixturesURL: root.appendingPathComponent("data/fixtures/rung1_negative_controls_v1.json")
        )
        #expect(sum.totalPoison == 21)
        #expect(sum.poisonKilled == 21)
        #expect(sum.totalClean == 5)
        #expect(sum.cleanPassed == 5)
        #expect(sum.copyInvariant)
    }

    @Test("Stratified RCT-R1 promotes all 7 blind-spot and seam strata")
    func stratifiedRctR1PromotesAll7() throws {
        let root = repoRootURL()
        let rep = try runRctR1(
            policyURL: root.appendingPathComponent("data/manifests/swe_sweep_policy_v1.json"),
            configURL: root.appendingPathComponent("data/trials/rct_r1_config_v1.json")
        )
        #expect(rep.strata.count == 7)
        #expect(rep.allStrataPromoted)
        for s in rep.strata {
            #expect(s.treatmentKills == 32)
            #expect(s.varghaDelaneyA12 >= 0.95)
            #expect(s.wilcoxonPTwoTailed < 0.01)
            if !s.isProbabilistic {
                #expect(s.treatmentFalsePositives == 0)
            }
        }
    }

    @Test("Direct D/R/P/Seam blind-spot guards reject poisoned inputs fail-closed")
    func directBlindSpotPressureChecks() throws {
        let root = repoRootURL()
        let policyData = try Data(contentsOf: root.appendingPathComponent("data/manifests/swe_sweep_policy_v1.json"))
        let t = try BlindSpotThresholds.decode(fromPolicyData: policyData)

        #expect(!evaluateFpDeterminism([1e16, 1.0, -1e16, 0.5], exactReference: 1.5, thresholds: t).passed)
        #expect(!evaluateSpdMatrix([[1.0, 2.0], [2.0, 1.0]], thresholds: t).passed)
        #expect(!evaluateStateInvariants([0.5, .nan, 0.5], cellAbsBound: 5.0, aggregateAbsCap: 1.0, requireProbSimplex: true, thresholds: t).passed)
        #expect(!evaluateStateInvariants([4.0, 4.0, 4.0], cellAbsBound: 5.0, aggregateAbsCap: 10.0, requireProbSimplex: false, thresholds: t).passed)

        let badEst = RawProbEstimate(
            pointEstimate: 0.1, calibrated: false, inDomain: false,
            oodMahalanobis: 5.0, sampleCount: 50, actuatorBypassedCertificate: false
        )
        #expect(admitPToD(badEst, thresholds: t) == nil)
        #expect(abs(dkwBound(n: 256, alpha: 0.01) - 0.10173) < 1e-4)
        let (lo, hi) = clopperPearsonCI(k: 32, n: 32, alpha: 0.01)
        #expect(lo > 0.80 && abs(hi - 1.0) < 1e-12)
        let (_, p, a12) = wilcoxonMannWhitneyA12(control: Array(repeating: 0.0, count: 32), treatment: Array(repeating: 1.0, count: 32))
        #expect(abs(a12 - 1.0) < 1e-12 && p < 1e-10)
    }
}
