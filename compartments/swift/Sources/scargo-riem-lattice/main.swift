// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

import Foundation
import RiemLattice
import SCargoModel

enum RiemLatticeCLIError: Error, CustomStringConvertible {
    case invalidUsage
    case unreadableVault(path: String, underlying: Error)
    case guardFailure(failedCompartments: [String])

    var description: String {
        switch self {
        case .invalidUsage:
            return "Usage: scargo-riem-lattice --vault <path/to/riemann_lattice_graph_rh_v1.json>"
        case .unreadableVault(let path, let underlying):
            return "[FAIL] unable to read vault '\(path)': \(underlying)"
        case .guardFailure(let failed):
            return "FAILED COMPARTMENTS: \(failed.joined(separator: ", "))"
        }
    }
}

func runRiemLatticeCLI(arguments: [String]) throws {
    var vaultPath: String?
    var idx = 1
    while idx < arguments.count {
        if arguments[idx] == "--vault", idx + 1 < arguments.count {
            vaultPath = arguments[idx + 1]
            idx += 2
        } else {
            throw RiemLatticeCLIError.invalidUsage
        }
    }
    guard let path = vaultPath else {
        throw RiemLatticeCLIError.invalidUsage
    }

    let rawJSON: String
    do {
        rawJSON = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        throw RiemLatticeCLIError.unreadableVault(path: path, underlying: error)
    }

    let verdicts = RiemLatticeVaultVerifier.evaluate(rawJSON: rawJSON)
    for verdict in verdicts {
        let tag = verdict.passed ? "PASS" : "FAIL"
        print("[\(tag)] \(verdict.compartment) — \(verdict.detail)")
        if let heal = verdict.healingAction {
            print("       HEAL: \(heal)")
        }
    }

    let failed = verdicts.filter { !$0.passed }.map(\.compartment)
    if failed.isEmpty {
        print("ALL \(verdicts.count) SWIFT ATOMIC RIEM-LATTICE GUARDS PASSED (0 violations)")
    } else {
        throw RiemLatticeCLIError.guardFailure(failedCompartments: failed)
    }
}

do {
    try runRiemLatticeCLI(arguments: CommandLine.arguments)
} catch {
    let msg = "\(error)\n"
    if let data = msg.data(using: .utf8) {
        try FileHandle.standardError.write(contentsOf: data)
    }
    exit(1)
}
