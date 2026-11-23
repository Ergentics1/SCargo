// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Arc 5 Clean-Room Dual-Route UP-07 Pre-Flight Bundle Emission (`emit`)
//! and Offline Verification (`verify`).

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use scargo_emit::{emit_arc5_bundles, verify_arc5_emitter};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("verify");

    match mode {
        "emit" => {
            let root = args
                .iter()
                .position(|a| a == "--root")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("."));
            let riem = args
                .iter()
                .position(|a| a == "--riemannian")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from);
            let out = args
                .iter()
                .position(|a| a == "--out")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("transfer/bundles/arc5_preflight_bundles_v1.json"));
            let riem_root = match riem {
                Some(p) => p,
                None => {
                    eprintln!("Usage: scargo-emit emit --root . --riemannian <dir> --out <file.json>");
                    return ExitCode::FAILURE;
                }
            };
            match emit_arc5_bundles(&root, &riem_root, &out) {
                Ok(sha) => {
                    println!("[PASS] emitted {} (sha256={})", out.display(), sha);
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("[ERROR] emit failed: {}", e);
                    ExitCode::FAILURE
                }
            }
        }
        "verify" => {
            let root = args
                .iter()
                .position(|a| a == "--root")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("."));
            let emit_json = args.iter().any(|a| a == "--json");
            let receipt = match verify_arc5_emitter(&root) {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("[ERROR] verify failed: {}", e);
                    return ExitCode::FAILURE;
                }
            };
            if emit_json {
                println!("{}", receipt.to_canonical_json());
            } else {
                println!(
                    "ARC 5 PRE-FLIGHT EMITTER VERIFICATION ({}, baseline={}, mutation_allowed={})",
                    receipt.bundle_suite_id, receipt.baseline_commit, receipt.target_repo_mutation_allowed
                );
                println!("  EG-1 Provenance, Zone A & UP-08: {}", receipt.eg1_provenance_zone_a_up08_clean);
                println!(
                    "  EG-2 Dual-Route UP-07 Soundness: {} (quick_check={}, full_build={}, full_bundles={})",
                    receipt.eg2_dual_route_up07_sound,
                    receipt.quick_check_shards,
                    receipt.full_build_shards,
                    receipt.total_full_bundles
                );
                println!(
                    "  EG-3 Shard Conservation & SHA:   {} (shards={})",
                    receipt.eg3_shard_conservation_and_hashes_valid, receipt.total_shards
                );
                println!(
                    "  EG-4 Synthetic Diff Suite:       {} (transforms={}/4, sha={})",
                    receipt.eg4_synthetic_diffs_valid,
                    receipt.synthetic_transforms_passed,
                    receipt.synthetic_diffs_sha256
                );
                println!("  EG-5 Lean 4.36 Preflight Mods:   {}", receipt.eg5_lean_preflight_modules_valid);
                println!(
                    "  EG-6 Negative Controls Rejected: {} ({}/{})",
                    receipt.eg6_negative_controls_valid,
                    receipt.negative_controls_rejected,
                    receipt.total_negative_controls
                );
                println!("  INPUT DIGESTS SHA-256:           {}", receipt.input_digests_sha256);
                println!("  EMITTER DIGEST SHA-256:          {}", receipt.emitter_digest_sha256);
                println!("  ALL PASSED:                      {}", receipt.all_passed);
            }
            if receipt.all_passed {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        other => {
            eprintln!("Unknown mode '{}'. Usage: scargo-emit [emit|verify] ...", other);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scargo_emit::{
        BinderSig, classify_up07_route, delimiters_balanced, rewrite_z1a_synthetic,
        rewrite_z2_synthetic, rewrite_z4_prune_redundant_imports, run_synthetic_diff_suite,
    };
    use std::collections::BTreeSet;

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
    fn arc5_emitter_verifies_all_6_guards_and_6_negatives() {
        let rep = verify_arc5_emitter(&repo_root()).expect("verify arc5 emitter");
        assert!(rep.all_passed);
        assert!(!rep.target_repo_mutation_allowed);
        assert_eq!(rep.total_shards, 24);
        assert_eq!(rep.total_full_bundles, 4);
        assert_eq!(rep.synthetic_transforms_passed, 4);
        assert_eq!(rep.negative_controls_rejected, 6);
    }

    #[test]
    fn synthetic_rewriters_and_up07_guards_fail_closed() {
        let (n, sha) = run_synthetic_diff_suite().expect("diff suite");
        assert_eq!(n, 4);
        assert_eq!(sha.len(), 64);
        assert_eq!(classify_up07_route(8, 4), "quick_check");
        assert_eq!(classify_up07_route(1, 127_439), "full_rh_build");
        assert_eq!(classify_up07_route(9, 0), "full_rh_build");
        assert!(delimiters_balanced("((a + b) * [c])"));
        assert!(!delimiters_balanced("((a + b)"));

        let s1 = BinderSig { explicit_count: 1, implicit_count: 1, instance_count: 0, universe_params: 1 };
        assert!(rewrite_z1a_synthetic("theorem x := by\n  exact y\n", s1, s1, "y").is_err());
        assert!(rewrite_z2_synthetic("def f := 1\n", false).is_err());
        let mut p = BTreeSet::new();
        p.insert("Req".to_string());
        assert!(rewrite_z4_prune_redundant_imports("public import Req\n", &BTreeSet::new(), &p).is_err());
    }
}
