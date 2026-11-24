// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import SCargoSynth

var root = "."
var asJSON = false
let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--root" where i + 1 < args.count:
        root = args[i + 1]
        i += 2
    case "--json":
        asJSON = true
        i += 1
    default:
        FileHandle.standardError.write(Data("Usage: scargo-synth [--root <dir>] [--json]\n".utf8))
        exit(2)
    }
}

do {
    let r = try verifyArc8Synth(scargoRoot: root)
    if asJSON {
        print(r.toCanonicalJSON(), terminator: "")
    } else {
        print("ARC 8 ADAPTIVE 5-ZONE AST SYNTHESIS VERIFICATION (\(r.synthPlanId), baseline=\(r.baselineCommit))")
        print("  SG-1 Baseline, Zone A & UP-08:    \(r.sg1BaselineZoneAUp08)")
        print("  SG-2 5-Zone Round-Trip & Pareto:  \(r.sg2FiveZoneRoundtripPareto) (files=\(r.totalFiles), saved_lines=\(r.totalSavedLines), saved_bytes=\(r.totalSavedBytes))")
        print("  SG-3 Z-C1A Dual-Mode Sound:       \(r.sg3Z1aDualModeSound) (files=\(r.z1aFiles))")
        print("  SG-4 Z-C2 Adaptive-Width Sound:   \(r.sg4Z2AdaptiveWidthSound) (files=\(r.z2Files))")
        print("  SG-5 Z-C3 Acyclic Clusters Sound: \(r.sg5Z3AcyclicClustersSound) (clusters=\(r.z3Clusters))")
        print("  SG-6 Adaptive Bin-Packing Sound:  \(r.sg6AdaptiveBinPackingSound) (naive_qc=\(r.naiveQuickCheckFiles), adaptive_qc=\(r.adaptiveQuickCheckFiles))")
        print("  SG-7 Negative Controls Rejected:  \(r.sg7AllNegativesPass) (\(r.sg7NegativesRejected)/8)")
        print("  INPUT DIGESTS SHA-256:            \(r.inputDigestsSha256)")
        print("  SYNTH DIGEST SHA-256:             \(r.synthDigestSha256)")
        print("  ALL PASSED:                       \(r.allPassed)")
    }
    exit(r.allPassed ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("[FAIL] \(error)\n".utf8))
    exit(1)
}
