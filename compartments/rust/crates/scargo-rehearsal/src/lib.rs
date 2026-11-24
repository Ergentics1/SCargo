// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone Arc 7 G4-G5 CI Receipt Ingestor (`ingest`), Rehearsal Stager (`stage`),
//! and Pure Offline Verifier (`verify`) matching upstream `scripts/quick-check.py`,
//! `scripts/ci-build.py`, `comparator.json`, and `export-targets.txt`
//! (zero external dependencies; strict UP-08 & PRIN-06 compliance).

use std::collections::{BTreeMap, BTreeSet};
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
    pub fn as_obj(&self) -> Option<&BTreeMap<String, JVal>> {
        match self {
            JVal::Obj(m) => Some(m),
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
// 3. Pinned Upstream Constants & Shared G4/G5 Validation Primitives
// =============================================================================

pub const PINNED_BASELINE_COMMIT: &str = "51d9b1a28026d458aef9c9af3df8b083276e3d2d";
pub const PINNED_TOOLCHAIN: &str = "leanprover/lean4:v4.36.0";
pub const PINNED_LAKEFILE_SHA256: &str =
    "e12dd96eb155851de5107571dbfc959e5d9b230ead90331b4778b55b048590bb";
pub const PINNED_MANIFEST_SHA256: &str =
    "ee003c5c7a9b2b2a82a142b6633916661c07117199dd143d94d1af63910237df";
pub const PINNED_COMPARATOR_SHA256: &str =
    "8ea890e6ccda9cf3983ada343af18a41d12542036875a3936e7925ed5b1582ff";
pub const PINNED_EXPORT_TARGETS_SHA256: &str =
    "9eeb2e5e55be4a78f6e4983fc950dba915b45ad8aeb7a02a32341927a89e05e8";
pub const PINNED_TOOLCHAIN_FILE_SHA256: &str =
    "582a63f8f9c5128067b688778c1051cf1464c3ca9d57b9325025c051c29b774a";
pub const PINNED_CHALLENGE_EXPORT_SHA256: &str =
    "bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9";

pub const REQUIRED_FIVE_THEOREMS: [&str; 5] = [
    "riemannHypothesis",
    "riemannZeta_eq_zero_re",
    "LFunction_ne_zero_of_half_lt_re",
    "LFunction_eq_zero_re",
    "LFunction_eq_zero_re_of_isPrimitive",
];

pub const PERMITTED_THREE_AXIOMS: [&str; 3] = ["propext", "Quot.sound", "Classical.choice"];

pub fn is_hex_of_len(s: &str, expected_len: usize) -> bool {
    s.len() == expected_len
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

pub fn contains_verbatim_proof_body(raw_json: &str) -> bool {
    raw_json.contains(":= by")
        || raw_json.contains("private theorem ")
        || raw_json.contains("noncomputable def ")
        || raw_json.contains("public import Mathlib")
}

/// Exact upstream `scripts/quick-check.py:80` small-runner route classifier.
pub fn classify_upstream_quick_check(
    changed_roots: usize,
    closure_modules: u64,
    has_deleted_files: bool,
) -> (&'static str, Option<&'static str>) {
    if has_deleted_files {
        return ("full_rh_build", Some("deleted/unsafe source requires full build"));
    }
    if changed_roots == 0 || changed_roots > 8 {
        return ("full_rh_build", Some("more than eight changed source roots; deferred"));
    }
    if closure_modules > 2000 {
        return ("full_rh_build", Some("project ancestor cone exceeds small-runner budget"));
    }
    ("quick_check", None)
}

/// Compute exact `scripts/ci-build.py:959` canonical `input_fingerprint`.
pub fn compute_ci_input_fingerprint(
    source_tree: &str,
    lakefile_sha256: &str,
    manifest_sha256: &str,
    toolchain: &str,
) -> String {
    let canonical = format!(
        "{{\"build_roots\":{{}},\"lakefile_sha256\":\"{}\",\"manifest_sha256\":\"{}\",\"source_tree\":\"{}\",\"toolchain\":\"{}\"}}",
        lakefile_sha256, manifest_sha256, source_tree, toolchain
    );
    sha256_hex(canonical.as_bytes())
}

/// Validate a `scripts/quick-check.py` `result.json` diagnostic artifact (G4 diagnostic ONLY).
pub fn validate_quick_check_receipt(val: &JVal, expected_base_head: &str) -> Result<(), String> {
    let status = val.get("status").and_then(JVal::as_str).unwrap_or("");
    let scope = val.get("scope").and_then(JVal::as_str).unwrap_or("");
    let full_build = val.get("full_build").and_then(JVal::as_bool).unwrap_or(true);
    let exit_code = val.get("exit_code").and_then(JVal::as_u64).unwrap_or(1);
    let has_del = val
        .get("has_deleted_files")
        .and_then(JVal::as_bool)
        .unwrap_or(false);
    let base_head = val.get("base_head").and_then(JVal::as_str).unwrap_or("");
    let cand_head = val.get("candidate_head").and_then(JVal::as_str).unwrap_or("");
    let closure = val.get("ancestor_modules").and_then(JVal::as_u64).unwrap_or(u64::MAX);
    let targets = val.get("targets").and_then(JVal::as_arr).ok_or("missing targets")?;

    if scope != "changed-modules-only" {
        return Err("quick-check scope must be changed-modules-only".to_string());
    }
    if full_build {
        return Err("quick-check receipt must declare full_build=false".to_string());
    }
    if has_del {
        return Err("deleted/unsafe source requires full build (scripts/quick-check.py:80)".to_string());
    }
    if base_head != expected_base_head {
        return Err("stale base_head triggers ICD Section 4 retest".to_string());
    }
    if !is_hex_of_len(cand_head, 40) {
        return Err("invalid 40-hex candidate_head".to_string());
    }
    if targets.is_empty() || targets.len() > 8 {
        return Err("quick-check requires 1..=8 target roots".to_string());
    }
    if closure > 2000 {
        return Err("quick-check closure exceeds 2000-module budget".to_string());
    }
    if status != "changed_roots_pass" || exit_code != 0 {
        return Err(format!("quick-check did not pass: status={} exit={}", status, exit_code));
    }
    Ok(())
}

/// Validate a full `scripts/ci-build.py` `receipt.json` (G4 full build).
pub fn validate_ci_build_receipt(val: &JVal, expected_base_head: &str) -> Result<(), String> {
    let schema = val.get("schema").and_then(JVal::as_u64).unwrap_or(0);
    let full_build = val.get("full_build").and_then(JVal::as_bool).unwrap_or(true);
    let base_head = val.get("base_head").and_then(JVal::as_str).unwrap_or(expected_base_head);
    let cand_head = val.get("candidate_head").and_then(JVal::as_str).unwrap_or("");
    let cand_tree = val.get("candidate_tree").and_then(JVal::as_str).unwrap_or("");
    let src_tree = val.get("source_tree").and_then(JVal::as_str).unwrap_or("");
    let toolchain = val.get("toolchain").and_then(JVal::as_str).unwrap_or("");
    let lf_sha = val.get("lakefile_sha256").and_then(JVal::as_str).unwrap_or("");
    let mf_sha = val.get("manifest_sha256").and_then(JVal::as_str).unwrap_or("");
    let fp = val.get("input_fingerprint").and_then(JVal::as_str).unwrap_or("");
    let exit_code = val.get("build_exit_code").and_then(JVal::as_u64).unwrap_or(1);
    let map_sha = val.get("map_sha256").and_then(JVal::as_str).unwrap_or("");
    let mm_sha = val.get("module_manifest_sha256").and_then(JVal::as_str).unwrap_or("");

    if schema != 1 {
        return Err("ci-build receipt schema must equal 1".to_string());
    }
    if !full_build {
        return Err("ci-build G4/G5 receipt requires full_build=true".to_string());
    }
    if base_head != expected_base_head {
        return Err("stale base_head triggers ICD Section 4 retest".to_string());
    }
    if !is_hex_of_len(cand_head, 40) || !is_hex_of_len(cand_tree, 40) || !is_hex_of_len(src_tree, 40) {
        return Err("invalid 40-hex git identity in ci-build receipt".to_string());
    }
    if toolchain != PINNED_TOOLCHAIN {
        return Err(format!("toolchain mismatch: got '{}'", toolchain));
    }
    if lf_sha != PINNED_LAKEFILE_SHA256 {
        return Err("Zone A drift: lakefile_sha256 mismatch".to_string());
    }
    if mf_sha != PINNED_MANIFEST_SHA256 {
        return Err("Zone A drift: manifest_sha256 mismatch".to_string());
    }
    let expected_fp = compute_ci_input_fingerprint(src_tree, lf_sha, mf_sha, toolchain);
    if fp != expected_fp {
        return Err("ci-build input_fingerprint recomputation mismatch".to_string());
    }
    if exit_code != 0 {
        return Err(format!("ci-build failed with exit code {}", exit_code));
    }
    if !is_hex_of_len(map_sha, 64) || !is_hex_of_len(mm_sha, 64) {
        return Err("invalid 64-hex map_sha256 or module_manifest_sha256".to_string());
    }
    Ok(())
}

/// Validate a G5 Comparator + dual-kernel + `#print axioms` receipt (`UP-01`..`UP-03`, `PRIN-06`).
pub fn validate_g5_comparator_receipt(
    val: &JVal,
    require_remote_attestation: bool,
) -> Result<(), String> {
    let full_build = val.get("full_build").and_then(JVal::as_bool).unwrap_or(false);
    let challenge_mod = val.get("challenge_module").and_then(JVal::as_str).unwrap_or("");
    let solution_mod = val.get("solution_module").and_then(JVal::as_str).unwrap_or("");
    let lk_exit = val.get("lean_kernel_exit").and_then(JVal::as_u64).unwrap_or(1);
    let lp_exit = val.get("leanchecker_paranoid_exit").and_then(JVal::as_u64).unwrap_or(1);
    let nanoda_exit = val.get("nanoda_exit").and_then(JVal::as_u64).unwrap_or(1);
    let ch_exp = val.get("challenge_export_sha256").and_then(JVal::as_str).unwrap_or("");
    let sol_exp = val.get("solution_export_sha256").and_then(JVal::as_str).unwrap_or("");
    let rehearsal_mode = val.get("rehearsal_mode").and_then(JVal::as_bool).unwrap_or(false);
    let remote_attested = val.get("remote_ci_attestation").and_then(JVal::as_bool).unwrap_or(false);
    let remote_run_id = val.get("remote_workflow_run_id").and_then(JVal::as_u64).unwrap_or(0);

    if !full_build {
        return Err("quick-check (full_build=false) cannot attest G5 release".to_string());
    }
    if rehearsal_mode && remote_attested {
        return Err("PRIN-06 violation: rehearsal fixture cannot spoof remote_ci_attestation=true".to_string());
    }
    if require_remote_attestation && (!remote_attested || remote_run_id == 0) {
        return Err("live G5 promotion requires genuine remote_ci_attestation=true and run_id > 0".to_string());
    }
    if challenge_mod != "Challenge" || solution_mod != "Main" {
        return Err("comparator modules must be Challenge and Main".to_string());
    }
    if lk_exit != 0 || lp_exit != 0 || nanoda_exit != 0 {
        return Err(format!(
            "G5 kernel check failed: lean={}, paranoid={}, nanoda={}",
            lk_exit, lp_exit, nanoda_exit
        ));
    }
    if ch_exp != PINNED_CHALLENGE_EXPORT_SHA256 || !is_hex_of_len(sol_exp, 64) {
        return Err("invalid challenge or solution export SHA-256".to_string());
    }

    let thms = val.get("theorem_names").and_then(JVal::as_arr).ok_or("missing theorem_names")?;
    let thm_set: BTreeSet<&str> = thms.iter().filter_map(JVal::as_str).collect();
    for req in REQUIRED_FIVE_THEOREMS {
        if !thm_set.contains(req) {
            return Err(format!("missing required Challenge theorem '{}'", req));
        }
    }

    let ax_map = val
        .get("theorem_axioms")
        .and_then(JVal::as_obj)
        .ok_or("missing theorem_axioms map")?;
    let permitted: BTreeSet<&str> = PERMITTED_THREE_AXIOMS.iter().copied().collect();
    for req in REQUIRED_FIVE_THEOREMS {
        let arr = ax_map
            .get(req)
            .and_then(JVal::as_arr)
            .ok_or_else(|| format!("missing #print axioms list for '{}'", req))?;
        for ax in arr {
            let name = ax.as_str().ok_or("non-string axiom entry")?;
            if !permitted.contains(name) {
                return Err(format!("UP-02 violation: forbidden axiom '{}' on '{}'", name, req));
            }
        }
    }
    Ok(())
}

// =============================================================================
// 4. Read-Only Rehearsal Stager (`stage`)
// =============================================================================

pub fn stage_arc7_rehearsal(
    scargo_root: &Path,
    riemannian_root: &Path,
    out_path: &Path,
) -> Result<String, String> {
    let bundles = parse_json(
        &fs::read_to_string(scargo_root.join("transfer/bundles/arc5_preflight_bundles_v1.json"))
            .map_err(|e| format!("read arc5 bundles: {}", e))?,
    )?;
    let patch_plan = parse_json(
        &fs::read_to_string(scargo_root.join("transfer/patches/arc6_patch_plan_v1.json"))
            .map_err(|e| format!("read arc6 patch plan: {}", e))?,
    )?;

    // Read-only SHA-256 verification of the 5 live Zone A baseline files
    let lf_sha = sha256_hex(
        &fs::read(riemannian_root.join("lakefile.toml")).map_err(|e| format!("read lakefile: {}", e))?,
    );
    let mf_sha = sha256_hex(
        &fs::read(riemannian_root.join("lake-manifest.json"))
            .map_err(|e| format!("read manifest: {}", e))?,
    );
    let cmp_sha = sha256_hex(
        &fs::read(riemannian_root.join("comparator.json"))
            .map_err(|e| format!("read comparator: {}", e))?,
    );
    let exp_sha = sha256_hex(
        &fs::read(riemannian_root.join("export-targets.txt"))
            .map_err(|e| format!("read export-targets: {}", e))?,
    );
    let tc_sha = sha256_hex(
        &fs::read(riemannian_root.join("lean-toolchain"))
            .map_err(|e| format!("read lean-toolchain: {}", e))?,
    );
    let tc_text = fs::read_to_string(riemannian_root.join("lean-toolchain"))
        .map_err(|e| format!("read lean-toolchain text: {}", e))?
        .trim()
        .to_string();

    if lf_sha != PINNED_LAKEFILE_SHA256
        || mf_sha != PINNED_MANIFEST_SHA256
        || cmp_sha != PINNED_COMPARATOR_SHA256
        || exp_sha != PINNED_EXPORT_TARGETS_SHA256
        || tc_sha != PINNED_TOOLCHAIN_FILE_SHA256
        || tc_text != PINNED_TOOLCHAIN
    {
        return Err("live Riemannian Zone A files drifted from pinned 51d9b1a280 baseline".to_string());
    }

    let total_files = patch_plan.get("total_files").and_then(JVal::as_u64).unwrap_or(0);
    let zs = patch_plan.get("zone_summaries").ok_or("missing zone_summaries")?;
    let z0_sl = zs.get("Z-C0").and_then(|z| z.get("saved_lines")).and_then(JVal::as_u64).unwrap_or(0);
    let z2_sl = zs.get("Z-C2").and_then(|z| z.get("saved_lines")).and_then(JVal::as_u64).unwrap_or(0);
    let z4_sl = zs.get("Z-C4").and_then(|z| z.get("saved_lines")).and_then(JVal::as_u64).unwrap_or(0);
    let z0_sb = zs.get("Z-C0").and_then(|z| z.get("saved_bytes")).and_then(JVal::as_u64).unwrap_or(0);
    let z2_sb = zs.get("Z-C2").and_then(|z| z.get("saved_bytes")).and_then(JVal::as_u64).unwrap_or(0);
    let z4_sb = zs.get("Z-C4").and_then(|z| z.get("saved_bytes")).and_then(JVal::as_u64).unwrap_or(0);

    // Map per-shard concrete Arc 6 saved lines & bytes
    let mut shard_saved: BTreeMap<String, (u64, u64)> = BTreeMap::new();
    for e in patch_plan.get("entries").and_then(JVal::as_arr).ok_or("missing entries")? {
        let sid = e.get("shard_id").and_then(JVal::as_str).unwrap_or("").to_string();
        let sl = e.get("lines_before").and_then(JVal::as_u64).unwrap_or(0)
            .saturating_sub(e.get("lines_after").and_then(JVal::as_u64).unwrap_or(0));
        let sb = e.get("bytes_before").and_then(JVal::as_u64).unwrap_or(0)
            .saturating_sub(e.get("bytes_after").and_then(JVal::as_u64).unwrap_or(0));
        let cur = shard_saved.entry(sid).or_insert((0, 0));
        cur.0 += sl;
        cur.1 += sb;
    }

    struct RoutingRow {
        shard_id: String,
        zone_id: String,
        changed_roots: usize,
        closure_modules: u64,
        has_deleted_files: bool,
        ci_route: String,
        deferral_reason: String,
        saved_lines: u64,
        saved_bytes: u64,
        targets: Vec<String>,
    }

    let mut rows: Vec<RoutingRow> = Vec::new();
    for sh in bundles.get("shards").and_then(JVal::as_arr).ok_or("missing shards")? {
        let zid = sh.get("zone_id").and_then(JVal::as_str).unwrap_or("");
        if zid != "Z-C0" && zid != "Z-C2" && zid != "Z-C4" {
            continue;
        }
        let sid = sh.get("shard_id").and_then(JVal::as_str).unwrap_or("").to_string();
        let roots = sh.get("changed_roots").and_then(JVal::as_u64).unwrap_or(0) as usize;
        let anc = sh.get("project_ancestors").and_then(JVal::as_u64).unwrap_or(0);
        let closure = anc + roots as u64;
        let has_del = zid == "Z-C0";
        let (route, reason) = classify_upstream_quick_check(roots, closure, has_del);
        let (sl, sb) = shard_saved.get(&sid).copied().unwrap_or((0, 0));
        let targets: Vec<String> = sh
            .get("paths")
            .and_then(JVal::as_arr)
            .ok_or("missing shard paths")?
            .iter()
            .filter_map(|v| {
                v.as_str().map(|p| {
                    p.strip_prefix("src/")
                        .unwrap_or(p)
                        .strip_suffix(".lean")
                        .unwrap_or(p)
                        .replace('/', ".")
                })
            })
            .collect();
        rows.push(RoutingRow {
            shard_id: sid,
            zone_id: zid.to_string(),
            changed_roots: roots,
            closure_modules: closure,
            has_deleted_files: has_del,
            ci_route: route.to_string(),
            deferral_reason: reason.unwrap_or("").to_string(),
            saved_lines: sl,
            saved_bytes: sb,
            targets,
        });
    }

    // Build deterministic rehearsed git SHAs (clearly synthetic SHA-256 prefixes!)
    let rehearse_head = &sha256_hex(b"SCARGO-ARC7-REHEARSAL-CANDIDATE-HEAD-V1")[..40];
    let rehearse_tree = &sha256_hex(b"SCARGO-ARC7-REHEARSAL-CANDIDATE-TREE-V1")[..40];
    let rehearse_src_tree = &sha256_hex(b"SCARGO-ARC7-REHEARSAL-SOURCE-TREE-V1")[..40];
    let rehearse_fp = compute_ci_input_fingerprint(rehearse_src_tree, &lf_sha, &mf_sha, PINNED_TOOLCHAIN);
    let rehearse_map_sha = sha256_hex(b"SCARGO-ARC7-REHEARSAL-MAP-SHA-V1");
    let rehearse_mm_sha = sha256_hex(b"SCARGO-ARC7-REHEARSAL-MODULE-MANIFEST-V1");
    let rehearse_sol_export = sha256_hex(b"SCARGO-ARC7-REHEARSAL-SOLUTION-EXPORT-V1");

    let mut out = String::new();
    out.push_str("{\n");
    out.push_str("  \"schema_version\": \"1.0.0\",\n");
    out.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    out.push_str("  \"organization\": \"Ergentics\",\n");
    out.push_str("  \"tool\": \"scargo-rehearsal/0.1.0\",\n");
    out.push_str("  \"rehearsal_suite_id\": \"ARC7-G4-G5-REHEARSAL-V1\",\n");
    out.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(PINNED_BASELINE_COMMIT)));
    out.push_str("  \"rehearsal_mode\": true,\n");
    out.push_str("  \"remote_ci_attestation\": false,\n");
    out.push_str("  \"target_repo_mutation_allowed\": false,\n");
    out.push_str("  \"zone_a_pins\": {\n");
    out.push_str(&format!("    \"toolchain\": {},\n", json_escape(PINNED_TOOLCHAIN)));
    out.push_str(&format!("    \"lakefile_sha256\": {},\n", json_escape(&lf_sha)));
    out.push_str(&format!("    \"manifest_sha256\": {},\n", json_escape(&mf_sha)));
    out.push_str(&format!("    \"comparator_sha256\": {},\n", json_escape(&cmp_sha)));
    out.push_str(&format!("    \"export_targets_sha256\": {},\n", json_escape(&exp_sha)));
    out.push_str(&format!("    \"lean_toolchain_sha256\": {}\n", json_escape(&tc_sha)));
    out.push_str("  },\n");
    out.push_str("  \"arc6_dataset_summary\": {\n");
    out.push_str(&format!("    \"total_files\": {},\n", total_files));
    out.push_str(&format!("    \"total_saved_lines\": {},\n", z0_sl + z2_sl + z4_sl));
    out.push_str(&format!("    \"total_saved_bytes\": {},\n", z0_sb + z2_sb + z4_sb));
    out.push_str(&format!("    \"z0_saved_lines\": {},\n", z0_sl));
    out.push_str(&format!("    \"z2_saved_lines\": {},\n", z2_sl));
    out.push_str(&format!("    \"z4_saved_lines\": {}\n", z4_sl));
    out.push_str("  },\n");
    out.push_str("  \"refined_shard_routing\": [\n");
    for (i, r) in rows.iter().enumerate() {
        let comma = if i + 1 < rows.len() { "," } else { "" };
        out.push_str(&format!(
            "    {{\"shard_id\": {}, \"zone_id\": {}, \"changed_roots\": {}, \"closure_modules\": {}, \"has_deleted_files\": {}, \"ci_route\": {}, \"deferral_reason\": {}, \"saved_lines\": {}, \"saved_bytes\": {}}}{}\n",
            json_escape(&r.shard_id),
            json_escape(&r.zone_id),
            r.changed_roots,
            r.closure_modules,
            r.has_deleted_files,
            json_escape(&r.ci_route),
            json_escape(&r.deferral_reason),
            r.saved_lines,
            r.saved_bytes,
            comma
        ));
    }
    out.push_str("  ],\n");

    // Rehearsed G4 quick-check diagnostic receipts (ONLY for the 3 Z-C2 in-place shards!)
    let qc_rows: Vec<&RoutingRow> = rows.iter().filter(|r| r.ci_route == "quick_check").collect();
    out.push_str("  \"rehearsed_quick_check_receipts\": [\n");
    for (i, r) in qc_rows.iter().enumerate() {
        let comma = if i + 1 < qc_rows.len() { "," } else { "" };
        out.push_str(&format!(
            "    {{\"shard_id\": {}, \"rehearsal_mode\": true, \"remote_ci_attestation\": false, \"status\": \"changed_roots_pass\", \"scope\": \"changed-modules-only\", \"full_build\": false, \"exit_code\": 0, \"has_deleted_files\": false, \"base_head\": {}, \"candidate_head\": {}, \"ancestor_modules\": {}, \"raw_work_source_tree\": {}, \"raw_work_uploaded\": false, \"runner_name\": \"rehearsal-small-runner\", \"targets\": [",
            json_escape(&r.shard_id),
            json_escape(PINNED_BASELINE_COMMIT),
            json_escape(rehearse_head),
            r.closure_modules,
            json_escape(rehearse_src_tree),
        ));
        for (j, t) in r.targets.iter().enumerate() {
            if j > 0 {
                out.push_str(", ");
            }
            out.push_str(&json_escape(t));
        }
        out.push_str(&format!("]}}{}\n", comma));
    }
    out.push_str("  ],\n");

    // Rehearsed G4 full ci-build.py receipt.json
    out.push_str("  \"rehearsed_ci_build_receipt\": {\n");
    out.push_str("    \"schema\": 1,\n");
    out.push_str("    \"rehearsal_mode\": true,\n");
    out.push_str("    \"remote_ci_attestation\": false,\n");
    out.push_str("    \"full_build\": true,\n");
    out.push_str(&format!("    \"base_head\": {},\n", json_escape(PINNED_BASELINE_COMMIT)));
    out.push_str(&format!("    \"candidate_head\": {},\n", json_escape(rehearse_head)));
    out.push_str(&format!("    \"candidate_tree\": {},\n", json_escape(rehearse_tree)));
    out.push_str(&format!("    \"source_tree\": {},\n", json_escape(rehearse_src_tree)));
    out.push_str(&format!("    \"toolchain\": {},\n", json_escape(PINNED_TOOLCHAIN)));
    out.push_str(&format!("    \"lakefile_sha256\": {},\n", json_escape(&lf_sha)));
    out.push_str(&format!("    \"manifest_sha256\": {},\n", json_escape(&mf_sha)));
    out.push_str(&format!("    \"input_fingerprint\": {},\n", json_escape(&rehearse_fp)));
    out.push_str("    \"build_exit_code\": 0,\n");
    out.push_str(&format!("    \"map_sha256\": {},\n", json_escape(&rehearse_map_sha)));
    out.push_str(&format!("    \"module_manifest_sha256\": {},\n", json_escape(&rehearse_mm_sha)));
    out.push_str("    \"module_manifest_bytes\": 9842100\n");
    out.push_str("  },\n");

    // Rehearsed G5 comparator + dual-kernel + #print axioms receipt
    out.push_str("  \"rehearsed_g5_comparator_receipt\": {\n");
    out.push_str("    \"rehearsal_mode\": true,\n");
    out.push_str("    \"remote_ci_attestation\": false,\n");
    out.push_str("    \"remote_workflow_run_id\": 0,\n");
    out.push_str("    \"full_build\": true,\n");
    out.push_str("    \"challenge_module\": \"Challenge\",\n");
    out.push_str("    \"solution_module\": \"Main\",\n");
    out.push_str("    \"lean_kernel_exit\": 0,\n");
    out.push_str("    \"leanchecker_paranoid_exit\": 0,\n");
    out.push_str("    \"nanoda_exit\": 0,\n");
    out.push_str(&format!(
        "    \"challenge_export_sha256\": {},\n",
        json_escape(PINNED_CHALLENGE_EXPORT_SHA256)
    ));
    out.push_str(&format!(
        "    \"solution_export_sha256\": {},\n",
        json_escape(&rehearse_sol_export)
    ));
    out.push_str("    \"theorem_names\": [\"riemannHypothesis\", \"riemannZeta_eq_zero_re\", \"LFunction_ne_zero_of_half_lt_re\", \"LFunction_eq_zero_re\", \"LFunction_eq_zero_re_of_isPrimitive\"],\n");
    out.push_str("    \"theorem_axioms\": {\n");
    for (i, thm) in REQUIRED_FIVE_THEOREMS.iter().enumerate() {
        let comma = if i + 1 < REQUIRED_FIVE_THEOREMS.len() { "," } else { "" };
        out.push_str(&format!(
            "      {}: [\"propext\", \"Quot.sound\", \"Classical.choice\"]{}\n",
            json_escape(thm),
            comma
        ));
    }
    out.push_str("    }\n");
    out.push_str("  }\n");
    out.push_str("}\n");

    if contains_verbatim_proof_body(&out) {
        return Err("UP-08 violation: rehearsal JSON contains verbatim proof-body markers".to_string());
    }
    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {}", parent.display(), e))?;
    }
    fs::write(out_path, &out).map_err(|e| format!("write {}: {}", out_path.display(), e))?;
    Ok(sha256_hex(out.as_bytes()))
}

// =============================================================================
// 5. Pure Offline Arc 7 Verifier (`verify`, RG-1..RG-6 + NEG-R1..NEG-R8)
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Arc7RehearsalReceipt {
    pub rehearsal_suite_id: String,
    pub baseline_commit: String,
    pub rehearsal_mode: bool,
    pub remote_ci_attestation: bool,
    pub target_repo_mutation_allowed: bool,
    pub rg1_zone_a_pins_and_up08_clean: bool,
    pub rg2_quick_check_and_deferral_valid: bool,
    pub rg3_ci_build_receipt_valid: bool,
    pub rg4_g5_comparator_and_axioms_valid: bool,
    pub rg5_arc6_binding_and_honesty_valid: bool,
    pub rg6_negative_controls_valid: bool,
    pub quick_check_eligible_shards: usize,
    pub full_build_deferred_shards: usize,
    pub total_routed_shards: usize,
    pub linked_arc6_files: usize,
    pub linked_arc6_saved_lines: u64,
    pub linked_arc6_saved_bytes: u64,
    pub negative_controls_rejected: usize,
    pub total_negative_controls: usize,
    pub input_digests_sha256: String,
    pub rehearsal_digest_sha256: String,
    pub all_passed: bool,
}

impl Arc7RehearsalReceipt {
    pub fn to_canonical_json(&self) -> String {
        format!(
            "{{\"all_passed\":{},\"baseline_commit\":\"{}\",\"full_build_deferred_shards\":{},\"input_digests_sha256\":\"{}\",\"linked_arc6_files\":{},\"linked_arc6_saved_bytes\":{},\"linked_arc6_saved_lines\":{},\"negative_controls_rejected\":{},\"quick_check_eligible_shards\":{},\"rehearsal_digest_sha256\":\"{}\",\"rehearsal_mode\":{},\"rehearsal_suite_id\":\"{}\",\"remote_ci_attestation\":{},\"rg1_zone_a_pins_and_up08_clean\":{},\"rg2_quick_check_and_deferral_valid\":{},\"rg3_ci_build_receipt_valid\":{},\"rg4_g5_comparator_and_axioms_valid\":{},\"rg5_arc6_binding_and_honesty_valid\":{},\"rg6_negative_controls_valid\":{},\"target_repo_mutation_allowed\":{},\"total_negative_controls\":{},\"total_routed_shards\":{}}}",
            self.all_passed,
            self.baseline_commit,
            self.full_build_deferred_shards,
            self.input_digests_sha256,
            self.linked_arc6_files,
            self.linked_arc6_saved_bytes,
            self.linked_arc6_saved_lines,
            self.negative_controls_rejected,
            self.quick_check_eligible_shards,
            self.rehearsal_digest_sha256,
            self.rehearsal_mode,
            self.rehearsal_suite_id,
            self.remote_ci_attestation,
            self.rg1_zone_a_pins_and_up08_clean,
            self.rg2_quick_check_and_deferral_valid,
            self.rg3_ci_build_receipt_valid,
            self.rg4_g5_comparator_and_axioms_valid,
            self.rg5_arc6_binding_and_honesty_valid,
            self.rg6_negative_controls_valid,
            self.target_repo_mutation_allowed,
            self.total_negative_controls,
            self.total_routed_shards,
        )
    }
}

pub fn verify_arc7_rehearsal(root: &Path) -> Result<Arc7RehearsalReceipt, String> {
    let rel_reh = "transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json";
    let rel_plan = "transfer/patches/arc6_patch_plan_v1.json";
    let rel_bundles = "transfer/bundles/arc5_preflight_bundles_v1.json";

    let reh_raw = fs::read_to_string(root.join(rel_reh)).map_err(|e| format!("read {}: {}", rel_reh, e))?;
    let plan_raw = fs::read_to_string(root.join(rel_plan)).map_err(|e| format!("read {}: {}", rel_plan, e))?;
    let bundles_raw = fs::read_to_string(root.join(rel_bundles)).map_err(|e| format!("read {}: {}", rel_bundles, e))?;

    let mut dchain = String::new();
    for (label, content) in [
        (rel_reh, reh_raw.as_str()),
        (rel_plan, plan_raw.as_str()),
        (rel_bundles, bundles_raw.as_str()),
    ] {
        dchain.push_str(label);
        dchain.push(':');
        dchain.push_str(&sha256_hex(content.as_bytes()));
        dchain.push(';');
    }
    let input_digests_sha256 = sha256_hex(dchain.as_bytes());

    let reh = parse_json(&reh_raw)?;
    let plan = parse_json(&plan_raw)?;
    let bundles = parse_json(&bundles_raw)?;

    let rehearsal_suite_id = reh
        .get("rehearsal_suite_id")
        .and_then(JVal::as_str)
        .ok_or("missing rehearsal_suite_id")?
        .to_string();
    let baseline_commit = reh
        .get("source_repo_commit")
        .and_then(JVal::as_str)
        .ok_or("missing source_repo_commit")?
        .to_string();
    let rehearsal_mode = reh.get("rehearsal_mode").and_then(JVal::as_bool).unwrap_or(false);
    let remote_ci_attestation = reh
        .get("remote_ci_attestation")
        .and_then(JVal::as_bool)
        .unwrap_or(true);
    let target_repo_mutation_allowed = reh
        .get("target_repo_mutation_allowed")
        .and_then(JVal::as_bool)
        .unwrap_or(true);

    // RG-1: Zone A cryptographic pins & UP-08 zero-copy
    let pins = reh.get("zone_a_pins").ok_or("missing zone_a_pins")?;
    let pins_ok = pins.get("toolchain").and_then(JVal::as_str) == Some(PINNED_TOOLCHAIN)
        && pins.get("lakefile_sha256").and_then(JVal::as_str) == Some(PINNED_LAKEFILE_SHA256)
        && pins.get("manifest_sha256").and_then(JVal::as_str) == Some(PINNED_MANIFEST_SHA256)
        && pins.get("comparator_sha256").and_then(JVal::as_str) == Some(PINNED_COMPARATOR_SHA256)
        && pins.get("export_targets_sha256").and_then(JVal::as_str) == Some(PINNED_EXPORT_TARGETS_SHA256)
        && pins.get("lean_toolchain_sha256").and_then(JVal::as_str) == Some(PINNED_TOOLCHAIN_FILE_SHA256);

    let plan_sha = plan.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let bundles_sha = bundles.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let rg1_zone_a_pins_and_up08_clean = !target_repo_mutation_allowed
        && baseline_commit == PINNED_BASELINE_COMMIT
        && baseline_commit == plan_sha
        && baseline_commit == bundles_sha
        && pins_ok
        && !contains_verbatim_proof_body(&reh_raw);

    // RG-2: Refined quick-check.py:80 routing & rehearsed quick-check receipts
    let routing = reh
        .get("refined_shard_routing")
        .and_then(JVal::as_arr)
        .ok_or("missing refined_shard_routing")?;
    let mut routing_ok = true;
    let mut quick_check_eligible_shards = 0usize;
    let mut full_build_deferred_shards = 0usize;
    let mut z0_deferred_count = 0usize;
    for r in routing {
        let zid = r.get("zone_id").and_then(JVal::as_str).unwrap_or("");
        let roots = r.get("changed_roots").and_then(JVal::as_u64).unwrap_or(0) as usize;
        let closure = r.get("closure_modules").and_then(JVal::as_u64).unwrap_or(0);
        let has_del = r.get("has_deleted_files").and_then(JVal::as_bool).unwrap_or(false);
        let route = r.get("ci_route").and_then(JVal::as_str).unwrap_or("");
        let (exp_route, _) = classify_upstream_quick_check(roots, closure, has_del);
        if route != exp_route {
            routing_ok = false;
        }
        if route == "quick_check" {
            quick_check_eligible_shards += 1;
        } else {
            full_build_deferred_shards += 1;
            if zid == "Z-C0" && has_del {
                z0_deferred_count += 1;
            }
        }
    }
    let qc_receipts = reh
        .get("rehearsed_quick_check_receipts")
        .and_then(JVal::as_arr)
        .ok_or("missing rehearsed_quick_check_receipts")?;
    let mut qc_all_ok = qc_receipts.len() == quick_check_eligible_shards && quick_check_eligible_shards == 3;
    for qr in qc_receipts {
        if validate_quick_check_receipt(qr, &baseline_commit).is_err() {
            qc_all_ok = false;
        }
    }
    let rg2_quick_check_and_deferral_valid =
        routing_ok && qc_all_ok && z0_deferred_count == 14 && routing.len() == 18;

    // RG-3: Full ci-build.py receipt.json integrity
    let ci_rec = reh
        .get("rehearsed_ci_build_receipt")
        .ok_or("missing rehearsed_ci_build_receipt")?;
    let rg3_ci_build_receipt_valid = validate_ci_build_receipt(ci_rec, &baseline_commit).is_ok();

    // RG-4: G5 comparator + dual-kernel + 3-axiom check (rehearsal schema valid, remote attestation NOT spoofed)
    let g5_rec = reh
        .get("rehearsed_g5_comparator_receipt")
        .ok_or("missing rehearsed_g5_comparator_receipt")?;
    let rg4_g5_comparator_and_axioms_valid = validate_g5_comparator_receipt(g5_rec, false).is_ok()
        && validate_g5_comparator_receipt(g5_rec, true).is_err();

    // RG-5: Exact Arc 6 dataset linkage & PRIN-06 rehearsal honesty
    let ds = reh
        .get("arc6_dataset_summary")
        .ok_or("missing arc6_dataset_summary")?;
    let linked_arc6_files = ds.get("total_files").and_then(JVal::as_u64).unwrap_or(0) as usize;
    let linked_arc6_saved_lines = ds.get("total_saved_lines").and_then(JVal::as_u64).unwrap_or(0);
    let linked_arc6_saved_bytes = ds.get("total_saved_bytes").and_then(JVal::as_u64).unwrap_or(0);

    let plan_files = plan.get("total_files").and_then(JVal::as_u64).unwrap_or(0) as usize;
    let plan_zs = plan.get("zone_summaries").ok_or("missing plan zone_summaries")?;
    let plan_sl = plan_zs.get("Z-C0").and_then(|z| z.get("saved_lines")).and_then(JVal::as_u64).unwrap_or(0)
        + plan_zs.get("Z-C2").and_then(|z| z.get("saved_lines")).and_then(JVal::as_u64).unwrap_or(0)
        + plan_zs.get("Z-C4").and_then(|z| z.get("saved_lines")).and_then(JVal::as_u64).unwrap_or(0);
    let plan_sb = plan_zs.get("Z-C0").and_then(|z| z.get("saved_bytes")).and_then(JVal::as_u64).unwrap_or(0)
        + plan_zs.get("Z-C2").and_then(|z| z.get("saved_bytes")).and_then(JVal::as_u64).unwrap_or(0)
        + plan_zs.get("Z-C4").and_then(|z| z.get("saved_bytes")).and_then(JVal::as_u64).unwrap_or(0);

    let rg5_arc6_binding_and_honesty_valid = rehearsal_mode
        && !remote_ci_attestation
        && linked_arc6_files == 137
        && linked_arc6_files == plan_files
        && linked_arc6_saved_lines == plan_sl
        && linked_arc6_saved_bytes == plan_sb;

    // RG-6: 8 Adversarial Negative Controls (all 8 must fail closed!)
    let mut neg_rejected = 0usize;

    // NEG-R1: quick-check (`full_build: false`) attempting to attest G5 release
    let neg1 = parse_json(
        "{\"full_build\":false,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}",
    )?;
    if validate_g5_comparator_receipt(&neg1, false).is_err() {
        neg_rejected += 1;
    }

    // NEG-R2: Z-C0 deleted file routed to quick-check (`has_deleted_files: true`)
    let neg2 = parse_json(&format!(
        "{{\"status\":\"changed_roots_pass\",\"scope\":\"changed-modules-only\",\"full_build\":false,\"exit_code\":0,\"has_deleted_files\":true,\"base_head\":\"{}\",\"candidate_head\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"ancestor_modules\":50,\"targets\":[\"Foo.Bar\"]}}",
        PINNED_BASELINE_COMMIT
    ))?;
    if validate_quick_check_receipt(&neg2, PINNED_BASELINE_COMMIT).is_err() {
        neg_rejected += 1;
    }

    // NEG-R3: Forbidden axiom (`Lean.ofReduceBool` / `sorryAx`) on theorem
    let neg3 = parse_json(
        "{\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\",\"Lean.ofReduceBool\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}",
    )?;
    if validate_g5_comparator_receipt(&neg3, false).is_err() {
        neg_rejected += 1;
    }

    // NEG-R4: `nanoda_bin` non-zero exit even when `leanchecker-paranoid == 0`
    let neg4 = parse_json(
        "{\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":2,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}",
    )?;
    if validate_g5_comparator_receipt(&neg4, false).is_err() {
        neg_rejected += 1;
    }

    // NEG-R5: Zone A drift (`manifest_sha256` modified) in ci-build receipt
    let neg5 = parse_json(&format!(
        "{{\"schema\":1,\"full_build\":true,\"base_head\":\"{}\",\"candidate_head\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"candidate_tree\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"source_tree\":\"cccccccccccccccccccccccccccccccccccccccc\",\"toolchain\":\"{}\",\"lakefile_sha256\":\"{}\",\"manifest_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"input_fingerprint\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"build_exit_code\":0,\"map_sha256\":\"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"module_manifest_sha256\":\"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"}}",
        PINNED_BASELINE_COMMIT, PINNED_TOOLCHAIN, PINNED_LAKEFILE_SHA256
    ))?;
    if validate_ci_build_receipt(&neg5, PINNED_BASELINE_COMMIT).is_err() {
        neg_rejected += 1;
    }

    // NEG-R6: Missing one of the 5 required Challenge theorems
    let neg6 = parse_json(
        "{\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"]}}",
    )?;
    if validate_g5_comparator_receipt(&neg6, false).is_err() {
        neg_rejected += 1;
    }

    // NEG-R7: Stale `base_head` triggers ICD Section 4 retest
    let neg7 = parse_json(
        "{\"status\":\"changed_roots_pass\",\"scope\":\"changed-modules-only\",\"full_build\":false,\"exit_code\":0,\"has_deleted_files\":false,\"base_head\":\"0000000000000000000000000000000000000000\",\"candidate_head\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"ancestor_modules\":12,\"targets\":[\"Foo.Bar\"]}",
    )?;
    if validate_quick_check_receipt(&neg7, PINNED_BASELINE_COMMIT).is_err() {
        neg_rejected += 1;
    }

    // NEG-R8: Rehearsal spoofing `remote_ci_attestation: true` (`PRIN-06`)
    let neg8 = parse_json(
        "{\"rehearsal_mode\":true,\"remote_ci_attestation\":true,\"remote_workflow_run_id\":999,\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}",
    )?;
    if validate_g5_comparator_receipt(&neg8, true).is_err() {
        neg_rejected += 1;
    }

    let total_negative_controls = 8usize;
    let rg6_negative_controls_valid = neg_rejected == total_negative_controls;
    let all_passed = rg1_zone_a_pins_and_up08_clean
        && rg2_quick_check_and_deferral_valid
        && rg3_ci_build_receipt_valid
        && rg4_g5_comparator_and_axioms_valid
        && rg5_arc6_binding_and_honesty_valid
        && rg6_negative_controls_valid;

    let digest_src = format!(
        "{}|R:{}:{}:{}|A6:{}:{}:{}|NEG:{}/{}|REH:{}:{}|PASS:{}",
        input_digests_sha256,
        routing.len(),
        quick_check_eligible_shards,
        full_build_deferred_shards,
        linked_arc6_files,
        linked_arc6_saved_lines,
        linked_arc6_saved_bytes,
        neg_rejected,
        total_negative_controls,
        rehearsal_mode,
        remote_ci_attestation,
        all_passed
    );
    let rehearsal_digest_sha256 = sha256_hex(digest_src.as_bytes());

    Ok(Arc7RehearsalReceipt {
        rehearsal_suite_id,
        baseline_commit,
        rehearsal_mode,
        remote_ci_attestation,
        target_repo_mutation_allowed,
        rg1_zone_a_pins_and_up08_clean,
        rg2_quick_check_and_deferral_valid,
        rg3_ci_build_receipt_valid,
        rg4_g5_comparator_and_axioms_valid,
        rg5_arc6_binding_and_honesty_valid,
        rg6_negative_controls_valid,
        quick_check_eligible_shards,
        full_build_deferred_shards,
        total_routed_shards: routing.len(),
        linked_arc6_files,
        linked_arc6_saved_lines,
        linked_arc6_saved_bytes,
        negative_controls_rejected: neg_rejected,
        total_negative_controls,
        input_digests_sha256,
        rehearsal_digest_sha256,
        all_passed,
    })
}
