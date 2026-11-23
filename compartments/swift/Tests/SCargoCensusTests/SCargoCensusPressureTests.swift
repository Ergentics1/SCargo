// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoCensus

@Suite("SCargo Swift 6.4 Arc 4 High-Mass Zone Census & UP-08 Provenance Verification")
struct SCargoCensusPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Pure-Swift census SHA-256 matches FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(censusSha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(censusSha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Arc 4 high-mass census passes all 5 guards (HG-1..HG-5) and rejects 6 negative controls")
    func censusVerifiesAll5GuardsAnd6Negatives() throws {
        let rep = try verifyArc4Census(repoRoot: repoRootURL())
        #expect(rep.allPassed)
        #expect(rep.hg1ProvenanceAndUp08Clean)
        #expect(rep.hg2Z2ExplicitDumpsValid)
        #expect(rep.hg3Z3DuplicateClustersValid)
        #expect(rep.hg4Z4DominatorHubValid)
        #expect(rep.hg5RankingAndNegativesValid)
        #expect(rep.ranking.count == 3)
        #expect(rep.negativeControlsRejected == 6)
    }

    @Test("UP-08 verbatim proof-body detector and duplicate-cluster accounting bounds fail closed")
    func up08AndClusterBoundsFailClosed() {
        #expect(containsVerbatimProofBody("{\"x\":\"private theorem foo : True := by trivial\"}"))
        #expect(!containsVerbatimProofBody("{\"fingerprint_sha256\":\"abc\",\"multiplicity\":3}"))
        #expect(clusterAccountingValid(multiplicity: 4, blockLines: 12, reclaimableLines: 36))
        #expect(!clusterAccountingValid(multiplicity: 1, blockLines: 12, reclaimableLines: 0))
        #expect(!clusterAccountingValid(multiplicity: 3, blockLines: 10, reclaimableLines: 30))
        #expect(censusRhoPpm(before: 1000, after: 750) == 750_000)
    }
}
