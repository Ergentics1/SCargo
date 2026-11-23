// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation

/// Typed errors raised by SCargoSweep without silent swallowing.
public enum SCargoSweepError: Error, CustomStringConvertible, Sendable {
    case invalidPolicy(String)
    case invalidFixture(String)
    case invalidRctConfig(String)
    case ioFailure(String)

    public var description: String {
        switch self {
        case .invalidPolicy(let msg): return "invalidPolicy: \(msg)"
        case .invalidFixture(let msg): return "invalidFixture: \(msg)"
        case .invalidRctConfig(let msg): return "invalidRctConfig: \(msg)"
        case .ioFailure(let msg): return "ioFailure: \(msg)"
        }
    }
}

/// Data-driven thresholds decoded directly from `data/manifests/swe_sweep_policy_v1.json`.
public struct BlindSpotThresholds: Sendable {
    public let machineUnitF64: Double
    public let highamSpreadMultiplier: Double
    public let maxConditionNumber: Double
    public let minRetainedBits: Int
    public let symmetryAbsTol: Double
    public let choleskyMinPivotSq: Double
    public let probabilityMassSumTol: Double
    public let aggregateCapMargin: Double
    public let dkwAlpha: Double
    public let minCalibrationSamples: Int
    public let coverageQuantiles: [Double]
    public let clopperPearsonAlpha: Double
    public let maxCrpsRatioToReference: Double
    public let maxBrierScore: Double
    public let oodMaxMahalanobis: Double
    public let bannedRngRust: [String]
    public let bannedRngSwift: [String]
    public let bannedRngLean: [String]
    public let minReplicatesPerStratum: Int
    public let wilcoxonAlpha: Double
    public let minVarghaDelaneyA12: Double

    public static func decode(fromPolicyData data: Data) throws -> BlindSpotThresholds {
        let decoded = try JSONDecoder().decode(PolicyEnvelope.self, from: data)
        let b = decoded.blindspot_and_seam_thresholds
        return BlindSpotThresholds(
            machineUnitF64: b.fp_determinism.machine_unit_f64,
            highamSpreadMultiplier: b.fp_determinism.higham_spread_multiplier,
            maxConditionNumber: b.fp_determinism.max_condition_number,
            minRetainedBits: b.fp_determinism.min_retained_bits,
            symmetryAbsTol: b.rt_invariants.symmetry_abs_tol,
            choleskyMinPivotSq: b.rt_invariants.cholesky_min_pivot_sq,
            probabilityMassSumTol: b.rt_invariants.probability_mass_sum_tol,
            aggregateCapMargin: b.rt_invariants.aggregate_cap_margin,
            dkwAlpha: b.prob_calibration.dkw_alpha,
            minCalibrationSamples: b.prob_calibration.min_calibration_samples,
            coverageQuantiles: b.prob_calibration.coverage_quantiles,
            clopperPearsonAlpha: b.prob_calibration.clopper_pearson_alpha,
            maxCrpsRatioToReference: b.prob_calibration.max_crps_ratio_to_reference,
            maxBrierScore: b.prob_calibration.max_brier_score,
            oodMaxMahalanobis: b.prob_calibration.ood_max_mahalanobis,
            bannedRngRust: b.seam_integrity.banned_unkeyed_rng_tokens.rust,
            bannedRngSwift: b.seam_integrity.banned_unkeyed_rng_tokens.swift,
            bannedRngLean: b.seam_integrity.banned_unkeyed_rng_tokens.lean,
            minReplicatesPerStratum: b.rct_qualification.min_replicates_per_stratum,
            wilcoxonAlpha: b.rct_qualification.wilcoxon_alpha,
            minVarghaDelaneyA12: b.rct_qualification.min_vargha_delaney_a12
        )
    }
}

public struct PolicyEnvelope: Decodable, Sendable {
    public let schema_version: String
    public let witness_compartments: [String]
    public let blindspot_and_seam_thresholds: ThresholdsDTO

    public struct ThresholdsDTO: Decodable, Sendable {
        public let fp_determinism: FpDTO
        public let rt_invariants: RtDTO
        public let prob_calibration: CalDTO
        public let seam_integrity: SeamDTO
        public let rct_qualification: RctDTO
    }
    public struct FpDTO: Decodable, Sendable {
        public let machine_unit_f64: Double
        public let higham_spread_multiplier: Double
        public let max_condition_number: Double
        public let min_retained_bits: Int
    }
    public struct RtDTO: Decodable, Sendable {
        public let symmetry_abs_tol: Double
        public let cholesky_min_pivot_sq: Double
        public let probability_mass_sum_tol: Double
        public let aggregate_cap_margin: Double
    }
    public struct CalDTO: Decodable, Sendable {
        public let dkw_alpha: Double
        public let min_calibration_samples: Int
        public let coverage_quantiles: [Double]
        public let clopper_pearson_alpha: Double
        public let max_crps_ratio_to_reference: Double
        public let max_brier_score: Double
        public let ood_max_mahalanobis: Double
    }
    public struct SeamDTO: Decodable, Sendable {
        public let banned_unkeyed_rng_tokens: RngTokensDTO
    }
    public struct RngTokensDTO: Decodable, Sendable {
        public let rust: [String]
        public let swift: [String]
        public let lean: [String]
    }
    public struct RctDTO: Decodable, Sendable {
        public let min_replicates_per_stratum: Int
        public let wilcoxon_alpha: Double
        public let min_vargha_delaney_a12: Double
    }
}

/// Deterministic keyed SplitMix64 PRNG matching Rust bit-for-bit.
public struct SweepSplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z &>> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z &>> 31)
    }

    public mutating func nextUnitDouble() -> Double {
        Double(nextUInt64() &>> 11) * (1.0 / Double(UInt64(1) << 53))
    }

    public mutating func nextNormal() -> Double {
        let rawU1 = nextUnitDouble()
        let u1 = rawU1 > 1e-15 ? rawU1 : 1e-15
        let u2 = nextUnitDouble()
        return sqrt(-2.0 * log(u1)) * cos(2.0 * Double.pi * u2)
    }
}

// MARK: - 1. D-Type: Floating-Point Non-Associativity & Cancellation

public func neumaierSum(_ xs: [Double]) -> Double {
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

public func naiveSum(_ xs: [Double]) -> Double {
    var acc = 0.0
    for x in xs {
        if !x.isFinite { return .nan }
        acc += x
    }
    return acc
}

public struct FpDeterminismReport: Sendable {
    public let passed: Bool
    public let compensatedSum: Double
    public let maxOrderSpread: Double
    public let conditionNumber: Double
    public let highamBound: Double
    public let retainedBits: Double
    public let detail: String
}

public func evaluateFpDeterminism(
    _ xs: [Double],
    exactReference: Double?,
    thresholds t: BlindSpotThresholds
) -> FpDeterminismReport {
    if xs.isEmpty || xs.contains(where: { !$0.isFinite }) {
        return FpDeterminismReport(
            passed: false,
            compensatedSum: .nan,
            maxOrderSpread: .infinity,
            conditionNumber: .infinity,
            highamBound: 0.0,
            retainedBits: 0.0,
            detail: "empty or non-finite floating-point input vector"
        )
    }

    let comp = neumaierSum(xs)
    let l1Norm = neumaierSum(xs.map { abs($0) })
    let refVal = exactReference ?? comp

    let forward = naiveSum(xs)
    let reverse = naiveSum(Array(xs.reversed()))
    let magAsc = xs.sorted { abs($0) < abs($1) }
    let ascSum = naiveSum(magAsc)
    let magDesc = Array(magAsc.reversed())
    let descSum = naiveSum(magDesc)

    var alt: [Double] = []
    alt.reserveCapacity(xs.count)
    var lo = 0
    var hi = magDesc.count
    while lo < hi {
        alt.append(magDesc[lo])
        lo += 1
        if lo < hi {
            hi -= 1
            alt.append(magDesc[hi])
        }
    }
    let altSum = naiveSum(alt)

    var maxSpread = 0.0
    for s in [forward, reverse, ascSum, descSum, altSum] {
        if !s.isFinite {
            maxSpread = .infinity
            break
        }
        let d = abs(s - refVal)
        if d > maxSpread { maxSpread = d }
    }

    let n = Double(xs.count)
    let nu = n * t.machineUnitF64
    let gammaN = nu < 1.0 ? (nu / (1.0 - nu)) : .infinity
    let denom = abs(refVal) > t.machineUnitF64 ? abs(refVal) : t.machineUnitF64
    let cond = l1Norm / denom
    let condClamped = cond > 1.0 ? cond : 1.0
    let retainedRaw = 53.0 - log2(condClamped)
    let retainedBits = retainedRaw > 0.0 ? retainedRaw : 0.0
    let highamBound = t.highamSpreadMultiplier * gammaN * (denom > 1.0 ? denom : 1.0)

    let passed = comp.isFinite
        && maxSpread.isFinite
        && cond.isFinite
        && cond <= t.maxConditionNumber
        && retainedBits >= Double(t.minRetainedBits)
        && maxSpread <= highamBound

    return FpDeterminismReport(
        passed: passed,
        compensatedSum: comp,
        maxOrderSpread: maxSpread,
        conditionNumber: cond,
        highamBound: highamBound,
        retainedBits: retainedBits,
        detail: String(format: "spread=%.3e (bound=%.3e), kappa=%.3e, retained_bits=%.1f", maxSpread, highamBound, cond, retainedBits)
    )
}

// MARK: - 2. R-Type: Global Matrix SPD, Positive Finiteness & Aggregate Conservation

public struct SpdReport: Sendable {
    public let passed: Bool
    public let symmetric: Bool
    public let allFinite: Bool
    public let minPivotSq: Double
    public let detail: String
}

public func evaluateSpdMatrix(_ rows: [[Double]], thresholds t: BlindSpotThresholds) -> SpdReport {
    let n = rows.count
    if n == 0 || rows.contains(where: { $0.count != n }) {
        return SpdReport(passed: false, symmetric: false, allFinite: false, minPivotSq: .nan, detail: "empty or non-square matrix")
    }
    for row in rows {
        if row.contains(where: { !$0.isFinite }) {
            return SpdReport(passed: false, symmetric: false, allFinite: false, minPivotSq: .nan, detail: "non-finite entry in covariance matrix")
        }
    }
    for i in 0..<n {
        for j in (i + 1)..<n {
            if abs(rows[i][j] - rows[j][i]) > t.symmetryAbsTol {
                return SpdReport(passed: false, symmetric: false, allFinite: true, minPivotSq: .nan, detail: "asymmetry at (\(i),\(j))")
            }
        }
    }

    var l = Array(repeating: Array(repeating: 0.0, count: n), count: n)
    var minPivotSq = Double.infinity
    for i in 0..<n {
        for j in 0...i {
            var terms: [Double] = []
            terms.reserveCapacity(j)
            for k in 0..<j {
                terms.append(l[i][k] * l[j][k])
            }
            let dot = neumaierSum(terms)
            if !dot.isFinite {
                return SpdReport(passed: false, symmetric: true, allFinite: false, minPivotSq: .nan, detail: "non-finite Cholesky inner product")
            }
            if i == j {
                let diagVal = rows[i][i] - dot
                if !diagVal.isFinite || diagVal <= t.choleskyMinPivotSq {
                    return SpdReport(
                        passed: false,
                        symmetric: true,
                        allFinite: diagVal.isFinite,
                        minPivotSq: diagVal,
                        detail: "indefinite Cholesky pivot \(diagVal) at index \(i)"
                    )
                }
                if diagVal < minPivotSq { minPivotSq = diagVal }
                l[i][j] = sqrt(diagVal)
            } else {
                l[i][j] = (rows[i][j] - dot) / l[j][j]
            }
        }
    }

    let ok = minPivotSq.isFinite && minPivotSq > t.choleskyMinPivotSq
    return SpdReport(
        passed: ok,
        symmetric: true,
        allFinite: true,
        minPivotSq: minPivotSq,
        detail: String(format: "SPD certified: min Cholesky pivot^2 = %.6e", minPivotSq)
    )
}

public struct StateInvariantReport: Sendable {
    public let passed: Bool
    public let allFinite: Bool
    public let cellBoundsOk: Bool
    public let aggregateCapOk: Bool
    public let simplexOk: Bool
    public let l1Norm: Double
    public let detail: String
}

public func evaluateStateInvariants(
    _ vec: [Double],
    cellAbsBound: Double,
    aggregateAbsCap: Double,
    requireProbSimplex: Bool,
    thresholds t: BlindSpotThresholds
) -> StateInvariantReport {
    if vec.isEmpty || !cellAbsBound.isFinite || !aggregateAbsCap.isFinite {
        return StateInvariantReport(
            passed: false, allFinite: false, cellBoundsOk: false, aggregateCapOk: false, simplexOk: false,
            l1Norm: .nan, detail: "empty state or non-finite bounds"
        )
    }
    let allFinite = vec.allSatisfy { $0.isFinite }
    if !allFinite {
        return StateInvariantReport(
            passed: false, allFinite: false, cellBoundsOk: false, aggregateCapOk: false, simplexOk: false,
            l1Norm: .nan, detail: "non-finite (NaN/Inf) sample detected in state vector"
        )
    }
    let cellOk = vec.allSatisfy { abs($0) <= cellAbsBound }
    let l1Norm = neumaierSum(vec.map { abs($0) })
    let aggOk = l1Norm.isFinite && l1Norm <= aggregateAbsCap + t.aggregateCapMargin
    let simpOk: Bool
    if requireProbSimplex {
        let nonneg = vec.allSatisfy { $0 >= -t.probabilityMassSumTol }
        let mass = neumaierSum(vec)
        simpOk = nonneg && mass.isFinite && abs(mass - 1.0) <= t.probabilityMassSumTol
    } else {
        simpOk = true
    }
    let passed = allFinite && cellOk && aggOk && simpOk
    return StateInvariantReport(
        passed: passed,
        allFinite: allFinite,
        cellBoundsOk: cellOk,
        aggregateCapOk: aggOk,
        simplexOk: simpOk,
        l1Norm: l1Norm,
        detail: String(format: "finite=%@, cell_ok=%@, l1=%.4f (cap=%.4f), simplex_ok=%@", "\(allFinite)", "\(cellOk)", l1Norm, aggregateAbsCap, "\(simpOk)")
    )
}

// MARK: - 3. P-Type: Distribution-Free Calibration (Massart-DKW, Clopper-Pearson, CRPS/Brier, OOD)

public func erfApprox(_ x: Double) -> Double {
    let sign = x < 0.0 ? -1.0 : 1.0
    let ax = abs(x)
    let t = 1.0 / (1.0 + 0.3275911 * ax)
    let poly = ((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592
    return sign * (1.0 - poly * t * exp(-ax * ax))
}

public func normalCdf(_ z: Double) -> Double {
    0.5 * (1.0 + erfApprox(z / sqrt(2.0)))
}

public func normalPdf(_ z: Double) -> Double {
    exp(-0.5 * z * z) / sqrt(2.0 * Double.pi)
}

public func normalCentralZ(_ coverage: Double) -> Double {
    let target = 0.5 + 0.5 * coverage
    var lo = 0.0
    var hi = 8.0
    for _ in 0..<80 {
        let mid = 0.5 * (lo + hi)
        if normalCdf(mid) < target { lo = mid } else { hi = mid }
    }
    return 0.5 * (lo + hi)
}

private func binomPmf(n: Int, k: Int, p: Double, lfacts: [Double]) -> Double {
    if p <= 0.0 { return k == 0 ? 1.0 : 0.0 }
    if p >= 1.0 { return k == n ? 1.0 : 0.0 }
    let lp = lfacts[n] - lfacts[k] - lfacts[n - k]
        + Double(k) * log(p)
        + Double(n - k) * log(1.0 - p)
    return exp(lp)
}

private func binomTailUpper(n: Int, k: Int, p: Double, lfacts: [Double]) -> Double {
    var terms: [Double] = []
    terms.reserveCapacity(n - k + 1)
    for j in k...n {
        terms.append(binomPmf(n: n, k: j, p: p, lfacts: lfacts))
    }
    return neumaierSum(terms)
}

private func binomTailLower(n: Int, k: Int, p: Double, lfacts: [Double]) -> Double {
    var terms: [Double] = []
    terms.reserveCapacity(k + 1)
    for j in 0...k {
        terms.append(binomPmf(n: n, k: j, p: p, lfacts: lfacts))
    }
    return neumaierSum(terms)
}

public func clopperPearsonCI(k: Int, n: Int, alpha: Double) -> (Double, Double) {
    if n <= 0 || k < 0 || k > n { return (0.0, 1.0) }
    var lfacts = Array(repeating: 0.0, count: n + 1)
    if n >= 2 {
        for i in 2...n {
            lfacts[i] = lfacts[i - 1] + log(Double(i))
        }
    }
    let halfAlpha = 0.5 * alpha

    let lower: Double
    if k == 0 {
        lower = 0.0
    } else {
        var lo = 0.0
        var hi = Double(k) / Double(n)
        for _ in 0..<80 {
            let mid = 0.5 * (lo + hi)
            if binomTailUpper(n: n, k: k, p: mid, lfacts: lfacts) < halfAlpha { lo = mid } else { hi = mid }
        }
        lower = 0.5 * (lo + hi)
    }

    let upper: Double
    if k == n {
        upper = 1.0
    } else {
        var lo = Double(k) / Double(n)
        var hi = 1.0
        for _ in 0..<80 {
            let mid = 0.5 * (lo + hi)
            if binomTailLower(n: n, k: k, p: mid, lfacts: lfacts) < halfAlpha { hi = mid } else { lo = mid }
        }
        upper = 0.5 * (lo + hi)
    }

    return (lower, upper)
}

public func dkwBound(n: Int, alpha: Double) -> Double {
    guard n > 0 && alpha > 0.0 && alpha < 1.0 else { return 0.0 }
    return sqrt(log(2.0 / alpha) / (2.0 * Double(n)))
}

public func calibrationPitDkwStat(_ pitValues: [Double]) -> Double {
    if pitValues.isEmpty || pitValues.contains(where: { !$0.isFinite }) {
        return .infinity
    }
    let sorted = pitValues.sorted()
    let n = Double(sorted.count)
    var maxD = 0.0
    for (idx, u) in sorted.enumerated() {
        let i = Double(idx + 1)
        let dPlus = abs(i / n - u)
        let dMinus = abs(u - (i - 1.0) / n)
        let d = dPlus >= dMinus ? dPlus : dMinus
        if d > maxD { maxD = d }
    }
    return maxD
}

public func generateCalibrationSamples(
    seed: UInt64,
    n: Int,
    trueMean: Double,
    trueStd: Double,
    mixtureWeightSecond: Double,
    mixtureShift: Double
) -> [Double] {
    var rng = SweepSplitMix64(seed: seed)
    var out: [Double] = []
    out.reserveCapacity(n)
    for _ in 0..<n {
        let u = rng.nextUnitDouble()
        let z = rng.nextNormal()
        let center: Double
        if mixtureWeightSecond > 0.0 {
            center = u < mixtureWeightSecond ? (trueMean - mixtureShift) : (trueMean + mixtureShift)
        } else {
            center = trueMean
        }
        out.append(center + trueStd * z)
    }
    return out
}

public struct CalibrationReport: Sendable {
    public let passed: Bool
    public let sampleCount: Int
    public let dkwStat: Double
    public let dkwLimit: Double
    public let crpsMean: Double
    public let crpsRatio: Double
    public let brierMean: Double
    public let coverageViolations: Int
    public let oodMahalanobis: Double
    public let detail: String
}

public func evaluateProbCalibration(
    samples: [Double],
    declaredMean: Double,
    declaredStd: Double,
    oodQueryZ: Double,
    thresholds t: BlindSpotThresholds
) -> CalibrationReport {
    let n = samples.count
    if n < t.minCalibrationSamples
        || !declaredMean.isFinite
        || !declaredStd.isFinite
        || declaredStd <= 0.0
        || !oodQueryZ.isFinite
        || samples.contains(where: { !$0.isFinite })
    {
        return CalibrationReport(
            passed: false,
            sampleCount: n,
            dkwStat: .infinity,
            dkwLimit: dkwBound(n: n > 0 ? n : 1, alpha: t.dkwAlpha),
            crpsMean: .infinity,
            crpsRatio: .infinity,
            brierMean: 1.0,
            coverageViolations: t.coverageQuantiles.count,
            oodMahalanobis: .infinity,
            detail: "insufficient samples or invalid/non-finite predictive parameters"
        )
    }

    let invSqrtPi = 1.0 / sqrt(Double.pi)
    var pits: [Double] = []
    var crpsVals: [Double] = []
    var brierVals: [Double] = []
    pits.reserveCapacity(n)
    crpsVals.reserveCapacity(n)
    brierVals.reserveCapacity(n)
    let brierThresholds = [declaredMean - declaredStd, declaredMean, declaredMean + declaredStd]

    for y in samples {
        let z = (y - declaredMean) / declaredStd
        let u = normalCdf(z)
        pits.append(u)
        crpsVals.append(declaredStd * (z * (2.0 * u - 1.0) + 2.0 * normalPdf(z) - invSqrtPi))

        var bAcc = 0.0
        for thr in brierThresholds {
            let pPred = normalCdf((thr - declaredMean) / declaredStd)
            let ind = y <= thr ? 1.0 : 0.0
            let diff = pPred - ind
            bAcc += diff * diff
        }
        brierVals.append(bAcc / Double(brierThresholds.count))
    }

    let dkwStat = calibrationPitDkwStat(pits)
    let dkwLimit = dkwBound(n: n, alpha: t.dkwAlpha)
    let crpsMean = neumaierSum(crpsVals) / Double(n)
    let oracleCrps = declaredStd * invSqrtPi
    let crpsRatio = crpsMean / oracleCrps
    let brierMean = neumaierSum(brierVals) / Double(n)

    var coverageViolations = 0
    for q in t.coverageQuantiles {
        let zQ = normalCentralZ(q)
        let covered = samples.filter { abs($0 - declaredMean) / declaredStd <= zQ }.count
        let (ciLo, ciHi) = clopperPearsonCI(k: covered, n: n, alpha: t.clopperPearsonAlpha)
        if q < ciLo || q > ciHi {
            coverageViolations += 1
        }
    }

    let oodMaha = abs(oodQueryZ)
    let passed = dkwStat <= dkwLimit
        && crpsRatio <= t.maxCrpsRatioToReference
        && brierMean <= t.maxBrierScore
        && coverageViolations == 0
        && oodMaha <= t.oodMaxMahalanobis

    return CalibrationReport(
        passed: passed,
        sampleCount: n,
        dkwStat: dkwStat,
        dkwLimit: dkwLimit,
        crpsMean: crpsMean,
        crpsRatio: crpsRatio,
        brierMean: brierMean,
        coverageViolations: coverageViolations,
        oodMahalanobis: oodMaha,
        detail: String(format: "DKW=%.4f (limit=%.4f), CRPS_ratio=%.3f, Brier=%.4f, cov_viol=%d, OOD_z=%.2f", dkwStat, dkwLimit, crpsRatio, brierMean, coverageViolations, oodMaha)
    )
}

// MARK: - 4. Cross-Type Seam Integrity (P -> D CertifiedEstimate & D -> P Keyed Replay)

public struct RawProbEstimate: Sendable {
    public let pointEstimate: Double
    public let calibrated: Bool
    public let inDomain: Bool
    public let oodMahalanobis: Double
    public let sampleCount: Int
    public let actuatorBypassedCertificate: Bool

    public init(
        pointEstimate: Double,
        calibrated: Bool,
        inDomain: Bool,
        oodMahalanobis: Double,
        sampleCount: Int,
        actuatorBypassedCertificate: Bool
    ) {
        self.pointEstimate = pointEstimate
        self.calibrated = calibrated
        self.inDomain = inDomain
        self.oodMahalanobis = oodMahalanobis
        self.sampleCount = sampleCount
        self.actuatorBypassedCertificate = actuatorBypassedCertificate
    }
}

public struct CertifiedEstimate: Sendable {
    public let value: Double
    fileprivate init(value: Double) { self.value = value }
}

public func admitPToD(_ est: RawProbEstimate, thresholds t: BlindSpotThresholds) -> CertifiedEstimate? {
    guard est.pointEstimate.isFinite,
          est.oodMahalanobis.isFinite,
          est.calibrated,
          est.inDomain,
          !est.actuatorBypassedCertificate,
          est.oodMahalanobis <= t.oodMaxMahalanobis,
          est.sampleCount >= t.minCalibrationSamples
    else {
        return nil
    }
    return CertifiedEstimate(value: est.pointEstimate)
}

public func keyedSimulationDigest(seed: UInt64, steps: Int) -> String {
    var rng = SweepSplitMix64(seed: seed)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(steps * 8)
    for _ in 0..<steps {
        let v = rng.nextUInt64()
        for shift in stride(from: 0, through: 56, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: v &>> UInt64(shift)))
        }
    }
    return PureSHA256.hex(bytes)
}
