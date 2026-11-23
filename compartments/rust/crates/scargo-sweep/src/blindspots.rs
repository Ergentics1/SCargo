// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

#![forbid(unsafe_code)]

//! Ground-level engines for the 4 Rung 1 blind-spot and cross-type seam axes:
//! - D-Type: Floating-point non-associativity & catastrophic cancellation (Higham / Neumaier)
//! - R-Type: Global SPD Cholesky, positive finiteness, and aggregate conservation invariants
//! - P-Type: Distribution-free Massart-DKW Calibration-PIT, Clopper-Pearson coverage, CRPS/Brier, OOD
//! - Seams: Typed P -> D CertifiedEstimate admission and D -> P bit-exact keyed replay

use crate::json::JsonValue;
use crate::sha256::sha256_hex;

/// Data-driven thresholds loaded directly from `data/manifests/swe_sweep_policy_v1.json`.
#[derive(Debug, Clone)]
pub struct BlindSpotThresholds {
    pub machine_unit_f64: f64,
    pub higham_spread_multiplier: f64,
    pub max_condition_number: f64,
    pub min_retained_bits: u32,
    pub symmetry_abs_tol: f64,
    pub cholesky_min_pivot_sq: f64,
    pub probability_mass_sum_tol: f64,
    pub aggregate_cap_margin: f64,
    pub dkw_alpha: f64,
    pub min_calibration_samples: usize,
    pub coverage_quantiles: Vec<f64>,
    pub clopper_pearson_alpha: f64,
    pub max_crps_ratio_to_reference: f64,
    pub max_brier_score: f64,
    pub ood_max_mahalanobis: f64,
    pub banned_rng_rust: Vec<String>,
    pub banned_rng_swift: Vec<String>,
    pub banned_rng_lean: Vec<String>,
    pub min_replicates_per_stratum: usize,
    pub wilcoxon_alpha: f64,
    pub min_vargha_delaney_a12: f64,
}

impl BlindSpotThresholds {
    pub fn from_policy_json(policy: &JsonValue) -> Result<Self, String> {
        let root = policy
            .get("blindspot_and_seam_thresholds")
            .ok_or_else(|| "missing blindspot_and_seam_thresholds in policy".to_string())?;
        let fp = root.get("fp_determinism").ok_or("missing fp_determinism")?;
        let rt = root.get("rt_invariants").ok_or("missing rt_invariants")?;
        let cal = root.get("prob_calibration").ok_or("missing prob_calibration")?;
        let seam = root.get("seam_integrity").ok_or("missing seam_integrity")?;
        let rct = root.get("rct_qualification").ok_or("missing rct_qualification")?;
        let rng = seam
            .get("banned_unkeyed_rng_tokens")
            .ok_or("missing banned_unkeyed_rng_tokens")?;

        let parse_str_list = |v: Option<&JsonValue>| -> Result<Vec<String>, String> {
            let arr = v
                .and_then(JsonValue::as_array)
                .ok_or_else(|| "expected string array".to_string())?;
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(
                    item.as_str()
                        .ok_or_else(|| "expected string element".to_string())?
                        .to_string(),
                );
            }
            Ok(out)
        };

        let cov_arr = cal
            .get("coverage_quantiles")
            .and_then(JsonValue::as_array)
            .ok_or("missing coverage_quantiles")?;
        let mut coverage_quantiles = Vec::with_capacity(cov_arr.len());
        for item in cov_arr {
            coverage_quantiles.push(item.as_f64().ok_or("invalid coverage quantile")?);
        }

        Ok(Self {
            machine_unit_f64: fp.get("machine_unit_f64").and_then(JsonValue::as_f64).ok_or("missing machine_unit_f64")?,
            higham_spread_multiplier: fp.get("higham_spread_multiplier").and_then(JsonValue::as_f64).ok_or("missing higham_spread_multiplier")?,
            max_condition_number: fp.get("max_condition_number").and_then(JsonValue::as_f64).ok_or("missing max_condition_number")?,
            min_retained_bits: fp.get("min_retained_bits").and_then(JsonValue::as_u64).ok_or("missing min_retained_bits")? as u32,
            symmetry_abs_tol: rt.get("symmetry_abs_tol").and_then(JsonValue::as_f64).ok_or("missing symmetry_abs_tol")?,
            cholesky_min_pivot_sq: rt.get("cholesky_min_pivot_sq").and_then(JsonValue::as_f64).ok_or("missing cholesky_min_pivot_sq")?,
            probability_mass_sum_tol: rt.get("probability_mass_sum_tol").and_then(JsonValue::as_f64).ok_or("missing probability_mass_sum_tol")?,
            aggregate_cap_margin: rt.get("aggregate_cap_margin").and_then(JsonValue::as_f64).ok_or("missing aggregate_cap_margin")?,
            dkw_alpha: cal.get("dkw_alpha").and_then(JsonValue::as_f64).ok_or("missing dkw_alpha")?,
            min_calibration_samples: cal.get("min_calibration_samples").and_then(JsonValue::as_u64).ok_or("missing min_calibration_samples")? as usize,
            coverage_quantiles,
            clopper_pearson_alpha: cal.get("clopper_pearson_alpha").and_then(JsonValue::as_f64).ok_or("missing clopper_pearson_alpha")?,
            max_crps_ratio_to_reference: cal.get("max_crps_ratio_to_reference").and_then(JsonValue::as_f64).ok_or("missing max_crps_ratio_to_reference")?,
            max_brier_score: cal.get("max_brier_score").and_then(JsonValue::as_f64).ok_or("missing max_brier_score")?,
            ood_max_mahalanobis: cal.get("ood_max_mahalanobis").and_then(JsonValue::as_f64).ok_or("missing ood_max_mahalanobis")?,
            banned_rng_rust: parse_str_list(rng.get("rust"))?,
            banned_rng_swift: parse_str_list(rng.get("swift"))?,
            banned_rng_lean: parse_str_list(rng.get("lean"))?,
            min_replicates_per_stratum: rct.get("min_replicates_per_stratum").and_then(JsonValue::as_u64).ok_or("missing min_replicates_per_stratum")? as usize,
            wilcoxon_alpha: rct.get("wilcoxon_alpha").and_then(JsonValue::as_f64).ok_or("missing wilcoxon_alpha")?,
            min_vargha_delaney_a12: rct.get("min_vargha_delaney_a12").and_then(JsonValue::as_f64).ok_or("missing min_vargha_delaney_a12")?,
        })
    }
}

/// Deterministic keyed SplitMix64 PRNG (identical bit semantics across Rust and Swift).
#[derive(Debug, Clone)]
pub struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    }

    pub fn next_unit_f64(&mut self) -> f64 {
        ((self.next_u64() >> 11) as f64) * (1.0 / ((1u64 << 53) as f64))
    }

    pub fn next_normal(&mut self) -> f64 {
        let u1 = self.next_unit_f64().max(1e-15);
        let u2 = self.next_unit_f64();
        (-2.0 * u1.ln()).sqrt() * (std::f64::consts::TAU * u2).cos()
    }
}

// =============================================================================
// 1. D-Type: Floating-Point Non-Associativity & Catastrophic Cancellation
// =============================================================================

/// Neumaier improved Kahan-Babuska compensated sum; returns NaN if any input is non-finite.
pub fn neumaier_sum(xs: &[f64]) -> f64 {
    let mut sum = 0.0f64;
    let mut comp = 0.0f64;
    for &x in xs {
        if !x.is_finite() {
            return f64::NAN;
        }
        let t = sum + x;
        if sum.abs() >= x.abs() {
            comp += (sum - t) + x;
        } else {
            comp += (x - t) + sum;
        }
        sum = t;
    }
    sum + comp
}

pub fn naive_sum(xs: &[f64]) -> f64 {
    let mut acc = 0.0f64;
    for &x in xs {
        if !x.is_finite() {
            return f64::NAN;
        }
        acc += x;
    }
    acc
}

#[derive(Debug, Clone)]
pub struct FpDeterminismReport {
    pub passed: bool,
    pub compensated_sum: f64,
    pub max_order_spread: f64,
    pub condition_number: f64,
    pub higham_bound: f64,
    pub retained_bits: f64,
    pub detail: String,
}

pub fn evaluate_fp_determinism(
    xs: &[f64],
    exact_reference: Option<f64>,
    t: &BlindSpotThresholds,
) -> FpDeterminismReport {
    if xs.is_empty() || xs.iter().any(|x| !x.is_finite()) {
        return FpDeterminismReport {
            passed: false,
            compensated_sum: f64::NAN,
            max_order_spread: f64::INFINITY,
            condition_number: f64::INFINITY,
            higham_bound: 0.0,
            retained_bits: 0.0,
            detail: "empty or non-finite floating-point input vector".to_string(),
        };
    }

    let comp = neumaier_sum(xs);
    let abs_vals: Vec<f64> = xs.iter().map(|x| x.abs()).collect();
    let l1_norm = neumaier_sum(&abs_vals);
    let ref_val = exact_reference.unwrap_or(comp);

    let forward = naive_sum(xs);

    let mut rev = xs.to_vec();
    rev.reverse();
    let reverse = naive_sum(&rev);

    let mut mag_asc = xs.to_vec();
    mag_asc.sort_by(|a, b| a.abs().total_cmp(&b.abs()));
    let asc_sum = naive_sum(&mag_asc);

    let mut mag_desc = mag_asc.clone();
    mag_desc.reverse();
    let desc_sum = naive_sum(&mag_desc);

    let mut alt = Vec::with_capacity(xs.len());
    let mut lo = 0usize;
    let mut hi = mag_desc.len();
    while lo < hi {
        alt.push(mag_desc[lo]);
        lo += 1;
        if lo < hi {
            hi -= 1;
            alt.push(mag_desc[hi]);
        }
    }
    let alt_sum = naive_sum(&alt);

    let order_sums = [forward, reverse, asc_sum, desc_sum, alt_sum];
    let mut max_spread = 0.0f64;
    for &s in &order_sums {
        if !s.is_finite() {
            max_spread = f64::INFINITY;
            break;
        }
        let d = (s - ref_val).abs();
        if d > max_spread {
            max_spread = d;
        }
    }

    let n = xs.len() as f64;
    let nu = n * t.machine_unit_f64;
    let gamma_n = if nu < 1.0 { nu / (1.0 - nu) } else { f64::INFINITY };
    let denom = ref_val.abs().max(t.machine_unit_f64);
    let cond = l1_norm / denom;
    let retained_bits = (53.0 - cond.max(1.0).log2()).max(0.0);
    // Relative order spread against the exact/compensated magnitude must stay inside Higham's bound.
    let higham_abs_bound = t.higham_spread_multiplier * gamma_n * denom.max(1.0);

    let passed = comp.is_finite()
        && max_spread.is_finite()
        && cond.is_finite()
        && cond <= t.max_condition_number
        && retained_bits >= (t.min_retained_bits as f64)
        && max_spread <= higham_abs_bound;

    FpDeterminismReport {
        passed,
        compensated_sum: comp,
        max_order_spread: max_spread,
        condition_number: cond,
        higham_bound: higham_abs_bound,
        retained_bits,
        detail: format!(
            "spread={:.3e} (bound={:.3e}), kappa={:.3e}, retained_bits={:.1}",
            max_spread, higham_abs_bound, cond, retained_bits
        ),
    }
}

// =============================================================================
// 2. R-Type: Global Matrix SPD (Cholesky), Positive Finiteness, Conservation
// =============================================================================

#[derive(Debug, Clone)]
pub struct SpdReport {
    pub passed: bool,
    pub symmetric: bool,
    pub all_finite: bool,
    pub min_pivot_sq: f64,
    pub detail: String,
}

/// Global symmetric positive-definite verification via exact symmetry + Cholesky L*L^T pivot floor.
pub fn evaluate_spd_matrix(rows: &[Vec<f64>], t: &BlindSpotThresholds) -> SpdReport {
    let n = rows.len();
    if n == 0 || rows.iter().any(|r| r.len() != n) {
        return SpdReport {
            passed: false,
            symmetric: false,
            all_finite: false,
            min_pivot_sq: f64::NAN,
            detail: "empty or non-square matrix".to_string(),
        };
    }

    for row in rows {
        if row.iter().any(|v| !v.is_finite()) {
            return SpdReport {
                passed: false,
                symmetric: false,
                all_finite: false,
                min_pivot_sq: f64::NAN,
                detail: "non-finite entry in covariance matrix".to_string(),
            };
        }
    }

    for i in 0..n {
        for j in (i + 1)..n {
            if (rows[i][j] - rows[j][i]).abs() > t.symmetry_abs_tol {
                return SpdReport {
                    passed: false,
                    symmetric: false,
                    all_finite: true,
                    min_pivot_sq: f64::NAN,
                    detail: format!("asymmetry at ({},{}) > {:.2e}", i, j, t.symmetry_abs_tol),
                };
            }
        }
    }

    let mut l = vec![vec![0.0f64; n]; n];
    let mut min_pivot_sq = f64::INFINITY;
    for i in 0..n {
        for j in 0..=i {
            let mut terms = Vec::with_capacity(j);
            for k in 0..j {
                terms.push(l[i][k] * l[j][k]);
            }
            let dot = neumaier_sum(&terms);
            if !dot.is_finite() {
                return SpdReport {
                    passed: false,
                    symmetric: true,
                    all_finite: false,
                    min_pivot_sq: f64::NAN,
                    detail: "non-finite Cholesky inner product".to_string(),
                };
            }
            if i == j {
                let diag_val = rows[i][i] - dot;
                if !diag_val.is_finite() || diag_val <= t.cholesky_min_pivot_sq {
                    return SpdReport {
                        passed: false,
                        symmetric: true,
                        all_finite: diag_val.is_finite(),
                        min_pivot_sq: diag_val,
                        detail: format!(
                            "indefinite/ill-conditioned Cholesky pivot {} at index {} (floor {:.2e})",
                            diag_val, i, t.cholesky_min_pivot_sq
                        ),
                    };
                }
                if diag_val < min_pivot_sq {
                    min_pivot_sq = diag_val;
                }
                l[i][j] = diag_val.sqrt();
            } else {
                l[i][j] = (rows[i][j] - dot) / l[j][j];
            }
        }
    }

    SpdReport {
        passed: min_pivot_sq.is_finite() && min_pivot_sq > t.cholesky_min_pivot_sq,
        symmetric: true,
        all_finite: true,
        min_pivot_sq,
        detail: format!("SPD certified: min Cholesky pivot^2 = {:.6e}", min_pivot_sq),
    }
}

#[derive(Debug, Clone)]
pub struct StateInvariantReport {
    pub passed: bool,
    pub all_finite: bool,
    pub cell_bounds_ok: bool,
    pub aggregate_cap_ok: bool,
    pub simplex_ok: bool,
    pub l1_norm: f64,
    pub detail: String,
}

/// Global runtime state invariant guard: positive finiteness, per-cell bounds, aggregate L1 cap, and optional simplex mass conservation.
pub fn evaluate_state_invariants(
    vec: &[f64],
    cell_abs_bound: f64,
    aggregate_abs_cap: f64,
    require_prob_simplex: bool,
    t: &BlindSpotThresholds,
) -> StateInvariantReport {
    if vec.is_empty() || !cell_abs_bound.is_finite() || !aggregate_abs_cap.is_finite() {
        return StateInvariantReport {
            passed: false,
            all_finite: false,
            cell_bounds_ok: false,
            aggregate_cap_ok: false,
            simplex_ok: false,
            l1_norm: f64::NAN,
            detail: "empty state or non-finite bounds".to_string(),
        };
    }

    let all_finite = vec.iter().all(|v| v.is_finite());
    if !all_finite {
        return StateInvariantReport {
            passed: false,
            all_finite: false,
            cell_bounds_ok: false,
            aggregate_cap_ok: false,
            simplex_ok: false,
            l1_norm: f64::NAN,
            detail: "non-finite (NaN/Inf) sample detected in state vector".to_string(),
        };
    }

    let cell_bounds_ok = vec.iter().all(|&v| v.abs() <= cell_abs_bound);
    let abs_vals: Vec<f64> = vec.iter().map(|v| v.abs()).collect();
    let l1_norm = neumaier_sum(&abs_vals);
    let aggregate_cap_ok = l1_norm.is_finite() && l1_norm <= aggregate_abs_cap + t.aggregate_cap_margin;

    let simplex_ok = if require_prob_simplex {
        let nonneg = vec.iter().all(|&v| v >= -t.probability_mass_sum_tol);
        let mass = neumaier_sum(vec);
        nonneg && mass.is_finite() && (mass - 1.0).abs() <= t.probability_mass_sum_tol
    } else {
        true
    };

    let passed = all_finite && cell_bounds_ok && aggregate_cap_ok && simplex_ok;
    StateInvariantReport {
        passed,
        all_finite,
        cell_bounds_ok,
        aggregate_cap_ok,
        simplex_ok,
        l1_norm,
        detail: format!(
            "finite={}, cell_ok={}, l1={:.4} (cap={:.4}), simplex_ok={}",
            all_finite, cell_bounds_ok, l1_norm, aggregate_abs_cap, simplex_ok
        ),
    }
}

// =============================================================================
// 3. P-Type: Distribution-Free Calibration (Massart-DKW, Clopper-Pearson, CRPS/Brier, OOD)
// =============================================================================

/// Abramowitz & Stegun 7.1.26 error function approximation (max abs error < 1.5e-7).
pub fn erf_approx(x: f64) -> f64 {
    let sign = if x < 0.0 { -1.0 } else { 1.0 };
    let ax = x.abs();
    let t = 1.0 / (1.0 + 0.3275911 * ax);
    let y = 1.0
        - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t
            + 0.254829592)
            * t
            * (-ax * ax).exp();
    sign * y
}

pub fn normal_cdf(z: f64) -> f64 {
    0.5 * (1.0 + erf_approx(z / std::f64::consts::SQRT_2))
}

pub fn normal_pdf(z: f64) -> f64 {
    (-0.5 * z * z).exp() / (std::f64::consts::TAU).sqrt()
}

/// Inverse standard normal quantile for central coverage interval (e.g., 0.50, 0.80, 0.95) via bisection.
pub fn normal_central_z(coverage: f64) -> f64 {
    let target = 0.5 + 0.5 * coverage;
    let mut lo = 0.0f64;
    let mut hi = 8.0f64;
    for _ in 0..80 {
        let mid = 0.5 * (lo + hi);
        if normal_cdf(mid) < target {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    0.5 * (lo + hi)
}

/// Log-factorial table via lgamma recurrence for exact Clopper-Pearson binomial tails.
fn log_fact(n: usize) -> f64 {
    let mut s = 0.0f64;
    for i in 2..=n {
        s += (i as f64).ln();
    }
    s
}

fn binom_pmf(n: usize, k: usize, p: f64, log_fact_n: f64, log_fact_k: f64, log_fact_nk: f64) -> f64 {
    if p <= 0.0 {
        return if k == 0 { 1.0 } else { 0.0 };
    }
    if p >= 1.0 {
        return if k == n { 1.0 } else { 0.0 };
    }
    let lp = log_fact_n - log_fact_k - log_fact_nk
        + (k as f64) * p.ln()
        + ((n - k) as f64) * (1.0 - p).ln();
    lp.exp()
}

fn binom_tail_upper(n: usize, k: usize, p: f64, lfacts: &[f64]) -> f64 {
    let mut terms = Vec::with_capacity(n - k + 1);
    for j in k..=n {
        terms.push(binom_pmf(n, j, p, lfacts[n], lfacts[j], lfacts[n - j]));
    }
    neumaier_sum(&terms)
}

fn binom_tail_lower(n: usize, k: usize, p: f64, lfacts: &[f64]) -> f64 {
    let mut terms = Vec::with_capacity(k + 1);
    for j in 0..=k {
        terms.push(binom_pmf(n, j, p, lfacts[n], lfacts[j], lfacts[n - j]));
    }
    neumaier_sum(&terms)
}

/// Exact Clopper-Pearson two-sided confidence interval `(lower, upper)` at significance `alpha`.
pub fn clopper_pearson_ci(k: usize, n: usize, alpha: f64) -> (f64, f64) {
    if n == 0 || k > n {
        return (0.0, 1.0);
    }
    let mut lfacts = vec![0.0f64; n + 1];
    for i in 2..=n {
        lfacts[i] = lfacts[i - 1] + (i as f64).ln();
    }
    let half_alpha = 0.5 * alpha;

    let lower = if k == 0 {
        0.0
    } else {
        let mut lo = 0.0f64;
        let mut hi = (k as f64) / (n as f64);
        for _ in 0..80 {
            let mid = 0.5 * (lo + hi);
            if binom_tail_upper(n, k, mid, &lfacts) < half_alpha {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        0.5 * (lo + hi)
    };

    let upper = if k == n {
        1.0
    } else {
        let mut lo = (k as f64) / (n as f64);
        let mut hi = 1.0f64;
        for _ in 0..80 {
            let mid = 0.5 * (lo + hi);
            if binom_tail_lower(n, k, mid, &lfacts) < half_alpha {
                hi = mid;
            } else {
                lo = mid;
            }
        }
        0.5 * (lo + hi)
    };

    // Keep log_fact referenced cleanly without dead-code warnings.
    let _ = log_fact(1);
    (lower, upper)
}

/// Exact Massart-DKW threshold `sqrt(ln(2/alpha) / (2n))`.
pub fn dkw_bound(n: usize, alpha: f64) -> f64 {
    if n == 0 || alpha <= 0.0 || alpha >= 1.0 {
        return 0.0;
    }
    ((2.0 / alpha).ln() / (2.0 * (n as f64))).sqrt()
}

/// Computes Kolmogorov-Smirnov / DKW supremum distance `sup_t |F_n(t) - t|` on `[0, 1]` Calibration-PIT values.
pub fn calibration_pit_dkw_stat(pit_values: &[f64]) -> f64 {
    if pit_values.is_empty() || pit_values.iter().any(|v| !v.is_finite()) {
        return f64::INFINITY;
    }
    let mut sorted = pit_values.to_vec();
    sorted.sort_by(f64::total_cmp);
    let n = sorted.len() as f64;
    let mut max_d = 0.0f64;
    for (idx, &u) in sorted.iter().enumerate() {
        let i = (idx + 1) as f64;
        let d_plus = (i / n - u).abs();
        let d_minus = (u - (i - 1.0) / n).abs();
        let d = if d_plus >= d_minus { d_plus } else { d_minus };
        if d > max_d {
            max_d = d;
        }
    }
    max_d
}

/// Generates synthetic samples for a calibration benchmark fixture using identical SplitMix64 Box-Muller across languages.
pub fn generate_calibration_samples(
    seed: u64,
    n: usize,
    true_mean: f64,
    true_std: f64,
    mixture_weight_second: f64,
    mixture_shift: f64,
) -> Vec<f64> {
    let mut rng = SplitMix64::new(seed);
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let u = rng.next_unit_f64();
        let z = rng.next_normal();
        let center = if mixture_weight_second > 0.0 {
            if u < mixture_weight_second {
                true_mean - mixture_shift
            } else {
                true_mean + mixture_shift
            }
        } else {
            true_mean
        };
        out.push(center + true_std * z);
    }
    out
}

#[derive(Debug, Clone)]
pub struct CalibrationReport {
    pub passed: bool,
    pub sample_count: usize,
    pub dkw_stat: f64,
    pub dkw_limit: f64,
    pub crps_mean: f64,
    pub crps_ratio: f64,
    pub brier_mean: f64,
    pub coverage_violations: usize,
    pub ood_mahalanobis: f64,
    pub detail: String,
}

pub fn evaluate_prob_calibration(
    samples: &[f64],
    declared_mean: f64,
    declared_std: f64,
    ood_query_z: f64,
    t: &BlindSpotThresholds,
) -> CalibrationReport {
    let n = samples.len();
    if n < t.min_calibration_samples
        || !declared_mean.is_finite()
        || !declared_std.is_finite()
        || declared_std <= 0.0
        || !ood_query_z.is_finite()
        || samples.iter().any(|v| !v.is_finite())
    {
        return CalibrationReport {
            passed: false,
            sample_count: n,
            dkw_stat: f64::INFINITY,
            dkw_limit: dkw_bound(n.max(1), t.dkw_alpha),
            crps_mean: f64::INFINITY,
            crps_ratio: f64::INFINITY,
            brier_mean: 1.0,
            coverage_violations: t.coverage_quantiles.len(),
            ood_mahalanobis: f64::INFINITY,
            detail: "insufficient samples or invalid/non-finite predictive parameters".to_string(),
        };
    }

    let inv_sqrt_pi = 1.0 / std::f64::consts::PI.sqrt();
    let mut pits = Vec::with_capacity(n);
    let mut crps_vals = Vec::with_capacity(n);
    let mut brier_vals = Vec::with_capacity(n);
    let brier_thresholds = [
        declared_mean - declared_std,
        declared_mean,
        declared_mean + declared_std,
    ];

    for &y in samples {
        let z = (y - declared_mean) / declared_std;
        let u = normal_cdf(z);
        pits.push(u);
        let crps = declared_std * (z * (2.0 * u - 1.0) + 2.0 * normal_pdf(z) - inv_sqrt_pi);
        crps_vals.push(crps);

        let mut b_acc = 0.0f64;
        for &thr in &brier_thresholds {
            let p_pred = normal_cdf((thr - declared_mean) / declared_std);
            let ind = if y <= thr { 1.0 } else { 0.0 };
            let diff = p_pred - ind;
            b_acc += diff * diff;
        }
        brier_vals.push(b_acc / (brier_thresholds.len() as f64));
    }

    let dkw_stat = calibration_pit_dkw_stat(&pits);
    let dkw_limit = dkw_bound(n, t.dkw_alpha);
    let crps_mean = neumaier_sum(&crps_vals) / (n as f64);
    let oracle_crps = declared_std * inv_sqrt_pi;
    let crps_ratio = crps_mean / oracle_crps;
    let brier_mean = neumaier_sum(&brier_vals) / (n as f64);

    let mut coverage_violations = 0usize;
    for &q in &t.coverage_quantiles {
        let z_q = normal_central_z(q);
        let covered = samples
            .iter()
            .filter(|&&y| ((y - declared_mean).abs() / declared_std) <= z_q)
            .count();
        let (ci_lo, ci_hi) = clopper_pearson_ci(covered, n, t.clopper_pearson_alpha);
        if q < ci_lo || q > ci_hi {
            coverage_violations += 1;
        }
    }

    let ood_maha = ood_query_z.abs();
    let passed = dkw_stat <= dkw_limit
        && crps_ratio <= t.max_crps_ratio_to_reference
        && brier_mean <= t.max_brier_score
        && coverage_violations == 0
        && ood_maha <= t.ood_max_mahalanobis;

    CalibrationReport {
        passed,
        sample_count: n,
        dkw_stat,
        dkw_limit,
        crps_mean,
        crps_ratio,
        brier_mean,
        coverage_violations,
        ood_mahalanobis: ood_maha,
        detail: format!(
            "DKW={:.4} (limit={:.4}), CRPS_ratio={:.3}, Brier={:.4}, cov_viol={}, OOD_z={:.2}",
            dkw_stat, dkw_limit, crps_ratio, brier_mean, coverage_violations, ood_maha
        ),
    }
}

// =============================================================================
// 4. Cross-Type Seam Integrity (P -> D CertifiedEstimate & D -> P Keyed Replay)
// =============================================================================

#[derive(Debug, Clone)]
pub struct RawProbEstimate {
    pub point_estimate: f64,
    pub calibrated: bool,
    pub in_domain: bool,
    pub ood_mahalanobis: f64,
    pub sample_count: usize,
    pub actuator_bypassed_certificate: bool,
}

#[derive(Debug, Clone)]
pub struct CertifiedEstimate {
    value: f64,
}

impl CertifiedEstimate {
    pub fn value(&self) -> f64 {
        self.value
    }
}

/// Fail-closed P -> D admission gate: only calibrated, in-domain, finite, sufficiently sampled estimates cross to D.
pub fn admit_p_to_d(est: &RawProbEstimate, t: &BlindSpotThresholds) -> Option<CertifiedEstimate> {
    if !est.point_estimate.is_finite()
        || !est.ood_mahalanobis.is_finite()
        || !est.calibrated
        || !est.in_domain
        || est.actuator_bypassed_certificate
        || est.ood_mahalanobis > t.ood_max_mahalanobis
        || est.sample_count < t.min_calibration_samples
    {
        return None;
    }
    Some(CertifiedEstimate {
        value: est.point_estimate,
    })
}

/// Deterministic keyed simulation digest for D -> P replay invariance testing.
pub fn keyed_simulation_digest(seed: u64, steps: usize) -> String {
    let mut rng = SplitMix64::new(seed);
    let mut buf = Vec::with_capacity(steps * 8);
    for _ in 0..steps {
        buf.extend_from_slice(&rng.next_u64().to_le_bytes());
    }
    sha256_hex(&buf)
}
