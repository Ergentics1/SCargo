// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Arc 7 G4–G5 Airlock Rehearsal Staging (`stage`),
//! Live Remote CI Artifact Ingestion (`ingest`), and Offline Verification (`verify`).

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use scargo_rehearsal::{
    PINNED_BASELINE_COMMIT, parse_json, stage_arc7_rehearsal, validate_ci_build_receipt,
    validate_g5_comparator_receipt, validate_quick_check_receipt, verify_arc7_rehearsal,
};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("verify");

    match mode {
        "stage" => {
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
                .unwrap_or_else(|| PathBuf::from("transfer/rehearsal/arc7_g4_g5_rehearsal_v1.json"));
            let riem_root = match riem {
                Some(p) => p,
                None => {
                    eprintln!(
                        "Usage: scargo-rehearsal stage --root . --riemannian <dir> --out <rehearsal.json>"
                    );
                    return ExitCode::FAILURE;
                }
            };
            match stage_arc7_rehearsal(&root, &riem_root, &out) {
                Ok(sha) => {
                    println!("[PASS] staged {} (sha256={})", out.display(), sha);
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("[ERROR] stage failed: {}", e);
                    ExitCode::FAILURE
                }
            }
        }
        "ingest" => {
            let qc = args
                .iter()
                .position(|a| a == "--quick-check")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from);
            let cb = args
                .iter()
                .position(|a| a == "--ci-build")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from);
            let cmp = args
                .iter()
                .position(|a| a == "--comparator")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from);
            let require_remote = args.iter().any(|a| a == "--require-remote-attestation");
            if qc.is_none() && cb.is_none() && cmp.is_none() {
                eprintln!(
                    "Usage: scargo-rehearsal ingest [--quick-check <result.json>] [--ci-build <receipt.json>] [--comparator <comp.json>] [--require-remote-attestation]"
                );
                return ExitCode::FAILURE;
            }
            if let Some(p) = qc {
                let raw = match fs::read_to_string(&p) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("[ERROR] read {}: {}", p.display(), e);
                        return ExitCode::FAILURE;
                    }
                };
                match parse_json(&raw).and_then(|v| validate_quick_check_receipt(&v, PINNED_BASELINE_COMMIT)) {
                    Ok(()) => println!("[PASS] G4 quick-check diagnostic accepted: {}", p.display()),
                    Err(e) => {
                        eprintln!("[FAIL] G4 quick-check rejected: {}", e);
                        return ExitCode::FAILURE;
                    }
                }
            }
            if let Some(p) = cb {
                let raw = match fs::read_to_string(&p) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("[ERROR] read {}: {}", p.display(), e);
                        return ExitCode::FAILURE;
                    }
                };
                match parse_json(&raw).and_then(|v| validate_ci_build_receipt(&v, PINNED_BASELINE_COMMIT)) {
                    Ok(()) => println!("[PASS] G4 full ci-build receipt accepted: {}", p.display()),
                    Err(e) => {
                        eprintln!("[FAIL] G4 ci-build rejected: {}", e);
                        return ExitCode::FAILURE;
                    }
                }
            }
            if let Some(p) = cmp {
                let raw = match fs::read_to_string(&p) {
                    Ok(s) => s,
                    Err(e) => {
                        eprintln!("[ERROR] read {}: {}", p.display(), e);
                        return ExitCode::FAILURE;
                    }
                };
                match parse_json(&raw).and_then(|v| validate_g5_comparator_receipt(&v, require_remote)) {
                    Ok(()) => println!("[PASS] G5 comparator & 3-axiom receipt accepted: {}", p.display()),
                    Err(e) => {
                        eprintln!("[FAIL] G5 comparator rejected: {}", e);
                        return ExitCode::FAILURE;
                    }
                }
            }
            ExitCode::SUCCESS
        }
        "verify" => {
            let root = args
                .iter()
                .position(|a| a == "--root")
                .and_then(|i| args.get(i + 1))
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("."));
            let emit_json = args.iter().any(|a| a == "--json");
            let receipt = match verify_arc7_rehearsal(&root) {
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
                    "ARC 7 G4–G5 AIRLOCK REHEARSAL VERIFICATION ({}, baseline={}, rehearsal={}, remote_attested={})",
                    receipt.rehearsal_suite_id,
                    receipt.baseline_commit,
                    receipt.rehearsal_mode,
                    receipt.remote_ci_attestation
                );
                println!("  RG-1 Zone A Pins & UP-08 Clean:  {}", receipt.rg1_zone_a_pins_and_up08_clean);
                println!(
                    "  RG-2 quick-check.py:80 Routing:  {} (quick_check={}, full_deferred={}, total={})",
                    receipt.rg2_quick_check_and_deferral_valid,
                    receipt.quick_check_eligible_shards,
                    receipt.full_build_deferred_shards,
                    receipt.total_routed_shards
                );
                println!("  RG-3 Full ci-build.py Receipt:   {}", receipt.rg3_ci_build_receipt_valid);
                println!("  RG-4 G5 Comparator & 3 Axioms:   {}", receipt.rg4_g5_comparator_and_axioms_valid);
                println!(
                    "  RG-5 Arc 6 Binding & Honesty:    {} (files={}, saved_lines={}, saved_bytes={})",
                    receipt.rg5_arc6_binding_and_honesty_valid,
                    receipt.linked_arc6_files,
                    receipt.linked_arc6_saved_lines,
                    receipt.linked_arc6_saved_bytes
                );
                println!(
                    "  RG-6 Negative Controls Rejected: {} ({}/{})",
                    receipt.rg6_negative_controls_valid,
                    receipt.negative_controls_rejected,
                    receipt.total_negative_controls
                );
                println!("  INPUT DIGESTS SHA-256:           {}", receipt.input_digests_sha256);
                println!("  REHEARSAL DIGEST SHA-256:        {}", receipt.rehearsal_digest_sha256);
                println!("  ALL PASSED:                      {}", receipt.all_passed);
            }
            if receipt.all_passed {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        other => {
            eprintln!("Unknown mode '{}'. Usage: scargo-rehearsal [stage|ingest|verify] ...", other);
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scargo_rehearsal::{
        classify_upstream_quick_check, compute_ci_input_fingerprint, PINNED_LAKEFILE_SHA256,
        PINNED_MANIFEST_SHA256, PINNED_TOOLCHAIN,
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
    fn arc7_rehearsal_verifies_all_6_guards_and_8_negatives() {
        let rep = verify_arc7_rehearsal(&repo_root()).expect("verify arc7 rehearsal");
        assert!(rep.all_passed);
        assert!(rep.rehearsal_mode);
        assert!(!rep.remote_ci_attestation);
        assert!(!rep.target_repo_mutation_allowed);
        assert_eq!(rep.quick_check_eligible_shards, 3);
        assert_eq!(rep.full_build_deferred_shards, 15);
        assert_eq!(rep.linked_arc6_files, 137);
        assert_eq!(rep.linked_arc6_saved_lines, 32166);
        assert_eq!(rep.negative_controls_rejected, 8);
    }

    #[test]
    fn upstream_quick_check_py80_and_ci_fingerprint_sound() {
        assert_eq!(classify_upstream_quick_check(8, 12, false).0, "quick_check");
        assert_eq!(classify_upstream_quick_check(8, 12, true).0, "full_rh_build");
        assert_eq!(classify_upstream_quick_check(1, 127_440, false).0, "full_rh_build");
        assert_eq!(classify_upstream_quick_check(9, 10, false).0, "full_rh_build");
        let fp = compute_ci_input_fingerprint(
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            PINNED_LAKEFILE_SHA256,
            PINNED_MANIFEST_SHA256,
            PINNED_TOOLCHAIN,
        );
        assert_eq!(fp.len(), 64);
    }

    #[test]
    fn g5_ingestor_rejects_quick_check_and_rehearsal_spoof() {
        let spoof = parse_json(
            "{\"rehearsal_mode\":true,\"remote_ci_attestation\":true,\"remote_workflow_run_id\":42,\"full_build\":true,\"challenge_module\":\"Challenge\",\"solution_module\":\"Main\",\"lean_kernel_exit\":0,\"leanchecker_paranoid_exit\":0,\"nanoda_exit\":0,\"challenge_export_sha256\":\"bd484ac9886a96f26b1d9a7a59ebd45b7a70d102c015d4f31f9302bbdd6ab2b9\",\"solution_export_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"theorem_names\":[\"riemannHypothesis\",\"riemannZeta_eq_zero_re\",\"LFunction_ne_zero_of_half_lt_re\",\"LFunction_eq_zero_re\",\"LFunction_eq_zero_re_of_isPrimitive\"],\"theorem_axioms\":{\"riemannHypothesis\":[\"propext\"],\"riemannZeta_eq_zero_re\":[\"propext\"],\"LFunction_ne_zero_of_half_lt_re\":[\"propext\"],\"LFunction_eq_zero_re\":[\"propext\"],\"LFunction_eq_zero_re_of_isPrimitive\":[\"propext\"]}}",
        )
        .expect("parse spoof");
        assert!(validate_g5_comparator_receipt(&spoof, true).is_err());
        assert!(validate_g5_comparator_receipt(&spoof, false).is_err());
    }
}
