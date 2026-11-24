// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone Arc 7 G4-G5 CI Receipt Ingestor & Airlock Rehearsal Verifier
// (pure Swift 6, zero external dependencies).

import Foundation

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256
// =============================================================================

private let rehSha256K: [UInt32] = [
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
private func rehRotr32(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}

public func rehearsalSha256Hex(_ data: [UInt8]) -> String {
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
            let s0 = rehRotr32(w[i - 15], 7) ^ rehRotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rehRotr32(w[i - 2], 17) ^ rehRotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
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
            let s1 = rehRotr32(e, 6) ^ rehRotr32(e, 11) ^ rehRotr32(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let t1 = hh &+ s1 &+ ch &+ rehSha256K[i] &+ w[i]
            let s0 = rehRotr32(a, 2) ^ rehRotr32(a, 13) ^ rehRotr32(a, 22)
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

public func rehearsalSha256Hex(_ text: String) -> String {
    rehearsalSha256Hex(Array(text.utf8))
}

public struct RehearsalError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) {
        self.message = message
    }
}

// =============================================================================
// 2. Pure Zero-Dependency JSON Parser
// =============================================================================

public enum RJVal: Sendable {
    case null
    case bool(Bool)
    case num(String)
    case str(String)
    case arr([RJVal])
    case obj([String: RJVal])

    public func asBool() -> Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    public func asU64() -> UInt64? {
        if case .num(let s) = self { return UInt64(s) }
        return nil
    }
    public func asStr() -> String? {
        if case .str(let s) = self { return s }
        return nil
    }
    public func asArr() -> [RJVal]? {
        if case .arr(let a) = self { return a }
        return nil
    }
    public func asObj() -> [String: RJVal]? {
        if case .obj(let m) = self { return m }
        return nil
    }
    public func get(_ k: String) -> RJVal? {
        if case .obj(let m) = self { return m[k] }
        return nil
    }
}

private struct RJsonParser {
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

    mutating func parseVal() throws -> RJVal {
        skipWs()
        guard let b = peek() else {
            throw RehearsalError("unexpected EOF in JSON at \(pos)")
        }
        switch b {
        case 0x22: return .str(try parseStr())
        case 0x5b: return try parseArr()
        case 0x7b: return try parseObj()
        case 0x74: return try expectLit([0x74, 0x72, 0x75, 0x65], .bool(true))
        case 0x66: return try expectLit([0x66, 0x61, 0x6c, 0x73, 0x65], .bool(false))
        case 0x6e: return try expectLit([0x6e, 0x75, 0x6c, 0x6c], .null)
        case 0x2d, 0x30...0x39: return try parseNum()
        default: throw RehearsalError("unexpected JSON token at \(pos)")
        }
    }

    mutating func expectLit(_ lit: [UInt8], _ val: RJVal) throws -> RJVal {
        guard pos + lit.count <= bytes.count else {
            throw RehearsalError("truncated literal at \(pos)")
        }
        for i in 0..<lit.count {
            if bytes[pos + i] != lit[i] {
                throw RehearsalError("invalid literal at \(pos)")
            }
        }
        pos += lit.count
        return val
    }

    mutating func parseStr() throws -> String {
        guard peek() == 0x22 else {
            throw RehearsalError("expected quote")
        }
        pos += 1
        var buf: [UInt8] = []
        while pos < bytes.count {
            let b = bytes[pos]
            pos += 1
            if b == 0x22 {
                guard let s = String(bytes: buf, encoding: .utf8) else {
                    throw RehearsalError("invalid utf8 string")
                }
                return s
            }
            if b == 0x5c {
                guard pos < bytes.count else {
                    throw RehearsalError("truncated escape")
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
                        throw RehearsalError("truncated unicode escape")
                    }
                    guard let hex = String(bytes: bytes[pos..<(pos + 4)], encoding: .utf8),
                          let code = UInt32(hex, radix: 16),
                          let scalar = UnicodeScalar(code)
                    else {
                        throw RehearsalError("bad unicode escape")
                    }
                    pos += 4
                    buf.append(contentsOf: String(scalar).utf8)
                default:
                    throw RehearsalError("unsupported escape")
                }
            } else {
                buf.append(b)
            }
        }
        throw RehearsalError("unterminated JSON string")
    }

    mutating func parseNum() throws -> RJVal {
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
            throw RehearsalError("bad number")
        }
        return .num(raw)
    }

    mutating func parseArr() throws -> RJVal {
        pos += 1
        skipWs()
        var items: [RJVal] = []
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
                throw RehearsalError("expected ',' or ']'")
            }
        }
    }

    mutating func parseObj() throws -> RJVal {
        pos += 1
        skipWs()
        var map: [String: RJVal] = [:]
        if peek() == 0x7d {
            pos += 1
            return .obj(map)
        }
        while true {
            skipWs()
            let k = try parseStr()
            skipWs()
            guard peek() == 0x3a else {
                throw RehearsalError("expected ':'")
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
                throw RehearsalError("expected ',' or '}'")
            }
        }
    }
}

public func parseRehearsalJSON(_ input: String) throws -> RJVal {
    var parser = RJsonParser(bytes: Array(input.utf8))
    let val = try parser.parseVal()
    parser.skipWs()
    if parser.pos != parser.bytes.count {
        throw RehearsalError("trailing JSON bytes")
    }
    return val
}

// =============================================================================
// 3. Pinned Upstream Constants & Shared G4/G5 Validation Primitives
// =============================================================================

public let pinnedBaselineCommit = "51d9b1a28026d458aef9c9af3df8b083276e3d2d"
public let pinnedToolchain = "leanprover/lean4:v4.36.0"
public let pinnedLakefileSha256 = "e12dd96eb155851de5107571dbfc959e5d9b230ead90331b4778b55b048590bb"
public let pinnedManifestSha256 = "ee003c5c7a9b2b2a82a142b6633916661c07117199dd143d94d1af63910237df"
public let pinnedComparatorSha256 = "8ea890e6ccda9cf3983ada343af18a41d12542036875a3936e7925ed5b1582ff"
public let pinnedExportTargetsSha256 = "9eeb2e5e55be4a78f6e4983fc950dba915b45ad8aeb7a02a32341927a89e05e8"
public let pinnedToolchainFileSha256 = "582a63f8f9c5128067b688778c1051cf1464c3ca9d57b9325025c051c29b774a"
public let pinnedChallengeExportSha256 = "bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9"

public let requiredFiveTheorems: [String] = [
    "riemannHypothesis",
    "riemannZeta_eq_zero_re",
    "LFunction_ne_zero_of_half_lt_re",
    "LFunction_eq_zero_re",
    "LFunction_eq_zero_re_of_isPrimitive",
]

public let permittedThreeAxioms: Set<String> = ["propext", "Quot.sound", "Classical.choice"]

public func isHexOfLen(_ s: String, _ expectedLen: Int) -> Bool {
    let bytes = Array(s.utf8)
    guard bytes.count == expectedLen else { return false }
    for b in bytes {
        let isDigit = b >= 0x30 && b <= 0x39
        let isLowerHex = b >= 0x61 && b <= 0x66
        if !isDigit && !isLowerHex {
            return false
        }
    }
    return true
}

public func containsVerbatimProofBody(_ rawJSON: String) -> Bool {
    rawJSON.contains(":= by")
        || rawJSON.contains("private theorem ")
        || rawJSON.contains("noncomputable def ")
        || rawJSON.contains("public import Mathlib")
}

public func classifyUpstreamQuickCheck(
    changedRoots: Int,
    closureModules: UInt64,
    hasDeletedFiles: Bool
) -> (String, String?) {
    if hasDeletedFiles {
        return ("full_rh_build", "deleted/unsafe source requires full build")
    }
    if changedRoots == 0 || changedRoots > 8 {
        return ("full_rh_build", "more than eight changed source roots; deferred")
    }
    if closureModules > 2000 {
        return ("full_rh_build", "project ancestor cone exceeds small-runner budget")
    }
    return ("quick_check", nil)
}

public func computeCiInputFingerprint(
    sourceTree: String,
    lakefileSha256: String,
    manifestSha256: String,
    toolchain: String
) -> String {
    let canonical = "{\"build_roots\":{},\"lakefile_sha256\":\"\(lakefileSha256)\",\"manifest_sha256\":\"\(manifestSha256)\",\"source_tree\":\"\(sourceTree)\",\"toolchain\":\"\(toolchain)\"}"
    return rehearsalSha256Hex(canonical)
}

public func validateQuickCheckReceipt(_ val: RJVal, expectedBaseHead: String) throws {
    let status = val.get("status")?.asStr() ?? ""
    let scope = val.get("scope")?.asStr() ?? ""
    let fullBuild = val.get("full_build")?.asBool() ?? true
    let exitCode = val.get("exit_code")?.asU64() ?? 1
    let hasDel = val.get("has_deleted_files")?.asBool() ?? false
    let baseHead = val.get("base_head")?.asStr() ?? ""
    let candHead = val.get("candidate_head")?.asStr() ?? ""
    let closure = val.get("ancestor_modules")?.asU64() ?? UInt64.max
    guard let targets = val.get("targets")?.asArr() else {
        throw RehearsalError("missing targets")
    }
    if scope != "changed-modules-only" {
        throw RehearsalError("quick-check scope must be changed-modules-only")
    }
    if fullBuild {
        throw RehearsalError("quick-check receipt must declare full_build=false")
    }
    if hasDel {
        throw RehearsalError("deleted/unsafe source requires full build (scripts/quick-check.py:80)")
    }
    if baseHead != expectedBaseHead {
        throw RehearsalError("stale base_head triggers ICD Section 4 retest")
    }
    if !isHexOfLen(candHead, 40) {
        throw RehearsalError("invalid 40-hex candidate_head")
    }
    if targets.isEmpty || targets.count > 8 {
        throw RehearsalError("quick-check requires 1..=8 target roots")
    }
    if closure > 2000 {
        throw RehearsalError("quick-check closure exceeds 2000-module budget")
    }
    if status != "changed_roots_pass" || exitCode != 0 {
        throw RehearsalError("quick-check did not pass: status=\(status) exit=\(exitCode)")
    }
}

public func validateCiBuildReceipt(_ val: RJVal, expectedBaseHead: String) throws {
    let schema = val.get("schema")?.asU64() ?? 0
    let fullBuild = val.get("full_build")?.asBool() ?? true
    let baseHead = val.get("base_head")?.asStr() ?? expectedBaseHead
    let candHead = val.get("candidate_head")?.asStr() ?? ""
    let candTree = val.get("candidate_tree")?.asStr() ?? ""
    let srcTree = val.get("source_tree")?.asStr() ?? ""
    let toolchain = val.get("toolchain")?.asStr() ?? ""
    let lfSha = val.get("lakefile_sha256")?.asStr() ?? ""
    let mfSha = val.get("manifest_sha256")?.asStr() ?? ""
    let fp = val.get("input_fingerprint")?.asStr() ?? ""
    let exitCode = val.get("build_exit_code")?.asU64() ?? 1
    let mapSha = val.get("map_sha256")?.asStr() ?? ""
    let mmSha = val.get("module_manifest_sha256")?.asStr() ?? ""

    if schema != 1 {
        throw RehearsalError("ci-build receipt schema must equal 1")
    }
    if !fullBuild {
        throw RehearsalError("ci-build G4/G5 receipt requires full_build=true")
    }
    if baseHead != expectedBaseHead {
        throw RehearsalError("stale base_head triggers ICD Section 4 retest")
    }
    if !isHexOfLen(candHead, 40) || !isHexOfLen(candTree, 40) || !isHexOfLen(srcTree, 40) {
        throw RehearsalError("invalid 40-hex git identity in ci-build receipt")
    }
    if toolchain != pinnedToolchain {
        throw RehearsalError("toolchain mismatch: got '\(toolchain)'")
    }
    if lfSha != pinnedLakefileSha256 {
        throw RehearsalError("Zone A drift: lakefile_sha256 mismatch")
    }
    if mfSha != pinnedManifestSha256 {
        throw RehearsalError("Zone A drift: manifest_sha256 mismatch")
    }
    let expectedFp = computeCiInputFingerprint(
        sourceTree: srcTree,
        lakefileSha256: lfSha,
        manifestSha256: mfSha,
        toolchain: toolchain
    )
    if fp != expectedFp {
        throw RehearsalError("ci-build input_fingerprint recomputation mismatch")
    }
    if exitCode != 0 {
        throw RehearsalError("ci-build failed with exit code \(exitCode)")
    }
    if !isHexOfLen(mapSha, 64) || !isHexOfLen(mmSha, 64) {
        throw RehearsalError("invalid 64-hex map_sha256 or module_manifest_sha256")
    }
}

public func validateG5ComparatorReceipt(_ val: RJVal, requireRemoteAttestation: Bool) throws {
    let fullBuild = val.get("full_build")?.asBool() ?? false
    let challengeMod = val.get("challenge_module")?.asStr() ?? ""
    let solutionMod = val.get("solution_module")?.asStr() ?? ""
    let lkExit = val.get("lean_kernel_exit")?.asU64() ?? 1
    let lpExit = val.get("leanchecker_paranoid_exit")?.asU64() ?? 1
    let nanodaExit = val.get("nanoda_exit")?.asU64() ?? 1
    let chExp = val.get("challenge_export_sha256")?.asStr() ?? ""
    let solExp = val.get("solution_export_sha256")?.asStr() ?? ""
    let rehearsalMode = val.get("rehearsal_mode")?.asBool() ?? false
    let remoteAttested = val.get("remote_ci_attestation")?.asBool() ?? false
    let remoteRunId = val.get("remote_workflow_run_id")?.asU64() ?? 0

    if !fullBuild {
        throw RehearsalError("quick-check (full_build=false) cannot attest G5 release")
    }
    if rehearsalMode && remoteAttested {
        throw RehearsalError("PRIN-06 violation: rehearsal fixture cannot spoof remote_ci_attestation=true")
    }
    if requireRemoteAttestation && (!remoteAttested || remoteRunId == 0) {
        throw RehearsalError("live G5 promotion requires genuine remote_ci_attestation=true and run_id > 0")
    }
    if challengeMod != "Challenge" || solutionMod != "Main" {
        throw RehearsalError("comparator modules must be Challenge and Main")
    }
    if lkExit != 0 || lpExit != 0 || nanodaExit != 0 {
        throw RehearsalError("G5 kernel check failed: lean=\(lkExit), paranoid=\(lpExit), nanoda=\(nanodaExit)")
    }
    if chExp != pinnedChallengeExportSha256 || !isHexOfLen(solExp, 64) {
        throw RehearsalError("invalid challenge or solution export SHA-256")
    }
    guard let thms = val.get("theorem_names")?.asArr() else {
        throw RehearsalError("missing theorem_names")
    }
    let thmSet = Set(thms.compactMap { $0.asStr() })
    for req in requiredFiveTheorems {
        if !thmSet.contains(req) {
            throw RehearsalError("missing required Challenge theorem '\(req)'")
        }
    }
    guard let axMap = val.get("theorem_axioms")?.asObj() else {
        throw RehearsalError("missing theorem_axioms map")
    }
    for req in requiredFiveTheorems {
        guard let arr = axMap[req]?.asArr() else {
            throw RehearsalError("missing #print axioms list for '\(req)'")
        }
        for ax in arr {
            guard let name = ax.asStr() else {
                throw RehearsalError("non-string axiom entry")
            }
            if !permittedThreeAxioms.contains(name) {
                throw RehearsalError("UP-02 violation: forbidden axiom '\(name)' on '\(req)'")
            }
        }
    }
}

// =============================================================================
// 4. Arc 7 Rehearsal Receipt & Pure Offline Verifier (RG-1..RG-6)
// =============================================================================

public struct Arc7RehearsalReceipt: Sendable, Equatable {
    public let rehearsalSuiteId: String
    public let baselineCommit: String
    public let rehearsalMode: Bool
    public let remoteCiAttestation: Bool
    public let targetRepoMutationAllowed: Bool
    public let rg1ZoneAPinsAndUp08Clean: Bool
    public let rg2QuickCheckAndDeferralValid: Bool
    public let rg3CiBuildReceiptValid: Bool
    public let rg4G5ComparatorAndAxiomsValid: Bool
    public let rg5Arc6BindingAndHonestyValid: Bool
    public let rg6NegativeControlsValid: Bool
    public let quickCheckEligibleShards: Int
    public let fullBuildDeferredShards: Int
    public let totalRoutedShards: Int
    public let linkedArc6Files: Int
    public let linkedArc6SavedLines: UInt64
    public let linkedArc6SavedBytes: UInt64
    public let negativeControlsRejected: Int
    public let totalNegativeControls: Int
    public let inputDigestsSha256: String
    public let rehearsalDigestSha256: String
    public let allPassed: Bool

    public func toCanonicalJSON() -> String {
        "{\"all_passed\":\(allPassed),\"baseline_commit\":\"\(baselineCommit)\",\"full_build_deferred_shards\":\(fullBuildDeferredShards),\"input_digests_sha256\":\"\(inputDigestsSha256)\",\"linked_arc6_files\":\(linkedArc6Files),\"linked_arc6_saved_bytes\":\(linkedArc6SavedBytes),\"linked_arc6_saved_lines\":\(linkedArc6SavedLines),\"negative_controls_rejected\":\(negativeControlsRejected),\"quick_check_eligible_shards\":\(quickCheckEligibleShards),\"rehearsal_digest_sha256\":\"\(rehearsalDigestSha256)\",\"rehearsal_mode\":\(rehearsalMode),\"rehearsal_suite_id\":\"\(rehearsalSuiteId)\",\"remote_ci_attestation\":\(remoteCiAttestation),\"rg1_zone_a_pins_and_up08_clean\":\(rg1ZoneAPinsAndUp08Clean),\"rg2_quick_check_and_deferral_valid\":\(rg2QuickCheckAndDeferralValid),\"rg3_ci_build_receipt_valid\":\(rg3CiBuildReceiptValid),\"rg4_g5_comparator_and_axioms_valid\":\(rg4G5ComparatorAndAxiomsValid),\"rg5_arc6_binding_and_honesty_valid\":\(rg5Arc6BindingAndHonestyValid),\"rg6_negative_controls_valid\":\(rg6NegativeControlsValid),\"target_repo_mutation_allowed\":\(targetRepoMutationAllowed),\"total_negative_controls\":\(totalNegativeControls),\"total_routed_shards\":\(totalRoutedShards)}"
    }
}

private func readUTF8(_ url: URL, label: String) throws -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw RehearsalError("read \(label): \(error)")
    }
}

public func verifyArc7Rehearsal(repoRoot: URL) throws -> Arc7RehearsalReceipt {
    let relReh = "transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json"
    let relPlan = "transfer/patches/arc6_patch_plan_v1.json"
    let relBundles = "transfer/bundles/arc5_preflight_bundles_v1.json"

    let rehRaw = try readUTF8(repoRoot.appendingPathComponent(relReh), label: relReh)
    let planRaw = try readUTF8(repoRoot.appendingPathComponent(relPlan), label: relPlan)
    let bundlesRaw = try readUTF8(repoRoot.appendingPathComponent(relBundles), label: relBundles)

    var dchain = ""
    for (label, content) in [
        (relReh, rehRaw),
        (relPlan, planRaw),
        (relBundles, bundlesRaw),
    ] {
        dchain.append(label)
        dchain.append(":")
        dchain.append(rehearsalSha256Hex(content))
        dchain.append(";")
    }
    let inputDigestsSha256 = rehearsalSha256Hex(dchain)

    let reh = try parseRehearsalJSON(rehRaw)
    let plan = try parseRehearsalJSON(planRaw)
    let bundles = try parseRehearsalJSON(bundlesRaw)

    guard let rehearsalSuiteId = reh.get("rehearsal_suite_id")?.asStr() else {
        throw RehearsalError("missing rehearsal_suite_id")
    }
    guard let baselineCommit = reh.get("source_repo_commit")?.asStr() else {
        throw RehearsalError("missing source_repo_commit")
    }
    let rehearsalMode = reh.get("rehearsal_mode")?.asBool() ?? false
    let remoteCiAttestation = reh.get("remote_ci_attestation")?.asBool() ?? true
    let targetRepoMutationAllowed = reh.get("target_repo_mutation_allowed")?.asBool() ?? true

    guard let pins = reh.get("zone_a_pins") else {
        throw RehearsalError("missing zone_a_pins")
    }
    let pinsOk = pins.get("toolchain")?.asStr() == pinnedToolchain
        && pins.get("lakefile_sha256")?.asStr() == pinnedLakefileSha256
        && pins.get("manifest_sha256")?.asStr() == pinnedManifestSha256
        && pins.get("comparator_sha256")?.asStr() == pinnedComparatorSha256
        && pins.get("export_targets_sha256")?.asStr() == pinnedExportTargetsSha256
        && pins.get("lean_toolchain_sha256")?.asStr() == pinnedToolchainFileSha256

    let planSha = plan.get("source_repo_commit")?.asStr() ?? ""
    let bundlesSha = bundles.get("source_repo_commit")?.asStr() ?? ""
    let rg1ZoneAPinsAndUp08Clean = !targetRepoMutationAllowed
        && baselineCommit == pinnedBaselineCommit
        && baselineCommit == planSha
        && baselineCommit == bundlesSha
        && pinsOk
        && !containsVerbatimProofBody(rehRaw)

    guard let routing = reh.get("refined_shard_routing")?.asArr() else {
        throw RehearsalError("missing refined_shard_routing")
    }
    var routingOk = true
    var quickCheckEligibleShards = 0
    var fullBuildDeferredShards = 0
    var z0DeferredCount = 0
    for r in routing {
        let zid = r.get("zone_id")?.asStr() ?? ""
        let roots = Int(r.get("changed_roots")?.asU64() ?? 0)
        let closure = r.get("closure_modules")?.asU64() ?? 0
        let hasDel = r.get("has_deleted_files")?.asBool() ?? false
        let route = r.get("ci_route")?.asStr() ?? ""
        let (expRoute, _) = classifyUpstreamQuickCheck(
            changedRoots: roots,
            closureModules: closure,
            hasDeletedFiles: hasDel
        )
        if route != expRoute {
            routingOk = false
        }
        if route == "quick_check" {
            quickCheckEligibleShards += 1
        } else {
            fullBuildDeferredShards += 1
            if zid == "Z-C0" && hasDel {
                z0DeferredCount += 1
            }
        }
    }
    guard let qcReceipts = reh.get("rehearsed_quick_check_receipts")?.asArr() else {
        throw RehearsalError("missing rehearsed_quick_check_receipts")
    }
    var qcAllOk = qcReceipts.count == quickCheckEligibleShards && quickCheckEligibleShards == 3
    for qr in qcReceipts {
        do {
            try validateQuickCheckReceipt(qr, expectedBaseHead: baselineCommit)
        } catch {
            qcAllOk = false
        }
    }
    let rg2QuickCheckAndDeferralValid =
        routingOk && qcAllOk && z0DeferredCount == 14 && routing.count == 18

    guard let ciRec = reh.get("rehearsed_ci_build_receipt") else {
        throw RehearsalError("missing rehearsed_ci_build_receipt")
    }
    var rg3CiBuildReceiptValid = true
    do {
        try validateCiBuildReceipt(ciRec, expectedBaseHead: baselineCommit)
    } catch {
        rg3CiBuildReceiptValid = false
    }

    guard let g5Rec = reh.get("rehearsed_g5_comparator_receipt") else {
        throw RehearsalError("missing rehearsed_g5_comparator_receipt")
    }
    var g5SchemaOk = true
    do {
        try validateG5ComparatorReceipt(g5Rec, requireRemoteAttestation: false)
    } catch {
        g5SchemaOk = false
    }
    var g5RemoteBlocked = false
    do {
        try validateG5ComparatorReceipt(g5Rec, requireRemoteAttestation: true)
    } catch {
        g5RemoteBlocked = true
    }
    let rg4G5ComparatorAndAxiomsValid = g5SchemaOk && g5RemoteBlocked

    guard let ds = reh.get("arc6_dataset_summary") else {
        throw RehearsalError("missing arc6_dataset_summary")
    }
    let linkedArc6Files = Int(ds.get("total_files")?.asU64() ?? 0)
    let linkedArc6SavedLines = ds.get("total_saved_lines")?.asU64() ?? 0
    let linkedArc6SavedBytes = ds.get("total_saved_bytes")?.asU64() ?? 0

    let planFiles = Int(plan.get("total_files")?.asU64() ?? 0)
    guard let planZs = plan.get("zone_summaries") else {
        throw RehearsalError("missing plan zone_summaries")
    }
    let planSl = (planZs.get("Z-C0")?.get("saved_lines")?.asU64() ?? 0)
        + (planZs.get("Z-C2")?.get("saved_lines")?.asU64() ?? 0)
        + (planZs.get("Z-C4")?.get("saved_lines")?.asU64() ?? 0)
    let planSb = (planZs.get("Z-C0")?.get("saved_bytes")?.asU64() ?? 0)
        + (planZs.get("Z-C2")?.get("saved_bytes")?.asU64() ?? 0)
        + (planZs.get("Z-C4")?.get("saved_bytes")?.asU64() ?? 0)

    let rg5Arc6BindingAndHonestyValid = rehearsalMode
        && !remoteCiAttestation
        && linkedArc6Files == 137
        && linkedArc6Files == planFiles
        && linkedArc6SavedLines == planSl
        && linkedArc6SavedBytes == planSb

    // RG-6: 8 Adversarial Negative Controls (all 8 must fail closed!)
    var negRejected = 0

    let neg1 = try parseRehearsalJSON(
        "{\"full_build\":false,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}"
    )
    do {
        try validateG5ComparatorReceipt(neg1, requireRemoteAttestation: false)
    } catch {
        negRejected += 1
    }

    let neg2 = try parseRehearsalJSON(
        "{\"status\":\"changed_roots_pass\",\"scope\":\"changed-modules-only\",\"full_build\":false,\"exit_code\":0,\"has_deleted_files\":true,\"base_head\":\"\(pinnedBaselineCommit)\",\"candidate_head\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"ancestor_modules\":50,\"targets\":[\"Foo.Bar\"]}"
    )
    do {
        try validateQuickCheckReceipt(neg2, expectedBaseHead: pinnedBaselineCommit)
    } catch {
        negRejected += 1
    }

    let neg3 = try parseRehearsalJSON(
        "{\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\",\"Lean.ofReduceBool\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}"
    )
    do {
        try validateG5ComparatorReceipt(neg3, requireRemoteAttestation: false)
    } catch {
        negRejected += 1
    }

    let neg4 = try parseRehearsalJSON(
        "{\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":2,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}"
    )
    do {
        try validateG5ComparatorReceipt(neg4, requireRemoteAttestation: false)
    } catch {
        negRejected += 1
    }

    let neg5 = try parseRehearsalJSON(
        "{\"schema\":1,\"full_build\":true,\"base_head\":\"\(pinnedBaselineCommit)\",\"candidate_head\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"candidate_tree\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_tree\":\"cccccccccccccccccccccccccccccccccccccccc\",\"toolchain\":\"\(pinnedToolchain)\",\"lakefile_sha256\":\"\(pinnedLakefileSha256)\",\"manifest_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"input_fingerprint\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"build_exit_code\":0,\"map_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"module_manifest_sha256\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"}"
    )
    do {
        try validateCiBuildReceipt(neg5, expectedBaseHead: pinnedBaselineCommit)
    } catch {
        negRejected += 1
    }

    let neg6 = try parseRehearsalJSON(
        "{\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"]}}"
    )
    do {
        try validateG5ComparatorReceipt(neg6, requireRemoteAttestation: false)
    } catch {
        negRejected += 1
    }

    let neg7 = try parseRehearsalJSON(
        "{\"status\":\"changed_roots_pass\",\"scope\":\"changed-modules-only\",\"full_build\":false,\"exit_code\":0,\"has_deleted_files\":false,\"base_head\":\"0000000000000000000000000000000000000000\",\"candidate_head\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"ancestor_modules\":12,\"targets\":[\"Foo.Bar\"]}"
    )
    do {
        try validateQuickCheckReceipt(neg7, expectedBaseHead: pinnedBaselineCommit)
    } catch {
        negRejected += 1
    }

    let neg8 = try parseRehearsalJSON(
        "{\"rehearsal_mode\":true,\"remote_ci_attestation\":true,\"remote_workflow_run_id\":999,\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}"
    )
    do {
        try validateG5ComparatorReceipt(neg8, requireRemoteAttestation: true)
    } catch {
        negRejected += 1
    }

    let totalNegativeControls = 8
    let rg6NegativeControlsValid = negRejected == totalNegativeControls
    let allPassed = rg1ZoneAPinsAndUp08Clean
        && rg2QuickCheckAndDeferralValid
        && rg3CiBuildReceiptValid
        && rg4G5ComparatorAndAxiomsValid
        && rg5Arc6BindingAndHonestyValid
        && rg6NegativeControlsValid

    let digestSrc = "\(inputDigestsSha256)|R:\(routing.count):\(quickCheckEligibleShards):\(fullBuildDeferredShards)|A6:\(linkedArc6Files):\(linkedArc6SavedLines):\(linkedArc6SavedBytes)|NEG:\(negRejected)/\(totalNegativeControls)|REH:\(rehearsalMode):\(remoteCiAttestation)|PASS:\(allPassed)"
    let rehearsalDigestSha256 = rehearsalSha256Hex(digestSrc)

    return Arc7RehearsalReceipt(
        rehearsalSuiteId: rehearsalSuiteId,
        baselineCommit: baselineCommit,
        rehearsalMode: rehearsalMode,
        remoteCiAttestation: remoteCiAttestation,
        targetRepoMutationAllowed: targetRepoMutationAllowed,
        rg1ZoneAPinsAndUp08Clean: rg1ZoneAPinsAndUp08Clean,
        rg2QuickCheckAndDeferralValid: rg2QuickCheckAndDeferralValid,
        rg3CiBuildReceiptValid: rg3CiBuildReceiptValid,
        rg4G5ComparatorAndAxiomsValid: rg4G5ComparatorAndAxiomsValid,
        rg5Arc6BindingAndHonestyValid: rg5Arc6BindingAndHonestyValid,
        rg6NegativeControlsValid: rg6NegativeControlsValid,
        quickCheckEligibleShards: quickCheckEligibleShards,
        fullBuildDeferredShards: fullBuildDeferredShards,
        totalRoutedShards: routing.count,
        linkedArc6Files: linkedArc6Files,
        linkedArc6SavedLines: linkedArc6SavedLines,
        linkedArc6SavedBytes: linkedArc6SavedBytes,
        negativeControlsRejected: negRejected,
        totalNegativeControls: totalNegativeControls,
        inputDigestsSha256: inputDigestsSha256,
        rehearsalDigestSha256: rehearsalDigestSha256,
        allPassed: allPassed
    )
}
