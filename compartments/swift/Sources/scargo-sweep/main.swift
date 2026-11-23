// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import SCargoSweep

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    let mode = args.count > 1 ? args[1] : "all"
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")

    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let policyURL = rootURL.appendingPathComponent("data/manifests/swe_sweep_policy_v1.json")
    let fixturesURL = rootURL.appendingPathComponent("data/fixtures/rung1_negative_controls_v1.json")
    let rctURL = rootURL.appendingPathComponent("data/trials/rct_r1_config_v1.json")

    func doSelfSweep(_ jsonMode: Bool) throws -> Bool {
        let witnesses = try runLiveSelfSweep(repoRoot: rootURL, policyURL: policyURL, fixturesURL: fixturesURL)
        let passedCount = witnesses.filter { $0.passed }.count
        if jsonMode {
            let items = try witnesses.map { try $0.toCanonicalJSON() }
            print("[" + items.joined(separator: ",") + "]")
        } else {
            for w in witnesses {
                let tag = w.passed ? "PASS" : "FAIL"
                print("[\(tag)] \(w.witness_compartment_id) (regime=\(w.regime), violations=\(w.violation_count)) :: \(w.correspondence_note)")
                for f in w.findings {
                    print("      -> [\(f.defect_class)] \(f.location) : \(f.detail)")
                }
            }
            print("SELF-SWEEP SUMMARY: \(passedCount)/\(witnesses.count) independent witnesses PASS")
        }
        return passedCount == witnesses.count && witnesses.count == 13
    }

    func doQualify(_ jsonMode: Bool) throws -> Bool {
        let sum = try qualifyNegativeControls(policyURL: policyURL, fixturesURL: fixturesURL)
        let ok = sum.totalPoison == 21
            && sum.poisonKilled == 21
            && sum.totalClean == 5
            && sum.cleanPassed == 5
            && sum.copyInvariant
        if jsonMode {
            print("{\"clean_passed\":\(sum.cleanPassed),\"copy_invariant\":\(sum.copyInvariant),\"poison_killed\":\(sum.poisonKilled),\"total_clean\":\(sum.totalClean),\"total_poison\":\(sum.totalPoison)}")
        } else {
            for v in sum.verdicts {
                let tag = v.matched ? "PASS" : "FAIL"
                print("[\(tag)] \(v.id) (\(v.kind) -> \(v.targetWitness), expected_pass=\(v.expectedPass), observed_pass=\(v.observedPass)) :: \(v.detail)")
            }
            print("QUALIFY SUMMARY: poison_killed=\(sum.poisonKilled)/\(sum.totalPoison), clean_passed=\(sum.cleanPassed)/\(sum.totalClean), prin06_copy_invariant=\(sum.copyInvariant)")
        }
        return ok
    }

    func doRct(_ jsonMode: Bool) throws -> Bool {
        let rep = try runRctR1(policyURL: policyURL, configURL: rctURL)
        if jsonMode {
            print(try rep.toCanonicalJSON())
        } else {
            for s in rep.strata {
                let tag = s.promoted ? "PROMOTE" : "REJECT"
                let line = String(
                    format: "[%@] %@ (%@): ctrl=%d/%d, trt=%d/%d (CI99 [%.3f,%.3f]), trt_fpr=%d/%d (CI99 [%.3f,%.3f]), A12=%.4f, p=%.2e",
                    tag, s.stratumId, s.defectClass, s.controlKills, s.replicates,
                    s.treatmentKills, s.replicates, s.treatmentTprCI99.0, s.treatmentTprCI99.1,
                    s.treatmentFalsePositives, s.cleanReplicates, s.treatmentFprCI99.0, s.treatmentFprCI99.1,
                    s.varghaDelaneyA12, s.wilcoxonPTwoTailed
                )
                print(line)
            }
            print("RCT-R1 SUMMARY: all_strata_promoted=\(rep.allStrataPromoted) (seed=\(rep.masterSeed), reps=\(rep.replicatesPerStratum)/stratum)")
        }
        return rep.allStrataPromoted
    }

    switch mode {
    case "self-sweep":
        return try doSelfSweep(emitJSON)
    case "qualify-fixtures":
        return try doQualify(emitJSON)
    case "rct-r1":
        return try doRct(emitJSON)
    case "all":
        let a = try doSelfSweep(false)
        let b = try doQualify(false)
        let c = try doRct(false)
        return a && b && c
    default:
        let msg = "Unknown mode '\(mode)'. Usage: scargo-sweep [self-sweep|qualify-fixtures|rct-r1|all] [--root <dir>] [--json]\n"
        try FileHandle.standardError.write(contentsOf: Data(msg.utf8))
        return false
    }
}

do {
    let ok = try runCLI()
    if !ok {
        exit(1)
    }
} catch {
    let msg = "[ERROR] scargo-sweep failed: \(error)\n"
    do {
        try FileHandle.standardError.write(contentsOf: Data(msg.utf8))
    } catch {
        fatalError("stderr write failure: \(error)")
    }
    exit(1)
}
