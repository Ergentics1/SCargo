// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

use scargo_synth::{generate_arc8_synth_plan, verify_arc8_synth};
use std::path::PathBuf;
use std::process::ExitCode;

fn print_usage() {
    eprintln!(
        "Usage:\n  scargo-synth generate --root <scargo> --riemannian <riem> --out <json> [--materialize-dir <dir>]\n  scargo-synth verify --root <scargo> [--json]"
    );
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        print_usage();
        return ExitCode::from(2);
    }

    match args[1].as_str() {
        "generate" => {
            let mut root = PathBuf::from(".");
            let mut riem: Option<PathBuf> = None;
            let mut out = PathBuf::from("transfer/patches/arc8_adaptive_synth_plan_v1.json");
            let mut mat: Option<PathBuf> = None;
            let mut i = 2usize;
            while i < args.len() {
                match args[i].as_str() {
                    "--root" if i + 1 < args.len() => {
                        root = PathBuf::from(&args[i + 1]);
                        i += 2;
                    }
                    "--riemannian" if i + 1 < args.len() => {
                        riem = Some(PathBuf::from(&args[i + 1]));
                        i += 2;
                    }
                    "--out" if i + 1 < args.len() => {
                        out = PathBuf::from(&args[i + 1]);
                        i += 2;
                    }
                    "--materialize-dir" if i + 1 < args.len() => {
                        mat = Some(PathBuf::from(&args[i + 1]));
                        i += 2;
                    }
                    other => {
                        eprintln!("unknown argument: {}", other);
                        print_usage();
                        return ExitCode::from(2);
                    }
                }
            }
            let Some(riem_dir) = riem else {
                eprintln!("--riemannian <dir> is required");
                return ExitCode::from(2);
            };
            match generate_arc8_synth_plan(&root, &riem_dir, &out, mat.as_deref()) {
                Ok(digest) => {
                    println!("[PASS] generated {} (sha256={})", out.display(), digest);
                    ExitCode::SUCCESS
                }
                Err(err) => {
                    eprintln!("[FAIL] generate: {}", err);
                    ExitCode::from(1)
                }
            }
        }
        "verify" => {
            let mut root = PathBuf::from(".");
            let mut as_json = false;
            let mut i = 2usize;
            while i < args.len() {
                match args[i].as_str() {
                    "--root" if i + 1 < args.len() => {
                        root = PathBuf::from(&args[i + 1]);
                        i += 2;
                    }
                    "--json" => {
                        as_json = true;
                        i += 1;
                    }
                    other => {
                        eprintln!("unknown argument: {}", other);
                        print_usage();
                        return ExitCode::from(2);
                    }
                }
            }
            match verify_arc8_synth(&root) {
                Ok(r) => {
                    if as_json {
                        print!("{}", r.to_canonical_json());
                    } else {
                        println!(
                            "ARC 8 ADAPTIVE 5-ZONE AST SYNTHESIS VERIFICATION ({}, baseline={})",
                            r.synth_plan_id, r.baseline_commit
                        );
                        println!("  SG-1 Baseline, Zone A & UP-08:    {}", r.sg1_baseline_zone_a_up08);
                        println!(
                            "  SG-2 5-Zone Round-Trip & Pareto:  {} (files={}, saved_lines={}, saved_bytes={})",
                            r.sg2_five_zone_roundtrip_pareto,
                            r.total_files,
                            r.total_saved_lines,
                            r.total_saved_bytes
                        );
                        println!("  SG-3 Z-C1A Dual-Mode Sound:       {} (files={})", r.sg3_z1a_dual_mode_sound, r.z1a_files);
                        println!("  SG-4 Z-C2 Adaptive-Width Sound:   {} (files={})", r.sg4_z2_adaptive_width_sound, r.z2_files);
                        println!("  SG-5 Z-C3 Acyclic Clusters Sound: {} (clusters={})", r.sg5_z3_acyclic_clusters_sound, r.z3_clusters);
                        println!(
                            "  SG-6 Adaptive Bin-Packing Sound:  {} (naive_qc={}, adaptive_qc={})",
                            r.sg6_adaptive_bin_packing_sound,
                            r.naive_quick_check_files,
                            r.adaptive_quick_check_files
                        );
                        println!(
                            "  SG-7 Negative Controls Rejected:  {} ({}/8)",
                            r.sg7_all_negatives_pass, r.sg7_negatives_rejected
                        );
                        println!("  INPUT DIGESTS SHA-256:            {}", r.input_digests_sha256);
                        println!("  SYNTH DIGEST SHA-256:             {}", r.synth_digest_sha256);
                        println!("  ALL PASSED:                       {}", r.all_passed);
                    }
                    if r.all_passed {
                        ExitCode::SUCCESS
                    } else {
                        ExitCode::from(1)
                    }
                }
                Err(err) => {
                    eprintln!("[FAIL] verify: {}", err);
                    ExitCode::from(1)
                }
            }
        }
        other => {
            eprintln!("unknown subcommand: {}", other);
            print_usage();
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use scargo_synth::{
        BinPackItem, QUICK_CHECK_MAX_CLOSURE, QUICK_CHECK_MAX_ROOTS, apply_unified_diff,
        emit_unified_diff_from_edits, rewrite_z2_adaptive, run_8_negative_controls,
        run_naive_vs_adaptive_bin_packing, sha256_hex, split_lf_lines, verify_arc8_synth,
    };
    use std::collections::BTreeSet;
    use std::path::Path;

    #[test]
    fn fips_sha256_and_negatives_pass() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(run_8_negative_controls(), 8);
    }

    #[test]
    fn adaptive_bin_packing_strictly_outperforms_naive_when_heavy_mixed() {
        let mut items = Vec::new();
        // Mix 1 heavy module (index 0) with 7 light modules (1..=7) -> naive alphabetical fails entire 8-file chunk!
        items.push(BinPackItem {
            path: "src/A_Heavy.lean".to_string(),
            zone_id: "Z-C1A".to_string(),
            has_deleted_files: false,
            saved_lines: 15,
            saved_bytes: 1500,
            closure: None,
            exact_closure_size: 5000,
        });
        for i in 1..=7 {
            let mut c = BTreeSet::new();
            c.insert(format!("M{}", i));
            c.insert("SharedBase".to_string());
            items.push(BinPackItem {
                path: format!("src/B_Light{:02}.lean", i),
                zone_id: "Z-C1A".to_string(),
                has_deleted_files: false,
                saved_lines: 12,
                saved_bytes: 1000,
                closure: Some(c),
                exact_closure_size: 2,
            });
        }
        let (sum, shards) = run_naive_vs_adaptive_bin_packing(&items);
        assert_eq!(sum.naive_quick_check_files, 0);
        assert_eq!(sum.adaptive_quick_check_files, 7);
        assert_eq!(sum.quick_check_file_gain, 7);
        for sh in &shards {
            if sh.ci_route == "quick_check" {
                assert!(sh.changed_roots <= QUICK_CHECK_MAX_ROOTS);
                assert!(sh.closure_modules <= QUICK_CHECK_MAX_CLOSURE);
                assert!(!sh.has_deleted_files);
            }
        }
    }

    #[test]
    fn z2_adaptive_roundtrip_and_layout_guard_sound() {
        let src = "def f (a b : Nat) : Nat :=\n  (@HAdd.hAdd\n    Nat\n    Nat\n    (@HMul.hMul\n      Nat\n      a\n      b)\n    a)\n";
        let res = rewrite_z2_adaptive(src, 160);
        assert!(res.token_stream_identical);
        assert!(!res.edits.is_empty());
        let old_lines = split_lf_lines(src);
        let (diff, hunks) = emit_unified_diff_from_edits("src/T.lean", &old_lines, &res.edits, 3).unwrap();
        assert_eq!(hunks, 1);
        let rt = apply_unified_diff(src, &diff).unwrap();
        assert_eq!(rt, res.new_src);
    }

    #[test]
    fn arc8_synth_plan_verifies_all_7_guards_and_8_negatives() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..");
        let r = verify_arc8_synth(&root).expect("arc8 synth verify must succeed");
        assert!(r.all_passed, "expected all Arc 8 guards PASS: {:?}", r);
        assert!(r.total_files >= 500);
        assert!(r.adaptive_quick_check_files >= r.naive_quick_check_files);
        assert_eq!(r.sg7_negatives_rejected, 8);
    }
}
