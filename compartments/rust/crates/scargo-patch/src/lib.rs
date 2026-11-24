// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone Arc 6 Concrete AST-Aware Patch Generator (`generate`) & Pure
//! In-Memory Unified-Diff Round-Trip Verifier (`verify`) across Z-C0, Z-C2,
//! and Z-C4 (zero external dependencies; strict UP-08 zero-copy compliance).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
use std::fs;
use std::path::Path;

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256
// =============================================================================

const SHA256_K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

pub fn sha256_hex(data: &[u8]) -> String {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut padded = Vec::with_capacity(data.len() + 72);
    padded.extend_from_slice(data);
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in padded.as_chunks::<64>().0 {
        let mut w = [0u32; 64];
        for (i, word) in w.iter_mut().enumerate().take(16) {
            let j = i * 4;
            *word = u32::from_be_bytes([chunk[j], chunk[j + 1], chunk[j + 2], chunk[j + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(SHA256_K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(64);
    for word in h {
        for b in word.to_be_bytes() {
            out.push(HEX[(b >> 4) as usize] as char);
            out.push(HEX[(b & 0x0f) as usize] as char);
        }
    }
    out
}

// =============================================================================
// 2. Pure Zero-Dependency JSON Parser & Escaper
// =============================================================================

#[derive(Debug, Clone)]
pub enum JVal {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<JVal>),
    Obj(BTreeMap<String, JVal>),
}

impl JVal {
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            JVal::Bool(b) => Some(*b),
            _ => None,
        }
    }
    pub fn as_u64(&self) -> Option<u64> {
        match self {
            JVal::Num(s) => s.parse::<u64>().ok(),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            JVal::Str(s) => Some(s.as_str()),
            _ => None,
        }
    }
    pub fn as_arr(&self) -> Option<&[JVal]> {
        match self {
            JVal::Arr(a) => Some(a.as_slice()),
            _ => None,
        }
    }
    pub fn get(&self, key: &str) -> Option<&JVal> {
        match self {
            JVal::Obj(m) => m.get(key),
            _ => None,
        }
    }
}

struct JsonParser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> JsonParser<'a> {
    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() {
            self.pos += 1;
        }
    }
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }
    fn parse_val(&mut self) -> Result<JVal, String> {
        self.skip_ws();
        match self.peek() {
            Some(b'"') => self.parse_str().map(JVal::Str),
            Some(b'[') => self.parse_arr(),
            Some(b'{') => self.parse_obj(),
            Some(b't') => self.expect_lit(b"true", JVal::Bool(true)),
            Some(b'f') => self.expect_lit(b"false", JVal::Bool(false)),
            Some(b'n') => self.expect_lit(b"null", JVal::Null),
            Some(b'-') | Some(b'0'..=b'9') => self.parse_num(),
            _ => Err(format!("unexpected JSON token at byte {}", self.pos)),
        }
    }
    fn expect_lit(&mut self, lit: &[u8], val: JVal) -> Result<JVal, String> {
        if self.bytes.get(self.pos..self.pos + lit.len()) == Some(lit) {
            self.pos += lit.len();
            Ok(val)
        } else {
            Err(format!("invalid JSON literal at byte {}", self.pos))
        }
    }
    fn parse_str(&mut self) -> Result<String, String> {
        if self.peek() != Some(b'"') {
            return Err("expected quote".to_string());
        }
        self.pos += 1;
        let mut buf = Vec::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            self.pos += 1;
            if b == b'"' {
                return String::from_utf8(buf).map_err(|_| "invalid utf8 string".to_string());
            }
            if b == b'\\' {
                if self.pos >= self.bytes.len() {
                    return Err("truncated string escape".to_string());
                }
                let e = self.bytes[self.pos];
                self.pos += 1;
                match e {
                    b'"' => buf.push(b'"'),
                    b'\\' => buf.push(b'\\'),
                    b'/' => buf.push(b'/'),
                    b'b' => buf.push(0x08),
                    b'f' => buf.push(0x0c),
                    b'n' => buf.push(b'\n'),
                    b'r' => buf.push(b'\r'),
                    b't' => buf.push(b'\t'),
                    b'u' => {
                        if self.pos + 4 > self.bytes.len() {
                            return Err("truncated unicode escape".to_string());
                        }
                        let hex = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
                            .map_err(|_| "bad unicode escape")?;
                        self.pos += 4;
                        let code = u32::from_str_radix(hex, 16).map_err(|_| "bad hex escape")?;
                        if let Some(ch) = char::from_u32(code) {
                            let mut tmp = [0u8; 4];
                            buf.extend_from_slice(ch.encode_utf8(&mut tmp).as_bytes());
                        }
                    }
                    _ => return Err("unsupported escape".to_string()),
                }
            } else {
                buf.push(b);
            }
        }
        Err("unterminated JSON string".to_string())
    }
    fn parse_num(&mut self) -> Result<JVal, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        while matches!(
            self.peek(),
            Some(b'0'..=b'9') | Some(b'.') | Some(b'e') | Some(b'E') | Some(b'+') | Some(b'-')
        ) {
            self.pos += 1;
        }
        let raw = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "bad number utf8")?
            .to_string();
        if raw.is_empty() {
            return Err("empty number".to_string());
        }
        Ok(JVal::Num(raw))
    }
    fn parse_arr(&mut self) -> Result<JVal, String> {
        self.pos += 1;
        self.skip_ws();
        let mut items = Vec::new();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JVal::Arr(items));
        }
        loop {
            items.push(self.parse_val()?);
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b']') => {
                    self.pos += 1;
                    return Ok(JVal::Arr(items));
                }
                _ => return Err("expected ',' or ']'".to_string()),
            }
        }
    }
    fn parse_obj(&mut self) -> Result<JVal, String> {
        self.pos += 1;
        self.skip_ws();
        let mut map = BTreeMap::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JVal::Obj(map));
        }
        loop {
            self.skip_ws();
            let k = self.parse_str()?;
            self.skip_ws();
            if self.peek() != Some(b':') {
                return Err("expected ':'".to_string());
            }
            self.pos += 1;
            let v = self.parse_val()?;
            map.insert(k, v);
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JVal::Obj(map));
                }
                _ => return Err("expected ',' or '}'".to_string()),
            }
        }
    }
}

pub fn parse_json(input: &str) -> Result<JVal, String> {
    let mut p = JsonParser {
        bytes: input.as_bytes(),
        pos: 0,
    };
    let val = p.parse_val()?;
    p.skip_ws();
    if p.pos != p.bytes.len() {
        return Err("trailing JSON bytes".to_string());
    }
    Ok(val)
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

// =============================================================================
// 3. Pure In-Memory Unified Diff Emitter & Fail-Closed Hunk Applier
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EditBlock {
    /// 0-indexed start line in original file (inclusive)
    pub old_start: usize,
    /// 0-indexed end line in original file (exclusive)
    pub old_end: usize,
    /// Replacement lines
    pub new_lines: Vec<String>,
}

pub fn split_lf_lines(src: &str) -> Vec<&str> {
    if src.is_empty() {
        return Vec::new();
    }
    let trimmed = src.strip_suffix('\n').unwrap_or(src);
    trimmed.split('\n').collect()
}

pub fn emit_delete_unified_diff(rel_path: &str, old_src: &str) -> (String, usize) {
    let old_lines = split_lf_lines(old_src);
    let mut out = String::new();
    out.push_str(&format!("diff --git a/{0} b/{0}\n", rel_path));
    out.push_str("deleted file mode 100644\n");
    out.push_str(&format!("--- a/{}\n", rel_path));
    out.push_str("+++ /dev/null\n");
    if old_lines.is_empty() {
        return (out, 0);
    }
    out.push_str(&format!("@@ -1,{} +0,0 @@\n", old_lines.len()));
    for ln in &old_lines {
        out.push('-');
        out.push_str(ln);
        out.push('\n');
    }
    (out, 1)
}

pub fn emit_unified_diff_from_edits(
    rel_path: &str,
    old_src: &str,
    edits: &[EditBlock],
    context: usize,
) -> Result<(String, usize), String> {
    if edits.is_empty() {
        return Err("refusing to emit empty unified diff".to_string());
    }
    let old_lines = split_lf_lines(old_src);
    let mut sorted = edits.to_vec();
    sorted.sort_by_key(|e| e.old_start);
    for w in sorted.windows(2) {
        if w[0].old_end > w[1].old_start {
            return Err("overlapping edit blocks".to_string());
        }
    }
    for e in &sorted {
        if e.old_end > old_lines.len() {
            return Err("edit block exceeds source line count".to_string());
        }
    }

    // Group adjacent edits within `2 * context` lines into merged hunks
    let mut groups: Vec<Vec<&EditBlock>> = Vec::new();
    for e in &sorted {
        if let Some(last_grp) = groups.last_mut()
            && let Some(prev) = last_grp.last()
            && e.old_start <= prev.old_end.saturating_add(context * 2)
        {
            last_grp.push(e);
            continue;
        }
        groups.push(vec![e]);
    }

    let mut out = String::new();
    out.push_str(&format!("diff --git a/{0} b/{0}\n", rel_path));
    out.push_str(&format!("--- a/{}\n", rel_path));
    out.push_str(&format!("+++ b/{}\n", rel_path));

    let mut delta: isize = 0;
    let hunk_count = groups.len();
    for grp in groups {
        let first = grp[0];
        let last = grp[grp.len() - 1];
        let ctx_start = first.old_start.saturating_sub(context);
        let ctx_end = (last.old_end + context).min(old_lines.len());

        let mut old_cnt = 0usize;
        let mut new_cnt = 0usize;
        let mut body = String::new();
        let mut cur = ctx_start;
        for e in grp {
            while cur < e.old_start {
                body.push(' ');
                body.push_str(old_lines[cur]);
                body.push('\n');
                old_cnt += 1;
                new_cnt += 1;
                cur += 1;
            }
            for &rem in &old_lines[e.old_start..e.old_end] {
                body.push('-');
                body.push_str(rem);
                body.push('\n');
                old_cnt += 1;
            }
            for add in &e.new_lines {
                body.push('+');
                body.push_str(add);
                body.push('\n');
                new_cnt += 1;
            }
            cur = e.old_end;
        }
        while cur < ctx_end {
            body.push(' ');
            body.push_str(old_lines[cur]);
            body.push('\n');
            old_cnt += 1;
            new_cnt += 1;
            cur += 1;
        }

        let old_s_1 = if old_cnt == 0 { ctx_start } else { ctx_start + 1 };
        let new_s_0 = (ctx_start as isize + delta) as usize;
        let new_s_1 = if new_cnt == 0 { new_s_0 } else { new_s_0 + 1 };
        out.push_str(&format!(
            "@@ -{},{} +{},{} @@\n",
            old_s_1, old_cnt, new_s_1, new_cnt
        ));
        out.push_str(&body);
        delta += new_cnt as isize - old_cnt as isize;
    }

    Ok((out, hunk_count))
}

fn parse_hunk_range(tok: &str, prefix: char) -> Result<(usize, usize), String> {
    let rest = tok
        .strip_prefix(prefix)
        .ok_or_else(|| format!("expected '{}' in hunk range '{}'", prefix, tok))?;
    if let Some((a, b)) = rest.split_once(',') {
        let start = a.parse::<usize>().map_err(|_| "bad hunk start")?;
        let count = b.parse::<usize>().map_err(|_| "bad hunk count")?;
        Ok((start, count))
    } else {
        let start = rest.parse::<usize>().map_err(|_| "bad hunk start")?;
        Ok((start, 1))
    }
}

/// Fail-closed pure in-memory unified-diff applier (zero subprocesses).
pub fn apply_unified_diff(old_src: &str, diff_text: &str) -> Result<String, String> {
    let diff_lines = split_lf_lines(diff_text);
    if diff_lines.is_empty() {
        return Err("empty unified diff".to_string());
    }
    let old_lines = split_lf_lines(old_src);
    let mut is_delete = false;
    let mut saw_old_hdr = false;
    let mut saw_new_hdr = false;
    let mut idx = 0usize;

    while idx < diff_lines.len() {
        let ln = diff_lines[idx];
        if ln.starts_with("--- ") {
            saw_old_hdr = true;
            idx += 1;
        } else if let Some(tgt) = ln.strip_prefix("+++ ") {
            saw_new_hdr = true;
            if tgt.trim() == "/dev/null" {
                is_delete = true;
            }
            idx += 1;
            break;
        } else {
            idx += 1;
        }
    }
    if !saw_old_hdr || !saw_new_hdr {
        return Err("missing --- / +++ unified diff headers".to_string());
    }

    let mut out_lines: Vec<String> = Vec::new();
    let mut src_cursor = 0usize;
    let mut hunks_applied = 0usize;

    while idx < diff_lines.len() {
        let hdr = diff_lines[idx];
        if !hdr.starts_with("@@ ") {
            return Err(format!("expected @@ hunk header, got '{}'", hdr));
        }
        let parts: Vec<&str> = hdr.split_whitespace().collect();
        if parts.len() < 4 || parts[0] != "@@" || parts[3] != "@@" {
            return Err(format!("malformed hunk header '{}'", hdr));
        }
        let (old_s, old_c) = parse_hunk_range(parts[1], '-')?;
        let (_new_s, new_c) = parse_hunk_range(parts[2], '+')?;
        let hunk_src_start = if old_c == 0 { old_s } else { old_s.saturating_sub(1) };
        if hunk_src_start < src_cursor || hunk_src_start > old_lines.len() {
            return Err("hunk start out of bounds or overlapping".to_string());
        }
        while src_cursor < hunk_src_start {
            out_lines.push(old_lines[src_cursor].to_string());
            src_cursor += 1;
        }
        idx += 1;
        let mut seen_old = 0usize;
        let mut seen_new = 0usize;
        while idx < diff_lines.len() && !diff_lines[idx].starts_with("@@ ") {
            let row = diff_lines[idx];
            if let Some(ctx) = row.strip_prefix(' ') {
                if src_cursor >= old_lines.len() || old_lines[src_cursor] != ctx {
                    return Err(format!(
                        "context mismatch at line {}",
                        src_cursor + 1
                    ));
                }
                out_lines.push(ctx.to_string());
                src_cursor += 1;
                seen_old += 1;
                seen_new += 1;
            } else if let Some(rem) = row.strip_prefix('-') {
                if src_cursor >= old_lines.len() || old_lines[src_cursor] != rem {
                    return Err(format!(
                        "deletion mismatch at line {}",
                        src_cursor + 1
                    ));
                }
                src_cursor += 1;
                seen_old += 1;
            } else if let Some(add) = row.strip_prefix('+') {
                out_lines.push(add.to_string());
                seen_new += 1;
            } else {
                return Err(format!("invalid diff line prefix in '{}'", row));
            }
            idx += 1;
        }
        if seen_old != old_c || seen_new != new_c {
            return Err(format!(
                "hunk line count mismatch: expected -{},+{}, got -{},+{}",
                old_c, new_c, seen_old, seen_new
            ));
        }
        hunks_applied += 1;
    }

    if hunks_applied == 0 && !old_lines.is_empty() {
        return Err("no hunks applied to non-empty file".to_string());
    }
    while src_cursor < old_lines.len() {
        out_lines.push(old_lines[src_cursor].to_string());
        src_cursor += 1;
    }

    if is_delete {
        if !out_lines.is_empty() {
            return Err("delete diff left residual lines".to_string());
        }
        return Ok(String::new());
    }
    if out_lines.is_empty() {
        return Ok(String::new());
    }
    let mut joined = out_lines.join("\n");
    joined.push('\n');
    Ok(joined)
}

// =============================================================================
// 4. Shared Guards, Z-C2 Balanced-AST Collapse, Closed CSE & Z-C4 Pruner
// =============================================================================

pub const Z2_WRAP_WIDTH: usize = 160;
pub const Z2_MAX_LINE_BOUND: usize = 280;

pub fn contains_verbatim_proof_body(raw_json: &str) -> bool {
    raw_json.contains(":= by")
        || raw_json.contains("private theorem ")
        || raw_json.contains("noncomputable def ")
        || raw_json.contains("public import Mathlib")
}

pub fn delimiters_balanced(src: &str) -> bool {
    let mut paren = 0i64;
    let mut brace = 0i64;
    let mut brack = 0i64;
    let mut in_str = false;
    let bytes = src.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        if b == b'"' && (i == 0 || bytes[i - 1] != b'\\') {
            in_str = !in_str;
            i += 1;
            continue;
        }
        if !in_str {
            if b == b'-' && i + 1 < bytes.len() && bytes[i + 1] == b'-' {
                while i < bytes.len() && bytes[i] != b'\n' {
                    i += 1;
                }
                continue;
            }
            match b {
                b'(' => paren += 1,
                b')' => {
                    paren -= 1;
                    if paren < 0 {
                        return false;
                    }
                }
                b'{' => brace += 1,
                b'}' => {
                    brace -= 1;
                    if brace < 0 {
                        return false;
                    }
                }
                b'[' => brack += 1,
                b']' => {
                    brack -= 1;
                    if brack < 0 {
                        return false;
                    }
                }
                _ => {}
            }
        }
        i += 1;
    }
    paren == 0 && brace == 0 && brack == 0
}

pub fn tokens_identical(a: &str, b: &str) -> bool {
    a.split_whitespace().eq(b.split_whitespace())
}

fn is_ident_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'\''
}

pub fn span_has_target_at_head(span: &str) -> bool {
    if span.contains("@inst")
        || span.contains("@AlgebraicClosure.inst")
        || span.contains("@NumberField.inst")
        || span.contains("@ValuativeRel.inst")
    {
        return true;
    }
    let bytes = span.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'@' && i + 1 < bytes.len() && bytes[i + 1].is_ascii_uppercase() {
            let mut j = i + 1;
            while j < bytes.len() && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_') {
                j += 1;
            }
            if j + 3 < bytes.len()
                && bytes[j] == b'.'
                && bytes[j + 1] == b't'
                && bytes[j + 2] == b'o'
                && bytes[j + 3].is_ascii_uppercase()
            {
                return true;
            }
        }
        i += 1;
    }
    false
}

pub fn span_has_layout_keyword(span: &str) -> bool {
    const LAYOUT_KWS: &[&str] = &[
        "by", "do", "match", "where", "let", "have", "show", "fun", "calc", "conv", "macro",
        "syntax", "notation",
    ];
    let bytes = span.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            let start = i;
            while i < bytes.len() && is_ident_char(bytes[i]) {
                i += 1;
            }
            let prev_is_dot_or_at = start > 0 && (bytes[start - 1] == b'.' || bytes[start - 1] == b'@');
            if !prev_is_dot_or_at && let Ok(word) = std::str::from_utf8(&bytes[start..i])
                && LAYOUT_KWS.contains(&word)
            {
                return true;
            }
        } else {
            i += 1;
        }
    }
    false
}

pub fn wrap_compact_tokens(compact: &str, width: usize) -> String {
    if compact.len() <= width {
        return compact.to_string();
    }
    let mut toks = compact.split(' ');
    let first = match toks.next() {
        Some(t) => t,
        None => return String::new(),
    };
    let mut lines: Vec<String> = Vec::new();
    let mut cur = first.to_string();
    for t in toks {
        if cur.len() + 1 + t.len() <= width {
            cur.push(' ');
            cur.push_str(t);
        } else {
            lines.push(cur);
            cur = format!("  {}", t);
        }
    }
    lines.push(cur);
    lines.join("\n")
}

#[derive(Debug, Clone)]
pub struct Z2CompactOutput {
    pub after_src: String,
    pub edits: Vec<EditBlock>,
    pub collapsed_spans: usize,
    pub skipped_layout_spans: usize,
}

/// Primary Z-C2 concrete AST-aware transform: layout-free balanced `(@...)` collapse with `<= wrap_width` wrap.
pub fn transform_z2_balanced_collapse(
    src: &str,
    wrap_width: usize,
) -> Result<Z2CompactOutput, String> {
    let bytes = src.as_bytes();
    let n = bytes.len();
    let mut char_edits: Vec<(usize, usize, String)> = Vec::new();
    let mut collapsed_spans = 0usize;
    let mut skipped_layout_spans = 0usize;
    let mut i = 0usize;

    while i < n {
        if bytes[i] == b'(' {
            let mut depth = 0i64;
            let mut j = i;
            let mut unsafe_span = false;
            while j < n {
                let b = bytes[j];
                if b == b'"'
                    || b == b'`'
                    || b == b'|'
                    || (b == b'-' && j + 1 < n && bytes[j + 1] == b'-')
                    || (b == b'/' && j + 1 < n && bytes[j + 1] == b'-')
                {
                    unsafe_span = true;
                    break;
                }
                if b == b'(' {
                    depth += 1;
                } else if b == b')' {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                j += 1;
            }
            if !unsafe_span && depth == 0 && j < n {
                let span = &src[i..=j];
                let at_count = span.bytes().filter(|&b| b == b'@').count();
                if span.contains('\n') && (at_count >= 2 || span_has_target_at_head(span)) {
                    if span_has_layout_keyword(span) {
                        skipped_layout_spans += 1;
                    } else {
                        let compact = span.split_whitespace().collect::<Vec<&str>>().join(" ");
                        let wrapped = wrap_compact_tokens(&compact, wrap_width);
                        if wrapped != span {
                            char_edits.push((i, j + 1, wrapped));
                            collapsed_spans += 1;
                            i = j + 1;
                            continue;
                        }
                    }
                }
            }
        }
        i += 1;
    }

    if char_edits.is_empty() {
        return Err("no eligible layout-free multi-line @-spans found".to_string());
    }

    // Build line-start byte offsets for exact O(N) mapping to EditBlocks
    let old_lines = split_lf_lines(src);
    let mut line_starts: Vec<usize> = Vec::with_capacity(old_lines.len());
    let mut off = 0usize;
    for ln in &old_lines {
        line_starts.push(off);
        off += ln.len() + 1;
    }
    let byte_to_line = |pos: usize| -> usize {
        match line_starts.binary_search(&pos) {
            Ok(idx) => idx,
            Err(idx) => idx.saturating_sub(1),
        }
    };

    // Group char edits whose affected inclusive line ranges overlap
    struct LineGroup {
        l_start: usize,
        l_end_incl: usize,
        reps: Vec<(usize, usize, String)>,
    }
    let mut groups: Vec<LineGroup> = Vec::new();
    for (a, b, rep) in char_edits {
        let ls = byte_to_line(a);
        let le = byte_to_line(b.saturating_sub(1));
        if let Some(last) = groups.last_mut()
            && ls <= last.l_end_incl
        {
            if le > last.l_end_incl {
                last.l_end_incl = le;
            }
            last.reps.push((a, b, rep));
            continue;
        }
        groups.push(LineGroup {
            l_start: ls,
            l_end_incl: le,
            reps: vec![(a, b, rep)],
        });
    }

    let mut edits: Vec<EditBlock> = Vec::with_capacity(groups.len());
    let mut after_lines: Vec<String> = Vec::with_capacity(old_lines.len());
    let mut cur_line = 0usize;
    for grp in groups {
        while cur_line < grp.l_start {
            after_lines.push(old_lines[cur_line].to_string());
            cur_line += 1;
        }
        let seg_byte_start = line_starts[grp.l_start];
        let seg_byte_end = line_starts[grp.l_end_incl] + old_lines[grp.l_end_incl].len();
        let mut rebuilt = String::new();
        let mut rel_pos = seg_byte_start;
        for (a, b, rep) in grp.reps {
            rebuilt.push_str(&src[rel_pos..a]);
            rebuilt.push_str(&rep);
            rel_pos = b;
        }
        rebuilt.push_str(&src[rel_pos..seg_byte_end]);
        let new_lines: Vec<String> = rebuilt.split('\n').map(String::from).collect();
        for nl in &new_lines {
            after_lines.push(nl.clone());
        }
        edits.push(EditBlock {
            old_start: grp.l_start,
            old_end: grp.l_end_incl + 1,
            new_lines,
        });
        cur_line = grp.l_end_incl + 1;
    }
    while cur_line < old_lines.len() {
        after_lines.push(old_lines[cur_line].to_string());
        cur_line += 1;
    }

    let mut after_src = after_lines.join("\n");
    if src.ends_with('\n') {
        after_src.push('\n');
    }

    if !tokens_identical(src, &after_src) {
        return Err("Z-C2-COMPACT violated token-stream identity".to_string());
    }
    if !delimiters_balanced(&after_src) {
        return Err("Z-C2-COMPACT violated delimiter balance".to_string());
    }
    if after_src.len() >= src.len() {
        return Err("Z-C2-COMPACT did not strictly reduce byte mass".to_string());
    }

    Ok(Z2CompactOutput {
        after_src,
        edits,
        collapsed_spans,
        skipped_layout_spans,
    })
}

/// Count free local variables in a candidate closed `@`-instance subtree.
pub fn count_free_local_vars(expr: &str) -> usize {
    const CLOSED_GLOBALS: &[&str] = &[
        "Nat", "Int", "Rat", "Real", "Complex", "Prop", "Type", "Sort", "True", "False", "Unit",
        "PUnit", "ULift", "Fact", "Fin", "HAdd", "HMul", "HSub", "HDiv", "HPow", "HSMul", "Add",
        "Mul", "Ring", "CommRing", "Semiring", "CommSemiring", "Field", "DivisionRing",
        "Semifield", "DivisionSemiring", "AddCommMonoid", "AddCommGroup", "Module", "Algebra",
        "Padic", "PadicInt", "PadicAlgCl", "AlgebraicClosure", "NumberField",
    ];
    let bytes = expr.as_bytes();
    let mut free = BTreeSet::new();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i].is_ascii_alphabetic() || bytes[i] == b'_' {
            let start = i;
            while i < bytes.len() && is_ident_char(bytes[i]) {
                i += 1;
            }
            let prev_at_or_dot = start > 0 && (bytes[start - 1] == b'@' || bytes[start - 1] == b'.');
            if !prev_at_or_dot && let Ok(tok) = std::str::from_utf8(&bytes[start..i])
                && !CLOSED_GLOBALS.contains(&tok)
                && !tok.starts_with("inst")
            {
                free.insert(tok.to_string());
            }
        } else {
            i += 1;
        }
    }
    free.len()
}

/// Guarded closed-subtree (`0` free local variables) `abbrev` CSE rewriter (fail-closed on any free var).
pub fn transform_z2_closed_cse(
    src: &str,
    target_expr: &str,
    abbrev_name: &str,
) -> Result<(String, Vec<EditBlock>), String> {
    if !delimiters_balanced(target_expr) || span_has_layout_keyword(target_expr) {
        return Err("invalid or layout-bearing CSE target".to_string());
    }
    let fv = count_free_local_vars(target_expr);
    if fv > 0 {
        return Err(format!(
            "refusing to hoist subtree with {} free local variable(s)",
            fv
        ));
    }
    let count = src.matches(target_expr).count();
    if count < 2 {
        return Err("CSE requires >= 2 exact occurrences".to_string());
    }
    let old_lines = split_lf_lines(src);
    let anchor_idx = old_lines
        .iter()
        .position(|ln| ln.trim() == "@[expose] public section")
        .ok_or("missing @[expose] public section anchor for Lean 4.36 module CSE")?;

    let mut edits: Vec<EditBlock> = Vec::new();
    let abbrev_line = format!("abbrev {} := {}", abbrev_name, target_expr);
    edits.push(EditBlock {
        old_start: anchor_idx,
        old_end: anchor_idx + 1,
        new_lines: vec![old_lines[anchor_idx].to_string(), abbrev_line],
    });
    for (li, &ln) in old_lines.iter().enumerate() {
        if li != anchor_idx && ln.contains(target_expr) {
            edits.push(EditBlock {
                old_start: li,
                old_end: li + 1,
                new_lines: vec![ln.replace(target_expr, abbrev_name)],
            });
        }
    }

    let (diff_txt, _) = emit_unified_diff_from_edits("SyntheticCse.lean", src, &edits, 3)?;
    let after_src = apply_unified_diff(src, &diff_txt)?;
    if after_src.len() >= src.len() || !delimiters_balanced(&after_src) {
        return Err("closed CSE failed strict Pareto or delimiter check".to_string());
    }
    Ok((after_src, edits))
}

/// Concrete Z-C4 transitive `public import` pruner producing exact `EditBlock`s.
pub fn transform_z4_prune_imports(
    src: &str,
    transitively_covered: &BTreeSet<String>,
    to_prune: &BTreeSet<String>,
) -> Result<(String, Vec<EditBlock>, usize), String> {
    if to_prune.is_empty() {
        return Err("empty Z-C4 prune set".to_string());
    }
    for m in to_prune {
        if !transitively_covered.contains(m) {
            return Err(format!("refusing to prune non-redundant import '{}'", m));
        }
    }
    let old_lines = split_lf_lines(src);
    let mut edits: Vec<EditBlock> = Vec::new();
    let mut after_lines: Vec<&str> = Vec::with_capacity(old_lines.len());
    let mut pruned = 0usize;
    let mut i = 0usize;
    while i < old_lines.len() {
        let is_dropped = |ln: &str| -> bool {
            if let Some(rest) = ln.trim().strip_prefix("public import ") {
                let mod_name = rest.split_whitespace().next().unwrap_or("");
                return to_prune.contains(mod_name);
            }
            false
        };
        if is_dropped(old_lines[i]) {
            let start = i;
            while i < old_lines.len() && is_dropped(old_lines[i]) {
                pruned += 1;
                i += 1;
            }
            edits.push(EditBlock {
                old_start: start,
                old_end: i,
                new_lines: Vec::new(),
            });
        } else {
            after_lines.push(old_lines[i]);
            i += 1;
        }
    }
    if pruned != to_prune.len() {
        return Err(format!(
            "Z-C4 pruned {} lines but expected {}",
            pruned,
            to_prune.len()
        ));
    }
    let mut after_src = after_lines.join("\n");
    if src.ends_with('\n') && !after_src.is_empty() {
        after_src.push('\n');
    }
    if after_src.len() >= src.len() {
        return Err("Z-C4 prune did not strictly reduce bytes".to_string());
    }
    Ok((after_src, edits, pruned))
}

pub struct PatchEntryHashInput<'a> {
    pub path: &'a str,
    pub zone_id: &'a str,
    pub shard_id: &'a str,
    pub transform_kind: &'a str,
    pub before_sha256: &'a str,
    pub after_sha256: &'a str,
    pub unified_diff_sha256: &'a str,
    pub lines_before: u64,
    pub lines_after: u64,
    pub bytes_before: u64,
    pub bytes_after: u64,
    pub hunk_count: usize,
}

pub fn compute_patch_entry_sha256(inp: &PatchEntryHashInput<'_>) -> String {
    let s = format!(
        "{}|{}|{}|{}|{}|{}|{}|{}:{}|{}:{}|{}",
        inp.path,
        inp.zone_id,
        inp.shard_id,
        inp.transform_kind,
        inp.before_sha256,
        inp.after_sha256,
        inp.unified_diff_sha256,
        inp.lines_before,
        inp.lines_after,
        inp.bytes_before,
        inp.bytes_after,
        inp.hunk_count
    );
    sha256_hex(s.as_bytes())
}

// =============================================================================
// 5. Offline Clean-Room Synthetic Unified-Diff & AST Round-Trip Suite (PG-4)
// =============================================================================

pub fn run_synthetic_patch_suite() -> Result<(usize, String), String> {
    let mut trace = String::new();

    // 1. Z-C0 synthetic dead-leaf delete unified diff + round-trip apply
    let z0_src = "module\npublic import Base\n@[expose] public section\ntheorem deadLeaf : True := trivial\n";
    let (z0_diff, z0_hunks) = emit_delete_unified_diff("Synthetic/DeadLeaf.lean", z0_src);
    let z0_rt = apply_unified_diff(z0_src, &z0_diff)?;
    if !z0_rt.is_empty() || z0_hunks != 1 {
        return Err("synthetic Z-C0 round-trip failed".to_string());
    }
    trace.push_str(&sha256_hex(z0_diff.as_bytes()));
    trace.push(';');

    // 2. Z-C2-COMPACT synthetic multi-line @-chain collapse (<= 160 wrap) + round-trip apply + token identity
    let z2_src = "module\n@[expose] public section\ndef poly (a b c : Nat) : Nat :=\n  (@HAdd.hAdd\n    Nat\n    Nat\n    Nat\n    (@instHAdd\n      Nat\n      instAddNat)\n    (@HMul.hMul\n      Nat\n      Nat\n      Nat\n      (@instHMul\n        Nat\n        instMulNat)\n      a\n      b)\n    c)\n";
    let z2_res = transform_z2_balanced_collapse(z2_src, Z2_WRAP_WIDTH)?;
    let (z2_diff, z2_hunks) = emit_unified_diff_from_edits(
        "Synthetic/CapelliCompact.lean",
        z2_src,
        &z2_res.edits,
        3,
    )?;
    let z2_rt = apply_unified_diff(z2_src, &z2_diff)?;
    if z2_rt != z2_res.after_src || z2_hunks == 0 || !tokens_identical(z2_src, &z2_rt) {
        return Err("synthetic Z-C2-COMPACT round-trip failed".to_string());
    }
    trace.push_str(&sha256_hex(z2_diff.as_bytes()));
    trace.push(';');

    // 3. Z-C2-CLOSED-CSE synthetic 0-free-variable abbrev hoist + round-trip apply
    let closed_expr = "(@HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) Nat.zero Nat.zero) Nat.zero)";
    let z2_cse_src = format!(
        "module\n@[expose] public section\ndef e1 : Nat := {}\ndef e2 : Nat := {}\n",
        closed_expr, closed_expr
    );
    let (z2_cse_after, z2_cse_edits) =
        transform_z2_closed_cse(&z2_cse_src, closed_expr, "_scargo_cse_0")?;
    let (z2_cse_diff, z2_cse_hunks) = emit_unified_diff_from_edits(
        "Synthetic/CapelliClosedCse.lean",
        &z2_cse_src,
        &z2_cse_edits,
        3,
    )?;
    let z2_cse_rt = apply_unified_diff(&z2_cse_src, &z2_cse_diff)?;
    if z2_cse_rt != z2_cse_after || z2_cse_hunks == 0 || !z2_cse_rt.contains("abbrev _scargo_cse_0 :=") {
        return Err("synthetic Z-C2-CLOSED-CSE round-trip failed".to_string());
    }
    trace.push_str(&sha256_hex(z2_cse_diff.as_bytes()));
    trace.push(';');

    // 4. Z-C4 synthetic transitive import pruning + round-trip apply
    let z4_src = "module\npublic import SCargoLean.Preflight.Leaf\npublic import SCargoLean.Preflight.Mid\n@[expose] public section\ntheorem hub : True := trivial\n";
    let mut covered = BTreeSet::new();
    covered.insert("SCargoLean.Preflight.Leaf".to_string());
    let mut to_prune = BTreeSet::new();
    to_prune.insert("SCargoLean.Preflight.Leaf".to_string());
    let (z4_after, z4_edits, z4_pruned) =
        transform_z4_prune_imports(z4_src, &covered, &to_prune)?;
    let (z4_diff, z4_hunks) =
        emit_unified_diff_from_edits("Synthetic/HubPruned.lean", z4_src, &z4_edits, 3)?;
    let z4_rt = apply_unified_diff(z4_src, &z4_diff)?;
    if z4_rt != z4_after || z4_pruned != 1 || z4_hunks != 1 {
        return Err("synthetic Z-C4 round-trip failed".to_string());
    }
    trace.push_str(&sha256_hex(z4_diff.as_bytes()));
    trace.push(';');

    Ok((4, sha256_hex(trace.as_bytes())))
}

// =============================================================================
// 6. Read-Only Concrete Patch Plan Generator (`generate`) + Optional `--out-dir`
// =============================================================================

fn parse_import_target(trimmed: &str) -> Option<String> {
    let mut rest = trimmed;
    loop {
        if let Some(r) = rest.strip_prefix("public ") {
            rest = r.trim_start();
        } else if let Some(r) = rest.strip_prefix("private ") {
            rest = r.trim_start();
        } else if let Some(r) = rest.strip_prefix("meta ") {
            rest = r.trim_start();
        } else {
            break;
        }
    }
    let after_imp = rest.strip_prefix("import ")?;
    let mut parts = after_imp.split_whitespace();
    let first = parts.next()?;
    let target = if first == "all" { parts.next()? } else { first };
    if target.is_empty() {
        None
    } else {
        Some(target.to_string())
    }
}

fn direct_project_imports(
    src_root: &Path,
    cache: &mut HashMap<String, Vec<String>>,
    module_name: &str,
) -> Vec<String> {
    if let Some(v) = cache.get(module_name) {
        return v.clone();
    }
    let path = src_root.join(format!("{}.lean", module_name.replace('.', "/")));
    let raw = match fs::read_to_string(&path) {
        Ok(s) => s,
        Err(_) => {
            cache.insert(module_name.to_string(), Vec::new());
            return Vec::new();
        }
    };
    let mut out = Vec::new();
    for line in raw.lines() {
        let t = line.trim();
        if t.is_empty() || t == "module" || t.starts_with("--") {
            continue;
        }
        if let Some(tgt) = parse_import_target(t) {
            if tgt != "Mathlib"
                && !tgt.starts_with("Mathlib.")
                && !tgt.starts_with("Init")
                && !tgt.starts_with("Lean")
            {
                out.push(tgt);
            }
        } else {
            break;
        }
    }
    cache.insert(module_name.to_string(), out.clone());
    out
}

fn compute_z4_redundant_imports(
    src_root: &Path,
    hub_src: &str,
) -> Result<(BTreeSet<String>, BTreeSet<String>, bool), String> {
    let mut direct: Vec<String> = Vec::new();
    for ln in split_lf_lines(hub_src) {
        if let Some(rest) = ln.trim().strip_prefix("public import ") {
            let m = rest.split_whitespace().next().unwrap_or("");
            if !m.is_empty()
                && m != "Mathlib"
                && !m.starts_with("Mathlib.")
                && !m.starts_with("Init")
                && !m.starts_with("Lean")
            {
                direct.push(m.to_string());
            }
        }
    }
    let mut cache: HashMap<String, Vec<String>> = HashMap::new();
    // Depth >= 1 reachable set across all direct project imports
    let mut depth_ge1: HashSet<String> = HashSet::new();
    let mut q: VecDeque<String> = VecDeque::new();
    for m in &direct {
        for nb in direct_project_imports(src_root, &mut cache, m) {
            if depth_ge1.insert(nb.clone()) {
                q.push_back(nb);
            }
        }
    }
    while let Some(u) = q.pop_front() {
        for nb in direct_project_imports(src_root, &mut cache, &u) {
            if depth_ge1.insert(nb.clone()) {
                q.push_back(nb);
            }
        }
    }
    let mut covered: BTreeSet<String> = BTreeSet::new();
    let mut to_prune: BTreeSet<String> = BTreeSet::new();
    let mut kept: Vec<String> = Vec::new();
    let mut seen_direct: HashSet<String> = HashSet::new();
    for m in &direct {
        if !seen_direct.insert(m.clone()) || depth_ge1.contains(m) {
            covered.insert(m.clone());
            to_prune.insert(m.clone());
        } else {
            kept.push(m.clone());
        }
    }

    // Independently verify exact closure invariance: Reach(kept) == Reach(all)
    let mut reach_all: HashSet<String> = direct.iter().cloned().collect();
    reach_all.extend(depth_ge1.iter().cloned());

    let mut reach_kept: HashSet<String> = HashSet::new();
    let mut qk: VecDeque<String> = VecDeque::new();
    for m in &kept {
        if reach_kept.insert(m.clone()) {
            qk.push_back(m.clone());
        }
    }
    while let Some(u) = qk.pop_front() {
        for nb in direct_project_imports(src_root, &mut cache, &u) {
            if reach_kept.insert(nb.clone()) {
                qk.push_back(nb);
            }
        }
    }
    let closure_preserved = reach_kept == reach_all;
    Ok((covered, to_prune, closure_preserved))
}

struct GeneratedEntry {
    path: String,
    zone_id: String,
    shard_id: String,
    transform_kind: String,
    before_sha256: String,
    after_sha256: String,
    unified_diff_sha256: String,
    lines_before: u64,
    lines_after: u64,
    bytes_before: u64,
    bytes_after: u64,
    max_line_after: usize,
    hunk_count: usize,
    ast_ops_count: usize,
    skipped_layout_spans: usize,
    roundtrip_verified: bool,
    invariant_verified: bool,
    entry_sha256: String,
}

pub fn generate_arc6_patch_plan(
    scargo_root: &Path,
    riemannian_root: &Path,
    out_plan: &Path,
    materialize_dir: Option<&Path>,
) -> Result<(usize, String), String> {
    let bundles_raw = fs::read_to_string(scargo_root.join("transfer/bundles/arc5_preflight_bundles_v1.json"))
        .map_err(|e| format!("read arc5 bundles: {}", e))?;
    let inv_raw = fs::read_to_string(scargo_root.join("data/baselines/riemannian_51d9b1a280_inventory.json"))
        .map_err(|e| format!("read inventory: {}", e))?;
    let bundles = parse_json(&bundles_raw)?;
    let inv = parse_json(&inv_raw)?;

    let commit = bundles
        .get("source_repo_commit")
        .and_then(JVal::as_str)
        .ok_or("missing source_repo_commit")?
        .to_string();

    let dead_set: BTreeSet<String> = inv
        .get("import_graph")
        .and_then(|g| g.get("unreachable_project_modules"))
        .and_then(JVal::as_arr)
        .ok_or("missing unreachable_project_modules")?
        .iter()
        .filter_map(|v| v.as_str().map(|m| format!("src/{}.lean", m.replace('.', "/"))))
        .collect();

    if let Some(dir) = materialize_dir {
        fs::create_dir_all(dir).map_err(|e| format!("mkdir {}: {}", dir.display(), e))?;
    }

    let src_root = riemannian_root.join("src");
    let shard_arr = bundles
        .get("shards")
        .and_then(JVal::as_arr)
        .ok_or("missing shards")?;

    let mut entries: Vec<GeneratedEntry> = Vec::new();
    for sh in shard_arr {
        let zid = sh.get("zone_id").and_then(JVal::as_str).unwrap_or("");
        if zid != "Z-C0" && zid != "Z-C2" && zid != "Z-C4" {
            continue;
        }
        let sid = sh.get("shard_id").and_then(JVal::as_str).unwrap_or("");
        let paths: Vec<String> = sh
            .get("paths")
            .and_then(JVal::as_arr)
            .ok_or("missing shard paths")?
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect();

        for rel in paths {
            let full_path = riemannian_root.join(&rel);
            let before_src = fs::read_to_string(&full_path)
                .map_err(|e| format!("read {}: {}", full_path.display(), e))?;
            let before_sha256 = sha256_hex(before_src.as_bytes());
            let lines_before = split_lf_lines(&before_src).len() as u64;
            let bytes_before = before_src.len() as u64;

            let (transform_kind, after_src, diff_txt, hunk_count, ast_ops_count, skipped_layout_spans, invariant_verified) =
                match zid {
                    "Z-C0" => {
                        let unreachable_ok = dead_set.contains(&rel);
                        let (diff, hc) = emit_delete_unified_diff(&rel, &before_src);
                        ("dead_leaf_delete", String::new(), diff, hc, 1usize, 0usize, unreachable_ok)
                    }
                    "Z-C2" => {
                        let res = transform_z2_balanced_collapse(&before_src, Z2_WRAP_WIDTH)?;
                        let (diff, hc) = emit_unified_diff_from_edits(&rel, &before_src, &res.edits, 3)?;
                        let inv_ok = tokens_identical(&before_src, &res.after_src)
                            && delimiters_balanced(&res.after_src);
                        (
                            "z2_balanced_ast_collapse_160",
                            res.after_src,
                            diff,
                            hc,
                            res.collapsed_spans,
                            res.skipped_layout_spans,
                            inv_ok,
                        )
                    }
                    "Z-C4" => {
                        let (covered, to_prune, closure_ok) =
                            compute_z4_redundant_imports(&src_root, &before_src)?;
                        let (after, edits, pruned) =
                            transform_z4_prune_imports(&before_src, &covered, &to_prune)?;
                        let (diff, hc) = emit_unified_diff_from_edits(&rel, &before_src, &edits, 3)?;
                        (
                            "z4_transitive_import_prune",
                            after,
                            diff,
                            hc,
                            pruned,
                            0usize,
                            closure_ok,
                        )
                    }
                    _ => return Err(format!("unexpected zone '{}'", zid)),
                };

            let roundtrip_after = apply_unified_diff(&before_src, &diff_txt)?;
            let roundtrip_verified = roundtrip_after == after_src;
            if !roundtrip_verified {
                return Err(format!("round-trip mismatch on {}", rel));
            }
            if !invariant_verified {
                return Err(format!("invariant verification failed on {}", rel));
            }

            if let Some(dir) = materialize_dir {
                let safe_name = format!(
                    "{:03}_{}_{}.patch",
                    entries.len() + 1,
                    sid,
                    rel.replace('/', "__").trim_end_matches(".lean")
                );
                fs::write(dir.join(safe_name), &diff_txt)
                    .map_err(|e| format!("write patch {}: {}", rel, e))?;
            }

            let after_sha256 = sha256_hex(after_src.as_bytes());
            let unified_diff_sha256 = sha256_hex(diff_txt.as_bytes());
            let after_lines = split_lf_lines(&after_src);
            let lines_after = after_lines.len() as u64;
            let bytes_after = after_src.len() as u64;
            let max_line_after = after_lines.iter().map(|l| l.chars().count()).max().unwrap_or(0);

            let entry_sha256 = compute_patch_entry_sha256(&PatchEntryHashInput {
                path: &rel,
                zone_id: zid,
                shard_id: sid,
                transform_kind,
                before_sha256: &before_sha256,
                after_sha256: &after_sha256,
                unified_diff_sha256: &unified_diff_sha256,
                lines_before,
                lines_after,
                bytes_before,
                bytes_after,
                hunk_count,
            });

            entries.push(GeneratedEntry {
                path: rel,
                zone_id: zid.to_string(),
                shard_id: sid.to_string(),
                transform_kind: transform_kind.to_string(),
                before_sha256,
                after_sha256,
                unified_diff_sha256,
                lines_before,
                lines_after,
                bytes_before,
                bytes_after,
                max_line_after,
                hunk_count,
                ast_ops_count,
                skipped_layout_spans,
                roundtrip_verified,
                invariant_verified,
                entry_sha256,
            });
        }
    }

    // Aggregate per-zone totals
    let sum_zone = |zid: &str| -> (usize, u64, u64, u64, u64, usize) {
        let mut cnt = 0usize;
        let mut lb = 0u64;
        let mut la = 0u64;
        let mut bb = 0u64;
        let mut ba = 0u64;
        let mut ops = 0usize;
        for e in &entries {
            if e.zone_id == zid {
                cnt += 1;
                lb += e.lines_before;
                la += e.lines_after;
                bb += e.bytes_before;
                ba += e.bytes_after;
                ops += e.ast_ops_count;
            }
        }
        (cnt, lb, la, bb, ba, ops)
    };
    let (z0_n, z0_lb, z0_la, z0_bb, z0_ba, z0_ops) = sum_zone("Z-C0");
    let (z2_n, z2_lb, z2_la, z2_bb, z2_ba, z2_ops) = sum_zone("Z-C2");
    let (z4_n, z4_lb, z4_la, z4_bb, z4_ba, z4_ops) = sum_zone("Z-C4");

    let mut out = String::new();
    out.push_str("{\n");
    out.push_str("  \"schema_version\": \"1.0.0\",\n");
    out.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    out.push_str("  \"organization\": \"Ergentics\",\n");
    out.push_str("  \"tool\": \"scargo-patch/0.1.0\",\n");
    out.push_str("  \"patch_plan_id\": \"ARC6-AST-PATCH-PLAN-V1\",\n");
    out.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&commit)));
    out.push_str("  \"target_repo_mutation_allowed\": false,\n");
    out.push_str(&format!("  \"z2_wrap_width\": {},\n", Z2_WRAP_WIDTH));
    out.push_str(&format!("  \"z2_max_line_bound\": {},\n", Z2_MAX_LINE_BOUND));
    out.push_str(&format!("  \"total_files\": {},\n", entries.len()));
    out.push_str("  \"zone_summaries\": {\n");
    out.push_str(&format!(
        "    \"Z-C0\": {{\"files\": {}, \"lines_before\": {}, \"lines_after\": {}, \"saved_lines\": {}, \"bytes_before\": {}, \"bytes_after\": {}, \"saved_bytes\": {}, \"ast_ops\": {}}},\n",
        z0_n, z0_lb, z0_la, z0_lb - z0_la, z0_bb, z0_ba, z0_bb - z0_ba, z0_ops
    ));
    out.push_str(&format!(
        "    \"Z-C2\": {{\"files\": {}, \"lines_before\": {}, \"lines_after\": {}, \"saved_lines\": {}, \"bytes_before\": {}, \"bytes_after\": {}, \"saved_bytes\": {}, \"ast_ops\": {}}},\n",
        z2_n, z2_lb, z2_la, z2_lb - z2_la, z2_bb, z2_ba, z2_bb - z2_ba, z2_ops
    ));
    out.push_str(&format!(
        "    \"Z-C4\": {{\"files\": {}, \"lines_before\": {}, \"lines_after\": {}, \"saved_lines\": {}, \"bytes_before\": {}, \"bytes_after\": {}, \"saved_bytes\": {}, \"ast_ops\": {}}}\n",
        z4_n, z4_lb, z4_la, z4_lb - z4_la, z4_bb, z4_ba, z4_bb - z4_ba, z4_ops
    ));
    out.push_str("  },\n");
    out.push_str("  \"entries\": [\n");
    for (i, e) in entries.iter().enumerate() {
        let comma = if i + 1 < entries.len() { "," } else { "" };
        out.push_str(&format!(
            "    {{\"path\": {}, \"zone_id\": {}, \"shard_id\": {}, \"transform_kind\": {}, \"before_sha256\": {}, \"after_sha256\": {}, \"unified_diff_sha256\": {}, \"lines_before\": {}, \"lines_after\": {}, \"bytes_before\": {}, \"bytes_after\": {}, \"max_line_after\": {}, \"hunk_count\": {}, \"ast_ops_count\": {}, \"skipped_layout_spans\": {}, \"roundtrip_verified\": {}, \"invariant_verified\": {}, \"entry_sha256\": {}}}{}\n",
            json_escape(&e.path),
            json_escape(&e.zone_id),
            json_escape(&e.shard_id),
            json_escape(&e.transform_kind),
            json_escape(&e.before_sha256),
            json_escape(&e.after_sha256),
            json_escape(&e.unified_diff_sha256),
            e.lines_before,
            e.lines_after,
            e.bytes_before,
            e.bytes_after,
            e.max_line_after,
            e.hunk_count,
            e.ast_ops_count,
            e.skipped_layout_spans,
            e.roundtrip_verified,
            e.invariant_verified,
            json_escape(&e.entry_sha256),
            comma
        ));
    }
    out.push_str("  ]\n");
    out.push_str("}\n");

    if contains_verbatim_proof_body(&out) {
        return Err("UP-08 violation: patch plan JSON contains verbatim proof-body markers".to_string());
    }
    if let Some(parent) = out_plan.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {}", parent.display(), e))?;
    }
    fs::write(out_plan, &out).map_err(|e| format!("write {}: {}", out_plan.display(), e))?;
    Ok((entries.len(), sha256_hex(out.as_bytes())))
}

// =============================================================================
// 7. Pure Offline Arc 6 Patch Plan & Unified-Diff Verifier (`verify`, PG-1..PG-6)
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Arc6PatchReceipt {
    pub patch_plan_id: String,
    pub baseline_commit: String,
    pub target_repo_mutation_allowed: bool,
    pub pg1_provenance_zone_a_up08_clean: bool,
    pub pg2_bijection_137_and_hashes_valid: bool,
    pub pg3_pareto_roundtrip_and_bounds_valid: bool,
    pub pg4_synthetic_patch_suite_valid: bool,
    pub pg5_lean_preflight_modules_valid: bool,
    pub pg6_negative_controls_valid: bool,
    pub total_files: usize,
    pub z0_saved_lines: u64,
    pub z2_saved_lines: u64,
    pub z4_saved_lines: u64,
    pub total_saved_lines: u64,
    pub total_saved_bytes: u64,
    pub z2_max_line_after: usize,
    pub synthetic_transforms_passed: usize,
    pub negative_controls_rejected: usize,
    pub total_negative_controls: usize,
    pub synthetic_patch_suite_sha256: String,
    pub input_digests_sha256: String,
    pub patch_digest_sha256: String,
    pub all_passed: bool,
}

impl Arc6PatchReceipt {
    pub fn to_canonical_json(&self) -> String {
        format!(
            "{{\"all_passed\":{},\"baseline_commit\":\"{}\",\"input_digests_sha256\":\"{}\",\"negative_controls_rejected\":{},\"patch_digest_sha256\":\"{}\",\"patch_plan_id\":\"{}\",\"pg1_provenance_zone_a_up08_clean\":{},\"pg2_bijection_137_and_hashes_valid\":{},\"pg3_pareto_roundtrip_and_bounds_valid\":{},\"pg4_synthetic_patch_suite_valid\":{},\"pg5_lean_preflight_modules_valid\":{},\"pg6_negative_controls_valid\":{},\"synthetic_patch_suite_sha256\":\"{}\",\"synthetic_transforms_passed\":{},\"target_repo_mutation_allowed\":{},\"total_files\":{},\"total_negative_controls\":{},\"total_saved_bytes\":{},\"total_saved_lines\":{},\"z0_saved_lines\":{},\"z2_max_line_after\":{},\"z2_saved_lines\":{},\"z4_saved_lines\":{}}}",
            self.all_passed,
            self.baseline_commit,
            self.input_digests_sha256,
            self.negative_controls_rejected,
            self.patch_digest_sha256,
            self.patch_plan_id,
            self.pg1_provenance_zone_a_up08_clean,
            self.pg2_bijection_137_and_hashes_valid,
            self.pg3_pareto_roundtrip_and_bounds_valid,
            self.pg4_synthetic_patch_suite_valid,
            self.pg5_lean_preflight_modules_valid,
            self.pg6_negative_controls_valid,
            self.synthetic_patch_suite_sha256,
            self.synthetic_transforms_passed,
            self.target_repo_mutation_allowed,
            self.total_files,
            self.total_negative_controls,
            self.total_saved_bytes,
            self.total_saved_lines,
            self.z0_saved_lines,
            self.z2_max_line_after,
            self.z2_saved_lines,
            self.z4_saved_lines,
        )
    }
}

pub fn verify_arc6_patch_plan(root: &Path) -> Result<Arc6PatchReceipt, String> {
    let rel_plan = "transfer/patches/arc6_patch_plan_v1.json";
    let rel_bundles = "transfer/bundles/arc5_preflight_bundles_v1.json";
    let rel_zones = "data/manifests/transfer_zones_v1.json";

    let plan_raw = fs::read_to_string(root.join(rel_plan)).map_err(|e| format!("read {}: {}", rel_plan, e))?;
    let bundles_raw = fs::read_to_string(root.join(rel_bundles)).map_err(|e| format!("read {}: {}", rel_bundles, e))?;
    let zones_raw = fs::read_to_string(root.join(rel_zones)).map_err(|e| format!("read {}: {}", rel_zones, e))?;

    let mut dchain = String::new();
    for (label, content) in [
        (rel_plan, plan_raw.as_str()),
        (rel_bundles, bundles_raw.as_str()),
        (rel_zones, zones_raw.as_str()),
    ] {
        dchain.push_str(label);
        dchain.push(':');
        dchain.push_str(&sha256_hex(content.as_bytes()));
        dchain.push(';');
    }
    let input_digests_sha256 = sha256_hex(dchain.as_bytes());

    let plan = parse_json(&plan_raw)?;
    let bundles = parse_json(&bundles_raw)?;
    let zones = parse_json(&zones_raw)?;

    let patch_plan_id = plan
        .get("patch_plan_id")
        .and_then(JVal::as_str)
        .ok_or("missing patch_plan_id")?
        .to_string();
    let baseline_commit = plan
        .get("source_repo_commit")
        .and_then(JVal::as_str)
        .ok_or("missing source_repo_commit")?
        .to_string();
    let target_repo_mutation_allowed = plan
        .get("target_repo_mutation_allowed")
        .and_then(JVal::as_bool)
        .unwrap_or(true);
    let wrap_width = plan.get("z2_wrap_width").and_then(JVal::as_u64).unwrap_or(0) as usize;

    let bundles_sha = bundles.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let zones_sha = zones.get("baseline_commit").and_then(JVal::as_str).unwrap_or("");

    let mut zone_a_paths: BTreeSet<String> = BTreeSet::new();
    for z in zones.get("zones").and_then(JVal::as_arr).ok_or("missing zones")? {
        if z.get("id").and_then(JVal::as_str) == Some("Z-A")
            && let Some(ps) = z.get("paths").and_then(JVal::as_arr)
        {
            for p in ps {
                if let Some(s) = p.as_str() {
                    zone_a_paths.insert(s.to_string());
                }
            }
        }
    }

    // Build expected path -> (zone_id, shard_id) bijection from Arc 5 bundles for Z-C0, Z-C2, Z-C4
    let mut expected_map: BTreeMap<String, (String, String)> = BTreeMap::new();
    for sh in bundles.get("shards").and_then(JVal::as_arr).ok_or("missing shards")? {
        let zid = sh.get("zone_id").and_then(JVal::as_str).unwrap_or("");
        if zid != "Z-C0" && zid != "Z-C2" && zid != "Z-C4" {
            continue;
        }
        let sid = sh.get("shard_id").and_then(JVal::as_str).unwrap_or("");
        for p in sh.get("paths").and_then(JVal::as_arr).ok_or("missing shard paths")? {
            if let Some(s) = p.as_str() {
                expected_map.insert(s.to_string(), (zid.to_string(), sid.to_string()));
            }
        }
    }

    let entries = plan.get("entries").and_then(JVal::as_arr).ok_or("missing entries")?;
    let mut seen_paths: BTreeSet<String> = BTreeSet::new();
    let mut any_zone_a_touch = false;
    let mut bijection_ok = true;
    let mut hashes_ok = true;
    let mut pareto_and_rt_ok = true;

    let mut z0_saved_lines = 0u64;
    let mut z2_saved_lines = 0u64;
    let mut z4_saved_lines = 0u64;
    let mut total_saved_bytes = 0u64;
    let mut z2_max_line_after = 0usize;

    for e in entries {
        let path = e.get("path").and_then(JVal::as_str).unwrap_or("");
        let zid = e.get("zone_id").and_then(JVal::as_str).unwrap_or("");
        let sid = e.get("shard_id").and_then(JVal::as_str).unwrap_or("");
        let kind = e.get("transform_kind").and_then(JVal::as_str).unwrap_or("");
        let b_sha = e.get("before_sha256").and_then(JVal::as_str).unwrap_or("");
        let a_sha = e.get("after_sha256").and_then(JVal::as_str).unwrap_or("");
        let d_sha = e.get("unified_diff_sha256").and_then(JVal::as_str).unwrap_or("");
        let decl_e_sha = e.get("entry_sha256").and_then(JVal::as_str).unwrap_or("");
        let lb = e.get("lines_before").and_then(JVal::as_u64).unwrap_or(0);
        let la = e.get("lines_after").and_then(JVal::as_u64).unwrap_or(0);
        let bb = e.get("bytes_before").and_then(JVal::as_u64).unwrap_or(0);
        let ba = e.get("bytes_after").and_then(JVal::as_u64).unwrap_or(0);
        let max_la = e.get("max_line_after").and_then(JVal::as_u64).unwrap_or(0) as usize;
        let hc = e.get("hunk_count").and_then(JVal::as_u64).unwrap_or(0) as usize;
        let rt = e.get("roundtrip_verified").and_then(JVal::as_bool).unwrap_or(false);
        let inv = e.get("invariant_verified").and_then(JVal::as_bool).unwrap_or(false);

        if zone_a_paths.contains(path) {
            any_zone_a_touch = true;
        }
        if !seen_paths.insert(path.to_string()) {
            bijection_ok = false;
        }
        match expected_map.get(path) {
            Some((exp_z, exp_s)) if exp_z == zid && exp_s == sid => {}
            _ => bijection_ok = false,
        }

        let recomp = compute_patch_entry_sha256(&PatchEntryHashInput {
            path,
            zone_id: zid,
            shard_id: sid,
            transform_kind: kind,
            before_sha256: b_sha,
            after_sha256: a_sha,
            unified_diff_sha256: d_sha,
            lines_before: lb,
            lines_after: la,
            bytes_before: bb,
            bytes_after: ba,
            hunk_count: hc,
        });
        if recomp != decl_e_sha || b_sha.len() != 64 || a_sha.len() != 64 || d_sha.len() != 64 {
            hashes_ok = false;
        }

        if la >= lb || ba >= bb || hc == 0 || !rt || !inv {
            pareto_and_rt_ok = false;
        }
        if zid == "Z-C2" {
            if max_la > Z2_MAX_LINE_BOUND {
                pareto_and_rt_ok = false;
            }
            if max_la > z2_max_line_after {
                z2_max_line_after = max_la;
            }
            z2_saved_lines += lb.saturating_sub(la);
        } else if zid == "Z-C0" {
            if la != 0 || ba != 0 {
                pareto_and_rt_ok = false;
            }
            z0_saved_lines += lb.saturating_sub(la);
        } else if zid == "Z-C4" {
            z4_saved_lines += lb.saturating_sub(la);
        }
        total_saved_bytes += bb.saturating_sub(ba);
    }

    let total_saved_lines = z0_saved_lines + z2_saved_lines + z4_saved_lines;
    let summary_ok = plan
        .get("zone_summaries")
        .and_then(|zs| {
            let s0 = zs.get("Z-C0")?.get("saved_lines")?.as_u64()?;
            let s2 = zs.get("Z-C2")?.get("saved_lines")?.as_u64()?;
            let s4 = zs.get("Z-C4")?.get("saved_lines")?.as_u64()?;
            Some(s0 == z0_saved_lines && s2 == z2_saved_lines && s4 == z4_saved_lines)
        })
        .unwrap_or(false);

    let pg1_provenance_zone_a_up08_clean = !target_repo_mutation_allowed
        && baseline_commit == bundles_sha
        && baseline_commit == zones_sha
        && !any_zone_a_touch
        && !contains_verbatim_proof_body(&plan_raw);

    let pg2_bijection_137_and_hashes_valid = bijection_ok
        && hashes_ok
        && summary_ok
        && seen_paths.len() == expected_map.len()
        && entries.len() == 137;

    let pg3_pareto_roundtrip_and_bounds_valid =
        pareto_and_rt_ok && wrap_width == Z2_WRAP_WIDTH && z2_max_line_after <= Z2_MAX_LINE_BOUND;

    // PG-4: Offline synthetic unified-diff & AST round-trip suite
    let (synthetic_transforms_passed, synthetic_patch_suite_sha256) =
        run_synthetic_patch_suite().unwrap_or_default();
    let pg4_synthetic_patch_suite_valid =
        synthetic_transforms_passed == 4 && synthetic_patch_suite_sha256.len() == 64;

    // PG-5: Verify all 5 clean-room Lean 4.36 `module` pre-flight files
    let lean_preflight_files = [
        "compartments/lean/SCargoLean/Preflight/Leaf.lean",
        "compartments/lean/SCargoLean/Preflight/Mid.lean",
        "compartments/lean/SCargoLean/Preflight/WrapAlias.lean",
        "compartments/lean/SCargoLean/Preflight/HubPruned.lean",
        "compartments/lean/SCargoLean/Preflight/CompactCse.lean",
    ];
    let mut pg5_lean_preflight_modules_valid = true;
    for rel in &lean_preflight_files {
        match fs::read_to_string(root.join(rel)) {
            Ok(txt) => {
                if !txt.contains("module\n")
                    || !txt.contains("@[expose] public section")
                    || txt.contains("sorry")
                    || txt.contains("native_decide")
                {
                    pg5_lean_preflight_modules_valid = false;
                }
            }
            Err(_) => {
                pg5_lean_preflight_modules_valid = false;
            }
        }
    }

    // PG-6: 7 Adversarial Negative Controls (all 7 must fail closed!)
    let mut neg_rejected = 0usize;
    // NEG-P1: Corrupted hunk context line rejected by pure in-memory applier
    let bad_diff = "--- a/X.lean\n+++ b/X.lean\n@@ -1,2 +1,1 @@\n WRONG_CONTEXT\n-line2\n";
    if apply_unified_diff("line1\nline2\n", bad_diff).is_err() {
        neg_rejected += 1;
    }
    // NEG-P2: Layout-keyword span (`by` inside `(@...)`) rejected/skipped by Z-C2-COMPACT
    let layout_src = "module\ndef f : Nat := (@Field.toSemifield\n  Nat\n  by exact inst)\n";
    if transform_z2_balanced_collapse(layout_src, Z2_WRAP_WIDTH).is_err() {
        neg_rejected += 1;
    }
    // NEG-P3: Free local variable capture (`K`) rejected by Z-C2-CLOSED-CSE
    let free_var_expr = "(@Field.toSemifield K (@instField K))";
    let free_var_src = format!(
        "module\n@[expose] public section\ndef a (K : Type) := {}\ndef b (K : Type) := {}\n",
        free_var_expr, free_var_expr
    );
    if transform_z2_closed_cse(&free_var_src, free_var_expr, "_scargo_cse_bad").is_err() {
        neg_rejected += 1;
    }
    // NEG-P4: Non-redundant import drop rejected by Z-C4 closure guard
    let mut bad_prune = BTreeSet::new();
    bad_prune.insert("Core.Required".to_string());
    if transform_z4_prune_imports(
        "module\npublic import Core.Required\n",
        &BTreeSet::new(),
        &bad_prune,
    )
    .is_err()
    {
        neg_rejected += 1;
    }
    // NEG-P5: Zone A protected target recognized and rejected
    if zone_a_paths.contains("src/Main.lean") {
        neg_rejected += 1;
    }
    // NEG-P6: UP-08 verbatim proof-body leak detected
    if contains_verbatim_proof_body("{\"bad\": \"private theorem leak : True := by trivial\"}") {
        neg_rejected += 1;
    }
    // NEG-P7: Non-Pareto byte-inflating closed-CSE rewrite rejected
    let tiny_expr = "(@instAddNat)";
    let tiny_src = format!(
        "module\n@[expose] public section\ndef a := {}\ndef b := {}\n",
        tiny_expr, tiny_expr
    );
    if transform_z2_closed_cse(&tiny_src, tiny_expr, "_scargo_very_long_inflating_abbrev_name").is_err() {
        neg_rejected += 1;
    }

    let total_negative_controls = 7usize;
    let pg6_negative_controls_valid = neg_rejected == total_negative_controls;
    let all_passed = pg1_provenance_zone_a_up08_clean
        && pg2_bijection_137_and_hashes_valid
        && pg3_pareto_roundtrip_and_bounds_valid
        && pg4_synthetic_patch_suite_valid
        && pg5_lean_preflight_modules_valid
        && pg6_negative_controls_valid;

    let digest_src = format!(
        "{}|{}|F:{}|L:{}:{}:{}|B:{}|MAX:{}|NEG:{}/{}|PASS:{}",
        input_digests_sha256,
        synthetic_patch_suite_sha256,
        entries.len(),
        z0_saved_lines,
        z2_saved_lines,
        z4_saved_lines,
        total_saved_bytes,
        z2_max_line_after,
        neg_rejected,
        total_negative_controls,
        all_passed
    );
    let patch_digest_sha256 = sha256_hex(digest_src.as_bytes());

    Ok(Arc6PatchReceipt {
        patch_plan_id,
        baseline_commit,
        target_repo_mutation_allowed,
        pg1_provenance_zone_a_up08_clean,
        pg2_bijection_137_and_hashes_valid,
        pg3_pareto_roundtrip_and_bounds_valid,
        pg4_synthetic_patch_suite_valid,
        pg5_lean_preflight_modules_valid,
        pg6_negative_controls_valid,
        total_files: entries.len(),
        z0_saved_lines,
        z2_saved_lines,
        z4_saved_lines,
        total_saved_lines,
        total_saved_bytes,
        z2_max_line_after,
        synthetic_transforms_passed,
        negative_controls_rejected: neg_rejected,
        total_negative_controls,
        synthetic_patch_suite_sha256,
        input_digests_sha256,
        patch_digest_sha256,
        all_passed,
    })
}
