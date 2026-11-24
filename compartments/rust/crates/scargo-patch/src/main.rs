// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Arc 6 Concrete AST-Aware Patch Plan Generation (`generate`)
//! and Offline Pure In-Memory Unified-Diff Verification (`verify`).

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use scargo_patch::{generate_arc6_patch_plan, verify_arc6_patch_plan};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("verify");

    match mode {
        "generate" => {
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
                .unwrap_or_else(|| PathBuf::from("transfer/patches/arc6_patch_plan_v1.json"));
            let out_dir = args
                .iter()
                .position(|a| a == "--out-dir")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from);
            let riem_root = match riem {
                Some(p) => p,
                None => {
                    eprintln!(
                        "Usage: scargo-patch generate --root . --riemannian <dir> --out <plan.json> [--out-dir <ephemeral_dir>]"
                    );
                    return ExitCode::FAILURE;
                }
            };
            match generate_arc6_patch_plan(&root, &riem_root, &out, out_dir.as_deref()) {
                Ok((n, sha)) => {
                    println!(
                        "[PASS] generated {} ({} files verified round-trip, sha256={})",
                        out.display(),
                        n,
                        sha
                    );
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("[ERROR] generate failed: {}", e);
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
            let receipt = match verify_arc6_patch_plan(&root) {
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
                    "ARC 6 AST PATCH PLAN & UNIFIED-DIFF VERIFICATION ({}, baseline={}, mutation_allowed={})",
                    receipt.patch_plan_id,
                    receipt.baseline_commit,
                    receipt.target_repo_mutation_allowed
                );
                println!("  PG-1 Provenance, Zone A & UP-08: {}", receipt.pg1_provenance_zone_a_up08_clean);
                println!(
                    "  PG-2 137-File Bijection & SHA:   {} (files={})",
                    receipt.pg2_bijection_137_and_hashes_valid, receipt.total_files
                );
                println!(
                    "  PG-3 Pareto, Round-Trip & Width: {} (saved_lines={} [Z0={}, Z2={}, Z4={}], saved_bytes={}, z2_max_line={})",
                    receipt.pg3_pareto_roundtrip_and_bounds_valid,
                    receipt.total_saved_lines,
                    receipt.z0_saved_lines,
                    receipt.z2_saved_lines,
                    receipt.z4_saved_lines,
                    receipt.total_saved_bytes,
                    receipt.z2_max_line_after
                );
                println!(
                    "  PG-4 Synthetic Unified-Diff RT:  {} (transforms={}/4, sha={})",
                    receipt.pg4_synthetic_patch_suite_valid,
                    receipt.synthetic_transforms_passed,
                    receipt.synthetic_patch_suite_sha256
                );
                println!("  PG-5 Lean 4.36 Preflight Mods:   {}", receipt.pg5_lean_preflight_modules_valid);
                println!(
                    "  PG-6 Negative Controls Rejected: {} ({}/{})",
                    receipt.pg6_negative_controls_valid,
                    receipt.negative_controls_rejected,
                    receipt.total_negative_controls
                );
                println!("  INPUT DIGESTS SHA-256:           {}", receipt.input_digests_sha256);
                println!("  PATCH DIGEST SHA-256:            {}", receipt.patch_digest_sha256);
                println!("  ALL PASSED:                      {}", receipt.all_passed);
            }
            if receipt.all_passed {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        other => {
            eprintln!("Unknown mode '{}'. Usage: scargo-patch [generate|verify] ...", other);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scargo_patch::{
        Z2_WRAP_WIDTH, apply_unified_diff, count_free_local_vars, run_synthetic_patch_suite,
        transform_z2_balanced_collapse, transform_z2_closed_cse, transform_z4_prune_imports,
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
    fn arc6_patch_plan_verifies_all_6_guards_and_7_negatives() {
        let rep = verify_arc6_patch_plan(&repo_root()).expect("verify arc6 patch plan");
        assert!(rep.all_passed);
        assert!(!rep.target_repo_mutation_allowed);
        assert_eq!(rep.total_files, 137);
        assert!(rep.z2_max_line_after <= 280);
        assert_eq!(rep.synthetic_transforms_passed, 4);
        assert_eq!(rep.negative_controls_rejected, 7);
    }

    #[test]
    fn unified_diff_applier_and_ast_guards_fail_closed() {
        let (n, sha) = run_synthetic_patch_suite().expect("synthetic patch suite");
        assert_eq!(n, 4);
        assert_eq!(sha.len(), 64);

        let bad_diff = "--- a/A.lean\n+++ b/A.lean\n@@ -1,1 +1,1 @@\n-nope\n+ok\n";
        assert!(apply_unified_diff("real\n", bad_diff).is_err());

        let layout_src = "module\ndef f := (@Field.toSemifield\n  Nat\n  by exact h)\n";
        assert!(transform_z2_balanced_collapse(layout_src, Z2_WRAP_WIDTH).is_err());

        assert_eq!(count_free_local_vars("(@instHAdd Nat instAddNat)"), 0);
        assert!(count_free_local_vars("(@Field.toSemifield K (@instField K))") > 0);
        assert!(
            transform_z2_closed_cse(
                "module\n@[expose] public section\ndef x := (@Field.toSemifield K)\ndef y := (@Field.toSemifield K)\n",
                "(@Field.toSemifield K)",
                "_scargo_bad"
            )
            .is_err()
        );

        let mut bad_p = BTreeSet::new();
        bad_p.insert("Req".to_string());
        assert!(
            transform_z4_prune_imports("public import Req\n", &BTreeSet::new(), &bad_p).is_err()
        );
    }
}
