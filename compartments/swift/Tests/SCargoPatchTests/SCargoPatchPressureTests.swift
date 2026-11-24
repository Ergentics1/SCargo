// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoPatch

@Suite("SCargo Swift 6.4 Arc 6 AST Patch Generator & Unified-Diff Verifier")
struct SCargoPatchPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pure-Swift patch SHA-256 matches FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(patchSha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(patchSha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Arc 6 patch plan passes all 6 guards (PG-1..PG-6) and rejects 7 negative controls")
    func patchPlanVerifiesAll6GuardsAnd7Negatives() throws {
        let rep = try verifyArc6PatchPlan(repoRoot: repoRootURL())
        #expect(rep.allPassed)
        #expect(!rep.targetRepoMutationAllowed)
        #expect(rep.pg1ProvenanceZoneAUp08Clean)
        #expect(rep.pg2Bijection137AndHashesValid)
        #expect(rep.pg3ParetoRoundtripAndBoundsValid)
        #expect(rep.pg4SyntheticPatchSuiteValid)
        #expect(rep.pg5LeanPreflightModulesValid)
        #expect(rep.pg6NegativeControlsValid)
        #expect(rep.totalFiles == 137)
        #expect(rep.z2MaxLineAfter <= 280)
        #expect(rep.syntheticTransformsPassed == 4)
        #expect(rep.negativeControlsRejected == 7)
    }

    @Test("Pure in-memory unified-diff applier and AST safety guards fail closed")
    func unifiedDiffApplierAndAstGuardsFailClosed() throws {
        let (n, sha) = try runSyntheticPatchSuite()
        #expect(n == 4)
        #expect(sha.count == 64)

        let badDiff = "--- a/A.lean\n+++ b/A.lean\n@@ -1,1 +1,1 @@\n-nope\n+ok\n"
        #expect(throws: PatchError.self) {
            _ = try applyUnifiedDiff(oldSrc: "real\n", diffText: badDiff)
        }

        let layoutSrc = "module\ndef f := (@Field.toSemifield\n  Nat\n  by exact h)\n"
        #expect(throws: PatchError.self) {
            _ = try transformZ2BalancedCollapse(src: layoutSrc, wrapWidth: z2WrapWidth)
        }

        #expect(countFreeLocalVars("(@instHAdd Nat instAddNat)") == 0)
        #expect(countFreeLocalVars("(@Field.toSemifield K (@instField K))") > 0)
        #expect(throws: PatchError.self) {
            _ = try transformZ2ClosedCse(
                src: "module\n@[expose] public section\ndef x := (@Field.toSemifield K)\ndef y := (@Field.toSemifield K)\n",
                targetExpr: "(@Field.toSemifield K)",
                abbrevName: "_scargo_bad"
            )
        }
        #expect(throws: PatchError.self) {
            _ = try transformZ4PruneImports(
                src: "public import Req\n",
                transitivelyCovered: Set<String>(),
                toPrune: ["Req"]
            )
        }
    }
}
