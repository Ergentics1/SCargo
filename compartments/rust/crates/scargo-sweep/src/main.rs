// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Standalone CLI for Rung 1 13-witness SWE-sweep, 21-fixture qualification, and Stratified RCT-R1.

use std::env;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use scargo_sweep::rct::run_rct_r1;
use scargo_sweep::sweep::{qualify_negative_controls, run_live_self_sweep};

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("all");
    let root = args
        .iter()
        .position(|a| a == "--root")
        .and_then(|i| args.get(i + 1))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    let emit_json = args.iter().any(|a| a == "--json");

    let policy_path = root.join("data/manifests/swe_sweep_policy_v1.json");
    let fixtures_path = root.join("data/fixtures/rung1_negative_controls_v1.json");
    let rct_path = root.join("data/trials/rct_r1_config_v1.json");

    let ok = match mode {
        "self-sweep" => run_self_sweep_cmd(&root, &policy_path, &fixtures_path, emit_json),
        "qualify-fixtures" => run_qualify_cmd(&policy_path, &fixtures_path, emit_json),
        "rct-r1" => run_rct_cmd(&policy_path, &rct_path, emit_json),
        "all" => {
            let a = run_self_sweep_cmd(&root, &policy_path, &fixtures_path, false);
            let b = run_qualify_cmd(&policy_path, &fixtures_path, false);
            let c = run_rct_cmd(&policy_path, &rct_path, false);
            a && b && c
        }
        other => {
            eprintln!(
                "Unknown mode '{}'. Usage: scargo-sweep [self-sweep|qualify-fixtures|rct-r1|all] [--root <dir>] [--json]",
                other
            );
            false
        }
    };

    if ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn run_self_sweep_cmd(root: &Path, policy: &Path, fixtures: &Path, emit_json: bool) -> bool {
    match run_live_self_sweep(root, policy, fixtures) {
        Ok(witnesses) => {
            let passed_count = witnesses.iter().filter(|w| w.passed).count();
            if emit_json {
                print!("[");
                for (i, w) in witnesses.iter().enumerate() {
                    if i > 0 {
                        print!(",");
                    }
                    print!("{}", w.to_canonical_json());
                }
                println!("]");
            } else {
                for w in &witnesses {
                    let tag = if w.passed { "PASS" } else { "FAIL" };
                    println!(
                        "[{}] {} (regime={}, violations={}) :: {}",
                        tag, w.witness_compartment_id, w.regime, w.violation_count, w.correspondence_note
                    );
                    for f in &w.findings {
                        println!("      -> [{}] {} : {}", f.defect_class, f.location, f.detail);
                    }
                }
                println!(
                    "SELF-SWEEP SUMMARY: {}/{} independent witnesses PASS",
                    passed_count,
                    witnesses.len()
                );
            }
            passed_count == witnesses.len() && witnesses.len() == 13
        }
        Err(e) => {
            eprintln!("[ERROR] self-sweep failed: {}", e);
            false
        }
    }
}

fn run_qualify_cmd(policy: &Path, fixtures: &Path, emit_json: bool) -> bool {
    match qualify_negative_controls(policy, fixtures) {
        Ok(sum) => {
            let ok = sum.total_poison == 21
                && sum.poison_killed == 21
                && sum.total_clean == 5
                && sum.clean_passed == 5
                && sum.copy_invariant;
            if emit_json {
                println!(
                    "{{\"clean_passed\":{},\"copy_invariant\":{},\"poison_killed\":{},\"total_clean\":{},\"total_poison\":{}}}",
                    sum.clean_passed, sum.copy_invariant, sum.poison_killed, sum.total_clean, sum.total_poison
                );
            } else {
                for v in &sum.verdicts {
                    let tag = if v.matched { "PASS" } else { "FAIL" };
                    println!(
                        "[{}] {} ({} -> {}, expected_pass={}, observed_pass={}) :: {}",
                        tag, v.id, v.kind, v.target_witness, v.expected_pass, v.observed_pass, v.detail
                    );
                }
                println!(
                    "QUALIFY SUMMARY: poison_killed={}/{}, clean_passed={}/{}, prin06_copy_invariant={}",
                    sum.poison_killed, sum.total_poison, sum.clean_passed, sum.total_clean, sum.copy_invariant
                );
            }
            ok
        }
        Err(e) => {
            eprintln!("[ERROR] qualify-fixtures failed: {}", e);
            false
        }
    }
}

fn run_rct_cmd(policy: &Path, rct_cfg: &Path, emit_json: bool) -> bool {
    match run_rct_r1(policy, rct_cfg) {
        Ok(rep) => {
            if emit_json {
                println!("{}", rep.to_canonical_json());
            } else {
                for s in &rep.strata {
                    let tag = if s.promoted { "PROMOTE" } else { "REJECT" };
                    println!(
                        "[{}] {} ({}): ctrl={}/{}, trt={}/{} (CI99 [{:.3},{:.3}]), trt_fpr={}/{} (CI99 [{:.3},{:.3}]), A12={:.4}, p={:.2e}",
                        tag,
                        s.stratum_id,
                        s.defect_class,
                        s.control_kills,
                        s.replicates,
                        s.treatment_kills,
                        s.replicates,
                        s.treatment_tpr_ci99.0,
                        s.treatment_tpr_ci99.1,
                        s.treatment_false_positives,
                        s.clean_replicates,
                        s.treatment_fpr_ci99.0,
                        s.treatment_fpr_ci99.1,
                        s.vargha_delaney_a12,
                        s.wilcoxon_p_two_tailed
                    );
                }
                println!(
                    "RCT-R1 SUMMARY: all_strata_promoted={} (seed={}, reps={}/stratum)",
                    rep.all_strata_promoted, rep.master_seed, rep.replicates_per_stratum
                );
            }
            rep.all_strata_promoted
        }
        Err(e) => {
            eprintln!("[ERROR] rct-r1 failed: {}", e);
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use scargo_sweep::blindspots::{
        BlindSpotThresholds, RawProbEstimate, admit_p_to_d, clopper_pearson_ci, dkw_bound,
        evaluate_fp_determinism, evaluate_spd_matrix, evaluate_state_invariants,
    };
    use scargo_sweep::json::parse_json;
    use scargo_sweep::rct::wilcoxon_mann_whitney_a12;
    use scargo_sweep::sha256::sha256_hex;

    fn repo_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .and_then(Path::parent)
            .and_then(Path::parent)
            .and_then(Path::parent)
            .expect("SCargo repo root")
            .to_path_buf()
    }

    #[test]
    fn sha256_matches_nist_abc_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn live_scargo_self_sweep_passes_all_13_witnesses() {
        let root = repo_root();
        let witnesses = run_live_self_sweep(
            &root,
            &root.join("data/manifests/swe_sweep_policy_v1.json"),
            &root.join("data/fixtures/rung1_negative_controls_v1.json"),
        )
        .expect("live self-sweep");
        assert_eq!(witnesses.len(), 13);
        for w in &witnesses {
            assert!(
                w.passed,
                "Witness {} failed with findings: {:?}",
                w.witness_compartment_id, w.findings
            );
            assert_eq!(w.policy_digest.len(), 64);
            assert!(!w.input_content_digests.is_empty());
        }
    }

    #[test]
    fn all_21_poisoned_killed_5_clean_passed_and_prin06_copy_invariant() {
        let root = repo_root();
        let sum = qualify_negative_controls(
            &root.join("data/manifests/swe_sweep_policy_v1.json"),
            &root.join("data/fixtures/rung1_negative_controls_v1.json"),
        )
        .expect("qualify negative controls");
        assert_eq!(sum.total_poison, 21);
        assert_eq!(sum.poison_killed, 21);
        assert_eq!(sum.total_clean, 5);
        assert_eq!(sum.clean_passed, 5);
        assert!(sum.copy_invariant);
    }

    #[test]
    fn stratified_rct_r1_promotes_all_7_strata() {
        let root = repo_root();
        let rep = run_rct_r1(
            &root.join("data/manifests/swe_sweep_policy_v1.json"),
            &root.join("data/trials/rct_r1_config_v1.json"),
        )
        .expect("run RCT-R1");
        assert_eq!(rep.strata.len(), 7);
        assert!(rep.all_strata_promoted);
        for s in &rep.strata {
            assert_eq!(s.treatment_kills, 32);
            assert!(s.vargha_delaney_a12 >= 0.95);
            assert!(s.wilcoxon_p_two_tailed < 0.01);
            if !s.is_probabilistic {
                assert_eq!(s.treatment_false_positives, 0);
            }
        }
    }

    #[test]
    fn direct_blindspot_unit_pressure_checks() {
        let root = repo_root();
        let policy_raw = std::fs::read_to_string(root.join("data/manifests/swe_sweep_policy_v1.json"))
            .expect("policy");
        let policy_json = parse_json(&policy_raw).expect("parse policy");
        let t = BlindSpotThresholds::from_policy_json(&policy_json).expect("thresholds");

        // D-Type cancellation
        let bad_fp = evaluate_fp_determinism(&[1e16, 1.0, -1e16, 0.5], Some(1.5), &t);
        assert!(!bad_fp.passed);

        // R-Type positive diagonal indefinite matrix
        let bad_spd = evaluate_spd_matrix(
            &[vec![1.0, 2.0], vec![2.0, 1.0]],
            &t,
        );
        assert!(!bad_spd.passed);

        // R-Type NaN poisoning and aggregate cap breach
        let bad_nan = evaluate_state_invariants(&[0.5, f64::NAN, 0.5], 5.0, 1.0, true, &t);
        assert!(!bad_nan.passed);
        let bad_cap = evaluate_state_invariants(&[4.0, 4.0, 4.0], 5.0, 10.0, false, &t);
        assert!(!bad_cap.passed);

        // Seam P -> D rejects OOD and uncalibrated estimates fail-closed
        let bad_est = RawProbEstimate {
            point_estimate: 0.1,
            calibrated: false,
            in_domain: false,
            ood_mahalanobis: 5.0,
            sample_count: 50,
            actuator_bypassed_certificate: false,
        };
        assert!(admit_p_to_d(&bad_est, &t).is_none());

        // Exact Massart-DKW, Clopper-Pearson, and Wilcoxon-Mann-Whitney sanity
        assert!((dkw_bound(256, 0.01) - 0.10173).abs() < 1e-4);
        let (lo, hi) = clopper_pearson_ci(32, 32, 0.01);
        assert!(lo > 0.80 && (hi - 1.0).abs() < 1e-12);
        let ctrl = vec![0.0; 32];
        let trt = vec![1.0; 32];
        let (_, p, a12) = wilcoxon_mann_whitney_a12(&ctrl, &trt);
        assert!((a12 - 1.0).abs() < 1e-12);
        assert!(p < 1e-10);
    }
}
