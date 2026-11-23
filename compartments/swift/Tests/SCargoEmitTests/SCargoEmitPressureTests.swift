// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoEmit

@Suite("SCargo Swift 6.4 Arc 5 Pre-Flight Emitter & UP-07 Dual-Route Verification")
struct SCargoEmitPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pure-Swift emitter SHA-256 matches FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(emitSha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(emitSha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Arc 5 pre-flight emitter passes all 6 guards (EG-1..EG-6) and rejects 6 negative controls")
    func emitterVerifiesAll6GuardsAnd6Negatives() throws {
        let rep = try verifyArc5Emitter(repoRoot: repoRootURL())
        #expect(rep.allPassed)
        #expect(!rep.targetRepoMutationAllowed)
        #expect(rep.eg1ProvenanceZoneAUp08Clean)
        #expect(rep.eg2DualRouteUp07Sound)
        #expect(rep.eg3ShardConservationAndHashesValid)
        #expect(rep.eg4SyntheticDiffsValid)
        #expect(rep.eg5LeanPreflightModulesValid)
        #expect(rep.eg6NegativeControlsValid)
        #expect(rep.totalShards == 24)
        #expect(rep.totalFullBundles == 4)
        #expect(rep.syntheticTransformsPassed == 4)
        #expect(rep.negativeControlsRejected == 6)
    }

    @Test("Synthetic rewriters, delimiter guards, and UP-07 route classifier fail closed")
    func syntheticRewritersAndUp07FailClosed() throws {
        let (n, sha) = try runSyntheticDiffSuite()
        #expect(n == 4)
        #expect(sha.count == 64)
        #expect(classifyUP07Route(changedRoots: 8, projectAncestors: 4) == "quick_check")
        #expect(classifyUP07Route(changedRoots: 1, projectAncestors: 127_439) == "full_rh_build")
        #expect(classifyUP07Route(changedRoots: 9, projectAncestors: 0) == "full_rh_build")
        #expect(delimitersBalanced("((a + b) * [c])"))
        #expect(!delimitersBalanced("((a + b)"))

        let polySig = BinderSig(explicitCount: 1, implicitCount: 1, instanceCount: 0, universeParams: 1)
        #expect(throws: EmitError.self) {
            _ = try rewriteZ1ASynthetic(src: "theorem x := by\n  exact y\n", wrapperSig: polySig, targetSig: polySig, targetSymbol: "y")
        }
        #expect(throws: EmitError.self) {
            _ = try rewriteZ2Synthetic(src: "def f := 1\n", defeqRflCertified: false)
        }
        #expect(throws: EmitError.self) {
            _ = try rewriteZ4PruneRedundantImports(src: "public import Req\n", transitivelyCovered: Set<String>(), toPrune: ["Req"])
        }
    }
}
