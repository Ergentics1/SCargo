// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation

/// Compartment classification mirroring ISS modular racks and Falcon separation boundaries.
public enum CompartmentKind: String, Codable, Sendable {
    case rust
    case swift
    case lean
    case dataVault = "data_vault"
    case research
    case transferAirlock = "transfer_airlock"
}

/// Experimental study paradigm enforced across `SCargo/experiments/`.
public enum StudyDesign: String, Codable, Sendable {
    case retrospectiveObservational = "retrospective_observational"
    case stratifiedRCT = "stratified_rct"
}

/// Mass-budget envelope for a repository or subtree (analogous to Falcon PAF mass/CG envelope).
public struct MassBudget: Codable, Sendable, Equatable {
    public let files: UInt64
    public let bytes: UInt64
    public let lines: UInt64
    public let nonBlankLines: UInt64

    enum CodingKeys: String, CodingKey {
        case files
        case bytes
        case lines
        case nonBlankLines = "non_blank_lines"
    }

    public init(files: UInt64, bytes: UInt64, lines: UInt64, nonBlankLines: UInt64) {
        self.files = files
        self.bytes = bytes
        self.lines = lines
        self.nonBlankLines = nonBlankLines
    }
}

public struct NamedBucket: Codable, Sendable, Equatable {
    public let name: String
    public let files: UInt64
    public let bytes: UInt64
    public let lines: UInt64
    public let nonBlankLines: UInt64

    enum CodingKeys: String, CodingKey {
        case name, files, bytes, lines
        case nonBlankLines = "non_blank_lines"
    }
}

public struct BloatMetrics: Codable, Sendable, Equatable {
    public let fallbackWrapperFiles: UInt64
    public let fallbackWrapperLines: UInt64
    public let fallbackWrapperBytes: UInt64
    public let statementNamedFiles: UInt64
    public let statementNamedLines: UInt64
    public let filesImportingFullMathlib: UInt64
    public let publicImportLines: UInt64
    public let privateImportLines: UInt64
    public let openLines: UInt64
    public let setOptionLines: UInt64
    public let explicitAtLinesGe5: UInt64
    public let privateTheoremOccurrences: UInt64

    enum CodingKeys: String, CodingKey {
        case fallbackWrapperFiles = "fallback_wrapper_files"
        case fallbackWrapperLines = "fallback_wrapper_lines"
        case fallbackWrapperBytes = "fallback_wrapper_bytes"
        case statementNamedFiles = "statement_named_files"
        case statementNamedLines = "statement_named_lines"
        case filesImportingFullMathlib = "files_importing_full_mathlib"
        case publicImportLines = "public_import_lines"
        case privateImportLines = "private_import_lines"
        case openLines = "open_lines"
        case setOptionLines = "set_option_lines"
        case explicitAtLinesGe5 = "explicit_at_lines_ge5"
        case privateTheoremOccurrences = "private_theorem_occurrences"
    }
}

public struct ImportGraphSummary: Codable, Sendable, Equatable {
    public let totalModules: UInt64
    public let reachableFromMain: UInt64
    public let unreachableProjectModulesCount: UInt64
    public let unreachableProjectModules: [String]

    enum CodingKeys: String, CodingKey {
        case totalModules = "total_modules"
        case reachableFromMain = "reachable_from_main"
        case unreachableProjectModulesCount = "unreachable_project_modules_count"
        case unreachableProjectModules = "unreachable_project_modules"
    }
}

/// Full typed schema matching `scargo-probe scan` JSON output in `SCargo/data/baselines/`.
public struct BaselineInventory: Codable, Sendable {
    public let schemaVersion: String
    public let copyright: String?
    public let tool: String
    public let sourceRepoCommit: String
    public let scanElapsedMs: UInt64
    public let totals: MassBudget
    public let importGraph: ImportGraphSummary
    public let bloatMetrics: BloatMetrics
    public let libraries: [NamedBucket]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case copyright
        case tool
        case sourceRepoCommit = "source_repo_commit"
        case scanElapsedMs = "scan_elapsed_ms"
        case totals
        case importGraph = "import_graph"
        case bloatMetrics = "bloat_metrics"
        case libraries
    }

    /// Computes scaffolding line fraction (imports + opens + set_option) relative to total lines.
    public var scaffoldingLineShare: Double {
        guard totals.lines > 0 else { return 0.0 }
        let scaffold = bloatMetrics.publicImportLines
            + bloatMetrics.privateImportLines
            + bloatMetrics.openLines
            + bloatMetrics.setOptionLines
        return Double(scaffold) / Double(totals.lines)
    }
}

/// Transfer-zone classification defined in `data/manifests/transfer_zones_v1.json`.
public enum TransferZonePolicy: String, Codable, Sendable {
    case protectedCoreNoTouch = "protected_core_no_touch"
    case documentationLowRisk = "documentation_low_risk"
    case qualifiedProofReduction = "qualified_proof_reduction"
}

/// Machine-readable descriptor for a single transfer zone between `SCargo` and `Riemannian`.
public struct TransferZone: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let policy: TransferZonePolicy
    public let paths: [String]
    public let requiredGates: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, policy, paths
        case requiredGates = "required_gates"
    }
}

public struct TransferManifest: Codable, Sendable {
    public let schemaVersion: String
    public let copyright: String?
    public let icdId: String
    public let baselineCommit: String
    public let zones: [TransferZone]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case copyright
        case icdId = "icd_id"
        case baselineCommit = "baseline_commit"
        case zones
    }
}

/// 1:1 Primary-source literature lineage record in `data/sources/formulary_lineage_v1.json`.
public struct FormularySourceEntry: Codable, Sendable, Equatable {
    public let id: String
    public let year: Int
    public let era: String
    public let author: String
    public let primaryCitation: String
    public let verificationStatus: String?
    public let mathematicalContribution: String
    public let traceModulePrefix: String?
    public let riemannianPaths: [String]
    public let leanSymbols: [String]
    public let roleInFormulary: String

    enum CodingKeys: String, CodingKey {
        case id, year, era, author
        case primaryCitation = "primary_citation"
        case verificationStatus = "verification_status"
        case mathematicalContribution = "mathematical_contribution"
        case traceModulePrefix = "trace_module_prefix"
        case riemannianPaths = "riemannian_paths"
        case leanSymbols = "lean_symbols"
        case roleInFormulary = "role_in_formulary"
    }
}

/// Graph summary emitted by Ergentics `scargo-trace` in `SCargo/data/traces/`.
public struct TraceGraphSummary: Codable, Sendable, Equatable {
    public let totalModulesScanned: UInt64
    public let reachableModules: UInt64
    public let reachableLines: UInt64
    public let reachableBytes: UInt64
    public let totalProjectImportEdges: UInt64
    public let reachableProjectImportEdges: UInt64
    public let externalImportRefs: UInt64
    public let isAcyclic: Bool
    public let criticalPathDepth: UInt32
    public let maxBfsDistanceFromRoot: UInt32

    enum CodingKeys: String, CodingKey {
        case totalModulesScanned = "total_modules_scanned"
        case reachableModules = "reachable_modules"
        case reachableLines = "reachable_lines"
        case reachableBytes = "reachable_bytes"
        case totalProjectImportEdges = "total_project_import_edges"
        case reachableProjectImportEdges = "reachable_project_import_edges"
        case externalImportRefs = "external_import_refs"
        case isAcyclic = "is_acyclic"
        case criticalPathDepth = "critical_path_depth"
        case maxBfsDistanceFromRoot = "max_bfs_distance_from_root"
    }
}

/// Dominator tree & fan-in/fan-out metric record for a single module in `scargo-trace`.
public struct DominatorNode: Codable, Sendable, Equatable {
    public let module: String
    public let path: String
    public let bfsDist: UInt32
    public let chainHeight: UInt32
    public let fanIn: UInt64
    public let fanOut: UInt64
    public let idom: String
    public let dominatedModules: UInt64
    public let dominatedModulesPct: Double
    public let dominatedLines: UInt64
    public let dominatedLinesPct: Double
    public let dominatedBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case module, path, idom
        case bfsDist = "bfs_dist"
        case chainHeight = "chain_height"
        case fanIn = "fan_in"
        case fanOut = "fan_out"
        case dominatedModules = "dominated_modules"
        case dominatedModulesPct = "dominated_modules_pct"
        case dominatedLines = "dominated_lines"
        case dominatedLinesPct = "dominated_lines_pct"
        case dominatedBytes = "dominated_bytes"
    }
}

/// Per-source live DAG reachability audit emitted by `scargo-trace --lineage`.
public struct LineageReachabilityAudit: Codable, Sendable, Equatable {
    public let sourceId: String
    public let modulePrefix: String
    public let verifiedReachable: Bool
    public let reachableModules: UInt64
    public let reachableLines: UInt64
    public let reachableBytes: UInt64
    public let minBfsDist: UInt32
    public let maxNodeDominatedModules: UInt64
    public let maxNodeDominatedLines: UInt64

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case modulePrefix = "module_prefix"
        case verifiedReachable = "verified_reachable"
        case reachableModules = "reachable_modules"
        case reachableLines = "reachable_lines"
        case reachableBytes = "reachable_bytes"
        case minBfsDist = "min_bfs_dist"
        case maxNodeDominatedModules = "max_node_dominated_modules"
        case maxNodeDominatedLines = "max_node_dominated_lines"
    }
}

/// Full typed schema matching Ergentics `scargo-trace` JSON output in `SCargo/data/traces/`.
public struct TraceReport: Codable, Sendable {
    public let schemaVersion: String
    public let copyright: String?
    public let tool: String
    public let algorithm: String
    public let sourceRepoCommit: String
    public let rootModule: String
    public let traceElapsedMs: UInt64
    public let graphSummary: TraceGraphSummary
    public let topModuleDominators: [DominatorNode]
    public let topFanInHubs: [DominatorNode]
    public let rootSpineDepthLe2: [DominatorNode]
    public let lineageReachabilityAudit: [LineageReachabilityAudit]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case copyright, tool, algorithm
        case sourceRepoCommit = "source_repo_commit"
        case rootModule = "root_module"
        case traceElapsedMs = "trace_elapsed_ms"
        case graphSummary = "graph_summary"
        case topModuleDominators = "top_module_dominators"
        case topFanInHubs = "top_fan_in_hubs"
        case rootSpineDepthLe2 = "root_spine_depth_le_2"
        case lineageReachabilityAudit = "lineage_reachability_audit"
    }
}
