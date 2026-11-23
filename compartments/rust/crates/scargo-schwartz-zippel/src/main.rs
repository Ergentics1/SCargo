// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

//! Standalone CLI and adversarial pressure-test suite for `scargo-schwartz-zippel`.

#![forbid(unsafe_code)]

use scargo_schwartz_zippel::sz_lattice::{
    all_guards_hold, failed_compartments, verify_coupled_vaults,
};
use std::env;
use std::fs;
use std::process::ExitCode;

fn print_usage() {
    eprintln!(
        "Usage: scargo-schwartz-zippel --sz-vault <schwartz_zippel_research_v1.json> --rl-vault <riemann_lattice_graph_rh_v1.json>"
    );
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mut sz_path: Option<String> = None;
    let mut rl_path: Option<String> = None;
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--sz-vault" && i + 1 < args.len() {
            sz_path = Some(args[i + 1].clone());
            i += 2;
        } else if args[i] == "--rl-vault" && i + 1 < args.len() {
            rl_path = Some(args[i + 1].clone());
            i += 2;
        } else {
            print_usage();
            return ExitCode::from(2);
        }
    }
    let (Some(sp), Some(rp)) = (sz_path, rl_path) else {
        print_usage();
        return ExitCode::from(2);
    };

    let sz_raw = match fs::read_to_string(&sp) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[FAIL] unable to read SZ vault '{}': {}", sp, e);
            return ExitCode::from(2);
        }
    };
    let rl_raw = match fs::read_to_string(&rp) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[FAIL] unable to read RL vault '{}': {}", rp, e);
            return ExitCode::from(2);
        }
    };

    let verdicts = verify_coupled_vaults(&sz_raw, &rl_raw);
    for v in &verdicts {
        let tag = if v.passed { "PASS" } else { "FAIL" };
        println!("[{}] {} — {}", tag, v.compartment, v.detail);
    }
    if all_guards_hold(&verdicts) {
        println!(
            "ALL {} ATOMIC SCHWARTZ-ZIPPEL x PLR GUARDS PASSED (0 violations)",
            verdicts.len()
        );
        ExitCode::SUCCESS
    } else {
        eprintln!(
            "FAILED COMPARTMENTS: {:?}",
            failed_compartments(&verdicts)
        );
        ExitCode::from(1)
    }
}

#[cfg(test)]
mod tests {
    use scargo_schwartz_zippel::sz_lattice::*;
    use std::path::PathBuf;

    fn sz_vault_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../../data/sources/schwartz_zippel_research_v1.json")
    }

    fn rl_vault_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../../data/sources/riemann_lattice_graph_rh_v1.json")
    }

    #[test]
    fn canonical_coupled_vaults_pass_all_9_atomic_guards() {
        let sz_raw = std::fs::read_to_string(sz_vault_path()).expect("SZ vault must exist");
        let rl_raw = std::fs::read_to_string(rl_vault_path()).expect("RL vault must exist");
        let verdicts = verify_coupled_vaults(&sz_raw, &rl_raw);
        assert_eq!(verdicts.len(), 9);
        assert!(
            all_guards_hold(&verdicts),
            "unexpected failures: {:?}",
            failed_compartments(&verdicts)
        );
    }

    #[test]
    fn correspondence_principle_binary_vs_composite_vs_cyclotomic_torus_vs_field() {
        // Binary grid {0,1} stalls at D = 2 (z^2 - z vanishes identically)
        assert!(guard_nonvacuous_degree(1, 2).passed);
        assert!(!guard_nonvacuous_degree(2, 2).passed);
        for z in [0u64, 1] {
            assert_eq!((z * z + 13 - z) % 13, 0);
        }

        // Composite ring Z/12Z collapses safe grid capacity back to p_min(12) = 2
        assert!(!guard_prime_integral_domain(12).passed);
        assert_eq!(smallest_prime_factor(12), 2);
        assert!(guard_condition_d_grid(12, &[0, 1]).passed);
        assert!(!guard_condition_d_grid(12, &[0, 1, 2]).passed);

        // Composite ring Z/6Z: x*(x-1) has 4/6 roots (2x SZ violation); Z/30Z has 8/30 (4x violation)
        assert_eq!((0..6u64).filter(|&x| (x * (x + 5)) % 6 == 0).count(), 4);
        assert_eq!((0..30u64).filter(|&x| (x * (x + 29)) % 30 == 0).count(), 8);
        assert!(guard_condition_d_grid(6, &[0, 1]).passed);
        assert!(!guard_condition_d_grid(6, &[0, 1, 3, 4]).passed);

        // 12-fold cyclotomic torus mu_12 in F_13: holds up to D = 11, stalls sharply at D = 12 (z^12 - 1)
        let torus13 = CyclotomicPlrTorus::new(13, 2).expect("F_13 cyclotomic torus");
        assert!(torus13.verify_all_24_triads());
        assert!(guard_nonvacuous_degree(11, 12).passed);
        assert!(!guard_nonvacuous_degree(12, 12).passed);
        for r in 0..12u64 {
            let z = mod_pow(2, r, 13);
            assert_eq!((mod_pow(z, 12, 13) + 13 - 1) % 13, 0);
        }
        // Full F_13 stalls at D = 13 (Frobenius z^13 - z)
        for z in 0..13u64 {
            assert_eq!((mod_pow(z, 13, 13) + 13 - z) % 13, 0);
        }
    }

    #[test]
    fn coupled_nonabelian_holonomy_and_cycle_sieve_pressure_test() {
        let torus = CyclotomicPlrTorus::new(65521, 53059).expect("F_65521 torus");
        assert!(torus.verify_all_24_triads());

        // Non-abelian separation: PL != LP on torus and under faithful rho_1, but abelian k=0 collapses them
        let p0 = torus.embed_triad(0, true);
        assert_ne!(
            torus.apply_word_bilinear(&[PlrOp::P, PlrOp::L], p0),
            torus.apply_word_bilinear(&[PlrOp::L, PlrOp::P], p0)
        );
        assert_eq!(
            rho_word(65521, 53059, 0, &[PlrOp::P, PlrOp::L]),
            rho_word(65521, 53059, 0, &[PlrOp::L, PlrOp::P])
        );
        let m_pl = rho_word(65521, 53059, 1, &[PlrOp::P, PlrOp::L]);
        let m_lp = rho_word(65521, 53059, 1, &[PlrOp::L, PlrOp::P]);
        assert_ne!(m_pl, m_lp);
        // Freivalds random vector distinguishes rho_1(PL) vs rho_1(LP) in O(1)
        let mut rng = SplitMix64::new(42);
        let v = (rng.next_mod(65521), rng.next_mod(65521));
        assert_ne!(m_pl.mul_vec(v, 65521), m_lp.mul_vec(v, 65521));

        // Representation-filtered length-6 cycle sieve
        let sieve = sieve_len6_cycles_g_plr();
        assert_eq!(sieve.total_walks, 192);
        assert_eq!(sieve.contractible_walks, 144);
        assert_eq!(sieve.non_contractible_walks, 48);
        assert_eq!(sieve.unoriented_lprlpr_faces, 12);
        assert_eq!(sieve.unoriented_lplplp_hexatonic, 4);
    }

    #[test]
    fn coupled_ramanujan_nb_mixing_beats_srw_and_rejects_17tet() {
        let rep12 = analyze_ntet_mixing(12, 4, 3, 20);
        let rep17 = analyze_ntet_mixing(17, 5, 5, 20);

        assert!(guard_ramanujan_nb_mixing(&rep12).passed);
        assert!(!guard_ramanujan_nb_mixing(&rep17).passed);
        assert!((rep12.nb_ihara_nontrivial_rate - (1.0 / 2.0f64.sqrt())).abs() < 1e-9);
        assert!((rep12.srw_nontrivial_rate - (5.0f64.sqrt() / 3.0)).abs() < 1e-9);
        assert!(rep17.nb_ihara_nontrivial_rate > 0.83);
        assert!(rep17.tv_step_20_nb / rep12.tv_step_20_nb > 20.0);
    }

    #[test]
    fn direct_g_plr_bridge_and_all_ones_char3_char5_false_negative() {
        assert_eq!(g_plr_exact_det_bareiss(), 45);
        assert_eq!(g_plr_exact_perm(), 113);

        // Deterministic all-1s evaluation vanishes mod 3 and mod 5 despite 113 matchings
        let b_u64: Vec<Vec<u64>> = g_plr_biadjacency_matrix()
            .into_iter()
            .map(|r| r.into_iter().map(|v| v as u64).collect())
            .collect();
        assert_eq!(det_mod_prime(&b_u64, 3), Some(0));
        assert_eq!(det_mod_prime(&b_u64, 5), Some(0));
        assert_eq!(det_mod_prime(&b_u64, 13), Some(45 % 13));

        // Randomized Edmonds PIT over F_65521 detects perfect matching reliably
        assert_eq!(edmonds_pit_g_plr(65521, 4, 777), Some(true));
        // Composite modulus rejected fail-closed (returns None)
        assert_eq!(edmonds_pit_g_plr(12, 4, 777), None);

        // Bass-Ihara D(u) PIT matches exact factored form and detects poisoned factor
        for u in [3u64, 17, 511, 12345] {
            let exact = bass_ihara_d_matrix_mod_p(u, 65521).expect("prime");
            let factored = bass_ihara_d_factored_mod_p(u, 65521);
            assert_eq!(exact, factored);
            assert_ne!(exact, (factored + 1) % 65521);
        }
    }

    #[test]
    fn negative_controls_poisoned_vaults_and_matrices_fail_closed() {
        let sz_raw = std::fs::read_to_string(sz_vault_path()).expect("SZ vault");
        let rl_raw = std::fs::read_to_string(rl_vault_path()).expect("RL vault");

        // 1. Poisoned permanent fails only bridge compartment
        let p1 = sz_raw.replacen(
            "\"exact_perm_B_perfect_matchings\": 113",
            "\"exact_perm_B_perfect_matchings\": 114",
            1,
        );
        assert_eq!(
            failed_compartments(&verify_coupled_vaults(&p1, &rl_raw)),
            vec!["g_plr_edmonds_and_bass_ihara_pit_bridge".to_string()]
        );

        // 2. Poisoned cycle sieve fails only sieve compartment
        let p2 = sz_raw.replacen("\"contractible_walks\": 144", "\"contractible_walks\": 140", 1);
        assert_eq!(
            failed_compartments(&verify_coupled_vaults(&p2, &rl_raw)),
            vec!["coupled_cycle_sieve_len6_cross_vault".to_string()]
        );

        // 3. Synthetic wiki host fails only provenance compartment
        let p3 = sz_raw.replacen(
            "\"verification_status\"",
            "\"poisoned_host\": \"synthetic.wikipedia.org\", \"verification_status\"",
            1,
        );
        assert_eq!(
            failed_compartments(&verify_coupled_vaults(&p3, &rl_raw)),
            vec!["vault_tradition_and_provenance".to_string()]
        );

        // 4. Freivalds rejects a single-entry poisoned Gram matrix
        let b_u64: Vec<Vec<u64>> = g_plr_biadjacency_matrix()
            .into_iter()
            .map(|r| r.into_iter().map(|v| v as u64).collect())
            .collect();
        let mut bt = vec![vec![0u64; 12]; 12];
        let mut gram = vec![vec![0u64; 12]; 12];
        for i in 0..12 {
            for j in 0..12 {
                bt[j][i] = b_u64[i][j];
            }
        }
        for i in 0..12 {
            for j in 0..12 {
                for k in 0..12 {
                    gram[i][j] = (gram[i][j] + b_u64[i][k] * bt[k][j]) % 65521;
                }
            }
        }
        gram[0][0] = (gram[0][0] + 1) % 65521;
        assert_eq!(freivalds_verify_mod_p(&b_u64, &bt, &gram, 65521, 4, 12345), Some(false));
        assert_eq!(freivalds_verify_mod_p(&b_u64, &bt, &gram, 12, 4, 12345), None);
    }

    #[test]
    fn constraint_arity_and_global_degree_boundary_pressure_test() {
        // Linear combination of m constraints of arity r=3 (degree d_c=3) preserves D = 3 < 12 on mu_12
        let d_linear = 3usize;
        assert!(guard_nonvacuous_degree(d_linear, 12).passed);

        // Conjunctive product of m=4 constraints of arity r=3 drives D = 12 >= 12 (stalls on mu_12!)
        let d_conjunctive = 4 * 3;
        assert!(!guard_nonvacuous_degree(d_conjunctive, 12).passed);
        // Lifting from mu_12 (|S|=12) to full prime torus F_65521 (|S|=65521) restores D=12 < 65521!
        assert!(guard_nonvacuous_degree(d_conjunctive, 65521).passed);

        // Low-entropy Ramanujan walk uses strictly less entropy than independent draws
        for k in [4usize, 8, 16, 32] {
            let indep_bits = (k as f64) * 24.0f64.log2();
            let nb_bits = 24.0f64.log2() + ((k - 1) as f64);
            assert!(nb_bits * 2.4 < indep_bits);
        }
    }
}
