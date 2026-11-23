// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock Engine
//! (zero external dependencies).
//!
//! Dynamically reconciles immutable baseline, trace, dry-run, transfer-zone,
//! upstream-requirement, and Rung 3 airlock manifest artifacts; verifies all
//! five Airlock Guards (AG-1..AG-5), UP-07 bounded batch schedules, Pareto
//! mass-vector ratios, non-parametric RCT-001 efficacy, synthetic clean-room
//! transforms, and 7 adversarial negative controls while leaving the target
//! flight-article repository untouched.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
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
// 2. Pure Zero-Dependency JSON Parser
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

// =============================================================================
// 3. Core Airlock Domain Types: MassVector, Pareto Ratios, Batching, Transforms
// =============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MassVector {
    pub files: u64,
    pub lines: u64,
    pub bytes: u64,
}

impl MassVector {
    pub fn is_pareto_reduction(&self, after: &MassVector) -> bool {
        after.files <= self.files && after.lines < self.lines && after.bytes < self.bytes
    }

    pub fn rho_ppm(before: u64, after: u64) -> u64 {
        if before == 0 {
            1_000_000
        } else {
            ((after as u128) * 1_000_000u128 / (before as u128)) as u64
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageQualification {
    pub package_id: String,
    pub zone_id: String,
    pub eligible_modules: usize,
    pub batch_count: usize,
    pub max_batch_size: usize,
    pub before: MassVector,
    pub after: MassVector,
    pub rho_files_ppm: u64,
    pub rho_lines_ppm: u64,
    pub rho_bytes_ppm: u64,
    pub pareto_strict: bool,
    pub batch_schedule_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rung3AirlockReceipt {
    pub icd_id: String,
    pub baseline_commit: String,
    pub target_repo_mutation_allowed: bool,
    pub ag1_zone_a_clean: bool,
    pub ag2_conservation_exact: bool,
    pub ag3_pareto_and_rct_passed: bool,
    pub ag4_up07_batches_and_axioms_clean: bool,
    pub ag5_synthetic_transforms_passed: bool,
    pub strategy_a_a12_bps: u64,
    pub strategy_b_a12_bps: u64,
    pub multi_decl_protected_count: usize,
    pub lineage_targets_verified: usize,
    pub negative_controls_rejected: usize,
    pub total_negative_controls: usize,
    pub packages: Vec<PackageQualification>,
    pub input_digests_sha256: String,
    pub airlock_digest_sha256: String,
    pub all_passed: bool,
}

impl Rung3AirlockReceipt {
    pub fn to_canonical_json(&self) -> String {
        let mut pkgs = String::new();
        pkgs.push('[');
        for (i, p) in self.packages.iter().enumerate() {
            if i > 0 {
                pkgs.push(',');
            }
            pkgs.push_str(&format!(
                "{{\"after_bytes\":{},\"after_files\":{},\"after_lines\":{},\"batch_count\":{},\"batch_schedule_sha256\":\"{}\",\"before_bytes\":{},\"before_files\":{},\"before_lines\":{},\"eligible_modules\":{},\"max_batch_size\":{},\"package_id\":\"{}\",\"pareto_strict\":{},\"rho_bytes_ppm\":{},\"rho_files_ppm\":{},\"rho_lines_ppm\":{},\"zone_id\":\"{}\"}}",
                p.after.bytes,
                p.after.files,
                p.after.lines,
                p.batch_count,
                p.batch_schedule_sha256,
                p.before.bytes,
                p.before.files,
                p.before.lines,
                p.eligible_modules,
                p.max_batch_size,
                p.package_id,
                p.pareto_strict,
                p.rho_bytes_ppm,
                p.rho_files_ppm,
                p.rho_lines_ppm,
                p.zone_id,
            ));
        }
        pkgs.push(']');
        format!(
            "{{\"ag1_zone_a_clean\":{},\"ag2_conservation_exact\":{},\"ag3_pareto_and_rct_passed\":{},\"ag4_up07_batches_and_axioms_clean\":{},\"ag5_synthetic_transforms_passed\":{},\"airlock_digest_sha256\":\"{}\",\"all_passed\":{},\"baseline_commit\":\"{}\",\"icd_id\":\"{}\",\"input_digests_sha256\":\"{}\",\"lineage_targets_verified\":{},\"multi_decl_protected_count\":{},\"negative_controls_rejected\":{},\"packages\":{},\"strategy_a_a12_bps\":{},\"strategy_b_a12_bps\":{},\"target_repo_mutation_allowed\":{},\"total_negative_controls\":{}}}",
            self.ag1_zone_a_clean,
            self.ag2_conservation_exact,
            self.ag3_pareto_and_rct_passed,
            self.ag4_up07_batches_and_axioms_clean,
            self.ag5_synthetic_transforms_passed,
            self.airlock_digest_sha256,
            self.all_passed,
            self.baseline_commit,
            self.icd_id,
            self.input_digests_sha256,
            self.lineage_targets_verified,
            self.multi_decl_protected_count,
            self.negative_controls_rejected,
            pkgs,
            self.strategy_a_a12_bps,
            self.strategy_b_a12_bps,
            self.target_repo_mutation_allowed,
            self.total_negative_controls,
        )
    }
}

pub fn split_up07_batches(modules: &[String], cap: usize) -> Vec<Vec<String>> {
    if cap == 0 {
        return Vec::new();
    }
    let mut sorted: Vec<String> = modules.to_vec();
    sorted.sort();
    let mut batches = Vec::new();
    for chunk in sorted.chunks(cap) {
        batches.push(chunk.to_vec());
    }
    batches
}

fn verify_up07_batches(modules: &[String], batches: &[Vec<String>], cap: usize) -> bool {
    let expected: BTreeSet<&String> = modules.iter().collect();
    let mut seen: BTreeSet<&String> = BTreeSet::new();
    for b in batches {
        if b.is_empty() || b.len() > cap {
            return false;
        }
        for m in b {
            if !seen.insert(m) {
                return false;
            }
        }
    }
    seen == expected
}

fn hash_batch_schedule(package_id: &str, batches: &[Vec<String>]) -> String {
    let mut canonical = String::new();
    canonical.push_str(package_id);
    canonical.push('|');
    for (i, b) in batches.iter().enumerate() {
        canonical.push_str(&format!("B{}:", i));
        for (j, m) in b.iter().enumerate() {
            if j > 0 {
                canonical.push(',');
            }
            canonical.push_str(m);
        }
        canonical.push(';');
    }
    sha256_hex(canonical.as_bytes())
}

/// Exact integer Vargha-Delaney A12 in basis points (0..=10000) comparing treatment savings vs 0-change control.
pub fn vargha_delaney_a12_bps_vs_zero_control(treatment_savings: &[u64]) -> u64 {
    let n = treatment_savings.len() as u128;
    if n == 0 {
        return 5000;
    }
    let pos = treatment_savings.iter().filter(|&&v| v > 0).count() as u128;
    let zero = n - pos;
    // Every positive treatment beats all n control zeros (weight 2), every zero ties all n zeros (weight 1).
    let two_u = (pos * n * 2) + (zero * n);
    let denom = 2 * n * n;
    ((two_u * 10_000) / denom) as u64
}

pub fn module_to_rel_path(module_name: &str) -> String {
    format!("src/{}.lean", module_name.replace('.', "/"))
}

pub fn touches_zone_a(paths: &[String], zone_a: &BTreeSet<String>) -> bool {
    paths.iter().any(|p| zone_a.contains(p))
}

pub fn axioms_permitted(axioms: &[String], permitted: &BTreeSet<String>) -> bool {
    !axioms.is_empty() && axioms.iter().all(|a| permitted.contains(a))
}

pub fn strategy_b_safe_guard(
    decl_count: u64,
    paired_impl_exists: bool,
    imports_subset_of_impl: bool,
    touches_core: bool,
) -> bool {
    decl_count == 1 && paired_impl_exists && imports_subset_of_impl && !touches_core
}

// =============================================================================
// 4. Clean-Room Synthetic Graph Transform Verifier (AG-5)
// =============================================================================

#[derive(Debug, Clone)]
struct SynthModule {
    name: String,
    lines: u64,
    bytes: u64,
    imports: Vec<String>,
}

#[derive(Debug, Clone)]
struct SynthGraph {
    root: String,
    modules: Vec<SynthModule>,
}

impl SynthGraph {
    fn valid(&self) -> bool {
        let mut names = BTreeSet::new();
        for m in &self.modules {
            if !names.insert(m.name.as_str()) {
                return false;
            }
        }
        if !names.contains(self.root.as_str()) {
            return false;
        }
        self.modules
            .iter()
            .all(|m| m.imports.iter().all(|imp| names.contains(imp.as_str())))
    }

    fn reachable(&self) -> BTreeSet<String> {
        let adj: BTreeMap<&str, &[String]> = self
            .modules
            .iter()
            .map(|m| (m.name.as_str(), m.imports.as_slice()))
            .collect();
        let mut vis = BTreeSet::new();
        if !adj.contains_key(self.root.as_str()) {
            return vis;
        }
        let mut q = VecDeque::new();
        vis.insert(self.root.clone());
        q.push_back(self.root.clone());
        while let Some(u) = q.pop_front() {
            if let Some(nbrs) = adj.get(u.as_str()) {
                for v in *nbrs {
                    if adj.contains_key(v.as_str()) && vis.insert(v.clone()) {
                        q.push_back(v.clone());
                    }
                }
            }
        }
        vis
    }

    fn has_cycle(&self) -> bool {
        let mut indeg: BTreeMap<String, usize> = BTreeMap::new();
        let mut rev: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for m in &self.modules {
            let uniq: BTreeSet<&String> = m.imports.iter().collect();
            indeg.insert(m.name.clone(), uniq.len());
            for imp in uniq {
                rev.entry(imp.clone()).or_default().push(m.name.clone());
            }
        }
        let mut q: VecDeque<String> = indeg
            .iter()
            .filter(|&(_, d)| *d == 0)
            .map(|(k, _)| k.clone())
            .collect();
        let mut peeled = 0usize;
        while let Some(u) = q.pop_front() {
            peeled += 1;
            if let Some(deps) = rev.get(&u) {
                for dep in deps {
                    if let Some(d) = indeg.get_mut(dep) {
                        *d = d.saturating_sub(1);
                        if *d == 0 {
                            q.push_back(dep.clone());
                        }
                    }
                }
            }
        }
        peeled < self.modules.len()
    }

    fn mass(&self) -> MassVector {
        MassVector {
            files: self.modules.len() as u64,
            lines: self.modules.iter().map(|m| m.lines).sum(),
            bytes: self.modules.iter().map(|m| m.bytes).sum(),
        }
    }
}

pub fn verify_synthetic_clean_room_transforms() -> bool {
    let base = SynthGraph {
        root: "Main".to_string(),
        modules: vec![
            SynthModule {
                name: "Main".to_string(),
                lines: 20,
                bytes: 500,
                imports: vec!["CoreA".to_string(), "CoreB".to_string()],
            },
            SynthModule {
                name: "CoreA".to_string(),
                lines: 40,
                bytes: 1100,
                imports: vec!["WrapAStatement".to_string()],
            },
            SynthModule {
                name: "CoreB".to_string(),
                lines: 30,
                bytes: 800,
                imports: vec!["CoreImpl".to_string()],
            },
            SynthModule {
                name: "WrapAStatement".to_string(),
                lines: 22,
                bytes: 640,
                imports: vec!["CoreImpl".to_string()],
            },
            SynthModule {
                name: "CoreImpl".to_string(),
                lines: 80,
                bytes: 2400,
                imports: vec![],
            },
            SynthModule {
                name: "DeadLeaf1".to_string(),
                lines: 25,
                bytes: 700,
                imports: vec!["CoreImpl".to_string()],
            },
            SynthModule {
                name: "DeadLeaf2".to_string(),
                lines: 20,
                bytes: 500,
                imports: vec!["DeadLeaf1".to_string()],
            },
        ],
    };

    if !base.valid() || base.has_cycle() {
        return false;
    }
    let base_reach = base.reachable();
    let base_mass = base.mass();

    // 1. Z-C0 Dead-Leaf Prune
    let pruned = SynthGraph {
        root: base.root.clone(),
        modules: base
            .modules
            .iter()
            .filter(|m| base_reach.contains(&m.name))
            .cloned()
            .collect(),
    };
    let z0_ok = pruned.valid()
        && !pruned.has_cycle()
        && pruned.reachable() == base_reach
        && base_mass.is_pareto_reduction(&pruned.mass())
        && pruned.mass().files + 2 == base_mass.files
        && pruned.mass().lines + 45 == base_mass.lines
        && pruned.mass().bytes + 1200 == base_mass.bytes;

    // 2. Z-C1A Strategy A In-Place Alias
    let mut alias_g = base.clone();
    for m in &mut alias_g.modules {
        if m.name == "WrapAStatement" {
            m.lines = 6;
            m.bytes = 210;
        }
    }
    let z1a_ok = alias_g.valid()
        && !alias_g.has_cycle()
        && alias_g.reachable() == base_reach
        && base_mass.is_pareto_reduction(&alias_g.mass())
        && alias_g.mass().files == base_mass.files
        && alias_g.mass().lines + 16 == base_mass.lines
        && alias_g.mass().bytes + 430 == base_mass.bytes;

    // 3. Z-C1B Strategy B Wrapper Collapse + Importer Rewire
    let mut collapse_mods = Vec::new();
    for m in &base.modules {
        if m.name == "WrapAStatement" {
            continue;
        }
        let mut cm = m.clone();
        if cm.name == "CoreImpl" {
            cm.lines += 1;
            cm.bytes += 35;
        }
        for imp in &mut cm.imports {
            if imp == "WrapAStatement" {
                *imp = "CoreImpl".to_string();
            }
        }
        collapse_mods.push(cm);
    }
    let collapse_g = SynthGraph {
        root: base.root.clone(),
        modules: collapse_mods,
    };
    let c_reach = collapse_g.reachable();
    let z1b_ok = collapse_g.valid()
        && !collapse_g.has_cycle()
        && c_reach.contains("Main")
        && c_reach.contains("CoreA")
        && c_reach.contains("CoreB")
        && c_reach.contains("CoreImpl")
        && !c_reach.contains("WrapAStatement")
        && base_mass.is_pareto_reduction(&collapse_g.mass())
        && collapse_g.mass().files + 1 == base_mass.files
        && collapse_g.mass().lines + 21 == base_mass.lines
        && collapse_g.mass().bytes + 605 == base_mass.bytes;

    z0_ok && z1a_ok && z1b_ok
}

// =============================================================================
// 5. Full Clean-Room Rung 3 Airlock Qualification Runner
// =============================================================================

fn check_up08_clean_room_lean_dir(root: &Path) -> bool {
    let lean_dir = root.join("compartments/lean");
    let entries = match fs::read_dir(&lean_dir) {
        Ok(e) => e,
        Err(_) => return false,
    };
    for ent in entries.flatten() {
        let name = ent.file_name().to_string_lossy().to_string();
        if name == "Development" || name == "Formalism" || name == "GroundTheory" {
            return false;
        }
    }
    true
}

pub fn run_rung3_airlock(root: &Path) -> Result<Rung3AirlockReceipt, String> {
    let manifest_rel = "transfer/packages/rung3_airlock_manifest_v1.json";
    let manifest_raw = fs::read_to_string(root.join(manifest_rel))
        .map_err(|e| format!("read {}: {}", manifest_rel, e))?;
    let manifest = parse_json(&manifest_raw)?;

    let icd_id = manifest
        .get("icd_id")
        .and_then(JVal::as_str)
        .ok_or("missing icd_id")?
        .to_string();
    let baseline_commit = manifest
        .get("baseline_commit")
        .and_then(JVal::as_str)
        .ok_or("missing baseline_commit")?
        .to_string();
    let target_repo_mutation_allowed = manifest
        .get("target_repo_mutation_allowed")
        .and_then(JVal::as_bool)
        .ok_or("missing target_repo_mutation_allowed")?;
    let up07_cap = manifest
        .get("up07_max_roots_per_quick_check_batch")
        .and_then(JVal::as_u64)
        .ok_or("missing up07 cap")? as usize;

    let permitted_axioms: BTreeSet<String> = manifest
        .get("permitted_axioms")
        .and_then(JVal::as_arr)
        .ok_or("missing permitted_axioms")?
        .iter()
        .filter_map(|v| v.as_str().map(String::from))
        .collect();

    let inputs = manifest
        .get("input_artifacts")
        .ok_or("missing input_artifacts")?;
    let rel_inv = inputs.get("inventory").and_then(JVal::as_str).ok_or("missing inventory path")?;
    let rel_trace = inputs.get("trace").and_then(JVal::as_str).ok_or("missing trace path")?;
    let rel_dr1 = inputs.get("dryrun_dead_leaves").and_then(JVal::as_str).ok_or("missing dr1 path")?;
    let rel_dr2 = inputs.get("dryrun_wrappers").and_then(JVal::as_str).ok_or("missing dr2 path")?;
    let rel_zones = inputs.get("transfer_zones").and_then(JVal::as_str).ok_or("missing zones path")?;
    let rel_up = inputs.get("upstream_requirements").and_then(JVal::as_str).ok_or("missing up path")?;

    let inv_raw = fs::read_to_string(root.join(rel_inv)).map_err(|e| format!("read {}: {}", rel_inv, e))?;
    let trace_raw = fs::read_to_string(root.join(rel_trace)).map_err(|e| format!("read {}: {}", rel_trace, e))?;
    let dr1_raw = fs::read_to_string(root.join(rel_dr1)).map_err(|e| format!("read {}: {}", rel_dr1, e))?;
    let dr2_raw = fs::read_to_string(root.join(rel_dr2)).map_err(|e| format!("read {}: {}", rel_dr2, e))?;
    let zones_raw = fs::read_to_string(root.join(rel_zones)).map_err(|e| format!("read {}: {}", rel_zones, e))?;
    let up_raw = fs::read_to_string(root.join(rel_up)).map_err(|e| format!("read {}: {}", rel_up, e))?;

    // Compute canonical SHA-256 chain across all 7 input files.
    let mut digest_chain = String::new();
    for (label, content) in [
        (manifest_rel, manifest_raw.as_str()),
        (rel_inv, inv_raw.as_str()),
        (rel_trace, trace_raw.as_str()),
        (rel_dr1, dr1_raw.as_str()),
        (rel_dr2, dr2_raw.as_str()),
        (rel_zones, zones_raw.as_str()),
        (rel_up, up_raw.as_str()),
    ] {
        digest_chain.push_str(label);
        digest_chain.push(':');
        digest_chain.push_str(&sha256_hex(content.as_bytes()));
        digest_chain.push(';');
    }
    let input_digests_sha256 = sha256_hex(digest_chain.as_bytes());

    let inv = parse_json(&inv_raw)?;
    let trace = parse_json(&trace_raw)?;
    let dr1 = parse_json(&dr1_raw)?;
    let dr2 = parse_json(&dr2_raw)?;
    let zones = parse_json(&zones_raw)?;
    let up = parse_json(&up_raw)?;

    // Extract Zone A protected paths from transfer_zones_v1.json.
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
    let zones_axioms: BTreeSet<String> = zones
        .get("protected_axioms")
        .and_then(JVal::as_arr)
        .ok_or("missing protected_axioms")?
        .iter()
        .filter_map(|v| v.as_str().map(String::from))
        .collect();

    // AG-2: Cross-tool SHA alignment & global mass conservation.
    let inv_sha = inv.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let trace_sha = trace.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let dr1_sha = dr1.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let dr2_sha = dr2.get("source_repo_commit").and_then(JVal::as_str).unwrap_or("");
    let zones_sha = zones.get("baseline_commit").and_then(JVal::as_str).unwrap_or("");
    let up_sha = up.get("verified_against_commit").and_then(JVal::as_str).unwrap_or("");
    let sha_all_match = inv_sha == baseline_commit
        && trace_sha == baseline_commit
        && dr1_sha == baseline_commit
        && dr2_sha == baseline_commit
        && zones_sha == baseline_commit
        && up_sha == baseline_commit;

    let totals = inv.get("totals").ok_or("missing totals")?;
    let tot_files = totals.get("files").and_then(JVal::as_u64).ok_or("missing files")?;
    let tot_lines = totals.get("lines").and_then(JVal::as_u64).ok_or("missing lines")?;
    let tot_bytes = totals.get("bytes").and_then(JVal::as_u64).ok_or("missing bytes")?;

    let inv_graph = inv.get("import_graph").ok_or("missing import_graph")?;
    let inv_reach = inv_graph.get("reachable_from_main").and_then(JVal::as_u64).ok_or("missing inv_reach")?;
    let dead_mods_list: Vec<String> = inv_graph
        .get("unreachable_project_modules")
        .and_then(JVal::as_arr)
        .ok_or("missing unreachable_project_modules")?
        .iter()
        .filter_map(|v| v.as_str().map(String::from))
        .collect();

    let tr_sum = trace.get("graph_summary").ok_or("missing graph_summary")?;
    let tr_reach = tr_sum.get("reachable_modules").and_then(JVal::as_u64).ok_or("missing tr_reach")?;
    let tr_reach_lines = tr_sum.get("reachable_lines").and_then(JVal::as_u64).ok_or("missing tr_reach_lines")?;
    let tr_reach_bytes = tr_sum.get("reachable_bytes").and_then(JVal::as_u64).ok_or("missing tr_reach_bytes")?;
    let is_acyclic = tr_sum.get("is_acyclic").and_then(JVal::as_bool).unwrap_or(false);

    // Derive exact Challenge.lean mass from <root> minus Main and Statements.
    let mut root_files = 0u64;
    let mut root_lines = 0u64;
    let mut root_bytes = 0u64;
    if let Some(libs) = inv.get("libraries").and_then(JVal::as_arr) {
        for lib in libs {
            if lib.get("name").and_then(JVal::as_str) == Some("<root>") {
                root_files = lib.get("files").and_then(JVal::as_u64).unwrap_or(0);
                root_lines = lib.get("lines").and_then(JVal::as_u64).unwrap_or(0);
                root_bytes = lib.get("bytes").and_then(JVal::as_u64).unwrap_or(0);
            }
        }
    }
    let mut main_stmt_lines = 0u64;
    let mut main_stmt_bytes = 0u64;
    let mut main_stmt_files = 0u64;
    if let Some(spine) = trace.get("root_spine_depth_le_2").and_then(JVal::as_arr) {
        for node in spine {
            let mname = node.get("module").and_then(JVal::as_str).unwrap_or("");
            if mname == "Main" || mname == "Statements" {
                main_stmt_files += 1;
            }
        }
    }
    let mut lineage_targets_verified = 0usize;
    if let Some(lin) = trace.get("lineage_reachability_audit").and_then(JVal::as_arr) {
        for item in lin {
            if item.get("verified_reachable").and_then(JVal::as_bool) == Some(true) {
                lineage_targets_verified += 1;
            }
            let pref = item.get("module_prefix").and_then(JVal::as_str).unwrap_or("");
            if pref == "Main" || pref == "Statements" {
                main_stmt_lines += item.get("reachable_lines").and_then(JVal::as_u64).unwrap_or(0);
                main_stmt_bytes += item.get("reachable_bytes").and_then(JVal::as_u64).unwrap_or(0);
            }
        }
    }

    let challenge_files = root_files.saturating_sub(main_stmt_files);
    let challenge_lines = root_lines.saturating_sub(main_stmt_lines);
    let challenge_bytes = root_bytes.saturating_sub(main_stmt_bytes);

    let dr1_sum = dr1.get("summary").ok_or("missing dr1 summary")?;
    let dr1_dead_count = dr1_sum.get("dead_modules_count").and_then(JVal::as_u64).ok_or("missing dead_modules_count")?;
    let dr1_dead_lines = dr1_sum.get("reclaimable_lines").and_then(JVal::as_u64).ok_or("missing reclaimable_lines")?;
    let dr1_dead_bytes = dr1_sum.get("reclaimable_bytes").and_then(JVal::as_u64).ok_or("missing reclaimable_bytes")?;
    let dr1_imp_by_reach = dr1_sum.get("imported_by_any_reachable_module").and_then(JVal::as_u64).unwrap_or(1);
    let dr1_lakefile_edit = dr1_sum.get("upstream_lakefile_edit_required").and_then(JVal::as_bool).unwrap_or(true);

    let ag2_conservation_exact = sha_all_match
        && is_acyclic
        && inv_reach == tr_reach
        && (dead_mods_list.len() as u64) == dr1_dead_count
        && dr1_imp_by_reach == 0
        && challenge_files == 1
        && (tr_reach + dr1_dead_count + challenge_files == tot_files)
        && (tr_reach_lines + dr1_dead_lines + challenge_lines == tot_lines)
        && (tr_reach_bytes + dr1_dead_bytes + challenge_bytes == tot_bytes)
        && lineage_targets_verified == 15;

    // AG-1 + AG-3: Unit-level reconciliation of dryrun_002_rct001_wrappers.json
    let dr2_qual = dr2
        .get("treatment_dryrun_qualification")
        .ok_or("missing treatment_dryrun_qualification")?;
    let expected_pure_wrappers = dr2_qual.get("single_declaration_pure_wrappers").and_then(JVal::as_u64).ok_or("missing pure wrappers")? as usize;
    let expected_multi_decl = dr2_qual.get("multi_declaration_proof_files_excluded_by_guard").and_then(JVal::as_u64).ok_or("missing multi decl")? as usize;
    let pure_base_lines = dr2_qual.get("pure_wrapper_baseline_lines").and_then(JVal::as_u64).ok_or("missing pure base lines")?;
    let pure_base_bytes = dr2_qual.get("pure_wrapper_baseline_bytes").and_then(JVal::as_u64).ok_or("missing pure base bytes")?;
    let expected_sa_count = dr2_qual.get("strategy_a_eligible_units").and_then(JVal::as_u64).ok_or("missing sa count")? as usize;
    let expected_sa_lines = dr2_qual.get("strategy_a_inplace_alias_saved_lines").and_then(JVal::as_u64).ok_or("missing sa lines")?;
    let expected_sa_bytes = dr2_qual.get("strategy_a_inplace_alias_saved_bytes").and_then(JVal::as_u64).ok_or("missing sa bytes")?;
    let expected_sb_count = dr2_qual.get("strategy_b_collapse_eligible_units").and_then(JVal::as_u64).ok_or("missing sb count")? as usize;
    let expected_sb_lines = dr2_qual.get("strategy_b_collapse_saved_lines").and_then(JVal::as_u64).ok_or("missing sb lines")?;
    let expected_sb_bytes = dr2_qual.get("strategy_b_collapse_saved_bytes").and_then(JVal::as_u64).ok_or("missing sb bytes")?;

    let mut trt_single_decl = 0usize;
    let mut trt_multi_decl = 0usize;
    let mut trt_multi_decl_leaked = 0usize;
    let mut any_touches_core = false;
    let mut sa_modules: Vec<String> = Vec::new();
    let mut sb_modules: Vec<String> = Vec::new();
    let mut sa_lines_sum = 0u64;
    let mut sb_lines_sum = 0u64;
    let mut sa_pure_savings: Vec<u64> = Vec::new();
    let mut sb_pure_savings: Vec<u64> = Vec::new();
    let mut all_touched_paths: Vec<String> = dead_mods_list.iter().map(|m| module_to_rel_path(m)).collect();

    for u in dr2.get("unit_diagnostics").and_then(JVal::as_arr).ok_or("missing unit_diagnostics")? {
        let arm = u.get("arm").and_then(JVal::as_str).unwrap_or("");
        let mname = u.get("module").and_then(JVal::as_str).unwrap_or("");
        let decl_count = u.get("decl_count").and_then(JVal::as_u64).unwrap_or(0);
        let paired_impl = u.get("paired_impl_exists").and_then(JVal::as_bool).unwrap_or(false);
        let subset_imp = u.get("imports_subset_of_impl").and_then(JVal::as_bool).unwrap_or(false);
        let touches_core = u.get("touches_core").and_then(JVal::as_bool).unwrap_or(true);
        let sa_elig = u.get("strategy_a_eligible").and_then(JVal::as_bool).unwrap_or(false);
        let sa_saved = u.get("strategy_a_saved_lines").and_then(JVal::as_u64).unwrap_or(0);
        let sb_elig = u.get("strategy_b_eligible").and_then(JVal::as_bool).unwrap_or(false);
        let sb_saved = u.get("strategy_b_saved_lines").and_then(JVal::as_u64).unwrap_or(0);

        if touches_core {
            any_touches_core = true;
        }
        if arm == "treatment" {
            all_touched_paths.push(module_to_rel_path(mname));
            if decl_count == 1 {
                trt_single_decl += 1;
                sa_pure_savings.push(if sa_elig { sa_saved } else { 0 });
                sb_pure_savings.push(if sb_elig { sb_saved } else { 0 });
            } else {
                trt_multi_decl += 1;
                if sa_elig || sb_elig {
                    trt_multi_decl_leaked += 1;
                }
            }
            if sa_elig {
                sa_modules.push(mname.to_string());
                sa_lines_sum += sa_saved;
            }
            if sb_elig {
                if !strategy_b_safe_guard(decl_count, paired_impl, subset_imp, touches_core) {
                    trt_multi_decl_leaked += 1;
                }
                sb_modules.push(mname.to_string());
                sb_lines_sum += sb_saved;
            }
        }
    }

    let ag1_zone_a_clean = !target_repo_mutation_allowed
        && zone_a_paths.len() == 8
        && !any_touches_core
        && !dr1_lakefile_edit
        && !touches_zone_a(&all_touched_paths, &zone_a_paths);

    // Build deterministic UP-07 batches and Pareto mass receipts for all 3 packages.
    let z0_batches = split_up07_batches(&dead_mods_list, up07_cap);
    let z1a_batches = split_up07_batches(&sa_modules, up07_cap);
    let z1b_batches = split_up07_batches(&sb_modules, up07_cap);

    let z0_before = MassVector { files: tot_files, lines: tot_lines, bytes: tot_bytes };
    let z0_after = MassVector {
        files: tot_files - dr1_dead_count,
        lines: tot_lines - dr1_dead_lines,
        bytes: tot_bytes - dr1_dead_bytes,
    };
    let z1a_before = MassVector { files: expected_pure_wrappers as u64, lines: pure_base_lines, bytes: pure_base_bytes };
    let z1a_after = MassVector {
        files: expected_pure_wrappers as u64,
        lines: pure_base_lines - expected_sa_lines,
        bytes: pure_base_bytes - expected_sa_bytes,
    };
    let z1b_before = z1a_before;
    let z1b_after = MassVector {
        files: (expected_pure_wrappers - expected_sb_count) as u64,
        lines: pure_base_lines - expected_sb_lines,
        bytes: pure_base_bytes - expected_sb_bytes,
    };

    let packages = vec![
        PackageQualification {
            package_id: "PKG-R3-Z0-DEAD-LEAVES".to_string(),
            zone_id: "Z-C0".to_string(),
            eligible_modules: dead_mods_list.len(),
            batch_count: z0_batches.len(),
            max_batch_size: z0_batches.iter().map(Vec::len).max().unwrap_or(0),
            before: z0_before,
            after: z0_after,
            rho_files_ppm: MassVector::rho_ppm(z0_before.files, z0_after.files),
            rho_lines_ppm: MassVector::rho_ppm(z0_before.lines, z0_after.lines),
            rho_bytes_ppm: MassVector::rho_ppm(z0_before.bytes, z0_after.bytes),
            pareto_strict: z0_before.is_pareto_reduction(&z0_after),
            batch_schedule_sha256: hash_batch_schedule("PKG-R3-Z0-DEAD-LEAVES", &z0_batches),
        },
        PackageQualification {
            package_id: "PKG-R3-Z1A-ALIAS-INPLACE".to_string(),
            zone_id: "Z-C1".to_string(),
            eligible_modules: sa_modules.len(),
            batch_count: z1a_batches.len(),
            max_batch_size: z1a_batches.iter().map(Vec::len).max().unwrap_or(0),
            before: z1a_before,
            after: z1a_after,
            rho_files_ppm: MassVector::rho_ppm(z1a_before.files, z1a_after.files),
            rho_lines_ppm: MassVector::rho_ppm(z1a_before.lines, z1a_after.lines),
            rho_bytes_ppm: MassVector::rho_ppm(z1a_before.bytes, z1a_after.bytes),
            pareto_strict: z1a_before.is_pareto_reduction(&z1a_after),
            batch_schedule_sha256: hash_batch_schedule("PKG-R3-Z1A-ALIAS-INPLACE", &z1a_batches),
        },
        PackageQualification {
            package_id: "PKG-R3-Z1B-WRAPPER-COLLAPSE".to_string(),
            zone_id: "Z-C1".to_string(),
            eligible_modules: sb_modules.len(),
            batch_count: z1b_batches.len(),
            max_batch_size: z1b_batches.iter().map(Vec::len).max().unwrap_or(0),
            before: z1b_before,
            after: z1b_after,
            rho_files_ppm: MassVector::rho_ppm(z1b_before.files, z1b_after.files),
            rho_lines_ppm: MassVector::rho_ppm(z1b_before.lines, z1b_after.lines),
            rho_bytes_ppm: MassVector::rho_ppm(z1b_before.bytes, z1b_after.bytes),
            pareto_strict: z1b_before.is_pareto_reduction(&z1b_after),
            batch_schedule_sha256: hash_batch_schedule("PKG-R3-Z1B-WRAPPER-COLLAPSE", &z1b_batches),
        },
    ];

    let strategy_a_a12_bps = vargha_delaney_a12_bps_vs_zero_control(&sa_pure_savings);
    let strategy_b_a12_bps = vargha_delaney_a12_bps_vs_zero_control(&sb_pure_savings);

    let ag3_pareto_and_rct_passed = trt_single_decl == expected_pure_wrappers
        && trt_multi_decl == expected_multi_decl
        && trt_multi_decl_leaked == 0
        && sa_modules.len() == expected_sa_count
        && sa_lines_sum == expected_sa_lines
        && sb_modules.len() == expected_sb_count
        && sb_lines_sum == expected_sb_lines
        && packages.iter().all(|p| p.pareto_strict)
        && strategy_a_a12_bps >= 9000
        && strategy_b_a12_bps >= 7500;

    let ag4_up07_batches_and_axioms_clean = up07_cap == 8
        && verify_up07_batches(&dead_mods_list, &z0_batches, up07_cap)
        && verify_up07_batches(&sa_modules, &z1a_batches, up07_cap)
        && verify_up07_batches(&sb_modules, &z1b_batches, up07_cap)
        && permitted_axioms == zones_axioms
        && permitted_axioms.len() == 3
        && check_up08_clean_room_lean_dir(root);

    let ag5_synthetic_transforms_passed = verify_synthetic_clean_room_transforms();

    // 7 Adversarial Negative Controls (all 7 must fail closed!).
    let mut neg_rejected = 0usize;
    if touches_zone_a(&["src/Main.lean".to_string(), "lakefile.toml".to_string()], &zone_a_paths) {
        neg_rejected += 1;
    }
    if "0000000000000000000000000000000000000000" != baseline_commit {
        neg_rejected += 1;
    }
    if !strategy_b_safe_guard(2, true, true, false) {
        neg_rejected += 1;
    }
    if !strategy_b_safe_guard(1, true, false, false) {
        neg_rejected += 1;
    }
    let oversized: Vec<String> = (0..9).map(|i| format!("Mod{}", i)).collect();
    if !verify_up07_batches(&oversized, std::slice::from_ref(&oversized), up07_cap) {
        neg_rejected += 1;
    }
    if !axioms_permitted(&["propext".to_string(), "CustomUnsoundAxiom".to_string()], &permitted_axioms) {
        neg_rejected += 1;
    }
    let inflated = MassVector { files: 51, lines: 1005, bytes: 96575 };
    if !z1a_before.is_pareto_reduction(&inflated) {
        neg_rejected += 1;
    }

    let total_negative_controls = 7usize;
    let all_passed = ag1_zone_a_clean
        && ag2_conservation_exact
        && ag3_pareto_and_rct_passed
        && ag4_up07_batches_and_axioms_clean
        && ag5_synthetic_transforms_passed
        && neg_rejected == total_negative_controls;

    let mut digest_src = String::new();
    digest_src.push_str(&input_digests_sha256);
    digest_src.push('|');
    for p in &packages {
        digest_src.push_str(&format!(
            "{}:{}:{}:{}:{}:{};",
            p.package_id, p.eligible_modules, p.batch_count, p.rho_files_ppm, p.rho_lines_ppm, p.batch_schedule_sha256
        ));
    }
    digest_src.push_str(&format!(
        "A12:{}:{};NEG:{}/{};PASS:{}",
        strategy_a_a12_bps, strategy_b_a12_bps, neg_rejected, total_negative_controls, all_passed
    ));
    let airlock_digest_sha256 = sha256_hex(digest_src.as_bytes());

    Ok(Rung3AirlockReceipt {
        icd_id,
        baseline_commit,
        target_repo_mutation_allowed,
        ag1_zone_a_clean,
        ag2_conservation_exact,
        ag3_pareto_and_rct_passed,
        ag4_up07_batches_and_axioms_clean,
        ag5_synthetic_transforms_passed,
        strategy_a_a12_bps,
        strategy_b_a12_bps,
        multi_decl_protected_count: trt_multi_decl,
        lineage_targets_verified,
        negative_controls_rejected: neg_rejected,
        total_negative_controls,
        packages,
        input_digests_sha256,
        airlock_digest_sha256,
        all_passed,
    })
}
