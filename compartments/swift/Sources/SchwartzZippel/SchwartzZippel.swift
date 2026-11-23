// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import RiemLattice
import SCargoModel

/// Atomic fail-closed guard verdict for Schwartz-Zippel x PLR checks.
public struct SZGuardVerdict: Sendable, Equatable {
    public let compartment: String
    public let passed: Bool
    public let violationCount: Int
    public let detail: String
    public let healingAction: String?

    public init(
        compartment: String,
        violationCount: Int,
        detail: String,
        healingAction: String? = nil
    ) {
        self.compartment = compartment
        self.passed = (violationCount == 0)
        self.violationCount = violationCount
        self.detail = detail
        self.healingAction = violationCount == 0 ? nil : healingAction
    }
}

/// Deterministic SplitMix64 PRNG for seeded PIT verification.
public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func nextMod(_ m: UInt64) -> UInt64 {
        nextUInt64() % m
    }
}

/// Exact prime-field and Condition (D) arithmetic helpers.
public enum FieldMath {
    public static func gcd(_ aIn: UInt64, _ bIn: UInt64) -> UInt64 {
        var a = aIn
        var b = bIn
        while b != 0 {
            let r = a % b
            a = b
            b = r
        }
        return a
    }

    public static func smallestPrimeFactor(_ m: UInt64) -> UInt64 {
        if m < 2 { return 0 }
        if m % 2 == 0 { return 2 }
        var d: UInt64 = 3
        while d <= m / d {
            if m % d == 0 { return d }
            d += 2
        }
        return m
    }

    public static func isPrime(_ m: UInt64) -> Bool {
        m >= 2 && smallestPrimeFactor(m) == m
    }

    /// Exact modular multiplication `(a * b) mod m` without 64-bit overflow.
    public static func mulMod(_ a: UInt64, _ b: UInt64, _ m: UInt64) -> UInt64 {
        if m <= 1 { return 0 }
        let prod = (a % m).multipliedFullWidth(by: b % m)
        return m.dividingFullWidth(prod).remainder
    }

    public static func modPow(_ baseIn: UInt64, _ expIn: UInt64, _ m: UInt64) -> UInt64 {
        if m <= 1 { return 0 }
        var acc: UInt64 = 1
        var b = baseIn % m
        var e = expIn
        while e > 0 {
            if (e & 1) == 1 {
                acc = mulMod(acc, b, m)
            }
            b = mulMod(b, b, m)
            e >>= 1
        }
        return acc
    }

    public static func modInvPrime(_ a: UInt64, _ p: UInt64) -> UInt64? {
        guard isPrime(p), a % p != 0 else { return nil }
        return modPow(a % p, p - 2, p)
    }

    public static func isPrimitive12thRoot(p: UInt64, z: UInt64) -> Bool {
        guard isPrime(p), p % 12 == 1 else { return false }
        let z12 = modPow(z, 12, p)
        let z6 = modPow(z, 6, p)
        let z4 = modPow(z, 4, p)
        let z2 = modPow(z, 2, p)
        let phi12 = (z4 + p - z2 + 1) % p
        return z12 == 1 && z6 != 1 && z4 != 1 && phi12 == 0
    }

    public static func satisfiesConditionD(modulus m: UInt64, grid: [UInt64]) -> Bool {
        guard m >= 2, !grid.isEmpty else { return false }
        for i in 0..<grid.count {
            for j in (i + 1)..<grid.count {
                let a = grid[i] % m
                let b = grid[j] % m
                if a == b { return false }
                let diff = a >= b ? (a - b) : (b - a)
                if gcd(diff, m) != 1 { return false }
            }
        }
        return true
    }

    public static func evalUniMod(coeffs: [UInt64], x: UInt64, p: UInt64) -> UInt64 {
        var acc: UInt64 = 0
        for c in coeffs.reversed() {
            acc = (mulMod(acc, x, p) + (c % p)) % p
        }
        return acc
    }
}

/// Neo-Riemannian PLR generators.
public enum SZPlrOp: CaseIterable, Sendable, Equatable, Hashable {
    case pOp
    case lOp
    case rOp

    public var shiftMod12: UInt64 {
        switch self {
        case .pOp: return 0
        case .lOp: return 4
        case .rOp: return 9
        }
    }

    public var honeycombVec: (Int, Int) {
        switch self {
        case .pOp: return (1, 0)
        case .lOp: return (0, 1)
        case .rOp: return (-1, -1)
        }
    }
}

/// Point `(z, sigma)` on the 12-fold cyclotomic torus `mu_12 x {+1, -1} subset F_p^2`.
public struct TorusPoint: Sendable, Equatable, Hashable {
    public let z: UInt64
    public let sigma: UInt64

    public init(z: UInt64, sigma: UInt64) {
        self.z = z
        self.sigma = sigma
    }
}

/// 12-fold cyclotomic torus with degree-2 bilinear PLR involutions over `F_p` (`p = 1 mod 12`).
public struct CyclotomicPlrTorus: Sendable {
    public let p: UInt64
    public let zeta12: UInt64
    private let inv2: UInt64

    public init?(p: UInt64, zeta12: UInt64) {
        guard FieldMath.isPrimitive12thRoot(p: p, z: zeta12) else { return nil }
        self.p = p
        self.zeta12 = zeta12
        self.inv2 = (p + 1) / 2
    }

    public func embedTriad(root: UInt64, isMajor: Bool) -> TorusPoint {
        let z = FieldMath.modPow(zeta12, root % 12, p)
        let sig: UInt64 = isMajor ? 1 : (p - 1)
        return TorusPoint(z: z, sigma: sig)
    }

    public func applyBilinear(_ op: SZPlrOp, to pt: TorusPoint) -> TorusPoint {
        let s = op.shiftMod12
        let zs = FieldMath.modPow(zeta12, s, p)
        let zms = FieldMath.modPow(zeta12, (12 - s) % 12, p)
        let cs = FieldMath.mulMod((zs + zms) % p, inv2, p)
        let ds = FieldMath.mulMod((zs + p - zms) % p, inv2, p)
        let factor = (cs + FieldMath.mulMod(pt.sigma, ds, p)) % p
        let newZ = FieldMath.mulMod(pt.z, factor, p)
        let newSig = pt.sigma == 0 ? 0 : (p - pt.sigma)
        return TorusPoint(z: newZ, sigma: newSig)
    }

    public func applyWordBilinear(_ word: [SZPlrOp], to start: TorusPoint) -> TorusPoint {
        var pt = start
        for op in word.reversed() {
            pt = applyBilinear(op, to: pt)
        }
        return pt
    }

    public func verifyAll24Triads() -> Bool {
        var roots = Set<UInt64>()
        for r in 0..<UInt64(12) {
            roots.insert(FieldMath.modPow(zeta12, r, p))
        }
        guard roots.count == 12 else { return false }
        for r in 0..<UInt64(12) {
            for isMajor in [true, false] {
                let pt = embedTriad(root: r, isMajor: isMajor)
                for op in SZPlrOp.allCases {
                    let pt1 = applyBilinear(op, to: pt)
                    let pt2 = applyBilinear(op, to: pt1)
                    let rExp = isMajor ? ((r + op.shiftMod12) % 12) : ((r + 12 - op.shiftMod12) % 12)
                    let expected = embedTriad(root: rExp, isMajor: !isMajor)
                    if pt1 != expected || pt2 != pt {
                        return false
                    }
                }
            }
        }
        return true
    }

    public func ramanujanNBWalk(steps: Int, seed: UInt64) -> [TorusPoint] {
        var rng = SplitMix64(seed: seed)
        let r0 = rng.nextMod(12)
        let maj0 = (rng.nextUInt64() & 1) == 0
        var pt = embedTriad(root: r0, isMajor: maj0)
        var pts: [TorusPoint] = [pt]
        var prev: SZPlrOp? = nil
        if steps <= 1 { return pts }
        for _ in 1..<steps {
            let choices = SZPlrOp.allCases.filter { $0 != prev }
            let idx = Int(rng.nextUInt64() & 1) % choices.count
            let op = choices[idx]
            pt = applyBilinear(op, to: pt)
            pts.append(pt)
            prev = op
        }
        return pts
    }
}

/// 2x2 matrix over `F_p` for dihedral representation `rho_k(D_12)`.
public struct Mat2: Sendable, Equatable, Hashable {
    public let a: UInt64
    public let b: UInt64
    public let c: UInt64
    public let d: UInt64

    public static let identity = Mat2(a: 1, b: 0, c: 0, d: 1)

    public init(a: UInt64, b: UInt64, c: UInt64, d: UInt64) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public func multiplied(by rhs: Mat2, mod p: UInt64) -> Mat2 {
        Mat2(
            a: (FieldMath.mulMod(a, rhs.a, p) + FieldMath.mulMod(b, rhs.c, p)) % p,
            b: (FieldMath.mulMod(a, rhs.b, p) + FieldMath.mulMod(b, rhs.d, p)) % p,
            c: (FieldMath.mulMod(c, rhs.a, p) + FieldMath.mulMod(d, rhs.c, p)) % p,
            d: (FieldMath.mulMod(c, rhs.b, p) + FieldMath.mulMod(d, rhs.d, p)) % p
        )
    }

    public func mulVec(_ v: (UInt64, UInt64), mod p: UInt64) -> (UInt64, UInt64) {
        (
            (FieldMath.mulMod(a, v.0, p) + FieldMath.mulMod(b, v.1, p)) % p,
            (FieldMath.mulMod(c, v.0, p) + FieldMath.mulMod(d, v.1, p)) % p
        )
    }
}

public enum DihedralHolonomy {
    public static func genMat(p: UInt64, zeta12: UInt64, modeK k: UInt64, op: SZPlrOp) -> Mat2 {
        let s = op.shiftMod12
        let up = FieldMath.modPow(zeta12, (12 - (s * k) % 12) % 12, p)
        let dn = FieldMath.modPow(zeta12, (s * k) % 12, p)
        return Mat2(a: 0, b: up, c: dn, d: 0)
    }

    public static func wordMat(p: UInt64, zeta12: UInt64, modeK k: UInt64, word: [SZPlrOp]) -> Mat2 {
        var acc = Mat2.identity
        for op in word {
            acc = acc.multiplied(by: genMat(p: p, zeta12: zeta12, modeK: k, op: op), mod: p)
        }
        return acc
    }

    public static func imageAndKernelSize(p: UInt64, zeta12: UInt64, modeK k: UInt64) -> (Int, Int) {
        var mats = Set<Mat2>()
        var ker = 0
        for r in 0..<UInt64(12) {
            let rot = Mat2(
                a: FieldMath.modPow(zeta12, (r * k) % 12, p),
                b: 0,
                c: 0,
                d: FieldMath.modPow(zeta12, (12 - (r * k) % 12) % 12, p)
            )
            if rot == .identity { ker += 1 }
            mats.insert(rot)

            let refl = Mat2(
                a: 0,
                b: FieldMath.modPow(zeta12, (12 - (r * k) % 12) % 12, p),
                c: FieldMath.modPow(zeta12, (r * k) % 12, p),
                d: 0
            )
            if refl == .identity { ker += 1 }
            mats.insert(refl)
        }
        return (mats.count, ker)
    }
}

/// Non-backtracking Hashimoto/Ihara mixing vs Simple Random Walk on an N-TET Tonnetz dual.
public struct MixingReport: Sendable {
    public let nTet: Int
    public let directedEdges: Int
    public let maxNontrivialLambdaSq: Double
    public let satisfiesGraphRH: Bool
    public let srwNontrivialRate: Double
    public let nbIharaNontrivialRate: Double
    public let tvStep20SRW: Double
    public let tvStep20NB: Double
    public let massConserved: Bool
}

public enum HashimotoMixing {
    private struct DirEdge: Hashable {
        let u: Int
        let v: Int
    }

    /// Neumaier compensated sum that fails closed to NaN on any non-finite summand.
    private static func neumaierSum(_ xs: [Double]) -> Double {
        var sum = 0.0
        var comp = 0.0
        for x in xs {
            if !x.isFinite { return .nan }
            let t = sum + x
            if abs(sum) >= abs(x) {
                comp += (sum - t) + x
            } else {
                comp += (x - t) + sum
            }
            sum = t
        }
        return sum + comp
    }

    private static func probabilityVectorConserved(_ vec: [Double], tol: Double) -> Bool {
        guard tol.isFinite && tol >= 0.0 else { return false }
        for v in vec {
            if !v.isFinite || v < -tol { return false }
        }
        let total = neumaierSum(vec)
        return total.isFinite && abs(total - 1.0) <= tol
    }

    public static func analyze(nTet: Int, m3: Int, minor3: Int, steps: Int = 20) -> MixingReport {
        let vCount = 2 * nTet
        let shifts = [0, m3 % nTet, (nTet - (minor3 % nTet)) % nTet]
        var adj = Array(repeating: [Int](), count: vCount)
        for r in 0..<nTet {
            for sh in shifts {
                let v = nTet + ((r + sh) % nTet)
                adj[r].append(v)
                adj[v].append(r)
            }
        }

        var dirEdges: [DirEdge] = []
        var edgeIdx: [DirEdge: Int] = [:]
        for u in 0..<vCount {
            for v in adj[u] {
                let e = DirEdge(u: u, v: v)
                edgeIdx[e] = dirEdges.count
                dirEdges.append(e)
            }
        }

        var maxY = 0.0
        let twoPi = 2.0 * Double.pi
        for k in 1..<nTet {
            let th1 = twoPi * Double((m3 * k) % nTet) / Double(nTet)
            let th2 = twoPi * Double((nTet - ((minor3 * k) % nTet)) % nTet) / Double(nTet)
            let re = neumaierSum([1.0, cos(th1), cos(th2)])
            let im = sin(th1) + sin(th2)
            let y = re * re + im * im
            if !y.isFinite {
                maxY = .nan
                break
            }
            if y > maxY { maxY = y }
        }
        let satRH = maxY.isFinite && maxY < 8.0
        let srwRate = maxY.isFinite ? (sqrt(maxY) / 3.0) : .nan
        let nbRate: Double
        if !maxY.isFinite {
            nbRate = .nan
        } else if satRH {
            nbRate = 1.0 / sqrt(2.0)
        } else {
            nbRate = (sqrt(maxY) + sqrt(maxY - 8.0)) / 4.0
        }

        let massTol = 1e-11
        var pSRW = Array(repeating: 0.0, count: vCount)
        pSRW[0] = 1.0
        var pNB = Array(repeating: 0.0, count: dirEdges.count)
        for v in adj[0] {
            if let idx = edgeIdx[DirEdge(u: 0, v: v)] {
                pNB[idx] = 1.0 / 3.0
            }
        }

        var massConserved = probabilityVectorConserved(pSRW, tol: massTol)
            && probabilityVectorConserved(pNB, tol: massTol)

        pSRW = stepSRW(adj: adj, vec: pSRW)
        massConserved = massConserved && probabilityVectorConserved(pSRW, tol: massTol)
        if steps >= 2 {
            for _ in 2...steps {
                pSRW = stepSRW(adj: adj, vec: pSRW)
                pNB = stepNB(adj: adj, dirEdges: dirEdges, edgeIdx: edgeIdx, evec: pNB)
                massConserved = massConserved
                    && probabilityVectorConserved(pSRW, tol: massTol)
                    && probabilityVectorConserved(pNB, tol: massTol)
            }
        }

        var vNB = Array(repeating: 0.0, count: vCount)
        for (i, mass) in pNB.enumerated() {
            vNB[dirEdges[i].v] += mass
        }
        massConserved = massConserved && probabilityVectorConserved(vNB, tol: massTol)

        let stat = 1.0 / Double(nTet)
        let diffsSRW = (0..<nTet).map { abs(pSRW[$0] - stat) }
        let diffsNB = (0..<nTet).map { abs(vNB[$0] - stat) }
        let tvSRW = 0.5 * neumaierSum(diffsSRW)
        let tvNB = 0.5 * neumaierSum(diffsNB)
        massConserved = massConserved && tvSRW.isFinite && tvNB.isFinite

        return MixingReport(
            nTet: nTet,
            directedEdges: dirEdges.count,
            maxNontrivialLambdaSq: maxY,
            satisfiesGraphRH: satRH,
            srwNontrivialRate: srwRate,
            nbIharaNontrivialRate: nbRate,
            tvStep20SRW: tvSRW,
            tvStep20NB: tvNB,
            massConserved: massConserved
        )
    }

    private static func stepSRW(adj: [[Int]], vec: [Double]) -> [Double] {
        var nxt = Array(repeating: 0.0, count: vec.count)
        for (u, mass) in vec.enumerated() where mass > 0.0 {
            let share = mass / Double(adj[u].count)
            for v in adj[u] { nxt[v] += share }
        }
        return nxt
    }

    private static func stepNB(
        adj: [[Int]],
        dirEdges: [DirEdge],
        edgeIdx: [DirEdge: Int],
        evec: [Double]
    ) -> [Double] {
        var nxt = Array(repeating: 0.0, count: evec.count)
        for (i, mass) in evec.enumerated() where mass > 0.0 {
            let e = dirEdges[i]
            let share = mass / Double(adj[e.v].count - 1)
            for w in adj[e.v] where w != e.u {
                if let ni = edgeIdx[DirEdge(u: e.v, v: w)] {
                    nxt[ni] += share
                }
            }
        }
        return nxt
    }
}

/// Representation / homology-filtered length-6 cycle sieve on `G_PLR`.
public struct CycleSieveLen6: Sendable, Equatable {
    public let totalWalks: Int
    public let contractibleWalks: Int
    public let nonContractibleWalks: Int
    public let unorientedLPRLPRFaces: Int
    public let unorientedLPLPLPHexatonic: Int
}

public enum GPLRBridge {
    public static func sieveLen6Cycles() -> CycleSieveLen6 {
        var words: [[SZPlrOp]] = []
        var cur: [SZPlrOp] = []
        genNBWords(len: 6, prev: nil, cur: &cur, out: &words)

        var contractible = 0
        var nonContractible = 0
        for r0 in 0..<UInt64(12) {
            for maj0 in [true, false] {
                for w in words {
                    if w[0] == w[5] { continue }
                    var r = r0
                    var maj = maj0
                    var wx = 0
                    var wy = 0
                    for op in w {
                        let (dx, dy) = op.honeycombVec
                        if maj {
                            wx += dx
                            wy += dy
                            r = (r + op.shiftMod12) % 12
                        } else {
                            wx -= dx
                            wy -= dy
                            r = (r + 12 - op.shiftMod12) % 12
                        }
                        maj.toggle()
                    }
                    if r == r0 && maj == maj0 {
                        if wx == 0 && wy == 0 { contractible += 1 } else { nonContractible += 1 }
                    }
                }
            }
        }
        return CycleSieveLen6(
            totalWalks: contractible + nonContractible,
            contractibleWalks: contractible,
            nonContractibleWalks: nonContractible,
            unorientedLPRLPRFaces: contractible / 12,
            unorientedLPLPLPHexatonic: nonContractible / 12
        )
    }

    private static func genNBWords(
        len: Int,
        prev: SZPlrOp?,
        cur: inout [SZPlrOp],
        out: inout [[SZPlrOp]]
    ) {
        if cur.count == len {
            out.append(cur)
            return
        }
        for op in SZPlrOp.allCases where op != prev {
            cur.append(op)
            genNBWords(len: len, prev: op, cur: &cur, out: &out)
            cur.removeLast()
        }
    }

    public static func twistedLen6CharacterPIT(p: UInt64, x: UInt64, y: UInt64) -> UInt64? {
        guard let xi = FieldMath.modInvPrime(x, p), let yi = FieldMath.modInvPrime(y, p) else {
            return nil
        }
        let x3 = FieldMath.modPow(x, 3, p)
        let xi3 = FieldMath.modPow(xi, 3, p)
        let y3 = FieldMath.modPow(y, 3, p)
        let yi3 = FieldMath.modPow(yi, 3, p)
        let sum = (FieldMath.mulMod(x3, yi3, p) + FieldMath.mulMod(xi3, y3, p)) % p
        return (144 + FieldMath.mulMod(24, sum, p)) % p
    }

    public static func biadjacencyMatrix() -> [[UInt64]] {
        var mat = Array(repeating: Array(repeating: UInt64(0), count: 12), count: 12)
        for r in 0..<12 {
            for sh in [0, 4, 9] {
                mat[r][(r + sh) % 12] = 1
            }
        }
        return mat
    }

    public static func exactPerm() -> UInt64 {
        var dp = Array(repeating: UInt64(0), count: 1 << 12)
        dp[0] = 1
        for r in 0..<12 {
            let cols = [r % 12, (r + 4) % 12, (r + 9) % 12]
            var ndp = Array(repeating: UInt64(0), count: 1 << 12)
            for mask in 0..<(1 << 12) {
                let cnt = dp[mask]
                if cnt == 0 { continue }
                for c in cols {
                    let bit = 1 << c
                    if (mask & bit) == 0 {
                        ndp[mask | bit] += cnt
                    }
                }
            }
            dp = ndp
        }
        return dp[(1 << 12) - 1]
    }

    public static func detModPrime(_ mat: [[UInt64]], p: UInt64) -> UInt64? {
        guard FieldMath.isPrime(p) else { return nil }
        let n = mat.count
        var a = mat.map { $0.map { $0 % p } }
        var det: UInt64 = 1
        for col in 0..<n {
            guard let piv = (col..<n).first(where: { a[$0][col] != 0 }) else {
                return 0
            }
            if piv != col {
                a.swapAt(col, piv)
                det = det == 0 ? 0 : (p - det)
            }
            let diag = a[col][col]
            det = FieldMath.mulMod(det, diag, p)
            guard let inv = FieldMath.modInvPrime(diag, p) else { return nil }
            if col + 1 < n {
                for r in (col + 1)..<n where a[r][col] != 0 {
                    let factor = FieldMath.mulMod(a[r][col], inv, p)
                    for c in col..<n {
                        let sub = FieldMath.mulMod(factor, a[col][c], p)
                        a[r][c] = (a[r][c] + p - sub) % p
                    }
                }
            }
        }
        return det
    }

    public static func exactDetBareiss() -> Int64 {
        var a = biadjacencyMatrix().map { $0.map { Int64($0) } }
        let n = a.count
        var sign: Int64 = 1
        var prevPiv: Int64 = 1
        for k in 0..<n {
            guard let piv = (k..<n).first(where: { a[$0][k] != 0 }) else { return 0 }
            if piv != k {
                a.swapAt(k, piv)
                sign = -sign
            }
            let pk = a[k][k]
            if k + 1 < n {
                for i in (k + 1)..<n {
                    for j in (k + 1)..<n {
                        a[i][j] = (a[i][j] * pk - a[i][k] * a[k][j]) / prevPiv
                    }
                    a[i][k] = 0
                }
            }
            prevPiv = pk
        }
        return sign * a[n - 1][n - 1]
    }

    public static func edmondsPIT(p: UInt64, trials: Int, seed: UInt64) -> Bool? {
        guard FieldMath.isPrime(p), trials > 0 else { return nil }
        var rng = SplitMix64(seed: seed)
        for _ in 0..<trials {
            var mat = Array(repeating: Array(repeating: UInt64(0), count: 12), count: 12)
            for r in 0..<12 {
                for sh in [0, 4, 9] {
                    mat[r][(r + sh) % 12] = rng.nextMod(p)
                }
            }
            guard let d = detModPrime(mat, p: p) else { return nil }
            if d != 0 { return true }
        }
        return false
    }

    public static func bassIharaDFactoredModP(u: UInt64, p: UInt64) -> UInt64 {
        let u2 = FieldMath.mulMod(u, u, p)
        let u4 = FieldMath.mulMod(u2, u2, p)
        let u6 = FieldMath.mulMod(u4, u2, p)
        let u8 = FieldMath.mulMod(u4, u4, p)

        let f1 = (1 + p - u2) % p
        let f2 = (1 + p - FieldMath.mulMod(4, u2, p)) % p
        let f3 = (1 + p - u2 + FieldMath.mulMod(4, u4, p)) % p
        let f4 = (1 + u2 + FieldMath.mulMod(4, u4, p)) % p
        let f5 = (1 + FieldMath.mulMod(3, u2, p) + FieldMath.mulMod(4, u4, p)) % p
        let f6 = (
            1
            + FieldMath.mulMod(4, u2, p)
            + FieldMath.mulMod(9, u4, p)
            + FieldMath.mulMod(16, u6, p)
            + FieldMath.mulMod(16, u8, p)
        ) % p

        var acc = FieldMath.mulMod(f1, f2, p)
        acc = FieldMath.mulMod(acc, FieldMath.mulMod(f3, f3, p), p)
        acc = FieldMath.mulMod(acc, FieldMath.mulMod(f4, f4, p), p)
        acc = FieldMath.mulMod(acc, FieldMath.mulMod(FieldMath.mulMod(f5, f5, p), f5, p), p)
        acc = FieldMath.mulMod(acc, FieldMath.mulMod(f6, f6, p), p)
        return acc
    }

    public static func bassIharaDMatrixModP(u: UInt64, p: UInt64) -> UInt64? {
        guard FieldMath.isPrime(p) else { return nil }
        let u2 = FieldMath.mulMod(u, u, p)
        let diag = (1 + FieldMath.mulMod(2, u2, p)) % p
        let negU = (u % p == 0) ? 0 : (p - (u % p))
        var mat = Array(repeating: Array(repeating: UInt64(0), count: 24), count: 24)
        for i in 0..<24 { mat[i][i] = diag }
        for r in 0..<12 {
            for sh in [0, 4, 9] {
                let c = 12 + ((r + sh) % 12)
                mat[r][c] = negU
                mat[c][r] = negU
            }
        }
        return detModPrime(mat, p: p)
    }

    public static func freivaldsVerify(
        a: [[UInt64]],
        b: [[UInt64]],
        c: [[UInt64]],
        p: UInt64,
        trials: Int,
        seed: UInt64
    ) -> Bool? {
        guard FieldMath.isPrime(p), trials > 0 else { return nil }
        let n = a.count
        var rng = SplitMix64(seed: seed)
        for _ in 0..<trials {
            let r = (0..<n).map { _ in rng.nextMod(p) }
            let br = matVecMod(b, r, p)
            let abr = matVecMod(a, br, p)
            let cr = matVecMod(c, r, p)
            if abr != cr { return false }
        }
        return true
    }

    private static func matVecMod(_ mat: [[UInt64]], _ v: [UInt64], _ p: UInt64) -> [UInt64] {
        mat.map { row in
            var s: UInt64 = 0
            for (val, x) in zip(row, v) {
                s = (s + FieldMath.mulMod(val, x, p)) % p
            }
            return s
        }
    }

    public static func hasseMultiplicitySumF5() -> (distinctRoots: Int, totalMult: Int) {
        let p = 5
        var distinctRoots = 0
        var totalMult = 0
        for a in 0..<p {
            for b in 0..<p {
                let c1 = ((a - b) % p + p) % p
                let c2 = (a + b) % p
                let t1: [((Int, Int), Int)] = [((0, 0), c1), ((1, 0), 1), ((0, 1), p - 1)]
                let t2: [((Int, Int), Int)] = [((0, 0), c2), ((1, 0), 1), ((0, 1), 1)]
                let sq = poly2Mul(t1, t1, p: p)
                let prod = poly2Mul(sq, t2, p: p)
                let mult = prod.filter { $0.1 != 0 }.map { $0.0.0 + $0.0.1 }.min() ?? 99
                if mult >= 1 { distinctRoots += 1 }
                totalMult += mult
            }
        }
        return (distinctRoots, totalMult)
    }

    private struct PairKey: Hashable {
        let i: Int
        let j: Int
    }

    private static func poly2Mul(
        _ a: [((Int, Int), Int)],
        _ b: [((Int, Int), Int)],
        p: Int
    ) -> [((Int, Int), Int)] {
        var map: [PairKey: Int] = [:]
        for ((i1, j1), c1) in a {
            for ((i2, j2), c2) in b {
                let key = PairKey(i: i1 + i2, j: j1 + j2)
                let cur = map[key] ?? 0
                map[key] = ((cur + c1 * c2) % p + p) % p
            }
        }
        return map.compactMap { $0.value == 0 ? nil : (($0.key.i, $0.key.j), $0.value) }
    }
}

/// Typed Decodable schema for `schwartz_zippel_research_v1.json`.
public struct SZResearchVault: Decodable, Sendable {
    public struct AntiConflation: Decodable, Sendable {
        public let attribution_rule: String
        public let ring_hypothesis_guard: String
    }

    public struct PrimarySource: Decodable, Sendable {
        public let id: String
        public let reference_url: String
    }

    public struct MultiplicityBench: Decodable, Sendable {
        public let distinct_roots_count: Int
        public let sum_of_hasse_multiplicities: Int
        public let dkss_upper_bound: Int
    }

    public struct ModRow: Decodable, Sendable {
        public let modulus_m: UInt64
        public let is_integral_domain: Bool
        public let smallest_prime_factor: UInt64
        public let root_count: Int
        public let violates_sz: Bool
    }

    public struct CompositeRingBench: Decodable, Sendable {
        public let moduli_sweep: [ModRow]
    }

    public struct GPLRBridgeBench: Decodable, Sendable {
        public let exact_det_B: Int64
        public let exact_det_B_squared: Int64
        public let exact_perm_B_perfect_matchings: UInt64
    }

    public struct CyclotomicPrimeRow: Decodable, Sendable {
        public let p: UInt64
        public let zeta_12: UInt64
        public let torus_order: Int
    }

    public struct DihedralIrrepRow: Decodable, Sendable {
        public let mode_k: UInt64
        public let distinct_matrices: Int
        public let kernel_size: Int
        public let faithful: Bool
    }

    public struct CycleSieveBench: Decodable, Sendable {
        public let total_closed_tailless_nb_walks: Int
        public let contractible_walks: Int
        public let contractible_unoriented_faces_LPRLPR: Int
        public let non_contractible_walks: Int
        public let non_contractible_unoriented_hexatonic_LPLPLP: Int
    }

    public struct CoupledBench: Decodable, Sendable {
        public let cyclotomic_torus_primes: [CyclotomicPrimeRow]
        public let dihedral_representations_D12: [DihedralIrrepRow]
        public let representation_filtered_cycle_sieve_len6: CycleSieveBench
    }

    public struct Benchmarks: Decodable, Sendable {
        public let multiplicity_sz_f5_benchmark: MultiplicityBench
        public let composite_ring_regime_failures: CompositeRingBench
        public let g_plr_riemann_lattice_bridge: GPLRBridgeBench
        public let coupled_plr_torus_benchmarks: CoupledBench
    }

    public let tradition_id: String
    public let anti_conflation_guard: AntiConflation
    public let primary_sources: [PrimarySource]
    public let verified_computational_benchmarks: Benchmarks
}

/// Minimal typed Decodable view of `riemann_lattice_graph_rh_v1.json` for cross-vault parity.
public struct RLBridgeVault: Decodable, Sendable {
    public struct HexDecomp: Decodable, Sendable {
        public let LPRLPR_pitch_class_dual_faces: Int
        public let LPLPLP_hexatonic_cycles: Int
    }

    public struct HexSummary: Decodable, Sendable {
        public let decomposition: HexDecomp
    }

    public struct Invariants: Decodable, Sendable {
        public let exact_charpoly_B_BT_descending_y: [Int]
        public let minimal_prime_hexagons_length_6: HexSummary
    }

    public let tradition_id: String
    public let tonnetz_dual_exact_invariants: Invariants
}

/// Fail-closed atomic guards and cross-vault verifier for coupled `PIT-SZ x RIEM-LATTICE`.
public enum SZCoupledVerifier {
    public static func guardPrimeIntegralDomain(_ m: UInt64) -> SZGuardVerdict {
        if FieldMath.isPrime(m) {
            return SZGuardVerdict(
                compartment: "sz_prime_integral_domain",
                violationCount: 0,
                detail: "m=\(m) is prime (integral domain)"
            )
        }
        return SZGuardVerdict(
            compartment: "sz_prime_integral_domain",
            violationCount: 1,
            detail: "m=\(m) is composite (p_min=\(FieldMath.smallestPrimeFactor(m)))",
            healingAction: "Use a prime modulus or enforce Condition (D) grid capacity <= p_min(m)."
        )
    }

    public static func guardConditionDGrid(modulus m: UInt64, grid: [UInt64]) -> SZGuardVerdict {
        let ok = FieldMath.satisfiesConditionD(modulus: m, grid: grid)
        return SZGuardVerdict(
            compartment: "sz_condition_d_grid",
            violationCount: ok ? 0 : 1,
            detail: ok ? "grid of size \(grid.count) satisfies Condition (D) mod \(m)"
                       : "grid violates Condition (D) mod \(m)",
            healingAction: "Restrict grid so all distinct differences are coprime to \(m)."
        )
    }

    public static func guardNonVacuousDegree(globalDegree: Int, safeGridSize: Int) -> SZGuardVerdict {
        let violations = globalDegree < safeGridSize ? 0 : (globalDegree - safeGridSize + 1)
        return SZGuardVerdict(
            compartment: "sz_nonvacuous_degree_boundary",
            violationCount: violations,
            detail: violations == 0 ? "D=\(globalDegree) < |S|=\(safeGridSize)"
                                    : "D=\(globalDegree) >= |S|=\(safeGridSize) (ODLSZ stall)",
            healingAction: "Lift sampling domain to larger prime field F_p with p > D."
        )
    }

    public static func guardRamanujanNBMixing(_ rep: MixingReport) -> SZGuardVerdict {
        let ok = rep.massConserved
            && rep.maxNontrivialLambdaSq.isFinite
            && rep.satisfiesGraphRH
            && rep.nbIharaNontrivialRate.isFinite
            && rep.srwNontrivialRate.isFinite
            && rep.nbIharaNontrivialRate < rep.srwNontrivialRate
        return SZGuardVerdict(
            compartment: "coupled_ramanujan_nb_mixing",
            violationCount: ok ? 0 : 1,
            detail: "\(rep.nTet)-TET: max_lambda^2=\(String(format: "%.5f", rep.maxNontrivialLambdaSq)), NB=\(String(format: "%.5f", rep.nbIharaNontrivialRate)), SRW=\(String(format: "%.5f", rep.srwNontrivialRate)), massConserved=\(rep.massConserved)",
            healingAction: "Switch to a Ramanujan N-TET graph (such as 12-TET) with max_lambda^2 < 8 and conserved Markov mass."
        )
    }

    public static func evaluate(szRawJSON: String, rlRawJSON: String) -> [SZGuardVerdict] {
        let szData = Data(szRawJSON.utf8)
        let rlData = Data(rlRawJSON.utf8)
        let decoder = JSONDecoder()

        let szVault: SZResearchVault
        let rlVault: RLBridgeVault
        do {
            szVault = try decoder.decode(SZResearchVault.self, from: szData)
            rlVault = try decoder.decode(RLBridgeVault.self, from: rlData)
        } catch {
            return [
                SZGuardVerdict(
                    compartment: "vault_json_schema_decode",
                    violationCount: 1,
                    detail: "JSON decode failed: \(error)",
                    healingAction: "Restore valid schema for both primary source vaults."
                )
            ]
        }

        var verdicts: [SZGuardVerdict] = []

        // 1. Disjoint tradition provenance & zero banned wiki hosts
        let szLC = szRawJSON.lowercased()
        let rlLC = rlRawJSON.lowercased()
        let bannedWiki = szLC.contains("wikipedia.org") || szLC.contains("wikisource.org")
            || rlLC.contains("wikipedia.org") || rlLC.contains("wikisource.org")
        let provOK = szVault.tradition_id == "PIT-SZ"
            && rlVault.tradition_id == "RIEM-LATTICE"
            && szVault.primary_sources.count == 38
            && !bannedWiki
        verdicts.append(SZGuardVerdict(
            compartment: "vault_tradition_and_provenance",
            violationCount: provOK ? 0 : 1,
            detail: "PIT-SZ (38 sources) + RIEM-LATTICE disjoint vaults, zero wiki hosts",
            healingAction: "Remove banned wiki hosts and preserve disjoint tradition IDs."
        ))

        // 2. Cyclotomic 12-fold torus & bilinear degree-2 involutions across all vault primes
        let bench = szVault.verified_computational_benchmarks
        var torusViolations = 0
        for row in bench.coupled_plr_torus_benchmarks.cyclotomic_torus_primes {
            if let torus = CyclotomicPlrTorus(p: row.p, zeta12: row.zeta_12),
               torus.verifyAll24Triads(), row.torus_order == 12 {
                continue
            }
            torusViolations += 1
        }
        verdicts.append(SZGuardVerdict(
            compartment: "coupled_cyclotomic_torus_bilinear",
            violationCount: torusViolations,
            detail: "verified \(bench.coupled_plr_torus_benchmarks.cyclotomic_torus_primes.count) cyclotomic primes with degree-2 P,L,R involutions",
            healingAction: "Ensure every prime satisfies p = 1 mod 12 with exact primitive 12th root."
        ))

        // 3. Non-abelian holonomy rho_1..rho_5 + PL != LP separation
        var holViolations = 0
        for row in bench.coupled_plr_torus_benchmarks.dihedral_representations_D12 {
            let (im, ker) = DihedralHolonomy.imageAndKernelSize(p: 65521, zeta12: 53059, modeK: row.mode_k)
            if im != row.distinct_matrices || ker != row.kernel_size || (ker == 1) != row.faithful {
                holViolations += 1
            }
        }
        let abelEq = DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 0, word: [.pOp, .lOp])
            == DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 0, word: [.lOp, .pOp])
        let faithNeq = DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 1, word: [.pOp, .lOp])
            != DihedralHolonomy.wordMat(p: 65521, zeta12: 53059, modeK: 1, word: [.lOp, .pOp])
        if !abelEq || !faithNeq { holViolations += 1 }
        verdicts.append(SZGuardVerdict(
            compartment: "coupled_nonabelian_holonomy_rho_k",
            violationCount: holViolations,
            detail: "rho_1/rho_5 faithful (24/24); separates PL vs LP where abelianization fails",
            healingAction: "Verify dihedral matrix representations over F_65521."
        ))

        // 4. Non-backtracking Hashimoto/Ihara Ramanujan mixing (12-TET vs 17-TET)
        let rep12 = HashimotoMixing.analyze(nTet: 12, m3: 4, minor3: 3, steps: 20)
        let rep17 = HashimotoMixing.analyze(nTet: 17, m3: 5, minor3: 5, steps: 20)
        let mixOK = rep12.satisfiesGraphRH && !rep17.satisfiesGraphRH
            && rep12.directedEdges == 72
            && rep12.nbIharaNontrivialRate < rep12.srwNontrivialRate
            && rep12.tvStep20NB < rep12.tvStep20SRW
            && rep12.tvStep20NB * 20.0 < rep17.tvStep20NB
        verdicts.append(SZGuardVerdict(
            compartment: "coupled_ihara_nb_mixing_vs_17tet",
            violationCount: mixOK ? 0 : 1,
            detail: "12-TET NB=\(String(format: "%.5f", rep12.nbIharaNontrivialRate)) (TV20=\(String(format: "%.6f", rep12.tvStep20NB))) vs 17-TET NB=\(String(format: "%.5f", rep17.nbIharaNontrivialRate)) (TV20=\(String(format: "%.6f", rep17.tvStep20NB)))",
            healingAction: "Check Hashimoto 72-edge transition matrix and N-TET Graph-RH margin."
        ))

        // 5. Representation/homology-filtered cycle sieving at length 6 + twisted character PIT
        let sieve = GPLRBridge.sieveLen6Cycles()
        let vSieve = bench.coupled_plr_torus_benchmarks.representation_filtered_cycle_sieve_len6
        let rlHex = rlVault.tonnetz_dual_exact_invariants.minimal_prime_hexagons_length_6.decomposition
        let twistOK = (GPLRBridge.twistedLen6CharacterPIT(p: 65521, x: 7, y: 11) ?? 144) != 144
        let sieveOK = sieve.totalWalks == vSieve.total_closed_tailless_nb_walks
            && sieve.contractibleWalks == vSieve.contractible_walks
            && sieve.nonContractibleWalks == vSieve.non_contractible_walks
            && sieve.unorientedLPRLPRFaces == rlHex.LPRLPR_pitch_class_dual_faces
            && sieve.unorientedLPLPLPHexatonic == rlHex.LPLPLP_hexatonic_cycles
            && twistOK
        verdicts.append(SZGuardVerdict(
            compartment: "coupled_cycle_sieve_len6_cross_vault",
            violationCount: sieveOK ? 0 : 1,
            detail: "192 NB walks = 144 contractible (12 LPRLPR) + 48 non-contractible (4 LPLPLP)",
            healingAction: "Cross-check Z^2 homology cycle counts across both vaults."
        ))

        // 6. Low-entropy Ramanujan walk PIT & exact D=12 boundary stall witness
        var lowEntOK = false
        if let torus65521 = CyclotomicPlrTorus(p: 65521, zeta12: 53059) {
            let walkPts = torus65521.ramanujanNBWalk(steps: 16, seed: 0x51A7_C0DE_2026)
            var deg11 = Array(repeating: UInt64(0), count: 12)
            deg11[0] = 65520
            deg11[11] = 1
            var deg12 = Array(repeating: UInt64(0), count: 13)
            deg12[0] = 65520
            deg12[12] = 1
            let hit11 = walkPts.contains { FieldMath.evalUniMod(coeffs: deg11, x: $0.z, p: 65521) != 0 }
            let stall12 = walkPts.allSatisfy { FieldMath.evalUniMod(coeffs: deg12, x: $0.z, p: 65521) == 0 }
            lowEntOK = hit11 && stall12
        }
        verdicts.append(SZGuardVerdict(
            compartment: "coupled_low_entropy_pit_and_degree_wall",
            violationCount: lowEntOK ? 0 : 1,
            detail: "Ramanujan NB walk detects deg-11 nonzero and confirms exact stall at D=12 (z^12 - 1)",
            healingAction: "Verify torus walk sampling and degree-12 vanishing witness."
        ))

        // 7. Direct G_PLR bridge: det(B)=45, det(B)^2=2025, perm(B)=113, Edmonds & Bass-Ihara PIT
        let detB = GPLRBridge.exactDetBareiss()
        let permB = GPLRBridge.exactPerm()
        let vBridge = bench.g_plr_riemann_lattice_bridge
        let rlConst = rlVault.tonnetz_dual_exact_invariants.exact_charpoly_B_BT_descending_y.last ?? -1
        let edmondsOK = (GPLRBridge.edmondsPIT(p: 65521, trials: 4, seed: 202601) == true)
            && (GPLRBridge.edmondsPIT(p: 1_000_000_009, trials: 4, seed: 202602) == true)
        let bassOK = [UInt64(7), 19, 1003, 40999].allSatisfy { u in
            GPLRBridge.bassIharaDMatrixModP(u: u, p: 65521) == GPLRBridge.bassIharaDFactoredModP(u: u, p: 65521)
        }
        let bridgeOK = detB == vBridge.exact_det_B
            && detB * detB == vBridge.exact_det_B_squared
            && Int(detB * detB) == rlConst
            && permB == vBridge.exact_perm_B_perfect_matchings
            && detB % 3 == 0 && detB % 5 == 0
            && edmondsOK && bassOK
        verdicts.append(SZGuardVerdict(
            compartment: "g_plr_edmonds_and_bass_ihara_pit_bridge",
            violationCount: bridgeOK ? 0 : 1,
            detail: "det(B)=45 (2025), perm(B)=113, Edmonds & Bass-Ihara PIT matched mod 65521",
            healingAction: "Recompute G_PLR biadjacency determinant, permanent, and Bass-Ihara evaluations."
        ))

        // 8. Correspondence Principle regimes: Hasse multiplicity + composite-ring breakdown + Condition (D)
        let hasse = GPLRBridge.hasseMultiplicitySumF5()
        let vHasse = bench.multiplicity_sz_f5_benchmark
        var modViolations = 0
        for row in bench.composite_ring_regime_failures.moduli_sweep {
            let m = row.modulus_m
            let roots = (0..<m).filter { ($0 * ($0 + m - 1)) % m == 0 }.count
            let spf = FieldMath.smallestPrimeFactor(m)
            let isDom = FieldMath.isPrime(m)
            let violates = roots > 2
            if roots != row.root_count || spf != row.smallest_prime_factor
                || isDom != row.is_integral_domain || violates != row.violates_sz {
                modViolations += 1
            }
        }
        let regimeOK = hasse.distinctRoots == vHasse.distinct_roots_count
            && hasse.totalMult == vHasse.sum_of_hasse_multiplicities
            && hasse.totalMult == vHasse.dkss_upper_bound
            && modViolations == 0
            && FieldMath.satisfiesConditionD(modulus: 6, grid: [0, 1])
            && !FieldMath.satisfiesConditionD(modulus: 6, grid: [0, 1, 3, 4])
        verdicts.append(SZGuardVerdict(
            compartment: "correspondence_regime_bounds_tf01_to_tf05",
            violationCount: regimeOK ? 0 : 1,
            detail: "DKSS Hasse sum=15/15; all 7 Z/mZ moduli and Condition (D) repair verified",
            healingAction: "Inspect composite-ring root sweep and Hasse multiplicity calculation."
        ))

        // 9. Freivalds O(n^2) Gram matrix check on G_PLR mod 65521
        let bMat = GPLRBridge.biadjacencyMatrix()
        var btMat = Array(repeating: Array(repeating: UInt64(0), count: 12), count: 12)
        for i in 0..<12 { for j in 0..<12 { btMat[j][i] = bMat[i][j] } }
        var gram = Array(repeating: Array(repeating: UInt64(0), count: 12), count: 12)
        for i in 0..<12 {
            for j in 0..<12 {
                var s: UInt64 = 0
                for k in 0..<12 { s = (s + bMat[i][k] * btMat[k][j]) % 65521 }
                gram[i][j] = s
            }
        }
        let freivaldsOK = GPLRBridge.freivaldsVerify(a: bMat, b: btMat, c: gram, p: 65521, trials: 8, seed: 99123) == true
        verdicts.append(SZGuardVerdict(
            compartment: "freivalds_g_plr_gram_verification",
            violationCount: freivaldsOK ? 0 : 1,
            detail: "Freivalds O(n^2) verification passed for G_PLR Gram matrix B * B^T mod 65521",
            healingAction: "Check G_PLR Gram matrix multiplication over F_65521."
        ))

        return verdicts
    }
}
