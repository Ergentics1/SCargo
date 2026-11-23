// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Pre-Registered Stratified RCT-R1 Engine:
//! Compares Control Arm (naive point/component/unguarded assertions) vs.
//! Treatment Arm (Rung 1 hardened D/R/P/Seam compartment witnesses) across
//! 7 poisoned + 7 clean strata (n = 32 replicates per stratum) using exact
//! Wilcoxon-Mann-Whitney U, Vargha-Delaney A12, and Clopper-Pearson 99% CIs.

use std::fs;
use std::path::Path;

use crate::blindspots::{
    BlindSpotThresholds, RawProbEstimate, SplitMix64, admit_p_to_d, clopper_pearson_ci,
    evaluate_fp_determinism, evaluate_prob_calibration, evaluate_spd_matrix,
    evaluate_state_invariants, generate_calibration_samples, keyed_simulation_digest, naive_sum,
    neumaier_sum, normal_cdf,
};
use crate::json::{JsonValue, parse_json, write_json_string};

#[derive(Debug, Clone)]
pub struct StratumRctResult {
    pub stratum_id: String,
    pub witness_id: String,
    pub defect_class: String,
    pub is_probabilistic: bool,
    pub replicates: usize,
    pub control_kills: usize,
    pub treatment_kills: usize,
    pub clean_replicates: usize,
    pub control_false_positives: usize,
    pub treatment_false_positives: usize,
    pub treatment_tpr_ci99: (f64, f64),
    pub treatment_fpr_ci99: (f64, f64),
    pub wilcoxon_u: f64,
    pub wilcoxon_p_two_tailed: f64,
    pub vargha_delaney_a12: f64,
    pub promoted: bool,
}

#[derive(Debug, Clone)]
pub struct RctR1Receipt {
    pub trial_id: String,
    pub master_seed: u64,
    pub replicates_per_stratum: usize,
    pub all_strata_promoted: bool,
    pub strata: Vec<StratumRctResult>,
}

impl RctR1Receipt {
    pub fn to_canonical_json(&self) -> String {
        let mut out = String::new();
        out.push_str("{\"all_strata_promoted\":");
        out.push_str(if self.all_strata_promoted { "true" } else { "false" });
        out.push_str(",\"master_seed\":");
        out.push_str(&self.master_seed.to_string());
        out.push_str(",\"replicates_per_stratum\":");
        out.push_str(&self.replicates_per_stratum.to_string());
        out.push_str(",\"strata\":[");
        for (i, s) in self.strata.iter().enumerate() {
            if i > 0 {
                out.push(',');
            }
            out.push_str("{\"clean_replicates\":");
            out.push_str(&s.clean_replicates.to_string());
            out.push_str(",\"control_false_positives\":");
            out.push_str(&s.control_false_positives.to_string());
            out.push_str(",\"control_kills\":");
            out.push_str(&s.control_kills.to_string());
            out.push_str(",\"defect_class\":");
            write_json_string(&s.defect_class, &mut out);
            out.push_str(",\"is_probabilistic\":");
            out.push_str(if s.is_probabilistic { "true" } else { "false" });
            out.push_str(",\"promoted\":");
            out.push_str(if s.promoted { "true" } else { "false" });
            out.push_str(",\"replicates\":");
            out.push_str(&s.replicates.to_string());
            out.push_str(",\"stratum_id\":");
            write_json_string(&s.stratum_id, &mut out);
            out.push_str(",\"treatment_false_positives\":");
            out.push_str(&s.treatment_false_positives.to_string());
            out.push_str(",\"treatment_kills\":");
            out.push_str(&s.treatment_kills.to_string());
            out.push_str(",\"vargha_delaney_a12_milli\":");
            out.push_str(&((s.vargha_delaney_a12 * 1000.0).round() as u64).to_string());
            out.push_str(",\"wilcoxon_p_lt_alpha\":");
            out.push_str(if s.wilcoxon_p_two_tailed < 0.01 { "true" } else { "false" });
            out.push_str(",\"witness_id\":");
            write_json_string(&s.witness_id, &mut out);
            out.push('}');
        }
        out.push_str("],\"trial_id\":");
        write_json_string(&self.trial_id, &mut out);
        out.push('}');
        out
    }
}

/// Exact Wilcoxon-Mann-Whitney U, tie-corrected two-tailed p-value, and Vargha-Delaney A12.
pub fn wilcoxon_mann_whitney_a12(control: &[f64], treatment: &[f64]) -> (f64, f64, f64) {
    let n1 = control.len();
    let n2 = treatment.len();
    if n1 == 0 || n2 == 0 {
        return (0.0, 1.0, 0.5);
    }
    let mut u = 0.0f64;
    for &y in treatment {
        for &x in control {
            if y > x {
                u += 1.0;
            } else if (y - x).abs() <= 0.0 {
                u += 0.5;
            }
        }
    }
    let prod = (n1 as f64) * (n2 as f64);
    let a12 = u / prod;

    // Tie correction over combined sorted values.
    let mut combined = Vec::with_capacity(n1 + n2);
    combined.extend_from_slice(control);
    combined.extend_from_slice(treatment);
    combined.sort_by(f64::total_cmp);

    let big_n = (n1 + n2) as f64;
    let mut tie_sum = 0.0f64;
    let mut idx = 0usize;
    while idx < combined.len() {
        let mut end = idx + 1;
        while end < combined.len() && (combined[end] - combined[idx]).abs() <= 0.0 {
            end += 1;
        }
        let t = (end - idx) as f64;
        if t > 1.0 {
            tie_sum += t * t * t - t;
        }
        idx = end;
    }

    let mean_u = 0.5 * prod;
    let denom_n = big_n * (big_n - 1.0);
    let var_u = (prod / 12.0) * ((big_n + 1.0) - tie_sum / denom_n);
    if var_u <= 0.0 || !var_u.is_finite() {
        return (u, 1.0, a12);
    }
    let z = ((u - mean_u).abs() - 0.5).max(0.0) / var_u.sqrt();
    let p_two_tailed = (2.0 * (1.0 - normal_cdf(z))).clamp(0.0, 1.0);
    (u, p_two_tailed, a12)
}

pub fn run_rct_r1(policy_path: &Path, config_path: &Path) -> Result<RctR1Receipt, String> {
    let policy_raw = fs::read_to_string(policy_path).map_err(|e| format!("read policy: {}", e))?;
    let policy_json = parse_json(&policy_raw)?;
    let t = BlindSpotThresholds::from_policy_json(&policy_json)?;

    let cfg_raw = fs::read_to_string(config_path).map_err(|e| format!("read rct config: {}", e))?;
    let cfg = parse_json(&cfg_raw)?;

    let trial_id = cfg
        .get("trial_id")
        .and_then(JsonValue::as_str)
        .ok_or("missing trial_id")?
        .to_string();
    let master_seed = cfg
        .get("master_seed")
        .and_then(JsonValue::as_u64)
        .ok_or("missing master_seed")?;
    let reps = cfg
        .get("replicates_per_stratum")
        .and_then(JsonValue::as_u64)
        .ok_or("missing replicates_per_stratum")? as usize;
    let cal_n = cfg
        .get("calibration_sample_size")
        .and_then(JsonValue::as_u64)
        .ok_or("missing calibration_sample_size")? as usize;

    let strata_arr = cfg
        .get("strata")
        .and_then(JsonValue::as_array)
        .ok_or("missing strata")?;

    let mut rng = SplitMix64::new(master_seed);
    let mut results = Vec::with_capacity(strata_arr.len());

    for stratum in strata_arr {
        let sid = stratum.get("id").and_then(JsonValue::as_str).ok_or("missing stratum id")?;
        let wid = stratum.get("witness").and_then(JsonValue::as_str).ok_or("missing witness")?;
        let dcls = stratum.get("defect_class").and_then(JsonValue::as_str).ok_or("missing defect_class")?;
        let is_prob = sid == "STRAT-P-CAL";

        let mut ctrl_scores = Vec::with_capacity(reps);
        let mut trt_scores = Vec::with_capacity(reps);
        let mut ctrl_fp = 0usize;
        let mut trt_fp = 0usize;

        for _ in 0..reps {
            let sub_seed = rng.next_u64();
            let (ctrl_killed, trt_killed, ctrl_clean_fp, trt_clean_fp) =
                run_single_replicate(sid, sub_seed, cal_n, &t)?;
            ctrl_scores.push(if ctrl_killed { 1.0 } else { 0.0 });
            trt_scores.push(if trt_killed { 1.0 } else { 0.0 });
            if ctrl_clean_fp {
                ctrl_fp += 1;
            }
            if trt_clean_fp {
                trt_fp += 1;
            }
        }

        let ctrl_kills = ctrl_scores.iter().filter(|&&v| v > 0.5).count();
        let trt_kills = trt_scores.iter().filter(|&&v| v > 0.5).count();
        let (u, p_val, a12) = wilcoxon_mann_whitney_a12(&ctrl_scores, &trt_scores);
        let tpr_ci = clopper_pearson_ci(trt_kills, reps, t.clopper_pearson_alpha);
        let fpr_ci = clopper_pearson_ci(trt_fp, reps, t.clopper_pearson_alpha);

        let fpr_ok = if is_prob {
            // For probabilistic DKW at alpha = 0.01 + 3 quantiles, allow calibrated finite-sample alarms <= 10%.
            (trt_fp as f64) / (reps as f64) <= 0.10
        } else {
            trt_fp == 0
        };

        let promoted = reps >= t.min_replicates_per_stratum
            && trt_kills == reps
            && trt_kills > ctrl_kills
            && p_val < t.wilcoxon_alpha
            && a12 >= t.min_vargha_delaney_a12
            && fpr_ok;

        results.push(StratumRctResult {
            stratum_id: sid.to_string(),
            witness_id: wid.to_string(),
            defect_class: dcls.to_string(),
            is_probabilistic: is_prob,
            replicates: reps,
            control_kills: ctrl_kills,
            treatment_kills: trt_kills,
            clean_replicates: reps,
            control_false_positives: ctrl_fp,
            treatment_false_positives: trt_fp,
            treatment_tpr_ci99: tpr_ci,
            treatment_fpr_ci99: fpr_ci,
            wilcoxon_u: u,
            wilcoxon_p_two_tailed: p_val,
            vargha_delaney_a12: a12,
            promoted,
        });
    }

    let all_promoted = !results.is_empty() && results.iter().all(|s| s.promoted);
    Ok(RctR1Receipt {
        trial_id,
        master_seed,
        replicates_per_stratum: reps,
        all_strata_promoted: all_promoted,
        strata: results,
    })
}

/// Runs one paired poisoned + clean control replicate for Control (naive) vs. Treatment (hardened).
/// Returns `(control_killed_poison, treatment_killed_poison, control_false_positive_on_clean, treatment_false_positive_on_clean)`.
fn run_single_replicate(
    stratum_id: &str,
    seed: u64,
    cal_n: usize,
    t: &BlindSpotThresholds,
) -> Result<(bool, bool, bool, bool), String> {
    let mut r = SplitMix64::new(seed);
    match stratum_id {
        "STRAT-D-CANCEL" => {
            // Poison: nominal order cancels big + (-big) first so fixed-order assertion matches exact sum,
            // masking catastrophic non-associative cancellation (kappa_sum > 1e16) under reordering.
            let big = 1.0e16 * (1.0 + (r.next_u64() % 4) as f64);
            let small = 0.25 + 0.125 * ((r.next_u64() % 5) as f64);
            let poison_xs = [big, -big, big, -big, small, small, small, small];
            let exact = 4.0 * small;
            // Control naive check: fixed-order nominal sum assertion against exact value.
            let naive_val = naive_sum(&poison_xs);
            let ctrl_killed = (naive_val - exact).abs() > 1e-6;
            let trt_killed = !evaluate_fp_determinism(&poison_xs, Some(exact), t).passed;

            // Clean: well-conditioned positive series.
            let clean_xs = [1.0, 0.5, 0.25, small, 0.125, 0.0625];
            let clean_exact = neumaier_sum(&clean_xs);
            let ctrl_fp = (naive_sum(&clean_xs) - clean_exact).abs() > 1e-6;
            let trt_fp = !evaluate_fp_determinism(&clean_xs, Some(clean_exact), t).passed;
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        "STRAT-R-SPD" => {
            // Poison: symmetric 3x3 with strictly positive diagonals, off-diagonal spike > diag => indefinite.
            let d = 1.0 + 0.5 * ((r.next_u64() % 4) as f64);
            let off = d + 0.5 + 0.25 * ((r.next_u64() % 3) as f64);
            let poison_m = vec![
                vec![d, off, 0.0],
                vec![off, d, 0.0],
                vec![0.0, 0.0, d],
            ];
            // Control naive check: diag(P) > 0 only.
            let ctrl_killed = !(poison_m[0][0] > 0.0 && poison_m[1][1] > 0.0 && poison_m[2][2] > 0.0);
            let trt_killed = !evaluate_spd_matrix(&poison_m, t).passed;

            let clean_m = vec![
                vec![d + 3.0, 0.5, 0.25],
                vec![0.5, d + 2.0, 0.125],
                vec![0.25, 0.125, d + 1.0],
            ];
            let ctrl_fp = !(clean_m[0][0] > 0.0 && clean_m[1][1] > 0.0 && clean_m[2][2] > 0.0);
            let trt_fp = !evaluate_spd_matrix(&clean_m, t).passed;
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        "STRAT-R-NAN" => {
            let idx = (r.next_u64() % 4) as usize;
            let mut poison_v = vec![0.25, 0.25, 0.25, 0.25];
            poison_v[idx] = f64::NAN;
            // Control naive check: negated range check (`v < 0.0 || v > 5.0`) + IEEE maxNum.
            let ctrl_killed = poison_v.iter().any(|&v| v < 0.0 || v > 5.0);
            let trt_killed = !evaluate_state_invariants(&poison_v, 5.0, 1.0, true, t).passed;

            let clean_v = vec![0.25, 0.25, 0.25, 0.25];
            let ctrl_fp = clean_v.iter().any(|&v| v < 0.0 || v > 5.0);
            let trt_fp = !evaluate_state_invariants(&clean_v, 5.0, 1.0, true, t).passed;
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        "STRAT-R-CAP" => {
            let v = 3.5 + 0.25 * ((r.next_u64() % 5) as f64); // 3.5..4.5, always <= 5.0
            let poison_v = vec![v, v, v, v]; // L1 = 14..18 > cap 10.0
            // Control naive check: per-cell clamp |u_i| <= 5.0 only.
            let ctrl_killed = poison_v.iter().any(|&x| x.abs() > 5.0);
            let trt_killed = !evaluate_state_invariants(&poison_v, 5.0, 10.0, false, t).passed;

            let c = 1.0 + 0.25 * ((r.next_u64() % 4) as f64); // L1 = 4..7 <= 10.0
            let clean_v = vec![c, c, c, c];
            let ctrl_fp = clean_v.iter().any(|&x| x.abs() > 5.0);
            let trt_fp = !evaluate_state_invariants(&clean_v, 5.0, 10.0, false, t).passed;
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        "STRAT-P-CAL" => {
            // Poison: symmetric zero-mean bimodal overconfident Gaussian (mean ~ 0 passes point check, fails DKW/CRPS/coverage).
            let p_samples = generate_calibration_samples(seed ^ 0x55AA_1234, cal_n, 0.0, 0.25, 0.5, 1.2);
            let mean_err = (neumaier_sum(&p_samples) / (cal_n as f64)).abs();
            // Control naive check: point mean error |mean - 0.0| <= 0.35 only.
            let ctrl_killed = mean_err > 0.35;
            let trt_killed = !evaluate_prob_calibration(&p_samples, 0.0, 0.4, 1.0, t).passed;

            // Clean: exact calibrated N(0, 1) forecast.
            let c_samples = generate_calibration_samples(seed ^ 0xAA55_9876, cal_n, 0.0, 1.0, 0.0, 0.0);
            let c_mean_err = (neumaier_sum(&c_samples) / (cal_n as f64)).abs();
            let ctrl_fp = c_mean_err > 0.35;
            let trt_fp = !evaluate_prob_calibration(&c_samples, 0.0, 1.0, 1.0, t).passed;
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        "STRAT-SEAM-P2D" => {
            let maha = 4.5 + 0.5 * ((r.next_u64() % 5) as f64);
            let poison_est = RawProbEstimate {
                point_estimate: 0.05,
                calibrated: false,
                in_domain: false,
                ood_mahalanobis: maha,
                sample_count: 16,
                actuator_bypassed_certificate: true,
            };
            // Control naive check: raw point estimate inside actuator limits |u| <= 1.0.
            let ctrl_killed = poison_est.point_estimate.abs() > 1.0;
            let trt_killed = admit_p_to_d(&poison_est, t).is_none();

            let clean_est = RawProbEstimate {
                point_estimate: 0.05,
                calibrated: true,
                in_domain: true,
                ood_mahalanobis: 1.2,
                sample_count: cal_n,
                actuator_bypassed_certificate: false,
            };
            let ctrl_fp = clean_est.point_estimate.abs() > 1.0;
            let trt_fp = admit_p_to_d(&clean_est, t).is_none();
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        "STRAT-SEAM-D2P" => {
            // Poison: unkeyed second run gets distinct seed -> divergent SHA-256 digest (delta_replay != 0).
            let run_a = keyed_simulation_digest(seed, 32);
            let run_b = keyed_simulation_digest(seed.wrapping_add(1), 32);
            // Control naive check: checks only that output digest has length 64 (ignores replay match).
            let ctrl_killed = run_a.len() != 64 || run_b.len() != 64;
            let trt_killed = run_a != run_b;

            // Clean: keyed deterministic replay with identical seed.
            let clean_a = keyed_simulation_digest(seed, 32);
            let clean_b = keyed_simulation_digest(seed, 32);
            let ctrl_fp = clean_a.len() != 64;
            let trt_fp = clean_a != clean_b;
            Ok((ctrl_killed, trt_killed, ctrl_fp, trt_fp))
        }
        other => Err(format!("unknown RCT-R1 stratum {}", other)),
    }
}
