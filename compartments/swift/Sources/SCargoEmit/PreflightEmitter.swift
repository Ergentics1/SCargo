// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone Arc 5 Clean-Room Dual-Route UP-07 Patch Bundle Verifier & Synthetic
// Deterministic Diff Emitter (pure Swift 6, zero external dependencies).

import Foundation

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256
// =============================================================================

private let emitSha256K: [UInt32] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

@inline(__always)
private func emitRotr32(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}

public func emitSha256Hex(_ data: [UInt8]) -> String {
    var h: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    let bitLen = UInt64(data.count) &* 8
    var padded = data
    padded.reserveCapacity(data.count + 72)
    padded.append(0x80)
    while (padded.count % 64) != 56 {
        padded.append(0)
    }
    for shift in stride(from: 56, through: 0, by: -8) {
        padded.append(UInt8((bitLen >> UInt64(shift)) & 0xff))
    }

    var offset = 0
    while offset < padded.count {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let j = offset + i * 4
            w[i] = (UInt32(padded[j]) << 24)
                | (UInt32(padded[j + 1]) << 16)
                | (UInt32(padded[j + 2]) << 8)
                | UInt32(padded[j + 3])
        }
        for i in 16..<64 {
            let s0 = emitRotr32(w[i - 15], 7) ^ emitRotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = emitRotr32(w[i - 2], 17) ^ emitRotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = h[0]
        var b = h[1]
        var c = h[2]
        var d = h[3]
        var e = h[4]
        var f = h[5]
        var g = h[6]
        var hh = h[7]

        for i in 0..<64 {
            let s1 = emitRotr32(e, 6) ^ emitRotr32(e, 11) ^ emitRotr32(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let t1 = hh &+ s1 &+ ch &+ emitSha256K[i] &+ w[i]
            let s0 = emitRotr32(a, 2) ^ emitRotr32(a, 13) ^ emitRotr32(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let t2 = s0 &+ maj
            hh = g
            g = f
            f = e
            e = d &+ t1
            d = c
            c = b
            b = a
            a = t1 &+ t2
        }
        h[0] = h[0] &+ a
        h[1] = h[1] &+ b
        h[2] = h[2] &+ c
        h[3] = h[3] &+ d
        h[4] = h[4] &+ e
        h[5] = h[5] &+ f
        h[6] = h[6] &+ g
        h[7] = h[7] &+ hh
        offset += 64
    }

    let hexChars: [Character] = Array("0123456789abcdef")
    var out = ""
    out.reserveCapacity(64)
    for word in h {
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = Int((word >> UInt32(shift)) & 0xff)
            out.append(hexChars[(byte >> 4) & 0x0f])
            out.append(hexChars[byte & 0x0f])
        }
    }
    return out
}

public func emitSha256Hex(_ text: String) -> String {
    emitSha256Hex(Array(text.utf8))
}

public struct EmitError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) {
        self.message = message
    }
}

// =============================================================================
// 2. Pure Zero-Dependency JSON Parser
// =============================================================================

private enum EJVal {
    case null
    case bool(Bool)
    case num(String)
    case str(String)
    case arr([EJVal])
    case obj([String: EJVal])

    func asBool() -> Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    func asU64() -> UInt64? {
        if case .num(let s) = self { return UInt64(s) }
        return nil
    }
    func asStr() -> String? {
        if case .str(let s) = self { return s }
        return nil
    }
    func asArr() -> [EJVal]? {
        if case .arr(let a) = self { return a }
        return nil
    }
    func get(_ k: String) -> EJVal? {
        if case .obj(let m) = self { return m[k] }
        return nil
    }
}

private struct EJsonParser {
    let bytes: [UInt8]
    var pos: Int = 0

    mutating func skipWs() {
        while pos < bytes.count {
            let b = bytes[pos]
            if b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d {
                pos += 1
            } else {
                break
            }
        }
    }

    func peek() -> UInt8? {
        pos < bytes.count ? bytes[pos] : nil
    }

    mutating func parseVal() throws -> EJVal {
        skipWs()
        guard let b = peek() else {
            throw EmitError("unexpected EOF in JSON at \(pos)")
        }
        switch b {
        case 0x22: return .str(try parseStr())
        case 0x5b: return try parseArr()
        case 0x7b: return try parseObj()
        case 0x74: return try expectLit([0x74, 0x72, 0x75, 0x65], .bool(true))
        case 0x66: return try expectLit([0x66, 0x61, 0x6c, 0x73, 0x65], .bool(false))
        case 0x6e: return try expectLit([0x6e, 0x75, 0x6c, 0x6c], .null)
        case 0x2d, 0x30...0x39: return try parseNum()
        default: throw EmitError("unexpected JSON token at \(pos)")
        }
    }

    mutating func expectLit(_ lit: [UInt8], _ val: EJVal) throws -> EJVal {
        guard pos + lit.count <= bytes.count else {
            throw EmitError("truncated literal at \(pos)")
        }
        for i in 0..<lit.count {
            if bytes[pos + i] != lit[i] {
                throw EmitError("invalid literal at \(pos)")
            }
        }
        pos += lit.count
        return val
    }

    mutating func parseStr() throws -> String {
        guard peek() == 0x22 else {
            throw EmitError("expected quote")
        }
        pos += 1
        var buf: [UInt8] = []
        while pos < bytes.count {
            let b = bytes[pos]
            pos += 1
            if b == 0x22 {
                guard let s = String(bytes: buf, encoding: .utf8) else {
                    throw EmitError("invalid utf8 string")
                }
                return s
            }
            if b == 0x5c {
                guard pos < bytes.count else {
                    throw EmitError("truncated escape")
                }
                let e = bytes[pos]
                pos += 1
                switch e {
                case 0x22: buf.append(0x22)
                case 0x5c: buf.append(0x5c)
                case 0x2f: buf.append(0x2f)
                case 0x62: buf.append(0x08)
                case 0x66: buf.append(0x0c)
                case 0x6e: buf.append(0x0a)
                case 0x72: buf.append(0x0d)
                case 0x74: buf.append(0x09)
                case 0x75:
                    guard pos + 4 <= bytes.count else {
                        throw EmitError("truncated unicode escape")
                    }
                    guard let hex = String(bytes: bytes[pos..<(pos + 4)], encoding: .utf8),
                          let code = UInt32(hex, radix: 16),
                          let scalar = UnicodeScalar(code)
                    else {
                        throw EmitError("bad unicode escape")
                    }
                    pos += 4
                    buf.append(contentsOf: String(scalar).utf8)
                default:
                    throw EmitError("unsupported escape")
                }
            } else {
                buf.append(b)
            }
        }
        throw EmitError("unterminated JSON string")
    }

    mutating func parseNum() throws -> EJVal {
        let start = pos
        if peek() == 0x2d {
            pos += 1
        }
        while let b = peek(),
              (b >= 0x30 && b <= 0x39) || b == 0x2e || b == 0x65 || b == 0x45 || b == 0x2b || b == 0x2d
        {
            pos += 1
        }
        guard let raw = String(bytes: bytes[start..<pos], encoding: .utf8), !raw.isEmpty else {
            throw EmitError("bad number")
        }
        return .num(raw)
    }

    mutating func parseArr() throws -> EJVal {
        pos += 1
        skipWs()
        var items: [EJVal] = []
        if peek() == 0x5d {
            pos += 1
            return .arr(items)
        }
        while true {
            items.append(try parseVal())
            skipWs()
            switch peek() {
            case 0x2c: pos += 1
            case 0x5d:
                pos += 1
                return .arr(items)
            default:
                throw EmitError("expected ',' or ']'")
            }
        }
    }

    mutating func parseObj() throws -> EJVal {
        pos += 1
        skipWs()
        var map: [String: EJVal] = [:]
        if peek() == 0x7d {
            pos += 1
            return .obj(map)
        }
        while true {
            skipWs()
            let k = try parseStr()
            skipWs()
            guard peek() == 0x3a else {
                throw EmitError("expected ':'")
            }
            pos += 1
            let v = try parseVal()
            map[k] = v
            skipWs()
            switch peek() {
            case 0x2c: pos += 1
            case 0x7d:
                pos += 1
                return .obj(map)
            default:
                throw EmitError("expected ',' or '}'")
            }
        }
    }
}

private func parseEmitJSON(_ input: String) throws -> EJVal {
    var parser = EJsonParser(bytes: Array(input.utf8))
    let val = try parser.parseVal()
    parser.skipWs()
    if parser.pos != parser.bytes.count {
        throw EmitError("trailing JSON bytes")
    }
    return val
}

// =============================================================================
// 3. Shared UP-07 Dual-Route Classifier, UP-08 Check & Synthetic Rewriters
// =============================================================================

public func classifyUP07Route(changedRoots: Int, projectAncestors: UInt64) -> String {
    if changedRoots >= 1 && changedRoots <= 8 && projectAncestors <= 2000 {
        return "quick_check"
    }
    return "full_rh_build"
}

public func containsVerbatimProofBody(_ rawJSON: String) -> Bool {
    rawJSON.contains(":= by")
        || rawJSON.contains("private theorem ")
        || rawJSON.contains("noncomputable def ")
        || rawJSON.contains("public import Mathlib")
}

public func delimitersBalanced(_ src: String) -> Bool {
    var paren = 0
    var brace = 0
    var brack = 0
    for ch in src {
        switch ch {
        case "(": paren += 1
        case ")":
            paren -= 1
            if paren < 0 { return false }
        case "{": brace += 1
        case "}":
            brace -= 1
            if brace < 0 { return false }
        case "[": brack += 1
        case "]":
            brack -= 1
            if brack < 0 { return false }
        default:
            break
        }
    }
    return paren == 0 && brace == 0 && brack == 0
}

public func computeShardSha256(shardId: String, zoneId: String, route: String, paths: [String]) -> String {
    var s = "\(shardId)|\(zoneId)|\(route)|"
    for (idx, p) in paths.enumerated() {
        if idx > 0 {
            s.append(",")
        }
        s.append(p)
    }
    return emitSha256Hex(s)
}

public struct BinderSig: Sendable, Equatable {
    public let explicitCount: Int
    public let implicitCount: Int
    public let instanceCount: Int
    public let universeParams: Int

    public init(explicitCount: Int, implicitCount: Int, instanceCount: Int, universeParams: Int) {
        self.explicitCount = explicitCount
        self.implicitCount = implicitCount
        self.instanceCount = instanceCount
        self.universeParams = universeParams
    }
}

private func splitRustLines(_ src: String) -> [String] {
    if src.isEmpty {
        return []
    }
    var parts = src.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if src.hasSuffix("\n"), !parts.isEmpty {
        parts.removeLast()
    }
    return parts.map { line in
        if line.hasSuffix("\r") {
            return String(line.dropLast())
        }
        return line
    }
}

private func trimStart(_ s: String) -> String {
    var idx = s.startIndex
    while idx < s.endIndex && (s[idx] == " " || s[idx] == "\t" || s[idx] == "\r") {
        idx = s.index(after: idx)
    }
    return String(s[idx...])
}

private func trimEnd(_ s: String) -> String {
    var end = s.endIndex
    while end > s.startIndex {
        let prev = s.index(before: end)
        if s[prev] == " " || s[prev] == "\t" || s[prev] == "\r" {
            end = prev
        } else {
            break
        }
    }
    return String(s[..<end])
}

public func rewriteZ1ASynthetic(
    src: String,
    wrapperSig: BinderSig,
    targetSig: BinderSig,
    targetSymbol: String
) throws -> String {
    if wrapperSig != targetSig {
        throw EmitError("binder-plicity mismatch between wrapper and target")
    }
    if wrapperSig.universeParams > 0 {
        throw EmitError("universe-polymorphic wrapper excluded fail-closed")
    }
    if !delimitersBalanced(src) {
        throw EmitError("unbalanced source delimiters")
    }
    var out = ""
    var replaced = false
    var skipBody = false
    for line in splitRustLines(src) {
        if skipBody {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                continue
            }
            skipBody = false
        }
        if trimStart(line).hasPrefix("theorem "), let range = line.range(of: ":= by") {
            let prefix = trimEnd(String(line[..<range.lowerBound]))
            out.append("\(prefix) := @\(targetSymbol)\n")
            replaced = true
            skipBody = true
        } else {
            out.append(line)
            out.append("\n")
        }
    }
    if !replaced || !delimitersBalanced(out) || out.utf8.count >= src.utf8.count {
        throw EmitError("Z-C1A rewrite failed strict safety/size reduction check")
    }
    return out
}

public func rewriteZ2Synthetic(src: String, defeqRflCertified: Bool) throws -> String {
    if !defeqRflCertified {
        throw EmitError("defeq rfl certificate required before Z-C2 de-expansion")
    }
    if !delimitersBalanced(src) {
        throw EmitError("unbalanced source delimiters")
    }
    let pat = "@HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c"
    if !src.contains(pat) {
        throw EmitError("no certified explicit @-chain pattern matched")
    }
    let out = src.replacingOccurrences(of: pat, with: "a * b + c")
    if !delimitersBalanced(out) || out.utf8.count >= src.utf8.count {
        throw EmitError("Z-C2 rewrite failed delimiter/Pareto check")
    }
    return out
}

public func rewriteZ4PruneRedundantImports(
    src: String,
    transitivelyCovered: Set<String>,
    toPrune: Set<String>
) throws -> String {
    for target in toPrune {
        if !transitivelyCovered.contains(target) {
            throw EmitError("refusing to prune non-redundant import '\(target)'")
        }
    }
    var out = ""
    var pruned = 0
    for line in splitRustLines(src) {
        let t = trimEnd(trimStart(line))
        var dropThis = false
        if t.hasPrefix("public import ") {
            let rest = String(t.dropFirst("public import ".count))
            let modName = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            if toPrune.contains(modName) {
                dropThis = true
                pruned += 1
            }
        }
        if !dropThis {
            out.append(line)
            out.append("\n")
        }
    }
    if pruned != toPrune.count || out.utf8.count >= src.utf8.count {
        throw EmitError("Z-C4 prune failed exact line-drop count or Pareto reduction")
    }
    return out
}

public func runSyntheticDiffSuite() throws -> (Int, String) {
    var diffTrace = ""

    // 1. Z-C0 synthetic delete plan
    let z0Src = "module\npublic import Base\n@[expose] public section\ntheorem unused : True := trivial\n"
    let z0Diff = "--- a/DeadLeaf.lean\n+++ /dev/null\n-lines:\(splitRustLines(z0Src).count):bytes:\(z0Src.utf8.count)\n"
    diffTrace.append(emitSha256Hex(z0Diff))
    diffTrace.append(";")

    // 2. Z-C1A synthetic in-place forwarding rewrite
    let z1aSrc = "module\npublic import SCargoLean.Preflight.Leaf\n@[expose] public section\ntheorem wrap : ∀ {α : Type} (x : α), x = x := by\n  first | exact @leafIdTheorem | exact leafIdTheorem\n"
    let sig = BinderSig(explicitCount: 1, implicitCount: 1, instanceCount: 0, universeParams: 0)
    let z1aOut = try rewriteZ1ASynthetic(src: z1aSrc, wrapperSig: sig, targetSig: sig, targetSymbol: "leafIdTheorem")
    if !z1aOut.contains("module\n") || !z1aOut.contains("@[expose] public section\n") {
        throw EmitError("Z-C1A lost module header")
    }
    let z1aDiff = "Z1A:\(z1aSrc.utf8.count):\(z1aOut.utf8.count):\(emitSha256Hex(z1aOut))"
    diffTrace.append(emitSha256Hex(z1aDiff))
    diffTrace.append(";")

    // 3. Z-C2 synthetic explicit @-chain de-expansion
    let z2Src = "module\n@[expose] public section\ndef f (a b c : Nat) : Nat :=\n  @HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c\n"
    let z2Out = try rewriteZ2Synthetic(src: z2Src, defeqRflCertified: true)
    if !z2Out.contains("a * b + c") {
        throw EmitError("Z-C2 missing clean expression")
    }
    let z2Diff = "Z2:\(z2Src.utf8.count):\(z2Out.utf8.count):\(emitSha256Hex(z2Out))"
    diffTrace.append(emitSha256Hex(z2Diff))
    diffTrace.append(";")

    // 4. Z-C4 synthetic transitive import pruning
    let z4Src = "module\npublic import SCargoLean.Preflight.Leaf\npublic import SCargoLean.Preflight.Mid\n@[expose] public section\ntheorem hub : True := trivial\n"
    let covered: Set<String> = ["SCargoLean.Preflight.Leaf"]
    let toPrune: Set<String> = ["SCargoLean.Preflight.Leaf"]
    let z4Out = try rewriteZ4PruneRedundantImports(src: z4Src, transitivelyCovered: covered, toPrune: toPrune)
    if z4Out.contains("Preflight.Leaf") || !z4Out.contains("Preflight.Mid") {
        throw EmitError("Z-C4 prune violated import closure")
    }
    let z4Diff = "Z4:\(z4Src.utf8.count):\(z4Out.utf8.count):\(emitSha256Hex(z4Out))"
    diffTrace.append(emitSha256Hex(z4Diff))
    diffTrace.append(";")

    return (4, emitSha256Hex(diffTrace))
}

// =============================================================================
// 4. Arc 5 Pre-Flight Emitter Receipt & Verifier (EG-1..EG-6)
// =============================================================================

public struct Arc5EmitterReceipt: Sendable, Equatable {
    public let bundleSuiteId: String
    public let baselineCommit: String
    public let targetRepoMutationAllowed: Bool
    public let eg1ProvenanceZoneAUp08Clean: Bool
    public let eg2DualRouteUp07Sound: Bool
    public let eg3ShardConservationAndHashesValid: Bool
    public let eg4SyntheticDiffsValid: Bool
    public let eg5LeanPreflightModulesValid: Bool
    public let eg6NegativeControlsValid: Bool
    public let totalShards: Int
    public let quickCheckShards: Int
    public let fullBuildShards: Int
    public let totalFullBundles: Int
    public let syntheticTransformsPassed: Int
    public let negativeControlsRejected: Int
    public let totalNegativeControls: Int
    public let syntheticDiffsSha256: String
    public let inputDigestsSha256: String
    public let emitterDigestSha256: String
    public let allPassed: Bool

    public func toCanonicalJSON() -> String {
        "{\"all_passed\":\(allPassed),\"baseline_commit\":\"\(baselineCommit)\",\"bundle_suite_id\":\"\(bundleSuiteId)\",\"eg1_provenance_zone_a_up08_clean\":\(eg1ProvenanceZoneAUp08Clean),\"eg2_dual_route_up07_sound\":\(eg2DualRouteUp07Sound),\"eg3_shard_conservation_and_hashes_valid\":\(eg3ShardConservationAndHashesValid),\"eg4_synthetic_diffs_valid\":\(eg4SyntheticDiffsValid),\"eg5_lean_preflight_modules_valid\":\(eg5LeanPreflightModulesValid),\"eg6_negative_controls_valid\":\(eg6NegativeControlsValid),\"emitter_digest_sha256\":\"\(emitterDigestSha256)\",\"full_build_shards\":\(fullBuildShards),\"input_digests_sha256\":\"\(inputDigestsSha256)\",\"negative_controls_rejected\":\(negativeControlsRejected),\"quick_check_shards\":\(quickCheckShards),\"synthetic_diffs_sha256\":\"\(syntheticDiffsSha256)\",\"synthetic_transforms_passed\":\(syntheticTransformsPassed),\"target_repo_mutation_allowed\":\(targetRepoMutationAllowed),\"total_full_bundles\":\(totalFullBundles),\"total_negative_controls\":\(totalNegativeControls),\"total_shards\":\(totalShards)}"
    }
}

private func readUTF8File(_ url: URL, label: String) throws -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw EmitError("read \(label): \(error)")
    }
}

public func verifyArc5Emitter(repoRoot: URL) throws -> Arc5EmitterReceipt {
    let relBundles = "transfer/bundles/arc5_preflight_bundles_v1.json"
    let relZones = "data/manifests/transfer_zones_v1.json"
    let relCensus = "data/trials/arc4_high_mass_census_v1.json"
    let relDr1 = "data/trials/dryrun_001_dead_leaves.json"
    let relDr2 = "data/trials/dryrun_002_rct001_wrappers.json"

    let bundlesRaw = try readUTF8File(repoRoot.appendingPathComponent(relBundles), label: relBundles)
    let zonesRaw = try readUTF8File(repoRoot.appendingPathComponent(relZones), label: relZones)
    let censusRaw = try readUTF8File(repoRoot.appendingPathComponent(relCensus), label: relCensus)
    let dr1Raw = try readUTF8File(repoRoot.appendingPathComponent(relDr1), label: relDr1)
    let dr2Raw = try readUTF8File(repoRoot.appendingPathComponent(relDr2), label: relDr2)

    var dchain = ""
    for (label, content) in [
        (relBundles, bundlesRaw),
        (relZones, zonesRaw),
        (relCensus, censusRaw),
        (relDr1, dr1Raw),
        (relDr2, dr2Raw),
    ] {
        dchain.append(label)
        dchain.append(":")
        dchain.append(emitSha256Hex(content))
        dchain.append(";")
    }
    let inputDigestsSha256 = emitSha256Hex(dchain)

    let bundles = try parseEmitJSON(bundlesRaw)
    let zones = try parseEmitJSON(zonesRaw)
    let census = try parseEmitJSON(censusRaw)
    let dr1 = try parseEmitJSON(dr1Raw)
    let dr2 = try parseEmitJSON(dr2Raw)

    guard let bundleSuiteId = bundles.get("bundle_suite_id")?.asStr() else {
        throw EmitError("missing bundle_suite_id")
    }
    guard let baselineCommit = bundles.get("source_repo_commit")?.asStr() else {
        throw EmitError("missing source_repo_commit")
    }
    let targetRepoMutationAllowed = bundles.get("target_repo_mutation_allowed")?.asBool() ?? true

    let zonesSha = zones.get("baseline_commit")?.asStr() ?? ""
    let censusSha = census.get("source_repo_commit")?.asStr() ?? ""
    let dr1Sha = dr1.get("source_repo_commit")?.asStr() ?? ""
    let dr2Sha = dr2.get("source_repo_commit")?.asStr() ?? ""

    guard let zoneArr = zones.get("zones")?.asArr() else {
        throw EmitError("missing zones")
    }
    var zoneAPaths = Set<String>()
    for z in zoneArr {
        if z.get("id")?.asStr() == "Z-A", let ps = z.get("paths")?.asArr() {
            for p in ps {
                if let s = p.asStr() {
                    zoneAPaths.insert(s)
                }
            }
        }
    }

    guard let shardArr = bundles.get("shards")?.asArr() else {
        throw EmitError("missing shards")
    }
    guard let fullArr = bundles.get("full_bundles")?.asArr() else {
        throw EmitError("missing full_bundles")
    }

    var anyZoneATouch = false
    var routesOk = true
    var hashesOk = true
    var quickCheckShards = 0
    var fullBuildShards = 0
    var zoneSeen: [String: Set<String>] = [:]
    var zoneDisjointOk = true

    for sh in shardArr {
        let sid = sh.get("shard_id")?.asStr() ?? ""
        let zid = sh.get("zone_id")?.asStr() ?? ""
        let route = sh.get("route")?.asStr() ?? ""
        let roots = Int(sh.get("changed_roots")?.asU64() ?? 0)
        let anc = sh.get("project_ancestors")?.asU64() ?? 0
        let declaredSha = sh.get("shard_sha256")?.asStr() ?? ""
        guard let rawPaths = sh.get("paths")?.asArr() else {
            throw EmitError("missing shard paths")
        }
        let paths = rawPaths.compactMap { $0.asStr() }

        if paths.count != roots || roots == 0 || roots > 8 {
            routesOk = false
        }
        let expectedRoute = classifyUP07Route(changedRoots: roots, projectAncestors: anc)
        if route != expectedRoute {
            routesOk = false
        }
        if route == "quick_check" {
            quickCheckShards += 1
        } else if route == "full_rh_build" {
            fullBuildShards += 1
        } else {
            routesOk = false
        }
        let recomputedSha = computeShardSha256(shardId: sid, zoneId: zid, route: route, paths: paths)
        if recomputedSha != declaredSha {
            hashesOk = false
        }
        var zSet = zoneSeen[zid] ?? Set<String>()
        for p in paths {
            if zoneAPaths.contains(p) {
                anyZoneATouch = true
            }
            if !zSet.insert(p).inserted {
                zoneDisjointOk = false
            }
        }
        zoneSeen[zid] = zSet
    }

    for fb in fullArr {
        let route = fb.get("route")?.asStr() ?? ""
        let roots = Int(fb.get("changed_roots")?.asU64() ?? 0)
        let anc = fb.get("project_ancestors")?.asU64() ?? 0
        if route != classifyUP07Route(changedRoots: roots, projectAncestors: anc) || route != "full_rh_build" {
            routesOk = false
        }
    }

    let expZ0 = Int(dr1.get("summary")?.get("dead_modules_count")?.asU64() ?? 0)
    let expZ1a = Int(dr2.get("treatment_dryrun_qualification")?.get("strategy_a_eligible_units")?.asU64() ?? 0)
    let expZ2 = Int(census.get("zone_z_c2_explicit_dumps")?.get("explicit_heavy_files")?.asU64() ?? 0)

    let z0Cnt = zoneSeen["Z-C0"]?.count ?? 0
    let z1aCnt = zoneSeen["Z-C1A"]?.count ?? 0
    let z2Cnt = zoneSeen["Z-C2"]?.count ?? 0
    let z4Cnt = zoneSeen["Z-C4"]?.count ?? 0

    let eg1ProvenanceZoneAUp08Clean = !targetRepoMutationAllowed
        && baselineCommit == zonesSha
        && baselineCommit == censusSha
        && baselineCommit == dr1Sha
        && baselineCommit == dr2Sha
        && !anyZoneATouch
        && !containsVerbatimProofBody(bundlesRaw)

    let eg2DualRouteUp07Sound = routesOk && quickCheckShards >= 1 && fullBuildShards >= 1 && fullArr.count == 4

    let eg3ShardConservationAndHashesValid = zoneDisjointOk
        && hashesOk
        && z0Cnt == expZ0
        && z1aCnt == expZ1a
        && z2Cnt == expZ2
        && z4Cnt == 1

    // EG-4: Synthetic deterministic diff suite across all 4 transform families
    let syntheticTransformsPassed: Int
    let syntheticDiffsSha256: String
    do {
        let res = try runSyntheticDiffSuite()
        syntheticTransformsPassed = res.0
        syntheticDiffsSha256 = res.1
    } catch {
        syntheticTransformsPassed = 0
        syntheticDiffsSha256 = ""
    }
    let eg4SyntheticDiffsValid = syntheticTransformsPassed == 4 && syntheticDiffsSha256.count == 64

    // EG-5: Verify all 4 clean-room Lean 4.36 `module` pre-flight files
    let leanPreflightFiles = [
        "compartments/lean/SCargoLean/Preflight/Leaf.lean",
        "compartments/lean/SCargoLean/Preflight/Mid.lean",
        "compartments/lean/SCargoLean/Preflight/WrapAlias.lean",
        "compartments/lean/SCargoLean/Preflight/HubPruned.lean",
    ]
    var eg5LeanPreflightModulesValid = true
    for rel in leanPreflightFiles {
        do {
            let txt = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            if !txt.contains("module\n")
                || !txt.contains("@[expose] public section")
                || txt.contains("sorry")
                || txt.contains("native_decide")
            {
                eg5LeanPreflightModulesValid = false
            }
        } catch {
            eg5LeanPreflightModulesValid = false
        }
    }

    // EG-6: 6 Adversarial Negative Controls (all 6 must fail closed!)
    var negRejected = 0
    let sigA = BinderSig(explicitCount: 2, implicitCount: 0, instanceCount: 0, universeParams: 0)
    let sigB = BinderSig(explicitCount: 1, implicitCount: 1, instanceCount: 0, universeParams: 0)
    do {
        _ = try rewriteZ1ASynthetic(src: "theorem w := by\n  exact t\n", wrapperSig: sigA, targetSig: sigB, targetSymbol: "t")
    } catch {
        negRejected += 1
    }
    do {
        _ = try rewriteZ2Synthetic(
            src: "def f := @HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c\n",
            defeqRflCertified: false
        )
    } catch {
        negRejected += 1
    }
    do {
        _ = try rewriteZ4PruneRedundantImports(
            src: "module\npublic import Core.Required\n",
            transitivelyCovered: Set<String>(),
            toPrune: ["Core.Required"]
        )
    } catch {
        negRejected += 1
    }
    if classifyUP07Route(changedRoots: 1, projectAncestors: 127_439) != "quick_check" {
        negRejected += 1
    }
    if zoneAPaths.contains("src/Main.lean") {
        negRejected += 1
    }
    if containsVerbatimProofBody("{\"bad\": \"private theorem leak : True := by trivial\"}") {
        negRejected += 1
    }

    let totalNegativeControls = 6
    let eg6NegativeControlsValid = negRejected == totalNegativeControls
    let allPassed = eg1ProvenanceZoneAUp08Clean
        && eg2DualRouteUp07Sound
        && eg3ShardConservationAndHashesValid
        && eg4SyntheticDiffsValid
        && eg5LeanPreflightModulesValid
        && eg6NegativeControlsValid

    let digestSrc = "\(inputDigestsSha256)|\(syntheticDiffsSha256)|S:\(shardArr.count):\(quickCheckShards):\(fullBuildShards)|F:\(fullArr.count)|NEG:\(negRejected)/\(totalNegativeControls)|PASS:\(allPassed)"
    let emitterDigestSha256 = emitSha256Hex(digestSrc)

    return Arc5EmitterReceipt(
        bundleSuiteId: bundleSuiteId,
        baselineCommit: baselineCommit,
        targetRepoMutationAllowed: targetRepoMutationAllowed,
        eg1ProvenanceZoneAUp08Clean: eg1ProvenanceZoneAUp08Clean,
        eg2DualRouteUp07Sound: eg2DualRouteUp07Sound,
        eg3ShardConservationAndHashesValid: eg3ShardConservationAndHashesValid,
        eg4SyntheticDiffsValid: eg4SyntheticDiffsValid,
        eg5LeanPreflightModulesValid: eg5LeanPreflightModulesValid,
        eg6NegativeControlsValid: eg6NegativeControlsValid,
        totalShards: shardArr.count,
        quickCheckShards: quickCheckShards,
        fullBuildShards: fullBuildShards,
        totalFullBundles: fullArr.count,
        syntheticTransformsPassed: syntheticTransformsPassed,
        negativeControlsRejected: negRejected,
        totalNegativeControls: totalNegativeControls,
        syntheticDiffsSha256: syntheticDiffsSha256,
        inputDigestsSha256: inputDigestsSha256,
        emitterDigestSha256: emitterDigestSha256,
        allPassed: allPassed
    )
}
