// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone Rung 2 Shared Ground Codec, QuickCheck Property Generator,
// Deterministic Counterexample Shrinker, Metamorphic Invariance Suite, and
// Differential Parity Harness (pure Swift 6, zero external dependencies).

import Foundation

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256 & Deterministic SplitMix64 PRNG
// =============================================================================

private let sha256K: [UInt32] = [
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

public func groundSha256Hex(_ data: [UInt8]) -> String {
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
            let t1 = hh &+ s1 &+ ch &+ sha256K[i] &+ w[i]
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

public func groundSha256Hex(_ text: String) -> String {
    groundSha256Hex(Array(text.utf8))
}

public struct GroundSplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func nextU64() -> UInt64 {
        state = state &+ 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }

    public mutating func nextUsize(_ upperExclusive: Int) -> Int {
        if upperExclusive <= 0 {
            return 0
        }
        return Int(nextU64() % UInt64(upperExclusive))
    }
}

// =============================================================================
// 2. Shared Ground Codec: GroundModule, GroundGraph, WrapperKind
// =============================================================================

public enum WrapperKind: String, Sendable, Equatable {
    case pureWrapper = "pure_wrapper"
    case reexportHub = "reexport_hub"
    case substantive = "substantive"
}

private func splitLinesLikeRust(_ source: String) -> [String] {
    var lines: [String] = []
    var current = ""
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let ch = chars[i]
        if ch == "\n" {
            lines.append(current)
            current = ""
            i += 1
        } else if ch == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" {
            lines.append(current)
            current = ""
            i += 2
        } else {
            current.append(ch)
            i += 1
        }
    }
    if !current.isEmpty {
        lines.append(current)
    }
    return lines
}

private func trimASCIIWhitespace(_ s: String) -> String {
    var start = s.startIndex
    var end = s.endIndex
    while start < end && (s[start] == " " || s[start] == "\t" || s[start] == "\r" || s[start] == "\n") {
        start = s.index(after: start)
    }
    while end > start {
        let prev = s.index(before: end)
        if s[prev] == " " || s[prev] == "\t" || s[prev] == "\r" || s[prev] == "\n" {
            end = prev
        } else {
            break
        }
    }
    return String(s[start..<end])
}

/// Classifies Lean 4 module text ignoring `--` line comments, `/- ... -/` block comments, and blank lines.
public func classifyWrapperText(_ source: String) -> WrapperKind {
    var inBlock = false
    var impCount = 0
    var pubCount = 0
    var hasDecl = false

    for rawLine in splitLinesLikeRust(source) {
        let t = trimASCIIWhitespace(rawLine)
        if t.hasPrefix("/-") {
            if !t.contains("-/") {
                inBlock = true
            }
            continue
        }
        if inBlock {
            if t.contains("-/") {
                inBlock = false
            }
            continue
        }
        if t.isEmpty || t.hasPrefix("--") || t == "module" {
            continue
        }
        if t.hasPrefix("theorem ")
            || t.hasPrefix("lemma ")
            || t.hasPrefix("def ")
            || t.hasPrefix("structure ")
            || t.hasPrefix("inductive ")
            || t.hasPrefix("class ")
            || t.hasPrefix("instance ")
            || t.hasPrefix("abbrev ")
            || t.hasPrefix("private theorem ")
            || t.hasPrefix("private def ")
        {
            hasDecl = true
        }
        if t.hasPrefix("public import ") {
            pubCount += 1
            impCount += 1
        } else if t.hasPrefix("import ")
            || t.hasPrefix("private import ")
            || t.hasPrefix("meta import ")
        {
            impCount += 1
        }
    }

    if hasDecl {
        return .substantive
    } else if pubCount >= 2 {
        return .reexportHub
    } else if impCount >= 1 {
        return .pureWrapper
    } else {
        return .substantive
    }
}

public struct GroundCodecError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) {
        self.message = message
    }
}

public struct GroundModule: Sendable, Equatable {
    public var name: String
    public var lines: UInt64
    public var bytes: UInt64
    public var imports: [String]
    public var wrapperKind: WrapperKind

    public init(name: String, lines: UInt64, bytes: UInt64, imports: [String], wrapperKind: WrapperKind) {
        self.name = name
        self.lines = lines
        self.bytes = bytes
        self.imports = imports
        self.wrapperKind = wrapperKind
    }
}

public struct GroundMassAccounting: Sendable, Equatable {
    public let reachableLines: UInt64
    public let deadLines: UInt64
    public let totalLines: UInt64
    public let reachableBytes: UInt64
    public let deadBytes: UInt64
    public let totalBytes: UInt64
}

private func utf8Less(_ a: String, _ b: String) -> Bool {
    a.utf8.lexicographicallyPrecedes(b.utf8)
}

private func appendJsonString(_ s: String, to out: inout String) {
    out.append("\"")
    for ch in s {
        switch ch {
        case "\"": out.append("\\\"")
        case "\\": out.append("\\\\")
        case "\n": out.append("\\n")
        default: out.append(ch)
        }
    }
    out.append("\"")
}

public struct GroundGraph: Sendable, Equatable {
    public var root: String
    public var modules: [GroundModule]

    public init(root: String, modules: [GroundModule]) {
        self.root = root
        self.modules = modules
    }

    /// Returns a canonicalized copy (modules sorted by name, imports sorted & deduplicated).
    public func canonicalized() -> GroundGraph {
        var mods = modules
        for i in mods.indices {
            let uniq = Set(mods[i].imports)
            mods[i].imports = uniq.sorted(by: utf8Less)
        }
        mods.sort { utf8Less($0.name, $1.name) }
        return GroundGraph(root: root, modules: mods)
    }

    /// Deterministic sorted-key canonical JSON encoding.
    public func toCanonicalJSON() -> String {
        let c = canonicalized()
        var out = "{\"modules\":["
        for (i, m) in c.modules.enumerated() {
            if i > 0 {
                out.append(",")
            }
            out.append("{\"bytes\":\(m.bytes),\"imports\":[")
            for (j, imp) in m.imports.enumerated() {
                if j > 0 {
                    out.append(",")
                }
                appendJsonString(imp, to: &out)
            }
            out.append("],\"lines\":\(m.lines),\"name\":")
            appendJsonString(m.name, to: &out)
            out.append(",\"wrapper_kind\":")
            appendJsonString(m.wrapperKind.rawValue, to: &out)
            out.append("}")
        }
        out.append("],\"root\":")
        appendJsonString(c.root, to: &out)
        out.append("}")
        return out
    }

    public func validate() throws {
        if root.isEmpty {
            throw GroundCodecError("empty root module")
        }
        var names = Set<String>()
        for m in modules {
            if m.name.isEmpty {
                throw GroundCodecError("empty module name")
            }
            if !names.insert(m.name).inserted {
                throw GroundCodecError("duplicate module '\(m.name)'")
            }
        }
        if !names.contains(root) {
            throw GroundCodecError("missing root '\(root)'")
        }
        for m in modules {
            for imp in m.imports {
                if !names.contains(imp) {
                    throw GroundCodecError("dangling import '\(imp)' in '\(m.name)'")
                }
            }
        }
    }

    public func isValid() -> Bool {
        do {
            try validate()
            return true
        } catch {
            return false
        }
    }

    public func reachableFromRoot() -> Set<String> {
        var adj: [String: [String]] = [:]
        adj.reserveCapacity(modules.count)
        for m in modules {
            adj[m.name] = m.imports
        }
        var visited = Set<String>()
        guard adj[root] != nil else {
            return visited
        }
        var queue: [String] = [root]
        var head = 0
        visited.insert(root)
        while head < queue.count {
            let u = queue[head]
            head += 1
            if let nbrs = adj[u] {
                for v in nbrs {
                    if adj[v] != nil && visited.insert(v).inserted {
                        queue.append(v)
                    }
                }
            }
        }
        return visited
    }

    public func deadLeaves() -> Set<String> {
        let reach = reachableFromRoot()
        var dead = Set<String>()
        for m in modules where !reach.contains(m.name) {
            dead.insert(m.name)
        }
        return dead
    }

    /// Exact Kahn topological peel: returns true iff the graph contains at least one directed cycle.
    public func hasCycle() -> Bool {
        var indeg: [String: Int] = [:]
        var revAdj: [String: [String]] = [:]
        indeg.reserveCapacity(modules.count)
        for m in modules {
            let uniq = Set(m.imports)
            indeg[m.name] = uniq.count
            for imp in uniq {
                revAdj[imp, default: []].append(m.name)
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
            if let dependents = revAdj[u] {
                for dep in dependents {
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

    /// Exact order-independent iterative fixed-point dominator sets on all nodes reachable from `root`.
    public func computeDominators() -> [String: Set<String>] {
        let reach = reachableFromRoot()
        let sortedReach = reach.sorted(by: utf8Less)
        var preds: [String: Set<String>] = [:]
        for n in sortedReach {
            preds[n] = []
        }
        for m in modules where reach.contains(m.name) {
            for imp in m.imports where reach.contains(imp) {
                preds[imp, default: []].insert(m.name)
            }
        }

        var dom: [String: Set<String>] = [:]
        for n in sortedReach {
            if n == root {
                dom[n] = [n]
            } else {
                dom[n] = reach
            }
        }

        var changed = true
        while changed {
            changed = false
            for n in sortedReach {
                if n == root {
                    continue
                }
                let ps = preds[n] ?? []
                var inter: Set<String>? = nil
                for p in ps {
                    let dp = dom[p] ?? []
                    if let acc = inter {
                        inter = acc.intersection(dp)
                    } else {
                        inter = dp
                    }
                }
                var newSet = inter ?? []
                newSet.insert(n)
                if dom[n] != newSet {
                    dom[n] = newSet
                    changed = true
                }
            }
        }
        return dom
    }

    public func edgeCount() -> Int {
        modules.reduce(0) { $0 + $1.imports.count }
    }

    public func massAccounting() -> GroundMassAccounting {
        let reach = reachableFromRoot()
        var rl: UInt64 = 0
        var dl: UInt64 = 0
        var rb: UInt64 = 0
        var db: UInt64 = 0
        for m in modules {
            if reach.contains(m.name) {
                rl += m.lines
                rb += m.bytes
            } else {
                dl += m.lines
                db += m.bytes
            }
        }
        return GroundMassAccounting(
            reachableLines: rl,
            deadLines: dl,
            totalLines: rl + dl,
            reachableBytes: rb,
            deadBytes: db,
            totalBytes: rb + db
        )
    }
}

// =============================================================================
// Strict Canonical JSON Decoder (fail-closed)
// =============================================================================

private enum JVal {
    case str(String)
    case num(UInt64)
    case arr([JVal])
    case obj([String: JVal])

    func asStr() -> String? {
        if case .str(let s) = self { return s }
        return nil
    }
    func asU64() -> UInt64? {
        if case .num(let n) = self { return n }
        return nil
    }
    func asArr() -> [JVal]? {
        if case .arr(let a) = self { return a }
        return nil
    }
    func get(_ k: String) -> JVal? {
        if case .obj(let m) = self { return m[k] }
        return nil
    }
}

private struct MiniParser {
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

    mutating func parseVal() throws -> JVal {
        skipWs()
        guard let b = peek() else {
            throw GroundCodecError("unexpected end of JSON at \(pos)")
        }
        if b == 0x22 {
            return .str(try parseStr())
        } else if b == 0x5b {
            return try parseArr()
        } else if b == 0x7b {
            return try parseObj()
        } else if b >= 0x30 && b <= 0x39 {
            return .num(try parseU64())
        } else {
            throw GroundCodecError("unexpected JSON token at \(pos)")
        }
    }

    mutating func parseStr() throws -> String {
        guard peek() == 0x22 else {
            throw GroundCodecError("expected quote")
        }
        pos += 1
        var outBytes: [UInt8] = []
        while pos < bytes.count {
            let b = bytes[pos]
            pos += 1
            if b == 0x22 {
                guard let s = String(bytes: outBytes, encoding: .utf8) else {
                    throw GroundCodecError("invalid UTF-8 string")
                }
                return s
            }
            if b == 0x5c {
                guard pos < bytes.count else {
                    throw GroundCodecError("truncated escape")
                }
                let e = bytes[pos]
                pos += 1
                switch e {
                case 0x22: outBytes.append(0x22)
                case 0x5c: outBytes.append(0x5c)
                case 0x6e: outBytes.append(0x0a)
                default: throw GroundCodecError("unsupported escape")
                }
            } else {
                outBytes.append(b)
            }
        }
        throw GroundCodecError("unterminated JSON string")
    }

    mutating func parseU64() throws -> UInt64 {
        let start = pos
        while let b = peek(), b >= 0x30 && b <= 0x39 {
            pos += 1
        }
        guard let raw = String(bytes: bytes[start..<pos], encoding: .utf8),
              let v = UInt64(raw)
        else {
            throw GroundCodecError("bad integer")
        }
        return v
    }

    mutating func parseArr() throws -> JVal {
        pos += 1
        skipWs()
        var items: [JVal] = []
        if peek() == 0x5d {
            pos += 1
            return .arr(items)
        }
        while true {
            items.append(try parseVal())
            skipWs()
            switch peek() {
            case 0x2c:
                pos += 1
            case 0x5d:
                pos += 1
                return .arr(items)
            default:
                throw GroundCodecError("expected ',' or ']'")
            }
        }
    }

    mutating func parseObj() throws -> JVal {
        pos += 1
        skipWs()
        var map: [String: JVal] = [:]
        if peek() == 0x7d {
            pos += 1
            return .obj(map)
        }
        while true {
            skipWs()
            let k = try parseStr()
            skipWs()
            guard peek() == 0x3a else {
                throw GroundCodecError("expected ':'")
            }
            pos += 1
            let v = try parseVal()
            map[k] = v
            skipWs()
            switch peek() {
            case 0x2c:
                pos += 1
            case 0x7d:
                pos += 1
                return .obj(map)
            default:
                throw GroundCodecError("expected ',' or '}'")
            }
        }
    }
}

public func decodeGroundGraphJSON(_ input: String) throws -> GroundGraph {
    var parser = MiniParser(bytes: Array(input.utf8))
    let val = try parser.parseVal()
    parser.skipWs()
    if parser.pos != parser.bytes.count {
        throw GroundCodecError("trailing bytes in JSON")
    }
    guard let root = val.get("root")?.asStr() else {
        throw GroundCodecError("missing root string")
    }
    guard let arr = val.get("modules")?.asArr() else {
        throw GroundCodecError("missing modules array")
    }
    var modules: [GroundModule] = []
    modules.reserveCapacity(arr.count)
    for item in arr {
        guard let name = item.get("name")?.asStr() else {
            throw GroundCodecError("missing name")
        }
        guard let lines = item.get("lines")?.asU64() else {
            throw GroundCodecError("missing lines")
        }
        guard let bytesLen = item.get("bytes")?.asU64() else {
            throw GroundCodecError("missing bytes")
        }
        guard let impArr = item.get("imports")?.asArr() else {
            throw GroundCodecError("missing imports")
        }
        var imports: [String] = []
        imports.reserveCapacity(impArr.count)
        for iv in impArr {
            guard let s = iv.asStr() else {
                throw GroundCodecError("import not string")
            }
            imports.append(s)
        }
        guard let wkRaw = item.get("wrapper_kind")?.asStr(),
              let wk = WrapperKind(rawValue: wkRaw)
        else {
            throw GroundCodecError("invalid wrapper_kind")
        }
        modules.append(GroundModule(name: name, lines: lines, bytes: bytesLen, imports: imports, wrapperKind: wk))
    }
    let g = GroundGraph(root: root, modules: modules)
    try g.validate()
    return g
}

// =============================================================================
// 3. Deterministic Counterexample Shrinker (QuickCheck Style, METH-20)
// =============================================================================

/// Deterministically shrinks a cyclic graph to a 1-edge-minimal cycle core.
public func shrinkCyclicGraph(_ g: GroundGraph) -> GroundGraph {
    var cur = g.canonicalized()
    if !cur.hasCycle() {
        return cur
    }
    var improved = true
    while improved {
        improved = false
        outer: for mi in 0..<cur.modules.count {
            for ei in 0..<cur.modules[mi].imports.count {
                var cand = cur
                cand.modules[mi].imports.remove(at: ei)
                if cand.hasCycle() {
                    cur = cand
                    improved = true
                    break outer
                }
            }
        }
    }
    return cur
}

public func isEdgeMinimalCycle(_ g: GroundGraph) -> Bool {
    if !g.hasCycle() {
        return false
    }
    for mi in 0..<g.modules.count {
        for ei in 0..<g.modules[mi].imports.count {
            var cand = g
            cand.modules[mi].imports.remove(at: ei)
            if cand.hasCycle() {
                return false
            }
        }
    }
    return true
}

// =============================================================================
// 4. Seeded Generative Corpus + Metamorphic Suite + Differential Parity Receipt
// =============================================================================

public struct Rung2ParityReceipt: Sendable, Equatable {
    public let masterSeed: UInt64
    public let casesPerFamily: Int
    public let totalCases: Int
    public let dagCleanPassed: Int
    public let cycleShrunkMinimal: Int
    public let diamondDomPassed: Int
    public let deadLeavesPassed: Int
    public let wrapperAstPassed: Int
    public let metamorphicPairsPassed: Int
    public let malformedRejected: Int
    public let corpusDigestSha256: String
    public let allPassed: Bool

    public func toCanonicalJSON() -> String {
        "{\"all_passed\":\(allPassed),\"cases_per_family\":\(casesPerFamily),\"corpus_digest_sha256\":\"\(corpusDigestSha256)\",\"cycle_shrunk_minimal\":\(cycleShrunkMinimal),\"dag_clean_passed\":\(dagCleanPassed),\"dead_leaves_passed\":\(deadLeavesPassed),\"diamond_dom_passed\":\(diamondDomPassed),\"malformed_rejected\":\(malformedRejected),\"master_seed\":\(masterSeed),\"metamorphic_pairs_passed\":\(metamorphicPairsPassed),\"total_cases\":\(totalCases),\"wrapper_ast_passed\":\(wrapperAstPassed)}"
    }
}

private func genDag(_ rng: inout GroundSplitMix64, n: Int, extraDead: Int) -> GroundGraph {
    var mods: [GroundModule] = []
    mods.reserveCapacity(n + extraDead)
    for i in 0..<n {
        var imps: [String] = []
        if i + 1 < n {
            let nextIdx = i + 1 + rng.nextUsize(n - i - 1)
            imps.append("M\(nextIdx)")
            for j in (i + 1)..<n {
                if j != nextIdx && (rng.nextU64() % 3) == 0 {
                    imps.append("M\(j)")
                }
            }
        }
        let lines = 5 + (rng.nextU64() % 95)
        let bytes = lines * (20 + (rng.nextU64() % 30))
        mods.append(GroundModule(name: "M\(i)", lines: lines, bytes: bytes, imports: imps, wrapperKind: .substantive))
    }
    for d in 0..<extraDead {
        var imps: [String] = []
        if n > 0 && (rng.nextU64() % 2) == 0 {
            imps.append("M\(rng.nextUsize(n))")
        }
        let lines = 10 + (rng.nextU64() % 40)
        let bytes = lines * 25
        mods.append(GroundModule(name: "Dead\(d)", lines: lines, bytes: bytes, imports: imps, wrapperKind: .pureWrapper))
    }
    return GroundGraph(root: "M0", modules: mods)
}

private func verifyDominatorCutProperty(_ g: GroundGraph, dom: [String: Set<String>]) -> Bool {
    let reach = g.reachableFromRoot()
    if dom.count != reach.count {
        return false
    }
    for v in reach {
        guard let ds = dom[v] else {
            return false
        }
        if !ds.contains(v) || !ds.contains(g.root) {
            return false
        }
        for d in ds {
            if d == v || d == g.root {
                continue
            }
            let filtered = GroundGraph(
                root: g.root,
                modules: g.modules
                    .filter { $0.name != d }
                    .map { m in
                        GroundModule(
                            name: m.name,
                            lines: m.lines,
                            bytes: m.bytes,
                            imports: m.imports.filter { $0 != d },
                            wrapperKind: m.wrapperKind
                        )
                    }
            )
            if filtered.reachableFromRoot().contains(v) {
                return false
            }
        }
    }
    return true
}

public func runRung2ParitySuite(masterSeed: UInt64, casesPerFamily: Int) -> Rung2ParityReceipt {
    var rng = GroundSplitMix64(seed: masterSeed)
    var trace = ""

    var dagCleanPassed = 0
    var cycleShrunkMinimal = 0
    var diamondDomPassed = 0
    var deadLeavesPassed = 0
    var wrapperAstPassed = 0
    var metamorphicPairsPassed = 0

    // 1. FAM-DAG-CLEAN
    for c in 0..<casesPerFamily {
        let n = 4 + rng.nextUsize(10)
        let g = genDag(&rng, n: n, extraDead: 0)
        let enc = g.toCanonicalJSON()
        var rtOk = false
        do {
            let dec = try decodeGroundGraphJSON(enc)
            rtOk = (dec.toCanonicalJSON() == enc)
        } catch {
            rtOk = false
        }
        let reach = g.reachableFromRoot()
        let dead = g.deadLeaves()
        let mass = g.massAccounting()
        let ok = g.isValid()
            && !g.hasCycle()
            && rtOk
            && reach.isDisjoint(with: dead)
            && (reach.count + dead.count == g.modules.count)
            && (mass.reachableLines + mass.deadLines == mass.totalLines)
            && (mass.reachableBytes + mass.deadBytes == mass.totalBytes)
        if ok {
            dagCleanPassed += 1
        }
        trace += "D:\(c):\(reach.count):\(dead.count):\(mass.totalLines);"
    }

    // 2. FAM-CYCLE-INJECTED + QuickCheck Deterministic Shrinking
    for c in 0..<casesPerFamily {
        let n = 4 + rng.nextUsize(8)
        var raw = genDag(&rng, n: n, extraDead: 0)
        for i in 0..<(n - 1) {
            raw.modules[i].imports.append("M\(i + 1)")
        }
        let a = rng.nextUsize(n - 1)
        let b = a + 1 + rng.nextUsize(n - 1 - a)
        raw.modules[b].imports.append("M\(a)")
        let g = raw.canonicalized()
        let origEdges = g.edgeCount()
        let shrunk = shrinkCyclicGraph(g)
        let ok = g.isValid()
            && g.hasCycle()
            && shrunk.edgeCount() <= origEdges
            && isEdgeMinimalCycle(shrunk)
        if ok {
            cycleShrunkMinimal += 1
        }
        trace += "C:\(c):\(origEdges):\(shrunk.edgeCount());"
    }

    // 3. FAM-DIAMOND-DOM (Exact Fixed-Point Dominators + Cut Oracle)
    for c in 0..<casesPerFamily {
        let n = 5 + rng.nextUsize(7)
        let g = genDag(&rng, n: n, extraDead: 0).canonicalized()
        let dom = g.computeDominators()
        let ok = g.isValid() && !g.hasCycle() && verifyDominatorCutProperty(g, dom: dom)
        if ok {
            diamondDomPassed += 1
        }
        let domSum = dom.values.reduce(0) { $0 + $1.count }
        trace += "M:\(c):\(dom.count):\(domSum);"
    }

    // 4. FAM-DEAD-LEAVES
    for c in 0..<casesPerFamily {
        let n = 3 + rng.nextUsize(5)
        let extra = 2 + rng.nextUsize(5)
        let g = genDag(&rng, n: n, extraDead: extra).canonicalized()
        let dead = g.deadLeaves()
        let mass = g.massAccounting()
        let ok = g.isValid()
            && !g.hasCycle()
            && dead.count >= extra
            && (mass.reachableLines + mass.deadLines == mass.totalLines)
            && (mass.reachableBytes + mass.deadBytes == mass.totalBytes)
        if ok {
            deadLeavesPassed += 1
        }
        trace += "L:\(c):\(dead.count):\(mass.deadLines):\(mass.deadBytes);"
    }

    // 5. FAM-WRAPPER-AST + MR-2 Comment/Blank-Line Invariance
    for c in 0..<casesPerFamily {
        let kindSel = rng.nextUsize(3)
        let src: String
        let expected: WrapperKind
        switch kindSel {
        case 0:
            src = "module\nimport Base.Core\nexport Base.Core (foo)\n"
            expected = .pureWrapper
        case 1:
            src = "public import A.One\npublic import B.Two\n"
            expected = .reexportHub
        default:
            src = "import Base.Core\ntheorem sample_id (x : Nat) : x = x := rfl\n"
            expected = .substantive
        }
        let perturbed = "-- generated header \(c)\n\n/- block comment -/\n\(src)\n-- footer\n\n"
        let k1 = classifyWrapperText(src)
        let k2 = classifyWrapperText(perturbed)
        if k1 == expected && k2 == expected {
            wrapperAstPassed += 1
        }
        trace += "W:\(c):\(k1.rawValue);"
    }

    // 6. FAM-METAMORPHIC-INV (MR-1 permutation, MR-2 comments, MR-3 bijective non-root rename)
    for c in 0..<casesPerFamily {
        let n = 4 + rng.nextUsize(6)
        let extra = 1 + rng.nextUsize(3)
        let g = genDag(&rng, n: n, extraDead: extra)
        let baseCycle = g.hasCycle()
        let baseReach = g.reachableFromRoot().count
        let baseDead = g.deadLeaves().count
        let baseMass = g.massAccounting()
        let baseDomSizes = g.computeDominators().values.map(\.count).sorted()

        // MR-1: Reverse module order and import order.
        var mr1Mods = Array(g.modules.reversed())
        for i in mr1Mods.indices {
            mr1Mods[i].imports.reverse()
        }
        let gMr1 = GroundGraph(root: g.root, modules: mr1Mods)
        let mr1DomSizes = gMr1.computeDominators().values.map(\.count).sorted()
        if gMr1.hasCycle() == baseCycle
            && gMr1.reachableFromRoot().count == baseReach
            && gMr1.deadLeaves().count == baseDead
            && gMr1.massAccounting() == baseMass
            && mr1DomSizes == baseDomSizes
            && gMr1.toCanonicalJSON() == g.toCanonicalJSON()
        {
            metamorphicPairsPassed += 1
        }

        // MR-2: Comment/blank injection on wrapper text.
        let wBase = "import Core.A\nexport Core.A (x)\n"
        let wPert = "\n-- mr2 \(c)\n\(wBase)\n\n-- end\n"
        if classifyWrapperText(wBase) == classifyWrapperText(wPert) {
            metamorphicPairsPassed += 1
        }

        // MR-3: Bijective rename of every non-root module (`X -> Ren_X`).
        func rename(_ s: String) -> String {
            s == g.root ? s : "Ren_\(s)"
        }
        let gMr3 = GroundGraph(
            root: g.root,
            modules: g.modules.map { m in
                GroundModule(
                    name: rename(m.name),
                    lines: m.lines,
                    bytes: m.bytes,
                    imports: m.imports.map(rename),
                    wrapperKind: m.wrapperKind
                )
            }
        )
        let mr3DomSizes = gMr3.computeDominators().values.map(\.count).sorted()
        if gMr3.hasCycle() == baseCycle
            && gMr3.reachableFromRoot().count == baseReach
            && gMr3.deadLeaves().count == baseDead
            && gMr3.massAccounting() == baseMass
            && mr3DomSizes == baseDomSizes
        {
            metamorphicPairsPassed += 1
        }

        trace += "X:\(c):\(baseReach):\(baseDead):\(baseMass.totalLines);"
    }

    // 7. Malformed Negative Controls (4 must all fail closed!)
    var malformedRejected = 0
    let mMissingRoot = GroundGraph(
        root: "Missing",
        modules: [GroundModule(name: "A", lines: 1, bytes: 10, imports: [], wrapperKind: .substantive)]
    )
    if !mMissingRoot.isValid() {
        malformedRejected += 1
    }
    let mDup = GroundGraph(
        root: "A",
        modules: [
            GroundModule(name: "A", lines: 1, bytes: 10, imports: [], wrapperKind: .substantive),
            GroundModule(name: "A", lines: 2, bytes: 20, imports: [], wrapperKind: .substantive),
        ]
    )
    if !mDup.isValid() {
        malformedRejected += 1
    }
    let mDangling = GroundGraph(
        root: "A",
        modules: [GroundModule(name: "A", lines: 1, bytes: 10, imports: ["Ghost"], wrapperKind: .substantive)]
    )
    if !mDangling.isValid() {
        malformedRejected += 1
    }
    do {
        _ = try decodeGroundGraphJSON("{\"root\":\"A\",\"modules\":[")
    } catch {
        malformedRejected += 1
    }

    let totalCases = casesPerFamily * 6
    let corpusDigestSha256 = groundSha256Hex(trace)
    let allPassed = casesPerFamily >= 30
        && dagCleanPassed == casesPerFamily
        && cycleShrunkMinimal == casesPerFamily
        && diamondDomPassed == casesPerFamily
        && deadLeavesPassed == casesPerFamily
        && wrapperAstPassed == casesPerFamily
        && metamorphicPairsPassed == casesPerFamily * 3
        && malformedRejected == 4

    return Rung2ParityReceipt(
        masterSeed: masterSeed,
        casesPerFamily: casesPerFamily,
        totalCases: totalCases,
        dagCleanPassed: dagCleanPassed,
        cycleShrunkMinimal: cycleShrunkMinimal,
        diamondDomPassed: diamondDomPassed,
        deadLeavesPassed: deadLeavesPassed,
        wrapperAstPassed: wrapperAstPassed,
        metamorphicPairsPassed: metamorphicPairsPassed,
        malformedRejected: malformedRejected,
        corpusDigestSha256: corpusDigestSha256,
        allPassed: allPassed
    )
}
