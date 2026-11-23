// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone Arc 5 Clean-Room Dual-Route UP-07 Patch Bundle Emitter (`emit`)
//! & Pre-Flight Verifier (`verify`) across Z-C0, Z-C1A, Z-C2, and Z-C4
//! (zero external dependencies; strict UP-08 compliance).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};

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
// 3. UP-07 Dual-Route Classification, UP-08 & Synthetic Rewriters (Shared Rules)
// =============================================================================

pub fn classify_up07_route(changed_roots: usize, project_ancestors: u64) -> &'static str {
    if (1..=8).contains(&changed_roots) && project_ancestors <= 2000 {
        "quick_check"
    } else {
        "full_rh_build"
    }
}

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
    for ch in src.chars() {
        match ch {
            '(' => paren += 1,
            ')' => {
                paren -= 1;
                if paren < 0 {
                    return false;
                }
            }
            '{' => brace += 1,
            '}' => {
                brace -= 1;
                if brace < 0 {
                    return false;
                }
            }
            '[' => brack += 1,
            ']' => {
                brack -= 1;
                if brack < 0 {
                    return false;
                }
            }
            _ => {}
        }
    }
    paren == 0 && brace == 0 && brack == 0
}

pub fn compute_shard_sha256(shard_id: &str, zone_id: &str, route: &str, paths: &[String]) -> String {
    let mut s = format!("{}|{}|{}|", shard_id, zone_id, route);
    for (i, p) in paths.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(p);
    }
    sha256_hex(s.as_bytes())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BinderSig {
    pub explicit_count: usize,
    pub implicit_count: usize,
    pub instance_count: usize,
    pub universe_params: usize,
}

/// Fail-closed Z-C1A synthetic in-place forwarding rewriter.
pub fn rewrite_z1a_synthetic(
    src: &str,
    wrapper_sig: BinderSig,
    target_sig: BinderSig,
    target_symbol: &str,
) -> Result<String, String> {
    if wrapper_sig != target_sig {
        return Err("binder-plicity mismatch between wrapper and target".to_string());
    }
    if wrapper_sig.universe_params > 0 {
        return Err("universe-polymorphic wrapper excluded fail-closed".to_string());
    }
    if !delimiters_balanced(src) {
        return Err("unbalanced source delimiters".to_string());
    }
    let mut out = String::new();
    let mut replaced = false;
    let mut skip_body = false;
    for line in src.lines() {
        if skip_body {
            if line.starts_with(' ') || line.starts_with('\t') {
                continue;
            }
            skip_body = false;
        }
        if line.trim_start().starts_with("theorem ") && line.contains(":= by") {
            let prefix = line.split(":= by").next().unwrap_or(line).trim_end();
            out.push_str(&format!("{} := @{}\n", prefix, target_symbol));
            replaced = true;
            skip_body = true;
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    if !replaced || !delimiters_balanced(&out) || out.len() >= src.len() {
        return Err("Z-C1A rewrite failed strict safety/size reduction check".to_string());
    }
    Ok(out)
}

/// Fail-closed Z-C2 synthetic explicit `@`-chain de-expander.
pub fn rewrite_z2_synthetic(src: &str, defeq_rfl_certified: bool) -> Result<String, String> {
    if !defeq_rfl_certified {
        return Err("defeq rfl certificate required before Z-C2 de-expansion".to_string());
    }
    if !delimiters_balanced(src) {
        return Err("unbalanced source delimiters".to_string());
    }
    let pat = "@HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c";
    if !src.contains(pat) {
        return Err("no certified explicit @-chain pattern matched".to_string());
    }
    let out = src.replace(pat, "a * b + c");
    if !delimiters_balanced(&out) || out.len() >= src.len() {
        return Err("Z-C2 rewrite failed delimiter/Pareto check".to_string());
    }
    Ok(out)
}

/// Fail-closed Z-C4 synthetic transitive `public import` pruner.
pub fn rewrite_z4_prune_redundant_imports(
    src: &str,
    transitively_covered: &BTreeSet<String>,
    to_prune: &BTreeSet<String>,
) -> Result<String, String> {
    for target in to_prune {
        if !transitively_covered.contains(target) {
            return Err(format!("refusing to prune non-redundant import '{}'", target));
        }
    }
    let mut out = String::new();
    let mut pruned = 0usize;
    for line in src.lines() {
        let t = line.trim();
        let mut drop_this = false;
        if let Some(rest) = t.strip_prefix("public import ") {
            let mod_name = rest.split_whitespace().next().unwrap_or("");
            if to_prune.contains(mod_name) {
                drop_this = true;
                pruned += 1;
            }
        }
        if !drop_this {
            out.push_str(line);
            out.push('\n');
        }
    }
    if pruned != to_prune.len() || out.len() >= src.len() {
        return Err("Z-C4 prune failed exact line-drop count or Pareto reduction".to_string());
    }
    Ok(out)
}

/// Deterministic unified-diff digest across all 4 clean-room synthetic transform emitters (EG-4).
pub fn run_synthetic_diff_suite() -> Result<(usize, String), String> {
    let mut diff_trace = String::new();

    // 1. Z-C0 synthetic delete plan
    let z0_src = "module\npublic import Base\n@[expose] public section\ntheorem unused : True := trivial\n";
    let z0_diff = format!("--- a/DeadLeaf.lean\n+++ /dev/null\n-lines:{}:bytes:{}\n", z0_src.lines().count(), z0_src.len());
    diff_trace.push_str(&sha256_hex(z0_diff.as_bytes()));
    diff_trace.push(';');

    // 2. Z-C1A synthetic in-place forwarding rewrite
    let z1a_src = "module\npublic import SCargoLean.Preflight.Leaf\n@[expose] public section\ntheorem wrap : ∀ {α : Type} (x : α), x = x := by\n  first | exact @leafIdTheorem | exact leafIdTheorem\n";
    let sig = BinderSig { explicit_count: 1, implicit_count: 1, instance_count: 0, universe_params: 0 };
    let z1a_out = rewrite_z1a_synthetic(z1a_src, sig, sig, "leafIdTheorem")?;
    if !z1a_out.contains("module\n") || !z1a_out.contains("@[expose] public section\n") {
        return Err("Z-C1A lost module header".to_string());
    }
    let z1a_diff = format!("Z1A:{}:{}:{}", z1a_src.len(), z1a_out.len(), sha256_hex(z1a_out.as_bytes()));
    diff_trace.push_str(&sha256_hex(z1a_diff.as_bytes()));
    diff_trace.push(';');

    // 3. Z-C2 synthetic explicit @-chain de-expansion
    let z2_src = "module\n@[expose] public section\ndef f (a b c : Nat) : Nat :=\n  @HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c\n";
    let z2_out = rewrite_z2_synthetic(z2_src, true)?;
    if !z2_out.contains("a * b + c") {
        return Err("Z-C2 missing clean expression".to_string());
    }
    let z2_diff = format!("Z2:{}:{}:{}", z2_src.len(), z2_out.len(), sha256_hex(z2_out.as_bytes()));
    diff_trace.push_str(&sha256_hex(z2_diff.as_bytes()));
    diff_trace.push(';');

    // 4. Z-C4 synthetic transitive import pruning
    let z4_src = "module\npublic import SCargoLean.Preflight.Leaf\npublic import SCargoLean.Preflight.Mid\n@[expose] public section\ntheorem hub : True := trivial\n";
    let mut covered = BTreeSet::new();
    covered.insert("SCargoLean.Preflight.Leaf".to_string());
    let mut to_prune = BTreeSet::new();
    to_prune.insert("SCargoLean.Preflight.Leaf".to_string());
    let z4_out = rewrite_z4_prune_redundant_imports(z4_src, &covered, &to_prune)?;
    if z4_out.contains("Preflight.Leaf") || !z4_out.contains("Preflight.Mid") {
        return Err("Z-C4 prune violated import closure".to_string());
    }
    let z4_diff = format!("Z4:{}:{}:{}", z4_src.len(), z4_out.len(), sha256_hex(z4_out.as_bytes()));
    diff_trace.push_str(&sha256_hex(z4_diff.as_bytes()));
    diff_trace.push(';');

    Ok((4, sha256_hex(diff_trace.as_bytes())))
}

// =============================================================================
// 4. Read-Only Pre-Flight Bundle Generator (`emit`)
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
    if target.is_empty() { None } else { Some(target.to_string()) }
}

fn direct_project_imports(src_root: &Path, cache: &mut HashMap<String, Vec<String>>, module_name: &str) -> Vec<String> {
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
            if tgt != "Mathlib" && !tgt.starts_with("Mathlib.") && !tgt.starts_with("Init") && !tgt.starts_with("Lean") {
                out.push(tgt);
            }
        } else {
            break;
        }
    }
    cache.insert(module_name.to_string(), out.clone());
    out
}

fn count_project_ancestors(src_root: &Path, cache: &mut HashMap<String, Vec<String>>, modules: &[String]) -> u64 {
    let mut vis: HashSet<String> = HashSet::new();
    let mut q: VecDeque<String> = VecDeque::new();
    for m in modules {
        for nb in direct_project_imports(src_root, cache, m) {
            if vis.insert(nb.clone()) {
                q.push_back(nb);
            }
        }
    }
    while let Some(u) = q.pop_front() {
        for nb in direct_project_imports(src_root, cache, &u) {
            if vis.insert(nb.clone()) {
                q.push_back(nb);
            }
        }
    }
    vis.len() as u64
}

fn collect_lean_files(dir: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    if !dir.exists() {
        return Ok(());
    }
    let mut subdirs = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = match entry { Ok(e) => e, Err(_) => continue };
        let ft = match entry.file_type() { Ok(ft) => ft, Err(_) => continue };
        let path = entry.path();
        if ft.is_dir() {
            subdirs.push(path);
        } else if ft.is_file() && path.extension().and_then(|e| e.to_str()) == Some("lean") {
            out.push(path);
        }
    }
    subdirs.sort();
    for sub in subdirs {
        collect_lean_files(&sub, out)?;
    }
    Ok(())
}

fn is_explicit_heavy_line(trimmed: &str) -> bool {
    if trimmed.starts_with("--") || trimmed.starts_with("/-") {
        return false;
    }
    let at_count = trimmed.bytes().filter(|&b| b == b'@').count();
    at_count >= 2
        || trimmed.contains("@Semifield.to")
        || trimmed.contains("@DivisionSemiring.to")
        || trimmed.contains("@Field.to")
        || trimmed.contains("@Semiring.to")
        || trimmed.contains("@CommRing.to")
        || trimmed.contains("@Ring.to")
        || trimmed.contains("@AddCommGroup.to")
        || trimmed.contains("@AlgebraicClosure.instField")
}

struct EmittedShard {
    shard_id: String,
    zone_id: String,
    kind: String,
    route: String,
    changed_roots: usize,
    project_ancestors: u64,
    estimated_saved_lines: u64,
    paths: Vec<String>,
    shard_sha256: String,
}

fn path_to_module(rel_src_path: &str) -> String {
    rel_src_path
        .strip_prefix("src/")
        .unwrap_or(rel_src_path)
        .strip_suffix(".lean")
        .unwrap_or(rel_src_path)
        .replace('/', ".")
}

pub fn emit_arc5_bundles(scargo_root: &Path, riemannian_root: &Path, out_path: &Path) -> Result<String, String> {
    let src_root = riemannian_root.join("src");
    let inv = parse_json(
        &fs::read_to_string(scargo_root.join("data/baselines/riemannian_51d9b1a280_inventory.json"))
            .map_err(|e| format!("read inv: {}", e))?,
    )?;
    let dr1 = parse_json(
        &fs::read_to_string(scargo_root.join("data/trials/dryrun_001_dead_leaves.json"))
            .map_err(|e| format!("read dr1: {}", e))?,
    )?;
    let dr2 = parse_json(
        &fs::read_to_string(scargo_root.join("data/trials/dryrun_002_rct001_wrappers.json"))
            .map_err(|e| format!("read dr2: {}", e))?,
    )?;
    let census = parse_json(
        &fs::read_to_string(scargo_root.join("data/trials/arc4_high_mass_census_v1.json"))
            .map_err(|e| format!("read census: {}", e))?,
    )?;

    let commit = inv
        .get("source_repo_commit")
        .and_then(JVal::as_str)
        .ok_or("missing commit")?
        .to_string();
    let mut cache: HashMap<String, Vec<String>> = HashMap::new();
    let mut shards: Vec<EmittedShard> = Vec::new();
    let mut full_bundles: Vec<EmittedShard> = Vec::new();

    // 1. Z-C0: 112 unreachable FlagMeasures dead leaves -> 14 shards + 1 full bundle
    let mut z0_mods: Vec<String> = inv
        .get("import_graph")
        .and_then(|g| g.get("unreachable_project_modules"))
        .and_then(JVal::as_arr)
        .ok_or("missing unreachable_project_modules")?
        .iter()
        .filter_map(|v| v.as_str().map(String::from))
        .collect();
    z0_mods.sort();
    let z0_paths: Vec<String> = z0_mods
        .iter()
        .map(|m| format!("src/{}.lean", m.replace('.', "/")))
        .collect();
    let z0_total_saved = dr1
        .get("summary")
        .and_then(|s| s.get("reclaimable_lines"))
        .and_then(JVal::as_u64)
        .unwrap_or(0);
    for (idx, chunk) in z0_paths.chunks(8).enumerate() {
        let paths = chunk.to_vec();
        let mods: Vec<String> = paths.iter().map(|p| path_to_module(p)).collect();
        let anc = count_project_ancestors(&src_root, &mut cache, &mods);
        let route = classify_up07_route(paths.len(), anc).to_string();
        let sid = format!("SHARD-ZC0-{:02}", idx + 1);
        let sha = compute_shard_sha256(&sid, "Z-C0", &route, &paths);
        let saved: u64 = paths
            .iter()
            .map(|p| {
                let rel = p.strip_prefix("src/").unwrap_or(p);
                fs::read_to_string(src_root.join(rel))
                    .map(|s| s.lines().count() as u64)
                    .unwrap_or(0)
            })
            .sum();
        shards.push(EmittedShard {
            shard_id: sid,
            zone_id: "Z-C0".to_string(),
            kind: "dead_leaf_prune".to_string(),
            route,
            changed_roots: paths.len(),
            project_ancestors: anc,
            estimated_saved_lines: saved,
            paths,
            shard_sha256: sha,
        });
    }
    let z0_full_anc = count_project_ancestors(&src_root, &mut cache, &z0_mods);
    let z0_full_route = classify_up07_route(z0_paths.len(), z0_full_anc).to_string();
    let z0_full_sha = compute_shard_sha256("BUNDLE-ZC0-FULL", "Z-C0", &z0_full_route, &z0_paths);
    full_bundles.push(EmittedShard {
        shard_id: "BUNDLE-ZC0-FULL".to_string(),
        zone_id: "Z-C0".to_string(),
        kind: "dead_leaf_prune".to_string(),
        route: z0_full_route,
        changed_roots: z0_paths.len(),
        project_ancestors: z0_full_anc,
        estimated_saved_lines: z0_total_saved,
        paths: z0_paths,
        shard_sha256: z0_full_sha,
    });

    // 2. Z-C1A: 46 Strategy A eligible pure wrappers -> 6 shards + 1 full bundle
    let mut z1a_items: Vec<(String, u64)> = Vec::new();
    for u in dr2
        .get("unit_diagnostics")
        .and_then(JVal::as_arr)
        .ok_or("missing unit_diagnostics")?
    {
        if u.get("arm").and_then(JVal::as_str) == Some("treatment")
            && u.get("strategy_a_eligible").and_then(JVal::as_bool) == Some(true)
            && let Some(m) = u.get("module").and_then(JVal::as_str)
        {
            let saved = u.get("strategy_a_saved_lines").and_then(JVal::as_u64).unwrap_or(0);
            z1a_items.push((format!("src/{}.lean", m.replace('.', "/")), saved));
        }
    }
    z1a_items.sort_by(|a, b| a.0.cmp(&b.0));
    for (idx, chunk) in z1a_items.chunks(8).enumerate() {
        let paths: Vec<String> = chunk.iter().map(|x| x.0.clone()).collect();
        let saved: u64 = chunk.iter().map(|x| x.1).sum();
        let mods: Vec<String> = paths.iter().map(|p| path_to_module(p)).collect();
        let anc = count_project_ancestors(&src_root, &mut cache, &mods);
        let route = classify_up07_route(paths.len(), anc).to_string();
        let sid = format!("SHARD-ZC1A-{:02}", idx + 1);
        let sha = compute_shard_sha256(&sid, "Z-C1A", &route, &paths);
        shards.push(EmittedShard {
            shard_id: sid,
            zone_id: "Z-C1A".to_string(),
            kind: "strategy_a_inplace_alias".to_string(),
            route,
            changed_roots: paths.len(),
            project_ancestors: anc,
            estimated_saved_lines: saved,
            paths,
            shard_sha256: sha,
        });
    }
    let z1a_paths: Vec<String> = z1a_items.iter().map(|x| x.0.clone()).collect();
    let z1a_mods: Vec<String> = z1a_paths.iter().map(|p| path_to_module(p)).collect();
    let z1a_full_anc = count_project_ancestors(&src_root, &mut cache, &z1a_mods);
    let z1a_full_route = classify_up07_route(z1a_paths.len(), z1a_full_anc).to_string();
    let z1a_full_sha = compute_shard_sha256("BUNDLE-ZC1A-FULL", "Z-C1A", &z1a_full_route, &z1a_paths);
    full_bundles.push(EmittedShard {
        shard_id: "BUNDLE-ZC1A-FULL".to_string(),
        zone_id: "Z-C1A".to_string(),
        kind: "strategy_a_inplace_alias".to_string(),
        route: z1a_full_route,
        changed_roots: z1a_paths.len(),
        project_ancestors: z1a_full_anc,
        estimated_saved_lines: z1a_items.iter().map(|x| x.1).sum(),
        paths: z1a_paths,
        shard_sha256: z1a_full_sha,
    });

    // 3. Z-C2: 24 explicit-heavy CapelliIdentities files sorted by heavy lines desc -> 3 shards + 1 full bundle
    let z2_dir = src_root.join("Development/AutomorphicArithmetic/IntegralCasts/CapelliIdentities");
    let mut z2_all = Vec::new();
    collect_lean_files(&z2_dir, &mut z2_all).map_err(|e| format!("walk z2: {}", e))?;
    let mut z2_heavy: Vec<(String, u64, u64)> = Vec::new();
    for p in z2_all {
        let rel = p.strip_prefix(&src_root).unwrap_or(&p).to_string_lossy().replace('\\', "/");
        let text = fs::read_to_string(&p).unwrap_or_default();
        let heavy = text.lines().filter(|ln| is_explicit_heavy_line(ln.trim())).count() as u64;
        if heavy >= 20 {
            z2_heavy.push((format!("src/{}", rel), heavy, (heavy * 3) / 4));
        }
    }
    z2_heavy.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    for (idx, chunk) in z2_heavy.chunks(8).enumerate() {
        let mut paths: Vec<String> = chunk.iter().map(|x| x.0.clone()).collect();
        paths.sort();
        let saved: u64 = chunk.iter().map(|x| x.2).sum();
        let mods: Vec<String> = paths.iter().map(|p| path_to_module(p)).collect();
        let anc = count_project_ancestors(&src_root, &mut cache, &mods);
        let route = classify_up07_route(paths.len(), anc).to_string();
        let sid = format!("SHARD-ZC2-{:02}", idx + 1);
        let sha = compute_shard_sha256(&sid, "Z-C2", &route, &paths);
        shards.push(EmittedShard {
            shard_id: sid,
            zone_id: "Z-C2".to_string(),
            kind: "explicit_at_deexpansion".to_string(),
            route,
            changed_roots: paths.len(),
            project_ancestors: anc,
            estimated_saved_lines: saved,
            paths,
            shard_sha256: sha,
        });
    }
    let mut z2_paths: Vec<String> = z2_heavy.iter().map(|x| x.0.clone()).collect();
    z2_paths.sort();
    let z2_mods: Vec<String> = z2_paths.iter().map(|p| path_to_module(p)).collect();
    let z2_full_anc = count_project_ancestors(&src_root, &mut cache, &z2_mods);
    let z2_full_route = classify_up07_route(z2_paths.len(), z2_full_anc).to_string();
    let z2_full_sha = compute_shard_sha256("BUNDLE-ZC2-FULL", "Z-C2", &z2_full_route, &z2_paths);
    full_bundles.push(EmittedShard {
        shard_id: "BUNDLE-ZC2-FULL".to_string(),
        zone_id: "Z-C2".to_string(),
        kind: "explicit_at_deexpansion".to_string(),
        route: z2_full_route,
        changed_roots: z2_paths.len(),
        project_ancestors: z2_full_anc,
        estimated_saved_lines: z2_heavy.iter().map(|x| x.2).sum(),
        paths: z2_paths,
        shard_sha256: z2_full_sha,
    });

    // 4. Z-C4: EveryCharacterOfLiteratureOfVWin.lean single-file transitive import hub prune
    let hub_rel = census
        .get("zone_z_c4_dominator_and_hub")
        .and_then(|z| z.get("fanout_hub"))
        .and_then(|h| h.get("path"))
        .and_then(JVal::as_str)
        .ok_or("missing hub path")?;
    let hub_saved = census
        .get("zone_z_c4_dominator_and_hub")
        .and_then(|z| z.get("fanout_hub"))
        .and_then(|h| h.get("transitively_redundant_imports"))
        .and_then(JVal::as_u64)
        .unwrap_or(0);
    let hub_paths = vec![format!("src/{}", hub_rel)];
    let hub_mods = vec![path_to_module(&hub_paths[0])];
    let hub_anc = count_project_ancestors(&src_root, &mut cache, &hub_mods);
    let hub_route = classify_up07_route(hub_paths.len(), hub_anc).to_string();
    let hub_shard_sha = compute_shard_sha256("SHARD-ZC4-01", "Z-C4", &hub_route, &hub_paths);
    shards.push(EmittedShard {
        shard_id: "SHARD-ZC4-01".to_string(),
        zone_id: "Z-C4".to_string(),
        kind: "transitive_import_hub_prune".to_string(),
        route: hub_route.clone(),
        changed_roots: 1,
        project_ancestors: hub_anc,
        estimated_saved_lines: hub_saved,
        paths: hub_paths.clone(),
        shard_sha256: hub_shard_sha,
    });
    let hub_full_sha = compute_shard_sha256("BUNDLE-ZC4-FULL", "Z-C4", &hub_route, &hub_paths);
    full_bundles.push(EmittedShard {
        shard_id: "BUNDLE-ZC4-FULL".to_string(),
        zone_id: "Z-C4".to_string(),
        kind: "transitive_import_hub_prune".to_string(),
        route: hub_route,
        changed_roots: 1,
        project_ancestors: hub_anc,
        estimated_saved_lines: hub_saved,
        paths: hub_paths,
        shard_sha256: hub_full_sha,
    });

    // Serialize declarative pre-flight bundles JSON (zero verbatim proof bodies!).
    let mut out = String::new();
    out.push_str("{\n");
    out.push_str("  \"schema_version\": \"1.0.0\",\n");
    out.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    out.push_str("  \"organization\": \"Ergentics\",\n");
    out.push_str("  \"tool\": \"scargo-emit/0.1.0\",\n");
    out.push_str("  \"bundle_suite_id\": \"ARC5-PREFLIGHT-BUNDLES-V1\",\n");
    out.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&commit)));
    out.push_str("  \"target_repo_mutation_allowed\": false,\n");
    out.push_str("  \"up07_quick_check_max_roots\": 8,\n");
    out.push_str("  \"up07_quick_check_max_ancestors\": 2000,\n");
    out.push_str("  \"shards\": [\n");
    for (i, sh) in shards.iter().enumerate() {
        let comma = if i + 1 < shards.len() { "," } else { "" };
        out.push_str(&format!(
            "    {{\"shard_id\": {}, \"zone_id\": {}, \"kind\": {}, \"route\": {}, \"changed_roots\": {}, \"project_ancestors\": {}, \"estimated_saved_lines\": {}, \"shard_sha256\": {}, \"paths\": [",
            json_escape(&sh.shard_id),
            json_escape(&sh.zone_id),
            json_escape(&sh.kind),
            json_escape(&sh.route),
            sh.changed_roots,
            sh.project_ancestors,
            sh.estimated_saved_lines,
            json_escape(&sh.shard_sha256),
        ));
        for (j, p) in sh.paths.iter().enumerate() {
            if j > 0 { out.push_str(", "); }
            out.push_str(&json_escape(p));
        }
        out.push_str(&format!("]}}{}\n", comma));
    }
    out.push_str("  ],\n");
    out.push_str("  \"full_bundles\": [\n");
    for (i, fb) in full_bundles.iter().enumerate() {
        let comma = if i + 1 < full_bundles.len() { "," } else { "" };
        out.push_str(&format!(
            "    {{\"bundle_id\": {}, \"zone_id\": {}, \"kind\": {}, \"route\": {}, \"changed_roots\": {}, \"project_ancestors\": {}, \"estimated_saved_lines\": {}, \"bundle_sha256\": {}}}{}\n",
            json_escape(&fb.shard_id),
            json_escape(&fb.zone_id),
            json_escape(&fb.kind),
            json_escape(&fb.route),
            fb.changed_roots,
            fb.project_ancestors,
            fb.estimated_saved_lines,
            json_escape(&fb.shard_sha256),
            comma
        ));
    }
    out.push_str("  ]\n");
    out.push_str("}\n");

    if contains_verbatim_proof_body(&out) {
        return Err("UP-08 violation: bundle JSON contains verbatim proof-body markers".to_string());
    }
    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {}", parent.display(), e))?;
    }
    fs::write(out_path, &out).map_err(|e| format!("write {}: {}", out_path.display(), e))?;
    Ok(sha256_hex(out.as_bytes()))
}

// =============================================================================
// 5. Pure Offline Pre-Flight Emitter Verifier (`verify`, EG-1..EG-6)
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Arc5EmitterReceipt {
    pub bundle_suite_id: String,
    pub baseline_commit: String,
    pub target_repo_mutation_allowed: bool,
    pub eg1_provenance_zone_a_up08_clean: bool,
    pub eg2_dual_route_up07_sound: bool,
    pub eg3_shard_conservation_and_hashes_valid: bool,
    pub eg4_synthetic_diffs_valid: bool,
    pub eg5_lean_preflight_modules_valid: bool,
    pub eg6_negative_controls_valid: bool,
    pub total_shards: usize,
    pub quick_check_shards: usize,
    pub full_build_shards: usize,
    pub total_full_bundles: usize,
    pub synthetic_transforms_passed: usize,
    pub negative_controls_rejected: usize,
    pub total_negative_controls: usize,
    pub synthetic_diffs_sha256: String,
    pub input_digests_sha256: String,
    pub emitter_digest_sha256: String,
    pub all_passed: bool,
}

impl Arc5EmitterReceipt {
    pub fn to_canonical_json(&self) -> String {
        format!(
            "{{\"all_passed\":{},\"baseline_commit\":\"{}\",\"bundle_suite_id\":\"{}\",\"eg1_provenance_zone_a_up08_clean\":{},\"eg2_dual_route_up07_sound\":{},\"eg3_shard_conservation_and_hashes_valid\":{},\"eg4_synthetic_diffs_valid\":{},\"eg5_lean_preflight_modules_valid\":{},\"eg6_negative_controls_valid\":{},\"emitter_digest_sha256\":\"{}\",\"full_build_shards\":{},\"input_digests_sha256\":\"{}\",\"negative_controls_rejected\":{},\"quick_check_shards\":{},\"synthetic_diffs_sha256\":\"{}\",\"synthetic_transforms_passed\":{},\"target_repo_mutation_allowed\":{},\"total_full_bundles\":{},\"total_negative_controls\":{},\"total_shards\":{}}}",
            self.all_passed,
            self.baseline_commit,
            self.bundle_suite_id,
            self.eg1_provenance_zone_a_up08_clean,
            self.eg2_dual_route_up07_sound,
            self.eg3_shard_conservation_and_hashes_valid,
            self.eg4_synthetic_diffs_valid,
            self.eg5_lean_preflight_modules_valid,
            self.eg6_negative_controls_valid,
            self.emitter_digest_sha256,
            self.full_build_shards,
            self.input_digests_sha256,
            self.negative_controls_rejected,
            self.quick_check_shards,
            self.synthetic_diffs_sha256,
            self.synthetic_transforms_passed,
            self.target_repo_mutation_allowed,
            self.total_full_bundles,
            self.total_negative_controls,
            self.total_shards,
        )
    }
}

pub fn verify_arc5_emitter(root: &Path) -> Result<Arc5EmitterReceipt, String> {
    let rel_bundles = "transfer/bundles/arc5_preflight_bundles_v1.json";
    let rel_zones = "data/manifests/transfer_zones_v1.json";
    let rel_census = "data/trials/arc4_high_mass_census_v1.json";
    let rel_dr1 = "data/trials/dryrun_001_dead_leaves.json";
    let rel_dr2 = "data/trials/dryrun_002_rct001_wrappers.json";

    let bundles_raw = fs::read_to_string(root.join(rel_bundles)).map_err(|e| format!("read {}: {}", rel_bundles, e))?;
    let zones_raw = fs::read_to_string(root.join(rel_zones)).map_err(|e| format!("read {}: {}", rel_zones, e))?;
    let census_raw = fs::read_to_string(root.join(rel_census)).map_err(|e| format!("read {}: {}", rel_census, e))?;
    let dr1_raw = fs::read_to_string(root.join(rel_dr1)).map_err(|e| format!("read {}: {}", rel_dr1, e))?;
    let dr2_raw = fs::read_to_string(root.join(rel_dr2)).map_err(|e| format!("read {}: {}", rel_dr2, e))?;

    let mut dchain = String::new();
    for (label, content) in [
        (rel_bundles, bundles_raw.as_str()),
        (rel_zones, zones_raw.as_str()),
        (rel_census, census_raw.as_str()),
        (rel_dr1, dr1_raw.as_str()),
        (rel_dr2, dr2_raw.as_str()),
    ] {
        dchain.push_str(label);
        dchain.push(':');
        dchain.push_str(&sha256_hex(content.as_bytes()));
        dchain.push(';');
    }
    let input_digests_sha256 = sha256_hex(dchain.as_bytes());

    let bundles = parse_json(&bundles_raw)?;
    let zones = parse_json(&zones_raw)?;
    let census = parse_json(&census_raw)?;
    let dr1 = parse_json(&dr1_raw)?;
    let dr2 = parse_json(&dr2_raw)?;

    let bundle_suite_id = bundles.get("bundle_suite_id").and_then(JVal::as_str).ok_or("missing bundle_suite_id")?.to_string();
    let baseline_commit = bundles.get("source_repo_commit").and_then(JVal::as_str).ok_or("missing source_repo_commit")?.to_string();
    let target_repo_mutation_allowed = bundles.get("target_repo_mutation_allowed").and_then(JVal::as_bool).unwrap_or(true);

    let zones_sha = zones.get("baseline_commit").and_then(JVal::as_str).unwrap_or("");
    let census_sha = census.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let dr1_sha = dr1.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let dr2_sha = dr2.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");

    let mut zone_a_paths = BTreeSet::new();
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

    let shard_arr = bundles.get("shards").and_then(JVal::as_arr).ok_or("missing shards")?;
    let full_arr = bundles.get("full_bundles").and_then(JVal::as_arr).ok_or("missing full_bundles")?;

    let mut any_zone_a_touch = false;
    let mut routes_ok = true;
    let mut hashes_ok = true;
    let mut quick_check_shards = 0usize;
    let mut full_build_shards = 0usize;
    let mut zone_seen: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    let mut zone_disjoint_ok = true;

    for sh in shard_arr {
        let sid = sh.get("shard_id").and_then(JVal::as_str).unwrap_or("");
        let zid = sh.get("zone_id").and_then(JVal::as_str).unwrap_or("");
        let route = sh.get("route").and_then(JVal::as_str).unwrap_or("");
        let roots = sh.get("changed_roots").and_then(JVal::as_u64).unwrap_or(0) as usize;
        let anc = sh.get("project_ancestors").and_then(JVal::as_u64).unwrap_or(0);
        let declared_sha = sh.get("shard_sha256").and_then(JVal::as_str).unwrap_or("");
        let paths: Vec<String> = sh
            .get("paths")
            .and_then(JVal::as_arr)
            .ok_or("missing shard paths")?
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect();

        if paths.len() != roots || roots == 0 || roots > 8 {
            routes_ok = false;
        }
        let expected_route = classify_up07_route(roots, anc);
        if route != expected_route {
            routes_ok = false;
        }
        if route == "quick_check" {
            quick_check_shards += 1;
        } else if route == "full_rh_build" {
            full_build_shards += 1;
        } else {
            routes_ok = false;
        }
        let recomputed_sha = compute_shard_sha256(sid, zid, route, &paths);
        if recomputed_sha != declared_sha {
            hashes_ok = false;
        }
        let set = zone_seen.entry(zid.to_string()).or_default();
        for p in &paths {
            if zone_a_paths.contains(p) {
                any_zone_a_touch = true;
            }
            if !set.insert(p.clone()) {
                zone_disjoint_ok = false;
            }
        }
    }

    for fb in full_arr {
        let route = fb.get("route").and_then(JVal::as_str).unwrap_or("");
        let roots = fb.get("changed_roots").and_then(JVal::as_u64).unwrap_or(0) as usize;
        let anc = fb.get("project_ancestors").and_then(JVal::as_u64).unwrap_or(0);
        if route != classify_up07_route(roots, anc) || route != "full_rh_build" {
            routes_ok = false;
        }
    }

    let exp_z0 = dr1.get("summary").and_then(|s| s.get("dead_modules_count")).and_then(JVal::as_u64).unwrap_or(0) as usize;
    let exp_z1a = dr2.get("treatment_dryrun_qualification").and_then(|s| s.get("strategy_a_eligible_units")).and_then(JVal::as_u64).unwrap_or(0) as usize;
    let exp_z2 = census.get("zone_z_c2_explicit_dumps").and_then(|s| s.get("explicit_heavy_files")).and_then(JVal::as_u64).unwrap_or(0) as usize;

    let z0_cnt = zone_seen.get("Z-C0").map(BTreeSet::len).unwrap_or(0);
    let z1a_cnt = zone_seen.get("Z-C1A").map(BTreeSet::len).unwrap_or(0);
    let z2_cnt = zone_seen.get("Z-C2").map(BTreeSet::len).unwrap_or(0);
    let z4_cnt = zone_seen.get("Z-C4").map(BTreeSet::len).unwrap_or(0);

    let eg1_provenance_zone_a_up08_clean = !target_repo_mutation_allowed
        && baseline_commit == zones_sha
        && baseline_commit == census_sha
        && baseline_commit == dr1_sha
        && baseline_commit == dr2_sha
        && !any_zone_a_touch
        && !contains_verbatim_proof_body(&bundles_raw);

    let eg2_dual_route_up07_sound = routes_ok && quick_check_shards >= 1 && full_build_shards >= 1 && full_arr.len() == 4;

    let eg3_shard_conservation_and_hashes_valid = zone_disjoint_ok
        && hashes_ok
        && z0_cnt == exp_z0
        && z1a_cnt == exp_z1a
        && z2_cnt == exp_z2
        && z4_cnt == 1;

    // EG-4: Synthetic deterministic diff suite across all 4 transform families
    let (synthetic_transforms_passed, synthetic_diffs_sha256) =
        run_synthetic_diff_suite().unwrap_or_default();
    let eg4_synthetic_diffs_valid = synthetic_transforms_passed == 4 && synthetic_diffs_sha256.len() == 64;

    // EG-5: Verify all 4 clean-room Lean 4.36 `module` pre-flight files exist and obey zero-sorry/zero-native_decide
    let lean_preflight_files = [
        "compartments/lean/SCargoLean/Preflight/Leaf.lean",
        "compartments/lean/SCargoLean/Preflight/Mid.lean",
        "compartments/lean/SCargoLean/Preflight/WrapAlias.lean",
        "compartments/lean/SCargoLean/Preflight/HubPruned.lean",
    ];
    let mut eg5_lean_preflight_modules_valid = true;
    for rel in &lean_preflight_files {
        match fs::read_to_string(root.join(rel)) {
            Ok(txt) => {
                if !txt.contains("module\n")
                    || !txt.contains("@[expose] public section")
                    || txt.contains("sorry")
                    || txt.contains("native_decide")
                {
                    eg5_lean_preflight_modules_valid = false;
                }
            }
            Err(_) => {
                eg5_lean_preflight_modules_valid = false;
            }
        }
    }

    // EG-6: 6 Adversarial Negative Controls (all 6 must fail closed!)
    let mut neg_rejected = 0usize;
    let sig_a = BinderSig { explicit_count: 2, implicit_count: 0, instance_count: 0, universe_params: 0 };
    let sig_b = BinderSig { explicit_count: 1, implicit_count: 1, instance_count: 0, universe_params: 0 };
    if rewrite_z1a_synthetic("theorem w := by\n  exact t\n", sig_a, sig_b, "t").is_err() {
        neg_rejected += 1;
    }
    if rewrite_z2_synthetic("def f := @HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c\n", false).is_err() {
        neg_rejected += 1;
    }
    let empty_cov = BTreeSet::new();
    let mut bad_prune = BTreeSet::new();
    bad_prune.insert("Core.Required".to_string());
    if rewrite_z4_prune_redundant_imports("module\npublic import Core.Required\n", &empty_cov, &bad_prune).is_err() {
        neg_rejected += 1;
    }
    if classify_up07_route(1, 127_439) != "quick_check" {
        neg_rejected += 1;
    }
    if zone_a_paths.contains("src/Main.lean") {
        neg_rejected += 1;
    }
    if contains_verbatim_proof_body("{\"bad\": \"private theorem leak : True := by trivial\"}") {
        neg_rejected += 1;
    }

    let total_negative_controls = 6usize;
    let eg6_negative_controls_valid = neg_rejected == total_negative_controls;
    let all_passed = eg1_provenance_zone_a_up08_clean
        && eg2_dual_route_up07_sound
        && eg3_shard_conservation_and_hashes_valid
        && eg4_synthetic_diffs_valid
        && eg5_lean_preflight_modules_valid
        && eg6_negative_controls_valid;

    let digest_src = format!(
        "{}|{}|S:{}:{}:{}|F:{}|NEG:{}/{}|PASS:{}",
        input_digests_sha256,
        synthetic_diffs_sha256,
        shard_arr.len(),
        quick_check_shards,
        full_build_shards,
        full_arr.len(),
        neg_rejected,
        total_negative_controls,
        all_passed
    );
    let emitter_digest_sha256 = sha256_hex(digest_src.as_bytes());

    Ok(Arc5EmitterReceipt {
        bundle_suite_id,
        baseline_commit,
        target_repo_mutation_allowed,
        eg1_provenance_zone_a_up08_clean,
        eg2_dual_route_up07_sound,
        eg3_shard_conservation_and_hashes_valid,
        eg4_synthetic_diffs_valid,
        eg5_lean_preflight_modules_valid,
        eg6_negative_controls_valid,
        total_shards: shard_arr.len(),
        quick_check_shards,
        full_build_shards,
        total_full_bundles: full_arr.len(),
        synthetic_transforms_passed,
        negative_controls_rejected: neg_rejected,
        total_negative_controls,
        synthetic_diffs_sha256,
        input_digests_sha256,
        emitter_digest_sha256,
        all_passed,
    })
}
