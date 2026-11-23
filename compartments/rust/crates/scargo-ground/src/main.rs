// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Rung 2 Shared Ground Codec, QuickCheck Shrinking, Metamorphic Suite & Parity Harness.

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use scargo_ground::run_rung2_parity_suite;

fn extract_u64_field(json: &str, key: &str) -> Option<u64> {
    let needle = format!("\"{}\":", key);
    let idx = json.find(&needle)?;
    let rest = json[idx + needle.len()..].trim_start();
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse::<u64>().ok()
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let root = args
        .iter()
        .position(|a| a == "--root")
        .and_then(|i| args.get(i + 1))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    let emit_json = args.iter().any(|a| a == "--json");

    let cfg_path = root.join("data/trials/rung2_fuzz_corpus_v1.json");
    let raw = match fs::read_to_string(&cfg_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[ERROR] failed to read {}: {}", cfg_path.display(), e);
            return ExitCode::FAILURE;
        }
    };
    let seed = match extract_u64_field(&raw, "master_seed") {
        Some(v) => v,
        None => {
            eprintln!("[ERROR] missing master_seed in config");
            return ExitCode::FAILURE;
        }
    };
    let cases = match extract_u64_field(&raw, "cases_per_family") {
        Some(v) => v as usize,
        None => {
            eprintln!("[ERROR] missing cases_per_family in config");
            return ExitCode::FAILURE;
        }
    };

    let receipt = run_rung2_parity_suite(seed, cases);
    if emit_json {
        println!("{}", receipt.to_canonical_json());
    } else {
        println!(
            "RUNG 2 PARITY SUITE (seed={}, cases/family={}, total={})",
            receipt.master_seed, receipt.cases_per_family, receipt.total_cases
        );
        println!("  FAM-DAG-CLEAN:       {}/{}", receipt.dag_clean_passed, receipt.cases_per_family);
        println!("  FAM-CYCLE-INJECTED:  {}/{} (1-edge-minimal shrunk)", receipt.cycle_shrunk_minimal, receipt.cases_per_family);
        println!("  FAM-DIAMOND-DOM:     {}/{} (exact cut oracle)", receipt.diamond_dom_passed, receipt.cases_per_family);
        println!("  FAM-DEAD-LEAVES:     {}/{}", receipt.dead_leaves_passed, receipt.cases_per_family);
        println!("  FAM-WRAPPER-AST:     {}/{}", receipt.wrapper_ast_passed, receipt.cases_per_family);
        println!("  FAM-METAMORPHIC-INV: {}/{} pairs (MR-1/2/3)", receipt.metamorphic_pairs_passed, receipt.cases_per_family * 3);
        println!("  MALFORMED REJECTED:  {}/4", receipt.malformed_rejected);
        println!("  CORPUS SHA-256:      {}", receipt.corpus_digest_sha256);
        println!("  ALL PASSED:          {}", receipt.all_passed);
    }

    if receipt.all_passed {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scargo_ground::{
        GroundGraph, GroundModule, WrapperKind, classify_wrapper_text, decode_ground_graph_json,
        is_edge_minimal_cycle, shrink_cyclic_graph,
    };

    fn repo_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(std::path::Path::parent)
            .and_then(std::path::Path::parent)
            .and_then(std::path::Path::parent)
            .expect("repo root")
            .to_path_buf()
    }

    #[test]
    fn rung2_seeded_corpus_passes_all_384_cases_and_192_metamorphic_pairs() {
        let cfg = fs::read_to_string(repo_root().join("data/trials/rung2_fuzz_corpus_v1.json")).expect("cfg");
        let seed = extract_u64_field(&cfg, "master_seed").expect("seed");
        let cases = extract_u64_field(&cfg, "cases_per_family").expect("cases") as usize;
        let rep = run_rung2_parity_suite(seed, cases);
        assert!(rep.all_passed);
        assert_eq!(rep.total_cases, 384);
        assert_eq!(rep.metamorphic_pairs_passed, 192);
        assert_eq!(rep.malformed_rejected, 4);
    }

    #[test]
    fn shrinker_reduces_large_cyclic_graph_to_minimal_cycle() {
        let g = GroundGraph {
            root: "A".to_string(),
            modules: vec![
                GroundModule { name: "A".to_string(), lines: 10, bytes: 100, imports: vec!["B".to_string(), "C".to_string()], wrapper_kind: WrapperKind::Substantive },
                GroundModule { name: "B".to_string(), lines: 10, bytes: 100, imports: vec!["C".to_string(), "D".to_string()], wrapper_kind: WrapperKind::Substantive },
                GroundModule { name: "C".to_string(), lines: 10, bytes: 100, imports: vec!["B".to_string()], wrapper_kind: WrapperKind::Substantive },
                GroundModule { name: "D".to_string(), lines: 10, bytes: 100, imports: vec![], wrapper_kind: WrapperKind::PureWrapper },
            ],
        };
        let shrunk = shrink_cyclic_graph(&g);
        assert!(is_edge_minimal_cycle(&shrunk));
        assert_eq!(shrunk.edge_count(), 2);
    }

    #[test]
    fn codec_roundtrip_and_wrapper_metamorphic_invariance() {
        let g = GroundGraph {
            root: "Main".to_string(),
            modules: vec![
                GroundModule { name: "Main".to_string(), lines: 10, bytes: 200, imports: vec!["B".to_string(), "A".to_string()], wrapper_kind: WrapperKind::Substantive },
                GroundModule { name: "A".to_string(), lines: 5, bytes: 50, imports: vec![], wrapper_kind: WrapperKind::PureWrapper },
                GroundModule { name: "B".to_string(), lines: 8, bytes: 80, imports: vec!["A".to_string()], wrapper_kind: WrapperKind::ReexportHub },
            ],
        };
        let enc = g.to_canonical_json();
        let dec = decode_ground_graph_json(&enc).expect("decode");
        assert_eq!(dec.to_canonical_json(), enc);
        assert_eq!(
            classify_wrapper_text("import A\n"),
            classify_wrapper_text("-- note\n\n/- block -/\nimport A\n")
        );
    }
}
