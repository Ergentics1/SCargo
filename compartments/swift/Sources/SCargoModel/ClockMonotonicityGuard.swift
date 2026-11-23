// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation

/// Atomic fail-closed boolean guard verdict for a single verification compartment.
/// Every failing verdict carries an explicit non-cheating healing path.
public struct CompartmentGuardVerdict: Codable, Sendable, Equatable {
    public let compartment: String
    public let passed: Bool
    public let detail: String
    public let healingAction: String?

    enum CodingKeys: String, CodingKey {
        case compartment
        case passed
        case detail
        case healingAction = "healing_action"
    }

    public init(
        compartment: String,
        passed: Bool,
        detail: String,
        healingAction: String? = nil
    ) {
        self.compartment = compartment
        self.passed = passed
        self.detail = detail
        self.healingAction = healingAction
    }
}

/// Assessment of physical clock monotonicity across execution contexts (Lamport 1978; Swift SE-0329).
/// Separates telemetry durability (saturating elapsed calculation) from skew observability (fail-closed guard).
public struct ClockSkewAssessment: Codable, Sendable, Equatable {
    public let clockName: String
    public let clocksource: String
    public let sampleCount: Int
    public let backwardCount: Int
    public let worstSkewNanoseconds: Int64
    public let requiresSingleCpuPin: Bool
    public let pinCpu: Int
    public let verdict: CompartmentGuardVerdict

    enum CodingKeys: String, CodingKey {
        case clockName = "clock_name"
        case clocksource
        case sampleCount = "sample_count"
        case backwardCount = "backward_count"
        case worstSkewNanoseconds = "worst_skew_nanoseconds"
        case requiresSingleCpuPin = "requires_single_cpu_pin"
        case pinCpu = "pin_cpu"
        case verdict
    }
}

/// Pure, zero-trap clock monotonicity guard & saturating interval calculator.
/// Mirrors Rust `std::time::Instant::saturating_duration_since` so skewed hypervisor
/// clocks never crash builds while remaining 100% observable.
public enum ClockMonotonicityGuard {
    /// Computes `max(0, end - start)` without ever trapping on negative skew or Int64 overflow.
    public static func saturatingElapsedNanoseconds(start: Int64, end: Int64) -> UInt64 {
        guard end > start else {
            return 0
        }
        return UInt64(bitPattern: end &- start)
    }

    /// Evaluates observed `(t_after - t_before)` deltas in nanoseconds.
    /// Fails closed on empty sample sets (prevents vacuous green checks) or any negative delta.
    public static func evaluate(
        clockName: String,
        clocksource: String,
        deltasNanoseconds: [Int64],
        pinCpu: Int = 0
    ) -> ClockSkewAssessment {
        guard !deltasNanoseconds.isEmpty else {
            let verdict = CompartmentGuardVerdict(
                compartment: "runtime_clock_monotonicity",
                passed: false,
                detail: "clock=\(clockName) clocksource=\(clocksource) samples=0 (vacuous probe rejected)",
                healingAction: "Collect >= 1,000 cross-CPU \(clockName) handoff samples before trusting physical clock monotonicity."
            )
            return ClockSkewAssessment(
                clockName: clockName,
                clocksource: clocksource,
                sampleCount: 0,
                backwardCount: 0,
                worstSkewNanoseconds: 0,
                requiresSingleCpuPin: true,
                pinCpu: pinCpu,
                verdict: verdict
            )
        }

        var backwardCount = 0
        var worstSkew: Int64 = 0
        for delta in deltasNanoseconds where delta < 0 {
            backwardCount += 1
            if delta < worstSkew {
                worstSkew = delta
            }
        }

        if backwardCount == 0 {
            let verdict = CompartmentGuardVerdict(
                compartment: "runtime_clock_monotonicity",
                passed: true,
                detail: "clock=\(clockName) clocksource=\(clocksource) samples=\(deltasNanoseconds.count) backward=0 worst_skew_ns=0",
                healingAction: nil
            )
            return ClockSkewAssessment(
                clockName: clockName,
                clocksource: clocksource,
                sampleCount: deltasNanoseconds.count,
                backwardCount: 0,
                worstSkewNanoseconds: 0,
                requiresSingleCpuPin: false,
                pinCpu: pinCpu,
                verdict: verdict
            )
        }

        let verdict = CompartmentGuardVerdict(
            compartment: "runtime_clock_monotonicity",
            passed: false,
            detail: "clock=\(clockName) clocksource=\(clocksource) samples=\(deltasNanoseconds.count) backward=\(backwardCount) worst_skew_ns=\(worstSkew)",
            healingAction: "Pin Swift 6.4 swiftbuild process affinity to CPU \(pinCpu) via sched_setaffinity / swift_guarded_build.py (or switch host clocksource from \(clocksource) to kvm-clock)."
        )
        return ClockSkewAssessment(
            clockName: clockName,
            clocksource: clocksource,
            sampleCount: deltasNanoseconds.count,
            backwardCount: backwardCount,
            worstSkewNanoseconds: worstSkew,
            requiresSingleCpuPin: true,
            pinCpu: pinCpu,
            verdict: verdict
        )
    }
}

/// Evaluates all atomic ICD & cross-tool parity compartment guards independently
/// (never collapses failures into an opaque monolithic boolean).
public enum CompartmentAuditEvaluator {
    public static func evaluate(
        baseline: BaselineInventory,
        manifest: TransferManifest,
        trace: TraceReport?
    ) -> [CompartmentGuardVerdict] {
        let baselineCommitOK = baseline.sourceRepoCommit == manifest.baselineCommit
        var verdicts: [CompartmentGuardVerdict] = [
            CompartmentGuardVerdict(
                compartment: "baseline_manifest_commit_parity",
                passed: baselineCommitOK,
                detail: "baseline=\(baseline.sourceRepoCommit) manifest=\(manifest.baselineCommit)",
                healingAction: baselineCommitOK
                    ? nil
                    : "Regenerate baseline JSON via scargo-probe on manifest commit \(manifest.baselineCommit) or update manifest baseline_commit."
            )
        ]

        if let trace {
            let traceCommitOK = trace.sourceRepoCommit == manifest.baselineCommit
            verdicts.append(CompartmentGuardVerdict(
                compartment: "trace_manifest_commit_parity",
                passed: traceCommitOK,
                detail: "trace=\(trace.sourceRepoCommit) manifest=\(manifest.baselineCommit)",
                healingAction: traceCommitOK
                    ? nil
                    : "Regenerate trace JSON via scargo-trace on manifest commit \(manifest.baselineCommit)."
            ))

            let acyclicOK = trace.graphSummary.isAcyclic
            verdicts.append(CompartmentGuardVerdict(
                compartment: "module_dag_acyclic",
                passed: acyclicOK,
                detail: "is_acyclic=\(acyclicOK)",
                healingAction: acyclicOK
                    ? nil
                    : "Inspect scargo-trace import cycle diagnostics and break cyclic module imports before reduction."
            ))

            let reachableParityOK = trace.graphSummary.reachableModules == baseline.importGraph.reachableFromMain
            verdicts.append(CompartmentGuardVerdict(
                compartment: "cross_tool_reachable_parity",
                passed: reachableParityOK,
                detail: "trace=\(trace.graphSummary.reachableModules) probe=\(baseline.importGraph.reachableFromMain)",
                healingAction: reachableParityOK
                    ? nil
                    : "Re-run both scargo-probe and scargo-trace on the identical clean commit and reconcile import parser differences."
            ))

            let verifiedLineage = trace.lineageReachabilityAudit.filter { $0.verifiedReachable }.count
            let totalLineage = trace.lineageReachabilityAudit.count
            let lineageOK = totalLineage > 0 && verifiedLineage == totalLineage
            verdicts.append(CompartmentGuardVerdict(
                compartment: "primary_lineage_reachability",
                passed: lineageOK,
                detail: "verified=\(verifiedLineage)/\(totalLineage)",
                healingAction: lineageOK
                    ? nil
                    : "Verify every primary lineage entry in formulary_lineage_v1.json resolves to an active reachable module prefix in trace."
            ))
        }

        return verdicts
    }
}
