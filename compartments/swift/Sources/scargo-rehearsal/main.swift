// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone CLI for Arc 7 G4–G5 Airlock Rehearsal Verification.

import Foundation
import SCargoRehearsal

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")
    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let receipt = try verifyArc7Rehearsal(repoRoot: rootURL)

    if emitJSON {
        print(receipt.toCanonicalJSON())
    } else {
        print("ARC 7 G4–G5 AIRLOCK REHEARSAL VERIFICATION (\(receipt.rehearsalSuiteId), baseline=\(receipt.baselineCommit), rehearsal=\(receipt.rehearsalMode), remote_attested=\(receipt.remoteCiAttestation))")
        print("  RG-1 Zone A Pins & UP-08 Clean:  \(receipt.rg1ZoneAPinsAndUp08Clean)")
        print("  RG-2 quick-check.py:80 Routing:  \(receipt.rg2QuickCheckAndDeferralValid) (quick_check=\(receipt.quickCheckEligibleShards), full_deferred=\(receipt.fullBuildDeferredShards), total=\(receipt.totalRoutedShards))")
        print("  RG-3 Full ci-build.py Receipt:   \(receipt.rg3CiBuildReceiptValid)")
        print("  RG-4 G5 Comparator & 3 Axioms:   \(receipt.rg4G5ComparatorAndAxiomsValid)")
        print("  RG-5 Arc 6 Binding & Honesty:    \(receipt.rg5Arc6BindingAndHonestyValid) (files=\(receipt.linkedArc6Files), saved_lines=\(receipt.linkedArc6SavedLines), saved_bytes=\(receipt.linkedArc6SavedBytes))")
        print("  RG-6 Negative Controls Rejected: \(receipt.rg6NegativeControlsValid) (\(receipt.negativeControlsRejected)/\(receipt.totalNegativeControls))")
        print("  INPUT DIGESTS SHA-256:           \(receipt.inputDigestsSha256)")
        print("  REHEARSAL DIGEST SHA-256:        \(receipt.rehearsalDigestSha256)")
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
