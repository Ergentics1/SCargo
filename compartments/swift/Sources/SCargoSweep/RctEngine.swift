// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation

public struct RctConfigDTO: Decodable, Sendable {
    public let trial_id: String
    public let master_seed: UInt64
    public let replicates_per_stratum: Int
    public let calibration_sample_size: Int
    public let strata: [StratumSpecDTO]

    public struct StratumSpecDTO: Decodable, Sendable {
        public let id: String
        public let witness: String
        public let defect_class: String
    }
}

public struct StratumRctResult: Sendable {
    public let stratumId: String
    public let witnessId: String
    public let defectClass: String
    public let isProbabilistic: Bool
    public let replicates: Int
    public let controlKills: Int
    public let treatmentKills: Int
    public let cleanReplicates: Int
    public let controlFalsePositives: Int
    public let treatmentFalsePositives: Int
    public let treatmentTprCI99: (Double, Double)
    public let treatmentFprCI99: (Double, Double)
    public let wilcoxonU: Double
    public let wilcoxonPTwoTailed: Double
    public let varghaDelaneyA12: Double
    public let promoted: Bool
}

public struct RctR1Receipt: Sendable {
    public let trialId: String
    public let masterSeed: UInt64
    public let replicatesPerStratum: Int
    public let allStrataPromoted: Bool
    public let strata: [StratumRctResult]

    public func toCanonicalJSON() throws -> String {
        struct StratumJSON: Encodable {
            let clean_replicates: Int
            let control_false_positives: Int
            let control_kills: Int
            let defect_class: String
            let is_probabilistic: Bool
            let promoted: Bool
            let replicates: Int
            let stratum_id: String
            let treatment_false_positives: Int
            let treatment_kills: Int
            let vargha_delaney_a12_milli: UInt64
            let wilcoxon_p_lt_alpha: Bool
            let witness_id: String
        }
        struct ReceiptJSON: Encodable {
            let all_strata_promoted: Bool
            let master_seed: UInt64
            let replicates_per_stratum: Int
            let strata: [StratumJSON]
            let trial_id: String
        }
        let dto = ReceiptJSON(
            all_strata_promoted: allStrataPromoted,
            master_seed: masterSeed,
            replicates_per_stratum: replicatesPerStratum,
            strata: strata.map { s in
                StratumJSON(
                    clean_replicates: s.cleanReplicates,
                    control_false_positives: s.controlFalsePositives,
                    control_kills: s.controlKills,
                    defect_class: s.defectClass,
                    is_probabilistic: s.isProbabilistic,
                    promoted: s.promoted,
                    replicates: s.replicates,
                    stratum_id: s.stratumId,
                    treatment_false_positives: s.treatmentFalsePositives,
                    treatment_kills: s.treatmentKills,
                    vargha_delaney_a12_milli: UInt64((s.varghaDelaneyA12 * 1000.0).rounded()),
                    wilcoxon_p_lt_alpha: s.wilcoxonPTwoTailed < 0.01,
                    witness_id: s.witnessId
                )
            },
            trial_id: trialId
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(dto)
        guard let str = String(data: data, encoding: .utf8) else {
            throw SCargoSweepError.ioFailure("UTF-8 encode failed")
        }
        return str
    }
}

public func wilcoxonMannWhitneyA12(control: [Double], treatment: [Double]) -> (Double, Double, Double) {
    let n1 = control.count
    let n2 = treatment.count
    if n1 == 0 || n2 == 0 { return (0.0, 1.0, 0.5) }
    var u = 0.0
    for y in treatment {
        for x in control {
            if y > x { u += 1.0 } else if y == x { u += 0.5 }
        }
    }
    let prod = Double(n1 * n2)
    let a12 = u / prod

    var combined = control + treatment
    combined.sort()
    let bigN = Double(n1 + n2)
    var tieSum = 0.0
    var idx = 0
    while idx < combined.count {
        var end = idx + 1
        while end < combined.count && combined[end] == combined[idx] {
            end += 1
        }
        let t = Double(end - idx)
        if t > 1.0 { tieSum += t * t * t - t }
        idx = end
    }

    let meanU = 0.5 * prod
    let denomN = bigN * (bigN - 1.0)
    let varU = (prod / 12.0) * ((bigN + 1.0) - tieSum / denomN)
    if varU <= 0.0 || !varU.isFinite {
        return (u, 1.0, a12)
    }
    let diffAdj = abs(u - meanU) - 0.5
    let z = (diffAdj > 0.0 ? diffAdj : 0.0) / sqrt(varU)
    let rawP = 2.0 * (1.0 - normalCdf(z))
    let pTwoTailed = rawP < 0.0 ? 0.0 : (rawP > 1.0 ? 1.0 : rawP)
    return (u, pTwoTailed, a12)
}

public func runRctR1(policyURL: URL, configURL: URL) throws -> RctR1Receipt {
    let policyData = try Data(contentsOf: policyURL)
    let t = try BlindSpotThresholds.decode(fromPolicyData: policyData)
    let cfgData = try Data(contentsOf: configURL)
    let cfg = try JSONDecoder().decode(RctConfigDTO.self, from: cfgData)

    var rng = SweepSplitMix64(seed: cfg.master_seed)
    var results: [StratumRctResult] = []
    results.reserveCapacity(cfg.strata.count)

    for s in cfg.strata {
        let isProb = s.id == "STRAT-P-CAL"
        var ctrlScores: [Double] = []
        var trtScores: [Double] = []
        ctrlScores.reserveCapacity(cfg.replicates_per_stratum)
        trtScores.reserveCapacity(cfg.replicates_per_stratum)
        var ctrlFP = 0
        var trtFP = 0

        for _ in 0..<cfg.replicates_per_stratum {
            let subSeed = rng.nextUInt64()
            let (ck, tk, cfp, tfp) = try runSingleReplicate(
                stratumId: s.id,
                seed: subSeed,
                calN: cfg.calibration_sample_size,
                t: t
            )
            ctrlScores.append(ck ? 1.0 : 0.0)
            trtScores.append(tk ? 1.0 : 0.0)
            if cfp { ctrlFP += 1 }
            if tfp { trtFP += 1 }
        }

        let ctrlKills = ctrlScores.filter { $0 > 0.5 }.count
        let trtKills = trtScores.filter { $0 > 0.5 }.count
        let (u, pVal, a12) = wilcoxonMannWhitneyA12(control: ctrlScores, treatment: trtScores)
        let tprCI = clopperPearsonCI(k: trtKills, n: cfg.replicates_per_stratum, alpha: t.clopperPearsonAlpha)
        let fprCI = clopperPearsonCI(k: trtFP, n: cfg.replicates_per_stratum, alpha: t.clopperPearsonAlpha)

        let fprOk = isProb
            ? (Double(trtFP) / Double(cfg.replicates_per_stratum) <= 0.10)
            : (trtFP == 0)

        let promoted = cfg.replicates_per_stratum >= t.minReplicatesPerStratum
            && trtKills == cfg.replicates_per_stratum
            && trtKills > ctrlKills
            && pVal < t.wilcoxonAlpha
            && a12 >= t.minVarghaDelaneyA12
            && fprOk

        results.append(StratumRctResult(
            stratumId: s.id,
            witnessId: s.witness,
            defectClass: s.defect_class,
            isProbabilistic: isProb,
            replicates: cfg.replicates_per_stratum,
            controlKills: ctrlKills,
            treatmentKills: trtKills,
            cleanReplicates: cfg.replicates_per_stratum,
            controlFalsePositives: ctrlFP,
            treatmentFalsePositives: trtFP,
            treatmentTprCI99: tprCI,
            treatmentFprCI99: fprCI,
            wilcoxonU: u,
            wilcoxonPTwoTailed: pVal,
            varghaDelaneyA12: a12,
            promoted: promoted
        ))
    }

    let allPromoted = !results.isEmpty && results.allSatisfy { $0.promoted }
    return RctR1Receipt(
        trialId: cfg.trial_id,
        masterSeed: cfg.master_seed,
        replicatesPerStratum: cfg.replicates_per_stratum,
        allStrataPromoted: allPromoted,
        strata: results
    )
}

private func runSingleReplicate(
    stratumId: String,
    seed: UInt64,
    calN: Int,
    t: BlindSpotThresholds
) throws -> (Bool, Bool, Bool, Bool) {
    var r = SweepSplitMix64(seed: seed)
    switch stratumId {
    case "STRAT-D-CANCEL":
        let big = 1.0e16 * (1.0 + Double(r.nextUInt64() % 4))
        let small = 0.25 + 0.125 * Double(r.nextUInt64() % 5)
        let poisonXs = [big, -big, big, -big, small, small, small, small]
        let exact = 4.0 * small
        let ctrlKilled = abs(naiveSum(poisonXs) - exact) > 1e-6
        let trtKilled = !evaluateFpDeterminism(poisonXs, exactReference: exact, thresholds: t).passed

        let cleanXs = [1.0, 0.5, 0.25, small, 0.125, 0.0625]
        let cleanExact = neumaierSum(cleanXs)
        let ctrlFP = abs(naiveSum(cleanXs) - cleanExact) > 1e-6
        let trtFP = !evaluateFpDeterminism(cleanXs, exactReference: cleanExact, thresholds: t).passed
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    case "STRAT-R-SPD":
        let d = 1.0 + 0.5 * Double(r.nextUInt64() % 4)
        let off = d + 0.5 + 0.25 * Double(r.nextUInt64() % 3)
        let poisonM = [[d, off, 0.0], [off, d, 0.0], [0.0, 0.0, d]]
        let ctrlKilled = !(poisonM[0][0] > 0.0 && poisonM[1][1] > 0.0 && poisonM[2][2] > 0.0)
        let trtKilled = !evaluateSpdMatrix(poisonM, thresholds: t).passed

        let cleanM = [[d + 3.0, 0.5, 0.25], [0.5, d + 2.0, 0.125], [0.25, 0.125, d + 1.0]]
        let ctrlFP = !(cleanM[0][0] > 0.0 && cleanM[1][1] > 0.0 && cleanM[2][2] > 0.0)
        let trtFP = !evaluateSpdMatrix(cleanM, thresholds: t).passed
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    case "STRAT-R-NAN":
        let idx = Int(r.nextUInt64() % 4)
        var poisonV = [0.25, 0.25, 0.25, 0.25]
        poisonV[idx] = .nan
        let ctrlKilled = poisonV.contains { $0 < 0.0 || $0 > 5.0 }
        let trtKilled = !evaluateStateInvariants(poisonV, cellAbsBound: 5.0, aggregateAbsCap: 1.0, requireProbSimplex: true, thresholds: t).passed

        let cleanV = [0.25, 0.25, 0.25, 0.25]
        let ctrlFP = cleanV.contains { $0 < 0.0 || $0 > 5.0 }
        let trtFP = !evaluateStateInvariants(cleanV, cellAbsBound: 5.0, aggregateAbsCap: 1.0, requireProbSimplex: true, thresholds: t).passed
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    case "STRAT-R-CAP":
        let v = 3.5 + 0.25 * Double(r.nextUInt64() % 5)
        let poisonV = [v, v, v, v]
        let ctrlKilled = poisonV.contains { abs($0) > 5.0 }
        let trtKilled = !evaluateStateInvariants(poisonV, cellAbsBound: 5.0, aggregateAbsCap: 10.0, requireProbSimplex: false, thresholds: t).passed

        let c = 1.0 + 0.25 * Double(r.nextUInt64() % 4)
        let cleanV = [c, c, c, c]
        let ctrlFP = cleanV.contains { abs($0) > 5.0 }
        let trtFP = !evaluateStateInvariants(cleanV, cellAbsBound: 5.0, aggregateAbsCap: 10.0, requireProbSimplex: false, thresholds: t).passed
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    case "STRAT-P-CAL":
        let pSamples = generateCalibrationSamples(seed: seed ^ 0x55AA_1234, n: calN, trueMean: 0.0, trueStd: 0.25, mixtureWeightSecond: 0.5, mixtureShift: 1.2)
        let meanErr = abs(neumaierSum(pSamples) / Double(calN))
        let ctrlKilled = meanErr > 0.35
        let trtKilled = !evaluateProbCalibration(samples: pSamples, declaredMean: 0.0, declaredStd: 0.4, oodQueryZ: 1.0, thresholds: t).passed

        let cSamples = generateCalibrationSamples(seed: seed ^ 0xAA55_9876, n: calN, trueMean: 0.0, trueStd: 1.0, mixtureWeightSecond: 0.0, mixtureShift: 0.0)
        let cMeanErr = abs(neumaierSum(cSamples) / Double(calN))
        let ctrlFP = cMeanErr > 0.35
        let trtFP = !evaluateProbCalibration(samples: cSamples, declaredMean: 0.0, declaredStd: 1.0, oodQueryZ: 1.0, thresholds: t).passed
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    case "STRAT-SEAM-P2D":
        let maha = 4.5 + 0.5 * Double(r.nextUInt64() % 5)
        let poisonEst = RawProbEstimate(
            pointEstimate: 0.05, calibrated: false, inDomain: false,
            oodMahalanobis: maha, sampleCount: 16, actuatorBypassedCertificate: true
        )
        let ctrlKilled = abs(poisonEst.pointEstimate) > 1.0
        let trtKilled = admitPToD(poisonEst, thresholds: t) == nil

        let cleanEst = RawProbEstimate(
            pointEstimate: 0.05, calibrated: true, inDomain: true,
            oodMahalanobis: 1.2, sampleCount: calN, actuatorBypassedCertificate: false
        )
        let ctrlFP = abs(cleanEst.pointEstimate) > 1.0
        let trtFP = admitPToD(cleanEst, thresholds: t) == nil
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    case "STRAT-SEAM-D2P":
        let runA = keyedSimulationDigest(seed: seed, steps: 32)
        let runB = keyedSimulationDigest(seed: seed &+ 1, steps: 32)
        let ctrlKilled = runA.count != 64 || runB.count != 64
        let trtKilled = runA != runB

        let cleanA = keyedSimulationDigest(seed: seed, steps: 32)
        let cleanB = keyedSimulationDigest(seed: seed, steps: 32)
        let ctrlFP = cleanA.count != 64
        let trtFP = cleanA != cleanB
        return (ctrlKilled, trtKilled, ctrlFP, trtFP)

    default:
        throw SCargoSweepError.invalidRctConfig("unknown stratum \(stratumId)")
    }
}
