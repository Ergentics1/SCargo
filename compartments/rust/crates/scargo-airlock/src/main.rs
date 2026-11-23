// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Rung 3 Reconciled Proof-Reduction & Clean-Room ICD Airlock Qualification.

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use scargo_airlock::run_rung3_airlock;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let root = args
        .iter()
        .position(|a| a == "--root")
        .and_then(|i| args.get(i + 1))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    let emit_json = args.iter().any(|a| a == "--json");

    let receipt = match run_rung3_airlock(&root) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("[ERROR] airlock qualification failed: {}", e);
            return ExitCode::FAILURE;
        }
    };

    if emit_json {
        println!("{}", receipt.to_canonical_json());
    } else {
        println!(
            "RUNG 3 CLEAN-ROOM AIRLOCK ({}, baseline={}, mutation_allowed={})",
            receipt.icd_id, receipt.baseline_commit, receipt.target_repo_mutation_allowed
        );
        println!("  AG-1 Zone A Immutability:       {}", receipt.ag1_zone_a_clean);
        println!("  AG-2 Baseline/Trace Conserved:  {} (lineage={}/15)", receipt.ag2_conservation_exact, receipt.lineage_targets_verified);
        println!(
            "  AG-3 Pareto & RCT-001 Efficacy: {} (multi_decl_protected={}, A12_A={}bps, A12_B={}bps)",
            receipt.ag3_pareto_and_rct_passed,
            receipt.multi_decl_protected_count,
            receipt.strategy_a_a12_bps,
            receipt.strategy_b_a12_bps
        );
        println!("  AG-4 UP-07 Batches & Axioms:    {}", receipt.ag4_up07_batches_and_axioms_clean);
        println!("  AG-5 Synthetic Clean-Room Ops:  {}", receipt.ag5_synthetic_transforms_passed);
        for p in &receipt.packages {
            println!(
                "  [{}] zone={} mods={} batches={} (max={}) lines:{}->{} (rho={}ppm) bytes:{}->{} (rho={}ppm)",
                p.package_id,
                p.zone_id,
                p.eligible_modules,
                p.batch_count,
                p.max_batch_size,
                p.before.lines,
                p.after.lines,
                p.rho_lines_ppm,
                p.before.bytes,
                p.after.bytes,
                p.rho_bytes_ppm
            );
        }
        println!(
            "  NEGATIVE CONTROLS REJECTED:     {}/{}",
            receipt.negative_controls_rejected, receipt.total_negative_controls
        );
        println!("  INPUT DIGESTS SHA-256:          {}", receipt.input_digests_sha256);
        println!("  AIRLOCK DIGEST SHA-256:         {}", receipt.airlock_digest_sha256);
        println!("  ALL PASSED:                     {}", receipt.all_passed);
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
    use scargo_airlock::{
        MassVector, axioms_permitted, split_up07_batches, strategy_b_safe_guard, touches_zone_a,
        vargha_delaney_a12_bps_vs_zero_control, verify_synthetic_clean_room_transforms,
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
    fn rung3_airlock_qualifies_all_three_packages_and_rejects_7_negative_controls() {
        let rep = run_rung3_airlock(&repo_root()).expect("airlock run");
        assert!(rep.all_passed);
        assert!(!rep.target_repo_mutation_allowed);
        assert_eq!(rep.packages.len(), 3);
        assert_eq!(rep.packages[0].eligible_modules, 112);
        assert_eq!(rep.packages[0].batch_count, 14);
        assert_eq!(rep.packages[1].eligible_modules, 46);
        assert_eq!(rep.packages[1].batch_count, 6);
        assert_eq!(rep.packages[2].eligible_modules, 30);
        assert_eq!(rep.packages[2].batch_count, 4);
        assert_eq!(rep.multi_decl_protected_count, 30);
        assert_eq!(rep.lineage_targets_verified, 15);
        assert_eq!(rep.negative_controls_rejected, 7);
    }

    #[test]
    fn airlock_negative_controls_fail_closed() {
        let za: BTreeSet<String> = ["src/Main.lean", "lakefile.toml"]
            .into_iter()
            .map(String::from)
            .collect();
        assert!(touches_zone_a(&["src/Main.lean".to_string()], &za));
        assert!(!touches_zone_a(&["src/Development/Foo.lean".to_string()], &za));
        assert!(!strategy_b_safe_guard(3, true, true, false));
        assert!(!strategy_b_safe_guard(1, true, false, false));
        assert!(!strategy_b_safe_guard(1, true, true, true));
        assert!(strategy_b_safe_guard(1, true, true, false));

        let permitted: BTreeSet<String> = ["propext", "Quot.sound", "Classical.choice"]
            .into_iter()
            .map(String::from)
            .collect();
        assert!(!axioms_permitted(&["propext".to_string(), "badAxiom".to_string()], &permitted));
        assert!(axioms_permitted(&["propext".to_string(), "Quot.sound".to_string()], &permitted));

        let b = MassVector { files: 10, lines: 100, bytes: 1000 };
        assert!(!b.is_pareto_reduction(&MassVector { files: 10, lines: 101, bytes: 900 }));
        assert!(b.is_pareto_reduction(&MassVector { files: 10, lines: 90, bytes: 900 }));
    }

    #[test]
    fn synthetic_transforms_and_up07_batching_and_a12_hold() {
        assert!(verify_synthetic_clean_room_transforms());
        let mods: Vec<String> = (0..19).map(|i| format!("M{:02}", i)).collect();
        let batches = split_up07_batches(&mods, 8);
        assert_eq!(batches.len(), 3);
        assert_eq!(batches[0].len(), 8);
        assert_eq!(batches[1].len(), 8);
        assert_eq!(batches[2].len(), 3);
        assert_eq!(vargha_delaney_a12_bps_vs_zero_control(&[10, 20, 0]), 8333);
    }
}
