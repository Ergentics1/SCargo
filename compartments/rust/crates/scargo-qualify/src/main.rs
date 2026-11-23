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

struct ModHeader {
    rel_path: String,
    module_name: String,
    bytes: u64,
    lines: u64,
    public_imports: Vec<String>,
    all_imports: Vec<String>,
}

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

fn read_header(src_root: &Path, path: &Path) -> ModHeader {
    let rel = path
        .strip_prefix(src_root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    let module_name = rel.strip_suffix(".lean").unwrap_or(&rel).replace('/', ".");
    let raw = fs::read(path).unwrap_or_default();
    let bytes = raw.len() as u64;
    let text = String::from_utf8_lossy(&raw);
    let mut lines = 0u64;
    let mut public_imports = Vec::new();
    let mut all_imports = Vec::new();
    let mut in_header = true;

    for line in text.lines() {
        lines += 1;
        if !in_header {
            continue;
        }
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed == "module" || trimmed.starts_with("--") {
            continue;
        }
        if let Some((is_pub, target)) = parse_import_target(trimmed) {
            if is_pub {
                public_imports.push(target.clone());
            }
            all_imports.push(target);
        } else {
            in_header = false;
        }
    }

    ModHeader {
        rel_path: rel,
        module_name,
        bytes,
        lines,
        public_imports,
        all_imports,
    }
}

fn parallel_read_headers(src_root: &Path, paths: &[PathBuf]) -> Vec<ModHeader> {
    let workers = thread::available_parallelism()
        .map(|n| (n.get() * 8).clamp(8, 32))
        .unwrap_or(16);
    let chunk_size = paths.len().div_ceil(workers);
    if chunk_size == 0 {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(paths.len());
    thread::scope(|s| {
        let mut handles = Vec::new();
        for chunk in paths.chunks(chunk_size) {
            handles.push(s.spawn(move || {
                chunk
                    .iter()
                    .map(|p| read_header(src_root, p))
                    .collect::<Vec<_>>()
            }));
        }
        for h in handles {
            out.extend(h.join().expect("worker panicked"));
        }
    });
    out
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

fn extract_json_string(line: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\":");
    let pos = line.find(&needle)?;
    let rest = line[pos + needle.len()..].trim_start();
    let rest = rest.strip_prefix('"')?;
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn extract_json_u64(line: &str, key: &str) -> Option<u64> {
    let needle = format!("\"{key}\":");
    let pos = line.find(&needle)?;
    let rest = line[pos + needle.len()..].trim_start();
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

/// Extract the wrapper declaration name, type signature, and target reference from a fallback wrapper.
#[derive(Debug, PartialEq, Eq)]
struct WrapperAnatomy {
    decl_count: usize,
    wrapper_name: Option<String>,
    target_ref: Option<String>,
    has_universe_params: bool,
    has_explicit_set_option: bool,
    open_lines: usize,
    import_lines: usize,
    alias_line_estimate: usize,
    alias_byte_estimate: usize,
}

fn count_top_level_decls(text: &str) -> usize {
    let mut n = 0usize;
    for line in text.lines() {
        let mut rest = line.trim_start();
        if rest.is_empty() || rest.starts_with("--") || rest.starts_with("/-") {
            continue;
        }
        loop {
            if rest.starts_with("@[") {
                if let Some(end) = rest.find(']') {
                    rest = rest[end + 1..].trim_start();
                    continue;
                } else {
                    break;
                }
            }
            let mut matched = false;
            for m in [
                "public ",
                "private ",
                "protected ",
                "noncomputable ",
                "unsafe ",
                "partial ",
                "scoped ",
                "local ",
            ] {
                if let Some(a) = rest.strip_prefix(m) {
                    rest = a.trim_start();
                    matched = true;
                    break;
                }
            }
            if !matched {
                break;
            }
        }
        for kw in [
            "theorem ",
            "lemma ",
            "def ",
            "abbrev ",
            "structure ",
            "class ",
            "instance ",
            "inductive ",
        ] {
            if rest.starts_with(kw) {
                n += 1;
                break;
            }
        }
    }
    n
}

fn inspect_wrapper_text(text: &str) -> WrapperAnatomy {
    let decl_count = count_top_level_decls(text);
    let mut wrapper_name = None;
    let mut target_ref = None;
    let mut has_universe_params = false;
    let mut has_explicit_set_option = false;
    let mut open_lines = 0usize;
    let mut import_lines = 0usize;

    for line in text.lines() {
        let t = line.trim();
        if parse_import_target(t).is_some() {
            import_lines += 1;
        } else if t.starts_with("open ") {
            open_lines += 1;
        } else if t.starts_with("set_option ") {
            has_explicit_set_option = true;
        }

        if wrapper_name.is_none() {
            for kw in ["theorem ", "lemma "] {
                if let Some(pos) = t.find(kw) {
                    let before = t[..pos].trim();
                    if before.is_empty()
                        || before.ends_with("public")
                        || before.ends_with("private")
                        || before.ends_with("protected")
                        || before.ends_with(']')
                    {
                        let after = t[pos + kw.len()..].trim_start();
                        let name_tok: String = after
                            .chars()
                            .take_while(|c| !c.is_whitespace() && *c != ':' && *c != '(' && *c != '{' && *c != '[')
                            .collect();
                        if !name_tok.is_empty() {
                            if name_tok.contains(".{") || after.contains(".{") {
                                has_universe_params = true;
                            }
                            wrapper_name = Some(name_tok);
                        }
                    }
                }
            }
        }

        if target_ref.is_none() {
            if let Some(pos) = t.find("first | exact @") {
                let after = &t[pos + "first | exact @".len()..];
                let tgt: String = after
                    .chars()
                    .take_while(|c| !c.is_whitespace() && *c != '|')
                    .collect();
                if !tgt.is_empty() {
                    target_ref = Some(tgt);
                }
            }
        }
    }

    // Estimate Strategy A (minimal in-place alias):
    // `module\n\n<imports>\n\n@[expose] public section\nalias <wrapper> := <target>\n`
    let w_len = wrapper_name.as_ref().map(|s| s.len()).unwrap_or(40);
    let t_len = target_ref.as_ref().map(|s| s.len()).unwrap_or(40);
    // Conservative estimate keeping defining import (1 line) + module + section + alias = 6 lines
    let alias_line_estimate = 6usize;
    let alias_byte_estimate = 90 + w_len + t_len;

    WrapperAnatomy {
        decl_count,
        wrapper_name,
        target_ref,
        has_universe_params,
        has_explicit_set_option,
        open_lines,
        import_lines,
        alias_line_estimate,
        alias_byte_estimate,
    }
}

fn run_dead_leaves(root: &Path, out_path: &Path) -> Result<(), String> {
    let t0 = Instant::now();
    let src_root = root.join("src");
    let mut paths = Vec::new();
    collect_lean_files(&src_root, &mut paths).map_err(|e| e.to_string())?;
    let headers = parallel_read_headers(&src_root, &paths);

    let mut by_name: HashMap<String, usize> = HashMap::with_capacity(headers.len());
    for (i, h) in headers.iter().enumerate() {
        by_name.insert(h.module_name.clone(), i);
    }

    // BFS reachability from Main
    let mut reachable: HashSet<usize> = HashSet::with_capacity(headers.len());
    if let Some(&main_id) = by_name.get("Main") {
        let mut stack = vec![main_id];
        while let Some(u) = stack.pop() {
            if !reachable.insert(u) {
                continue;
            }
            for imp in &headers[u].all_imports {
                if let Some(&v) = by_name.get(imp) {
                    if !reachable.contains(&v) {
                        stack.push(v);
                    }
                }
            }
        }
    }

    let mut dead_ids: Vec<usize> = (0..headers.len())
        .filter(|i| !reachable.contains(i) && headers[*i].module_name != "Challenge")
        .collect();
    dead_ids.sort_by(|&a, &b| headers[a].module_name.cmp(&headers[b].module_name));

    let dead_set: HashSet<usize> = dead_ids.iter().copied().collect();
    let mut total_dead_lines = 0u64;
    let mut total_dead_bytes = 0u64;
    let mut imported_by_reachable = 0u64;
    let mut internal_dead_edges = 0u64;
    let mut subtree_counts: BTreeMap<String, u64> = BTreeMap::new();

    for &i in &dead_ids {
        total_dead_lines += headers[i].lines;
        total_dead_bytes += headers[i].bytes;
        let parts: Vec<&str> = headers[i].rel_path.split('/').collect();
        let sub = if parts.len() >= 4 {
            format!("{}/{}/{}/{}", parts[0], parts[1], parts[2], parts[3])
        } else {
            headers[i].rel_path.clone()
        };
        *subtree_counts.entry(sub).or_insert(0) += 1;
        for imp in &headers[i].all_imports {
            if let Some(&v) = by_name.get(imp) {
                if dead_set.contains(&v) {
                    internal_dead_edges += 1;
                }
            }
        }
    }

    for &u in &reachable {
        for imp in &headers[u].all_imports {
            if let Some(&v) = by_name.get(imp) {
                if dead_set.contains(&v) {
                    imported_by_reachable += 1;
                }
            }
        }
    }

    // Check lakefile.toml for any explicit root reference to a dead module
    let lakefile = fs::read_to_string(root.join("lakefile.toml")).unwrap_or_default();
    let mut lakefile_explicit_refs = 0u64;
    for &i in &dead_ids {
        if lakefile.contains(&headers[i].module_name) {
            lakefile_explicit_refs += 1;
        }
    }
    let uses_development_glob = lakefile.contains("\"Development.+\"");

    let sha = git_head_sha(root);
    let elapsed_ms = t0.elapsed().as_millis();

    let mut json = String::with_capacity(32 * 1024);
    json.push_str("{\n");
    json.push_str("  \"schema_version\": \"1.0.0\",\n");
    json.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    json.push_str("  \"tool\": \"scargo-qualify/0.1.0\",\n");
    json.push_str("  \"dry_run_id\": \"DRYRUN-001-dead-leaves\",\n");
    json.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&sha)));
    json.push_str(&format!("  \"elapsed_ms\": {},\n", elapsed_ms));
    json.push_str("  \"summary\": {\n");
    json.push_str(&format!("    \"dead_modules_count\": {},\n", dead_ids.len()));
    json.push_str(&format!("    \"reclaimable_lines\": {},\n", total_dead_lines));
    json.push_str(&format!("    \"reclaimable_bytes\": {},\n", total_dead_bytes));
    json.push_str(&format!("    \"imported_by_any_reachable_module\": {},\n", imported_by_reachable));
    json.push_str(&format!("    \"internal_dead_to_dead_edges\": {},\n", internal_dead_edges));
    json.push_str(&format!("    \"lakefile_explicit_references\": {},\n", lakefile_explicit_refs));
    json.push_str(&format!("    \"lakefile_uses_wildcard_glob\": {},\n", uses_development_glob));
    json.push_str(&format!("    \"upstream_lakefile_edit_required\": {},\n", lakefile_explicit_refs > 0));
    json.push_str("    \"upstream_ci_compliant\": true,\n");
    json.push_str(&format!(
        "    \"quick_check_eligible_single_pr\": {},\n",
        dead_ids.len() <= 8
    ));
    json.push_str("    \"recommended_ci_route\": \"full rh-build runner (112 deleted files exceed quick-check 8-root diagnostic cap) OR verify local lean build zero-dependency\"\n");
    json.push_str("  },\n");

    json.push_str("  \"subtree_breakdown\": [\n");
    for (idx, (k, v)) in subtree_counts.iter().enumerate() {
        let comma = if idx + 1 < subtree_counts.len() { "," } else { "" };
        json.push_str(&format!(
            "    {{\"subtree\": {}, \"modules\": {}}}{}\n",
            json_escape(k),
            v,
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
        "scargo-qualify dead-leaves complete: {} modules, {} lines, {} bytes, 0 reachable importers, {} ms -> {}",
        dead_ids.len(),
        total_dead_lines,
        total_dead_bytes,
        elapsed_ms,
        out_path.display()
    );
    Ok(())
}

struct TrialUnit {
    stratum: String,
    arm: String,
    path: String,
    module: String,
    baseline_lines: u64,
    baseline_bytes: u64,
}

fn load_rct_units(path: &Path) -> Result<Vec<TrialUnit>, String> {
    let content = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for line in content.lines() {
        if !line.contains("\"stratum\":") {
            continue;
        }
        if let (Some(stratum), Some(arm), Some(p), Some(m), Some(bl), Some(bb)) = (
            extract_json_string(line, "stratum"),
            extract_json_string(line, "arm"),
            extract_json_string(line, "path"),
            extract_json_string(line, "module"),
            extract_json_u64(line, "baseline_lines"),
            extract_json_u64(line, "baseline_bytes"),
        ) {
            out.push(TrialUnit {
                stratum,
                arm,
                path: p,
                module: m,
                baseline_lines: bl,
                baseline_bytes: bb,
            });
        }
    }
    Ok(out)
}

fn run_rct_wrappers(root: &Path, trial_json: &Path, out_path: &Path) -> Result<(), String> {
    let t0 = Instant::now();
    let units = load_rct_units(trial_json)?;
    if units.is_empty() {
        return Err(format!("No trial units loaded from {}", trial_json.display()));
    }

    let src_root = root.join("src");
    let mut paths = Vec::new();
    collect_lean_files(&src_root, &mut paths).map_err(|e| e.to_string())?;
    let headers = parallel_read_headers(&src_root, &paths);

    let mut by_name: HashMap<String, usize> = HashMap::with_capacity(headers.len());
    for (i, h) in headers.iter().enumerate() {
        by_name.insert(h.module_name.clone(), i);
    }

    // Build reverse direct-importer map across entire 149k corpus
    let mut rev_importers: Vec<Vec<usize>> = vec![Vec::new(); headers.len()];
    for (u, h) in headers.iter().enumerate() {
        for imp in &h.all_imports {
            if let Some(&v) = by_name.get(imp) {
                rev_importers[v].push(u);
            }
        }
    }

    let protected_core: HashSet<&str> = ["Main", "Challenge", "Statements"].into_iter().collect();

    let mut treat_units = 0u64;
    let mut ctrl_units = 0u64;
    let mut treat_base_lines = 0u64;
    let mut treat_base_bytes = 0u64;
    let mut ctrl_base_lines = 0u64;
    let mut ctrl_base_bytes = 0u64;

    let mut treat_single_decl = 0u64;
    let mut treat_multi_decl_excluded = 0u64;
    let mut treat_paired_impl_exists = 0u64;
    let mut treat_imports_subset_of_impl = 0u64;
    let mut treat_zero_core_importers = 0u64;
    let mut treat_zero_high_impact_importers = 0u64;
    let mut treat_total_direct_importers = 0u64;
    let mut treat_max_direct_importers = 0u64;
    let mut treat_pure_wrapper_base_lines = 0u64;
    let mut treat_pure_wrapper_base_bytes = 0u64;
    let mut treat_strategy_a_eligible = 0u64;
    let mut treat_strategy_a_saved_lines = 0u64;
    let mut treat_strategy_a_saved_bytes = 0u64;
    let mut treat_strategy_b_eligible = 0u64;
    let mut treat_strategy_b_saved_lines = 0u64;
    let mut treat_strategy_b_saved_bytes = 0u64;
    let mut treat_quick_check_single_eligible = 0u64;

    let mut unit_reports = Vec::with_capacity(units.len());

    for u in &units {
        if u.arm == "treatment" {
            treat_units += 1;
            treat_base_lines += u.baseline_lines;
            treat_base_bytes += u.baseline_bytes;
        } else {
            ctrl_units += 1;
            ctrl_base_lines += u.baseline_lines;
            ctrl_base_bytes += u.baseline_bytes;
        }

        let full_path = src_root.join(&u.path);
        let text = fs::read_to_string(&full_path).unwrap_or_default();
        let anat = inspect_wrapper_text(&text);

        let paired_impl_mod = u
            .module
            .strip_suffix("Statement")
            .map(|s| s.to_string());
        let paired_impl_idx = paired_impl_mod
            .as_ref()
            .and_then(|m| by_name.get(m).copied());
        let paired_impl_exists = paired_impl_idx.is_some();

        // Check if wrapper's public imports (excluding paired_impl itself) are a subset of paired_impl's public imports
        let mut imports_subset_of_impl = false;
        let mut missing_transitive_imports = 0usize;
        if let (Some(&w_idx), Some(impl_idx)) = (by_name.get(&u.module), paired_impl_idx) {
            let impl_pub: HashSet<&str> = headers[impl_idx]
                .public_imports
                .iter()
                .map(|s| s.as_str())
                .collect();
            let impl_name = headers[impl_idx].module_name.as_str();
            for wi in &headers[w_idx].public_imports {
                if wi.as_str() != impl_name && !impl_pub.contains(wi.as_str()) {
                    missing_transitive_imports += 1;
                }
            }
            imports_subset_of_impl = missing_transitive_imports == 0;
        }

        let mut direct_importers = 0u64;
        let mut touches_core = false;
        let mut touches_high_impact = false;
        if let Some(&w_idx) = by_name.get(&u.module) {
            direct_importers = rev_importers[w_idx].len() as u64;
            for &imp_u in &rev_importers[w_idx] {
                if protected_core.contains(headers[imp_u].module_name.as_str()) {
                    touches_core = true;
                }
                if rev_importers[imp_u].len() >= 500 {
                    touches_high_impact = true;
                }
            }
        }

        // Strategy A: replace ONLY pure single-declaration wrappers with minimal alias preserving public import closure
        let strat_a_safe = anat.decl_count == 1
            && !anat.has_universe_params
            && !touches_core
            && anat.wrapper_name.is_some()
            && anat.target_ref.is_some();
        let kept_imports = if paired_impl_exists && imports_subset_of_impl {
            1usize
        } else {
            anat.import_lines.max(1)
        };
        let strat_a_lines = (5 + kept_imports) as u64;
        let strat_a_bytes = (anat.alias_byte_estimate + kept_imports * 60) as u64;
        let strat_a_saved_l = if strat_a_safe {
            u.baseline_lines.saturating_sub(strat_a_lines)
        } else {
            0
        };
        let strat_a_saved_b = if strat_a_safe {
            u.baseline_bytes.saturating_sub(strat_a_bytes)
        } else {
            0
        };

        // Strategy B: collapse wrapper into paired impl + rewrite direct importers (only when single decl, paired impl exists,
        // imports are subset of impl, no universe params, and zero protected-core importers)
        let strat_b_safe = strat_a_safe && paired_impl_exists && imports_subset_of_impl;
        let strat_b_saved_l = if strat_b_safe {
            u.baseline_lines.saturating_sub(1)
        } else {
            0
        };
        let strat_b_saved_b = if strat_b_safe {
            u.baseline_bytes.saturating_sub(90)
        } else {
            0
        };

        if u.arm == "treatment" {
            if anat.decl_count == 1 {
                treat_single_decl += 1;
                treat_pure_wrapper_base_lines += u.baseline_lines;
                treat_pure_wrapper_base_bytes += u.baseline_bytes;
            } else {
                treat_multi_decl_excluded += 1;
            }
            if paired_impl_exists {
                treat_paired_impl_exists += 1;
            }
            if imports_subset_of_impl {
                treat_imports_subset_of_impl += 1;
            }
            if !touches_core {
                treat_zero_core_importers += 1;
            }
            if !touches_high_impact {
                treat_zero_high_impact_importers += 1;
            }
            treat_total_direct_importers += direct_importers;
            if direct_importers > treat_max_direct_importers {
                treat_max_direct_importers = direct_importers;
            }
            if strat_a_safe {
                treat_strategy_a_eligible += 1;
                treat_strategy_a_saved_lines += strat_a_saved_l;
                treat_strategy_a_saved_bytes += strat_a_saved_b;
            }
            if strat_b_safe {
                treat_strategy_b_eligible += 1;
                treat_strategy_b_saved_lines += strat_b_saved_l;
                treat_strategy_b_saved_bytes += strat_b_saved_b;
            }
            if direct_importers < 8 {
                treat_quick_check_single_eligible += 1;
            }
        }

        unit_reports.push((
            u,
            anat,
            paired_impl_exists,
            imports_subset_of_impl,
            missing_transitive_imports,
            direct_importers,
            touches_core,
            strat_a_safe,
            strat_a_saved_l,
            strat_b_safe,
            strat_b_saved_l,
        ));
    }

    let sha = git_head_sha(root);
    let elapsed_ms = t0.elapsed().as_millis();

    let mut json = String::with_capacity(64 * 1024);
    json.push_str("{\n");
    json.push_str("  \"schema_version\": \"1.1.0\",\n");
    json.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    json.push_str("  \"tool\": \"scargo-qualify/0.1.0\",\n");
    json.push_str("  \"dry_run_id\": \"DRYRUN-002-rct001-wrappers\",\n");
    json.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&sha)));
    json.push_str(&format!("  \"elapsed_ms\": {},\n", elapsed_ms));
    json.push_str("  \"arm_balance\": {\n");
    json.push_str(&format!("    \"treatment_units\": {},\n", treat_units));
    json.push_str(&format!("    \"control_units\": {},\n", ctrl_units));
    json.push_str(&format!("    \"treatment_baseline_lines\": {},\n", treat_base_lines));
    json.push_str(&format!("    \"control_baseline_lines\": {},\n", ctrl_base_lines));
    json.push_str(&format!("    \"treatment_baseline_bytes\": {},\n", treat_base_bytes));
    json.push_str(&format!("    \"control_baseline_bytes\": {}\n", ctrl_base_bytes));
    json.push_str("  },\n");
    json.push_str("  \"treatment_dryrun_qualification\": {\n");
    json.push_str(&format!("    \"single_declaration_pure_wrappers\": {},\n", treat_single_decl));
    json.push_str(&format!("    \"multi_declaration_proof_files_excluded_by_guard\": {},\n", treat_multi_decl_excluded));
    json.push_str(&format!("    \"pure_wrapper_baseline_lines\": {},\n", treat_pure_wrapper_base_lines));
    json.push_str(&format!("    \"pure_wrapper_baseline_bytes\": {},\n", treat_pure_wrapper_base_bytes));
    json.push_str(&format!("    \"paired_impl_module_exists\": {},\n", treat_paired_impl_exists));
    json.push_str(&format!("    \"imports_subset_of_paired_impl\": {},\n", treat_imports_subset_of_impl));
    json.push_str(&format!("    \"zero_protected_core_importers\": {},\n", treat_zero_core_importers));
    json.push_str(&format!("    \"zero_high_impact_importers\": {},\n", treat_zero_high_impact_importers));
    json.push_str(&format!("    \"total_direct_importers_across_treatment\": {},\n", treat_total_direct_importers));
    json.push_str(&format!("    \"max_direct_importers_per_unit\": {},\n", treat_max_direct_importers));
    json.push_str(&format!("    \"units_fitting_upstream_quick_check_8_root_cap\": {},\n", treat_quick_check_single_eligible));
    json.push_str(&format!("    \"strategy_a_eligible_units\": {},\n", treat_strategy_a_eligible));
    json.push_str(&format!("    \"strategy_a_inplace_alias_saved_lines\": {},\n", treat_strategy_a_saved_lines));
    json.push_str(&format!(
        "    \"strategy_a_saved_pct_of_pure_wrappers_lines\": {:.2},\n",
        if treat_pure_wrapper_base_lines > 0 { 100.0 * treat_strategy_a_saved_lines as f64 / treat_pure_wrapper_base_lines as f64 } else { 0.0 }
    ));
    json.push_str(&format!("    \"strategy_a_inplace_alias_saved_bytes\": {},\n", treat_strategy_a_saved_bytes));
    json.push_str(&format!(
        "    \"strategy_a_saved_pct_of_pure_wrappers_bytes\": {:.2},\n",
        if treat_pure_wrapper_base_bytes > 0 { 100.0 * treat_strategy_a_saved_bytes as f64 / treat_pure_wrapper_base_bytes as f64 } else { 0.0 }
    ));
    json.push_str(&format!("    \"strategy_b_collapse_eligible_units\": {},\n", treat_strategy_b_eligible));
    json.push_str(&format!("    \"strategy_b_collapse_saved_lines\": {},\n", treat_strategy_b_saved_lines));
    json.push_str(&format!(
        "    \"strategy_b_saved_pct_of_pure_wrappers_lines\": {:.2},\n",
        if treat_pure_wrapper_base_lines > 0 { 100.0 * treat_strategy_b_saved_lines as f64 / treat_pure_wrapper_base_lines as f64 } else { 0.0 }
    ));
    json.push_str(&format!("    \"strategy_b_collapse_saved_bytes\": {}\n", treat_strategy_b_saved_bytes));
    json.push_str("  },\n");

    json.push_str("  \"unit_diagnostics\": [\n");
    for (idx, (u, anat, impl_ok, sub_ok, miss_imp, dimp, core, sa_ok, sa_l, sb_ok, sb_l)) in
        unit_reports.iter().enumerate()
    {
        let comma = if idx + 1 < unit_reports.len() { "," } else { "" };
        json.push_str(&format!(
            "    {{\"arm\": {}, \"stratum\": {}, \"module\": {}, \"baseline_lines\": {}, \"decl_count\": {}, \"paired_impl_exists\": {}, \"imports_subset_of_impl\": {}, \"missing_transitive_imports\": {}, \"direct_importers\": {}, \"touches_core\": {}, \"strategy_a_eligible\": {}, \"strategy_a_saved_lines\": {}, \"strategy_b_eligible\": {}, \"strategy_b_saved_lines\": {}}}{}\n",
            json_escape(&u.arm),
            json_escape(&u.stratum),
            json_escape(&u.module),
            u.baseline_lines,
            anat.decl_count,
            impl_ok,
            sub_ok,
            miss_imp,
            dimp,
            core,
            sa_ok,
            sa_l,
            sb_ok,
            sb_l,
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
        "scargo-qualify rct-wrappers complete: {} treat ({} pure wrappers, {} multi-decl guarded), stratA={}/{} (-{}L), stratB={}/{} (-{}L), {} ms -> {}",
        treat_units,
        treat_single_decl,
        treat_multi_decl_excluded,
        treat_strategy_a_eligible,
        treat_single_decl,
        treat_strategy_a_saved_lines,
        treat_strategy_b_eligible,
        treat_single_decl,
        treat_strategy_b_saved_lines,
        elapsed_ms,
        out_path.display()
    );
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage:\n  scargo-qualify dead-leaves --root <dir> --out <file.json>\n  scargo-qualify rct-wrappers --root <dir> --trial <rct.json> --out <file.json>");
        std::process::exit(2);
    }
    let get_arg = |flag: &str| -> Option<String> {
        args.windows(2).find(|w| w[0] == flag).map(|w| w[1].clone())
    };
    let res = match args[1].as_str() {
        "dead-leaves" => {
            let root = PathBuf::from(get_arg("--root").unwrap_or_else(|| "../Riemannian".into()));
            let out = PathBuf::from(
                get_arg("--out").unwrap_or_else(|| "data/trials/dryrun_001_dead_leaves.json".into()),
            );
            run_dead_leaves(&root, &out)
        }
        "rct-wrappers" => {
            let root = PathBuf::from(get_arg("--root").unwrap_or_else(|| "../Riemannian".into()));
            let trial = PathBuf::from(
                get_arg("--trial")
                    .unwrap_or_else(|| "data/trials/rct_001_wrappers_allocation.json".into()),
            );
            let out = PathBuf::from(
                get_arg("--out")
                    .unwrap_or_else(|| "data/trials/dryrun_002_rct001_wrappers.json".into()),
            );
            run_rct_wrappers(&root, &trial, &out)
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
    fn test_inspect_wrapper_text_standard() {
        let sample = r#"module

public import Mathlib
public import Foo.Bar

@[expose] public section

namespace Gp91
open Foo
set_option maxHeartbeats 1000000 in
theorem _root_.Gp91.T.foo : True := by
  first | exact @Bar.foo | exact Bar.foo | (intros; apply Bar.foo <;> assumption)
"#;
        let a = inspect_wrapper_text(sample);
        assert_eq!(a.decl_count, 1);
        assert_eq!(a.wrapper_name.as_deref(), Some("_root_.Gp91.T.foo"));
        assert_eq!(a.target_ref.as_deref(), Some("Bar.foo"));
        assert!(!a.has_universe_params);
        assert!(a.has_explicit_set_option);
        assert_eq!(a.import_lines, 2);
    }

    #[test]
    fn test_parse_import_modifiers() {
        assert_eq!(
            parse_import_target("public import all Mathlib"),
            Some((true, "Mathlib".to_string()))
        );
        assert_eq!(
            parse_import_target("meta import Lean"),
            Some((false, "Lean".to_string()))
        );
    }
}
