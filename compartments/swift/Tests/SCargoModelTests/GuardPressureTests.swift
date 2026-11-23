// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import SCargoModel
import Testing

/// Adversarial & boundary pressure-test suite for Swift 6.4 compartment guards and OBS-01 clock discipline.
@Suite("SCargo Swift 6.4 Compartment & Clock Guard Pressure Tests")
struct GuardPressureTests {
    // MARK: - ClockMonotonicityGuard (OBS-01)

    @Test("Monotonic zero-skew samples pass without requiring single-CPU pinning")
    func monotonicSamplesPass() {
        let assessment = ClockMonotonicityGuard.evaluate(
            clockName: "CLOCK_BOOTTIME",
            clocksource: "kvm-clock",
            deltasNanoseconds: [0, 6_900, 8_700, 14_200, 480_100]
        )
        #expect(assessment.verdict.passed)
        #expect(!assessment.requiresSingleCpuPin)
        #expect(assessment.backwardCount == 0)
        #expect(assessment.worstSkewNanoseconds == 0)
        #expect(assessment.verdict.healingAction == nil)
    }

    @Test("Exact OBS-01 KVM TSC skew signature fails closed with single-CPU healing route")
    func obs01KvmSkewSignatureFailsClosedWithHealing() {
        let deltas: [Int64] = [8_700, -1_000_535, 12_000, -2_080_625, 4_200]
        let assessment = ClockMonotonicityGuard.evaluate(
            clockName: "CLOCK_BOOTTIME",
            clocksource: "tsc",
            deltasNanoseconds: deltas,
            pinCpu: 0
        )
        #expect(!assessment.verdict.passed)
        #expect(assessment.requiresSingleCpuPin)
        #expect(assessment.backwardCount == 2)
        #expect(assessment.worstSkewNanoseconds == -2_080_625)
        #expect(assessment.verdict.healingAction?.contains("CPU 0") == true)
        #expect(assessment.verdict.healingAction?.contains("kvm-clock") == true)
    }

    @Test("Single -1 ns backward tick fails closed while 0 ns stays monotonic")
    func singularBoundaryNegativeOneNanosecond() {
        let zeroDelta = ClockMonotonicityGuard.evaluate(
            clockName: "CLOCK_BOOTTIME",
            clocksource: "tsc",
            deltasNanoseconds: [0]
        )
        #expect(zeroDelta.verdict.passed)

        let negOne = ClockMonotonicityGuard.evaluate(
            clockName: "CLOCK_BOOTTIME",
            clocksource: "tsc",
            deltasNanoseconds: [-1]
        )
        #expect(!negOne.verdict.passed)
        #expect(negOne.worstSkewNanoseconds == -1)
    }

    @Test("Vacuous empty clock probe fails closed")
    func emptyClockProbeFailsClosed() {
        let assessment = ClockMonotonicityGuard.evaluate(
            clockName: "CLOCK_BOOTTIME",
            clocksource: "unknown",
            deltasNanoseconds: []
        )
        #expect(!assessment.verdict.passed)
        #expect(assessment.requiresSingleCpuPin)
        #expect(assessment.verdict.healingAction != nil)
    }

    @Test("Saturating elapsed duration clamps backward OBS-01 crash timestamps and Int64 extremes without trapping")
    func saturatingElapsedNeverTraps() {
        // Exact crash timestamps from task-647.log (in ns): start > end by 1,000,535 ns
        let startNs: Int64 = 21_636_411_039_009
        let endNs: Int64 = 21_636_410_038_474
        #expect(ClockMonotonicityGuard.saturatingElapsedNanoseconds(start: startNs, end: endNs) == 0)
        #expect(ClockMonotonicityGuard.saturatingElapsedNanoseconds(start: endNs, end: startNs) == 1_000_535)
        #expect(ClockMonotonicityGuard.saturatingElapsedNanoseconds(start: Int64.max, end: Int64.min) == 0)
        #expect(ClockMonotonicityGuard.saturatingElapsedNanoseconds(start: Int64.min, end: Int64.max) == UInt64.max)
    }

    // MARK: - CompartmentAuditEvaluator Fixtures & Poisoned Negative Controls

    private static func makeFixtureJSON(
        baselineCommit: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        manifestCommit: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        traceCommit: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        probeReachable: UInt64 = 100,
        traceReachable: UInt64 = 100,
        isAcyclic: Bool = true,
        lineageEntries: [(String, Bool)] = [("SRC-01", true), ("SRC-02", true)]
    ) throws -> (BaselineInventory, TransferManifest, TraceReport) {
        let decoder = JSONDecoder()

        let baselineJSON = """
        {
          "schema_version": "1.0.0",
          "tool": "scargo-probe",
          "source_repo_commit": "\(baselineCommit)",
          "scan_elapsed_ms": 12,
          "totals": { "files": 100, "bytes": 10000, "lines": 500, "non_blank_lines": 400 },
          "import_graph": {
            "total_modules": 100,
            "reachable_from_main": \(probeReachable),
            "unreachable_project_modules_count": 0,
            "unreachable_project_modules": []
          },
          "bloat_metrics": {
            "fallback_wrapper_files": 0, "fallback_wrapper_lines": 0, "fallback_wrapper_bytes": 0,
            "statement_named_files": 0, "statement_named_lines": 0, "files_importing_full_mathlib": 0,
            "public_import_lines": 10, "private_import_lines": 5, "open_lines": 2,
            "set_option_lines": 1, "explicit_at_lines_ge5": 0, "private_theorem_occurrences": 0
          },
          "libraries": []
        }
        """

        let manifestJSON = """
        {
          "schema_version": "1.0.0",
          "icd_id": "ICD-TEST",
          "baseline_commit": "\(manifestCommit)",
          "zones": []
        }
        """

        let lineageJSON = lineageEntries
            .map { id, ok in
                """
                {
                  "source_id": "\(id)",
                  "module_prefix": "Test.\(id)",
                  "verified_reachable": \(ok ? "true" : "false"),
                  "reachable_modules": 1,
                  "reachable_lines": 10,
                  "reachable_bytes": 100,
                  "min_bfs_dist": 1,
                  "max_node_dominated_modules": 1,
                  "max_node_dominated_lines": 10
                }
                """
            }
            .joined(separator: ",")

        let traceJSON = """
        {
          "schema_version": "1.0.0",
          "tool": "scargo-trace",
          "algorithm": "Cooper-Harvey-Kennedy",
          "source_repo_commit": "\(traceCommit)",
          "root_module": "Main",
          "trace_elapsed_ms": 5,
          "graph_summary": {
            "total_modules_scanned": 100,
            "reachable_modules": \(traceReachable),
            "reachable_lines": 500,
            "reachable_bytes": 10000,
            "total_project_import_edges": 120,
            "reachable_project_import_edges": 120,
            "external_import_refs": 1,
            "is_acyclic": \(isAcyclic ? "true" : "false"),
            "critical_path_depth": 5,
            "max_bfs_distance_from_root": 3
          },
          "top_module_dominators": [],
          "top_fan_in_hubs": [],
          "root_spine_depth_le_2": [],
          "lineage_reachability_audit": [\(lineageJSON)]
        }
        """

        let baseline = try decoder.decode(BaselineInventory.self, from: Data(baselineJSON.utf8))
        let manifest = try decoder.decode(TransferManifest.self, from: Data(manifestJSON.utf8))
        let trace = try decoder.decode(TraceReport.self, from: Data(traceJSON.utf8))
        return (baseline, manifest, trace)
    }

    @Test("Valid canonical fixture passes all 5 atomic compartment guards")
    func canonicalAuditPassesAllFiveGuards() throws {
        let (b, m, t) = try Self.makeFixtureJSON()
        let verdicts = CompartmentAuditEvaluator.evaluate(baseline: b, manifest: m, trace: t)
        #expect(verdicts.count == 5)
        #expect(verdicts.allSatisfy { $0.passed && $0.healingAction == nil })
    }

    @Test("Poisoned baseline/manifest commit drift isolates exact failing compartment without hiding peers")
    func poisonedCommitMismatchIsolated() throws {
        let (b, m, t) = try Self.makeFixtureJSON(
            baselineCommit: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        )
        let verdicts = CompartmentAuditEvaluator.evaluate(baseline: b, manifest: m, trace: t)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.count == 1)
        #expect(failed[0].compartment == "baseline_manifest_commit_parity")
        #expect(failed[0].healingAction != nil)
    }

    @Test("Poisoned cyclic import DAG fails module_dag_acyclic")
    func poisonedCyclicGraphFailsClosed() throws {
        let (b, m, t) = try Self.makeFixtureJSON(isAcyclic: false)
        let verdicts = CompartmentAuditEvaluator.evaluate(baseline: b, manifest: m, trace: t)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.count == 1)
        #expect(failed[0].compartment == "module_dag_acyclic")
        #expect(failed[0].healingAction != nil)
    }

    @Test("Poisoned reachable module count drift fails cross_tool_reachable_parity")
    func poisonedReachableParityFailsClosed() throws {
        let (b, m, t) = try Self.makeFixtureJSON(probeReachable: 100, traceReachable: 99)
        let verdicts = CompartmentAuditEvaluator.evaluate(baseline: b, manifest: m, trace: t)
        let failed = verdicts.filter { !$0.passed }
        #expect(failed.count == 1)
        #expect(failed[0].compartment == "cross_tool_reachable_parity")
        #expect(failed[0].healingAction != nil)
    }

    @Test("Poisoned partial or empty lineage audit fails primary_lineage_reachability (anti-vacuous green)")
    func poisonedLineageFailsClosed() throws {
        let (b1, m1, t1) = try Self.makeFixtureJSON(lineageEntries: [("SRC-01", true), ("SRC-02", false)])
        let f1 = CompartmentAuditEvaluator.evaluate(baseline: b1, manifest: m1, trace: t1).filter { !$0.passed }
        #expect(f1.count == 1)
        #expect(f1[0].compartment == "primary_lineage_reachability")

        let (b2, m2, t2) = try Self.makeFixtureJSON(lineageEntries: [])
        let f2 = CompartmentAuditEvaluator.evaluate(baseline: b2, manifest: m2, trace: t2).filter { !$0.passed }
        #expect(f2.count == 1)
        #expect(f2[0].compartment == "primary_lineage_reachability")
    }
}
