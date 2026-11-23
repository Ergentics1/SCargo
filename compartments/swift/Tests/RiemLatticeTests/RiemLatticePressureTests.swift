// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import RiemLattice
import SCargoModel
import Testing

@Suite("SCargo Swift 6.4 Import-Style Riemann Lattice & Graph-RH Pressure Tests")
struct RiemLatticePressureTests {
    private static func loadCanonicalVaultJSON() throws -> String {
        // Resolve relative to #filePath: compartments/swift/Tests/RiemLatticeTests/RiemLatticePressureTests.swift
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // RiemLatticeTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift
            .deletingLastPathComponent() // compartments
            .deletingLastPathComponent() // SCargo
        let vaultURL = repoRoot.appendingPathComponent("data/sources/riemann_lattice_graph_rh_v1.json")
        return try String(contentsOf: vaultURL, encoding: .utf8)
    }

    @Test("Canonical vault passes all 8 atomic Swift RIEM-LATTICE guards")
    func canonicalVaultPassesAll8Guards() throws {
        let raw = try Self.loadCanonicalVaultJSON()
        let verdicts = RiemLatticeVaultVerifier.evaluate(rawJSON: raw)
        #expect(verdicts.count == 8)
        let failed = verdicts.filter { !$0.passed }.map(\.compartment)
        #expect(failed.isEmpty)
    }

    @Test("Exact Z Faddeev-LeVerrier charpoly and Cayley-Hamilton zero remainder on 12-TET G_PLR")
    func exact12TETCharpolyAndCayleyHamilton() {
        let sys = NTetSystem.canonical12TET
        let (coeffs, remZero) = RiemLatticeEngine.faddeevLeVerrierExact(sys.gramMatrix())
        #expect(remZero)
        #expect(coeffs == [1, -36, 558, -4916, 27303, -100056, 245924, -404088, 435183, -295684, 118446, -24660, 2025])
    }

    @Test("Negative control: poisoned charpoly fails closed with explicit healing path")
    func poisonedCharpolyFailsClosed() throws {
        let raw = try Self.loadCanonicalVaultJSON()
        let poisoned = raw.replacingOccurrences(of: "2025", with: "2026")
        let verdicts = RiemLatticeVaultVerifier.evaluate(rawJSON: poisoned)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.map(\.compartment) == ["g_plr_exact_charpoly_over_Z"])
        #expect(failed.first?.healingAction != nil)
    }

    @Test("Negative control: poisoned prime-hexagon decomposition fails closed")
    func poisonedHexagonsFailsClosed() throws {
        let raw = try Self.loadCanonicalVaultJSON()
        let poisoned = raw.replacingOccurrences(
            of: "\"LPLPLP_hexatonic_cycles\": 4",
            with: "\"LPLPLP_hexatonic_cycles\": 5"
        )
        let verdicts = RiemLatticeVaultVerifier.evaluate(rawJSON: poisoned)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.map(\.compartment) == ["g_plr_prime_cycles_and_16_hexagons"])
    }

    @Test("Negative control: banned wiki domain fails closed")
    func poisonedWikipediaURLFailsClosed() throws {
        let raw = try Self.loadCanonicalVaultJSON()
        let poisoned = raw.replacingOccurrences(
            of: "\"verification_status\"",
            with: "\"poisoned_host\": \"synthetic.wikipedia.org\", \"verification_status\""
        )
        let verdicts = RiemLatticeVaultVerifier.evaluate(rawJSON: poisoned)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.map(\.compartment) == ["vault_tradition_and_provenance"])
    }

    @Test("Correspondence Principle N-TET regime boundary: 12/31 pass, 17/53 fail RH, 24 disconnects")
    func correspondenceNTetBoundaryPressureTest() throws {
        let l12 = try #require(NTetSystem.fromN(12).maxNontrivialLambdaSquared())
        #expect(abs(l12 - 5.0) < 1e-12)
        #expect(l12 < 8.0)

        let l17 = try #require(NTetSystem.fromN(17).maxNontrivialLambdaSquared())
        #expect(l17 > 8.0)

        let l53 = try #require(NTetSystem.fromN(53).maxNontrivialLambdaSquared())
        #expect(l53 > 8.0)

        let s24 = NTetSystem.fromN(24)
        #expect(!s24.isConnected)
        #expect(s24.maxNontrivialLambdaSquared() == nil)

        let l31 = try #require(NTetSystem.fromN(31).maxNontrivialLambdaSquared())
        #expect(l31 < 8.0 && l31 > 7.97)
    }

    @Test("Universal mutual centralizer holds across N-TET while 5-TET exposes M3+P5=5 pitch-class degeneracy")
    func mutualCentralizerAnd5TETDegeneracy() {
        for n in [5, 7, 12, 17, 19, 24, 31, 53] {
            let sys = NTetSystem.fromN(n)
            #expect(sys.mutualCentralizerViolations() == 0)
        }
        #expect(NTetSystem.canonical12TET.parsimonyViolations() == 0)
        // In 5-TET (P5=3, M3=2), M3 + P5 = 5 == 0 mod 5 so L maps a major triad onto the exact same 3 pitch classes!
        #expect(NTetSystem.fromN(5).parsimonyViolations() == 10)
    }
}
