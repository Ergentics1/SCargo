// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import SCargoModel

/// Typed audit error for clear failure reporting without silent error swallowing.
enum SCargoAuditError: Error, CustomStringConvertible {
    case invalidUsage(String)
    case guardFailed([CompartmentGuardVerdict])

    var description: String {
        switch self {
        case .invalidUsage(let usage):
            return usage
        case .guardFailed(let failed):
            let summary = failed
                .map { verdict in
                    if let heal = verdict.healingAction {
                        return "  [FAIL] \(verdict.compartment): \(verdict.detail)\n         Heal: \(heal)"
                    }
                    return "  [FAIL] \(verdict.compartment): \(verdict.detail)"
                }
                .joined(separator: "\n")
            return "COMPARTMENT GUARD FAILURE (\(failed.count) failed):\n\(summary)\n"
        }
    }
}

/// Swift 6.4 ICD & Baseline Auditor (`scargo-audit`).
/// Reads immutable JSON datasets from `SCargo/data/` without embedding data in code.
@main
struct SCargoAuditCLI {
    private static func writeStderr(_ message: String) throws {
        let data = Data(message.utf8)
        try FileHandle.standardError.write(contentsOf: data)
    }

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            let usage = "Usage: scargo-audit <baseline.json> <transfer_zones.json> [trace.json]\n"
            try writeStderr(usage)
            throw SCargoAuditError.invalidUsage(usage)
        }

        let decoder = JSONDecoder()
        let baselineURL = URL(fileURLWithPath: args[1])
        let manifestURL = URL(fileURLWithPath: args[2])

        let baseline = try decoder.decode(BaselineInventory.self, from: Data(contentsOf: baselineURL))
        let manifest = try decoder.decode(TransferManifest.self, from: Data(contentsOf: manifestURL))

        var trace: TraceReport?
        if args.count >= 4 {
            let traceURL = URL(fileURLWithPath: args[3])
            trace = try decoder.decode(TraceReport.self, from: Data(contentsOf: traceURL))
        }

        let verdicts = CompartmentAuditEvaluator.evaluate(
            baseline: baseline,
            manifest: manifest,
            trace: trace
        )

        print("Ergentics SCargo — Swift 6.4 ICD & Compartment Guard Audit")
        print("  Baseline commit : \(baseline.sourceRepoCommit)")
        print("  Manifest commit : \(manifest.baselineCommit)")
        print("  Total files     : \(baseline.totals.files)")
        print("  Total lines     : \(baseline.totals.lines)")
        print("  Total bytes     : \(baseline.totals.bytes)")
        print("  Reachable mods  : \(baseline.importGraph.reachableFromMain)")
        print("  Unreachable mod : \(baseline.importGraph.unreachableProjectModulesCount)")
        print("  Fallback wraps  : \(baseline.bloatMetrics.fallbackWrapperFiles) files (\(baseline.bloatMetrics.fallbackWrapperLines) lines)")
        print(String(format: "  Scaffold share  : %.2f%%", baseline.scaffoldingLineShare * 100.0))
        print("  Transfer zones  : \(manifest.zones.count)")

        if let trace {
            print("  Trace tool      : \(trace.tool) (\(trace.traceElapsedMs) ms)")
            print("  Trace commit    : \(trace.sourceRepoCommit)")
            print("  Critical path   : \(trace.graphSummary.criticalPathDepth) hops")
        }

        print("  Compartment guards:")
        for v in verdicts {
            let status = v.passed ? "PASS" : "FAIL"
            print("    [\(status)] \(v.compartment): \(v.detail)")
        }

        let failed = verdicts.filter { !$0.passed }
        if !failed.isEmpty {
            let err = SCargoAuditError.guardFailed(failed)
            try writeStderr(err.description)
            throw err
        }
    }
}
