// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone Rung 2 Shared Ground Codec, QuickCheck Property Generator,
//! Deterministic Counterexample Shrinker, Metamorphic Invariance Suite, and
//! Differential Parity Harness (zero external dependencies).

use std::collections::{BTreeMap, BTreeSet, VecDeque};

// =============================================================================
// 1. Pure FIPS 180-4 SHA-256 & Deterministic SplitMix64 PRNG
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
            let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(SHA256_K[i]).wrapping_add(w[i]);
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

#[derive(Debug, Clone)]
pub struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }

    pub fn next_usize(&mut self, upper_exclusive: usize) -> usize {
        if upper_exclusive == 0 {
            0
        } else {
            (self.next_u64() % (upper_exclusive as u64)) as usize
        }
    }
}

// =============================================================================
// 2. Shared Ground Codec: GroundModule, GroundGraph, WrapperKind
// =============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WrapperKind {
    PureWrapper,
    ReexportHub,
    Substantive,
}

impl WrapperKind {
    pub fn as_str(self) -> &'static str {
        match self {
            WrapperKind::PureWrapper => "pure_wrapper",
            WrapperKind::ReexportHub => "reexport_hub",
            WrapperKind::Substantive => "substantive",
        }
    }
}

/// Classifies Lean 4 module text ignoring `--` line comments, `/- ... -/` block comments, and blank lines.
pub fn classify_wrapper_text(source: &str) -> WrapperKind {
    let mut in_block = false;
    let mut imp_count = 0usize;
    let mut pub_count = 0usize;
    let mut has_decl = false;

    for raw_line in source.lines() {
        let t = raw_line.trim();
        if t.starts_with("/-") {
            if !t.contains("-/") {
                in_block = true;
            }
            continue;
        }
        if in_block {
            if t.contains("-/") {
                in_block = false;
            }
            continue;
        }
        if t.is_empty() || t.starts_with("--") || t == "module" {
            continue;
        }
        if t.starts_with("theorem ")
            || t.starts_with("lemma ")
            || t.starts_with("def ")
            || t.starts_with("structure ")
            || t.starts_with("inductive ")
            || t.starts_with("class ")
            || t.starts_with("instance ")
            || t.starts_with("abbrev ")
            || t.starts_with("private theorem ")
            || t.starts_with("private def ")
        {
            has_decl = true;
        }
        if t.starts_with("public import ") {
            pub_count += 1;
            imp_count += 1;
        } else if t.starts_with("import ")
            || t.starts_with("private import ")
            || t.starts_with("meta import ")
        {
            imp_count += 1;
        }
    }

    if has_decl {
        WrapperKind::Substantive
    } else if pub_count >= 2 {
        WrapperKind::ReexportHub
    } else if imp_count >= 1 {
        WrapperKind::PureWrapper
    } else {
        WrapperKind::Substantive
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroundModule {
    pub name: String,
    pub lines: u64,
    pub bytes: u64,
    pub imports: Vec<String>,
    pub wrapper_kind: WrapperKind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroundGraph {
    pub root: String,
    pub modules: Vec<GroundModule>,
}

fn push_json_str(s: &str, out: &mut String) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            c => out.push(c),
        }
    }
    out.push('"');
}

impl GroundGraph {
    /// Returns a canonicalized copy (modules sorted by name, imports sorted & deduplicated).
    pub fn canonicalized(&self) -> Self {
        let mut mods = self.modules.clone();
        for m in &mut mods {
            let uniq: BTreeSet<String> = m.imports.iter().cloned().collect();
            m.imports = uniq.into_iter().collect();
        }
        mods.sort_by(|a, b| a.name.cmp(&b.name));
        Self {
            root: self.root.clone(),
            modules: mods,
        }
    }

    /// Deterministic sorted-key canonical JSON encoding.
    pub fn to_canonical_json(&self) -> String {
        let c = self.canonicalized();
        let mut out = String::new();
        out.push_str("{\"modules\":[");
        for (i, m) in c.modules.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            out.push_str("{\"bytes\":");
            out.push_str(&m.bytes.to_string());
            out.push_str(",\"imports\":[");
            for (j, imp) in m.imports.iter().enumerate() {
                if j > 0 {
                    out.push(',');
                }
                push_json_str(imp, &mut out);
            }
            out.push_str("],\"lines\":");
            out.push_str(&m.lines.to_string());
            out.push_str(",\"name\":");
            push_json_str(&m.name, &mut out);
            out.push_str(",\"wrapper_kind\":");
            push_json_str(m.wrapper_kind.as_str(), &mut out);
            out.push('}');
        }
        out.push_str("],\"root\":");
        push_json_str(&c.root, &mut out);
        out.push('}');
        out
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.root.is_empty() {
            return Err("empty root module".to_string());
        }
        let mut names = BTreeSet::new();
        for m in &self.modules {
            if m.name.is_empty() {
                return Err("empty module name".to_string());
            }
            if !names.insert(m.name.clone()) {
                return Err(format!("duplicate module '{}'", m.name));
            }
        }
        if !names.contains(&self.root) {
            return Err(format!("missing root '{}'", self.root));
        }
        for m in &self.modules {
            for imp in &m.imports {
                if !names.contains(imp) {
                    return Err(format!("dangling import '{}' in '{}'", imp, m.name));
                }
            }
        }
        Ok(())
    }

    pub fn reachable_from_root(&self) -> BTreeSet<String> {
        let adj: BTreeMap<&str, &[String]> = self
            .modules
            .iter()
            .map(|m| (m.name.as_str(), m.imports.as_slice()))
            .collect();
        let mut visited = BTreeSet::new();
        if !adj.contains_key(self.root.as_str()) {
            return visited;
        }
        let mut q = VecDeque::new();
        visited.insert(self.root.clone());
        q.push_back(self.root.clone());
        while let Some(u) = q.pop_front() {
            if let Some(nbrs) = adj.get(u.as_str()) {
                for v in *nbrs {
                    if adj.contains_key(v.as_str()) && visited.insert(v.clone()) {
                        q.push_back(v.clone());
                    }
                }
            }
        }
        visited
    }

    pub fn dead_leaves(&self) -> BTreeSet<String> {
        let reach = self.reachable_from_root();
        self.modules
            .iter()
            .map(|m| m.name.clone())
            .filter(|n| !reach.contains(n))
            .collect()
    }

    /// Exact Kahn topological peel: returns true iff the graph contains at least one directed cycle.
    pub fn has_cycle(&self) -> bool {
        let mut indeg: BTreeMap<String, usize> = BTreeMap::new();
        let mut rev_adj: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for m in &self.modules {
            let uniq: BTreeSet<&String> = m.imports.iter().collect();
            indeg.insert(m.name.clone(), uniq.len());
            for imp in uniq {
                rev_adj.entry(imp.clone()).or_default().push(m.name.clone());
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
            if let Some(dependents) = rev_adj.get(&u) {
                for dep in dependents {
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

    /// Exact order-independent iterative fixed-point dominator sets on all nodes reachable from `root`.
    pub fn compute_dominators(&self) -> BTreeMap<String, BTreeSet<String>> {
        let reach = self.reachable_from_root();
        let mut preds: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        for n in &reach {
            preds.insert(n.clone(), BTreeSet::new());
        }
        for m in &self.modules {
            if reach.contains(&m.name) {
                for imp in &m.imports {
                    if reach.contains(imp)
                        && let Some(ps) = preds.get_mut(imp)
                    {
                        ps.insert(m.name.clone());
                    }
                }
            }
        }

        let mut dom: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
        for n in &reach {
            if n == &self.root {
                let mut s = BTreeSet::new();
                s.insert(n.clone());
                dom.insert(n.clone(), s);
            } else {
                dom.insert(n.clone(), reach.clone());
            }
        }

        let mut changed = true;
        while changed {
            changed = false;
            for n in &reach {
                if n == &self.root {
                    continue;
                }
                let ps = &preds[n];
                let mut inter: Option<BTreeSet<String>> = None;
                for p in ps {
                    let dp = &dom[p];
                    inter = Some(match inter {
                        None => dp.clone(),
                        Some(acc) => acc.intersection(dp).cloned().collect(),
                    });
                }
                let mut new_set = inter.unwrap_or_default();
                new_set.insert(n.clone());
                if dom[n] != new_set {
                    dom.insert(n.clone(), new_set);
                    changed = true;
                }
            }
        }
        dom
    }

    pub fn edge_count(&self) -> usize {
        self.modules.iter().map(|m| m.imports.len()).sum()
    }

    pub fn mass_accounting(&self) -> (u64, u64, u64, u64, u64, u64) {
        let reach = self.reachable_from_root();
        let (mut rl, mut dl, mut rb, mut db) = (0u64, 0u64, 0u64, 0u64);
        for m in &self.modules {
            if reach.contains(&m.name) {
                rl += m.lines;
                rb += m.bytes;
            } else {
                dl += m.lines;
                db += m.bytes;
            }
        }
        (rl, dl, rl + dl, rb, db, rb + db)
    }
}

/// Strict canonical JSON decoder for `GroundGraph` (fail-closed on malformed JSON or missing fields).
pub fn decode_ground_graph_json(input: &str) -> Result<GroundGraph, String> {
    let bytes = input.as_bytes();
    let mut p = MiniParser { bytes, pos: 0 };
    let val = p.parse_val()?;
    p.skip_ws();
    if p.pos != bytes.len() {
        return Err("trailing bytes in JSON".to_string());
    }
    let root = val
        .get("root")
        .and_then(JVal::as_str)
        .ok_or("missing root string")?
        .to_string();
    let arr = val
        .get("modules")
        .and_then(JVal::as_arr)
        .ok_or("missing modules array")?;
    let mut modules = Vec::with_capacity(arr.len());
    for item in arr {
        let name = item.get("name").and_then(JVal::as_str).ok_or("missing name")?.to_string();
        let lines = item.get("lines").and_then(JVal::as_u64).ok_or("missing lines")?;
        let bytes_len = item.get("bytes").and_then(JVal::as_u64).ok_or("missing bytes")?;
        let imp_arr = item.get("imports").and_then(JVal::as_arr).ok_or("missing imports")?;
        let mut imports = Vec::with_capacity(imp_arr.len());
        for iv in imp_arr {
            imports.push(iv.as_str().ok_or("import not string")?.to_string());
        }
        let wk = match item.get("wrapper_kind").and_then(JVal::as_str) {
            Some("pure_wrapper") => WrapperKind::PureWrapper,
            Some("reexport_hub") => WrapperKind::ReexportHub,
            Some("substantive") => WrapperKind::Substantive,
            _ => return Err("invalid wrapper_kind".to_string()),
        };
        modules.push(GroundModule {
            name,
            lines,
            bytes: bytes_len,
            imports,
            wrapper_kind: wk,
        });
    }
    let g = GroundGraph { root, modules };
    g.validate()?;
    Ok(g)
}

#[derive(Debug, Clone)]
enum JVal {
    Str(String),
    Num(u64),
    Arr(Vec<JVal>),
    Obj(BTreeMap<String, JVal>),
}

impl JVal {
    fn as_str(&self) -> Option<&str> {
        match self {
            JVal::Str(s) => Some(s.as_str()),
            _ => None,
        }
    }
    fn as_u64(&self) -> Option<u64> {
        match self {
            JVal::Num(n) => Some(*n),
            _ => None,
        }
    }
    fn as_arr(&self) -> Option<&[JVal]> {
        match self {
            JVal::Arr(a) => Some(a.as_slice()),
            _ => None,
        }
    }
    fn get(&self, k: &str) -> Option<&JVal> {
        match self {
            JVal::Obj(m) => m.get(k),
            _ => None,
        }
    }
}

struct MiniParser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> MiniParser<'a> {
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
            Some(b'0'..=b'9') => self.parse_u64().map(JVal::Num),
            _ => Err(format!("unexpected JSON token at {}", self.pos)),
        }
    }
    fn parse_str(&mut self) -> Result<String, String> {
        if self.peek() != Some(b'"') {
            return Err("expected quote".to_string());
        }
        self.pos += 1;
        let mut s = String::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            self.pos += 1;
            if b == b'"' {
                return Ok(s);
            }
            if b == b'\\' {
                if self.pos >= self.bytes.len() {
                    return Err("truncated escape".to_string());
                }
                let e = self.bytes[self.pos];
                self.pos += 1;
                match e {
                    b'"' => s.push('"'),
                    b'\\' => s.push('\\'),
                    b'n' => s.push('\n'),
                    _ => return Err("unsupported escape".to_string()),
                }
            } else {
                s.push(b as char);
            }
        }
        Err("unterminated JSON string".to_string())
    }
    fn parse_u64(&mut self) -> Result<u64, String> {
        let start = self.pos;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.pos += 1;
        }
        let raw = std::str::from_utf8(&self.bytes[start..self.pos]).map_err(|_| "bad utf8")?;
        raw.parse::<u64>().map_err(|_| "bad integer".to_string())
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
        let mut m = BTreeMap::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JVal::Obj(m));
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
            m.insert(k, v);
            self.skip_ws();
            match self.peek() {
                Some(b',') => self.pos += 1,
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(JVal::Obj(m));
                }
                _ => return Err("expected ',' or '}'".to_string()),
            }
        }
    }
}

// =============================================================================
// 3. Deterministic Counterexample Shrinker (QuickCheck Style, METH-20)
// =============================================================================

/// Deterministically shrinks a cyclic graph to a 1-edge-minimal cycle core.
pub fn shrink_cyclic_graph(g: &GroundGraph) -> GroundGraph {
    let mut cur = g.canonicalized();
    if !cur.has_cycle() {
        return cur;
    }
    let mut improved = true;
    while improved {
        improved = false;
        'outer: for mi in 0..cur.modules.len() {
            for ei in 0..cur.modules[mi].imports.len() {
                let mut cand = cur.clone();
                cand.modules[mi].imports.remove(ei);
                if cand.has_cycle() {
                    cur = cand;
                    improved = true;
                    break 'outer;
                }
            }
        }
    }
    cur
}

pub fn is_edge_minimal_cycle(g: &GroundGraph) -> bool {
    if !g.has_cycle() {
        return false;
    }
    for mi in 0..g.modules.len() {
        for ei in 0..g.modules[mi].imports.len() {
            let mut cand = g.clone();
            cand.modules[mi].imports.remove(ei);
            if cand.has_cycle() {
                return false;
            }
        }
    }
    true
}

// =============================================================================
// 4. Seeded Generative Corpus + Metamorphic Suite + Differential Parity Receipt
// =============================================================================

#[derive(Debug, Clone)]
pub struct Rung2ParityReceipt {
    pub master_seed: u64,
    pub cases_per_family: usize,
    pub total_cases: usize,
    pub dag_clean_passed: usize,
    pub cycle_shrunk_minimal: usize,
    pub diamond_dom_passed: usize,
    pub dead_leaves_passed: usize,
    pub wrapper_ast_passed: usize,
    pub metamorphic_pairs_passed: usize,
    pub malformed_rejected: usize,
    pub corpus_digest_sha256: String,
    pub all_passed: bool,
}

impl Rung2ParityReceipt {
    pub fn to_canonical_json(&self) -> String {
        format!(
            "{{\"all_passed\":{},\"cases_per_family\":{},\"corpus_digest_sha256\":\"{}\",\"cycle_shrunk_minimal\":{},\"dag_clean_passed\":{},\"dead_leaves_passed\":{},\"diamond_dom_passed\":{},\"malformed_rejected\":{},\"master_seed\":{},\"metamorphic_pairs_passed\":{},\"total_cases\":{},\"wrapper_ast_passed\":{}}}",
            self.all_passed,
            self.cases_per_family,
            self.corpus_digest_sha256,
            self.cycle_shrunk_minimal,
            self.dag_clean_passed,
            self.dead_leaves_passed,
            self.diamond_dom_passed,
            self.malformed_rejected,
            self.master_seed,
            self.metamorphic_pairs_passed,
            self.total_cases,
            self.wrapper_ast_passed,
        )
    }
}

fn gen_dag(rng: &mut SplitMix64, n: usize, extra_dead: usize) -> GroundGraph {
    let mut mods = Vec::with_capacity(n + extra_dead);
    for i in 0..n {
        let mut imps = Vec::new();
        if i + 1 < n {
            // Ensure connected spine from M0 so root reaches core nodes.
            let next_idx = i + 1 + rng.next_usize(n - i - 1);
            imps.push(format!("M{}", next_idx));
            for j in (i + 1)..n {
                if j != next_idx && rng.next_u64().is_multiple_of(3) {
                    imps.push(format!("M{}", j));
                }
            }
        }
        let lines = 5 + (rng.next_u64() % 95);
        let bytes = lines * (20 + (rng.next_u64() % 30));
        mods.push(GroundModule {
            name: format!("M{}", i),
            lines,
            bytes,
            imports: imps,
            wrapper_kind: WrapperKind::Substantive,
        });
    }
    for d in 0..extra_dead {
        let mut imps = Vec::new();
        if n > 0 && rng.next_u64().is_multiple_of(2) {
            imps.push(format!("M{}", rng.next_usize(n)));
        }
        let lines = 10 + (rng.next_u64() % 40);
        let bytes = lines * 25;
        mods.push(GroundModule {
            name: format!("Dead{}", d),
            lines,
            bytes,
            imports: imps,
            wrapper_kind: WrapperKind::PureWrapper,
        });
    }
    GroundGraph {
        root: "M0".to_string(),
        modules: mods,
    }
}

/// Verifies every dominator `d in Dom(v)` strictly disconnects `v` from `root` when removed.
fn verify_dominator_cut_property(g: &GroundGraph, dom: &BTreeMap<String, BTreeSet<String>>) -> bool {
    let reach = g.reachable_from_root();
    if dom.len() != reach.len() {
        return false;
    }
    for v in &reach {
        let ds = match dom.get(v) {
            Some(s) => s,
            None => return false,
        };
        if !ds.contains(v) || !ds.contains(&g.root) {
            return false;
        }
        for d in ds {
            if d == v || d == &g.root {
                continue;
            }
            // Remove node d and check v is no longer reachable from root.
            let filtered = GroundGraph {
                root: g.root.clone(),
                modules: g
                    .modules
                    .iter()
                    .filter(|m| &m.name != d)
                    .map(|m| GroundModule {
                        name: m.name.clone(),
                        lines: m.lines,
                        bytes: m.bytes,
                        imports: m.imports.iter().filter(|x| *x != d).cloned().collect(),
                        wrapper_kind: m.wrapper_kind,
                    })
                    .collect(),
            };
            if filtered.reachable_from_root().contains(v) {
                return false;
            }
        }
    }
    true
}

pub fn run_rung2_parity_suite(master_seed: u64, cases_per_family: usize) -> Rung2ParityReceipt {
    let mut rng = SplitMix64::new(master_seed);
    let mut trace = String::new();

    let mut dag_clean_passed = 0usize;
    let mut cycle_shrunk_minimal = 0usize;
    let mut diamond_dom_passed = 0usize;
    let mut dead_leaves_passed = 0usize;
    let mut wrapper_ast_passed = 0usize;
    let mut metamorphic_pairs_passed = 0usize;

    // 1. FAM-DAG-CLEAN
    for c in 0..cases_per_family {
        let n = 4 + rng.next_usize(10);
        let g = gen_dag(&mut rng, n, 0);
        let enc = g.to_canonical_json();
        let rt_ok = decode_ground_graph_json(&enc)
            .map(|dec| dec.to_canonical_json() == enc)
            .unwrap_or(false);
        let reach = g.reachable_from_root();
        let dead = g.dead_leaves();
        let (rl, dl, tl, rb, db, tb) = g.mass_accounting();
        let ok = g.validate().is_ok()
            && !g.has_cycle()
            && rt_ok
            && reach.is_disjoint(&dead)
            && (reach.len() + dead.len() == g.modules.len())
            && (rl + dl == tl)
            && (rb + db == tb);
        if ok {
            dag_clean_passed += 1;
        }
        trace.push_str(&format!("D:{}:{}:{}:{};", c, reach.len(), dead.len(), tl));
    }

    // 2. FAM-CYCLE-INJECTED + QuickCheck Deterministic Shrinking
    for c in 0..cases_per_family {
        let n = 4 + rng.next_usize(8);
        let mut g = gen_dag(&mut rng, n, 0);
        // Guarantee a directed path M0 -> M1 -> ... -> M(n-1) and inject a back-edge M(b) -> M(a).
        for (i, m) in g.modules.iter_mut().enumerate().take(n - 1) {
            m.imports.push(format!("M{}", i + 1));
        }
        let a = rng.next_usize(n - 1);
        let b = a + 1 + rng.next_usize(n - 1 - a);
        g.modules[b].imports.push(format!("M{}", a));
        let g = g.canonicalized();
        let orig_edges = g.edge_count();
        let shrunk = shrink_cyclic_graph(&g);
        let ok = g.validate().is_ok()
            && g.has_cycle()
            && shrunk.edge_count() <= orig_edges
            && is_edge_minimal_cycle(&shrunk);
        if ok {
            cycle_shrunk_minimal += 1;
        }
        trace.push_str(&format!("C:{}:{}:{};", c, orig_edges, shrunk.edge_count()));
    }

    // 3. FAM-DIAMOND-DOM (Exact Fixed-Point Dominators + Cut Oracle)
    for c in 0..cases_per_family {
        let n = 5 + rng.next_usize(7);
        let g = gen_dag(&mut rng, n, 0).canonicalized();
        let dom = g.compute_dominators();
        let ok = g.validate().is_ok() && !g.has_cycle() && verify_dominator_cut_property(&g, &dom);
        if ok {
            diamond_dom_passed += 1;
        }
        let dom_sum: usize = dom.values().map(BTreeSet::len).sum();
        trace.push_str(&format!("M:{}:{}:{};", c, dom.len(), dom_sum));
    }

    // 4. FAM-DEAD-LEAVES
    for c in 0..cases_per_family {
        let n = 3 + rng.next_usize(5);
        let extra = 2 + rng.next_usize(5);
        let g = gen_dag(&mut rng, n, extra).canonicalized();
        let dead = g.dead_leaves();
        let (rl, dl, tl, rb, db, tb) = g.mass_accounting();
        let ok = g.validate().is_ok()
            && !g.has_cycle()
            && dead.len() >= extra
            && (rl + dl == tl)
            && (rb + db == tb);
        if ok {
            dead_leaves_passed += 1;
        }
        trace.push_str(&format!("L:{}:{}:{}:{};", c, dead.len(), dl, db));
    }

    // 5. FAM-WRAPPER-AST + MR-2 Comment/Blank-Line Invariance
    for c in 0..cases_per_family {
        let kind_sel = rng.next_usize(3);
        let (src, expected) = match kind_sel {
            0 => ("module\nimport Base.Core\nexport Base.Core (foo)\n".to_string(), WrapperKind::PureWrapper),
            1 => ("public import A.One\npublic import B.Two\n".to_string(), WrapperKind::ReexportHub),
            _ => ("import Base.Core\ntheorem sample_id (x : Nat) : x = x := rfl\n".to_string(), WrapperKind::Substantive),
        };
        let perturbed = format!("-- generated header {}\n\n/- block comment -/\n{}\n-- footer\n\n", c, src);
        let k1 = classify_wrapper_text(&src);
        let k2 = classify_wrapper_text(&perturbed);
        if k1 == expected && k2 == expected {
            wrapper_ast_passed += 1;
        }
        trace.push_str(&format!("W:{}:{};", c, k1.as_str()));
    }

    // 6. FAM-METAMORPHIC-INV (MR-1 permutation, MR-2 comments, MR-3 bijective non-root rename)
    for c in 0..cases_per_family {
        let n = 4 + rng.next_usize(6);
        let extra = 1 + rng.next_usize(3);
        let g = gen_dag(&mut rng, n, extra);
        let base_cycle = g.has_cycle();
        let base_reach = g.reachable_from_root().len();
        let base_dead = g.dead_leaves().len();
        let base_mass = g.mass_accounting();
        let mut base_dom_sizes: Vec<usize> = g.compute_dominators().values().map(BTreeSet::len).collect();
        base_dom_sizes.sort();

        // MR-1: Reverse module order and import order.
        let mut mr1_mods = g.modules.clone();
        mr1_mods.reverse();
        for m in &mut mr1_mods {
            m.imports.reverse();
        }
        let g_mr1 = GroundGraph { root: g.root.clone(), modules: mr1_mods };
        let mut mr1_dom_sizes: Vec<usize> = g_mr1.compute_dominators().values().map(BTreeSet::len).collect();
        mr1_dom_sizes.sort();
        if g_mr1.has_cycle() == base_cycle
            && g_mr1.reachable_from_root().len() == base_reach
            && g_mr1.dead_leaves().len() == base_dead
            && g_mr1.mass_accounting() == base_mass
            && mr1_dom_sizes == base_dom_sizes
            && g_mr1.to_canonical_json() == g.to_canonical_json()
        {
            metamorphic_pairs_passed += 1;
        }

        // MR-2: Comment/blank injection on wrapper text.
        let w_base = "import Core.A\nexport Core.A (x)\n";
        let w_pert = format!("\n-- mr2 {}\n{}\n\n-- end\n", c, w_base);
        if classify_wrapper_text(w_base) == classify_wrapper_text(&w_pert) {
            metamorphic_pairs_passed += 1;
        }

        // MR-3: Bijective rename of every non-root module (`X -> Ren_X`).
        let rename = |s: &str| -> String {
            if s == g.root {
                s.to_string()
            } else {
                format!("Ren_{}", s)
            }
        };
        let g_mr3 = GroundGraph {
            root: g.root.clone(),
            modules: g
                .modules
                .iter()
                .map(|m| GroundModule {
                    name: rename(&m.name),
                    lines: m.lines,
                    bytes: m.bytes,
                    imports: m.imports.iter().map(|imp| rename(imp)).collect(),
                    wrapper_kind: m.wrapper_kind,
                })
                .collect(),
        };
        let mut mr3_dom_sizes: Vec<usize> = g_mr3.compute_dominators().values().map(BTreeSet::len).collect();
        mr3_dom_sizes.sort();
        if g_mr3.has_cycle() == base_cycle
            && g_mr3.reachable_from_root().len() == base_reach
            && g_mr3.dead_leaves().len() == base_dead
            && g_mr3.mass_accounting() == base_mass
            && mr3_dom_sizes == base_dom_sizes
        {
            metamorphic_pairs_passed += 1;
        }

        trace.push_str(&format!("X:{}:{}:{}:{};", c, base_reach, base_dead, base_mass.2));
    }

    // 7. Malformed Negative Controls (4 must all fail closed!)
    let mut malformed_rejected = 0usize;
    let m_missing_root = GroundGraph {
        root: "Missing".to_string(),
        modules: vec![GroundModule {
            name: "A".to_string(),
            lines: 1,
            bytes: 10,
            imports: vec![],
            wrapper_kind: WrapperKind::Substantive,
        }],
    };
    if m_missing_root.validate().is_err() {
        malformed_rejected += 1;
    }
    let m_dup = GroundGraph {
        root: "A".to_string(),
        modules: vec![
            GroundModule { name: "A".to_string(), lines: 1, bytes: 10, imports: vec![], wrapper_kind: WrapperKind::Substantive },
            GroundModule { name: "A".to_string(), lines: 2, bytes: 20, imports: vec![], wrapper_kind: WrapperKind::Substantive },
        ],
    };
    if m_dup.validate().is_err() {
        malformed_rejected += 1;
    }
    let m_dangling = GroundGraph {
        root: "A".to_string(),
        modules: vec![GroundModule {
            name: "A".to_string(),
            lines: 1,
            bytes: 10,
            imports: vec!["Ghost".to_string()],
            wrapper_kind: WrapperKind::Substantive,
        }],
    };
    if m_dangling.validate().is_err() {
        malformed_rejected += 1;
    }
    if decode_ground_graph_json("{\"root\":\"A\",\"modules\":[").is_err() {
        malformed_rejected += 1;
    }

    let total_cases = cases_per_family * 6;
    let corpus_digest_sha256 = sha256_hex(trace.as_bytes());
    let all_passed = cases_per_family >= 30
        && dag_clean_passed == cases_per_family
        && cycle_shrunk_minimal == cases_per_family
        && diamond_dom_passed == cases_per_family
        && dead_leaves_passed == cases_per_family
        && wrapper_ast_passed == cases_per_family
        && metamorphic_pairs_passed == cases_per_family * 3
        && malformed_rejected == 4;

    Rung2ParityReceipt {
        master_seed,
        cases_per_family,
        total_cases,
        dag_clean_passed,
        cycle_shrunk_minimal,
        diamond_dom_passed,
        dead_leaves_passed,
        wrapper_ast_passed,
        metamorphic_pairs_passed,
        malformed_rejected,
        corpus_digest_sha256,
        all_passed,
    }
}
