// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

use std::collections::{BTreeMap, HashMap, HashSet};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Instant;

#[derive(Default, Clone)]
struct BucketStats {
    files: u64,
    bytes: u64,
    lines: u64,
    non_blank_lines: u64,
}

impl BucketStats {
    fn add(&mut self, bytes: u64, lines: u64, non_blank: u64) {
        self.files += 1;
        self.bytes += bytes;
        self.lines += lines;
        self.non_blank_lines += non_blank;
    }
}

struct FileRecord {
    rel_path: String,
    module_name: String,
    lib: String,
    level2: String,
    level3: String,
    bytes: u64,
    lines: u64,
    non_blank_lines: u64,
    blank_lines: u64,
    imports: Vec<String>,
    imports_full_mathlib: bool,
    public_import_lines: u64,
    private_import_lines: u64,
    open_lines: u64,
    set_option_lines: u64,
    explicit_at_lines: u64,
    is_fallback_wrapper: bool,
    is_statement_named: bool,
    private_thm_count: u64,
    decl_counts: [u64; 8], // theorem, lemma, def, abbrev, structure, class, instance, inductive
}

const DECL_KINDS: [&str; 8] = [
    "theorem",
    "lemma",
    "def",
    "abbrev",
    "structure",
    "class",
    "instance",
    "inductive",
];

fn collect_lean_files(dir: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    let mut subdirs = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        let path = entry.path();
        if ft.is_dir() {
            subdirs.push(path);
        } else if ft.is_file() && path.extension().and_then(|e| e.to_str()) == Some("lean") {
            out.push(path);
        }
    }
    for sub in subdirs {
        collect_lean_files(&sub, out)?;
    }
    Ok(())
}

fn classify_decl_keyword(line: &str) -> Option<usize> {
    let trimmed = line.trim_start();
    if trimmed.is_empty() || trimmed.starts_with("--") || trimmed.starts_with("/-") {
        return None;
    }
    let mut rest = trimmed;
    loop {
        if rest.starts_with("@[") {
            let end = rest.find(']')?;
            rest = rest[end + 1..].trim_start();
            continue;
        }
        let mut matched_mod = false;
        for modifier in [
            "public ",
            "private ",
            "protected ",
            "noncomputable ",
            "unsafe ",
            "partial ",
            "scoped ",
            "local ",
        ] {
            if let Some(after) = rest.strip_prefix(modifier) {
                rest = after.trim_start();
                matched_mod = true;
                break;
            }
        }
        if !matched_mod {
            break;
        }
    }
    for (idx, kw) in DECL_KINDS.iter().enumerate() {
        if let Some(after) = rest.strip_prefix(kw) {
            if after.is_empty() || after.starts_with(char::is_whitespace) {
                return Some(idx);
            }
        }
    }
    None
}

fn parse_import_target(trimmed: &str) -> Option<(bool, String)> {
    let mut rest = trimmed;
    let mut is_pub = false;
    loop {
        if let Some(r) = rest.strip_prefix("public ") {
            is_pub = true;
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
    let target = if first == "all" {
        parts.next()?
    } else {
        first
    };
    if target.is_empty() {
        return None;
    }
    Some((is_pub, target.to_string()))
}

fn analyze_file(src_root: &Path, path: &Path) -> FileRecord {
    let rel = path
        .strip_prefix(src_root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    let module_name = rel
        .strip_suffix(".lean")
        .unwrap_or(&rel)
        .replace('/', ".");
    let parts: Vec<&str> = rel.split('/').collect();
    let lib = if parts.len() > 1 {
        parts[0].to_string()
    } else {
        "<root>".to_string()
    };
    let level2 = if parts.len() > 2 {
        format!("{}/{}", parts[0], parts[1])
    } else {
        lib.clone()
    };
    let level3 = if parts.len() > 3 {
        format!("{}/{}/{}", parts[0], parts[1], parts[2])
    } else {
        level2.clone()
    };
    let file_name = parts.last().copied().unwrap_or("");
    let is_statement_named = file_name.contains("Statement");

    let raw = fs::read(path).unwrap_or_default();
    let bytes = raw.len() as u64;
    let text = String::from_utf8_lossy(&raw);

    let mut lines = 0u64;
    let mut blank_lines = 0u64;
    let mut non_blank_lines = 0u64;
    let mut imports = Vec::new();
    let mut imports_full_mathlib = false;
    let mut public_import_lines = 0u64;
    let mut private_import_lines = 0u64;
    let mut open_lines = 0u64;
    let mut set_option_lines = 0u64;
    let mut explicit_at_lines = 0u64;
    let mut private_thm_count = 0u64;
    let mut decl_counts = [0u64; 8];

    let mut has_first_exact_at = false;
    let mut has_assumption = false;

    for line in text.lines() {
        lines += 1;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            blank_lines += 1;
            continue;
        }
        non_blank_lines += 1;

        if trimmed.contains("first | exact @") {
            has_first_exact_at = true;
        }
        if trimmed.contains("<;> assumption)") {
            has_assumption = true;
        }

        if let Some((is_pub, target)) = parse_import_target(trimmed) {
            if is_pub {
                public_import_lines += 1;
            } else {
                private_import_lines += 1;
            }
            if target == "Mathlib" {
                imports_full_mathlib = true;
            }
            imports.push(target);
        } else if trimmed.starts_with("open ") {
            open_lines += 1;
        } else if trimmed.starts_with("set_option ") {
            set_option_lines += 1;
        }

        if trimmed.as_bytes().iter().filter(|&&b| b == b'@').count() >= 5 {
            explicit_at_lines += 1;
        }

        if trimmed.starts_with("private theorem ") || trimmed.starts_with("private lemma ") {
            private_thm_count += 1;
        }

        if let Some(kind_idx) = classify_decl_keyword(line) {
            decl_counts[kind_idx] += 1;
        }
    }

    FileRecord {
        rel_path: rel,
        module_name,
        lib,
        level2,
        level3,
        bytes,
        lines,
        non_blank_lines,
        blank_lines,
        imports,
        imports_full_mathlib,
        public_import_lines,
        private_import_lines,
        open_lines,
        set_option_lines,
        explicit_at_lines,
        is_fallback_wrapper: has_first_exact_at && has_assumption,
        is_statement_named,
        private_thm_count,
        decl_counts,
    }
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
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn git_head_sha(root: &Path) -> String {
    let git_dir = root.join(".git");
    let head = match fs::read_to_string(git_dir.join("HEAD")) {
        Ok(s) => s.trim().to_string(),
        Err(_) => return "unknown".to_string(),
    };
    if let Some(ref_path) = head.strip_prefix("ref:") {
        let ref_rel = ref_path.trim();
        if let Ok(sha) = fs::read_to_string(git_dir.join(ref_rel)) {
            let trimmed = sha.trim();
            if !trimmed.is_empty() {
                return trimmed.to_string();
            }
        }
        if let Ok(packed) = fs::read_to_string(git_dir.join("packed-refs")) {
            for line in packed.lines() {
                let l = line.trim();
                if l.is_empty() || l.starts_with('#') || l.starts_with('^') {
                    continue;
                }
                if let Some((sha, name)) = l.split_once(' ') {
                    if name.trim() == ref_rel {
                        return sha.trim().to_string();
                    }
                }
            }
        }
        "unknown".to_string()
    } else if !head.is_empty() {
        head
    } else {
        "unknown".to_string()
    }
}

fn line_bucket(lines: u64) -> &'static str {
    if lines <= 20 {
        "<=20"
    } else if lines <= 50 {
        "21-50"
    } else if lines <= 100 {
        "51-100"
    } else if lines <= 250 {
        "101-250"
    } else if lines <= 1000 {
        "251-1000"
    } else {
        ">1000"
    }
}

fn parallel_analyze(src_root: &Path, paths: &[PathBuf]) -> Vec<FileRecord> {
    let workers = thread::available_parallelism()
        .map(|n| (n.get() * 8).clamp(8, 32))
        .unwrap_or(16);
    let chunk_size = paths.len().div_ceil(workers);
    if chunk_size == 0 {
        return Vec::new();
    }
    let mut results: Vec<FileRecord> = Vec::with_capacity(paths.len());
    thread::scope(|s| {
        let mut handles = Vec::new();
        for chunk in paths.chunks(chunk_size) {
            handles.push(s.spawn(move || {
                chunk
                    .iter()
                    .map(|p| analyze_file(src_root, p))
                    .collect::<Vec<_>>()
            }));
        }
        for h in handles {
            results.extend(h.join().expect("worker panicked"));
        }
    });
    results
}

struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }

    fn shuffle<T>(&mut self, slice: &mut [T]) {
        for i in (1..slice.len()).rev() {
            let j = (self.next_u64() as usize) % (i + 1);
            slice.swap(i, j);
        }
    }
}

fn run_scan(root: &Path, out_path: &Path) -> Result<(), String> {
    let t0 = Instant::now();
    let src_root = root.join("src");
    if !src_root.is_dir() {
        return Err(format!("Expected src/ directory under {}", root.display()));
    }
    let mut paths = Vec::new();
    collect_lean_files(&src_root, &mut paths).map_err(|e| e.to_string())?;
    let records = parallel_analyze(&src_root, &paths);

    let mut total = BucketStats::default();
    let mut total_blank = 0u64;
    let mut by_lib: BTreeMap<String, BucketStats> = BTreeMap::new();
    let mut by_level2: BTreeMap<String, BucketStats> = BTreeMap::new();
    let mut by_level3: BTreeMap<String, BucketStats> = BTreeMap::new();
    let mut line_hist: BTreeMap<&'static str, u64> = BTreeMap::new();
    for k in ["<=20", "21-50", "51-100", "101-250", "251-1000", ">1000"] {
        line_hist.insert(k, 0);
    }

    let mut fallback_files = 0u64;
    let mut fallback_lines = 0u64;
    let mut fallback_bytes = 0u64;
    let mut stmt_files = 0u64;
    let mut stmt_lines = 0u64;
    let mut mathlib_files = 0u64;
    let mut pub_imports = 0u64;
    let mut priv_imports = 0u64;
    let mut open_lines = 0u64;
    let mut set_option_lines = 0u64;
    let mut explicit_at_lines = 0u64;
    let mut private_thm_occurrences = 0u64;
    let mut decl_totals = [0u64; 8];

    let mut module_set: HashSet<String> = HashSet::with_capacity(records.len());
    let mut adj: HashMap<String, Vec<String>> = HashMap::with_capacity(records.len());
    let mut largest: Vec<(u64, u64, String)> = Vec::with_capacity(records.len());

    for r in &records {
        total.add(r.bytes, r.lines, r.non_blank_lines);
        total_blank += r.blank_lines;
        by_lib
            .entry(r.lib.clone())
            .or_default()
            .add(r.bytes, r.lines, r.non_blank_lines);
        by_level2
            .entry(r.level2.clone())
            .or_default()
            .add(r.bytes, r.lines, r.non_blank_lines);
        by_level3
            .entry(r.level3.clone())
            .or_default()
            .add(r.bytes, r.lines, r.non_blank_lines);
        *line_hist.entry(line_bucket(r.lines)).or_insert(0) += 1;

        if r.is_fallback_wrapper {
            fallback_files += 1;
            fallback_lines += r.lines;
            fallback_bytes += r.bytes;
        }
        if r.is_statement_named {
            stmt_files += 1;
            stmt_lines += r.lines;
        }
        if r.imports_full_mathlib {
            mathlib_files += 1;
        }
        pub_imports += r.public_import_lines;
        priv_imports += r.private_import_lines;
        open_lines += r.open_lines;
        set_option_lines += r.set_option_lines;
        explicit_at_lines += r.explicit_at_lines;
        private_thm_occurrences += r.private_thm_count;
        for i in 0..8 {
            decl_totals[i] += r.decl_counts[i];
        }
        module_set.insert(r.module_name.clone());
        adj.insert(r.module_name.clone(), r.imports.clone());
        largest.push((r.bytes, r.lines, r.rel_path.clone()));
    }

    // Reachability from Main
    let mut visited: HashSet<String> = HashSet::with_capacity(records.len());
    let mut stack = vec!["Main".to_string()];
    while let Some(m) = stack.pop() {
        if !module_set.contains(&m) || !visited.insert(m.clone()) {
            continue;
        }
        if let Some(deps) = adj.get(&m) {
            for d in deps {
                if module_set.contains(d) && !visited.contains(d) {
                    stack.push(d.clone());
                }
            }
        }
    }

    let mut unreachable_project: Vec<String> = module_set
        .iter()
        .filter(|m| !visited.contains(*m) && m.as_str() != "Challenge")
        .cloned()
        .collect();
    unreachable_project.sort();

    // Sort top subtrees by bytes descending
    let mut lib_vec: Vec<(String, BucketStats)> = by_lib.into_iter().collect();
    lib_vec.sort_by(|a, b| b.1.bytes.cmp(&a.1.bytes).then(a.0.cmp(&b.0)));

    let mut l2_vec: Vec<(String, BucketStats)> = by_level2.into_iter().collect();
    l2_vec.sort_by(|a, b| b.1.bytes.cmp(&a.1.bytes).then(a.0.cmp(&b.0)));
    l2_vec.truncate(25);

    let mut l3_vec: Vec<(String, BucketStats)> = by_level3.into_iter().collect();
    l3_vec.sort_by(|a, b| b.1.bytes.cmp(&a.1.bytes).then(a.0.cmp(&b.0)));
    l3_vec.truncate(25);

    largest.sort_by(|a, b| b.0.cmp(&a.0).then(a.2.cmp(&b.2)));
    largest.truncate(20);

    let elapsed_ms = t0.elapsed().as_millis();
    let sha = git_head_sha(root);

    let mut json = String::with_capacity(64 * 1024);
    json.push_str("{\n");
    json.push_str("  \"schema_version\": \"1.0.0\",\n");
    json.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    json.push_str("  \"tool\": \"scargo-probe/0.1.0\",\n");
    json.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&sha)));
    json.push_str(&format!("  \"scan_elapsed_ms\": {},\n", elapsed_ms));
    json.push_str("  \"totals\": {\n");
    json.push_str(&format!("    \"files\": {},\n", total.files));
    json.push_str(&format!("    \"bytes\": {},\n", total.bytes));
    json.push_str(&format!("    \"lines\": {},\n", total.lines));
    json.push_str(&format!("    \"non_blank_lines\": {},\n", total.non_blank_lines));
    json.push_str(&format!("    \"blank_lines\": {}\n", total_blank));
    json.push_str("  },\n");

    json.push_str("  \"import_graph\": {\n");
    json.push_str(&format!("    \"total_modules\": {},\n", module_set.len()));
    json.push_str(&format!("    \"reachable_from_main\": {},\n", visited.len()));
    json.push_str(&format!(
        "    \"unreachable_project_modules_count\": {},\n",
        unreachable_project.len()
    ));
    json.push_str("    \"unreachable_project_modules\": [\n");
    for (i, m) in unreachable_project.iter().enumerate() {
        let comma = if i + 1 < unreachable_project.len() { "," } else { "" };
        json.push_str(&format!("      {}{}\n", json_escape(m), comma));
    }
    json.push_str("    ]\n  },\n");

    json.push_str("  \"bloat_metrics\": {\n");
    json.push_str(&format!("    \"fallback_wrapper_files\": {},\n", fallback_files));
    json.push_str(&format!("    \"fallback_wrapper_lines\": {},\n", fallback_lines));
    json.push_str(&format!("    \"fallback_wrapper_bytes\": {},\n", fallback_bytes));
    json.push_str(&format!("    \"statement_named_files\": {},\n", stmt_files));
    json.push_str(&format!("    \"statement_named_lines\": {},\n", stmt_lines));
    json.push_str(&format!("    \"files_importing_full_mathlib\": {},\n", mathlib_files));
    json.push_str(&format!("    \"public_import_lines\": {},\n", pub_imports));
    json.push_str(&format!("    \"private_import_lines\": {},\n", priv_imports));
    json.push_str(&format!("    \"open_lines\": {},\n", open_lines));
    json.push_str(&format!("    \"set_option_lines\": {},\n", set_option_lines));
    json.push_str(&format!("    \"explicit_at_lines_ge5\": {},\n", explicit_at_lines));
    json.push_str(&format!("    \"private_theorem_occurrences\": {}\n", private_thm_occurrences));
    json.push_str("  },\n");

    json.push_str("  \"declarations\": {\n");
    for (i, kw) in DECL_KINDS.iter().enumerate() {
        let comma = if i + 1 < DECL_KINDS.len() { "," } else { "" };
        json.push_str(&format!("    {}: {}{}\n", json_escape(kw), decl_totals[i], comma));
    }
    json.push_str("  },\n");

    json.push_str("  \"line_count_histogram\": {\n");
    let hist_keys = ["<=20", "21-50", "51-100", "101-250", "251-1000", ">1000"];
    for (i, k) in hist_keys.iter().enumerate() {
        let comma = if i + 1 < hist_keys.len() { "," } else { "" };
        json.push_str(&format!(
            "    {}: {}{}\n",
            json_escape(k),
            line_hist.get(k).copied().unwrap_or(0),
            comma
        ));
    }
    json.push_str("  },\n");

    let write_buckets = |buf: &mut String, name: &str, items: &[(String, BucketStats)], trailing_comma: bool| {
        buf.push_str(&format!("  {}: [\n", json_escape(name)));
        for (i, (k, s)) in items.iter().enumerate() {
            let comma = if i + 1 < items.len() { "," } else { "" };
            buf.push_str(&format!(
                "    {{\"name\": {}, \"files\": {}, \"bytes\": {}, \"lines\": {}, \"non_blank_lines\": {}}}{}\n",
                json_escape(k),
                s.files,
                s.bytes,
                s.lines,
                s.non_blank_lines,
                comma
            ));
        }
        buf.push_str(&format!("  ]{}\n", if trailing_comma { "," } else { "" }));
    };

    write_buckets(&mut json, "libraries", &lib_vec, true);
    write_buckets(&mut json, "top_level2_subtrees", &l2_vec, true);
    write_buckets(&mut json, "top_level3_subtrees", &l3_vec, true);

    json.push_str("  \"largest_files\": [\n");
    for (i, (b, l, p)) in largest.iter().enumerate() {
        let comma = if i + 1 < largest.len() { "," } else { "" };
        json.push_str(&format!(
            "    {{\"path\": {}, \"bytes\": {}, \"lines\": {}}}{}\n",
            json_escape(p),
            b,
            l,
            comma
        ));
    }
    json.push_str("  ]\n}\n");

    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let mut f = fs::File::create(out_path).map_err(|e| e.to_string())?;
    f.write_all(json.as_bytes()).map_err(|e| e.to_string())?;
    eprintln!(
        "scargo-probe scan complete: {} files, {} lines, {} bytes in {} ms -> {}",
        total.files,
        total.lines,
        total.bytes,
        elapsed_ms,
        out_path.display()
    );
    Ok(())
}

fn run_rct_sample(
    root: &Path,
    seed: u64,
    per_stratum: usize,
    filter: &str,
    out_path: &Path,
) -> Result<(), String> {
    let src_root = root.join("src");
    let mut paths = Vec::new();
    collect_lean_files(&src_root, &mut paths).map_err(|e| e.to_string())?;
    let records = parallel_analyze(&src_root, &paths);
    let sha = git_head_sha(root);

    let mut strata: BTreeMap<String, Vec<&FileRecord>> = BTreeMap::new();
    for r in &records {
        if r.module_name == "Main" || r.module_name == "Challenge" || r.module_name == "Statements"
        {
            continue;
        }
        let eligible = match filter {
            "all" => true,
            "wrappers" => r.is_fallback_wrapper,
            "explicit" => r.explicit_at_lines > 0,
            other => return Err(format!("Unknown filter: {other}")),
        };
        if !eligible {
            continue;
        }
        let key = format!("{}::{}", r.lib, line_bucket(r.lines));
        strata.entry(key).or_default().push(r);
    }

    let mut rng = SplitMix64::new(seed);
    let mut assignments: Vec<(String, &'static str, &FileRecord)> = Vec::new();

    for (stratum, mut pool) in strata {
        pool.sort_by(|a, b| a.rel_path.cmp(&b.rel_path));
        rng.shuffle(&mut pool);
        let pairs = (pool.len() / 2).min(per_stratum);
        for rec in &pool[..pairs] {
            assignments.push((stratum.clone(), "treatment", *rec));
        }
        for rec in &pool[pairs..pairs * 2] {
            assignments.push((stratum.clone(), "control", *rec));
        }
    }

    let mut json = String::with_capacity(32 * 1024);
    json.push_str("{\n");
    json.push_str("  \"schema_version\": \"1.0.0\",\n");
    json.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    json.push_str("  \"tool\": \"scargo-probe/0.1.0\",\n");
    json.push_str("  \"study_design\": \"stratified_rct\",\n");
    json.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&sha)));
    json.push_str(&format!("  \"prng_seed\": {},\n", seed));
    json.push_str(&format!("  \"filter\": {},\n", json_escape(filter)));
    json.push_str(&format!("  \"max_pairs_per_stratum\": {},\n", per_stratum));
    json.push_str(&format!("  \"total_assigned\": {},\n", assignments.len()));
    json.push_str("  \"units\": [\n");
    for (i, (stratum, arm, r)) in assignments.iter().enumerate() {
        let comma = if i + 1 < assignments.len() { "," } else { "" };
        json.push_str(&format!(
            "    {{\"stratum\": {}, \"arm\": {}, \"path\": {}, \"module\": {}, \"baseline_lines\": {}, \"baseline_bytes\": {}}}{}\n",
            json_escape(stratum),
            json_escape(arm),
            json_escape(&r.rel_path),
            json_escape(&r.module_name),
            r.lines,
            r.bytes,
            comma
        ));
    }
    json.push_str("  ]\n}\n");

    if let Some(parent) = out_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(out_path, json.as_bytes()).map_err(|e| e.to_string())?;
    eprintln!(
        "scargo-probe rct-sample complete: {} units assigned (seed={}, filter={}) -> {}",
        assignments.len(),
        seed,
        filter,
        out_path.display()
    );
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage:\n  scargo-probe scan --root <dir> --out <file.json>\n  scargo-probe rct-sample --root <dir> --seed <u64> --per-stratum <N> --filter <all|wrappers|explicit> --out <file.json>");
        std::process::exit(2);
    }

    let get_arg = |flag: &str| -> Option<String> {
        args.windows(2).find(|w| w[0] == flag).map(|w| w[1].clone())
    };

    let res = match args[1].as_str() {
        "scan" => {
            let root = PathBuf::from(get_arg("--root").unwrap_or_else(|| "../Riemannian".into()));
            let out = PathBuf::from(
                get_arg("--out").unwrap_or_else(|| "data/baselines/inventory.json".into()),
            );
            run_scan(&root, &out)
        }
        "rct-sample" => {
            let root = PathBuf::from(get_arg("--root").unwrap_or_else(|| "../Riemannian".into()));
            let seed: u64 = get_arg("--seed")
                .and_then(|s| s.parse().ok())
                .unwrap_or(20261122);
            let per_stratum: usize = get_arg("--per-stratum")
                .and_then(|s| s.parse().ok())
                .unwrap_or(10);
            let filter = get_arg("--filter").unwrap_or_else(|| "wrappers".into());
            let out = PathBuf::from(
                get_arg("--out").unwrap_or_else(|| "data/baselines/rct_sample.json".into()),
            );
            run_rct_sample(&root, seed, per_stratum, &filter, &out)
        }
        cmd => Err(format!("Unknown subcommand: {cmd}")),
    };

    if let Err(e) = res {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_import_target() {
        assert_eq!(
            parse_import_target("public import Mathlib"),
            Some((true, "Mathlib".to_string()))
        );
        assert_eq!(
            parse_import_target("public import all Foo.Bar"),
            Some((true, "Foo.Bar".to_string()))
        );
        assert_eq!(
            parse_import_target("private import Formalism.Foo"),
            Some((false, "Formalism.Foo".to_string()))
        );
        assert_eq!(
            parse_import_target("meta import Lean"),
            Some((false, "Lean".to_string()))
        );
        assert_eq!(
            parse_import_target("import Statements"),
            Some((false, "Statements".to_string()))
        );
        assert_eq!(parse_import_target("open Mathlib"), None);
    }

    #[test]
    fn test_classify_decl_keyword() {
        assert_eq!(classify_decl_keyword("theorem foo : True := trivial"), Some(0));
        assert_eq!(classify_decl_keyword("private lemma bar : True := trivial"), Some(1));
        assert_eq!(classify_decl_keyword("@[simp] noncomputable def baz := 1"), Some(2));
        assert_eq!(classify_decl_keyword("-- theorem comment"), None);
    }

    #[test]
    fn test_splitmix64_deterministic() {
        let mut a = SplitMix64::new(42);
        let mut b = SplitMix64::new(42);
        let mut v1 = vec![1, 2, 3, 4, 5, 6, 7, 8];
        let mut v2 = v1.clone();
        a.shuffle(&mut v1);
        b.shuffle(&mut v2);
        assert_eq!(v1, v2);
    }
}
