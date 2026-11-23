// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

//! Standalone CLI & pressure-test suite for `scargo-riem-lattice` (`RIEM-LATTICE`).

#![forbid(unsafe_code)]

use scargo_riem_lattice::riem_lattice::{all_guards_hold, failed_compartments, verify_vault_json};
use std::env;
use std::fs;
use std::process::ExitCode;

fn print_usage() {
    eprintln!("Usage: scargo-riem-lattice --vault <path/to/riemann_lattice_graph_rh_v1.json>");
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    let mut vault_path: Option<String> = None;
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--vault" && i + 1 < args.len() {
            vault_path = Some(args[i + 1].clone());
            i += 2;
        } else {
            print_usage();
            return ExitCode::from(2);
        }
    }
    let path = match vault_path {
        Some(p) => p,
        None => {
            print_usage();
            return ExitCode::from(2);
        }
    };
    let raw = match fs::read_to_string(&path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[FAIL] unable to read vault '{}': {}", path, e);
            return ExitCode::from(2);
        }
    };

    let verdicts = verify_vault_json(&raw);
    for v in &verdicts {
        let tag = if v.passed { "PASS" } else { "FAIL" };
        println!("[{}] {} — {}", tag, v.compartment, v.detail);
    }
    if all_guards_hold(&verdicts) {
        println!(
            "ALL {} ATOMIC RIEM-LATTICE GUARDS PASSED (0 violations)",
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
    use scargo_riem_lattice::riem_lattice::*;
    use std::path::PathBuf;

    fn canonical_vault_path() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../../data/sources/riemann_lattice_graph_rh_v1.json")
    }

    #[test]
    fn canonical_vault_passes_all_8_atomic_guards() {
        let raw = std::fs::read_to_string(canonical_vault_path())
            .expect("canonical vault file must exist");
        let verdicts = verify_vault_json(&raw);
        assert_eq!(verdicts.len(), 8);
        assert!(
            all_guards_hold(&verdicts),
            "unexpected failures: {:?}",
            failed_compartments(&verdicts)
        );
        assert!(failed_compartments(&verdicts).is_empty());
    }

    #[test]
    fn exact_12tet_charpoly_and_cayley_hamilton_zero_remainder() {
        let sys = NTetSystem::canonical_12tet();
        let (coeffs, rem_zero) = faddeev_leverrier_exact(&sys.gram_matrix());
        assert!(rem_zero, "Cayley-Hamilton remainder matrix must be identically zero");
        assert_eq!(
            coeffs,
            vec![
                1, -36, 558, -4916, 27303, -100056, 245924, -404088, 435183, -295684, 118446,
                -24660, 2025
            ]
        );
    }

    #[test]
    fn negative_control_poisoned_charpoly_fails_closed() {
        let raw = std::fs::read_to_string(canonical_vault_path()).expect("vault readable");
        let poisoned = raw.replacen("2025", "2026", 1);
        let verdicts = verify_vault_json(&poisoned);
        assert!(!all_guards_hold(&verdicts));
        assert_eq!(
            failed_compartments(&verdicts),
            vec!["g_plr_exact_charpoly_over_Z".to_string()]
        );
    }

    #[test]
    fn negative_control_poisoned_prime_hexagons_fails_closed() {
        let raw = std::fs::read_to_string(canonical_vault_path()).expect("vault readable");
        let poisoned = raw.replacen("\"LPLPLP_hexatonic_cycles\": 4", "\"LPLPLP_hexatonic_cycles\": 5", 1);
        let verdicts = verify_vault_json(&poisoned);
        assert!(!all_guards_hold(&verdicts));
        assert_eq!(
            failed_compartments(&verdicts),
            vec!["g_plr_prime_cycles_and_16_hexagons".to_string()]
        );
    }

    #[test]
    fn negative_control_wikipedia_url_fails_closed() {
        let raw = std::fs::read_to_string(canonical_vault_path()).expect("vault readable");
        let poisoned = raw.replacen(
            "\"verification_status\"",
            "\"poisoned_host\": \"synthetic.wikipedia.org\", \"verification_status\"",
            1,
        );
        let verdicts = verify_vault_json(&poisoned);
        assert!(!all_guards_hold(&verdicts));
        assert_eq!(
            failed_compartments(&verdicts),
            vec!["vault_tradition_and_provenance".to_string()]
        );
    }

    #[test]
    fn correspondence_principle_ntet_regime_boundary_pressure_test() {
        // 12-TET passes with exact integer margin 8 - 5 = 3
        let s12 = NTetSystem::from_n(12);
        assert!(s12.is_connected());
        let l12 = s12.max_nontrivial_lambda_sq().expect("12-TET connected");
        assert!((l12 - 5.0).abs() < 1e-12);
        assert!(l12 < 8.0);

        // 17-TET and 53-TET violate Graph RH (Alon-Boppana / flat Z^2 approach)
        let l17 = NTetSystem::from_n(17).max_nontrivial_lambda_sq().expect("17-TET connected");
        assert!(l17 > 8.0, "17-TET must fail Graph RH (got {})", l17);
        let l53 = NTetSystem::from_n(53).max_nontrivial_lambda_sq().expect("53-TET connected");
        assert!(l53 > 8.0, "53-TET must fail Graph RH (got {})", l53);

        // 24-TET fails connectivity (gcd(8, 14, 24) = 2)
        let s24 = NTetSystem::from_n(24);
        assert!(!s24.is_connected());
        assert!(s24.max_nontrivial_lambda_sq().is_none());

        // 31-TET barely stays inside Graph RH regime (< 8.0)
        let l31 = NTetSystem::from_n(31).max_nontrivial_lambda_sq().expect("31-TET connected");
        assert!(l31 < 8.0 && l31 > 7.97);
    }

    #[test]
    fn mutual_centralizer_holds_universally_across_temperaments() {
        for n in [5, 7, 12, 17, 19, 24, 31, 53] {
            let sys = NTetSystem::from_n(n);
            assert_eq!(
                sys.mutual_centralizer_violations(),
                0,
                "mutual centralizer failed for {}-TET",
                n
            );
        }
    }
}
