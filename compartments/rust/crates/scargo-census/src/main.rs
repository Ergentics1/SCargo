// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Arc 4 Clean-Room High-Mass Zone Census (`scan` and `verify`).

use std::env;
use std::path::PathBuf;
use std::process::ExitCode;

use scargo_census::{scan_high_mass_zones, verify_arc4_census};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("verify");

    match mode {
        "scan" => {
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
                .unwrap_or_else(|| PathBuf::from("data/trials/arc4_high_mass_census_v1.json"));
            let riem_root = match riem {
                Some(p) => p,
                None => {
                    eprintln!("Usage: scargo-census scan --riemannian <dir> --out <file.json>");
                    return ExitCode::FAILURE;
                }
            };
            match scan_high_mass_zones(&riem_root, &out) {
                Ok(sha) => {
                    println!("[PASS] wrote {} (sha256={})", out.display(), sha);
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("[ERROR] scan failed: {}", e);
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
            let receipt = match verify_arc4_census(&root) {
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
                    "ARC 4 HIGH-MASS CENSUS VERIFICATION ({}, baseline={})",
                    receipt.census_id, receipt.baseline_commit
                );
                println!("  HG-1 Provenance & UP-08 Clean:   {}", receipt.hg1_provenance_and_up08_clean);
                println!("  HG-2 Z-C2 Explicit @-Dumps:      {} (reclaimable={} lines)", receipt.hg2_z2_explicit_dumps_valid, receipt.z2_reclaimable_lines);
                println!("  HG-3 Z-C3 Private Duplicates:    {} (reclaimable={} lines)", receipt.hg3_z3_duplicate_clusters_valid, receipt.z3_reclaimable_lines);
                println!("  HG-4 Z-C4 Dominator & Hub:       {} (redundant_hub_imports={})", receipt.hg4_z4_dominator_hub_valid, receipt.z4_redundant_hub_imports);
                println!("  HG-5 Pareto Ranking & Negatives: {} (top={}, neg={}/{})", receipt.hg5_ranking_and_negatives_valid, receipt.top_ranked_zone, receipt.negative_controls_rejected, receipt.total_negative_controls);
                for r in &receipt.ranking {
                    println!(
                        "  #{} [{}] total_lines={} reclaimable={} (rho={}ppm) total_bytes={} reclaimable_bytes={} (rho={}ppm)",
                        r.rank, r.zone_id, r.zone_total_lines, r.reclaimable_lines, r.rho_lines_ppm, r.zone_total_bytes, r.reclaimable_bytes, r.rho_bytes_ppm
                    );
                }
                println!("  INPUT DIGESTS SHA-256:           {}", receipt.input_digests_sha256);
                println!("  CENSUS DIGEST SHA-256:           {}", receipt.census_digest_sha256);
                println!("  ALL PASSED:                      {}", receipt.all_passed);
            }
            if receipt.all_passed {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        other => {
            eprintln!("Unknown mode '{}'. Usage: scargo-census [scan|verify] ...", other);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scargo_census::{cluster_accounting_valid, contains_verbatim_proof_body, rho_ppm};

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
    fn arc4_high_mass_census_verifies_all_5_guards_and_6_negatives() {
        let rep = verify_arc4_census(&repo_root()).expect("verify arc4 census");
        assert!(rep.all_passed);
        assert!(rep.hg1_provenance_and_up08_clean);
        assert!(rep.hg2_z2_explicit_dumps_valid);
        assert!(rep.hg3_z3_duplicate_clusters_valid);
        assert!(rep.hg4_z4_dominator_hub_valid);
        assert!(rep.hg5_ranking_and_negatives_valid);
        assert_eq!(rep.ranking.len(), 3);
        assert_eq!(rep.negative_controls_rejected, 6);
    }

    #[test]
    fn up08_verbatim_body_and_cluster_bounds_fail_closed() {
        assert!(contains_verbatim_proof_body("{\"x\":\"private theorem foo : True := by trivial\"}"));
        assert!(!contains_verbatim_proof_body("{\"fingerprint_sha256\":\"abc\",\"multiplicity\":3}"));
        assert!(cluster_accounting_valid(4, 12, 36));
        assert!(!cluster_accounting_valid(1, 12, 0));
        assert!(!cluster_accounting_valid(3, 10, 30));
        assert_eq!(rho_ppm(1000, 750), 750_000);
    }
}
