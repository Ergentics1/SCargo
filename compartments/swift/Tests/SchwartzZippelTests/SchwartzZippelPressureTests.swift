// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import Testing
import SCargoModel
import SchwartzZippel

@Suite("Schwartz-Zippel x Neo-Riemannian PLR Coupled Lattice Pressure Tests")
struct SchwartzZippelPressureTests {
    private func loadCanonicalVaults() throws -> (szRaw: String, rlRaw: String) {
        let here = URL(fileURLWithPath: #filePath)
        let repoRoot = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let szURL = repoRoot.appendingPathComponent("data/sources/schwartz_zippel_research_v1.json")
        let rlURL = repoRoot.appendingPathComponent("data/sources/riemann_lattice_graph_rh_v1.json")
        let szRaw = try String(contentsOf: szURL, encoding: .utf8)
        let rlRaw = try String(contentsOf: rlURL, encoding: .utf8)
        return (szRaw, rlRaw)
    }

    @Test("Canonical coupled vaults pass all 9 atomic fail-closed guards")
    func canonicalVaultsPassAll9Guards() throws {
        let (szRaw, rlRaw) = try loadCanonicalVaults()
        let verdicts = SZCoupledVerifier.evaluate(szRawJSON: szRaw, rlRawJSON: rlRaw)
        #expect(verdicts.count == 9)
        let failed = verdicts.filter { !$0.passed }.map(\.compartment)
        #expect(failed.isEmpty)
    }

    @Test("Correspondence Principle: binary vs composite vs cyclotomic torus vs prime field")
    func correspondencePrincipleRegimeBoundaries() {
        // Binary grid {0,1} stalls at D = 2 (z^2 - z vanishes identically)
        #expect(SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 1, safeGridSize: 2).passed)
        #expect(!SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 2, safeGridSize: 2).passed)
        for z in [UInt64(0), 1] {
            #expect((z * z + 13 - z) % 13 == 0)
        }

        // Composite ring Z/12Z collapses safe grid capacity back to p_min(12) = 2
        #expect(!SZCoupledVerifier.guardPrimeIntegralDomain(12).passed)
        #expect(FieldMath.smallestPrimeFactor(12) == 2)
        #expect(SZCoupledVerifier.guardConditionDGrid(modulus: 12, grid: [0, 1]).passed)
        #expect(!SZCoupledVerifier.guardConditionDGrid(modulus: 12, grid: [0, 1, 2]).passed)

        // Z/6Z (4/6 roots) & Z/30Z (8/30 roots) violate classical SZ; Condition (D) repairs Z/6Z on {0,1}
        let z6Roots = (0..<UInt64(6)).filter { ($0 * ($0 + 5)) % 6 == 0 }.count
        let z30Roots = (0..<UInt64(30)).filter { ($0 * ($0 + 29)) % 30 == 0 }.count
        #expect(z6Roots == 4)
        #expect(z30Roots == 8)
        #expect(SZCoupledVerifier.guardConditionDGrid(modulus: 6, grid: [0, 1]).passed)
        #expect(!SZCoupledVerifier.guardConditionDGrid(modulus: 6, grid: [0, 1, 3, 4]).passed)

        // Cyclotomic torus mu_12 in F_13 holds through D=11 and stalls sharply at D=12 (z^12 - 1)
        let torus13 = CyclotomicPlrTorus(p: 13, zeta12: 2)
        #expect(torus13 != nil)
        #expect(torus13?.verifyAll24Triads() == true)
        #expect(SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 11, safeGridSize: 12).passed)
        #expect(!SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 12, safeGridSize: 12).passed)
        for r in 0..<UInt64(12) {
            let z = FieldMath.modPow(2, r, 13)
            #expect((FieldMath.modPow(z, 12, 13) + 13 - 1) % 13 == 0)
        }
        // Full F_13 stalls at D=13 (Frobenius z^13 - z)
        for z in 0..<UInt64(13) {
            #expect((FieldMath.modPow(z, 13, 13) + 13 - z) % 13 == 0)
        }
    }

    @Test("Coupled non-abelian holonomy and homology-filtered cycle sieving")
    func coupledHolonomyAndCycleSieving() {
        let torus = CyclotomicPlrTorus(p: 65521, zeta12: 53059)
        #expect(torus != nil)
        guard let t = torus else { return }
        #expect(t.verifyAll24Triads())

        let p0 = t.embedTriad(root: 0, isMajor: true)
        #expect(t.applyWordBilinear([.pOp, .lOp], to: p0) != t.applyWordBilinear([.lOp, .pOp], to: p0))

        // Abelianization k=0 collapses PL and LP; faithful rho_1 separates them
        #expect(
            DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 0, word: [.pOp, .lOp])
                == DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 0, word: [.lOp, .pOp])
        )
        let mPL = DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 1, word: [.pOp, .lOp])
        let mLP = DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 1, word: [.lOp, .pOp])
        #expect(mPL != mLP)
        var rng = SplitMix64(seed: 42)
        let v = (rng.nextMod(65521), rng.nextMod(65521))
        #expect(mPL.mulVec(v, mod: 65521) != mLP.mulVec(v, mod: 65521))

        let sieve = GPLRBridge.sieveLen6Cycles()
        #expect(sieve.totalWalks == 192)
        #expect(sieve.contractibleWalks == 144)
        #expect(sieve.nonContractibleWalks == 48)
        #expect(sieve.unorientedLPRLPRFaces == 12)
        #expect(sieve.unorientedLPLPLPHexatonic == 4)
    }

    @Test("Non-backtracking Ramanujan mixing beats SRW and rejects 17-TET")
    func ramanujanMixingBeatsSRWAndRejects17Tet() {
        let rep12 = HashimotoMixing.analyze(nTet: 12, m3: 4, minor3: 3, steps: 20)
        let rep17 = HashimotoMixing.analyze(nTet: 17, m3: 5, minor3: 5, steps: 20)

        #expect(SZCoupledVerifier.guardRamanujanNBMixing(rep12).passed)
        #expect(!SZCoupledVerifier.guardRamanujanNBMixing(rep17).passed)
        #expect(abs(rep12.nbIharaNontrivialRate - (1.0 / sqrt(2.0))) < 1e-9)
        #expect(abs(rep12.srwNontrivialRate - (sqrt(5.0) / 3.0)) < 1e-9)
        #expect(rep17.tvStep20NB / rep12.tvStep20NB > 20.0)
    }

    @Test("Direct G_PLR bridge: det=45, perm=113, char 3/5 all-ones false negative, Edmonds & Bass-Ihara PIT")
    func directGPLRBridgeAndEdmondsPIT() {
        #expect(GPLRBridge.exactDetBareiss() == 45)
        #expect(GPLRBridge.exactPerm() == 113)

        let bMat = GPLRBridge.biadjacencyMatrix()
        #expect(GPLRBridge.detModPrime(bMat, p: 3) == 0)
        #expect(GPLRBridge.detModPrime(bMat, p: 5) == 0)
        #expect(GPLRBridge.detModPrime(bMat, p: 13) == 45 % 13)

        #expect(GPLRBridge.edmondsPIT(p: 65521, trials: 4, seed: 777) == true)
        #expect(GPLRBridge.edmondsPIT(p: 12, trials: 4, seed: 777) == nil)

        for u in [UInt64(3), 17, 511, 12345] {
            let exact = GPLRBridge.bassIharaDMatrixModP(u: u, p: 65521)
            let factored = GPLRBridge.bassIharaDFactoredModP(u: u, p: 65521)
            #expect(exact == factored)
            #expect(exact != (factored + 1) % 65521)
        }
    }

    @Test("Negative controls: poisoned vaults, wiki URLs, and corrupted Gram matrices fail closed")
    func negativeControlsFailClosed() throws {
        let (szRaw, rlRaw) = try loadCanonicalVaults()

        let p1 = szRaw.replacingOccurrences(
            of: "\"exact_perm_B_perfect_matchings\": 113",
            with: "\"exact_perm_B_perfect_matchings\": 114"
        )
        let f1 = SZCoupledVerifier.evaluate(szRawJSON: p1, rlRawJSON: rlRaw)
            .filter { !$0.passed }.map(\.compartment)
        #expect(f1 == ["g_plr_edmonds_and_bass_ihara_pit_bridge"])

        let p2 = szRaw.replacingOccurrences(
            of: "\"contractible_walks\": 144",
            with: "\"contractible_walks\": 140"
        )
        let f2 = SZCoupledVerifier.evaluate(szRawJSON: p2, rlRawJSON: rlRaw)
            .filter { !$0.passed }.map(\.compartment)
        #expect(f2 == ["coupled_cycle_sieve_len6_cross_vault"])

        let p3 = szRaw.replacingOccurrences(
            of: "\"tradition_id\": \"PIT-SZ\"",
            with: "\"tradition_id\": \"PIT-SZ\", \"poisoned_host\": \"synthetic.wikipedia.org\""
        )
        let f3 = SZCoupledVerifier.evaluate(szRawJSON: p3, rlRawJSON: rlRaw)
            .filter { !$0.passed }.map(\.compartment)
        #expect(f3 == ["vault_tradition_and_provenance"])

        // Corrupted Gram matrix rejected by Freivalds; composite modulus rejected fail-closed
        let bMat = GPLRBridge.biadjacencyMatrix()
        var bt = Array(repeating: Array(repeating: UInt64(0), count: 12), count: 12)
        var gram = Array(repeating: Array(repeating: UInt64(0), count: 12), count: 12)
        for i in 0..<12 { for j in 0..<12 { bt[j][i] = bMat[i][j] } }
        for i in 0..<12 {
            for j in 0..<12 {
                for k in 0..<12 { gram[i][j] = (gram[i][j] + bMat[i][k] * bt[k][j]) % 65521 }
            }
        }
        gram[0][0] = (gram[0][0] + 1) % 65521
        #expect(GPLRBridge.freivaldsVerify(a: bMat, b: bt, c: gram, p: 65521, trials: 4, seed: 12345) == false)
        #expect(GPLRBridge.freivaldsVerify(a: bMat, b: bt, c: gram, p: 12, trials: 4, seed: 12345) == nil)
    }

    @Test("Constraint arity, global degree boundary, and low-entropy randomness budget")
    func constraintArityAndLowEntropyBudget() {
        // Linear combination of arity-3 constraints keeps D=3 < 12 on mu_12
        #expect(SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 3, safeGridSize: 12).passed)
        // Product of 4 arity-3 constraints hits D=12 >= 12 (stalls on mu_12)
        #expect(!SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 12, safeGridSize: 12).passed)
        // Lifting to F_65521 restores D=12 < 65521
        #expect(SZCoupledVerifier.guardNonVacuousDegree(globalDegree: 12, safeGridSize: 65521).passed)

        for k in [4, 8, 16, 32] {
            let indepBits = Double(k) * log2(24.0)
            let nbBits = log2(24.0) + Double(k - 1)
            #expect(nbBits * 2.4 < indepBits)
        }
    }
}
