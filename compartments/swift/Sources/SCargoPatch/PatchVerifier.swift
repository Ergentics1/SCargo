// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

// Standalone Arc 6 Concrete AST-Aware Patch Plan Verifier & Pure In-Memory
// Unified-Diff Round-Trip Engine (pure Swift 6, zero external dependencies).

import Foundation

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256
// =============================================================================

private let patchSha256K: [UInt32] = [
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
private func patchRotr32(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}

public func patchSha256Hex(_ data: [UInt8]) -> String {
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
            let s0 = patchRotr32(w[i - 15], 7) ^ patchRotr32(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = patchRotr32(w[i - 2], 17) ^ patchRotr32(w[i - 2], 19) ^ (w[i - 2] >> 10)
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
            let s1 = patchRotr32(e, 6) ^ patchRotr32(e, 11) ^ patchRotr32(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let t1 = hh &+ s1 &+ ch &+ patchSha256K[i] &+ w[i]
            let s0 = patchRotr32(a, 2) ^ patchRotr32(a, 13) ^ patchRotr32(a, 22)
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

public func patchSha256Hex(_ text: String) -> String {
    patchSha256Hex(Array(text.utf8))
}

public struct PatchError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) {
        self.message = message
    }
}

// =============================================================================
// 2. Pure Zero-Dependency JSON Parser
// =============================================================================

private enum PJVal {
    case null
    case bool(Bool)
    case num(String)
    case str(String)
    case arr([PJVal])
    case obj([String: PJVal])

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
    func asArr() -> [PJVal]? {
        if case .arr(let a) = self { return a }
        return nil
    }
    func get(_ k: String) -> PJVal? {
        if case .obj(let m) = self { return m[k] }
        return nil
    }
}

private struct PJsonParser {
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

    mutating func parseVal() throws -> PJVal {
        skipWs()
        guard let b = peek() else {
            throw PatchError("unexpected EOF in JSON at \(pos)")
        }
        switch b {
        case 0x22: return .str(try parseStr())
        case 0x5b: return try parseArr()
        case 0x7b: return try parseObj()
        case 0x74: return try expectLit([0x74, 0x72, 0x75, 0x65], .bool(true))
        case 0x66: return try expectLit([0x66, 0x61, 0x6c, 0x73, 0x65], .bool(false))
        case 0x6e: return try expectLit([0x6e, 0x75, 0x6c, 0x6c], .null)
        case 0x2d, 0x30...0x39: return try parseNum()
        default: throw PatchError("unexpected JSON token at \(pos)")
        }
    }

    mutating func expectLit(_ lit: [UInt8], _ val: PJVal) throws -> PJVal {
        guard pos + lit.count <= bytes.count else {
            throw PatchError("truncated literal at \(pos)")
        }
        for i in 0..<lit.count {
            if bytes[pos + i] != lit[i] {
                throw PatchError("invalid literal at \(pos)")
            }
        }
        pos += lit.count
        return val
    }

    mutating func parseStr() throws -> String {
        guard peek() == 0x22 else {
            throw PatchError("expected quote")
        }
        pos += 1
        var buf: [UInt8] = []
        while pos < bytes.count {
            let b = bytes[pos]
            pos += 1
            if b == 0x22 {
                guard let s = String(bytes: buf, encoding: .utf8) else {
                    throw PatchError("invalid utf8 string")
                }
                return s
            }
            if b == 0x5c {
                guard pos < bytes.count else {
                    throw PatchError("truncated escape")
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
                        throw PatchError("truncated unicode escape")
                    }
                    guard let hex = String(bytes: bytes[pos..<(pos + 4)], encoding: .utf8),
                          let code = UInt32(hex, radix: 16),
                          let scalar = UnicodeScalar(code)
                    else {
                        throw PatchError("bad unicode escape")
                    }
                    pos += 4
                    buf.append(contentsOf: String(scalar).utf8)
                default:
                    throw PatchError("unsupported escape")
                }
            } else {
                buf.append(b)
            }
        }
        throw PatchError("unterminated JSON string")
    }

    mutating func parseNum() throws -> PJVal {
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
            throw PatchError("bad number")
        }
        return .num(raw)
    }

    mutating func parseArr() throws -> PJVal {
        pos += 1
        skipWs()
        var items: [PJVal] = []
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
                throw PatchError("expected ',' or ']'")
            }
        }
    }

    mutating func parseObj() throws -> PJVal {
        pos += 1
        skipWs()
        var map: [String: PJVal] = [:]
        if peek() == 0x7d {
            pos += 1
            return .obj(map)
        }
        while true {
            skipWs()
            let k = try parseStr()
            skipWs()
            guard peek() == 0x3a else {
                throw PatchError("expected ':'")
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
                throw PatchError("expected ',' or '}'")
            }
        }
    }
}

private func parsePatchJSON(_ input: String) throws -> PJVal {
    var parser = PJsonParser(bytes: Array(input.utf8))
    let val = try parser.parseVal()
    parser.skipWs()
    if parser.pos != parser.bytes.count {
        throw PatchError("trailing JSON bytes")
    }
    return val
}

// =============================================================================
// 3. Pure In-Memory Unified Diff Emitter & Fail-Closed Hunk Applier
// =============================================================================

public struct EditBlock: Sendable, Equatable {
    public let oldStart: Int
    public let oldEnd: Int
    public let newLines: [String]

    public init(oldStart: Int, oldEnd: Int, newLines: [String]) {
        self.oldStart = oldStart
        self.oldEnd = oldEnd
        self.newLines = newLines
    }
}

public func splitLFLines(_ src: String) -> [String] {
    if src.isEmpty {
        return []
    }
    let trimmed = src.hasSuffix("\n") ? String(src.dropLast()) : src
    return trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

public func emitDeleteUnifiedDiff(relPath: String, oldSrc: String) -> (String, Int) {
    let oldLines = splitLFLines(oldSrc)
    var out = ""
    out.append("diff --git a/\(relPath) b/\(relPath)\n")
    out.append("deleted file mode 100644\n")
    out.append("--- a/\(relPath)\n")
    out.append("+++ /dev/null\n")
    if oldLines.isEmpty {
        return (out, 0)
    }
    out.append("@@ -1,\(oldLines.count) +0,0 @@\n")
    for ln in oldLines {
        out.append("-")
        out.append(ln)
        out.append("\n")
    }
    return (out, 1)
}

public func emitUnifiedDiffFromEdits(
    relPath: String,
    oldSrc: String,
    edits: [EditBlock],
    context: Int
) throws -> (String, Int) {
    if edits.isEmpty {
        throw PatchError("refusing to emit empty unified diff")
    }
    let oldLines = splitLFLines(oldSrc)
    let sorted = edits.sorted { $0.oldStart < $1.oldStart }
    for i in 1..<sorted.count {
        if sorted[i - 1].oldEnd > sorted[i].oldStart {
            throw PatchError("overlapping edit blocks")
        }
    }
    for e in sorted {
        if e.oldEnd > oldLines.count {
            throw PatchError("edit block exceeds source line count")
        }
    }

    var groups: [[EditBlock]] = []
    for e in sorted {
        if let lastIdx = groups.indices.last,
           let prev = groups[lastIdx].last,
           e.oldStart <= prev.oldEnd + context * 2
        {
            groups[lastIdx].append(e)
            continue
        }
        groups.append([e])
    }

    var out = ""
    out.append("diff --git a/\(relPath) b/\(relPath)\n")
    out.append("--- a/\(relPath)\n")
    out.append("+++ b/\(relPath)\n")

    var delta = 0
    for grp in groups {
        let first = grp[0]
        let last = grp[grp.count - 1]
        let ctxStart = max(0, first.oldStart - context)
        let ctxEnd = min(oldLines.count, last.oldEnd + context)

        var oldCnt = 0
        var newCnt = 0
        var body = ""
        var cur = ctxStart
        for e in grp {
            while cur < e.oldStart {
                body.append(" ")
                body.append(oldLines[cur])
                body.append("\n")
                oldCnt += 1
                newCnt += 1
                cur += 1
            }
            for k in e.oldStart..<e.oldEnd {
                body.append("-")
                body.append(oldLines[k])
                body.append("\n")
                oldCnt += 1
            }
            for add in e.newLines {
                body.append("+")
                body.append(add)
                body.append("\n")
                newCnt += 1
            }
            cur = e.oldEnd
        }
        while cur < ctxEnd {
            body.append(" ")
            body.append(oldLines[cur])
            body.append("\n")
            oldCnt += 1
            newCnt += 1
            cur += 1
        }

        let oldS1 = oldCnt == 0 ? ctxStart : ctxStart + 1
        let newS0 = ctxStart + delta
        let newS1 = newCnt == 0 ? newS0 : newS0 + 1
        out.append("@@ -\(oldS1),\(oldCnt) +\(newS1),\(newCnt) @@\n")
        out.append(body)
        delta += newCnt - oldCnt
    }

    return (out, groups.count)
}

private func parseHunkRange(_ tok: String, prefix: Character) throws -> (Int, Int) {
    guard tok.first == prefix else {
        throw PatchError("expected '\(prefix)' in hunk range '\(tok)'")
    }
    let rest = String(tok.dropFirst())
    if let comma = rest.firstIndex(of: ",") {
        let aStr = String(rest[..<comma])
        let bStr = String(rest[rest.index(after: comma)...])
        guard let start = Int(aStr), let count = Int(bStr) else {
            throw PatchError("bad hunk range '\(tok)'")
        }
        return (start, count)
    } else {
        guard let start = Int(rest) else {
            throw PatchError("bad hunk start '\(tok)'")
        }
        return (start, 1)
    }
}

public func applyUnifiedDiff(oldSrc: String, diffText: String) throws -> String {
    let diffLines = splitLFLines(diffText)
    if diffLines.isEmpty {
        throw PatchError("empty unified diff")
    }
    let oldLines = splitLFLines(oldSrc)
    var isDelete = false
    var sawOldHdr = false
    var sawNewHdr = false
    var idx = 0

    while idx < diffLines.count {
        let ln = diffLines[idx]
        if ln.hasPrefix("--- ") {
            sawOldHdr = true
            idx += 1
        } else if ln.hasPrefix("+++ ") {
            sawNewHdr = true
            let tgt = String(ln.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if tgt == "/dev/null" {
                isDelete = true
            }
            idx += 1
            break
        } else {
            idx += 1
        }
    }
    if !sawOldHdr || !sawNewHdr {
        throw PatchError("missing --- / +++ unified diff headers")
    }

    var outLines: [String] = []
    var srcCursor = 0
    var hunksApplied = 0

    while idx < diffLines.count {
        let hdr = diffLines[idx]
        if !hdr.hasPrefix("@@ ") {
            throw PatchError("expected @@ hunk header, got '\(hdr)'")
        }
        let parts = hdr.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if parts.count < 4 || parts[0] != "@@" || parts[3] != "@@" {
            throw PatchError("malformed hunk header '\(hdr)'")
        }
        let (oldS, oldC) = try parseHunkRange(parts[1], prefix: "-")
        let (_, newC) = try parseHunkRange(parts[2], prefix: "+")
        let hunkSrcStart = oldC == 0 ? oldS : max(0, oldS - 1)
        if hunkSrcStart < srcCursor || hunkSrcStart > oldLines.count {
            throw PatchError("hunk start out of bounds or overlapping")
        }
        while srcCursor < hunkSrcStart {
            outLines.append(oldLines[srcCursor])
            srcCursor += 1
        }
        idx += 1
        var seenOld = 0
        var seenNew = 0
        while idx < diffLines.count && !diffLines[idx].hasPrefix("@@ ") {
            let row = diffLines[idx]
            if row.hasPrefix(" ") {
                let ctx = String(row.dropFirst())
                if srcCursor >= oldLines.count || oldLines[srcCursor] != ctx {
                    throw PatchError("context mismatch at line \(srcCursor + 1)")
                }
                outLines.append(ctx)
                srcCursor += 1
                seenOld += 1
                seenNew += 1
            } else if row.hasPrefix("-") {
                let rem = String(row.dropFirst())
                if srcCursor >= oldLines.count || oldLines[srcCursor] != rem {
                    throw PatchError("deletion mismatch at line \(srcCursor + 1)")
                }
                srcCursor += 1
                seenOld += 1
            } else if row.hasPrefix("+") {
                outLines.append(String(row.dropFirst()))
                seenNew += 1
            } else {
                throw PatchError("invalid diff line prefix in '\(row)'")
            }
            idx += 1
        }
        if seenOld != oldC || seenNew != newC {
            throw PatchError("hunk line count mismatch")
        }
        hunksApplied += 1
    }

    if hunksApplied == 0 && !oldLines.isEmpty {
        throw PatchError("no hunks applied to non-empty file")
    }
    while srcCursor < oldLines.count {
        outLines.append(oldLines[srcCursor])
        srcCursor += 1
    }
    if isDelete {
        if !outLines.isEmpty {
            throw PatchError("delete diff left residual lines")
        }
        return ""
    }
    if outLines.isEmpty {
        return ""
    }
    return outLines.joined(separator: "\n") + "\n"
}

// =============================================================================
// 4. Shared Guards, Z-C2 Balanced-AST Collapse, Closed CSE & Z-C4 Pruner
// =============================================================================

public let z2WrapWidth: Int = 160
public let z2MaxLineBound: Int = 280

public func containsVerbatimProofBody(_ rawJSON: String) -> Bool {
    rawJSON.contains(":= by")
        || rawJSON.contains("private theorem ")
        || rawJSON.contains("noncomputable def ")
        || rawJSON.contains("public import Mathlib")
}

public func delimitersBalanced(_ src: String) -> Bool {
    let bytes = Array(src.utf8)
    var paren = 0
    var brace = 0
    var brack = 0
    var inStr = false
    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if b == 0x22 && (i == 0 || bytes[i - 1] != 0x5c) {
            inStr = !inStr
            i += 1
            continue
        }
        if !inStr {
            if b == 0x2d && i + 1 < bytes.count && bytes[i + 1] == 0x2d {
                while i < bytes.count && bytes[i] != 0x0a {
                    i += 1
                }
                continue
            }
            switch b {
            case 0x28: paren += 1
            case 0x29:
                paren -= 1
                if paren < 0 { return false }
            case 0x7b: brace += 1
            case 0x7d:
                brace -= 1
                if brace < 0 { return false }
            case 0x5b: brack += 1
            case 0x5d:
                brack -= 1
                if brack < 0 { return false }
            default:
                break
            }
        }
        i += 1
    }
    return paren == 0 && brace == 0 && brack == 0
}

private func splitASCIIWhitespace(_ s: String) -> [String] {
    s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).map(String.init)
}

public func tokensIdentical(_ a: String, _ b: String) -> Bool {
    splitASCIIWhitespace(a) == splitASCIIWhitespace(b)
}

@inline(__always)
private func isASCIIAlpha(_ b: UInt8) -> Bool {
    (b >= 0x41 && b <= 0x5a) || (b >= 0x61 && b <= 0x7a)
}

@inline(__always)
private func isASCIIUpper(_ b: UInt8) -> Bool {
    b >= 0x41 && b <= 0x5a
}

@inline(__always)
private func isASCIIDigit(_ b: UInt8) -> Bool {
    b >= 0x30 && b <= 0x39
}

@inline(__always)
private func isIdentByte(_ b: UInt8) -> Bool {
    isASCIIAlpha(b) || isASCIIDigit(b) || b == 0x5f || b == 0x27
}

public func spanHasTargetAtHead(_ span: String) -> Bool {
    if span.contains("@inst")
        || span.contains("@AlgebraicClosure.inst")
        || span.contains("@NumberField.inst")
        || span.contains("@ValuativeRel.inst")
    {
        return true
    }
    let bytes = Array(span.utf8)
    var i = 0
    while i < bytes.count {
        if bytes[i] == 0x40 && i + 1 < bytes.count && isASCIIUpper(bytes[i + 1]) {
            var j = i + 1
            while j < bytes.count && (isASCIIAlpha(bytes[j]) || isASCIIDigit(bytes[j]) || bytes[j] == 0x5f) {
                j += 1
            }
            if j + 3 < bytes.count
                && bytes[j] == 0x2e
                && bytes[j + 1] == 0x74
                && bytes[j + 2] == 0x6f
                && isASCIIUpper(bytes[j + 3])
            {
                return true
            }
        }
        i += 1
    }
    return false
}

public func spanHasLayoutKeyword(_ span: String) -> Bool {
    let layoutKws: Set<String> = [
        "by", "do", "match", "where", "let", "have", "show", "fun",
        "calc", "conv", "macro", "syntax", "notation",
    ]
    let bytes = Array(span.utf8)
    var i = 0
    while i < bytes.count {
        if isASCIIAlpha(bytes[i]) || bytes[i] == 0x5f {
            let start = i
            while i < bytes.count && isIdentByte(bytes[i]) {
                i += 1
            }
            let prevDotOrAt = start > 0 && (bytes[start - 1] == 0x2e || bytes[start - 1] == 0x40)
            if !prevDotOrAt, let word = String(bytes: bytes[start..<i], encoding: .utf8), layoutKws.contains(word) {
                return true
            }
        } else {
            i += 1
        }
    }
    return false
}

public func wrapCompactTokens(_ compact: String, width: Int) -> String {
    if compact.utf8.count <= width {
        return compact
    }
    let toks = compact.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard let first = toks.first else {
        return ""
    }
    var lines: [String] = []
    var cur = first
    for t in toks.dropFirst() {
        if cur.utf8.count + 1 + t.utf8.count <= width {
            cur.append(" ")
            cur.append(t)
        } else {
            lines.append(cur)
            cur = "  \(t)"
        }
    }
    lines.append(cur)
    return lines.joined(separator: "\n")
}

public struct Z2CompactOutput: Sendable, Equatable {
    public let afterSrc: String
    public let edits: [EditBlock]
    public let collapsedSpans: Int
    public let skippedLayoutSpans: Int
}

public func transformZ2BalancedCollapse(src: String, wrapWidth: Int) throws -> Z2CompactOutput {
    let bytes = Array(src.utf8)
    let n = bytes.count
    var charEdits: [(Int, Int, String)] = []
    var collapsedSpans = 0
    var skippedLayoutSpans = 0
    var i = 0

    while i < n {
        if bytes[i] == 0x28 {
            var depth = 0
            var j = i
            var unsafeSpan = false
            while j < n {
                let b = bytes[j]
                if b == 0x22
                    || b == 0x60
                    || b == 0x7c
                    || (b == 0x2d && j + 1 < n && bytes[j + 1] == 0x2d)
                    || (b == 0x2f && j + 1 < n && bytes[j + 1] == 0x2d)
                {
                    unsafeSpan = true
                    break
                }
                if b == 0x28 {
                    depth += 1
                } else if b == 0x29 {
                    depth -= 1
                    if depth == 0 {
                        break
                    }
                }
                j += 1
            }
            if !unsafeSpan && depth == 0 && j < n {
                guard let span = String(bytes: bytes[i...j], encoding: .utf8) else {
                    throw PatchError("invalid utf8 span")
                }
                var atCount = 0
                for b in bytes[i...j] where b == 0x40 {
                    atCount += 1
                }
                if span.contains("\n") && (atCount >= 2 || spanHasTargetAtHead(span)) {
                    if spanHasLayoutKeyword(span) {
                        skippedLayoutSpans += 1
                    } else {
                        let compact = splitASCIIWhitespace(span).joined(separator: " ")
                        let wrapped = wrapCompactTokens(compact, width: wrapWidth)
                        if wrapped != span {
                            charEdits.append((i, j + 1, wrapped))
                            collapsedSpans += 1
                            i = j + 1
                            continue
                        }
                    }
                }
            }
        }
        i += 1
    }

    if charEdits.isEmpty {
        throw PatchError("no eligible layout-free multi-line @-spans found")
    }

    let oldLines = splitLFLines(src)
    var lineStarts: [Int] = []
    lineStarts.reserveCapacity(oldLines.count)
    var off = 0
    for ln in oldLines {
        lineStarts.append(off)
        off += ln.utf8.count + 1
    }

    func byteToLine(_ pos: Int) -> Int {
        var lo = 0
        var hi = lineStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= pos {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return max(0, lo - 1)
    }

    struct LineGroup {
        var lStart: Int
        var lEndIncl: Int
        var reps: [(Int, Int, String)]
    }
    var groups: [LineGroup] = []
    for (a, b, rep) in charEdits {
        let ls = byteToLine(a)
        let le = byteToLine(max(0, b - 1))
        if let lastIdx = groups.indices.last, ls <= groups[lastIdx].lEndIncl {
            if le > groups[lastIdx].lEndIncl {
                groups[lastIdx].lEndIncl = le
            }
            groups[lastIdx].reps.append((a, b, rep))
            continue
        }
        groups.append(LineGroup(lStart: ls, lEndIncl: le, reps: [(a, b, rep)]))
    }

    var edits: [EditBlock] = []
    var afterLines: [String] = []
    var curLine = 0
    for grp in groups {
        while curLine < grp.lStart {
            afterLines.append(oldLines[curLine])
            curLine += 1
        }
        let segByteStart = lineStarts[grp.lStart]
        let segByteEnd = lineStarts[grp.lEndIncl] + oldLines[grp.lEndIncl].utf8.count
        var rebuiltBytes: [UInt8] = []
        var relPos = segByteStart
        for (a, b, rep) in grp.reps {
            if a > relPos {
                rebuiltBytes.append(contentsOf: bytes[relPos..<a])
            }
            rebuiltBytes.append(contentsOf: rep.utf8)
            relPos = b
        }
        if segByteEnd > relPos {
            rebuiltBytes.append(contentsOf: bytes[relPos..<segByteEnd])
        }
        guard let rebuilt = String(bytes: rebuiltBytes, encoding: .utf8) else {
            throw PatchError("rebuilt utf8 error")
        }
        let newLines = rebuilt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        afterLines.append(contentsOf: newLines)
        edits.append(EditBlock(oldStart: grp.lStart, oldEnd: grp.lEndIncl + 1, newLines: newLines))
        curLine = grp.lEndIncl + 1
    }
    while curLine < oldLines.count {
        afterLines.append(oldLines[curLine])
        curLine += 1
    }

    var afterSrc = afterLines.joined(separator: "\n")
    if src.hasSuffix("\n") {
        afterSrc.append("\n")
    }
    if !tokensIdentical(src, afterSrc) {
        throw PatchError("Z-C2-COMPACT violated token-stream identity")
    }
    if !delimitersBalanced(afterSrc) {
        throw PatchError("Z-C2-COMPACT violated delimiter balance")
    }
    if afterSrc.utf8.count >= src.utf8.count {
        throw PatchError("Z-C2-COMPACT did not strictly reduce byte mass")
    }

    return Z2CompactOutput(
        afterSrc: afterSrc,
        edits: edits,
        collapsedSpans: collapsedSpans,
        skippedLayoutSpans: skippedLayoutSpans
    )
}

public func countFreeLocalVars(_ expr: String) -> Int {
    let closedGlobals: Set<String> = [
        "Nat", "Int", "Rat", "Real", "Complex", "Prop", "Type", "Sort", "True", "False", "Unit",
        "PUnit", "ULift", "Fact", "Fin", "HAdd", "HMul", "HSub", "HDiv", "HPow", "HSMul", "Add",
        "Mul", "Ring", "CommRing", "Semiring", "CommSemiring", "Field", "DivisionRing",
        "Semifield", "DivisionSemiring", "AddCommMonoid", "AddCommGroup", "Module", "Algebra",
        "Padic", "PadicInt", "PadicAlgCl", "AlgebraicClosure", "NumberField",
    ]
    let bytes = Array(expr.utf8)
    var free = Set<String>()
    var i = 0
    while i < bytes.count {
        if isASCIIAlpha(bytes[i]) || bytes[i] == 0x5f {
            let start = i
            while i < bytes.count && isIdentByte(bytes[i]) {
                i += 1
            }
            let prevAtOrDot = start > 0 && (bytes[start - 1] == 0x40 || bytes[start - 1] == 0x2e)
            if !prevAtOrDot,
               let tok = String(bytes: bytes[start..<i], encoding: .utf8),
               !closedGlobals.contains(tok),
               !tok.hasPrefix("inst")
            {
                free.insert(tok)
            }
        } else {
            i += 1
        }
    }
    return free.count
}

private func countNonOverlappingMatches(in haystack: String, needle: String) -> Int {
    if needle.isEmpty { return 0 }
    var count = 0
    var searchStart = haystack.startIndex
    while searchStart < haystack.endIndex,
          let r = haystack.range(of: needle, range: searchStart..<haystack.endIndex)
    {
        count += 1
        searchStart = r.upperBound
    }
    return count
}

public func transformZ2ClosedCse(
    src: String,
    targetExpr: String,
    abbrevName: String
) throws -> (String, [EditBlock]) {
    if !delimitersBalanced(targetExpr) || spanHasLayoutKeyword(targetExpr) {
        throw PatchError("invalid or layout-bearing CSE target")
    }
    let fv = countFreeLocalVars(targetExpr)
    if fv > 0 {
        throw PatchError("refusing to hoist subtree with \(fv) free local variable(s)")
    }
    if countNonOverlappingMatches(in: src, needle: targetExpr) < 2 {
        throw PatchError("CSE requires >= 2 exact occurrences")
    }
    let oldLines = splitLFLines(src)
    guard let anchorIdx = oldLines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "@[expose] public section" }) else {
        throw PatchError("missing @[expose] public section anchor for Lean 4.36 module CSE")
    }

    var edits: [EditBlock] = []
    let abbrevLine = "abbrev \(abbrevName) := \(targetExpr)"
    edits.append(EditBlock(oldStart: anchorIdx, oldEnd: anchorIdx + 1, newLines: [oldLines[anchorIdx], abbrevLine]))
    for (li, ln) in oldLines.enumerated() {
        if li != anchorIdx && ln.contains(targetExpr) {
            edits.append(
                EditBlock(
                    oldStart: li,
                    oldEnd: li + 1,
                    newLines: [ln.replacingOccurrences(of: targetExpr, with: abbrevName)]
                )
            )
        }
    }
    let (diffTxt, _) = try emitUnifiedDiffFromEdits(
        relPath: "SyntheticCse.lean",
        oldSrc: src,
        edits: edits,
        context: 3
    )
    let afterSrc = try applyUnifiedDiff(oldSrc: src, diffText: diffTxt)
    if afterSrc.utf8.count >= src.utf8.count || !delimitersBalanced(afterSrc) {
        throw PatchError("closed CSE failed strict Pareto or delimiter check")
    }
    return (afterSrc, edits)
}

public func transformZ4PruneImports(
    src: String,
    transitivelyCovered: Set<String>,
    toPrune: Set<String>
) throws -> (String, [EditBlock], Int) {
    if toPrune.isEmpty {
        throw PatchError("empty Z-C4 prune set")
    }
    for m in toPrune {
        if !transitivelyCovered.contains(m) {
            throw PatchError("refusing to prune non-redundant import '\(m)'")
        }
    }
    let oldLines = splitLFLines(src)
    var edits: [EditBlock] = []
    var afterLines: [String] = []
    var pruned = 0
    var i = 0

    func isDropped(_ ln: String) -> Bool {
        let t = ln.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("public import ") {
            let rest = String(t.dropFirst("public import ".count))
            let modName = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            return toPrune.contains(modName)
        }
        return false
    }

    while i < oldLines.count {
        if isDropped(oldLines[i]) {
            let start = i
            while i < oldLines.count && isDropped(oldLines[i]) {
                pruned += 1
                i += 1
            }
            edits.append(EditBlock(oldStart: start, oldEnd: i, newLines: []))
        } else {
            afterLines.append(oldLines[i])
            i += 1
        }
    }
    if pruned != toPrune.count {
        throw PatchError("Z-C4 pruned \(pruned) lines but expected \(toPrune.count)")
    }
    var afterSrc = afterLines.joined(separator: "\n")
    if src.hasSuffix("\n") && !afterSrc.isEmpty {
        afterSrc.append("\n")
    }
    if afterSrc.utf8.count >= src.utf8.count {
        throw PatchError("Z-C4 prune did not strictly reduce bytes")
    }
    return (afterSrc, edits, pruned)
}

public struct PatchEntryHashInput: Sendable {
    public let path: String
    public let zoneId: String
    public let shardId: String
    public let transformKind: String
    public let beforeSha256: String
    public let afterSha256: String
    public let unifiedDiffSha256: String
    public let linesBefore: UInt64
    public let linesAfter: UInt64
    public let bytesBefore: UInt64
    public let bytesAfter: UInt64
    public let hunkCount: Int
}

public func computePatchEntrySha256(_ inp: PatchEntryHashInput) -> String {
    let s = "\(inp.path)|\(inp.zoneId)|\(inp.shardId)|\(inp.transformKind)|\(inp.beforeSha256)|\(inp.afterSha256)|\(inp.unifiedDiffSha256)|\(inp.linesBefore):\(inp.linesAfter)|\(inp.bytesBefore):\(inp.bytesAfter)|\(inp.hunkCount)"
    return patchSha256Hex(s)
}

// =============================================================================
// 5. Offline Clean-Room Synthetic Unified-Diff & AST Round-Trip Suite (PG-4)
// =============================================================================

public func runSyntheticPatchSuite() throws -> (Int, String) {
    var trace = ""

    // 1. Z-C0 synthetic dead-leaf delete unified diff + round-trip apply
    let z0Src = "module\npublic import Base\n@[expose] public section\ntheorem deadLeaf : True := trivial\n"
    let (z0Diff, z0Hunks) = emitDeleteUnifiedDiff(relPath: "Synthetic/DeadLeaf.lean", oldSrc: z0Src)
    let z0Rt = try applyUnifiedDiff(oldSrc: z0Src, diffText: z0Diff)
    if !z0Rt.isEmpty || z0Hunks != 1 {
        throw PatchError("synthetic Z-C0 round-trip failed")
    }
    trace.append(patchSha256Hex(z0Diff))
    trace.append(";")

    // 2. Z-C2-COMPACT synthetic multi-line @-chain collapse (<= 160 wrap) + round-trip apply
    let z2Src = "module\n@[expose] public section\ndef poly (a b c : Nat) : Nat :=\n  (@HAdd.hAdd\n    Nat\n    Nat\n    Nat\n    (@instHAdd\n      Nat\n      instAddNat)\n    (@HMul.hMul\n      Nat\n      Nat\n      Nat\n      (@instHMul\n        Nat\n        instMulNat)\n      a\n      b)\n    c)\n"
    let z2Res = try transformZ2BalancedCollapse(src: z2Src, wrapWidth: z2WrapWidth)
    let (z2Diff, z2Hunks) = try emitUnifiedDiffFromEdits(
        relPath: "Synthetic/CapelliCompact.lean",
        oldSrc: z2Src,
        edits: z2Res.edits,
        context: 3
    )
    let z2Rt = try applyUnifiedDiff(oldSrc: z2Src, diffText: z2Diff)
    if z2Rt != z2Res.afterSrc || z2Hunks == 0 || !tokensIdentical(z2Src, z2Rt) {
        throw PatchError("synthetic Z-C2-COMPACT round-trip failed")
    }
    trace.append(patchSha256Hex(z2Diff))
    trace.append(";")

    // 3. Z-C2-CLOSED-CSE synthetic 0-free-variable abbrev hoist + round-trip apply
    let closedExpr = "(@HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) Nat.zero Nat.zero) Nat.zero)"
    let z2CseSrc = "module\n@[expose] public section\ndef e1 : Nat := \(closedExpr)\ndef e2 : Nat := \(closedExpr)\n"
    let (z2CseAfter, z2CseEdits) = try transformZ2ClosedCse(
        src: z2CseSrc,
        targetExpr: closedExpr,
        abbrevName: "_scargo_cse_0"
    )
    let (z2CseDiff, z2CseHunks) = try emitUnifiedDiffFromEdits(
        relPath: "Synthetic/CapelliClosedCse.lean",
        oldSrc: z2CseSrc,
        edits: z2CseEdits,
        context: 3
    )
    let z2CseRt = try applyUnifiedDiff(oldSrc: z2CseSrc, diffText: z2CseDiff)
    if z2CseRt != z2CseAfter || z2CseHunks == 0 || !z2CseRt.contains("abbrev _scargo_cse_0 :=") {
        throw PatchError("synthetic Z-C2-CLOSED-CSE round-trip failed")
    }
    trace.append(patchSha256Hex(z2CseDiff))
    trace.append(";")

    // 4. Z-C4 synthetic transitive import pruning + round-trip apply
    let z4Src = "module\npublic import SCargoLean.Preflight.Leaf\npublic import SCargoLean.Preflight.Mid\n@[expose] public section\ntheorem hub : True := trivial\n"
    let covered: Set<String> = ["SCargoLean.Preflight.Leaf"]
    let toPrune: Set<String> = ["SCargoLean.Preflight.Leaf"]
    let (z4After, z4Edits, z4Pruned) = try transformZ4PruneImports(
        src: z4Src,
        transitivelyCovered: covered,
        toPrune: toPrune
    )
    let (z4Diff, z4Hunks) = try emitUnifiedDiffFromEdits(
        relPath: "Synthetic/HubPruned.lean",
        oldSrc: z4Src,
        edits: z4Edits,
        context: 3
    )
    let z4Rt = try applyUnifiedDiff(oldSrc: z4Src, diffText: z4Diff)
    if z4Rt != z4After || z4Pruned != 1 || z4Hunks != 1 {
        throw PatchError("synthetic Z-C4 round-trip failed")
    }
    trace.append(patchSha256Hex(z4Diff))
    trace.append(";")

    return (4, patchSha256Hex(trace))
}

// =============================================================================
// 6. Arc 6 Patch Plan Receipt & Offline Verifier (PG-1..PG-6)
// =============================================================================

public struct Arc6PatchReceipt: Sendable, Equatable {
    public let patchPlanId: String
    public let baselineCommit: String
    public let targetRepoMutationAllowed: Bool
    public let pg1ProvenanceZoneAUp08Clean: Bool
    public let pg2Bijection137AndHashesValid: Bool
    public let pg3ParetoRoundtripAndBoundsValid: Bool
    public let pg4SyntheticPatchSuiteValid: Bool
    public let pg5LeanPreflightModulesValid: Bool
    public let pg6NegativeControlsValid: Bool
    public let totalFiles: Int
    public let z0SavedLines: UInt64
    public let z2SavedLines: UInt64
    public let z4SavedLines: UInt64
    public let totalSavedLines: UInt64
    public let totalSavedBytes: UInt64
    public let z2MaxLineAfter: Int
    public let syntheticTransformsPassed: Int
    public let negativeControlsRejected: Int
    public let totalNegativeControls: Int
    public let syntheticPatchSuiteSha256: String
    public let inputDigestsSha256: String
    public let patchDigestSha256: String
    public let allPassed: Bool

    public func toCanonicalJSON() -> String {
        "{\"all_passed\":\(allPassed),\"baseline_commit\":\"\(baselineCommit)\",\"input_digests_sha256\":\"\(inputDigestsSha256)\",\"negative_controls_rejected\":\(negativeControlsRejected),\"patch_digest_sha256\":\"\(patchDigestSha256)\",\"patch_plan_id\":\"\(patchPlanId)\",\"pg1_provenance_zone_a_up08_clean\":\(pg1ProvenanceZoneAUp08Clean),\"pg2_bijection_137_and_hashes_valid\":\(pg2Bijection137AndHashesValid),\"pg3_pareto_roundtrip_and_bounds_valid\":\(pg3ParetoRoundtripAndBoundsValid),\"pg4_synthetic_patch_suite_valid\":\(pg4SyntheticPatchSuiteValid),\"pg5_lean_preflight_modules_valid\":\(pg5LeanPreflightModulesValid),\"pg6_negative_controls_valid\":\(pg6NegativeControlsValid),\"synthetic_patch_suite_sha256\":\"\(syntheticPatchSuiteSha256)\",\"synthetic_transforms_passed\":\(syntheticTransformsPassed),\"target_repo_mutation_allowed\":\(targetRepoMutationAllowed),\"total_files\":\(totalFiles),\"total_negative_controls\":\(totalNegativeControls),\"total_saved_bytes\":\(totalSavedBytes),\"total_saved_lines\":\(totalSavedLines),\"z0_saved_lines\":\(z0SavedLines),\"z2_max_line_after\":\(z2MaxLineAfter),\"z2_saved_lines\":\(z2SavedLines),\"z4_saved_lines\":\(z4SavedLines)}"
    }
}

private func readUTF8(_ url: URL, label: String) throws -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw PatchError("read \(label): \(error)")
    }
}

public func verifyArc6PatchPlan(repoRoot: URL) throws -> Arc6PatchReceipt {
    let relPlan = "transfer/patches/arc6_patch_plan_v1.json"
    let relBundles = "transfer/bundles/arc5_preflight_bundles_v1.json"
    let relZones = "data/manifests/transfer_zones_v1.json"

    let planRaw = try readUTF8(repoRoot.appendingPathComponent(relPlan), label: relPlan)
    let bundlesRaw = try readUTF8(repoRoot.appendingPathComponent(relBundles), label: relBundles)
    let zonesRaw = try readUTF8(repoRoot.appendingPathComponent(relZones), label: relZones)

    var dchain = ""
    for (label, content) in [
        (relPlan, planRaw),
        (relBundles, bundlesRaw),
        (relZones, zonesRaw),
    ] {
        dchain.append(label)
        dchain.append(":")
        dchain.append(patchSha256Hex(content))
        dchain.append(";")
    }
    let inputDigestsSha256 = patchSha256Hex(dchain)

    let plan = try parsePatchJSON(planRaw)
    let bundles = try parsePatchJSON(bundlesRaw)
    let zones = try parsePatchJSON(zonesRaw)

    guard let patchPlanId = plan.get("patch_plan_id")?.asStr() else {
        throw PatchError("missing patch_plan_id")
    }
    guard let baselineCommit = plan.get("source_repo_commit")?.asStr() else {
        throw PatchError("missing source_repo_commit")
    }
    let targetRepoMutationAllowed = plan.get("target_repo_mutation_allowed")?.asBool() ?? true
    let wrapWidth = Int(plan.get("z2_wrap_width")?.asU64() ?? 0)

    let bundlesSha = bundles.get("source_repo_commit")?.asStr() ?? ""
    let zonesSha = zones.get("baseline_commit")?.asStr() ?? ""

    guard let zoneArr = zones.get("zones")?.asArr() else {
        throw PatchError("missing zones")
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
        throw PatchError("missing shards")
    }
    var expectedMap: [String: (String, String)] = [:]
    for sh in shardArr {
        let zid = sh.get("zone_id")?.asStr() ?? ""
        if zid != "Z-C0" && zid != "Z-C2" && zid != "Z-C4" {
            continue
        }
        let sid = sh.get("shard_id")?.asStr() ?? ""
        guard let ps = sh.get("paths")?.asArr() else {
            throw PatchError("missing shard paths")
        }
        for p in ps {
            if let s = p.asStr() {
                expectedMap[s] = (zid, sid)
            }
        }
    }

    guard let entries = plan.get("entries")?.asArr() else {
        throw PatchError("missing entries")
    }
    var seenPaths = Set<String>()
    var anyZoneATouch = false
    var bijectionOk = true
    var hashesOk = true
    var paretoAndRtOk = true

    var z0SavedLines: UInt64 = 0
    var z2SavedLines: UInt64 = 0
    var z4SavedLines: UInt64 = 0
    var totalSavedBytes: UInt64 = 0
    var z2MaxLineAfter = 0

    for e in entries {
        let path = e.get("path")?.asStr() ?? ""
        let zid = e.get("zone_id")?.asStr() ?? ""
        let sid = e.get("shard_id")?.asStr() ?? ""
        let kind = e.get("transform_kind")?.asStr() ?? ""
        let bSha = e.get("before_sha256")?.asStr() ?? ""
        let aSha = e.get("after_sha256")?.asStr() ?? ""
        let dSha = e.get("unified_diff_sha256")?.asStr() ?? ""
        let declESha = e.get("entry_sha256")?.asStr() ?? ""
        let lb = e.get("lines_before")?.asU64() ?? 0
        let la = e.get("lines_after")?.asU64() ?? 0
        let bb = e.get("bytes_before")?.asU64() ?? 0
        let ba = e.get("bytes_after")?.asU64() ?? 0
        let maxLa = Int(e.get("max_line_after")?.asU64() ?? 0)
        let hc = Int(e.get("hunk_count")?.asU64() ?? 0)
        let rt = e.get("roundtrip_verified")?.asBool() ?? false
        let inv = e.get("invariant_verified")?.asBool() ?? false

        if zoneAPaths.contains(path) {
            anyZoneATouch = true
        }
        if !seenPaths.insert(path).inserted {
            bijectionOk = false
        }
        if let (expZ, expS) = expectedMap[path] {
            if expZ != zid || expS != sid {
                bijectionOk = false
            }
        } else {
            bijectionOk = false
        }

        let recomp = computePatchEntrySha256(
            PatchEntryHashInput(
                path: path,
                zoneId: zid,
                shardId: sid,
                transformKind: kind,
                beforeSha256: bSha,
                afterSha256: aSha,
                unifiedDiffSha256: dSha,
                linesBefore: lb,
                linesAfter: la,
                bytesBefore: bb,
                bytesAfter: ba,
                hunkCount: hc
            )
        )
        if recomp != declESha || bSha.count != 64 || aSha.count != 64 || dSha.count != 64 {
            hashesOk = false
        }

        if la >= lb || ba >= bb || hc == 0 || !rt || !inv {
            paretoAndRtOk = false
        }
        if zid == "Z-C2" {
            if maxLa > z2MaxLineBound {
                paretoAndRtOk = false
            }
            if maxLa > z2MaxLineAfter {
                z2MaxLineAfter = maxLa
            }
            z2SavedLines += lb >= la ? (lb - la) : 0
        } else if zid == "Z-C0" {
            if la != 0 || ba != 0 {
                paretoAndRtOk = false
            }
            z0SavedLines += lb >= la ? (lb - la) : 0
        } else if zid == "Z-C4" {
            z4SavedLines += lb >= la ? (lb - la) : 0
        }
        totalSavedBytes += bb >= ba ? (bb - ba) : 0
    }

    let totalSavedLines = z0SavedLines + z2SavedLines + z4SavedLines
    let summaryOk: Bool
    if let zs = plan.get("zone_summaries"),
       let s0 = zs.get("Z-C0")?.get("saved_lines")?.asU64(),
       let s2 = zs.get("Z-C2")?.get("saved_lines")?.asU64(),
       let s4 = zs.get("Z-C4")?.get("saved_lines")?.asU64()
    {
        summaryOk = (s0 == z0SavedLines && s2 == z2SavedLines && s4 == z4SavedLines)
    } else {
        summaryOk = false
    }

    let pg1ProvenanceZoneAUp08Clean = !targetRepoMutationAllowed
        && baselineCommit == bundlesSha
        && baselineCommit == zonesSha
        && !anyZoneATouch
        && !containsVerbatimProofBody(planRaw)

    let pg2Bijection137AndHashesValid = bijectionOk
        && hashesOk
        && summaryOk
        && seenPaths.count == expectedMap.count
        && entries.count == 137

    let pg3ParetoRoundtripAndBoundsValid =
        paretoAndRtOk && wrapWidth == z2WrapWidth && z2MaxLineAfter <= z2MaxLineBound

    // PG-4: Offline synthetic unified-diff & AST round-trip suite
    let syntheticTransformsPassed: Int
    let syntheticPatchSuiteSha256: String
    do {
        let res = try runSyntheticPatchSuite()
        syntheticTransformsPassed = res.0
        syntheticPatchSuiteSha256 = res.1
    } catch {
        syntheticTransformsPassed = 0
        syntheticPatchSuiteSha256 = ""
    }
    let pg4SyntheticPatchSuiteValid =
        syntheticTransformsPassed == 4 && syntheticPatchSuiteSha256.count == 64

    // PG-5: Verify all 5 clean-room Lean 4.36 `module` pre-flight files
    let leanPreflightFiles = [
        "compartments/lean/SCargoLean/Preflight/Leaf.lean",
        "compartments/lean/SCargoLean/Preflight/Mid.lean",
        "compartments/lean/SCargoLean/Preflight/WrapAlias.lean",
        "compartments/lean/SCargoLean/Preflight/HubPruned.lean",
        "compartments/lean/SCargoLean/Preflight/CompactCse.lean",
    ]
    var pg5LeanPreflightModulesValid = true
    for rel in leanPreflightFiles {
        do {
            let txt = try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
            if !txt.contains("module\n")
                || !txt.contains("@[expose] public section")
                || txt.contains("sorry")
                || txt.contains("native_decide")
            {
                pg5LeanPreflightModulesValid = false
            }
        } catch {
            pg5LeanPreflightModulesValid = false
        }
    }

    // PG-6: 7 Adversarial Negative Controls (all 7 must fail closed!)
    var negRejected = 0
    // NEG-P1: Corrupted hunk context line rejected by pure in-memory applier
    let badDiff = "--- a/X.lean\n+++ b/X.lean\n@@ -1,2 +1,1 @@\n WRONG_CONTEXT\n-line2\n"
    do {
        _ = try applyUnifiedDiff(oldSrc: "line1\nline2\n", diffText: badDiff)
    } catch {
        negRejected += 1
    }
    // NEG-P2: Layout-keyword span (`by` inside `(@...)`) rejected/skipped by Z-C2-COMPACT
    let layoutSrc = "module\ndef f : Nat := (@Field.toSemifield\n  Nat\n  by exact inst)\n"
    do {
        _ = try transformZ2BalancedCollapse(src: layoutSrc, wrapWidth: z2WrapWidth)
    } catch {
        negRejected += 1
    }
    // NEG-P3: Free local variable capture (`K`) rejected by Z-C2-CLOSED-CSE
    let freeVarExpr = "(@Field.toSemifield K (@instField K))"
    let freeVarSrc = "module\n@[expose] public section\ndef a (K : Type) := \(freeVarExpr)\ndef b (K : Type) := \(freeVarExpr)\n"
    do {
        _ = try transformZ2ClosedCse(src: freeVarSrc, targetExpr: freeVarExpr, abbrevName: "_scargo_cse_bad")
    } catch {
        negRejected += 1
    }
    // NEG-P4: Non-redundant import drop rejected by Z-C4 closure guard
    do {
        _ = try transformZ4PruneImports(
            src: "module\npublic import Core.Required\n",
            transitivelyCovered: Set<String>(),
            toPrune: ["Core.Required"]
        )
    } catch {
        negRejected += 1
    }
    // NEG-P5: Zone A protected target recognized and rejected
    if zoneAPaths.contains("src/Main.lean") {
        negRejected += 1
    }
    // NEG-P6: UP-08 verbatim proof-body leak detected
    if containsVerbatimProofBody("{\"bad\": \"private theorem leak : True := by trivial\"}") {
        negRejected += 1
    }
    // NEG-P7: Non-Pareto byte-inflating closed-CSE rewrite rejected
    let tinyExpr = "(@instAddNat)"
    let tinySrc = "module\n@[expose] public section\ndef a := \(tinyExpr)\ndef b := \(tinyExpr)\n"
    do {
        _ = try transformZ2ClosedCse(src: tinySrc, targetExpr: tinyExpr, abbrevName: "_scargo_very_long_inflating_abbrev_name")
    } catch {
        negRejected += 1
    }

    let totalNegativeControls = 7
    let pg6NegativeControlsValid = negRejected == totalNegativeControls
    let allPassed = pg1ProvenanceZoneAUp08Clean
        && pg2Bijection137AndHashesValid
        && pg3ParetoRoundtripAndBoundsValid
        && pg4SyntheticPatchSuiteValid
        && pg5LeanPreflightModulesValid
        && pg6NegativeControlsValid

    let digestSrc = "\(inputDigestsSha256)|\(syntheticPatchSuiteSha256)|F:\(entries.count)|L:\(z0SavedLines):\(z2SavedLines):\(z4SavedLines)|B:\(totalSavedBytes)|MAX:\(z2MaxLineAfter)|NEG:\(negRejected)/\(totalNegativeControls)|PASS:\(allPassed)"
    let patchDigestSha256 = patchSha256Hex(digestSrc)

    return Arc6PatchReceipt(
        patchPlanId: patchPlanId,
        baselineCommit: baselineCommit,
        targetRepoMutationAllowed: targetRepoMutationAllowed,
        pg1ProvenanceZoneAUp08Clean: pg1ProvenanceZoneAUp08Clean,
        pg2Bijection137AndHashesValid: pg2Bijection137AndHashesValid,
        pg3ParetoRoundtripAndBoundsValid: pg3ParetoRoundtripAndBoundsValid,
        pg4SyntheticPatchSuiteValid: pg4SyntheticPatchSuiteValid,
        pg5LeanPreflightModulesValid: pg5LeanPreflightModulesValid,
        pg6NegativeControlsValid: pg6NegativeControlsValid,
        totalFiles: entries.count,
        z0SavedLines: z0SavedLines,
        z2SavedLines: z2SavedLines,
        z4SavedLines: z4SavedLines,
        totalSavedLines: totalSavedLines,
        totalSavedBytes: totalSavedBytes,
        z2MaxLineAfter: z2MaxLineAfter,
        syntheticTransformsPassed: syntheticTransformsPassed,
        negativeControlsRejected: negRejected,
        totalNegativeControls: totalNegativeControls,
        syntheticPatchSuiteSha256: syntheticPatchSuiteSha256,
        inputDigestsSha256: inputDigestsSha256,
        patchDigestSha256: patchDigestSha256,
        allPassed: allPassed
    )
}
