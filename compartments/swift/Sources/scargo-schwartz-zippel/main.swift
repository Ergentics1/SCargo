// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import SCargoModel
import SchwartzZippel

enum SZCLIError: Error, CustomStringConvertible {
    case invalidUsage
    case unreadableVault(path: String, underlying: Error)
    case guardFailure(failedCompartments: [String])

    var description: String {
        switch self {
        case .invalidUsage:
            return "Usage: scargo-schwartz-zippel --sz-vault <schwartz_zippel_research_v1.json> --rl-vault <riemann_lattice_graph_rh_v1.json>"
        case .unreadableVault(let path, let underlying):
            return "[FAIL] unable to read vault '\(path)': \(underlying)"
        case .guardFailure(let failed):
            return "FAILED COMPARTMENTS: \(failed.joined(separator: ", "))"
        }
    }
}

func runSZCLI(arguments: [String]) throws {
    var szPath: String?
    var rlPath: String?
    var idx = 1
    while idx < arguments.count {
        if arguments[idx] == "--sz-vault", idx + 1 < arguments.count {
            szPath = arguments[idx + 1]
            idx += 2
        } else if arguments[idx] == "--rl-vault", idx + 1 < arguments.count {
            rlPath = arguments[idx + 1]
            idx += 2
        } else {
            throw SZCLIError.invalidUsage
        }
    }
    guard let sp = szPath, let rp = rlPath else {
        throw SZCLIError.invalidUsage
    }

    let szRaw: String
    do {
        szRaw = try String(contentsOfFile: sp, encoding: .utf8)
    } catch {
        throw SZCLIError.unreadableVault(path: sp, underlying: error)
    }

    let rlRaw: String
    do {
        rlRaw = try String(contentsOfFile: rp, encoding: .utf8)
    } catch {
        throw SZCLIError.unreadableVault(path: rp, underlying: error)
    }

    let verdicts = SZCoupledVerifier.evaluate(szRawJSON: szRaw, rlRawJSON: rlRaw)
    for verdict in verdicts {
        let tag = verdict.passed ? "PASS" : "FAIL"
        print("[\(tag)] \(verdict.compartment) — \(verdict.detail)")
        if let heal = verdict.healingAction {
            print("       HEAL: \(heal)")
        }
    }

    let failed = verdicts.filter { !$0.passed }.map(\.compartment)
    if failed.isEmpty {
        print("ALL \(verdicts.count) SWIFT ATOMIC SCHWARTZ-ZIPPEL x PLR GUARDS PASSED (0 violations)")
    } else {
        throw SZCLIError.guardFailure(failedCompartments: failed)
    }
}

do {
    try runSZCLI(arguments: CommandLine.arguments)
} catch {
    let msg = "\(error)\n"
    if let data = msg.data(using: .utf8) {
        try FileHandle.standardError.write(contentsOf: data)
    }
    exit(1)
}
