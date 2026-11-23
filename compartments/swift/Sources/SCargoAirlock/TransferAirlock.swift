// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock Engine
// (pure Swift 6, zero external dependencies).

import Foundation

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256
// =============================================================================

private let airlockSha256K: [UInt32] = [
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
private func rotr32(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}

public func airlockSha256Hex(_ data: [UInt8]) -> String {
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
            let s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
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
            let s1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let t1 = hh &+ s1 &+ ch &+ airlockSha256K[i] &+ w[i]
            let s0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)
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

public func airlockSha256Hex(_ text: String) -> String {
    airlockSha256Hex(Array(text.utf8))
}

public struct AirlockError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) {
        self.message = message
    }
}

// =============================================================================
// 2. Pure Zero-Dependency JSON Parser
// =============================================================================

private enum AJVal {
    case null
    case bool(Bool)
    case num(String)
    case str(String)
    case arr([AJVal])
    case obj([String: AJVal])

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
    func asArr() -> [AJVal]? {
        if case .arr(let a) = self { return a }
        return nil
    }
    func get(_ k: String) -> AJVal? {
        if case .obj(let m) = self { return m[k] }
        return nil
    }
}

private struct AJsonParser {
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

    mutating func parseVal() throws -> AJVal {
        skipWs()
        guard let b = peek() else {
            throw AirlockError("unexpected EOF in JSON at \(pos)")
        }
        switch b {
        case 0x22: return .str(try parseStr())
        case 0x5b: return try parseArr()
        case 0x7b: return try parseObj()
        case 0x74: return try expectLit([0x74, 0x72, 0x75, 0x65], .bool(true))
        case 0x66: return try expectLit([0x66, 0x61, 0x6c, 0x73, 0x65], .bool(false))
        case 0x6e: return try expectLit([0x6e, 0x75, 0x6c, 0x6c], .null)
        case 0x2d, 0x30...0x39: return try parseNum()
        default: throw AirlockError("unexpected JSON token at \(pos)")
        }
    }

    mutating func expectLit(_ lit: [UInt8], _ val: AJVal) throws -> AJVal {
        guard pos + lit.count <= bytes.count else {
            throw AirlockError("truncated literal at \(pos)")
        }
        for i in 0..<lit.count {
            if bytes[pos + i] != lit[i] {
                throw AirlockError("invalid literal at \(pos)")
            }
        }
        pos += lit.count
        return val
    }

    mutating func parseStr() throws -> String {
        guard peek() == 0x22 else {
            throw AirlockError("expected quote")
        }
        pos += 1
        var buf: [UInt8] = []
        while pos < bytes.count {
            let b = bytes[pos]
            pos += 1
            if b == 0x22 {
                guard let s = String(bytes: buf, encoding: .utf8) else {
                    throw AirlockError("invalid utf8 string")
                }
                return s
            }
            if b == 0x5c {
                guard pos < bytes.count else {
                    throw AirlockError("truncated escape")
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
                        throw AirlockError("truncated unicode escape")
                    }
                    guard let hex = String(bytes: bytes[pos..<(pos + 4)], encoding: .utf8),
                          let code = UInt32(hex, radix: 16),
                          let scalar = UnicodeScalar(code)
                    else {
                        throw AirlockError("bad unicode escape")
                    }
                    pos += 4
                    buf.append(contentsOf: String(scalar).utf8)
                default:
                    throw AirlockError("unsupported escape")
                }
            } else {
                buf.append(b)
            }
        }
        throw AirlockError("unterminated JSON string")
    }

    mutating func parseNum() throws -> AJVal {
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
            throw AirlockError("bad number")
        }
        return .num(raw)
    }

    mutating func parseArr() throws -> AJVal {
        pos += 1
        skipWs()
        var items: [AJVal] = []
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
                throw AirlockError("expected ',' or ']'")
            }
        }
    }

    mutating func parseObj() throws -> AJVal {
        pos += 1
        skipWs()
        var map: [String: AJVal] = [:]
        if peek() == 0x7d {
            pos += 1
            return .obj(map)
        }
        while true {
            skipWs()
            let k = try parseStr()
            skipWs()
            guard peek() == 0x3a else {
                throw AirlockError("expected ':'")
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
                throw AirlockError("expected ',' or '}'")
            }
        }
    }
}

private func parseAirlockJSON(_ input: String) throws -> AJVal {
    var p = AJsonParser(bytes: Array(input.utf8))
    let val = try p.parseVal()
    p.skipWs()
    if p.pos != p.bytes.count {
        throw AirlockError("trailing JSON bytes")
    }
    return val
}

// =============================================================================
// 3. Core Airlock Domain Types: MassVector, Pareto Ratios, Batching, Transforms
// =============================================================================

public struct MassVector: Sendable, Equatable {
    public let files: UInt64
    public let lines: UInt64
    public let bytes: UInt64

    public init(files: UInt64, lines: UInt64, bytes: UInt64) {
        self.files = files
        self.lines = lines
        self.bytes = bytes
    }

    public func isParetoReduction(_ after: MassVector) -> Bool {
        after.files <= files && after.lines < lines && after.bytes < bytes
    }

    public static func rhoPpm(before: UInt64, after: UInt64) -> UInt64 {
        if before == 0 {
            return 1_000_000
        }
        let (hi, lo) = after.multipliedFullWidth(by: 1_000_000)
        return before.dividingFullWidth((high: hi, low: lo)).quotient
    }
}

public struct PackageQualification: Sendable, Equatable {
    public let packageId: String
    public let zoneId: String
    public let eligibleModules: Int
    public let batchCount: Int
    public let maxBatchSize: Int
    public let before: MassVector
    public let after: MassVector
    public let rhoFilesPpm: UInt64
    public let rhoLinesPpm: UInt64
    public let rhoBytesPpm: UInt64
    public let paretoStrict: Bool
    public let batchScheduleSha256: String
}

public struct Rung3AirlockReceipt: Sendable, Equatable {
    public let icdId: String
    public let baselineCommit: String
    public let targetRepoMutationAllowed: Bool
    public let ag1ZoneAClean: Bool
    public let ag2ConservationExact: Bool
    public let ag3ParetoAndRctPassed: Bool
    public let ag4Up07BatchesAndAxiomsClean: Bool
    public let ag5SyntheticTransformsPassed: Bool
    public let strategyAA12Bps: UInt64
    public let strategyBA12Bps: UInt64
    public let multiDeclProtectedCount: Int
    public let lineageTargetsVerified: Int
    public let negativeControlsRejected: Int
    public let totalNegativeControls: Int
    public let packages: [PackageQualification]
    public let inputDigestsSha256: String
    public let airlockDigestSha256: String
    public let allPassed: Bool

    public func toCanonicalJSON() -> String {
        var pkgs = "["
        for (i, p) in packages.enumerated() {
            if i > 0 {
                pkgs.append(",")
            }
            pkgs.append(
                "{\"after_bytes\":\(p.after.bytes),\"after_files\":\(p.after.files),\"after_lines\":\(p.after.lines),\"batch_count\":\(p.batchCount),\"batch_schedule_sha256\":\"\(p.batchScheduleSha256)\",\"before_bytes\":\(p.before.bytes),\"before_files\":\(p.before.files),\"before_lines\":\(p.before.lines),\"eligible_modules\":\(p.eligibleModules),\"max_batch_size\":\(p.maxBatchSize),\"package_id\":\"\(p.packageId)\",\"pareto_strict\":\(p.paretoStrict),\"rho_bytes_ppm\":\(p.rhoBytesPpm),\"rho_files_ppm\":\(p.rhoFilesPpm),\"rho_lines_ppm\":\(p.rhoLinesPpm),\"zone_id\":\"\(p.zoneId)\"}"
            )
        }
        pkgs.append("]")
        return "{\"ag1_zone_a_clean\":\(ag1ZoneAClean),\"ag2_conservation_exact\":\(ag2ConservationExact),\"ag3_pareto_and_rct_passed\":\(ag3ParetoAndRctPassed),\"ag4_up07_batches_and_axioms_clean\":\(ag4Up07BatchesAndAxiomsClean),\"ag5_synthetic_transforms_passed\":\(ag5SyntheticTransformsPassed),\"airlock_digest_sha256\":\"\(airlockDigestSha256)\",\"all_passed\":\(allPassed),\"baseline_commit\":\"\(baselineCommit)\",\"icd_id\":\"\(icdId)\",\"input_digests_sha256\":\"\(inputDigestsSha256)\",\"lineage_targets_verified\":\(lineageTargetsVerified),\"multi_decl_protected_count\":\(multiDeclProtectedCount),\"negative_controls_rejected\":\(negativeControlsRejected),\"packages\":\(pkgs),\"strategy_a_a12_bps\":\(strategyAA12Bps),\"strategy_b_a12_bps\":\(strategyBA12Bps),\"target_repo_mutation_allowed\":\(targetRepoMutationAllowed),\"total_negative_controls\":\(totalNegativeControls)}"
    }
}

private func utf8Less(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
}

public func splitUp07Batches(_ modules: [String], cap: Int) -> [[String]] {
    if cap <= 0 {
        return []
    }
    let sorted = modules.sorted(by: utf8Less)
    var batches: [[String]] = []
    var idx = 0
    while idx < sorted.count {
        let end = min(idx + cap, sorted.count)
        batches.append(Array(sorted[idx..<end]))
        idx = end
    }
    return batches
}

private func verifyUp07Batches(_ modules: [String], batches: [[String]], cap: Int) -> Bool {
    let expected = Set(modules)
    var seen = Set<String>()
    for b in batches {
        if b.isEmpty || b.count > cap {
            return false
        }
        for m in b {
            if !seen.insert(m).inserted {
                return false
            }
        }
    }
    return seen == expected
}

private func hashBatchSchedule(packageId: String, batches: [[String]]) -> String {
    var canonical = "\(packageId)|"
    for (i, b) in batches.enumerated() {
        canonical.append("B\(i):")
        for (j, m) in b.enumerated() {
            if j > 0 {
                canonical.append(",")
            }
            canonical.append(m)
        }
        canonical.append(";")
    }
    return airlockSha256Hex(canonical)
}

public func varghaDelaneyA12BpsVsZeroControl(_ treatmentSavings: [UInt64]) -> UInt64 {
    let n = UInt64(treatmentSavings.count)
    if n == 0 {
        return 5000
    }
    let pos = UInt64(treatmentSavings.filter { $0 > 0 }.count)
    let zero = n - pos
    let twoU = (pos * n * 2) + (zero * n)
    let denom = 2 * n * n
    return (twoU * 10_000) / denom
}

public func moduleToRelPath(_ moduleName: String) -> String {
    "src/\(moduleName.replacingOccurrences(of: ".", with: "/")).lean"
}

public func touchesZoneA(_ paths: [String], zoneA: Set<String>) -> Bool {
    paths.contains { zoneA.contains($0) }
}

public func axiomsPermitted(_ axioms: [String], permitted: Set<String>) -> Bool {
    !axioms.isEmpty && axioms.allSatisfy { permitted.contains($0) }
}

public func strategyBSafeGuard(
    declCount: UInt64,
    pairedImplExists: Bool,
    importsSubsetOfImpl: Bool,
    touchesCore: Bool
) -> Bool {
    declCount == 1 && pairedImplExists && importsSubsetOfImpl && !touchesCore
}

// =============================================================================
// 4. Clean-Room Synthetic Graph Transform Verifier (AG-5)
// =============================================================================

private struct SynthModule {
    var name: String
    var lines: UInt64
    var bytes: UInt64
    var imports: [String]
}

private struct SynthGraph {
    var root: String
    var modules: [SynthModule]

    func valid() -> Bool {
        var names = Set<String>()
        for m in modules {
            if !names.insert(m.name).inserted {
                return false
            }
        }
        if !names.contains(root) {
            return false
        }
        return modules.allSatisfy { m in m.imports.allSatisfy { names.contains($0) } }
    }

    func reachable() -> Set<String> {
        var adj: [String: [String]] = [:]
        for m in modules {
            adj[m.name] = m.imports
        }
        var vis = Set<String>()
        guard adj[root] != nil else { return vis }
        var queue = [root]
        var head = 0
        vis.insert(root)
        while head < queue.count {
            let u = queue[head]
            head += 1
            if let nbrs = adj[u] {
                for v in nbrs where adj[v] != nil && vis.insert(v).inserted {
                    queue.append(v)
                }
            }
        }
        return vis
    }

    func hasCycle() -> Bool {
        var indeg: [String: Int] = [:]
        var rev: [String: [String]] = [:]
        for m in modules {
            let uniq = Set(m.imports)
            indeg[m.name] = uniq.count
            for imp in uniq {
                rev[imp, default: []].append(m.name)
            }
        }
        var queue: [String] = []
        for (k, d) in indeg where d == 0 {
            queue.append(k)
        }
        var head = 0
        var peeled = 0
        while head < queue.count {
            let u = queue[head]
            head += 1
            peeled += 1
            if let deps = rev[u] {
                for dep in deps {
                    if let cur = indeg[dep] {
                        let next = cur > 0 ? cur - 1 : 0
                        indeg[dep] = next
                        if next == 0 {
                            queue.append(dep)
                        }
                    }
                }
            }
        }
        return peeled < modules.count
    }

    func mass() -> MassVector {
        MassVector(
            files: UInt64(modules.count),
            lines: modules.reduce(0) { $0 + $1.lines },
            bytes: modules.reduce(0) { $0 + $1.bytes }
        )
    }
}

public func verifySyntheticCleanRoomTransforms() -> Bool {
    let base = SynthGraph(
        root: "Main",
        modules: [
            SynthModule(name: "Main", lines: 20, bytes: 500, imports: ["CoreA", "CoreB"]),
            SynthModule(name: "CoreA", lines: 40, bytes: 1100, imports: ["WrapAStatement"]),
            SynthModule(name: "CoreB", lines: 30, bytes: 800, imports: ["CoreImpl"]),
            SynthModule(name: "WrapAStatement", lines: 22, bytes: 640, imports: ["CoreImpl"]),
            SynthModule(name: "CoreImpl", lines: 80, bytes: 2400, imports: []),
            SynthModule(name: "DeadLeaf1", lines: 25, bytes: 700, imports: ["CoreImpl"]),
            SynthModule(name: "DeadLeaf2", lines: 20, bytes: 500, imports: ["DeadLeaf1"]),
        ]
    )

    if !base.valid() || base.hasCycle() {
        return false
    }
    let baseReach = base.reachable()
    let baseMass = base.mass()

    // 1. Z-C0 Dead-Leaf Prune
    let pruned = SynthGraph(
        root: base.root,
        modules: base.modules.filter { baseReach.contains($0.name) }
    )
    let z0Ok = pruned.valid()
        && !pruned.hasCycle()
        && pruned.reachable() == baseReach
        && baseMass.isParetoReduction(pruned.mass())
        && pruned.mass().files + 2 == baseMass.files
        && pruned.mass().lines + 45 == baseMass.lines
        && pruned.mass().bytes + 1200 == baseMass.bytes

    // 2. Z-C1A Strategy A In-Place Alias
    var aliasG = base
    for i in aliasG.modules.indices where aliasG.modules[i].name == "WrapAStatement" {
        aliasG.modules[i].lines = 6
        aliasG.modules[i].bytes = 210
    }
    let z1aOk = aliasG.valid()
        && !aliasG.hasCycle()
        && aliasG.reachable() == baseReach
        && baseMass.isParetoReduction(aliasG.mass())
        && aliasG.mass().files == baseMass.files
        && aliasG.mass().lines + 16 == baseMass.lines
        && aliasG.mass().bytes + 430 == baseMass.bytes

    // 3. Z-C1B Strategy B Wrapper Collapse + Importer Rewire
    var collapseMods: [SynthModule] = []
    for m in base.modules {
        if m.name == "WrapAStatement" {
            continue
        }
        var cm = m
        if cm.name == "CoreImpl" {
            cm.lines += 1
            cm.bytes += 35
        }
        cm.imports = cm.imports.map { $0 == "WrapAStatement" ? "CoreImpl" : $0 }
        collapseMods.append(cm)
    }
    let collapseG = SynthGraph(root: base.root, modules: collapseMods)
    let cReach = collapseG.reachable()
    let z1bOk = collapseG.valid()
        && !collapseG.hasCycle()
        && cReach.contains("Main")
        && cReach.contains("CoreA")
        && cReach.contains("CoreB")
        && cReach.contains("CoreImpl")
        && !cReach.contains("WrapAStatement")
        && baseMass.isParetoReduction(collapseG.mass())
        && collapseG.mass().files + 1 == baseMass.files
        && collapseG.mass().lines + 21 == baseMass.lines
        && collapseG.mass().bytes + 605 == baseMass.bytes

    return z0Ok && z1aOk && z1bOk
}

// =============================================================================
// 5. Full Clean-Room Rung 3 Airlock Qualification Runner
// =============================================================================

private func checkUp08CleanRoomLeanDir(_ rootURL: URL) -> Bool {
    let leanURL = rootURL.appendingPathComponent("compartments/lean")
    do {
        let names = try FileManager.default.contentsOfDirectory(atPath: leanURL.path)
        for name in names {
            if name == "Development" || name == "Formalism" || name == "GroundTheory" {
                return false
            }
        }
        return true
    } catch {
        return false
    }
}

public func runRung3Airlock(repoRoot: URL) throws -> Rung3AirlockReceipt {
    let manifestRel = "transfer/packages/rung3_airlock_manifest_v1.json"
    let manifestRaw = try String(contentsOf: repoRoot.appendingPathComponent(manifestRel), encoding: .utf8)
    let manifest = try parseAirlockJSON(manifestRaw)

    guard let icdId = manifest.get("icd_id")?.asStr() else { throw AirlockError("missing icd_id") }
    guard let baselineCommit = manifest.get("baseline_commit")?.asStr() else { throw AirlockError("missing baseline_commit") }
    guard let targetRepoMutationAllowed = manifest.get("target_repo_mutation_allowed")?.asBool() else {
        throw AirlockError("missing target_repo_mutation_allowed")
    }
    guard let up07CapU64 = manifest.get("up07_max_roots_per_quick_check_batch")?.asU64() else {
        throw AirlockError("missing up07 cap")
    }
    let up07Cap = Int(up07CapU64)

    guard let permArr = manifest.get("permitted_axioms")?.asArr() else {
        throw AirlockError("missing permitted_axioms")
    }
    let permittedAxioms = Set(permArr.compactMap { $0.asStr() })

    guard let inputs = manifest.get("input_artifacts"),
          let relInv = inputs.get("inventory")?.asStr(),
          let relTrace = inputs.get("trace")?.asStr(),
          let relDr1 = inputs.get("dryrun_dead_leaves")?.asStr(),
          let relDr2 = inputs.get("dryrun_wrappers")?.asStr(),
          let relZones = inputs.get("transfer_zones")?.asStr(),
          let relUp = inputs.get("upstream_requirements")?.asStr()
    else {
        throw AirlockError("missing input_artifacts paths")
    }

    let invRaw = try String(contentsOf: repoRoot.appendingPathComponent(relInv), encoding: .utf8)
    let traceRaw = try String(contentsOf: repoRoot.appendingPathComponent(relTrace), encoding: .utf8)
    let dr1Raw = try String(contentsOf: repoRoot.appendingPathComponent(relDr1), encoding: .utf8)
    let dr2Raw = try String(contentsOf: repoRoot.appendingPathComponent(relDr2), encoding: .utf8)
    let zonesRaw = try String(contentsOf: repoRoot.appendingPathComponent(relZones), encoding: .utf8)
    let upRaw = try String(contentsOf: repoRoot.appendingPathComponent(relUp), encoding: .utf8)

    var digestChain = ""
    for (label, content) in [
        (manifestRel, manifestRaw),
        (relInv, invRaw),
        (relTrace, traceRaw),
        (relDr1, dr1Raw),
        (relDr2, dr2Raw),
        (relZones, zonesRaw),
        (relUp, upRaw),
    ] {
        digestChain += "\(label):\(airlockSha256Hex(content));"
    }
    let inputDigestsSha256 = airlockSha256Hex(digestChain)

    let inv = try parseAirlockJSON(invRaw)
    let trace = try parseAirlockJSON(traceRaw)
    let dr1 = try parseAirlockJSON(dr1Raw)
    let dr2 = try parseAirlockJSON(dr2Raw)
    let zones = try parseAirlockJSON(zonesRaw)
    let up = try parseAirlockJSON(upRaw)

    var zoneAPaths = Set<String>()
    guard let zonesArr = zones.get("zones")?.asArr() else { throw AirlockError("missing zones") }
    for z in zonesArr {
        if z.get("id")?.asStr() == "Z-A", let ps = z.get("paths")?.asArr() {
            for p in ps {
                if let s = p.asStr() {
                    zoneAPaths.insert(s)
                }
            }
        }
    }
    guard let zAxArr = zones.get("protected_axioms")?.asArr() else { throw AirlockError("missing protected_axioms") }
    let zonesAxioms = Set(zAxArr.compactMap { $0.asStr() })

    let invSha = inv.get("source_repo_commit")?.asStr() ?? ""
    let traceSha = trace.get("source_repo_commit")?.asStr() ?? ""
    let dr1Sha = dr1.get("source_repo_commit")?.asStr() ?? ""
    let dr2Sha = dr2.get("source_repo_commit")?.asStr() ?? ""
    let zonesSha = zones.get("baseline_commit")?.asStr() ?? ""
    let upSha = up.get("verified_against_commit")?.asStr() ?? ""
    let shaAllMatch = invSha == baselineCommit
        && traceSha == baselineCommit
        && dr1Sha == baselineCommit
        && dr2Sha == baselineCommit
        && zonesSha == baselineCommit
        && upSha == baselineCommit

    guard let totals = inv.get("totals"),
          let totFiles = totals.get("files")?.asU64(),
          let totLines = totals.get("lines")?.asU64(),
          let totBytes = totals.get("bytes")?.asU64()
    else {
        throw AirlockError("missing inventory totals")
    }

    guard let invGraph = inv.get("import_graph"),
          let invReach = invGraph.get("reachable_from_main")?.asU64(),
          let deadArr = invGraph.get("unreachable_project_modules")?.asArr()
    else {
        throw AirlockError("missing inventory import_graph")
    }
    let deadModsList = deadArr.compactMap { $0.asStr() }

    guard let trSum = trace.get("graph_summary"),
          let trReach = trSum.get("reachable_modules")?.asU64(),
          let trReachLines = trSum.get("reachable_lines")?.asU64(),
          let trReachBytes = trSum.get("reachable_bytes")?.asU64()
    else {
        throw AirlockError("missing trace graph_summary")
    }
    let isAcyclic = trSum.get("is_acyclic")?.asBool() ?? false

    var rootFiles: UInt64 = 0
    var rootLines: UInt64 = 0
    var rootBytes: UInt64 = 0
    if let libs = inv.get("libraries")?.asArr() {
        for lib in libs where lib.get("name")?.asStr() == "<root>" {
            rootFiles = lib.get("files")?.asU64() ?? 0
            rootLines = lib.get("lines")?.asU64() ?? 0
            rootBytes = lib.get("bytes")?.asU64() ?? 0
        }
    }
    var mainStmtFiles: UInt64 = 0
    var mainStmtLines: UInt64 = 0
    var mainStmtBytes: UInt64 = 0
    if let spine = trace.get("root_spine_depth_le_2")?.asArr() {
        for node in spine {
            let mname = node.get("module")?.asStr() ?? ""
            if mname == "Main" || mname == "Statements" {
                mainStmtFiles += 1
            }
        }
    }
    var lineageTargetsVerified = 0
    if let lin = trace.get("lineage_reachability_audit")?.asArr() {
        for item in lin {
            if item.get("verified_reachable")?.asBool() == true {
                lineageTargetsVerified += 1
            }
            let pref = item.get("module_prefix")?.asStr() ?? ""
            if pref == "Main" || pref == "Statements" {
                mainStmtLines += item.get("reachable_lines")?.asU64() ?? 0
                mainStmtBytes += item.get("reachable_bytes")?.asU64() ?? 0
            }
        }
    }

    let challengeFiles = rootFiles >= mainStmtFiles ? rootFiles - mainStmtFiles : 0
    let challengeLines = rootLines >= mainStmtLines ? rootLines - mainStmtLines : 0
    let challengeBytes = rootBytes >= mainStmtBytes ? rootBytes - mainStmtBytes : 0

    guard let dr1Sum = dr1.get("summary"),
          let dr1DeadCount = dr1Sum.get("dead_modules_count")?.asU64(),
          let dr1DeadLines = dr1Sum.get("reclaimable_lines")?.asU64(),
          let dr1DeadBytes = dr1Sum.get("reclaimable_bytes")?.asU64()
    else {
        throw AirlockError("missing dr1 summary")
    }
    let dr1ImpByReach = dr1Sum.get("imported_by_any_reachable_module")?.asU64() ?? 1
    let dr1LakefileEdit = dr1Sum.get("upstream_lakefile_edit_required")?.asBool() ?? true

    let ag2ConservationExact = shaAllMatch
        && isAcyclic
        && invReach == trReach
        && UInt64(deadModsList.count) == dr1DeadCount
        && dr1ImpByReach == 0
        && challengeFiles == 1
        && (trReach + dr1DeadCount + challengeFiles == totFiles)
        && (trReachLines + dr1DeadLines + challengeLines == totLines)
        && (trReachBytes + dr1DeadBytes + challengeBytes == totBytes)
        && lineageTargetsVerified == 15

    guard let dr2Qual = dr2.get("treatment_dryrun_qualification"),
          let expectedPureWrappersU64 = dr2Qual.get("single_declaration_pure_wrappers")?.asU64(),
          let expectedMultiDeclU64 = dr2Qual.get("multi_declaration_proof_files_excluded_by_guard")?.asU64(),
          let pureBaseLines = dr2Qual.get("pure_wrapper_baseline_lines")?.asU64(),
          let pureBaseBytes = dr2Qual.get("pure_wrapper_baseline_bytes")?.asU64(),
          let expectedSaCountU64 = dr2Qual.get("strategy_a_eligible_units")?.asU64(),
          let expectedSaLines = dr2Qual.get("strategy_a_inplace_alias_saved_lines")?.asU64(),
          let expectedSaBytes = dr2Qual.get("strategy_a_inplace_alias_saved_bytes")?.asU64(),
          let expectedSbCountU64 = dr2Qual.get("strategy_b_collapse_eligible_units")?.asU64(),
          let expectedSbLines = dr2Qual.get("strategy_b_collapse_saved_lines")?.asU64(),
          let expectedSbBytes = dr2Qual.get("strategy_b_collapse_saved_bytes")?.asU64(),
          let unitDiags = dr2.get("unit_diagnostics")?.asArr()
    else {
        throw AirlockError("missing dr2 qualification fields")
    }

    let expectedPureWrappers = Int(expectedPureWrappersU64)
    let expectedMultiDecl = Int(expectedMultiDeclU64)
    let expectedSaCount = Int(expectedSaCountU64)
    let expectedSbCount = Int(expectedSbCountU64)

    var trtSingleDecl = 0
    var trtMultiDecl = 0
    var trtMultiDeclLeaked = 0
    var anyTouchesCore = false
    var saModules: [String] = []
    var sbModules: [String] = []
    var saLinesSum: UInt64 = 0
    var sbLinesSum: UInt64 = 0
    var saPureSavings: [UInt64] = []
    var sbPureSavings: [UInt64] = []
    var allTouchedPaths = deadModsList.map(moduleToRelPath)

    for u in unitDiags {
        let arm = u.get("arm")?.asStr() ?? ""
        let mname = u.get("module")?.asStr() ?? ""
        let declCount = u.get("decl_count")?.asU64() ?? 0
        let pairedImpl = u.get("paired_impl_exists")?.asBool() ?? false
        let subsetImp = u.get("imports_subset_of_impl")?.asBool() ?? false
        let touchesCore = u.get("touches_core")?.asBool() ?? true
        let saElig = u.get("strategy_a_eligible")?.asBool() ?? false
        let saSaved = u.get("strategy_a_saved_lines")?.asU64() ?? 0
        let sbElig = u.get("strategy_b_eligible")?.asBool() ?? false
        let sbSaved = u.get("strategy_b_saved_lines")?.asU64() ?? 0

        if touchesCore {
            anyTouchesCore = true
        }
        if arm == "treatment" {
            allTouchedPaths.append(moduleToRelPath(mname))
            if declCount == 1 {
                trtSingleDecl += 1
                saPureSavings.append(saElig ? saSaved : 0)
                sbPureSavings.append(sbElig ? sbSaved : 0)
            } else {
                trtMultiDecl += 1
                if saElig || sbElig {
                    trtMultiDeclLeaked += 1
                }
            }
            if saElig {
                saModules.append(mname)
                saLinesSum += saSaved
            }
            if sbElig {
                if !strategyBSafeGuard(
                    declCount: declCount,
                    pairedImplExists: pairedImpl,
                    importsSubsetOfImpl: subsetImp,
                    touchesCore: touchesCore
                ) {
                    trtMultiDeclLeaked += 1
                }
                sbModules.append(mname)
                sbLinesSum += sbSaved
            }
        }
    }

    let ag1ZoneAClean = !targetRepoMutationAllowed
        && zoneAPaths.count == 8
        && !anyTouchesCore
        && !dr1LakefileEdit
        && !touchesZoneA(allTouchedPaths, zoneA: zoneAPaths)

    let z0Batches = splitUp07Batches(deadModsList, cap: up07Cap)
    let z1aBatches = splitUp07Batches(saModules, cap: up07Cap)
    let z1bBatches = splitUp07Batches(sbModules, cap: up07Cap)

    let z0Before = MassVector(files: totFiles, lines: totLines, bytes: totBytes)
    let z0After = MassVector(
        files: totFiles - dr1DeadCount,
        lines: totLines - dr1DeadLines,
        bytes: totBytes - dr1DeadBytes
    )
    let z1aBefore = MassVector(files: UInt64(expectedPureWrappers), lines: pureBaseLines, bytes: pureBaseBytes)
    let z1aAfter = MassVector(
        files: UInt64(expectedPureWrappers),
        lines: pureBaseLines - expectedSaLines,
        bytes: pureBaseBytes - expectedSaBytes
    )
    let z1bBefore = z1aBefore
    let z1bAfter = MassVector(
        files: UInt64(expectedPureWrappers - expectedSbCount),
        lines: pureBaseLines - expectedSbLines,
        bytes: pureBaseBytes - expectedSbBytes
    )

    let packages = [
        PackageQualification(
            packageId: "PKG-R3-Z0-DEAD-LEAVES",
            zoneId: "Z-C0",
            eligibleModules: deadModsList.count,
            batchCount: z0Batches.count,
            maxBatchSize: z0Batches.map(\.count).max() ?? 0,
            before: z0Before,
            after: z0After,
            rhoFilesPpm: MassVector.rhoPpm(before: z0Before.files, after: z0After.files),
            rhoLinesPpm: MassVector.rhoPpm(before: z0Before.lines, after: z0After.lines),
            rhoBytesPpm: MassVector.rhoPpm(before: z0Before.bytes, after: z0After.bytes),
            paretoStrict: z0Before.isParetoReduction(z0After),
            batchScheduleSha256: hashBatchSchedule(packageId: "PKG-R3-Z0-DEAD-LEAVES", batches: z0Batches)
        ),
        PackageQualification(
            packageId: "PKG-R3-Z1A-ALIAS-INPLACE",
            zoneId: "Z-C1",
            eligibleModules: saModules.count,
            batchCount: z1aBatches.count,
            maxBatchSize: z1aBatches.map(\.count).max() ?? 0,
            before: z1aBefore,
            after: z1aAfter,
            rhoFilesPpm: MassVector.rhoPpm(before: z1aBefore.files, after: z1aAfter.files),
            rhoLinesPpm: MassVector.rhoPpm(before: z1aBefore.lines, after: z1aAfter.lines),
            rhoBytesPpm: MassVector.rhoPpm(before: z1aBefore.bytes, after: z1aAfter.bytes),
            paretoStrict: z1aBefore.isParetoReduction(z1aAfter),
            batchScheduleSha256: hashBatchSchedule(packageId: "PKG-R3-Z1A-ALIAS-INPLACE", batches: z1aBatches)
        ),
        PackageQualification(
            packageId: "PKG-R3-Z1B-WRAPPER-COLLAPSE",
            zoneId: "Z-C1",
            eligibleModules: sbModules.count,
            batchCount: z1bBatches.count,
            maxBatchSize: z1bBatches.map(\.count).max() ?? 0,
            before: z1bBefore,
            after: z1bAfter,
            rhoFilesPpm: MassVector.rhoPpm(before: z1bBefore.files, after: z1bAfter.files),
            rhoLinesPpm: MassVector.rhoPpm(before: z1bBefore.lines, after: z1bAfter.lines),
            rhoBytesPpm: MassVector.rhoPpm(before: z1bBefore.bytes, after: z1bAfter.bytes),
            paretoStrict: z1bBefore.isParetoReduction(z1bAfter),
            batchScheduleSha256: hashBatchSchedule(packageId: "PKG-R3-Z1B-WRAPPER-COLLAPSE", batches: z1bBatches)
        ),
    ]

    let strategyAA12Bps = varghaDelaneyA12BpsVsZeroControl(saPureSavings)
    let strategyBA12Bps = varghaDelaneyA12BpsVsZeroControl(sbPureSavings)

    let ag3ParetoAndRctPassed = trtSingleDecl == expectedPureWrappers
        && trtMultiDecl == expectedMultiDecl
        && trtMultiDeclLeaked == 0
        && saModules.count == expectedSaCount
        && saLinesSum == expectedSaLines
        && sbModules.count == expectedSbCount
        && sbLinesSum == expectedSbLines
        && packages.allSatisfy(\.paretoStrict)
        && strategyAA12Bps >= 9000
        && strategyBA12Bps >= 7500

    let ag4Up07BatchesAndAxiomsClean = up07Cap == 8
        && verifyUp07Batches(deadModsList, batches: z0Batches, cap: up07Cap)
        && verifyUp07Batches(saModules, batches: z1aBatches, cap: up07Cap)
        && verifyUp07Batches(sbModules, batches: z1bBatches, cap: up07Cap)
        && permittedAxioms == zonesAxioms
        && permittedAxioms.count == 3
        && checkUp08CleanRoomLeanDir(repoRoot)

    let ag5SyntheticTransformsPassed = verifySyntheticCleanRoomTransforms()

    var negRejected = 0
    if touchesZoneA(["src/Main.lean", "lakefile.toml"], zoneA: zoneAPaths) {
        negRejected += 1
    }
    if "0000000000000000000000000000000000000000" != baselineCommit {
        negRejected += 1
    }
    if !strategyBSafeGuard(declCount: 2, pairedImplExists: true, importsSubsetOfImpl: true, touchesCore: false) {
        negRejected += 1
    }
    if !strategyBSafeGuard(declCount: 1, pairedImplExists: true, importsSubsetOfImpl: false, touchesCore: false) {
        negRejected += 1
    }
    let oversized = (0..<9).map { "Mod\($0)" }
    if !verifyUp07Batches(oversized, batches: [oversized], cap: up07Cap) {
        negRejected += 1
    }
    if !axiomsPermitted(["propext", "CustomUnsoundAxiom"], permitted: permittedAxioms) {
        negRejected += 1
    }
    let inflated = MassVector(files: 51, lines: 1005, bytes: 96575)
    if !z1aBefore.isParetoReduction(inflated) {
        negRejected += 1
    }

    let totalNegativeControls = 7
    let allPassed = ag1ZoneAClean
        && ag2ConservationExact
        && ag3ParetoAndRctPassed
        && ag4Up07BatchesAndAxiomsClean
        && ag5SyntheticTransformsPassed
        && negRejected == totalNegativeControls

    var digestSrc = "\(inputDigestsSha256)|"
    for p in packages {
        digestSrc += "\(p.packageId):\(p.eligibleModules):\(p.batchCount):\(p.rhoFilesPpm):\(p.rhoLinesPpm):\(p.batchScheduleSha256);"
    }
    digestSrc += "A12:\(strategyAA12Bps):\(strategyBA12Bps);NEG:\(negRejected)/\(totalNegativeControls);PASS:\(allPassed)"
    let airlockDigestSha256 = airlockSha256Hex(digestSrc)

    return Rung3AirlockReceipt(
        icdId: icdId,
        baselineCommit: baselineCommit,
        targetRepoMutationAllowed: targetRepoMutationAllowed,
        ag1ZoneAClean: ag1ZoneAClean,
        ag2ConservationExact: ag2ConservationExact,
        ag3ParetoAndRctPassed: ag3ParetoAndRctPassed,
        ag4Up07BatchesAndAxiomsClean: ag4Up07BatchesAndAxiomsClean,
        ag5SyntheticTransformsPassed: ag5SyntheticTransformsPassed,
        strategyAA12Bps: strategyAA12Bps,
        strategyBA12Bps: strategyBA12Bps,
        multiDeclProtectedCount: trtMultiDecl,
        lineageTargetsVerified: lineageTargetsVerified,
        negativeControlsRejected: negRejected,
        totalNegativeControls: totalNegativeControls,
        packages: packages,
        inputDigestsSha256: inputDigestsSha256,
        airlockDigestSha256: airlockDigestSha256,
        allPassed: allPassed
    )
}
