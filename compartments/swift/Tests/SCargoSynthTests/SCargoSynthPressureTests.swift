// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoSynth

@Suite("SCargo Swift 6.4 Arc 8 Adaptive 5-Zone AST Synthesis & Min-Closure Bin-Packing")
struct SCargoSynthPressureTests {
    private static func scargoRoot() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    @Test("Pure-Swift synth SHA-256 matches FIPS 180-4 test vector")
    func sha256VectorMatches() {
        #expect(
            synthSha256Hex(Array("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("All 8 Arc 8 adversarial negative controls fail closed")
    func negativeControlsFailClosed() {
        #expect(runEightNegativeControls() == 8)
        #expect(isZoneAPath("src/Challenge.lean"))
        #expect(isZoneAPath("lake-manifest.json"))
        #expect(!isZoneAPath("src/CompanionTheory/Example.lean"))
    }

    @Test("Arc 8 adaptive 5-zone synth plan passes SG-1..SG-7 and monotone bin-packing lift")
    func arc8SynthPlanVerifiesCleanly() throws {
        let r = try verifyArc8Synth(scargoRoot: Self.scargoRoot())
        #expect(r.allPassed)
        #expect(r.sg1BaselineZoneAUp08)
        #expect(r.sg2FiveZoneRoundtripPareto)
        #expect(r.sg3Z1aDualModeSound)
        #expect(r.sg4Z2AdaptiveWidthSound)
        #expect(r.sg5Z3AcyclicClustersSound)
        #expect(r.sg6AdaptiveBinPackingSound)
        #expect(r.sg7NegativesRejected == 8)
        #expect(r.totalFiles >= 500)
        #expect(r.adaptiveQuickCheckFiles >= r.naiveQuickCheckFiles)
        #expect(isValidHex64(r.synthDigestSha256))
    }
}
