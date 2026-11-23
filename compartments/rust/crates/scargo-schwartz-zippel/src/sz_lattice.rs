// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

//! Core zero-dependency engine for Schwartz-Zippel (ODLSZ) coupled with the
//! Neo-Riemannian PLR 12-fold cyclotomic torus and non-backtracking Ihara operator.

#![forbid(unsafe_code)]

use std::collections::{BTreeMap, BTreeSet};

/// Atomic fail-closed boolean guard verdict.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GuardVerdict {
    pub compartment: String,
    pub passed: bool,
    pub violation_count: usize,
    pub detail: String,
}

impl GuardVerdict {
    pub fn from_violations(compartment: &str, violation_count: usize, detail: String) -> Self {
        Self {
            compartment: compartment.to_string(),
            passed: violation_count == 0,
            violation_count,
            detail,
        }
    }
}

pub fn all_guards_hold(verdicts: &[GuardVerdict]) -> bool {
    verdicts.iter().all(|v| v.passed)
}

pub fn failed_compartments(verdicts: &[GuardVerdict]) -> Vec<String> {
    verdicts
        .iter()
        .filter(|v| !v.passed)
        .map(|v| v.compartment.clone())
        .collect()
}

/// Deterministic SplitMix64 PRNG for seeded PIT verification.
#[derive(Debug, Clone)]
pub struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    pub fn next_mod(&mut self, m: u64) -> u64 {
        self.next_u64() % m
    }
}

/// Greatest common divisor.
pub fn gcd_u64(mut a: u64, mut b: u64) -> u64 {
    while b != 0 {
        let r = a % b;
        a = b;
        b = r;
    }
    a
}

/// Smallest prime factor of `m >= 2` (equals max Condition (D) grid capacity in `Z/mZ`).
pub fn smallest_prime_factor(m: u64) -> u64 {
    if m < 2 {
        return 0;
    }
    if m.is_multiple_of(2) {
        return 2;
    }
    let mut d = 3u64;
    while d <= m / d {
        if m.is_multiple_of(d) {
            return d;
        }
        d += 2;
    }
    m
}

pub fn is_prime(m: u64) -> bool {
    m >= 2 && smallest_prime_factor(m) == m
}

/// Modular exponentiation `(base^exp) mod m` using 128-bit intermediates.
pub fn mod_pow(mut base: u64, mut exp: u64, m: u64) -> u64 {
    if m <= 1 {
        return 0;
    }
    let mut acc = 1u128;
    base %= m;
    let m128 = m as u128;
    let mut b = base as u128;
    while exp > 0 {
        if exp & 1 == 1 {
            acc = (acc * b) % m128;
        }
        b = (b * b) % m128;
        exp >>= 1;
    }
    acc as u64
}

/// Modular multiplicative inverse in prime field `F_p`.
pub fn mod_inv_prime(a: u64, p: u64) -> Option<u64> {
    if !is_prime(p) || a.is_multiple_of(p) {
        return None;
    }
    Some(mod_pow(a % p, p - 2, p))
}

/// Verifies `z` is a primitive 12th root of unity in `F_p` (`p = 1 mod 12`, `Phi_12(z) = 0`).
pub fn is_primitive_12th_root(p: u64, z: u64) -> bool {
    if !is_prime(p) || p % 12 != 1 {
        return false;
    }
    let z12 = mod_pow(z, 12, p);
    let z6 = mod_pow(z, 6, p);
    let z4 = mod_pow(z, 4, p);
    let z2 = mod_pow(z, 2, p);
    let phi12 = (z4 + p - z2 + 1) % p;
    z12 == 1 && z6 != 1 && z4 != 1 && phi12 == 0
}

/// Finds the smallest primitive 12th root of unity in `F_p` (`p = 1 mod 12`).
pub fn find_primitive_12th_root(p: u64) -> Option<u64> {
    if !is_prime(p) || p % 12 != 1 {
        return None;
    }
    for g in 2..p {
        let cand = mod_pow(g, (p - 1) / 12, p);
        if is_primitive_12th_root(p, cand) {
            return Some(cand);
        }
    }
    None
}

/// Neo-Riemannian PLR generators.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum PlrOp {
    P,
    L,
    R,
}

impl PlrOp {
    pub const ALL: [PlrOp; 3] = [PlrOp::P, PlrOp::L, PlrOp::R];

    pub fn shift_mod12(self) -> u64 {
        match self {
            PlrOp::P => 0,
            PlrOp::L => 4,
            PlrOp::R => 9,
        }
    }

    pub fn honeycomb_vec(self) -> (i32, i32) {
        match self {
            PlrOp::P => (1, 0),
            PlrOp::L => (0, 1),
            PlrOp::R => (-1, -1),
        }
    }
}

/// 12-fold cyclotomic torus `mu_12 x {+1, -1}` embedded in prime field `F_p` (`p = 1 mod 12`).
#[derive(Debug, Clone)]
pub struct CyclotomicPlrTorus {
    pub p: u64,
    pub zeta12: u64,
    inv2: u64,
}

impl CyclotomicPlrTorus {
    pub fn new(p: u64, zeta12: u64) -> Option<Self> {
        if !is_primitive_12th_root(p, zeta12) {
            return None;
        }
        let inv2 = p.div_ceil(2);
        Some(Self { p, zeta12, inv2 })
    }

    pub fn embed_triad(&self, root: u64, is_major: bool) -> (u64, u64) {
        let z = mod_pow(self.zeta12, root % 12, self.p);
        let sig = if is_major { 1 } else { self.p - 1 };
        (z, sig)
    }

    /// Bilinear degree-2 involution `(z, sig) -> (z * (c_s + sig * d_s), -sig)`.
    pub fn apply_bilinear(&self, op: PlrOp, pt: (u64, u64)) -> (u64, u64) {
        let s = op.shift_mod12();
        let zs = mod_pow(self.zeta12, s, self.p) as u128;
        let zms = mod_pow(self.zeta12, (12 - s) % 12, self.p) as u128;
        let p = self.p as u128;
        let inv2 = self.inv2 as u128;
        let cs = ((zs + zms) % p * inv2) % p;
        let ds = ((zs + p - zms) % p * inv2) % p;
        let factor = (cs + (pt.1 as u128 * ds) % p) % p;
        let new_z = ((pt.0 as u128 * factor) % p) as u64;
        let new_sig = if pt.1 == 0 { 0 } else { self.p - pt.1 };
        (new_z, new_sig)
    }

    pub fn apply_word_bilinear(&self, word: &[PlrOp], mut pt: (u64, u64)) -> (u64, u64) {
        for &op in word.iter().rev() {
            pt = self.apply_bilinear(op, pt);
        }
        pt
    }

    /// Verifies exact involutivity and isomorphism with combinatorial `G_PLR` across all 24 triads.
    pub fn verify_all_24_triads(&self) -> bool {
        let mut roots = BTreeSet::new();
        for r in 0..12u64 {
            roots.insert(mod_pow(self.zeta12, r, self.p));
        }
        if roots.len() != 12 {
            return false;
        }
        for r in 0..12u64 {
            for is_major in [true, false] {
                let pt = self.embed_triad(r, is_major);
                for op in PlrOp::ALL {
                    let pt1 = self.apply_bilinear(op, pt);
                    let pt2 = self.apply_bilinear(op, pt1);
                    let r_exp = if is_major {
                        (r + op.shift_mod12()) % 12
                    } else {
                        (r + 12 - op.shift_mod12()) % 12
                    };
                    let expected = self.embed_triad(r_exp, !is_major);
                    if pt1 != expected || pt2 != pt {
                        return false;
                    }
                }
            }
        }
        true
    }
}

/// 2x2 matrix over `F_p` for dihedral representation `rho_k(D_12)`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Mat2 {
    pub a: u64,
    pub b: u64,
    pub c: u64,
    pub d: u64,
}

impl Mat2 {
    pub const ID: Mat2 = Mat2 {
        a: 1,
        b: 0,
        c: 0,
        d: 1,
    };

    pub fn mul(self, rhs: Mat2, p: u64) -> Mat2 {
        let m = p as u128;
        Mat2 {
            a: ((self.a as u128 * rhs.a as u128 + self.b as u128 * rhs.c as u128) % m) as u64,
            b: ((self.a as u128 * rhs.b as u128 + self.b as u128 * rhs.d as u128) % m) as u64,
            c: ((self.c as u128 * rhs.a as u128 + self.d as u128 * rhs.c as u128) % m) as u64,
            d: ((self.c as u128 * rhs.b as u128 + self.d as u128 * rhs.d as u128) % m) as u64,
        }
    }

    pub fn mul_vec(self, v: (u64, u64), p: u64) -> (u64, u64) {
        let m = p as u128;
        (
            ((self.a as u128 * v.0 as u128 + self.b as u128 * v.1 as u128) % m) as u64,
            ((self.c as u128 * v.0 as u128 + self.d as u128 * v.1 as u128) % m) as u64,
        )
    }
}

/// Generator matrix `rho_k(op)` in `GL_2(F_p)`.
pub fn rho_gen(p: u64, zeta12: u64, k: u64, op: PlrOp) -> Mat2 {
    let s = op.shift_mod12();
    let up = mod_pow(zeta12, (12 - (s * k) % 12) % 12, p);
    let dn = mod_pow(zeta12, (s * k) % 12, p);
    Mat2 {
        a: 0,
        b: up,
        c: dn,
        d: 0,
    }
}

pub fn rho_word(p: u64, zeta12: u64, k: u64, word: &[PlrOp]) -> Mat2 {
    let mut acc = Mat2::ID;
    for &op in word {
        acc = acc.mul(rho_gen(p, zeta12, k, op), p);
    }
    acc
}

/// Returns `(distinct_matrices, kernel_size)` of `rho_k` over all 24 elements of `D_12`.
pub fn rho_image_and_kernel(p: u64, zeta12: u64, k: u64) -> (usize, usize) {
    let mut mats = BTreeSet::new();
    let mut ker = 0usize;
    for r in 0..12u64 {
        let rot = Mat2 {
            a: mod_pow(zeta12, (r * k) % 12, p),
            b: 0,
            c: 0,
            d: mod_pow(zeta12, (12 - (r * k) % 12) % 12, p),
        };
        if rot == Mat2::ID {
            ker += 1;
        }
        mats.insert(rot);

        let refl = Mat2 {
            a: 0,
            b: mod_pow(zeta12, (12 - (r * k) % 12) % 12, p),
            c: mod_pow(zeta12, (r * k) % 12, p),
            d: 0,
        };
        if refl == Mat2::ID {
            ker += 1;
        }
        mats.insert(refl);
    }
    (mats.len(), ker)
}

/// Randomized Freivalds check for `A * B = C` over `F_p` (`k` independent trials).
pub fn freivalds_verify_mod_p(
    a: &[Vec<u64>],
    b: &[Vec<u64>],
    c: &[Vec<u64>],
    p: u64,
    trials: usize,
    seed: u64,
) -> Option<bool> {
    if !is_prime(p) || trials == 0 {
        return None;
    }
    let n = a.len();
    let m = p as u128;
    let mut rng = SplitMix64::new(seed);
    for _ in 0..trials {
        let r: Vec<u64> = (0..n).map(|_| rng.next_mod(p)).collect();
        let br = mat_vec_mod(b, &r, m);
        let abr = mat_vec_mod(a, &br, m);
        let cr = mat_vec_mod(c, &r, m);
        if abr != cr {
            return Some(false);
        }
    }
    Some(true)
}

fn mat_vec_mod(mat: &[Vec<u64>], v: &[u64], m: u128) -> Vec<u64> {
    mat.iter()
        .map(|row| {
            let mut sum = 0u128;
            for (val, &x) in row.iter().zip(v.iter()) {
                sum = (sum + (*val as u128 * x as u128) % m) % m;
            }
            sum as u64
        })
        .collect()
}

/// Mixing comparison between Simple Random Walk `(1/3) A` and Non-Backtracking
/// Hashimoto/Ihara walk `(1/2) T` on an `N`-TET Tonnetz dual.
#[derive(Debug, Clone)]
pub struct MixingReport {
    pub n_tet: usize,
    pub directed_edges: usize,
    pub max_nontrivial_lambda_sq: f64,
    pub satisfies_graph_rh: bool,
    pub srw_nontrivial_rate: f64,
    pub nb_ihara_nontrivial_rate: f64,
    pub tv_step_20_srw: f64,
    pub tv_step_20_nb: f64,
    pub mass_conserved: bool,
}

/// Neumaier compensated sum that fails closed to NaN if any summand is non-finite.
fn neumaier_sum(xs: &[f64]) -> f64 {
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

fn probability_vector_conserved(vec: &[f64], tol: f64) -> bool {
    if !tol.is_finite() || tol < 0.0 {
        return false;
    }
    if vec.iter().any(|&v| !v.is_finite() || v < -tol) {
        return false;
    }
    let total = neumaier_sum(vec);
    total.is_finite() && (total - 1.0).abs() <= tol
}

pub fn analyze_ntet_mixing(n_tet: usize, m3: usize, minor3: usize, steps: usize) -> MixingReport {
    let v_count = 2 * n_tet;
    let shifts = [0usize, m3 % n_tet, (n_tet - (minor3 % n_tet)) % n_tet];
    let mut adj: Vec<Vec<usize>> = vec![Vec::new(); v_count];
    for r in 0..n_tet {
        for &sh in &shifts {
            let v = n_tet + ((r + sh) % n_tet);
            adj[r].push(v);
            adj[v].push(r);
        }
    }

    let mut dir_edges: Vec<(usize, usize)> = Vec::new();
    let mut edge_idx: BTreeMap<(usize, usize), usize> = BTreeMap::new();
    for (u, nbrs) in adj.iter().enumerate() {
        for &v in nbrs {
            let id = dir_edges.len();
            dir_edges.push((u, v));
            edge_idx.insert((u, v), id);
        }
    }
    let e2 = dir_edges.len();

    // Exact Fourier spectrum of B*B^T with NaN-propagating maximum.
    let mut max_y = 0.0f64;
    let two_pi = std::f64::consts::TAU;
    for k in 1..n_tet {
        let th1 = two_pi * ((m3 * k) % n_tet) as f64 / (n_tet as f64);
        let th2 = two_pi * ((n_tet - ((minor3 * k) % n_tet)) % n_tet) as f64 / (n_tet as f64);
        let re = neumaier_sum(&[1.0, th1.cos(), th2.cos()]);
        let im = th1.sin() + th2.sin();
        let y = re * re + im * im;
        if !y.is_finite() {
            max_y = f64::NAN;
            break;
        }
        if y > max_y {
            max_y = y;
        }
    }
    let satisfies_graph_rh = max_y.is_finite() && max_y < 8.0;
    let srw_rate = if max_y.is_finite() { max_y.sqrt() / 3.0 } else { f64::NAN };
    let nb_rate = if !max_y.is_finite() {
        f64::NAN
    } else if satisfies_graph_rh {
        1.0 / 2.0f64.sqrt()
    } else {
        (max_y.sqrt() + (max_y - 8.0).sqrt()) / 4.0
    };

    let mass_tol = 1e-11;
    let mut p_srw = vec![0.0f64; v_count];
    p_srw[0] = 1.0;
    let mut p_nb = vec![0.0f64; e2];
    for &v in &adj[0] {
        p_nb[edge_idx[&(0, v)]] = 1.0 / 3.0;
    }

    let mut mass_conserved =
        probability_vector_conserved(&p_srw, mass_tol) && probability_vector_conserved(&p_nb, mass_tol);

    // Advance step 1 for SRW (NB starts already at edge (0, v) after step 1).
    p_srw = step_srw(&adj, &p_srw);
    mass_conserved &= probability_vector_conserved(&p_srw, mass_tol);
    for _ in 2..=steps {
        p_srw = step_srw(&adj, &p_srw);
        p_nb = step_nb(&adj, &dir_edges, &edge_idx, &p_nb);
        mass_conserved &= probability_vector_conserved(&p_srw, mass_tol)
            && probability_vector_conserved(&p_nb, mass_tol);
    }

    let mut v_nb = vec![0.0f64; v_count];
    for (i, &mass) in p_nb.iter().enumerate() {
        v_nb[dir_edges[i].1] += mass;
    }
    mass_conserved &= probability_vector_conserved(&v_nb, mass_tol);

    let stationary = 1.0 / (n_tet as f64);
    let diffs_srw: Vec<f64> = p_srw[..n_tet]
        .iter()
        .map(|&x| (x - stationary).abs())
        .collect();
    let diffs_nb: Vec<f64> = v_nb[..n_tet]
        .iter()
        .map(|&x| (x - stationary).abs())
        .collect();
    let tv_srw = 0.5 * neumaier_sum(&diffs_srw);
    let tv_nb = 0.5 * neumaier_sum(&diffs_nb);
    mass_conserved &= tv_srw.is_finite() && tv_nb.is_finite();

    MixingReport {
        n_tet,
        directed_edges: e2,
        max_nontrivial_lambda_sq: max_y,
        satisfies_graph_rh,
        srw_nontrivial_rate: srw_rate,
        nb_ihara_nontrivial_rate: nb_rate,
        tv_step_20_srw: tv_srw,
        tv_step_20_nb: tv_nb,
        mass_conserved,
    }
}

fn step_srw(adj: &[Vec<usize>], vec: &[f64]) -> Vec<f64> {
    let mut nxt = vec![0.0f64; vec.len()];
    for (u, &mass) in vec.iter().enumerate() {
        if mass > 0.0 {
            let share = mass / (adj[u].len() as f64);
            for &v in &adj[u] {
                nxt[v] += share;
            }
        }
    }
    nxt
}

fn step_nb(
    adj: &[Vec<usize>],
    dir_edges: &[(usize, usize)],
    edge_idx: &BTreeMap<(usize, usize), usize>,
    evec: &[f64],
) -> Vec<f64> {
    let mut nxt = vec![0.0f64; evec.len()];
    for (i, &mass) in evec.iter().enumerate() {
        if mass > 0.0 {
            let (u, v) = dir_edges[i];
            let share = mass / ((adj[v].len() - 1) as f64);
            for &w in &adj[v] {
                if w != u {
                    nxt[edge_idx[&(v, w)]] += share;
                }
            }
        }
    }
    nxt
}

/// Representation / homology-filtered cycle sieving at length 6 on `G_PLR`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CycleSieveLen6 {
    pub total_walks: usize,
    pub contractible_walks: usize,
    pub non_contractible_walks: usize,
    pub unoriented_lprlpr_faces: usize,
    pub unoriented_lplplp_hexatonic: usize,
}

pub fn sieve_len6_cycles_g_plr() -> CycleSieveLen6 {
    let mut words: Vec<[PlrOp; 6]> = Vec::new();
    let mut buf = [PlrOp::P; 6];
    gen_nb_words6(0, None, &mut buf, &mut words);

    let mut contractible = 0usize;
    let mut non_contractible = 0usize;
    for r0 in 0..12u64 {
        for is_maj0 in [true, false] {
            for w in &words {
                if w[0] == w[5] {
                    continue; // tailless requirement
                }
                let mut r = r0;
                let mut maj = is_maj0;
                let mut wx = 0i32;
                let mut wy = 0i32;
                for &op in w {
                    let (dx, dy) = op.honeycomb_vec();
                    if maj {
                        wx += dx;
                        wy += dy;
                        r = (r + op.shift_mod12()) % 12;
                    } else {
                        wx -= dx;
                        wy -= dy;
                        r = (r + 12 - op.shift_mod12()) % 12;
                    }
                    maj = !maj;
                }
                if r == r0 && maj == is_maj0 {
                    if wx == 0 && wy == 0 {
                        contractible += 1;
                    } else {
                        non_contractible += 1;
                    }
                }
            }
        }
    }
    CycleSieveLen6 {
        total_walks: contractible + non_contractible,
        contractible_walks: contractible,
        non_contractible_walks: non_contractible,
        unoriented_lprlpr_faces: contractible / 12,
        unoriented_lplplp_hexatonic: non_contractible / 12,
    }
}

fn gen_nb_words6(pos: usize, prev: Option<PlrOp>, buf: &mut [PlrOp; 6], out: &mut Vec<[PlrOp; 6]>) {
    if pos == 6 {
        out.push(*buf);
        return;
    }
    for op in PlrOp::ALL {
        if prev == Some(op) {
            continue;
        }
        buf[pos] = op;
        gen_nb_words6(pos + 1, Some(op), buf, out);
    }
}

/// Twisted homology character sum over length-6 closed NB walks evaluated at `(x, y)` in `F_p`.
/// Equals `144 + 24 * (x^3 y^-3 + x^-3 y^3) mod p`; subtracting `144` isolates non-contractible cycles!
pub fn twisted_len6_character_pit(p: u64, x: u64, y: u64) -> Option<u64> {
    let x_inv = mod_inv_prime(x, p)?;
    let y_inv = mod_inv_prime(y, p)?;
    let m = p as u128;
    let x3 = mod_pow(x, 3, p) as u128;
    let xi3 = mod_pow(x_inv, 3, p) as u128;
    let y3 = mod_pow(y, 3, p) as u128;
    let yi3 = mod_pow(y_inv, 3, p) as u128;
    let non_triv = (24u128 * ((x3 * yi3) % m + (xi3 * y3) % m)) % m;
    Some(((144u128 + non_triv) % m) as u64)
}

/// Low-entropy non-backtracking Ramanujan walk on `G_PLR` (`1` random bit per step after start).
pub fn ramanujan_nb_walk_torus(
    torus: &CyclotomicPlrTorus,
    steps: usize,
    seed: u64,
) -> Vec<(u64, u64)> {
    let mut rng = SplitMix64::new(seed);
    let r0 = rng.next_mod(12);
    let maj0 = (rng.next_u64() & 1) == 0;
    let mut pt = torus.embed_triad(r0, maj0);
    let mut pts = Vec::with_capacity(steps);
    pts.push(pt);
    let mut prev: Option<PlrOp> = None;
    for _ in 1..steps {
        let choices: Vec<PlrOp> = PlrOp::ALL
            .into_iter()
            .filter(|&op| Some(op) != prev)
            .collect();
        let bit = (rng.next_u64() & 1) as usize;
        let op = choices[bit % choices.len()];
        pt = torus.apply_bilinear(op, pt);
        pts.push(pt);
        prev = Some(op);
    }
    pts
}

/// Evaluates univariate polynomial (ascending coeffs) mod `p`.
pub fn eval_uni_mod(coeffs: &[u64], x: u64, p: u64) -> u64 {
    let m = p as u128;
    let mut acc = 0u128;
    for &c in coeffs.iter().rev() {
        acc = (acc * (x as u128) + (c as u128)) % m;
    }
    acc as u64
}

/// Direct `G_PLR` bridge: exact `det(B) = 45`, `perm(B) = 113`, Edmonds symbolic PIT, and Bass-Ihara PIT.
pub fn g_plr_biadjacency_matrix() -> Vec<Vec<i64>> {
    let mut b = vec![vec![0i64; 12]; 12];
    for (r, row) in b.iter_mut().enumerate() {
        for sh in [0usize, 4, 9] {
            row[(r + sh) % 12] = 1;
        }
    }
    b
}

/// Exact permanent of 12x12 `G_PLR` biadjacency matrix (`113` perfect matchings).
pub fn g_plr_exact_perm() -> u64 {
    let mut dp = vec![0u64; 1 << 12];
    dp[0] = 1;
    for r in 0..12usize {
        let cols = [r % 12, (r + 4) % 12, (r + 9) % 12];
        let mut ndp = vec![0u64; 1 << 12];
        for (mask, &cnt) in dp.iter().enumerate() {
            if cnt == 0 {
                continue;
            }
            for &c in &cols {
                if (mask & (1 << c)) == 0 {
                    ndp[mask | (1 << c)] += cnt;
                }
            }
        }
        dp = ndp;
    }
    dp[(1 << 12) - 1]
}

/// Determinant modulo prime `p` via Gaussian elimination in `F_p`.
pub fn det_mod_prime(mat: &[Vec<u64>], p: u64) -> Option<u64> {
    if !is_prime(p) {
        return None;
    }
    let n = mat.len();
    let m = p as u128;
    let mut a: Vec<Vec<u64>> = mat
        .iter()
        .map(|row| row.iter().map(|&v| v % p).collect())
        .collect();
    let mut det = 1u128;
    for col in 0..n {
        let piv = (col..n).find(|&r| a[r][col] != 0);
        let Some(piv_row) = piv else {
            return Some(0);
        };
        if piv_row != col {
            a.swap(col, piv_row);
            det = (m - det) % m;
        }
        let diag = a[col][col];
        det = (det * diag as u128) % m;
        let inv = mod_inv_prime(diag, p)? as u128;
        for r in (col + 1)..n {
            if a[r][col] != 0 {
                let factor = (a[r][col] as u128 * inv) % m;
                let piv_vals: Vec<u64> = a[col][col..n].to_vec();
                for (offset, &pv) in piv_vals.iter().enumerate() {
                    let sub = (factor * pv as u128) % m;
                    let cur = a[r][col + offset] as u128;
                    a[r][col + offset] = ((cur + m - sub) % m) as u64;
                }
            }
        }
    }
    Some(det as u64)
}

/// Exact integer determinant of `B = I_12 + C^4 + C^9` via Bareiss algorithm (`45`).
pub fn g_plr_exact_det_bareiss() -> i64 {
    let mut a: Vec<Vec<i128>> = g_plr_biadjacency_matrix()
        .into_iter()
        .map(|row| row.into_iter().map(i128::from).collect())
        .collect();
    let n = a.len();
    let mut sign = 1i128;
    let mut prev_piv = 1i128;
    for k in 0..n {
        let piv = (k..n).find(|&r| a[r][k] != 0);
        let Some(piv_row) = piv else {
            return 0;
        };
        if piv_row != k {
            a.swap(k, piv_row);
            sign = -sign;
        }
        let pk = a[k][k];
        for i in (k + 1)..n {
            for j in (k + 1)..n {
                a[i][j] = (a[i][j] * pk - a[i][k] * a[k][j]) / prev_piv;
            }
            a[i][k] = 0;
        }
        prev_piv = pk;
    }
    (sign * a[n - 1][n - 1]) as i64
}

/// Randomized Schwartz-Zippel Edmonds PIT on `G_PLR` over `F_p` (`k` trials, error <= `(12/p)^k`).
pub fn edmonds_pit_g_plr(p: u64, trials: usize, seed: u64) -> Option<bool> {
    if !is_prime(p) || trials == 0 {
        return None;
    }
    let mut rng = SplitMix64::new(seed);
    for _ in 0..trials {
        let mut mat = vec![vec![0u64; 12]; 12];
        for (r, row) in mat.iter_mut().enumerate() {
            for sh in [0usize, 4, 9] {
                row[(r + sh) % 12] = rng.next_mod(p);
            }
        }
        if det_mod_prime(&mat, p)? != 0 {
            return Some(true);
        }
    }
    Some(false)
}

/// Evaluates factored Bass-Ihara polynomial `D(u)` mod prime `p`.
pub fn bass_ihara_d_factored_mod_p(u: u64, p: u64) -> u64 {
    let m = p as u128;
    let u2 = (u as u128 * u as u128) % m;
    let u4 = (u2 * u2) % m;
    let u6 = (u4 * u2) % m;
    let u8 = (u4 * u4) % m;

    let f1 = (1 + m - u2) % m;
    let f2 = (1 + m - (4 * u2) % m) % m;
    let f3 = (1 + m - u2 + (4 * u4) % m) % m;
    let f4 = (1 + u2 + (4 * u4) % m) % m;
    let f5 = (1 + (3 * u2) % m + (4 * u4) % m) % m;
    let f6 = (1 + (4 * u2) % m + (9 * u4) % m + (16 * u6) % m + (16 * u8) % m) % m;

    let mut acc = (f1 * f2) % m;
    acc = (acc * ((f3 * f3) % m)) % m;
    acc = (acc * ((f4 * f4) % m)) % m;
    acc = (acc * (((f5 * f5) % m * f5) % m)) % m;
    acc = (acc * ((f6 * f6) % m)) % m;
    acc as u64
}

/// Evaluates full 24x24 `det(I_24 - u*A + 2*u^2*I_24) mod p` directly for PIT comparison.
pub fn bass_ihara_d_matrix_mod_p(u: u64, p: u64) -> Option<u64> {
    if !is_prime(p) {
        return None;
    }
    let m = p as u128;
    let diag = ((1 + 2 * ((u as u128 * u as u128) % m)) % m) as u64;
    let neg_u = if u.is_multiple_of(p) { 0 } else { p - (u % p) };
    let mut mat = vec![vec![0u64; 24]; 24];
    for (i, row) in mat.iter_mut().enumerate() {
        row[i] = diag;
    }
    for r in 0..12usize {
        for sh in [0usize, 4, 9] {
            let c = 12 + ((r + sh) % 12);
            mat[r][c] = neg_u;
            mat[c][r] = neg_u;
        }
    }
    det_mod_prime(&mat, p)
}

/// Exact Hasse-derivative multiplicity sum for `f(x, y) = (x - y)^2 * (x + y)` over `F_5^2`.
pub fn hasse_multiplicity_sum_f5() -> (usize, usize) {
    let p = 5i64;
    let mut distinct_roots = 0usize;
    let mut total_mult = 0usize;
    for a in 0..p {
        for b in 0..p {
            // Expand ((a-b) + u - v)^2 * ((a+b) + u + v) in F_5[u, v]
            let c1 = (a - b).rem_euclid(p);
            let c2 = (a + b).rem_euclid(p);
            let t1 = [((0, 0), c1), ((1, 0), 1), ((0, 1), p - 1)];
            let t2 = [((0, 0), c2), ((1, 0), 1), ((0, 1), 1)];
            let sq = poly2_mul(&t1, &t1, p);
            let prod = poly2_mul(&sq, &t2, p);
            let mult = prod
                .iter()
                .filter(|&&(_, coeff)| coeff != 0)
                .map(|&((i, j), _)| i + j)
                .min()
                .unwrap_or(99);
            if mult >= 1 {
                distinct_roots += 1;
            }
            total_mult += mult;
        }
    }
    (distinct_roots, total_mult)
}

fn poly2_mul(a: &[((usize, usize), i64)], b: &[((usize, usize), i64)], p: i64) -> Vec<((usize, usize), i64)> {
    let mut map: BTreeMap<(usize, usize), i64> = BTreeMap::new();
    for &((i1, j1), c1) in a {
        for &((i2, j2), c2) in b {
            let entry = map.entry((i1 + i2, j1 + j2)).or_insert(0);
            *entry = (*entry + c1 * c2).rem_euclid(p);
        }
    }
    map.into_iter().filter(|&(_, c)| c != 0).collect()
}

/// Checks whether a grid subset in `Z/mZ` satisfies Condition (D) with no duplicates.
pub fn satisfies_condition_d(m: u64, grid: &[u64]) -> bool {
    if m < 2 || grid.is_empty() {
        return false;
    }
    for i in 0..grid.len() {
        for j in (i + 1)..grid.len() {
            let a = grid[i] % m;
            let b = grid[j] % m;
            if a == b {
                return false;
            }
            let diff = a.abs_diff(b);
            if gcd_u64(diff, m) != 1 {
                return false;
            }
        }
    }
    true
}

/// Fail-closed atomic guard: modulus must be prime for classical SZ PIT.
pub fn guard_prime_integral_domain(m: u64) -> GuardVerdict {
    if is_prime(m) {
        GuardVerdict::from_violations(
            "sz_prime_integral_domain",
            0,
            format!("m={} is prime (integral domain)", m),
        )
    } else {
        GuardVerdict::from_violations(
            "sz_prime_integral_domain",
            1,
            format!(
                "m={} is composite (zero divisors, p_min={})",
                m,
                smallest_prime_factor(m)
            ),
        )
    }
}

/// Fail-closed atomic guard: total degree must stay strictly below safe grid size.
pub fn guard_nonvacuous_degree(global_degree: usize, safe_grid_size: usize) -> GuardVerdict {
    if global_degree < safe_grid_size {
        GuardVerdict::from_violations(
            "sz_nonvacuous_degree_boundary",
            0,
            format!("D={} < |S|={} (non-vacuous SZ regime)", global_degree, safe_grid_size),
        )
    } else {
        GuardVerdict::from_violations(
            "sz_nonvacuous_degree_boundary",
            global_degree - safe_grid_size + 1,
            format!("D={} >= |S|={} (ODLSZ vacuous stall boundary reached)", global_degree, safe_grid_size),
        )
    }
}

/// Fail-closed atomic guard: Condition (D) grid compliance over `Z/mZ`.
pub fn guard_condition_d_grid(m: u64, grid: &[u64]) -> GuardVerdict {
    if satisfies_condition_d(m, grid) {
        GuardVerdict::from_violations(
            "sz_condition_d_grid",
            0,
            format!("grid of size {} satisfies Condition (D) mod {}", grid.len(), m),
        )
    } else {
        GuardVerdict::from_violations(
            "sz_condition_d_grid",
            1,
            format!("grid violates Condition (D) mod {}", m),
        )
    }
}

/// Fail-closed atomic guard: Ramanujan non-backtracking mixing must hold (`max lambda^2 < 8`) and conserve probability mass.
pub fn guard_ramanujan_nb_mixing(rep: &MixingReport) -> GuardVerdict {
    let ok = rep.mass_conserved
        && rep.max_nontrivial_lambda_sq.is_finite()
        && rep.satisfies_graph_rh
        && rep.nb_ihara_nontrivial_rate.is_finite()
        && rep.srw_nontrivial_rate.is_finite()
        && rep.nb_ihara_nontrivial_rate < rep.srw_nontrivial_rate;
    GuardVerdict::from_violations(
        "coupled_ramanujan_nb_mixing",
        usize::from(!ok),
        format!(
            "{}-TET: max_lambda^2={:.5}, NB={:.5}, SRW={:.5}, TV20_NB={:.6}, mass_conserved={}",
            rep.n_tet,
            rep.max_nontrivial_lambda_sq,
            rep.nb_ihara_nontrivial_rate,
            rep.srw_nontrivial_rate,
            rep.tv_step_20_nb,
            rep.mass_conserved
        ),
    )
}

/// Evaluates all atomic fail-closed guards across both primary data vaults dynamically.
pub fn verify_coupled_vaults(sz_raw: &str, rl_raw: &str) -> Vec<GuardVerdict> {
    let mut verdicts = Vec::new();

    // 1. Provenance & zero-wiki guard
    let sz_lc = sz_raw.to_lowercase();
    let rl_lc = rl_raw.to_lowercase();
    let prov_ok = sz_raw.contains("\"tradition_id\": \"PIT-SZ\"")
        && sz_raw.contains("\"anti_conflation_guard\"")
        && rl_raw.contains("\"tradition_id\": \"RIEM-LATTICE\"")
        && !sz_lc.contains("wikipedia.org")
        && !sz_lc.contains("wikisource.org")
        && !rl_lc.contains("wikipedia.org")
        && !rl_lc.contains("wikisource.org");
    verdicts.push(GuardVerdict::from_violations(
        "vault_tradition_and_provenance",
        usize::from(!prov_ok),
        "PIT-SZ + RIEM-LATTICE disjoint traditions, zero wiki URLs".to_string(),
    ));

    // 2. 12-fold cyclotomic torus & bilinear degree-2 involutions across all 6 vault primes
    let primes = [
        (13u64, 2u64),
        (37, 8),
        (61, 32),
        (97, 6),
        (65521, 53059),
        (1_000_000_009, 655_997_907),
    ];
    let mut torus_violations = 0usize;
    for (p, z) in primes {
        let ok = CyclotomicPlrTorus::new(p, z)
            .map(|t| t.verify_all_24_triads())
            .unwrap_or(false)
            && sz_raw.contains(&format!("\"zeta_12\": {}", z));
        if !ok {
            torus_violations += 1;
        }
    }
    verdicts.push(GuardVerdict::from_violations(
        "coupled_cyclotomic_torus_bilinear",
        torus_violations,
        "verified 6 cyclotomic primes p=1 mod 12 with exact degree-2 P,L,R involutions".to_string(),
    ));

    // 3. Non-abelian holonomy verification (rho_1..rho_5 + PL != LP separation)
    let expected_irrep = [(1u64, 24usize, 1usize), (2, 12, 2), (3, 8, 3), (4, 6, 4), (5, 24, 1)];
    let mut hol_violations = 0usize;
    for (k, exp_im, exp_ker) in expected_irrep {
        let (im, ker) = rho_image_and_kernel(65521, 53059, k);
        if im != exp_im || ker != exp_ker {
            hol_violations += 1;
        }
    }
    let abel_eq = rho_word(65521, 53059, 0, &[PlrOp::P, PlrOp::L])
        == rho_word(65521, 53059, 0, &[PlrOp::L, PlrOp::P]);
    let faith_neq = rho_word(65521, 53059, 1, &[PlrOp::P, PlrOp::L])
        != rho_word(65521, 53059, 1, &[PlrOp::L, PlrOp::P]);
    if !abel_eq || !faith_neq || !sz_raw.contains("\"distinct_matrices\": 24, \"kernel_size\": 1, \"faithful\": true") {
        hol_violations += 1;
    }
    verdicts.push(GuardVerdict::from_violations(
        "coupled_nonabelian_holonomy_rho_k",
        hol_violations,
        "rho_1/rho_5 faithful (24/24); separates PL vs LP where abelianization fails".to_string(),
    ));

    // 4. Non-backtracking Ihara/Hashimoto Ramanujan mixing (12-TET vs 17-TET boundary)
    let mix12 = analyze_ntet_mixing(12, 4, 3, 20);
    let mix17 = analyze_ntet_mixing(17, 5, 5, 20);
    let mix_ok = mix12.satisfies_graph_rh
        && !mix17.satisfies_graph_rh
        && mix12.directed_edges == 72
        && mix12.nb_ihara_nontrivial_rate < mix12.srw_nontrivial_rate
        && mix12.tv_step_20_nb < mix12.tv_step_20_srw
        && mix12.tv_step_20_nb * 20.0 < mix17.tv_step_20_nb
        && sz_raw.contains("\"directed_edges_12tet\": 72");
    verdicts.push(GuardVerdict::from_violations(
        "coupled_ihara_nb_mixing_vs_17tet",
        usize::from(!mix_ok),
        format!(
            "12-TET NB={:.5} (TV20={:.6}) vs 17-TET NB={:.5} (TV20={:.6})",
            mix12.nb_ihara_nontrivial_rate,
            mix12.tv_step_20_nb,
            mix17.nb_ihara_nontrivial_rate,
            mix17.tv_step_20_nb
        ),
    ));

    // 5. Representation/homology-filtered cycle sieving at length 6 + twisted PIT
    let sieve = sieve_len6_cycles_g_plr();
    let twist_ok = twisted_len6_character_pit(65521, 7, 11)
        .map(|val| val != 144)
        .unwrap_or(false);
    let sieve_ok = sieve.total_walks == 192
        && sieve.contractible_walks == 144
        && sieve.non_contractible_walks == 48
        && sieve.unoriented_lprlpr_faces == 12
        && sieve.unoriented_lplplp_hexatonic == 4
        && twist_ok
        && sz_raw.contains("\"contractible_walks\": 144")
        && sz_raw.contains("\"non_contractible_walks\": 48")
        && rl_raw.contains("\"LPRLPR_pitch_class_dual_faces\": 12")
        && rl_raw.contains("\"LPLPLP_hexatonic_cycles\": 4");
    verdicts.push(GuardVerdict::from_violations(
        "coupled_cycle_sieve_len6_cross_vault",
        usize::from(!sieve_ok),
        "192 NB walks = 144 contractible (12 LPRLPR) + 48 non-contractible (4 LPLPLP)".to_string(),
    ));

    // 6. Low-entropy Ramanujan walk PIT & sharp degree boundary (`z^12 - 1` stall at D=12)
    let torus65521 = CyclotomicPlrTorus::new(65521, 53059).expect("65521 torus valid");
    let walk_pts = ramanujan_nb_walk_torus(&torus65521, 16, 0x51A7_C0DE_2026);
    // Nonzero degree-11 polynomial z^11 - 1 must hit nonzero on torus; degree-12 z^12 - 1 stalls!
    let mut deg11 = vec![0u64; 12];
    deg11[0] = 65520;
    deg11[11] = 1;
    let mut deg12 = vec![0u64; 13];
    deg12[0] = 65520;
    deg12[12] = 1;
    let hit_deg11 = walk_pts.iter().any(|&(z, _)| eval_uni_mod(&deg11, z, 65521) != 0);
    let stall_deg12 = walk_pts.iter().all(|&(z, _)| eval_uni_mod(&deg12, z, 65521) == 0);
    let low_ent_ok = hit_deg11 && stall_deg12 && sz_raw.contains("\"vanishing_witness\": \"z^12 - 1\"");
    verdicts.push(GuardVerdict::from_violations(
        "coupled_low_entropy_pit_and_degree_wall",
        usize::from(!low_ent_ok),
        "Ramanujan NB walk detects deg-11 nonzero and confirms exact stall at D=12 (z^12 - 1)".to_string(),
    ));

    // 7. Direct G_PLR bridge: det(B)=45, det(B)^2=2025, perm(B)=113, Edmonds PIT & Bass-Ihara PIT
    let det_b = g_plr_exact_det_bareiss();
    let perm_b = g_plr_exact_perm();
    let edmonds_ok = edmonds_pit_g_plr(65521, 4, 202601).unwrap_or(false)
        && edmonds_pit_g_plr(1_000_000_009, 4, 202602).unwrap_or(false);
    let bass_ihara_pit_ok = [7u64, 19, 1003, 40999].iter().all(|&u| {
        bass_ihara_d_matrix_mod_p(u, 65521) == Some(bass_ihara_d_factored_mod_p(u, 65521))
    });
    let bridge_ok = det_b == 45
        && det_b * det_b == 2025
        && perm_b == 113
        && det_b % 3 == 0
        && det_b % 5 == 0
        && edmonds_ok
        && bass_ihara_pit_ok
        && sz_raw.contains("\"exact_det_B\": 45")
        && sz_raw.contains("\"exact_perm_B_perfect_matchings\": 113")
        && rl_raw.contains("2025]");
    verdicts.push(GuardVerdict::from_violations(
        "g_plr_edmonds_and_bass_ihara_pit_bridge",
        usize::from(!bridge_ok),
        "det(B)=45 (2025), perm(B)=113, Edmonds & Bass-Ihara PIT matched mod 65521".to_string(),
    ));

    // 8. Correspondence Principle regimes: TF-01..TF-05, Hasse multiplicity, Z/mZ breakdown & Condition (D)
    let (distinct_r, hasse_sum) = hasse_multiplicity_sum_f5();
    let z6_roots = (0..6u64).filter(|&x| (x * (x + 5)) % 6 == 0).count();
    let z30_roots = (0..30u64).filter(|&x| (x * (x + 29)) % 30 == 0).count();
    let z6_3x_full = (0..6u64)
        .flat_map(|x| (0..6u64).map(move |y| (x, y)))
        .filter(|&(x, _)| (3 * x) % 6 == 0)
        .count();
    let z6_3x_cond_d = [0u64, 1]
        .iter()
        .flat_map(|&x| [0u64, 1].iter().map(move |&y| (x, y)))
        .filter(|&(x, _)| (3 * x) % 6 == 0)
        .count();
    let regime_ok = distinct_r == 9
        && hasse_sum == 15
        && z6_roots == 4
        && z30_roots == 8
        && z6_3x_full == 18
        && z6_3x_cond_d == 2
        && satisfies_condition_d(6, &[0, 1])
        && !satisfies_condition_d(6, &[0, 1, 3, 4])
        && smallest_prime_factor(12) == 2
        && sz_raw.contains("\"sum_of_hasse_multiplicities\": 15")
        && sz_raw.contains("\"actual_zero_ratio\": \"2/3\"");
    verdicts.push(GuardVerdict::from_violations(
        "correspondence_regime_bounds_tf01_to_tf05",
        usize::from(!regime_ok),
        "DKSS Hasse sum=15/15; Z/6Z (4/6) & Z/30Z (8/30) breakdown; Condition (D) repair verified".to_string(),
    ));

    // 9. Freivalds O(n^2) matrix product check on G_PLR Gram matrix B * B^T mod 65521
    let b_u64: Vec<Vec<u64>> = g_plr_biadjacency_matrix()
        .into_iter()
        .map(|row| row.into_iter().map(|v| v as u64).collect())
        .collect();
    let mut bt_u64 = vec![vec![0u64; 12]; 12];
    for i in 0..12 {
        for j in 0..12 {
            bt_u64[j][i] = b_u64[i][j];
        }
    }
    let mut gram = vec![vec![0u64; 12]; 12];
    for i in 0..12 {
        for j in 0..12 {
            let mut s = 0u64;
            for k in 0..12 {
                s = (s + b_u64[i][k] * bt_u64[k][j]) % 65521;
            }
            gram[i][j] = s;
        }
    }
    let freivalds_ok = freivalds_verify_mod_p(&b_u64, &bt_u64, &gram, 65521, 8, 99123).unwrap_or(false);
    verdicts.push(GuardVerdict::from_violations(
        "freivalds_g_plr_gram_verification",
        usize::from(!freivalds_ok),
        "Freivalds O(n^2) verification passed for G_PLR Gram matrix B * B^T mod 65521".to_string(),
    ));

    verdicts
}
