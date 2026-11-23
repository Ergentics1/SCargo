// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone CLI for Arc 4 Clean-Room High-Mass Zone Census Verification.

import Foundation
import SCargoCensus

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let receipt = try verifyArc4Census(repoRoot: rootURL)

    if emitJSON {
        print(receipt.toCanonicalJSON())
    } else {
        print("ARC 4 HIGH-MASS CENSUS VERIFICATION (\(receipt.censusId), baseline=\(receipt.baselineCommit))")
        print("  HG-1 Provenance & UP-08 Clean:   \(receipt.hg1ProvenanceAndUp08Clean)")
        print("  HG-2 Z-C2 Explicit @-Dumps:      \(receipt.hg2Z2ExplicitDumpsValid) (reclaimable=\(receipt.z2ReclaimableLines) lines)")
        print("  HG-3 Z-C3 Private Duplicates:    \(receipt.hg3Z3DuplicateClustersValid) (reclaimable=\(receipt.z3ReclaimableLines) lines)")
        print("  HG-4 Z-C4 Dominator & Hub:       \(receipt.hg4Z4DominatorHubValid) (redundant_hub_imports=\(receipt.z4RedundantHubImports))")
        print("  HG-5 Pareto Ranking & Negatives: \(receipt.hg5RankingAndNegativesValid) (top=\(receipt.topRankedZone), neg=\(receipt.negativeControlsRejected)/\(receipt.totalNegativeControls))")
        for r in receipt.ranking {
            print("  #\(r.rank) [\(r.zoneId)] total_lines=\(r.zoneTotalLines) reclaimable=\(r.reclaimableLines) (rho=\(r.rhoLinesPpm)ppm) total_bytes=\(r.zoneTotalBytes) reclaimable_bytes=\(r.reclaimableBytes) (rho=\(r.rhoBytesPpm)ppm)")
        }
        print("  INPUT DIGESTS SHA-256:           \(receipt.inputDigestsSha256)")
        print("  CENSUS DIGEST SHA-256:           \(receipt.censusDigestSha256)")
        print("  ALL PASSED:                      \(receipt.allPassed)")
    }
    return receipt.allPassed
}

do {
    let ok = try runCLI()
    exit(ok ? 0 : 1)
} catch {
    let msg = "[ERROR] verify failed: \(error)\n"
    do {
        try FileHandle.standardError.write(contentsOf: Data(msg.utf8))
    } catch {
        print(msg)
    }
    exit(1)
}
