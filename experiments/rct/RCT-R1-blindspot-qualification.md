# Pre-Registered Stratified RCT Protocol (`RCT-R1`: Rung 1 Blind-Spot & Seam Qualification)

- **Organization**: Ergentics (© 2026 Ergentics, LLC)
- **Study Design**: Prospective Stratified Randomized Controlled Trial (`stratified_rct`)
- **Configuration Vault**: [`data/trials/rct_r1_config_v1.json`](../../data/trials/rct_r1_config_v1.json)
- **Policy Anchor**: [`data/manifests/swe_sweep_policy_v1.json`](../../data/manifests/swe_sweep_policy_v1.json) (`v1.2.0`)
- **Randomization Instrument**: Deterministic `SplitMix64(master_seed = 2026112301)` executed independently in Rust `1.100.0` and Swift `6.4.3`, with exact discrete decision-rule verification in Lean `v4.36.0` (no combo runners).
- **Containment Boundary**: Operates strictly on synthetic/materialized fixtures inside isolated temp directories; `Ergentics1/Riemannian` stays untouched (`0` dirty files).

---

## 1. Hypotheses & Arms

- **Control Arm (`naive_point_component_unguarded`)**:
  - Fixed-order floating-point summation check
  - Component-wise runtime bounds (`diag(P) > 0`, negated range checks / IEEE `max`, per-cell `|u_i| <= 5.0`)
  - Point-estimate mean accuracy check without calibration or proper scoring
  - Unguarded `P → D` actuator pass-through and unkeyed `D → P` entropy
- **Treatment Arm (`rung1_hardened_13_witness_compartments`)**:
  - `w_fp_determinism`: adversarial summation orderings + Neumaier compensated sum + Higham condition bound
  - `w_rt_invariants`: symmetry + Cholesky pivot floor (`min L_ii^2 > tau_spd`), positive `is_finite` guard, global conservation cap
  - `w_prob_calibration`: Massart–DKW Calibration-PIT ($\alpha = 0.01$, $n = 256$), 50%/80%/95% Clopper–Pearson coverage, CRPS/Brier proper scores, OOD Mahalanobis gate
  - `w_seam_integrity`: typed `P → D` `CertifiedEstimate` admission gate and static + SHA-256 bit-exact `D → P` replay check

---

## 2. Stratification & Sample Size

- **7 Poisoned Strata** (`n = 32` seeded replicates each, exceeding `METH-21` minimum $n \ge 30$):
  `STRAT-D-CANCEL`, `STRAT-R-SPD`, `STRAT-R-NAN`, `STRAT-R-CAP`, `STRAT-P-CAL`, `STRAT-SEAM-P2D`, `STRAT-SEAM-D2P`.
- **7 Matched Clean-Control Strata** (`n = 32` seeded replicates each):
  `CLEAN-D-FP`, `CLEAN-R-SPD`, `CLEAN-R-FINITE`, `CLEAN-R-CAP`, `CLEAN-P-CAL`, `CLEAN-SEAM-P2D`, `CLEAN-SEAM-D2P`.

---

## 3. Pre-Registered Endpoints & Promotion Rule

1. **Defect Kill Rate (TPR)** per poisoned stratum with exact **Clopper–Pearson 99% CI** (`METH-54`).
2. **False Positive Rate (FPR)** per clean-control stratum with exact **Clopper–Pearson 99% CI**.
3. **Nonparametric Dominance**: Two-tailed **Wilcoxon–Mann–Whitney $U$ test** ($\alpha = 0.01$) and **Vargha–Delaney $\hat{A}_{12}$** effect size comparing Treatment vs. Control (`METH-21`).
4. **3-Way Parity**: Exact discrete verdict parity ($\Delta_{\text{parity}} = 0$) across Rust, Swift 6.4, and Lean 4.36.

**Promotion Criteria (All Must Hold)**:
- Treatment beats Control in every stratum with $p < 0.01$ and $\hat{A}_{12} \ge 0.95$.
- **100% TPR** and **0% FPR** across all deterministic, runtime, and seam strata (`D-CANCEL`, `R-SPD`, `R-NAN`, `R-CAP`, `SEAM-P2D`, `SEAM-D2P`).
- **100% TPR** on `STRAT-P-CAL` and calibrated finite-sample FPR consistent with $\alpha = 0.01$ (visibly reported) on `CLEAN-P-CAL`.
- Exact Lean `v4.36.0` kernel verification of Sylvester SPD minors, typed `P → D` seam admission soundness, and 13-witness non-opacity.
