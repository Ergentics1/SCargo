// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
@testable import SCargoGround

@Suite("SCargo Swift 6.4 Rung 2 Shared Ground Codec, Shrinking, Metamorphic & Parity Suite")
struct SCargoGroundPressureTests {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func extractU64Field(json: String, key: String) -> UInt64? {
        let needle = "\"\(key)\":"
        guard let range = json.range(of: needle) else {
            return nil
        }
        var idx = range.upperBound
        while idx < json.endIndex && (json[idx] == " " || json[idx] == "\t" || json[idx] == "\n" || json[idx] == "\r") {
            idx = json.index(after: idx)
        }
        let start = idx
        while idx < json.endIndex && json[idx] >= "0" && json[idx] <= "9" {
            idx = json.index(after: idx)
        }
        if start == idx {
            return nil
        }
        return UInt64(json[start..<idx])
    }

    @Test("Pure-Swift ground SHA-256 matches FIPS 180-4 test vectors")
    func sha256NISTVectors() {
        #expect(groundSha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(groundSha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("Rung 2 seeded corpus passes all 384 cases, 192 metamorphic pairs, and 4 malformed rejections")
    func seededCorpusAll384Pass() throws {
        let cfgURL = repoRootURL().appendingPathComponent("data/trials/rung2_fuzz_corpus_v1.json")
        let raw = try String(contentsOf: cfgURL, encoding: .utf8)
        let seed = try #require(extractU64Field(json: raw, key: "master_seed"))
        let cases = try #require(extractU64Field(json: raw, key: "cases_per_family"))
        let rep = runRung2ParitySuite(masterSeed: seed, casesPerFamily: Int(cases))
        #expect(rep.allPassed)
        #expect(rep.totalCases == 384)
        #expect(rep.dagCleanPassed == 64)
        #expect(rep.cycleShrunkMinimal == 64)
        #expect(rep.diamondDomPassed == 64)
        #expect(rep.deadLeavesPassed == 64)
        #expect(rep.wrapperAstPassed == 64)
        #expect(rep.metamorphicPairsPassed == 192)
        #expect(rep.malformedRejected == 4)
        #expect(rep.corpusDigestSha256.count == 64)
    }

    @Test("QuickCheck deterministic shrinker reduces cyclic graph to 1-edge-minimal cycle")
    func shrinkerReducesToMinimalCycle() {
        let g = GroundGraph(
            root: "A",
            modules: [
                GroundModule(name: "A", lines: 10, bytes: 100, imports: ["B", "C"], wrapperKind: .substantive),
                GroundModule(name: "B", lines: 10, bytes: 100, imports: ["C", "D"], wrapperKind: .substantive),
                GroundModule(name: "C", lines: 10, bytes: 100, imports: ["B"], wrapperKind: .substantive),
                GroundModule(name: "D", lines: 10, bytes: 100, imports: [], wrapperKind: .pureWrapper),
            ]
        )
        let shrunk = shrinkCyclicGraph(g)
        #expect(isEdgeMinimalCycle(shrunk))
        #expect(shrunk.edgeCount() == 2)
    }

    @Test("Canonical JSON codec roundtrip and MR-2 comment-invariance hold")
    func codecRoundtripAndWrapperInvariance() throws {
        let g = GroundGraph(
            root: "Main",
            modules: [
                GroundModule(name: "Main", lines: 10, bytes: 200, imports: ["B", "A"], wrapperKind: .substantive),
                GroundModule(name: "A", lines: 5, bytes: 50, imports: [], wrapperKind: .pureWrapper),
                GroundModule(name: "B", lines: 8, bytes: 80, imports: ["A"], wrapperKind: .reexportHub),
            ]
        )
        let enc = g.toCanonicalJSON()
        let dec = try decodeGroundGraphJSON(enc)
        #expect(dec.toCanonicalJSON() == enc)
        #expect(
            classifyWrapperText("import A\n")
                == classifyWrapperText("-- note\n\n/- block -/\nimport A\n")
        )
    }
}
