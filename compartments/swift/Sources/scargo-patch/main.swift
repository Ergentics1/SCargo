// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone CLI for Arc 6 Concrete AST Patch Plan & Pure In-Memory Unified-Diff Verification.

import Foundation
import SCargoPatch

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let receipt = try verifyArc6PatchPlan(repoRoot: rootURL)

    if emitJSON {
        print(receipt.toCanonicalJSON())
    } else {
        print("ARC 6 AST PATCH PLAN & UNIFIED-DIFF VERIFICATION (\(receipt.patchPlanId), baseline=\(receipt.baselineCommit), mutation_allowed=\(receipt.targetRepoMutationAllowed))")
        print("  PG-1 Provenance, Zone A & UP-08: \(receipt.pg1ProvenanceZoneAUp08Clean)")
        print("  PG-2 137-File Bijection & SHA:   \(receipt.pg2Bijection137AndHashesValid) (files=\(receipt.totalFiles))")
        print("  PG-3 Pareto, Round-Trip & Width: \(receipt.pg3ParetoRoundtripAndBoundsValid) (saved_lines=\(receipt.totalSavedLines) [Z0=\(receipt.z0SavedLines), Z2=\(receipt.z2SavedLines), Z4=\(receipt.z4SavedLines)], saved_bytes=\(receipt.totalSavedBytes), z2_max_line=\(receipt.z2MaxLineAfter))")
        print("  PG-4 Synthetic Unified-Diff RT:  \(receipt.pg4SyntheticPatchSuiteValid) (transforms=\(receipt.syntheticTransformsPassed)/4, sha=\(receipt.syntheticPatchSuiteSha256))")
        print("  PG-5 Lean 4.36 Preflight Mods:   \(receipt.pg5LeanPreflightModulesValid)")
        print("  PG-6 Negative Controls Rejected: \(receipt.pg6NegativeControlsValid) (\(receipt.negativeControlsRejected)/\(receipt.totalNegativeControls))")
        print("  INPUT DIGESTS SHA-256:           \(receipt.inputDigestsSha256)")
        print("  PATCH DIGEST SHA-256:            \(receipt.patchDigestSha256)")
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
