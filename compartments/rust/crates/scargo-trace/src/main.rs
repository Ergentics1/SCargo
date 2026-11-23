// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

//! Independent module-DAG, dominator-tree (Cooper-Harvey-Kennedy), critical-path,
//! and primary-source verification tracer for `Riemannian`.
//!
//! Computes all graph, dominator, depth, and dominated-mass metrics directly from
//! live Lean 4 source files without copying external third-party traces.

#![forbid(unsafe_code)]

use std::collections::{HashMap, VecDeque};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Instant;

struct RawModule {
    rel_path: String,
    module_name: String,
    bytes: u64,
    lines: u64,
    imports: Vec<String>,
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
    let target = if first == "all" {
        parts.next()?
    } else {
        first
    };
    if target.is_empty() {
        None
    } else {
        Some(target.to_string())
    }
}

fn read_module(src_root: &Path, path: &Path) -> RawModule {
    let rel_path = path
        .strip_prefix(src_root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/");
    let module_name = rel_path
        .strip_suffix(".lean")
        .unwrap_or(&rel_path)
        .replace('/', ".");
    let raw = fs::read(path).unwrap_or_default();
    let bytes = raw.len() as u64;
    let text = String::from_utf8_lossy(&raw);
    let mut lines = 0u64;
    let mut imports = Vec::new();
    let mut in_header = true;
    for line in text.lines() {
        lines += 1;
        if !in_header {
            continue;
        }
        let trimmed = line.trim();
        if trimmed.is_empty()
            || trimmed == "module"
            || trimmed.starts_with("--")
            || trimmed.starts_with("/-")
        {
            continue;
        }
        if let Some(target) = parse_import_target(trimmed) {
            imports.push(target);
        } else {
            // Imports in Lean 4 must precede commands/sections.
            in_header = false;
        }
    }
    RawModule {
        rel_path,
        module_name,
        bytes,
        lines,
        imports,
    }
}

fn parallel_read(src_root: &Path, paths: &[PathBuf]) -> Vec<RawModule> {
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
                    .map(|p| read_module(src_root, p))
                    .collect::<Vec<_>>()
            }));
        }
        for h in handles {
            out.extend(h.join().expect("worker panicked"));
        }
    });
    out
}

/// Computes exact dominator tree on a directed graph rooted at `root`
/// using the Cooper-Harvey-Kennedy iterative algorithm over reverse postorder.
/// Returns `idom` indexed by dense reachable RPO id (`0 == root`, `idom[0] = 0`).
fn compute_dominators_rpo(n: usize, preds: &[Vec<usize>]) -> Vec<usize> {
    const UNDEF: usize = usize::MAX;
    let mut idom = vec![UNDEF; n];
    if n == 0 {
        return idom;
    }
    idom[0] = 0;

    let intersect = |mut b1: usize, mut b2: usize, idom: &[usize]| -> usize {
        while b1 != b2 {
            while b1 > b2 {
                b1 = idom[b1];
            }
            while b2 > b1 {
                b2 = idom[b2];
            }
        }
        b1
    };

    let mut changed = true;
    while changed {
        changed = false;
        for b in 1..n {
            let mut new_idom = UNDEF;
            for &p in &preds[b] {
                if idom[p] != UNDEF {
                    if new_idom == UNDEF {
                        new_idom = p;
                    } else {
                        new_idom = intersect(p, new_idom, &idom);
                    }
                }
            }
            if new_idom != UNDEF && idom[b] != new_idom {
                idom[b] = new_idom;
                changed = true;
            }
        }
    }
    idom
}

/// Iterative DFS postorder starting from `root`, producing RPO numbering (`0..rpo.len()`).
fn build_rpo(root: usize, adj: &[Vec<usize>]) -> (Vec<usize>, Vec<usize>) {
    let total = adj.len();
    let mut visited = vec![false; total];
    let mut postorder = Vec::new();
    let mut stack: Vec<(usize, usize)> = Vec::new();
    visited[root] = true;
    stack.push((root, 0));

    while let Some((u, idx)) = stack.last_mut() {
        let u_val = *u;
        if *idx < adj[u_val].len() {
            let v = adj[u_val][*idx];
            *idx += 1;
            if !visited[v] {
                visited[v] = true;
                stack.push((v, 0));
            }
        } else {
            postorder.push(u_val);
            stack.pop();
        }
    }

    postorder.reverse();
    let rpo_to_orig = postorder;
    let mut orig_to_rpo = vec![usize::MAX; total];
    for (rpo_id, &orig_id) in rpo_to_orig.iter().enumerate() {
        orig_to_rpo[orig_id] = rpo_id;
    }
    (rpo_to_orig, orig_to_rpo)
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

fn run_trace(
    root: &Path,
    root_mod: &str,
    lineage_path: Option<&Path>,
    out_path: &Path,
) -> Result<(), String> {
    let t0 = Instant::now();
    let src_root = root.join("src");
    if !src_root.is_dir() {
        return Err(format!("Expected src/ under {}", root.display()));
    }
    let mut paths = Vec::new();
    collect_lean_files(&src_root, &mut paths).map_err(|e| e.to_string())?;
    let mut mods = parallel_read(&src_root, &paths);
    mods.sort_by(|a, b| a.module_name.cmp(&b.module_name));

    let total_modules = mods.len();
    let mut name_to_id: HashMap<String, usize> = HashMap::with_capacity(total_modules);
    for (i, m) in mods.iter().enumerate() {
        name_to_id.insert(m.module_name.clone(), i);
    }

    let &root_id = name_to_id
        .get(root_mod)
        .ok_or_else(|| format!("Root module `{root_mod}` not found"))?;

    let mut adj: Vec<Vec<usize>> = vec![Vec::new(); total_modules];
    let mut total_project_edges = 0u64;
    let mut external_import_refs = 0u64;
    for (u, m) in mods.iter().enumerate() {
        let mut seen_local = Vec::new();
        for imp in &m.imports {
            if let Some(&v) = name_to_id.get(imp) {
                if !seen_local.contains(&v) {
                    seen_local.push(v);
                }
            } else {
                external_import_refs += 1;
            }
        }
        seen_local.sort_unstable();
        total_project_edges += seen_local.len() as u64;
        adj[u] = seen_local;
    }

    // 1. Build RPO from root_mod
    let (rpo_to_orig, orig_to_rpo) = build_rpo(root_id, &adj);
    let r_n = rpo_to_orig.len();

    let mut r_adj: Vec<Vec<usize>> = vec![Vec::new(); r_n];
    let mut r_preds: Vec<Vec<usize>> = vec![Vec::new(); r_n];
    let mut reachable_edges = 0u64;
    let mut reachable_lines = 0u64;
    let mut reachable_bytes = 0u64;

    for r_u in 0..r_n {
        let orig_u = rpo_to_orig[r_u];
        reachable_lines += mods[orig_u].lines;
        reachable_bytes += mods[orig_u].bytes;
        for &orig_v in &adj[orig_u] {
            let r_v = orig_to_rpo[orig_v];
            if r_v != usize::MAX {
                r_adj[r_u].push(r_v);
                r_preds[r_v].push(r_u);
                reachable_edges += 1;
            }
        }
    }

    // 2. Kahn's topological sort + acyclicity check + longest-path depth from leaves
    let mut out_deg: Vec<usize> = r_adj.iter().map(|v| v.len()).collect();
    let mut q = VecDeque::new();
    for (u, &deg) in out_deg.iter().enumerate() {
        if deg == 0 {
            q.push_back(u);
        }
    }
    let mut topo_from_leaves = Vec::with_capacity(r_n);
    let mut longest_chain_height = vec![0u32; r_n];
    while let Some(u) = q.pop_front() {
        topo_from_leaves.push(u);
        let h_u = longest_chain_height[u];
        for &p in &r_preds[u] {
            if h_u + 1 > longest_chain_height[p] {
                longest_chain_height[p] = h_u + 1;
            }
            out_deg[p] -= 1;
            if out_deg[p] == 0 {
                q.push_back(p);
            }
        }
    }
    let is_acyclic = topo_from_leaves.len() == r_n;
    let critical_path_len = longest_chain_height[0];

    // 3. Shortest BFS distance from root_mod
    let mut bfs_dist = vec![u32::MAX; r_n];
    let mut bq = VecDeque::new();
    bfs_dist[0] = 0;
    bq.push_back(0usize);
    while let Some(u) = bq.pop_front() {
        let d = bfs_dist[u];
        for &v in &r_adj[u] {
            if bfs_dist[v] == u32::MAX {
                bfs_dist[v] = d + 1;
                bq.push_back(v);
            }
        }
    }
    let max_bfs_dist = bfs_dist.iter().copied().filter(|&d| d != u32::MAX).max().unwrap_or(0);

    // 4. Exact Cooper-Harvey-Kennedy Dominator Tree
    let idom = compute_dominators_rpo(r_n, &r_preds);
    let mut dom_children: Vec<Vec<usize>> = vec![Vec::new(); r_n];
    for (u, &parent) in idom.iter().enumerate().skip(1) {
        if parent < r_n {
            dom_children[parent].push(u);
        }
    }

    // Bottom-up accumulation of uniquely dominated subtree mass
    let mut dom_mods = vec![1u64; r_n];
    let mut dom_lines = vec![0u64; r_n];
    let mut dom_bytes = vec![0u64; r_n];
    for u in 0..r_n {
        let orig = rpo_to_orig[u];
        dom_lines[u] = mods[orig].lines;
        dom_bytes[u] = mods[orig].bytes;
    }

    // Postorder traversal of dominator tree
    let mut dom_post = Vec::with_capacity(r_n);
    let mut dstack: Vec<(usize, bool)> = vec![(0, false)];
    while let Some((u, expanded)) = dstack.pop() {
        if expanded {
            dom_post.push(u);
        } else {
            dstack.push((u, true));
            for &c in &dom_children[u] {
                dstack.push((c, false));
            }
        }
    }
    for u in dom_post {
        if u == 0 {
            continue;
        }
        let p = idom[u];
        if p < r_n {
            dom_mods[p] += dom_mods[u];
            dom_lines[p] += dom_lines[u];
            dom_bytes[p] += dom_bytes[u];
        }
    }

    // Top dominators excluding root `Main` and trivial root wrappers with dom_mods == r_n
    let mut dom_rank: Vec<usize> = (1..r_n).collect();
    dom_rank.sort_by(|&a, &b| {
        dom_lines[b]
            .cmp(&dom_lines[a])
            .then(dom_mods[b].cmp(&dom_mods[a]))
            .then(mods[rpo_to_orig[a]].module_name.cmp(&mods[rpo_to_orig[b]].module_name))
    });

    // Top fan-in modules (most directly imported across reachable graph)
    let mut fanin_rank: Vec<usize> = (0..r_n).collect();
    fanin_rank.sort_by(|&a, &b| {
        r_preds[b]
            .len()
            .cmp(&r_preds[a].len())
            .then(mods[rpo_to_orig[a]].module_name.cmp(&mods[rpo_to_orig[b]].module_name))
    });

    // Top spine modules (BFS distance <= 3 from Main)
    let mut spine_nodes: Vec<usize> = (0..r_n).filter(|&u| bfs_dist[u] <= 2).collect();
    spine_nodes.sort_by(|&a, &b| {
        bfs_dist[a]
            .cmp(&bfs_dist[b])
            .then(dom_lines[b].cmp(&dom_lines[a]))
    });

    // Load lineage reachability audit targets from immutable data file (strict code/data separation)
    let target_prefixes = match lineage_path {
        Some(lp) => load_lineage_targets(lp)?,
        None => Vec::new(),
    };

    let elapsed_ms = t0.elapsed().as_millis();
    let sha = git_head_sha(root);

    let mut json = String::with_capacity(64 * 1024);
    json.push_str("{\n");
    json.push_str("  \"schema_version\": \"1.0.0\",\n");
    json.push_str("  \"copyright\": \"Copyright (c) 2026 Ergentics, LLC\",\n");
    json.push_str("  \"tool\": \"scargo-trace/0.1.0\",\n");
    json.push_str("  \"algorithm\": \"Cooper-Harvey-Kennedy iterative dominators + Kahn DAG longest-path\",\n");
    json.push_str(&format!("  \"source_repo_commit\": {},\n", json_escape(&sha)));
    json.push_str(&format!("  \"root_module\": {},\n", json_escape(root_mod)));
    json.push_str(&format!("  \"trace_elapsed_ms\": {},\n", elapsed_ms));
    json.push_str("  \"graph_summary\": {\n");
    json.push_str(&format!("    \"total_modules_scanned\": {},\n", total_modules));
    json.push_str(&format!("    \"reachable_modules\": {},\n", r_n));
    json.push_str(&format!("    \"reachable_lines\": {},\n", reachable_lines));
    json.push_str(&format!("    \"reachable_bytes\": {},\n", reachable_bytes));
    json.push_str(&format!("    \"total_project_import_edges\": {},\n", total_project_edges));
    json.push_str(&format!("    \"reachable_project_import_edges\": {},\n", reachable_edges));
    json.push_str(&format!("    \"external_import_refs\": {},\n", external_import_refs));
    json.push_str(&format!("    \"is_acyclic\": {},\n", is_acyclic));
    json.push_str(&format!("    \"critical_path_depth\": {},\n", critical_path_len));
    json.push_str(&format!("    \"max_bfs_distance_from_root\": {}\n", max_bfs_dist));
    json.push_str("  },\n");

    let write_node = |buf: &mut String, u: usize, comma: &str| {
        let orig = rpo_to_orig[u];
        let m = &mods[orig];
        let idom_name = if u == 0 {
            "<ROOT>".to_string()
        } else {
            mods[rpo_to_orig[idom[u]]].module_name.clone()
        };
        let dom_line_pct = if reachable_lines > 0 {
            100.0 * (dom_lines[u] as f64) / (reachable_lines as f64)
        } else {
            0.0
        };
        let dom_mod_pct = if r_n > 0 {
            100.0 * (dom_mods[u] as f64) / (r_n as f64)
        } else {
            0.0
        };
        buf.push_str(&format!(
            "    {{\"module\": {}, \"path\": {}, \"bfs_dist\": {}, \"chain_height\": {}, \"fan_in\": {}, \"fan_out\": {}, \"idom\": {}, \"dominated_modules\": {}, \"dominated_modules_pct\": {:.3}, \"dominated_lines\": {}, \"dominated_lines_pct\": {:.3}, \"dominated_bytes\": {}}}{}\n",
            json_escape(&m.module_name),
            json_escape(&m.rel_path),
            bfs_dist[u],
            longest_chain_height[u],
            r_preds[u].len(),
            r_adj[u].len(),
            json_escape(&idom_name),
            dom_mods[u],
            dom_mod_pct,
            dom_lines[u],
            dom_line_pct,
            dom_bytes[u],
            comma
        ));
    };

    json.push_str("  \"top_module_dominators\": [\n");
    let top_d = dom_rank.len().min(30);
    for (idx, &u) in dom_rank[..top_d].iter().enumerate() {
        write_node(&mut json, u, if idx + 1 < top_d { "," } else { "" });
    }
    json.push_str("  ],\n");

    json.push_str("  \"top_fan_in_hubs\": [\n");
    let top_f = fanin_rank.len().min(20);
    for (idx, &u) in fanin_rank[..top_f].iter().enumerate() {
        write_node(&mut json, u, if idx + 1 < top_f { "," } else { "" });
    }
    json.push_str("  ],\n");

    json.push_str("  \"root_spine_depth_le_2\": [\n");
    let top_s = spine_nodes.len().min(40);
    for (idx, &u) in spine_nodes[..top_s].iter().enumerate() {
        write_node(&mut json, u, if idx + 1 < top_s { "," } else { "" });
    }
    json.push_str("  ],\n");

    json.push_str("  \"lineage_reachability_audit\": [\n");
    for (idx, (src_id, prefix)) in target_prefixes.iter().enumerate() {
        let mut matched_reach = 0u64;
        let mut matched_lines = 0u64;
        let mut matched_bytes = 0u64;
        let mut min_bfs = u32::MAX;
        let mut max_dom_lines = 0u64;
        let mut max_dom_mods = 0u64;
        for u in 0..r_n {
            let m = &mods[rpo_to_orig[u]];
            if m.module_name == *prefix || m.module_name.starts_with(&format!("{prefix}.")) {
                matched_reach += 1;
                matched_lines += m.lines;
                matched_bytes += m.bytes;
                if bfs_dist[u] < min_bfs {
                    min_bfs = bfs_dist[u];
                }
                if dom_lines[u] > max_dom_lines {
                    max_dom_lines = dom_lines[u];
                }
                if dom_mods[u] > max_dom_mods {
                    max_dom_mods = dom_mods[u];
                }
            }
        }
        let comma = if idx + 1 < target_prefixes.len() { "," } else { "" };
        json.push_str(&format!(
            "    {{\"source_id\": {}, \"module_prefix\": {}, \"verified_reachable\": {}, \"reachable_modules\": {}, \"reachable_lines\": {}, \"reachable_bytes\": {}, \"min_bfs_dist\": {}, \"max_node_dominated_modules\": {}, \"max_node_dominated_lines\": {}}}{}\n",
            json_escape(src_id),
            json_escape(prefix),
            matched_reach > 0,
            matched_reach,
            matched_lines,
            matched_bytes,
            if min_bfs == u32::MAX { 0 } else { min_bfs },
            max_dom_mods,
            max_dom_lines,
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
        "scargo-trace complete: {r_n}/{total_modules} reachable, {reachable_edges} edges, acyclic={is_acyclic}, critical_path={critical_path_len}, lineage_targets={}, {elapsed_ms} ms -> {}",
        target_prefixes.len(),
        out_path.display()
    );
    Ok(())
}

fn extract_json_string_field(line: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\":");
    let pos = line.find(&needle)?;
    let rest = line[pos + needle.len()..].trim_start();
    let rest = rest.strip_prefix('"')?;
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn parse_lineage_targets_str(content: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut current_id: Option<String> = None;
    for line in content.lines() {
        if let Some(id) = extract_json_string_field(line, "id") {
            current_id = Some(id);
        }
        if let Some(prefix) = extract_json_string_field(line, "trace_module_prefix") {
            if let Some(id) = current_id.take() {
                out.push((id, prefix));
            }
        }
    }
    out
}

fn load_lineage_targets(path: &Path) -> Result<Vec<(String, String)>, String> {
    let content = fs::read_to_string(path)
        .map_err(|e| format!("Failed to read lineage file {}: {e}", path.display()))?;
    let pairs = parse_lineage_targets_str(&content);
    if pairs.is_empty() {
        return Err(format!(
            "No (id, trace_module_prefix) entries found in {}",
            path.display()
        ));
    }
    Ok(pairs)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let get_arg = |flag: &str| -> Option<String> {
        args.windows(2).find(|w| w[0] == flag).map(|w| w[1].clone())
    };
    let root = PathBuf::from(get_arg("--root").unwrap_or_else(|| "../Riemannian".into()));
    let root_mod = get_arg("--root-module").unwrap_or_else(|| "Main".into());
    let lineage = get_arg("--lineage").map(PathBuf::from);
    let out = PathBuf::from(
        get_arg("--out").unwrap_or_else(|| "data/traces/riemannian_trace.json".into()),
    );
    if let Err(e) = run_trace(&root, &root_mod, lineage.as_deref(), &out) {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dominators_diamond_graph() {
        // 0 -> 1, 0 -> 2, 1 -> 3, 2 -> 3, 3 -> 4
        // idom(1)=0, idom(2)=0, idom(3)=0, idom(4)=3
        let adj = vec![vec![1, 2], vec![3], vec![3], vec![4], vec![]];
        let (rpo_to_orig, orig_to_rpo) = build_rpo(0, &adj);
        let n = rpo_to_orig.len();
        let mut preds = vec![Vec::new(); n];
        for (u, outs) in adj.iter().enumerate() {
            let ru = orig_to_rpo[u];
            for &v in outs {
                preds[orig_to_rpo[v]].push(ru);
            }
        }
        let idom = compute_dominators_rpo(n, &preds);
        let orig_idom = |orig_u: usize| rpo_to_orig[idom[orig_to_rpo[orig_u]]];
        assert_eq!(orig_idom(1), 0);
        assert_eq!(orig_idom(2), 0);
        assert_eq!(orig_idom(3), 0);
        assert_eq!(orig_idom(4), 3);
    }

    #[test]
    fn test_parse_import_all() {
        assert_eq!(
            parse_import_target("public import all Foo.Bar"),
            Some("Foo.Bar".to_string())
        );
        assert_eq!(
            parse_import_target("private import Baz"),
            Some("Baz".to_string())
        );
        assert_eq!(
            parse_import_target("meta import Lean"),
            Some("Lean".to_string())
        );
        assert_eq!(
            parse_import_target("public meta import Foo.Meta"),
            Some("Foo.Meta".to_string())
        );
    }

    #[test]
    fn test_parse_lineage_targets_str() {
        let sample = r#"{
          "entries": [
            { "id": "SRC-01", "trace_module_prefix": "Statements" },
            { "id": "SRC-02", "trace_module_prefix": "Main" }
          ]
        }"#;
        assert_eq!(
            parse_lineage_targets_str(sample),
            vec![
                ("SRC-01".to_string(), "Statements".to_string()),
                ("SRC-02".to_string(), "Main".to_string()),
            ]
        );
    }
}
