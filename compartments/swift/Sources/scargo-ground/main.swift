// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone CLI for Rung 2 Shared Ground Codec, QuickCheck Shrinking, Metamorphic Suite & Parity Harness.

import Foundation
import SCargoGround

private func extractU64Field(json: String, key: String) -> UInt64? {
    let needle = "\"\(key)\":"
    guard let range = json.range(of: needle) else {
        return nil
    }
    var idx = range.upperBound
    while idx < json.endIndex && (json[idx] == " " || json[idx] == "\t" || json[idx] == "\n" || json[idx] == "\r") {
        idx = json.index(after: idx)
    }
    let start = idx
    while idx < json.endIndex && json[idx] >= "0" && json[idx] <= "9" {
        idx = json.index(after: idx)
    }
    if start == idx {
        return nil
    }
    return UInt64(json[start..<idx])
}

private func runCLI() throws -> Bool {
    let args = CommandLine.arguments
    var rootPath = "."
    if let idx = args.firstIndex(of: "--root"), idx + 1 < args.count {
        rootPath = args[idx + 1]
    }
    let emitJSON = args.contains("--json")

    let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL
    let cfgURL = rootURL.appendingPathComponent("data/trials/rung2_fuzz_corpus_v1.json")
    let raw = try String(contentsOf: cfgURL, encoding: .utf8)

    guard let seed = extractU64Field(json: raw, key: "master_seed") else {
        throw GroundCodecError("missing master_seed in config")
    }
    guard let casesU64 = extractU64Field(json: raw, key: "cases_per_family") else {
        throw GroundCodecError("missing cases_per_family in config")
    }

    let receipt = runRung2ParitySuite(masterSeed: seed, casesPerFamily: Int(casesU64))
    if emitJSON {
        print(receipt.toCanonicalJSON())
    } else {
        print("RUNG 2 PARITY SUITE (seed=\(receipt.masterSeed), cases/family=\(receipt.casesPerFamily), total=\(receipt.totalCases))")
        print("  FAM-DAG-CLEAN:       \(receipt.dagCleanPassed)/\(receipt.casesPerFamily)")
        print("  FAM-CYCLE-INJECTED:  \(receipt.cycleShrunkMinimal)/\(receipt.casesPerFamily) (1-edge-minimal shrunk)")
        print("  FAM-DIAMOND-DOM:     \(receipt.diamondDomPassed)/\(receipt.casesPerFamily) (exact cut oracle)")
        print("  FAM-DEAD-LEAVES:     \(receipt.deadLeavesPassed)/\(receipt.casesPerFamily)")
        print("  FAM-WRAPPER-AST:     \(receipt.wrapperAstPassed)/\(receipt.casesPerFamily)")
        print("  FAM-METAMORPHIC-INV: \(receipt.metamorphicPairsPassed)/\(receipt.casesPerFamily * 3) pairs (MR-1/2/3)")
        print("  MALFORMED REJECTED:  \(receipt.malformedRejected)/4")
        print("  CORPUS SHA-256:      \(receipt.corpusDigestSha256)")
        print("  ALL PASSED:          \(receipt.allPassed)")
    }
    return receipt.allPassed
}

do {
    let ok = try runCLI()
    exit(ok ? 0 : 1)
} catch {
    let msg = "[ERROR] \(error)\n"
    do {
        try FileHandle.standardError.write(contentsOf: Data(msg.utf8))
    } catch {
        print(msg)
    }
    exit(1)
}
