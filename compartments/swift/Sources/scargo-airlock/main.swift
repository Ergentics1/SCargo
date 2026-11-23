// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone CLI for Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock Qualification.

import Foundation
import SCargoAirlock

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let receipt = try runRung3Airlock(repoRoot: rootURL)

    if emitJSON {
        print(receipt.toCanonicalJSON())
    } else {
        print("RUNG 3 CLEAN-ROOM AIRLOCK (\(receipt.icdId), baseline=\(receipt.baselineCommit), mutation_allowed=\(receipt.targetRepoMutationAllowed))")
        print("  AG-1 Zone A Immutability:       \(receipt.ag1ZoneAClean)")
        print("  AG-2 Baseline/Trace Conserved:  \(receipt.ag2ConservationExact) (lineage=\(receipt.lineageTargetsVerified)/15)")
        print("  AG-3 Pareto & RCT-001 Efficacy: \(receipt.ag3ParetoAndRctPassed) (multi_decl_protected=\(receipt.multiDeclProtectedCount), A12_A=\(receipt.strategyAA12Bps)bps, A12_B=\(receipt.strategyBA12Bps)bps)")
        print("  AG-4 UP-07 Batches & Axioms:    \(receipt.ag4Up07BatchesAndAxiomsClean)")
        print("  AG-5 Synthetic Clean-Room Ops:  \(receipt.ag5SyntheticTransformsPassed)")
        for p in receipt.packages {
            print("  [\(p.packageId)] zone=\(p.zoneId) mods=\(p.eligibleModules) batches=\(p.batchCount) (max=\(p.maxBatchSize)) lines:\(p.before.lines)->\(p.after.lines) (rho=\(p.rhoLinesPpm)ppm) bytes:\(p.before.bytes)->\(p.after.bytes) (rho=\(p.rhoBytesPpm)ppm)")
        }
        print("  NEGATIVE CONTROLS REJECTED:     \(receipt.negativeControlsRejected)/\(receipt.totalNegativeControls)")
        print("  INPUT DIGESTS SHA-256:          \(receipt.inputDigestsSha256)")
        print("  AIRLOCK DIGEST SHA-256:         \(receipt.airlockDigestSha256)")
        print("  ALL PASSED:                     \(receipt.allPassed)")
    }
    return receipt.allPassed
}

do {
    let ok = try runCLI()
    exit(ok ? 0 : 1)
} catch {
    let msg = "[ERROR] airlock qualification failed: \(error)\n"
    do {
        try FileHandle.standardError.write(contentsOf: Data(msg.utf8))
    } catch {
        print(msg)
    }
    exit(1)
}
