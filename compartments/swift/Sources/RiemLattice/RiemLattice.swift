// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import SCargoModel

// MARK: - Exact Arbitrary-Precision Integer (Z) & Rational (Q)

private let exactBase: UInt64 = 1_000_000_000

public struct ExactInt: Sendable, Equatable {
    public let isNegative: Bool
    /// Little-endian base-10^9 limbs; empty means 0 (and `isNegative` is always `false`).
    public let limbs: [UInt32]

    public static let zero = ExactInt(isNegative: false, limbs: [])
    public static let one = ExactInt(isNegative: false, limbs: [1])

    public init(isNegative: Bool, limbs: [UInt32]) {
        var trimmed = limbs
        while let last = trimmed.last, last == 0 {
            trimmed.removeLast()
        }
        self.limbs = trimmed
        self.isNegative = trimmed.isEmpty ? false : isNegative
    }

    public init(_ value: Int64) {
        if value == 0 {
            self = .zero
            return
        }
        let neg = value < 0
        var mag = value.magnitude
        var arr: [UInt32] = []
        while mag > 0 {
            arr.append(UInt32(mag % exactBase))
            mag /= exactBase
        }
        self.init(isNegative: neg, limbs: arr)
    }

    public var isZero: Bool { limbs.isEmpty }
    public var absValue: ExactInt { ExactInt(isNegative: false, limbs: limbs) }
    public var negated: ExactInt { isZero ? .zero : ExactInt(isNegative: !isNegative, limbs: limbs) }

    private static func cmpMag(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        }
        return 0
    }

    private static func addMag(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        let n = max(a.count, b.count)
        var out: [UInt32] = []
        out.reserveCapacity(n + 1)
        var carry: UInt64 = 0
        for i in 0..<n {
            let av: UInt64 = i < a.count ? UInt64(a[i]) : 0
            let bv: UInt64 = i < b.count ? UInt64(b[i]) : 0
            let s = av + bv + carry
            out.append(UInt32(s % exactBase))
            carry = s / exactBase
        }
        if carry > 0 { out.append(UInt32(carry)) }
        return out
    }

    /// Assumes |a| >= |b|.
    private static func subMag(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            let av = Int64(a[i])
            let bv: Int64 = i < b.count ? Int64(b[i]) : 0
            var diff = av - bv - borrow
            if diff < 0 {
                diff += Int64(exactBase)
                borrow = 1
            } else {
                borrow = 0
            }
            out.append(UInt32(diff))
        }
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    public static func + (lhs: ExactInt, rhs: ExactInt) -> ExactInt {
        if lhs.isNegative == rhs.isNegative {
            return ExactInt(isNegative: lhs.isNegative, limbs: addMag(lhs.limbs, rhs.limbs))
        }
        let c = cmpMag(lhs.limbs, rhs.limbs)
        if c == 0 { return .zero }
        if c > 0 {
            return ExactInt(isNegative: lhs.isNegative, limbs: subMag(lhs.limbs, rhs.limbs))
        } else {
            return ExactInt(isNegative: rhs.isNegative, limbs: subMag(rhs.limbs, lhs.limbs))
        }
    }

    public static func - (lhs: ExactInt, rhs: ExactInt) -> ExactInt {
        lhs + rhs.negated
    }

    public static func * (lhs: ExactInt, rhs: ExactInt) -> ExactInt {
        if lhs.isZero || rhs.isZero { return .zero }
        var out = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in 0..<lhs.limbs.count {
            var carry: UInt64 = 0
            let av = UInt64(lhs.limbs[i])
            for j in 0..<rhs.limbs.count {
                let prod = av * UInt64(rhs.limbs[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(prod % exactBase)
                carry = prod / exactBase
            }
            if carry > 0 {
                out[i + rhs.limbs.count] = UInt32(UInt64(out[i + rhs.limbs.count]) + carry)
            }
        }
        return ExactInt(isNegative: lhs.isNegative != rhs.isNegative, limbs: out)
    }

    public func pow(_ exp: Int) -> ExactInt {
        precondition(exp >= 0)
        var e = exp
        var base = self
        var acc = ExactInt.one
        while e > 0 {
            if (e & 1) == 1 { acc = acc * base }
            e >>= 1
            if e > 0 { base = base * base }
        }
        return acc
    }

    private static func divRemMag(_ a: [UInt32], _ b: [UInt32]) -> ([UInt32], [UInt32]) {
        precondition(!b.isEmpty, "division by zero")
        if cmpMag(a, b) < 0 { return ([], a) }
        if b.count == 1 {
            let d = UInt64(b[0])
            var q = [UInt32](repeating: 0, count: a.count)
            var rem: UInt64 = 0
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                let cur = rem * exactBase + UInt64(a[i])
                q[i] = UInt32(cur / d)
                rem = cur % d
            }
            while let last = q.last, last == 0 { q.removeLast() }
            return (q, rem == 0 ? [] : [UInt32(rem)])
        }
        var rem = ExactInt.zero
        var quot = ExactInt.zero
        let bBig = ExactInt(isNegative: false, limbs: b)
        let baseBig = ExactInt(Int64(exactBase))
        for limb in a.reversed() {
            rem = rem * baseBig + ExactInt(Int64(limb))
            var lo: UInt64 = 0
            var hi: UInt64 = exactBase - 1
            var best: UInt64 = 0
            while lo <= hi {
                let mid = lo + (hi - lo) / 2
                let trial = bBig * ExactInt(Int64(mid))
                if cmpMag(trial.limbs, rem.limbs) <= 0 {
                    best = mid
                    lo = mid + 1
                } else if mid == 0 {
                    break
                } else {
                    hi = mid - 1
                }
            }
            if best > 0 {
                rem = rem - bBig * ExactInt(Int64(best))
            }
            quot = quot * baseBig + ExactInt(Int64(best))
        }
        return (quot.limbs, rem.limbs)
    }

    public func dividedExactly(by other: ExactInt) -> ExactInt? {
        if other.isZero { return nil }
        if isZero { return .zero }
        let (q, r) = Self.divRemMag(limbs, other.limbs)
        if !r.isEmpty { return nil }
        return ExactInt(isNegative: isNegative != other.isNegative, limbs: q)
    }

    public static func gcd(_ a: ExactInt, _ b: ExactInt) -> ExactInt {
        var x = a.absValue
        var y = b.absValue
        while !y.isZero {
            let (_, rem) = divRemMag(x.limbs, y.limbs)
            x = y
            y = ExactInt(isNegative: false, limbs: rem)
        }
        return x
    }

    public var int64Value: Int64? {
        if isZero { return 0 }
        var acc: UInt64 = 0
        for limb in limbs.reversed() {
            let (m, ov1) = acc.multipliedReportingOverflow(by: exactBase)
            if ov1 { return nil }
            let (s, ov2) = m.addingReportingOverflow(UInt64(limb))
            if ov2 { return nil }
            acc = s
        }
        if isNegative {
            if acc == UInt64(Int64.max) + 1 { return Int64.min }
            if acc > UInt64(Int64.max) { return nil }
            return -Int64(acc)
        } else {
            if acc > UInt64(Int64.max) { return nil }
            return Int64(acc)
        }
    }
}

public struct ExactRat: Sendable, Equatable {
    public let num: ExactInt
    public let den: ExactInt

    public static let zero = ExactRat(0, 1)
    public static let one = ExactRat(1, 1)

    public init(_ num: ExactInt, _ den: ExactInt) {
        precondition(!den.isZero, "zero denominator")
        if num.isZero {
            self.num = .zero
            self.den = .one
            return
        }
        let n = den.isNegative ? num.negated : num
        let d = den.isNegative ? den.negated : den
        let g = ExactInt.gcd(n, d)
        self.num = n.dividedExactly(by: g)!
        self.den = d.dividedExactly(by: g)!
    }

    public init(_ n: Int64, _ d: Int64 = 1) {
        self.init(ExactInt(n), ExactInt(d))
    }

    public var isZero: Bool { num.isZero }
    public var negated: ExactRat { ExactRat(num.negated, den) }

    public static func + (lhs: ExactRat, rhs: ExactRat) -> ExactRat {
        ExactRat(lhs.num * rhs.den + rhs.num * lhs.den, lhs.den * rhs.den)
    }

    public static func - (lhs: ExactRat, rhs: ExactRat) -> ExactRat {
        lhs + rhs.negated
    }

    public static func * (lhs: ExactRat, rhs: ExactRat) -> ExactRat {
        ExactRat(lhs.num * rhs.num, lhs.den * rhs.den)
    }

    public static func / (lhs: ExactRat, rhs: ExactRat) -> ExactRat {
        precondition(!rhs.isZero, "division by zero")
        return ExactRat(lhs.num * rhs.den, lhs.den * rhs.num)
    }

    public func pow(_ exp: Int) -> ExactRat {
        ExactRat(num.pow(exp), den.pow(exp))
    }
}

// MARK: - Dual Klang, Generalized N-TET Operators & Tonnetz Dual G_PLR

public enum Polarity: String, Codable, Sendable, Equatable, Hashable {
    case major
    case minor

    public var flipped: Polarity {
        switch self {
        case .major: .minor
        case .minor: .major
        }
    }
}

public struct Triad: Sendable, Equatable, Hashable {
    public let root: Int
    public let polarity: Polarity

    public init(root: Int, polarity: Polarity) {
        self.root = root
        self.polarity = polarity
    }
}

public enum PLROperator: String, CaseIterable, Sendable, Equatable {
    case P
    case L
    case R
}

public struct NTetSystem: Sendable, Equatable {
    public let n: Int
    public let p5: Int
    public let m3: Int

    public var minorThird: Int { p5 - m3 }

    public static let canonical12TET = NTetSystem(n: 12, p5: 7, m3: 4)

    public init(n: Int, p5: Int, m3: Int) {
        precondition(n > 0)
        self.n = n
        self.p5 = p5
        self.m3 = m3
    }

    public static func fromN(_ n: Int) -> NTetSystem {
        let p5 = Int((Double(n) * log2(1.5)).rounded())
        let m3 = Int((Double(n) * log2(1.25)).rounded())
        return NTetSystem(n: n, p5: p5, m3: m3)
    }

    public func applyPLR(_ op: PLROperator, to t: Triad) -> Triad {
        switch (op, t.polarity) {
        case (.P, let p):
            return Triad(root: t.root, polarity: p.flipped)
        case (.L, .major):
            return Triad(root: (t.root + m3) % n, polarity: .minor)
        case (.L, .minor):
            return Triad(root: (t.root + n - (m3 % n)) % n, polarity: .major)
        case (.R, .major):
            return Triad(root: (t.root + n - (minorThird % n)) % n, polarity: .minor)
        case (.R, .minor):
            return Triad(root: (t.root + minorThird) % n, polarity: .major)
        }
    }

    public func applyT(_ shift: Int, to t: Triad) -> Triad {
        Triad(root: (t.root + shift) % n, polarity: t.polarity)
    }

    public func applyI(_ axis: Int, to t: Triad) -> Triad {
        let r = (axis + n - (t.root % n) + n - (p5 % n)) % n
        return Triad(root: r, polarity: t.polarity.flipped)
    }

    public func pitchClasses(of t: Triad) -> [Int] {
        switch t.polarity {
        case .major: [t.root, (t.root + m3) % n, (t.root + p5) % n]
        case .minor: [t.root, (t.root + minorThird) % n, (t.root + p5) % n]
        }
    }

    public func sharedPitchClasses(_ a: Triad, _ b: Triad) -> Int {
        let pb = pitchClasses(of: b)
        return pitchClasses(of: a).filter { pb.contains($0) }.count
    }

    public var allTriads: [Triad] {
        (0..<n).map { Triad(root: $0, polarity: .major) }
            + (0..<n).map { Triad(root: $0, polarity: .minor) }
    }

    public var isConnected: Bool {
        gcdInt(m3, gcdInt(p5, n)) == 1
    }

    public func mutualCentralizerViolations() -> Int {
        var violations = 0
        for t in allTriads {
            for op in PLROperator.allCases {
                if applyPLR(op, to: applyPLR(op, to: t)) != t { violations += 1 }
                for k in 0..<n {
                    if applyPLR(op, to: applyT(k, to: t)) != applyT(k, to: applyPLR(op, to: t)) {
                        violations += 1
                    }
                    if applyPLR(op, to: applyI(k, to: t)) != applyI(k, to: applyPLR(op, to: t)) {
                        violations += 1
                    }
                }
            }
        }
        return violations
    }

    public func parsimonyViolations() -> Int {
        var violations = 0
        for t in allTriads {
            for op in PLROperator.allCases {
                if sharedPitchClasses(t, applyPLR(op, to: t)) != 2 { violations += 1 }
            }
        }
        return violations
    }

    public func biadjacencyMatrix() -> [[Int64]] {
        var b = [[Int64]](repeating: [Int64](repeating: 0, count: n), count: n)
        for i in 0..<n {
            let maj = Triad(root: i, polarity: .major)
            for op in PLROperator.allCases {
                let nb = applyPLR(op, to: maj)
                b[i][nb.root] = 1
            }
        }
        return b
    }

    public func adjacencyMatrix() -> [[Int64]] {
        let b = biadjacencyMatrix()
        var a = [[Int64]](repeating: [Int64](repeating: 0, count: 2 * n), count: 2 * n)
        for i in 0..<n {
            for j in 0..<n {
                a[i][n + j] = b[i][j]
                a[n + j][i] = b[i][j]
            }
        }
        return a
    }

    public func gramMatrix() -> [[Int64]] {
        let b = biadjacencyMatrix()
        var m = [[Int64]](repeating: [Int64](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in 0..<n {
                var acc: Int64 = 0
                for k in 0..<n { acc += b[i][k] * b[j][k] }
                m[i][j] = acc
            }
        }
        return m
    }

    public func maxNontrivialLambdaSquared() -> Double? {
        guard isConnected else { return nil }
        let shL = Double(m3)
        let shR = Double(n - (minorThird % n))
        let nf = Double(n)
        var best = 0.0
        for k in 1..<n {
            let kf = Double(k)
            let a1 = 2.0 * Double.pi * kf * shL / nf
            let a2 = 2.0 * Double.pi * kf * shR / nf
            let re = 1.0 + cos(a1) + cos(a2)
            let im = sin(a1) + sin(a2)
            let magSq = re * re + im * im
            guard magSq.isFinite else { return nil }
            if magSq > best { best = magSq }
        }
        return best
    }
}

public func gcdInt(_ a: Int, _ b: Int) -> Int {
    var x = abs(a)
    var y = abs(b)
    while y != 0 {
        let r = x % y
        x = y
        y = r
    }
    return x
}

// MARK: - Exact Faddeev-LeVerrier, Bass-Ihara Determinant & Prime Cycles

public enum RiemLatticeEngine {
    public static func faddeevLeVerrierExact(_ m: [[Int64]]) -> (coefficients: [Int64], cayleyHamiltonZero: Bool) {
        let n = m.count
        let mBig = m.map { $0.map { ExactInt($0) } }
        var kMat = (0..<n).map { i in
            (0..<n).map { j in i == j ? ExactInt.one : ExactInt.zero }
        }
        var coeffs: [Int64] = [1]
        for step in 1...n {
            var mk = [[ExactInt]](repeating: [ExactInt](repeating: .zero, count: n), count: n)
            for i in 0..<n {
                for j in 0..<n {
                    var sum = ExactInt.zero
                    for t in 0..<n { sum = sum + mBig[i][t] * kMat[t][j] }
                    mk[i][j] = sum
                }
            }
            var tr = ExactInt.zero
            for i in 0..<n { tr = tr + mk[i][i] }
            let ck = tr.negated.dividedExactly(by: ExactInt(Int64(step)))!
            coeffs.append(ck.int64Value!)
            for i in 0..<n { mk[i][i] = mk[i][i] + ck }
            kMat = mk
        }
        let remZero = kMat.allSatisfy { row in row.allSatisfy { $0.isZero } }
        return (coeffs, remZero)
    }

    public static func determinantExact(_ matrix: [[ExactRat]]) -> ExactRat {
        let n = matrix.count
        var a = matrix
        var det = ExactRat.one
        for col in 0..<n {
            guard let piv = (col..<n).first(where: { !a[$0][col].isZero }) else {
                return .zero
            }
            if piv != col {
                a.swapAt(col, piv)
                det = det.negated
            }
            let pv = a[col][col]
            det = det * pv
            for r in (col + 1)..<n {
                if !a[r][col].isZero {
                    let factor = a[r][col] / pv
                    for k in col..<n {
                        a[r][k] = a[r][k] - factor * a[col][k]
                    }
                }
            }
        }
        return det
    }

    public static func bassIharaMatrixDet(adj: [[Int64]], u: ExactRat) -> ExactRat {
        let n = adj.count
        let diag = ExactRat.one + ExactRat(2, 1) * u * u
        let mat: [[ExactRat]] = (0..<n).map { i in
            (0..<n).map { j in
                let base = i == j ? diag : ExactRat.zero
                return adj[i][j] != 0 ? base - u * ExactRat(adj[i][j], 1) : base
            }
        }
        return determinantExact(mat)
    }

    public static func bassIharaDFactored12TET(u: ExactRat) -> ExactRat {
        let u2 = u * u
        let u4 = u2 * u2
        let u6 = u4 * u2
        let u8 = u4 * u4
        let f1 = ExactRat.one - u2
        let f2 = ExactRat.one - ExactRat(4, 1) * u2
        let f3 = (ExactRat.one - u2 + ExactRat(4, 1) * u4).pow(2)
        let f4 = (ExactRat.one + u2 + ExactRat(4, 1) * u4).pow(2)
        let f5 = (ExactRat.one + ExactRat(3, 1) * u2 + ExactRat(4, 1) * u4).pow(3)
        let f6 = (ExactRat.one + ExactRat(4, 1) * u2 + ExactRat(9, 1) * u4
            + ExactRat(16, 1) * u6 + ExactRat(16, 1) * u8).pow(2)
        return f1 * f2 * f3 * f4 * f5 * f6
    }

    public static func polyMul(_ a: [Int64], _ b: [Int64]) -> [Int64] {
        var r = [Int64](repeating: 0, count: a.count + b.count - 1)
        for i in 0..<a.count {
            for j in 0..<b.count { r[i + j] += a[i] * b[j] }
        }
        return r
    }

    public static func polyPow(_ p: [Int64], _ exp: Int) -> [Int64] {
        var acc: [Int64] = [1]
        for _ in 0..<exp { acc = polyMul(acc, p) }
        return acc
    }

    public static func zetaInversePoly12TET() -> [Int64] {
        let factors: [([Int64], Int)] = [
            ([1, 0, -1], 13),
            ([1, 0, -4], 1),
            ([1, 0, -1, 0, 4], 2),
            ([1, 0, 1, 0, 4], 2),
            ([1, 0, 3, 0, 4], 3),
            ([1, 0, 4, 0, 9, 0, 16, 0, 16], 2),
        ]
        var f: [Int64] = [1]
        for (fac, mult) in factors { f = polyMul(f, polyPow(fac, mult)) }
        return f
    }

    public static func mobius(_ value: Int) -> Int64 {
        if value == 0 { return 0 }
        var n = value
        var p = 2
        var cnt = 0
        while p * p <= n {
            if n % p == 0 {
                n /= p
                if n % p == 0 { return 0 }
                cnt += 1
            }
            p += 1
        }
        if n > 1 { cnt += 1 }
        return cnt % 2 == 1 ? -1 : 1
    }

    public struct PrimeCycleRow: Sendable, Equatable {
        public let lengthM: Int
        public let closedNBWalks: Int64
        public let orientedPrimes: Int64
        public let unorientedPrimes: Int64
    }

    public static func computePrimeCycleTable(zetaInv: [Int64], maxM: Int) -> [PrimeCycleRow] {
        var nWalk = [Int64](repeating: 0, count: maxM + 1)
        for m in 1...maxM {
            let fm: Int64 = m < zetaInv.count ? zetaInv[m] : 0
            let rhs = -Int64(m) * fm
            var lhsRest: Int64 = 0
            for k in 1..<m {
                let fk: Int64 = k < zetaInv.count ? zetaInv[k] : 0
                lhsRest += fk * nWalk[m - k]
            }
            nWalk[m] = rhs - lhsRest
        }
        var rows: [PrimeCycleRow] = []
        for m in stride(from: 2, through: maxM, by: 2) {
            var total: Int64 = 0
            for d in 1...m where m % d == 0 {
                total += mobius(m / d) * nWalk[d]
            }
            let oriented = total / Int64(m)
            rows.append(PrimeCycleRow(
                lengthM: m,
                closedNBWalks: nWalk[m],
                orientedPrimes: oriented,
                unorientedPrimes: oriented / 2
            ))
        }
        return rows
    }

    public static func enumerateMusicalHexagons12TET() -> (lprlpr: Int, lplplp: Int) {
        let sys = NTetSystem.canonical12TET
        let lprlpr: [PLROperator] = [.L, .P, .R, .L, .P, .R]
        let lplplp: [PLROperator] = [.L, .P, .L, .P, .L, .P]

        func countDistinct(_ word: [PLROperator]) -> Int {
            var orbits = Set<[Int]>()
            for r in 0..<12 {
                var cur = Triad(root: r, polarity: .major)
                var majors = Set<Int>([cur.root])
                for op in word {
                    cur = sys.applyPLR(op, to: cur)
                    if cur.polarity == .major { majors.insert(cur.root) }
                }
                precondition(cur == Triad(root: r, polarity: .major))
                orbits.insert(majors.sorted())
            }
            return orbits.count
        }
        return (countDistinct(lprlpr), countDistinct(lplplp))
    }

    public static func primal12TETMaxNontrivialAbsLambda() -> Double {
        let shifts = [3.0, 4.0, 5.0, 7.0, 8.0, 9.0]
        var best = 0.0
        for k in 1..<12 {
            let kf = Double(k)
            var sum = 0.0
            var comp = 0.0
            for s in shifts {
                let term = cos(2.0 * Double.pi * kf * s / 12.0)
                if !term.isFinite { return .nan }
                let t = sum + term
                if abs(sum) >= abs(term) {
                    comp += (sum - t) + term
                } else {
                    comp += (term - t) + sum
                }
                sum = t
            }
            let mag = abs(sum + comp)
            if !mag.isFinite { return .nan }
            if mag > best { best = mag }
        }
        return best
    }
}

// MARK: - Strongly-Typed Codable Schema for `riemann_lattice_graph_rh_v1.json`

public struct RiemannLatticeVault: Codable, Sendable {
    public struct AntiConflationGuard: Codable, Sendable {
        public let sharedHistoricalRoot: String
        public let finiteGraphRhScope: String
        public let classicalRhSeparation: String

        enum CodingKeys: String, CodingKey {
            case sharedHistoricalRoot = "shared_historical_root"
            case finiteGraphRhScope = "finite_graph_rh_scope"
            case classicalRhSeparation = "classical_rh_separation"
        }
    }

    public struct GraphRHVerdictRecord: Codable, Sendable {
        public let satisfiesGraphRiemannHypothesis: Bool
        public let isRamanujan: Bool
        public let ramanujanBoundSquared4q: Int
        public let maxNontrivialLambdaSquared: Int
        public let exactIntegerSquaredMargin: Int

        enum CodingKeys: String, CodingKey {
            case satisfiesGraphRiemannHypothesis = "satisfies_graph_riemann_hypothesis"
            case isRamanujan = "is_ramanujan"
            case ramanujanBoundSquared4q = "ramanujan_bound_squared_4q"
            case maxNontrivialLambdaSquared = "max_nontrivial_lambda_squared"
            case exactIntegerSquaredMargin = "exact_integer_squared_margin"
        }
    }

    public struct HexagonDecomposition: Codable, Sendable {
        public let lprlprPitchClassDualFaces: Int
        public let lplplpHexatonicCycles: Int

        enum CodingKeys: String, CodingKey {
            case lprlprPitchClassDualFaces = "LPRLPR_pitch_class_dual_faces"
            case lplplpHexatonicCycles = "LPLPLP_hexatonic_cycles"
        }
    }

    public struct MinimalHexagons: Codable, Sendable {
        public let totalUnoriented: Int
        public let totalOriented: Int
        public let decomposition: HexagonDecomposition

        enum CodingKeys: String, CodingKey {
            case totalUnoriented = "total_unoriented"
            case totalOriented = "total_oriented"
            case decomposition
        }
    }

    public struct PrimeCycleEntry: Codable, Sendable {
        public let lengthM: Int
        public let closedNBWalks: Int64
        public let orientedPrimes: Int64
        public let unorientedPrimes: Int64

        enum CodingKeys: String, CodingKey {
            case lengthM = "length_m"
            case closedNBWalks = "closed_nb_walks_N_m"
            case orientedPrimes = "oriented_primes"
            case unorientedPrimes = "unoriented_primes"
        }
    }

    public struct TonnetzDualInvariants: Codable, Sendable {
        public let verticesCount: Int
        public let edgesCount: Int
        public let degreeD: Int
        public let iharaParameterQ: Int
        public let exactCharpolyBBTDescendingY: [Int64]
        public let graphRhVerdict: GraphRHVerdictRecord
        public let minimalPrimeHexagonsLength6: MinimalHexagons
        public let exactPrimeCycleTable: [PrimeCycleEntry]

        enum CodingKeys: String, CodingKey {
            case verticesCount = "vertices_count"
            case edgesCount = "edges_count"
            case degreeD = "degree_d"
            case iharaParameterQ = "ihara_parameter_q"
            case exactCharpolyBBTDescendingY = "exact_charpoly_B_BT_descending_y"
            case graphRhVerdict = "graph_rh_verdict"
            case minimalPrimeHexagonsLength6 = "minimal_prime_hexagons_length_6"
            case exactPrimeCycleTable = "exact_prime_cycle_table"
        }
    }

    public struct PrimalSummary: Codable, Sendable {
        public let verticesCount: Int
        public let edgesCount: Int
        public let degreeD: Int
        public let iharaParameterQ: Int
        public let maxNontrivialAbsLambdaApprox: Double
        public let satisfiesGraphRiemannHypothesis: Bool

        enum CodingKeys: String, CodingKey {
            case verticesCount = "vertices_count"
            case edgesCount = "edges_count"
            case degreeD = "degree_d"
            case iharaParameterQ = "ihara_parameter_q"
            case maxNontrivialAbsLambdaApprox = "max_nontrivial_abs_lambda_approx"
            case satisfiesGraphRiemannHypothesis = "satisfies_graph_riemann_hypothesis"
        }
    }

    public struct NTetSweepEntry: Codable, Sendable {
        public let n: Int
        public let vertices: Int
        public let p5: Int
        public let m3: Int
        public let minorThird: Int
        public let connected: Bool
        public let maxLambdaSq: Double?
        public let satisfiesGraphRh: Bool

        enum CodingKeys: String, CodingKey {
            case n = "N"
            case vertices
            case p5 = "P5"
            case m3 = "M3"
            case minorThird = "m3"
            case connected
            case maxLambdaSq = "max_lambda_sq"
            case satisfiesGraphRh = "satisfies_graph_rh"
        }
    }

    public let schemaVersion: String
    public let traditionId: String
    public let antiConflationGuard: AntiConflationGuard
    public let tonnetzDualExactInvariants: TonnetzDualInvariants
    public let primal12TETTonnetzSummary: PrimalSummary
    public let ntetCorrespondenceRegimeSweep: [NTetSweepEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case traditionId = "tradition_id"
        case antiConflationGuard = "anti_conflation_guard"
        case tonnetzDualExactInvariants = "tonnetz_dual_exact_invariants"
        case primal12TETTonnetzSummary = "primal_12tet_tonnetz_summary"
        case ntetCorrespondenceRegimeSweep = "ntet_correspondence_regime_sweep"
    }
}

// MARK: - Atomic Fail-Closed Vault Parity Verifier

public enum RiemLatticeVaultVerifier {
    public static func evaluate(rawJSON: String) -> [CompartmentGuardVerdict] {
        guard let data = rawJSON.data(using: .utf8) else {
            return [
                CompartmentGuardVerdict(
                    compartment: "vault_utf8_decode",
                    passed: false,
                    detail: "vault input is not valid UTF-8",
                    healingAction: "Encode vault file as valid UTF-8 JSON."
                )
            ]
        }

        let vault: RiemannLatticeVault
        do {
            vault = try JSONDecoder().decode(RiemannLatticeVault.self, from: data)
        } catch {
            return [
                CompartmentGuardVerdict(
                    compartment: "vault_json_decode",
                    passed: false,
                    detail: "JSON schema decode failed: \(error)",
                    healingAction: "Repair schema fields in data/sources/riemann_lattice_graph_rh_v1.json."
                )
            ]
        }

        var verdicts: [CompartmentGuardVerdict] = []

        // Guard 1: Tradition tag & primary-source hygiene (0 wiki URLs)
        let lower = rawJSON.lowercased()
        let tradOk = vault.traditionId == "RIEM-LATTICE"
            && !lower.contains("wikipedia.org")
            && !lower.contains("wikisource.org")
        verdicts.append(CompartmentGuardVerdict(
            compartment: "vault_tradition_and_provenance",
            passed: tradOk,
            detail: tradOk
                ? "tradition_id=RIEM-LATTICE, anti_conflation_guard decoded, 0 wiki URLs"
                : "invalid tradition_id or banned wiki domain detected",
            healingAction: tradOk ? nil : "Set tradition_id=\"RIEM-LATTICE\" and replace any wiki URLs with primary archives."
        ))

        let sys12 = NTetSystem.canonical12TET
        let adj = sys12.adjacencyMatrix()
        let gram = sys12.gramMatrix()
        let inv = vault.tonnetzDualExactInvariants

        // Guard 2: Basic 24-vertex, 36-edge, 3-regular bipartite invariants
        let directedEdges = adj.reduce(0) { $0 + $1.reduce(0, +) }
        let allDeg3 = adj.allSatisfy { $0.reduce(0, +) == 3 }
        let graphOk = allDeg3
            && directedEdges == 72
            && inv.verticesCount == 24
            && inv.edgesCount == 36
            && inv.degreeD == 3
            && inv.iharaParameterQ == 2
        verdicts.append(CompartmentGuardVerdict(
            compartment: "g_plr_graph_invariants",
            passed: graphOk,
            detail: graphOk
                ? "|V|=24, |E|=36, 3-regular bipartite, q=2 verified"
                : "G_PLR structural invariant mismatch between computed graph and vault",
            healingAction: graphOk ? nil : "Recompute G_PLR = Cay(D_12, {P, L, R}) invariants from first principles."
        ))

        // Guard 3: Mutual centralizer duality + 12-TET 2-of-3 parsimony
        let mcViol = sys12.mutualCentralizerViolations() + sys12.parsimonyViolations()
        verdicts.append(CompartmentGuardVerdict(
            compartment: "g_plr_mutual_centralizer_duality",
            passed: mcViol == 0,
            detail: mcViol == 0
                ? "0 violations across all 24 triads x 12 shifts/axes x {P,L,R}"
                : "\(mcViol) mutual centralizer / parsimony violations",
            healingAction: mcViol == 0 ? nil : "Verify T_n, I_n, and PLR action formulas in NTetSystem."
        ))

        // Guard 4: Exact Z Faddeev-LeVerrier characteristic polynomial & Cayley-Hamilton remainder
        let (charPoly, chZero) = RiemLatticeEngine.faddeevLeVerrierExact(gram)
        let charOk = chZero && charPoly == inv.exactCharpolyBBTDescendingY
        verdicts.append(CompartmentGuardVerdict(
            compartment: "g_plr_exact_charpoly_over_Z",
            passed: charOk,
            detail: charOk
                ? "exact Faddeev-LeVerrier charpoly matches vault with 0 Cayley-Hamilton remainder"
                : "charpoly mismatch between exact Faddeev-LeVerrier and vault JSON",
            healingAction: charOk ? nil : "Recompute det(y I_12 - B B^T) over Z without floating-point approximation."
        ))

        // Guard 5: Exact Q 24x24 Bass-Ihara determinant identity + completed functional equation
        let testUs = [ExactRat(1, 3), ExactRat(1, 5), ExactRat(2, 7), ExactRat(3, 11)]
        var biViol = 0
        for u in testUs {
            let detMat = RiemLatticeEngine.bassIharaMatrixDet(adj: adj, u: u)
            let detFac = RiemLatticeEngine.bassIharaDFactored12TET(u: u)
            if detMat != detFac { biViol += 1 }
            let rhs = (ExactRat(2, 1) * u * u).pow(24) * RiemLatticeEngine.bassIharaDFactored12TET(u: ExactRat(1, 2) / u)
            if detFac != rhs { biViol += 1 }
        }
        let rhOk = biViol == 0
            && inv.graphRhVerdict.satisfiesGraphRiemannHypothesis
            && inv.graphRhVerdict.exactIntegerSquaredMargin == 3
        verdicts.append(CompartmentGuardVerdict(
            compartment: "g_plr_bass_ihara_and_functional_eq_over_Q",
            passed: rhOk,
            detail: rhOk
                ? "exact 24x24 det(I - uA + 2u^2 I) = D(u) = (2u^2)^24 D(1/(2u)) verified over Q; margin=3"
                : "Bass-Ihara rational identity or Graph-RH margin mismatch (\(biViol) violations)",
            healingAction: rhOk ? nil : "Verify exact Q Bass-Ihara factorization and functional equation exponent 24."
        ))

        // Guard 6: Exact prime-cycle table (m=2..20) + 12 LPRLPR + 4 LPLPLP minimal hexagons
        let zetaInv = RiemLatticeEngine.zetaInversePoly12TET()
        let computedPrimes = RiemLatticeEngine.computePrimeCycleTable(zetaInv: zetaInv, maxM: 20)
        let hex = RiemLatticeEngine.enumerateMusicalHexagons12TET()
        var primeViol = 0
        if computedPrimes.count != inv.exactPrimeCycleTable.count {
            primeViol += 1
        } else {
            for (c, v) in zip(computedPrimes, inv.exactPrimeCycleTable) {
                if c.lengthM != v.lengthM
                    || c.closedNBWalks != v.closedNBWalks
                    || c.orientedPrimes != v.orientedPrimes
                    || c.unorientedPrimes != v.unorientedPrimes
                {
                    primeViol += 1
                }
            }
        }
        if inv.minimalPrimeHexagonsLength6.totalUnoriented != 16
            || inv.minimalPrimeHexagonsLength6.decomposition.lprlprPitchClassDualFaces != hex.lprlpr
            || inv.minimalPrimeHexagonsLength6.decomposition.lplplpHexatonicCycles != hex.lplplp
            || hex.lprlpr != 12
            || hex.lplplp != 4
        {
            primeViol += 1
        }
        verdicts.append(CompartmentGuardVerdict(
            compartment: "g_plr_prime_cycles_and_16_hexagons",
            passed: primeViol == 0,
            detail: primeViol == 0
                ? "10 prime-cycle rows (m=2..20) + 12 LPRLPR + 4 LPLPLP = 16 minimal hexagons verified"
                : "\(primeViol) prime-cycle or hexagon decomposition mismatches",
            healingAction: primeViol == 0 ? nil : "Recompute exact Mobius prime-cycle counts from zeta_inv(u)."
        ))

        // Guard 7: Primal 12-TET Tonnetz (6-regular, q=5) Ramanujan verification
        let primalLam = RiemLatticeEngine.primal12TETMaxNontrivialAbsLambda()
        let primalBound = 2.0 * sqrt(5.0)
        let primalOk = primalLam < primalBound
            && vault.primal12TETTonnetzSummary.satisfiesGraphRiemannHypothesis
            && abs(vault.primal12TETTonnetzSummary.maxNontrivialAbsLambdaApprox - primalLam) < 1e-6
        verdicts.append(CompartmentGuardVerdict(
            compartment: "primal_12tet_tonnetz_ramanujan",
            passed: primalOk,
            detail: primalOk
                ? String(format: "max|lambda|=%.6f < 2*sqrt(5)=%.6f matches vault", primalLam, primalBound)
                : "primal 12-TET Tonnetz Ramanujan summary mismatch",
            healingAction: primalOk ? nil : "Verify primal 12-TET circulant shifts {+-3, +-4, +-7} mod 12."
        ))

        // Guard 8: N-TET Correspondence-Principle regime sweep
        var sweepViol = 0
        if vault.ntetCorrespondenceRegimeSweep.isEmpty { sweepViol += 1 }
        for row in vault.ntetCorrespondenceRegimeSweep {
            let sys = NTetSystem.fromN(row.n)
            let paramsOk = row.p5 == sys.p5
                && row.m3 == sys.m3
                && row.minorThird == sys.minorThird
                && row.connected == sys.isConnected
            if !paramsOk {
                sweepViol += 1
                continue
            }
            if let lamSq = sys.maxNontrivialLambdaSquared() {
                let passesRH = lamSq <= 8.0 + 1e-12
                guard let vaultLam = row.maxLambdaSq,
                      abs(vaultLam - lamSq) < 1e-4,
                      row.satisfiesGraphRh == passesRH
                else {
                    sweepViol += 1
                    continue
                }
            } else if row.satisfiesGraphRh {
                sweepViol += 1
            }
        }
        verdicts.append(CompartmentGuardVerdict(
            compartment: "ntet_correspondence_regime_sweep",
            passed: sweepViol == 0,
            detail: sweepViol == 0
                ? "all \(vault.ntetCorrespondenceRegimeSweep.count) N-TET sweep rows verified"
                : "\(sweepViol) N-TET correspondence sweep mismatches",
            healingAction: sweepViol == 0 ? nil : "Recompute N-TET Fourier spectrum and connectivity gcd(M3, P5, N)."
        ))

        return verdicts
    }
}
