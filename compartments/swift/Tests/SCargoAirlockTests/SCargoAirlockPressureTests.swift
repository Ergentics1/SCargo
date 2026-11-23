// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoAirlock

@Suite("SCargo Swift 6.4 Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock")
struct SCargoAirlockPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pure-Swift airlock SHA-256 matches FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(airlockSha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(airlockSha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Clean-room Rung 3 airlock qualifies all 3 staged packages and rejects 7 negative controls")
    func airlockQualifiesAll3PackagesAndRejects7Negatives() throws {
        let rep = try runRung3Airlock(repoRoot: repoRootURL())
        #expect(rep.allPassed)
        #expect(!rep.targetRepoMutationAllowed)
        #expect(rep.ag1ZoneAClean)
        #expect(rep.ag2ConservationExact)
        #expect(rep.ag3ParetoAndRctPassed)
        #expect(rep.ag4Up07BatchesAndAxiomsClean)
        #expect(rep.ag5SyntheticTransformsPassed)
        #expect(rep.packages.count == 3)
        #expect(rep.packages[0].eligibleModules == 112)
        #expect(rep.packages[0].batchCount == 14)
        #expect(rep.packages[1].eligibleModules == 46)
        #expect(rep.packages[1].batchCount == 6)
        #expect(rep.packages[2].eligibleModules == 30)
        #expect(rep.packages[2].batchCount == 4)
        #expect(rep.multiDeclProtectedCount == 30)
        #expect(rep.lineageTargetsVerified == 15)
        #expect(rep.negativeControlsRejected == 7)
    }

    @Test("Airlock negative controls fail closed on Zone A touch, multi-decl collapse, custom axiom, and inflation")
    func airlockNegativeControlsFailClosed() {
        let za: Set<String> = ["src/Main.lean", "lakefile.toml"]
        #expect(touchesZoneA(["src/Main.lean"], zoneA: za))
        #expect(!touchesZoneA(["src/Development/Foo.lean"], zoneA: za))
        #expect(!strategyBSafeGuard(declCount: 3, pairedImplExists: true, importsSubsetOfImpl: true, touchesCore: false))
        #expect(!strategyBSafeGuard(declCount: 1, pairedImplExists: true, importsSubsetOfImpl: false, touchesCore: false))
        #expect(!strategyBSafeGuard(declCount: 1, pairedImplExists: true, importsSubsetOfImpl: true, touchesCore: true))
        #expect(strategyBSafeGuard(declCount: 1, pairedImplExists: true, importsSubsetOfImpl: true, touchesCore: false))

        let permitted: Set<String> = ["propext", "Quot.sound", "Classical.choice"]
        #expect(!axiomsPermitted(["propext", "badAxiom"], permitted: permitted))
        #expect(axiomsPermitted(["propext", "Quot.sound"], permitted: permitted))

        let b = MassVector(files: 10, lines: 100, bytes: 1000)
        #expect(!b.isParetoReduction(MassVector(files: 10, lines: 101, bytes: 900)))
        #expect(b.isParetoReduction(MassVector(files: 10, lines: 90, bytes: 900)))
    }

    @Test("Synthetic clean-room transforms, UP-07 batch partitioning, and exact Vargha-Delaney A12 hold")
    func syntheticTransformsBatchingAndA12() {
        #expect(verifySyntheticCleanRoomTransforms())
        let mods = (0..<19).map { String(format: "M%02d", $0) }
        let batches = splitUp07Batches(mods, cap: 8)
        #expect(batches.count == 3)
        #expect(batches[0].count == 8)
        #expect(batches[1].count == 8)
        #expect(batches[2].count == 3)
        #expect(varghaDelaneyA12BpsVsZeroControl([10, 20, 0]) == 8333)
    }
}
