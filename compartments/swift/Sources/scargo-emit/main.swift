// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone CLI for Arc 5 Clean-Room Dual-Route UP-07 Pre-Flight Verification.

import Foundation
import SCargoEmit

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let receipt = try verifyArc5Emitter(repoRoot: rootURL)

    if emitJSON {
        print(receipt.toCanonicalJSON())
    } else {
        print("ARC 5 PRE-FLIGHT EMITTER VERIFICATION (\(receipt.bundleSuiteId), baseline=\(receipt.baselineCommit), mutation_allowed=\(receipt.targetRepoMutationAllowed))")
        print("  EG-1 Provenance, Zone A & UP-08: \(receipt.eg1ProvenanceZoneAUp08Clean)")
        print("  EG-2 Dual-Route UP-07 Soundness: \(receipt.eg2DualRouteUp07Sound) (quick_check=\(receipt.quickCheckShards), full_build=\(receipt.fullBuildShards), full_bundles=\(receipt.totalFullBundles))")
        print("  EG-3 Shard Conservation & SHA:   \(receipt.eg3ShardConservationAndHashesValid) (shards=\(receipt.totalShards))")
        print("  EG-4 Synthetic Diff Suite:       \(receipt.eg4SyntheticDiffsValid) (transforms=\(receipt.syntheticTransformsPassed)/4, sha=\(receipt.syntheticDiffsSha256))")
        print("  EG-5 Lean 4.36 Preflight Mods:   \(receipt.eg5LeanPreflightModulesValid)")
        print("  EG-6 Negative Controls Rejected: \(receipt.eg6NegativeControlsValid) (\(receipt.negativeControlsRejected)/\(receipt.totalNegativeControls))")
        print("  INPUT DIGESTS SHA-256:           \(receipt.inputDigestsSha256)")
        print("  EMITTER DIGEST SHA-256:          \(receipt.emitterDigestSha256)")
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
