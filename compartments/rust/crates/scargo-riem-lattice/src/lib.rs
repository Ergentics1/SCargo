// Copyright (c) 2026 Ergentics, LLC
// Licensed under the MIT License. See LICENSE in the project root.

//! Zero-dependency exact Z/Q machine layer for the Import-Style Riemann Lattice (`RIEM-LATTICE`).
//!
//! Strict Anti-Conflation Note:
//! This module (`riem_lattice`) computes and verifies finite-graph Ihara zeta functions,
//! Ramanujan spectral bounds, and Euler-1730s-rooted Neo-Riemannian Tonnetz dual invariants.
//! It is strictly separate from `RIEM-A` (classical analytic RH for zeta(s)).

#![forbid(unsafe_code)]

use std::cmp::Ordering;
use std::collections::BTreeSet;
use std::f64::consts::PI;

pub mod riem_lattice {
    use super::{BTreeSet, Ordering, PI};

    /// Atomic fail-closed verification verdict for one independent compartment check.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct GuardVerdict {
        pub compartment: String,
        pub passed: bool,
        pub violation_count: usize,
        pub detail: String,
    }

    impl GuardVerdict {
        pub fn pass(compartment: impl Into<String>, detail: impl Into<String>) -> Self {
            Self {
                compartment: compartment.into(),
                passed: true,
                violation_count: 0,
                detail: detail.into(),
            }
        }

        pub fn fail(
            compartment: impl Into<String>,
            violation_count: usize,
            detail: impl Into<String>,
        ) -> Self {
            Self {
                compartment: compartment.into(),
                passed: false,
                violation_count: violation_count.max(1),
                detail: detail.into(),
            }
        }
    }

    pub fn failed_compartments(verdicts: &[GuardVerdict]) -> Vec<String> {
        verdicts
            .iter()
            .filter(|v| !v.passed)
            .map(|v| v.compartment.clone())
            .collect()
    }

    pub fn all_guards_hold(verdicts: &[GuardVerdict]) -> bool {
        verdicts.iter().all(|v| v.passed)
    }

    // -------------------------------------------------------------------------
    // Exact Arbitrary-Precision Integer (BigInt) & Rational (BigRat) over Z/Q
    // -------------------------------------------------------------------------

    const BASE: u64 = 1_000_000_000;

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct BigInt {
        neg: bool,
        /// Little-endian base-10^9 limbs; empty means 0 (and neg is always false when empty).
        limbs: Vec<u32>,
    }

    impl BigInt {
        pub fn zero() -> Self {
            Self {
                neg: false,
                limbs: Vec::new(),
            }
        }

        pub fn one() -> Self {
            Self {
                neg: false,
                limbs: vec![1],
            }
        }

        pub fn from_i64(v: i64) -> Self {
            if v == 0 {
                return Self::zero();
            }
            let neg = v < 0;
            let mut mag = v.unsigned_abs();
            let mut limbs = Vec::new();
            while mag > 0 {
                limbs.push((mag % BASE) as u32);
                mag /= BASE;
            }
            Self { neg, limbs }
        }

        pub fn is_zero(&self) -> bool {
            self.limbs.is_empty()
        }

        pub fn is_neg(&self) -> bool {
            self.neg && !self.limbs.is_empty()
        }

        pub fn abs(&self) -> Self {
            Self {
                neg: false,
                limbs: self.limbs.clone(),
            }
        }

        pub fn neg_val(&self) -> Self {
            if self.is_zero() {
                Self::zero()
            } else {
                Self {
                    neg: !self.neg,
                    limbs: self.limbs.clone(),
                }
            }
        }

        fn normalize(&mut self) {
            while matches!(self.limbs.last(), Some(&0)) {
                self.limbs.pop();
            }
            if self.limbs.is_empty() {
                self.neg = false;
            }
        }

        fn cmp_mag(a: &[u32], b: &[u32]) -> Ordering {
            if a.len() != b.len() {
                return a.len().cmp(&b.len());
            }
            for (&x, &y) in a.iter().rev().zip(b.iter().rev()) {
                if x != y {
                    return x.cmp(&y);
                }
            }
            Ordering::Equal
        }

        fn add_mag(a: &[u32], b: &[u32]) -> Vec<u32> {
            let n = a.len().max(b.len());
            let mut out = Vec::with_capacity(n + 1);
            let mut carry: u64 = 0;
            for i in 0..n {
                let av = *a.get(i).unwrap_or(&0) as u64;
                let bv = *b.get(i).unwrap_or(&0) as u64;
                let s = av + bv + carry;
                out.push((s % BASE) as u32);
                carry = s / BASE;
            }
            if carry > 0 {
                out.push(carry as u32);
            }
            out
        }

        /// Assumes |a| >= |b|.
        fn sub_mag(a: &[u32], b: &[u32]) -> Vec<u32> {
            let mut out = Vec::with_capacity(a.len());
            let mut borrow: i64 = 0;
            for (i, &a_limb) in a.iter().enumerate() {
                let av = a_limb as i64;
                let bv = *b.get(i).unwrap_or(&0) as i64;
                let mut diff = av - bv - borrow;
                if diff < 0 {
                    diff += BASE as i64;
                    borrow = 1;
                } else {
                    borrow = 0;
                }
                out.push(diff as u32);
            }
            while matches!(out.last(), Some(&0)) {
                out.pop();
            }
            out
        }

        pub fn add(&self, other: &Self) -> Self {
            if self.neg == other.neg {
                let mut r = Self {
                    neg: self.neg,
                    limbs: Self::add_mag(&self.limbs, &other.limbs),
                };
                r.normalize();
                r
            } else {
                match Self::cmp_mag(&self.limbs, &other.limbs) {
                    Ordering::Equal => Self::zero(),
                    Ordering::Greater => {
                        let mut r = Self {
                            neg: self.neg,
                            limbs: Self::sub_mag(&self.limbs, &other.limbs),
                        };
                        r.normalize();
                        r
                    }
                    Ordering::Less => {
                        let mut r = Self {
                            neg: other.neg,
                            limbs: Self::sub_mag(&other.limbs, &self.limbs),
                        };
                        r.normalize();
                        r
                    }
                }
            }
        }

        pub fn sub(&self, other: &Self) -> Self {
            self.add(&other.neg_val())
        }

        pub fn mul(&self, other: &Self) -> Self {
            if self.is_zero() || other.is_zero() {
                return Self::zero();
            }
            let mut out = vec![0u32; self.limbs.len() + other.limbs.len()];
            for (i, &a) in self.limbs.iter().enumerate() {
                let mut carry: u64 = 0;
                for (j, &b) in other.limbs.iter().enumerate() {
                    let prod = (a as u64) * (b as u64) + (out[i + j] as u64) + carry;
                    out[i + j] = (prod % BASE) as u32;
                    carry = prod / BASE;
                }
                if carry > 0 {
                    out[i + other.limbs.len()] =
                        ((out[i + other.limbs.len()] as u64) + carry) as u32;
                }
            }
            let mut r = Self {
                neg: self.neg ^ other.neg,
                limbs: out,
            };
            r.normalize();
            r
        }

        pub fn pow_u32(&self, mut exp: u32) -> Self {
            let mut base = self.clone();
            let mut acc = Self::one();
            while exp > 0 {
                if exp & 1 == 1 {
                    acc = acc.mul(&base);
                }
                exp >>= 1;
                if exp > 0 {
                    base = base.mul(&base);
                }
            }
            acc
        }

        /// Divides non-negative `self` by non-negative `divisor > 0`, returning `(quot, rem)`.
        fn div_rem_mag(a: &[u32], b: &[u32]) -> (Vec<u32>, Vec<u32>) {
            assert!(!b.is_empty(), "division by zero");
            if Self::cmp_mag(a, b) == Ordering::Less {
                return (Vec::new(), a.to_vec());
            }
            if b.len() == 1 {
                let d = b[0] as u64;
                let mut q = vec![0u32; a.len()];
                let mut rem: u64 = 0;
                for i in (0..a.len()).rev() {
                    let cur = rem * BASE + (a[i] as u64);
                    q[i] = (cur / d) as u32;
                    rem = cur % d;
                }
                while matches!(q.last(), Some(&0)) {
                    q.pop();
                }
                let r = if rem == 0 {
                    Vec::new()
                } else {
                    vec![rem as u32]
                };
                return (q, r);
            }
            // Binary long division on magnitudes (simple, exact, zero edge-case bugs).
            let mut rem = Self::zero();
            let mut quot = Self::zero();
            let b_big = Self {
                neg: false,
                limbs: b.to_vec(),
            };
            let base_big = Self::from_i64(BASE as i64);
            for &limb in a.iter().rev() {
                // Shift rem and quot by BASE via binary search over 0..BASE-1 for digit
                rem = rem.mul(&base_big).add(&Self::from_i64(limb as i64));
                let mut lo: u64 = 0;
                let mut hi: u64 = BASE - 1;
                let mut best: u64 = 0;
                while lo <= hi {
                    let mid = lo + (hi - lo) / 2;
                    let trial = b_big.mul(&Self::from_i64(mid as i64));
                    if Self::cmp_mag(&trial.limbs, &rem.limbs) != Ordering::Greater {
                        best = mid;
                        lo = mid + 1;
                    } else if mid == 0 {
                        break;
                    } else {
                        hi = mid - 1;
                    }
                }
                if best > 0 {
                    let sub = b_big.mul(&Self::from_i64(best as i64));
                    rem = rem.sub(&sub);
                }
                quot = quot.mul(&base_big).add(&Self::from_i64(best as i64));
            }
            (quot.limbs, rem.limbs)
        }

        pub fn div_exact(&self, other: &Self) -> Option<Self> {
            if other.is_zero() {
                return None;
            }
            if self.is_zero() {
                return Some(Self::zero());
            }
            let (q, r) = Self::div_rem_mag(&self.limbs, &other.limbs);
            if !r.is_empty() {
                return None;
            }
            let mut res = Self {
                neg: self.neg ^ other.neg,
                limbs: q,
            };
            res.normalize();
            Some(res)
        }

        pub fn gcd(a: &Self, b: &Self) -> Self {
            let mut x = a.abs();
            let mut y = b.abs();
            while !y.is_zero() {
                let (_, rem) = Self::div_rem_mag(&x.limbs, &y.limbs);
                x = y;
                y = Self {
                    neg: false,
                    limbs: rem,
                };
            }
            x
        }

        pub fn to_i64_checked(&self) -> Option<i64> {
            if self.is_zero() {
                return Some(0);
            }
            let mut val: i128 = 0;
            for &limb in self.limbs.iter().rev() {
                val = val.checked_mul(BASE as i128)?.checked_add(limb as i128)?;
            }
            if self.neg {
                val = -val;
            }
            i64::try_from(val).ok()
        }
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct BigRat {
        num: BigInt,
        den: BigInt, // strictly > 0
    }

    impl BigRat {
        pub fn new(num: BigInt, den: BigInt) -> Self {
            assert!(!den.is_zero(), "zero denominator");
            if num.is_zero() {
                return Self {
                    num: BigInt::zero(),
                    den: BigInt::one(),
                };
            }
            let (n, d) = if den.is_neg() {
                (num.neg_val(), den.neg_val())
            } else {
                (num, den)
            };
            let g = BigInt::gcd(&n, &d);
            Self {
                num: n.div_exact(&g).expect("gcd divides numerator"),
                den: d.div_exact(&g).expect("gcd divides denominator"),
            }
        }

        pub fn from_frac(n: i64, d: i64) -> Self {
            Self::new(BigInt::from_i64(n), BigInt::from_i64(d))
        }

        pub fn zero() -> Self {
            Self::from_frac(0, 1)
        }

        pub fn one() -> Self {
            Self::from_frac(1, 1)
        }

        pub fn is_zero(&self) -> bool {
            self.num.is_zero()
        }

        pub fn neg_val(&self) -> Self {
            Self {
                num: self.num.neg_val(),
                den: self.den.clone(),
            }
        }

        pub fn add(&self, other: &Self) -> Self {
            let num = self.num.mul(&other.den).add(&other.num.mul(&self.den));
            let den = self.den.mul(&other.den);
            Self::new(num, den)
        }

        pub fn sub(&self, other: &Self) -> Self {
            self.add(&other.neg_val())
        }

        pub fn mul(&self, other: &Self) -> Self {
            Self::new(self.num.mul(&other.num), self.den.mul(&other.den))
        }

        pub fn div(&self, other: &Self) -> Self {
            assert!(!other.is_zero(), "rational division by zero");
            Self::new(self.num.mul(&other.den), self.den.mul(&other.num))
        }

        pub fn pow_u32(&self, exp: u32) -> Self {
            Self {
                num: self.num.pow_u32(exp),
                den: self.den.pow_u32(exp),
            }
        }
    }

    // -------------------------------------------------------------------------
    // Dual Klang, N-TET Neo-Riemannian Operators, & Tonnetz Dual G_PLR
    // -------------------------------------------------------------------------

    #[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub enum Polarity {
        Major,
        Minor,
    }

    impl Polarity {
        pub fn flip(self) -> Self {
            match self {
                Self::Major => Self::Minor,
                Self::Minor => Self::Major,
            }
        }
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub struct Triad {
        pub root: usize,
        pub polarity: Polarity,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum PlrOp {
        P,
        L,
        R,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct NTetSystem {
        pub n: usize,
        pub p5: usize,
        pub m3: usize,
    }

    impl NTetSystem {
        pub fn canonical_12tet() -> Self {
            Self {
                n: 12,
                p5: 7,
                m3: 4,
            }
        }

        pub fn from_n(n: usize) -> Self {
            let p5 = ((n as f64) * (1.5_f64).log2()).round() as usize;
            let m3 = ((n as f64) * (1.25_f64).log2()).round() as usize;
            Self { n, p5, m3 }
        }

        pub fn minor_third(&self) -> usize {
            self.p5 - self.m3
        }

        pub fn apply_plr(&self, op: PlrOp, t: Triad) -> Triad {
            let m3_min = self.minor_third();
            match (op, t.polarity) {
                (PlrOp::P, p) => Triad {
                    root: t.root,
                    polarity: p.flip(),
                },
                (PlrOp::L, Polarity::Major) => Triad {
                    root: (t.root + self.m3) % self.n,
                    polarity: Polarity::Minor,
                },
                (PlrOp::L, Polarity::Minor) => Triad {
                    root: (t.root + self.n - (self.m3 % self.n)) % self.n,
                    polarity: Polarity::Major,
                },
                (PlrOp::R, Polarity::Major) => Triad {
                    root: (t.root + self.n - (m3_min % self.n)) % self.n,
                    polarity: Polarity::Minor,
                },
                (PlrOp::R, Polarity::Minor) => Triad {
                    root: (t.root + m3_min) % self.n,
                    polarity: Polarity::Major,
                },
            }
        }

        pub fn apply_t(&self, shift: usize, t: Triad) -> Triad {
            Triad {
                root: (t.root + shift) % self.n,
                polarity: t.polarity,
            }
        }

        pub fn apply_i(&self, axis: usize, t: Triad) -> Triad {
            Triad {
                root: (axis + self.n - (t.root % self.n) + self.n - (self.p5 % self.n)) % self.n,
                polarity: t.polarity.flip(),
            }
        }

        pub fn pitch_classes(&self, t: Triad) -> [usize; 3] {
            match t.polarity {
                Polarity::Major => [t.root, (t.root + self.m3) % self.n, (t.root + self.p5) % self.n],
                Polarity::Minor => [
                    t.root,
                    (t.root + self.minor_third()) % self.n,
                    (t.root + self.p5) % self.n,
                ],
            }
        }

        pub fn shared_pitch_classes(&self, a: Triad, b: Triad) -> usize {
            let pa = self.pitch_classes(a);
            let pb = self.pitch_classes(b);
            pa.iter().filter(|x| pb.contains(x)).count()
        }

        pub fn all_triads(&self) -> Vec<Triad> {
            let mut out = Vec::with_capacity(2 * self.n);
            for r in 0..self.n {
                out.push(Triad {
                    root: r,
                    polarity: Polarity::Major,
                });
            }
            for r in 0..self.n {
                out.push(Triad {
                    root: r,
                    polarity: Polarity::Minor,
                });
            }
            out
        }

        pub fn is_connected(&self) -> bool {
            gcd_usize(self.m3, gcd_usize(self.p5, self.n)) == 1
        }

        /// Exhaustively verifies mutual centralizer commutation (`T_n` and `I_n` commute with `P, L, R`)
        /// plus involutivity across all `2N` triads (universal for every N-TET). Returns violation count.
        pub fn mutual_centralizer_violations(&self) -> usize {
            let mut violations = 0usize;
            let ops = [PlrOp::P, PlrOp::L, PlrOp::R];
            for t in self.all_triads() {
                for &op in &ops {
                    if self.apply_plr(op, self.apply_plr(op, t)) != t {
                        violations += 1;
                    }
                    for k in 0..self.n {
                        if self.apply_plr(op, self.apply_t(k, t))
                            != self.apply_t(k, self.apply_plr(op, t))
                        {
                            violations += 1;
                        }
                        if self.apply_plr(op, self.apply_i(k, t))
                            != self.apply_i(k, self.apply_plr(op, t))
                        {
                            violations += 1;
                        }
                    }
                }
            }
            violations
        }

        /// Counts triads/operators failing strict 2-of-3 shared pitch-class parsimony
        /// (holds for non-degenerate temperaments where `M3 + P5 != 0 mod N`, e.g. 12-TET).
        pub fn parsimony_violations(&self) -> usize {
            let mut violations = 0usize;
            for t in self.all_triads() {
                for op in [PlrOp::P, PlrOp::L, PlrOp::R] {
                    if self.shared_pitch_classes(t, self.apply_plr(op, t)) != 2 {
                        violations += 1;
                    }
                }
            }
            violations
        }

        /// `N x N` biadjacency block `B` (`major i -> minor j`).
        pub fn biadjacency_matrix(&self) -> Vec<Vec<i64>> {
            let mut b = vec![vec![0i64; self.n]; self.n];
            for (i, row) in b.iter_mut().enumerate() {
                let maj = Triad {
                    root: i,
                    polarity: Polarity::Major,
                };
                for op in [PlrOp::P, PlrOp::L, PlrOp::R] {
                    let nb = self.apply_plr(op, maj);
                    debug_assert_eq!(nb.polarity, Polarity::Minor);
                    row[nb.root] = 1;
                }
            }
            b
        }

        /// Full `2N x 2N` bipartite adjacency matrix `A = [[0, B], [B^T, 0]]`.
        pub fn adjacency_matrix(&self) -> Vec<Vec<i64>> {
            let b = self.biadjacency_matrix();
            let mut a = vec![vec![0i64; 2 * self.n]; 2 * self.n];
            for i in 0..self.n {
                for j in 0..self.n {
                    a[i][self.n + j] = b[i][j];
                    a[self.n + j][i] = b[i][j];
                }
            }
            a
        }

        /// `N x N` Gram matrix `M = B * B^T`.
        pub fn gram_matrix(&self) -> Vec<Vec<i64>> {
            let b = self.biadjacency_matrix();
            let mut m = vec![vec![0i64; self.n]; self.n];
            for i in 0..self.n {
                for j in 0..self.n {
                    let mut acc = 0i64;
                    for k in 0..self.n {
                        acc += b[i][k] * b[j][k];
                    }
                    m[i][j] = acc;
                }
            }
            m
        }

        /// Exact Fourier-mode maximum nontrivial `lambda^2` for connected `G_PLR(N, P5, M3)`.
        /// Returns `None` if disconnected or if any spectral mode is non-finite.
        pub fn max_nontrivial_lambda_sq(&self) -> Option<f64> {
            if !self.is_connected() {
                return None;
            }
            let sh_l = self.m3 as f64;
            let sh_r = (self.n - (self.minor_third() % self.n)) as f64;
            let nf = self.n as f64;
            let mut best = 0.0_f64;
            for k in 1..self.n {
                let kf = k as f64;
                let a1 = 2.0 * PI * kf * sh_l / nf;
                let a2 = 2.0 * PI * kf * sh_r / nf;
                let re = 1.0 + a1.cos() + a2.cos();
                let im = a1.sin() + a2.sin();
                let mag_sq = re * re + im * im;
                if !mag_sq.is_finite() {
                    return None;
                }
                if mag_sq > best {
                    best = mag_sq;
                }
            }
            Some(best)
        }
    }

    pub fn gcd_usize(mut a: usize, mut b: usize) -> usize {
        while b != 0 {
            let r = a % b;
            a = b;
            b = r;
        }
        a
    }

    // -------------------------------------------------------------------------
    // Exact Z Faddeev-LeVerrier, Exact Q Bass-Ihara Determinant, & Prime Cycles
    // -------------------------------------------------------------------------

    /// Exact arbitrary-precision Faddeev-LeVerrier on an `n x n` integer matrix.
    /// Returns `(descending charpoly coefficients, cayley_hamilton_remainder_is_zero)`.
    pub fn faddeev_leverrier_exact(m: &[Vec<i64>]) -> (Vec<i64>, bool) {
        let n = m.len();
        let m_big: Vec<Vec<BigInt>> = m
            .iter()
            .map(|r| r.iter().map(|&v| BigInt::from_i64(v)).collect())
            .collect();
        let mut k_mat: Vec<Vec<BigInt>> = (0..n)
            .map(|i| {
                (0..n)
                    .map(|j| if i == j { BigInt::one() } else { BigInt::zero() })
                    .collect()
            })
            .collect();
        let mut coeffs = Vec::with_capacity(n + 1);
        coeffs.push(1i64);

        for step in 1..=n {
            let mut mk = vec![vec![BigInt::zero(); n]; n];
            for i in 0..n {
                for j in 0..n {
                    let mut sum = BigInt::zero();
                    for t in 0..n {
                        sum = sum.add(&m_big[i][t].mul(&k_mat[t][j]));
                    }
                    mk[i][j] = sum;
                }
            }
            let mut tr = BigInt::zero();
            for (i, row) in mk.iter().enumerate() {
                tr = tr.add(&row[i]);
            }
            let ck_big = tr
                .neg_val()
                .div_exact(&BigInt::from_i64(step as i64))
                .expect("Faddeev-LeVerrier trace divisible by step");
            coeffs.push(ck_big.to_i64_checked().expect("charpoly coeff fits i64"));
            for (i, row) in mk.iter_mut().enumerate() {
                row[i] = row[i].add(&ck_big);
            }
            k_mat = mk;
        }

        let rem_zero = k_mat.iter().all(|row| row.iter().all(BigInt::is_zero));
        (coeffs, rem_zero)
    }

    /// Exact rational determinant via Gaussian elimination over `BigRat`.
    pub fn det_exact_rat(mat: &[Vec<BigRat>]) -> BigRat {
        let n = mat.len();
        let mut a = mat.to_vec();
        let mut det = BigRat::one();
        for col in 0..n {
            let piv = match (col..n).find(|&r| !a[r][col].is_zero()) {
                Some(r) => r,
                None => return BigRat::zero(),
            };
            if piv != col {
                a.swap(col, piv);
                det = det.neg_val();
            }
            let pv = a[col][col].clone();
            det = det.mul(&pv);
            for r in (col + 1)..n {
                if !a[r][col].is_zero() {
                    let factor = a[r][col].div(&pv);
                    for k in col..n {
                        let sub = factor.mul(&a[col][k]);
                        a[r][k] = a[r][k].sub(&sub);
                    }
                }
            }
        }
        det
    }

    /// Evaluates `det(I_24 - u * A + 2 * u^2 * I_24)` directly over exact `BigRat`.
    pub fn bass_ihara_matrix_det(adj: &[Vec<i64>], u: &BigRat) -> BigRat {
        let n = adj.len();
        let u2 = u.mul(u);
        let diag = BigRat::one().add(&BigRat::from_frac(2, 1).mul(&u2));
        let mat: Vec<Vec<BigRat>> = (0..n)
            .map(|i| {
                (0..n)
                    .map(|j| {
                        let base = if i == j { diag.clone() } else { BigRat::zero() };
                        if adj[i][j] != 0 {
                            base.sub(&u.mul(&BigRat::from_frac(adj[i][j], 1)))
                        } else {
                            base
                        }
                    })
                    .collect()
            })
            .collect();
        det_exact_rat(&mat)
    }

    /// Evaluates the closed-form factored Bass-Ihara determinant `D(u)` for 12-TET `G_PLR`.
    pub fn bass_ihara_d_factored_12tet(u: &BigRat) -> BigRat {
        let one = BigRat::one();
        let u2 = u.mul(u);
        let u4 = u2.mul(&u2);
        let u6 = u4.mul(&u2);
        let u8 = u4.mul(&u4);
        let c4 = BigRat::from_frac(4, 1);
        let c3 = BigRat::from_frac(3, 1);
        let c9 = BigRat::from_frac(9, 1);
        let c16 = BigRat::from_frac(16, 1);

        let f1 = one.sub(&u2);
        let f2 = one.sub(&c4.mul(&u2));
        let f3 = one.sub(&u2).add(&c4.mul(&u4)).pow_u32(2);
        let f4 = one.add(&u2).add(&c4.mul(&u4)).pow_u32(2);
        let f5 = one.add(&c3.mul(&u2)).add(&c4.mul(&u4)).pow_u32(3);
        let f6 = one
            .add(&c4.mul(&u2))
            .add(&c9.mul(&u4))
            .add(&c16.mul(&u6))
            .add(&c16.mul(&u8))
            .pow_u32(2);

        f1.mul(&f2).mul(&f3).mul(&f4).mul(&f5).mul(&f6)
    }

    pub fn poly_mul_i64(a: &[i64], b: &[i64]) -> Vec<i64> {
        let mut r = vec![0i64; a.len() + b.len() - 1];
        for (i, &x) in a.iter().enumerate() {
            for (j, &y) in b.iter().enumerate() {
                r[i + j] += x * y;
            }
        }
        r
    }

    pub fn poly_pow_i64(p: &[i64], exp: usize) -> Vec<i64> {
        let mut acc = vec![1i64];
        for _ in 0..exp {
            acc = poly_mul_i64(&acc, p);
        }
        acc
    }

    /// Ascending coefficients of `zeta_{G_PLR}(u)^{-1} = (1 - u^2)^12 * D(u)` (degree 72).
    pub fn zeta_inverse_poly_12tet() -> Vec<i64> {
        let factors: [(&[i64], usize); 6] = [
            (&[1, 0, -1], 13),
            (&[1, 0, -4], 1),
            (&[1, 0, -1, 0, 4], 2),
            (&[1, 0, 1, 0, 4], 2),
            (&[1, 0, 3, 0, 4], 3),
            (&[1, 0, 4, 0, 9, 0, 16, 0, 16], 2),
        ];
        let mut f = vec![1i64];
        for (fac, mult) in factors {
            f = poly_mul_i64(&f, &poly_pow_i64(fac, mult));
        }
        f
    }

    pub fn mobius(mut n: usize) -> i64 {
        if n == 0 {
            return 0;
        }
        let mut p = 2usize;
        let mut cnt = 0usize;
        while p * p <= n {
            if n.is_multiple_of(p) {
                n /= p;
                if n.is_multiple_of(p) {
                    return 0;
                }
                cnt += 1;
            }
            p += 1;
        }
        if n > 1 {
            cnt += 1;
        }
        if cnt % 2 == 1 {
            -1
        } else {
            1
        }
    }

    /// Exact prime-cycle table row `(m, N_m, oriented_primes, unoriented_primes)`.
    pub fn compute_prime_cycle_table(zeta_inv: &[i64], max_m: usize) -> Vec<(usize, i64, i64, i64)> {
        let mut n_walk = vec![0i64; max_m + 1];
        for m in 1..=max_m {
            let fm = *zeta_inv.get(m).unwrap_or(&0);
            let rhs = -(m as i64) * fm;
            let mut lhs_rest = 0i64;
            for k in 1..m {
                lhs_rest += (*zeta_inv.get(k).unwrap_or(&0)) * n_walk[m - k];
            }
            n_walk[m] = rhs - lhs_rest;
        }
        let mut rows = Vec::new();
        for m in (2..=max_m).step_by(2) {
            let mut total = 0i64;
            for (d, &nw_d) in n_walk.iter().enumerate().take(m + 1).skip(1) {
                if m.is_multiple_of(d) {
                    total += mobius(m / d) * nw_d;
                }
            }
            let oriented = total / (m as i64);
            rows.push((m, n_walk[m], oriented, oriented / 2));
        }
        rows
    }

    /// Direct combinatorial enumeration of the `LPRLPR` (pitch-class dual faces) and `LPLPLP`
    /// (Cohn hexatonic cycles) minimal hexagons on 12-TET `G_PLR`.
    pub fn enumerate_musical_hexagons_12tet() -> (usize, usize) {
        let sys = NTetSystem::canonical_12tet();
        let lprlpr = [PlrOp::L, PlrOp::P, PlrOp::R, PlrOp::L, PlrOp::P, PlrOp::R];
        let lplplp = [PlrOp::L, PlrOp::P, PlrOp::L, PlrOp::P, PlrOp::L, PlrOp::P];

        let count_distinct = |word: &[PlrOp]| -> usize {
            let mut set: BTreeSet<Vec<usize>> = BTreeSet::new();
            for r in 0..12 {
                let mut cur = Triad {
                    root: r,
                    polarity: Polarity::Major,
                };
                let mut majors = BTreeSet::new();
                majors.insert(cur.root);
                for &op in word {
                    cur = sys.apply_plr(op, cur);
                    if cur.polarity == Polarity::Major {
                        majors.insert(cur.root);
                    }
                }
                assert_eq!(cur, Triad { root: r, polarity: Polarity::Major });
                set.insert(majors.into_iter().collect());
            }
            set.len()
        };

        (count_distinct(&lprlpr), count_distinct(&lplplp))
    }

    /// Computes exact maximum nontrivial `|lambda|` for the primal 12-TET Tonnetz
    /// (12 vertices, 6-regular circulant with shifts `{±3, ±4, ±7} mod 12`, `q = 5`).
    pub fn primal_12tet_tonnetz_max_nontrivial_abs_lambda() -> f64 {
        let shifts = [3.0_f64, 4.0, 5.0, 7.0, 8.0, 9.0];
        let mut best = 0.0_f64;
        for k in 1..12 {
            let kf = k as f64;
            let mut sum = 0.0_f64;
            let mut comp = 0.0_f64;
            for &s in &shifts {
                let term = (2.0 * PI * kf * s / 12.0).cos();
                if !term.is_finite() {
                    return f64::NAN;
                }
                let t = sum + term;
                if sum.abs() >= term.abs() {
                    comp += (sum - t) + term;
                } else {
                    comp += (term - t) + sum;
                }
                sum = t;
            }
            let mag = (sum + comp).abs();
            if !mag.is_finite() {
                return f64::NAN;
            }
            if mag > best {
                best = mag;
            }
        }
        best
    }

    // -------------------------------------------------------------------------
    // Minimal Zero-Dependency JSON Parser & Vault Parity Auditor
    // -------------------------------------------------------------------------

    #[derive(Debug, Clone, PartialEq)]
    pub enum JsonValue {
        Null,
        Bool(bool),
        Number(f64, String),
        Str(String),
        Array(Vec<JsonValue>),
        Object(Vec<(String, JsonValue)>),
    }

    impl JsonValue {
        pub fn get(&self, key: &str) -> Option<&JsonValue> {
            match self {
                JsonValue::Object(entries) => entries.iter().find(|(k, _)| k == key).map(|(_, v)| v),
                _ => None,
            }
        }

        pub fn as_str(&self) -> Option<&str> {
            match self {
                JsonValue::Str(s) => Some(s.as_str()),
                _ => None,
            }
        }

        pub fn as_bool(&self) -> Option<bool> {
            match self {
                JsonValue::Bool(b) => Some(*b),
                _ => None,
            }
        }

        pub fn as_i64(&self) -> Option<i64> {
            match self {
                JsonValue::Number(_, raw) => raw.parse::<i64>().ok(),
                _ => None,
            }
        }

        pub fn as_f64(&self) -> Option<f64> {
            match self {
                JsonValue::Number(v, _) => Some(*v),
                _ => None,
            }
        }

        pub fn as_array(&self) -> Option<&[JsonValue]> {
            match self {
                JsonValue::Array(a) => Some(a.as_slice()),
                _ => None,
            }
        }
    }

    struct JsonParser<'a> {
        bytes: &'a [u8],
        pos: usize,
    }

    impl<'a> JsonParser<'a> {
        fn new(s: &'a str) -> Self {
            Self {
                bytes: s.as_bytes(),
                pos: 0,
            }
        }

        fn skip_ws(&mut self) {
            while self.pos < self.bytes.len() && matches!(self.bytes[self.pos], b' ' | b'\n' | b'\r' | b'\t') {
                self.pos += 1;
            }
        }

        fn peek(&mut self) -> Option<u8> {
            self.skip_ws();
            self.bytes.get(self.pos).copied()
        }

        fn parse_value(&mut self) -> Result<JsonValue, String> {
            match self.peek() {
                Some(b'{') => self.parse_object(),
                Some(b'[') => self.parse_array(),
                Some(b'"') => self.parse_string().map(JsonValue::Str),
                Some(b't') => self.expect_literal(b"true", JsonValue::Bool(true)),
                Some(b'f') => self.expect_literal(b"false", JsonValue::Bool(false)),
                Some(b'n') => self.expect_literal(b"null", JsonValue::Null),
                Some(b'-' | b'0'..=b'9') => self.parse_number(),
                other => Err(format!("unexpected token at {}: {:?}", self.pos, other)),
            }
        }

        fn expect_literal(&mut self, lit: &[u8], val: JsonValue) -> Result<JsonValue, String> {
            if self.bytes.get(self.pos..self.pos + lit.len()) == Some(lit) {
                self.pos += lit.len();
                Ok(val)
            } else {
                Err(format!("invalid literal at {}", self.pos))
            }
        }

        fn parse_string(&mut self) -> Result<String, String> {
            self.skip_ws();
            if self.bytes.get(self.pos) != Some(&b'"') {
                return Err(format!("expected '\"' at {}", self.pos));
            }
            self.pos += 1;
            let mut out = String::new();
            while self.pos < self.bytes.len() {
                let b = self.bytes[self.pos];
                self.pos += 1;
                if b == b'"' {
                    return Ok(out);
                }
                if b == b'\\' {
                    let esc = *self
                        .bytes
                        .get(self.pos)
                        .ok_or_else(|| "unterminated escape".to_string())?;
                    self.pos += 1;
                    match esc {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000C}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let hex = std::str::from_utf8(
                                self.bytes
                                    .get(self.pos..self.pos + 4)
                                    .ok_or_else(|| "short unicode escape".to_string())?,
                            )
                            .map_err(|e| e.to_string())?;
                            let code = u32::from_str_radix(hex, 16).map_err(|e| e.to_string())?;
                            self.pos += 4;
                            out.push(char::from_u32(code).unwrap_or('\u{FFFD}'));
                        }
                        _ => return Err(format!("unknown escape \\{}", esc as char)),
                    }
                } else {
                    // Advance valid UTF-8 slice cleanly
                    let start = self.pos - 1;
                    let mut end = self.pos;
                    while end < self.bytes.len() && (self.bytes[end] & 0xC0) == 0x80 {
                        end += 1;
                    }
                    let chunk = std::str::from_utf8(&self.bytes[start..end])
                        .map_err(|e| e.to_string())?;
                    out.push_str(chunk);
                    self.pos = end;
                }
            }
            Err("unterminated string".to_string())
        }

        fn parse_number(&mut self) -> Result<JsonValue, String> {
            self.skip_ws();
            let start = self.pos;
            while self.pos < self.bytes.len()
                && matches!(
                    self.bytes[self.pos],
                    b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9'
                )
            {
                self.pos += 1;
            }
            let raw = std::str::from_utf8(&self.bytes[start..self.pos])
                .map_err(|e| e.to_string())?
                .to_string();
            let num = raw
                .parse::<f64>()
                .map_err(|e| format!("invalid number '{}': {}", raw, e))?;
            Ok(JsonValue::Number(num, raw))
        }

        fn parse_array(&mut self) -> Result<JsonValue, String> {
            self.pos += 1; // '['
            let mut items = Vec::new();
            if self.peek() == Some(b']') {
                self.pos += 1;
                return Ok(JsonValue::Array(items));
            }
            loop {
                items.push(self.parse_value()?);
                match self.peek() {
                    Some(b',') => self.pos += 1,
                    Some(b']') => {
                        self.pos += 1;
                        return Ok(JsonValue::Array(items));
                    }
                    other => return Err(format!("expected ',' or ']' at {}: {:?}", self.pos, other)),
                }
            }
        }

        fn parse_object(&mut self) -> Result<JsonValue, String> {
            self.pos += 1; // '{'
            let mut entries = Vec::new();
            if self.peek() == Some(b'}') {
                self.pos += 1;
                return Ok(JsonValue::Object(entries));
            }
            loop {
                let key = self.parse_string()?;
                if self.peek() != Some(b':') {
                    return Err(format!("expected ':' at {}", self.pos));
                }
                self.pos += 1;
                let val = self.parse_value()?;
                entries.push((key, val));
                match self.peek() {
                    Some(b',') => self.pos += 1,
                    Some(b'}') => {
                        self.pos += 1;
                        return Ok(JsonValue::Object(entries));
                    }
                    other => return Err(format!("expected ',' or '}}' at {}: {:?}", self.pos, other)),
                }
            }
        }
    }

    pub fn parse_json(raw: &str) -> Result<JsonValue, String> {
        let mut p = JsonParser::new(raw);
        let v = p.parse_value()?;
        p.skip_ws();
        if p.pos != p.bytes.len() {
            return Err(format!("trailing bytes at {}", p.pos));
        }
        Ok(v)
    }

    /// Evaluates 8 independent atomic fail-closed boolean guards verifying exact Z/Q mathematical
    /// parity between freshly computed `riem_lattice` invariants and a JSON data vault.
    pub fn verify_vault_json(raw_json: &str) -> Vec<GuardVerdict> {
        let parsed = match parse_json(raw_json) {
            Ok(v) => v,
            Err(e) => {
                return vec![GuardVerdict::fail(
                    "vault_json_parse",
                    1,
                    format!("JSON parse failed: {}", e),
                )];
            }
        };

        let mut verdicts = Vec::with_capacity(8);

        // Guard 1: Tradition ID & anti-conflation provenance tag
        let trad_ok = parsed.get("tradition_id").and_then(JsonValue::as_str) == Some("RIEM-LATTICE")
            && parsed.get("anti_conflation_guard").is_some()
            && !raw_json.to_ascii_lowercase().contains("wikipedia.org")
            && !raw_json.to_ascii_lowercase().contains("wikisource.org");
        verdicts.push(if trad_ok {
            GuardVerdict::pass(
                "vault_tradition_and_provenance",
                "tradition_id=RIEM-LATTICE, anti_conflation_guard present, 0 wiki URLs",
            )
        } else {
            GuardVerdict::fail(
                "vault_tradition_and_provenance",
                1,
                "missing RIEM-LATTICE tradition tag, anti_conflation_guard, or banned wiki URL present",
            )
        });

        let sys12 = NTetSystem::canonical_12tet();
        let adj = sys12.adjacency_matrix();
        let gram = sys12.gram_matrix();

        // Guard 2: Basic 24-vertex, 36-edge, 3-regular bipartite graph invariants
        let inv = parsed.get("tonnetz_dual_exact_invariants");
        let directed_edges: i64 = adj.iter().flat_map(|r| r.iter()).sum();
        let deg3_all = adj.iter().all(|r| r.iter().sum::<i64>() == 3);
        let v_match = inv.and_then(|o| o.get("vertices_count")).and_then(JsonValue::as_i64) == Some(24);
        let e_match = inv.and_then(|o| o.get("edges_count")).and_then(JsonValue::as_i64) == Some(directed_edges / 2);
        let d_match = inv.and_then(|o| o.get("degree_d")).and_then(JsonValue::as_i64) == Some(3);
        let q_match = inv.and_then(|o| o.get("ihara_parameter_q")).and_then(JsonValue::as_i64) == Some(2);
        verdicts.push(if deg3_all && directed_edges == 72 && v_match && e_match && d_match && q_match {
            GuardVerdict::pass(
                "g_plr_graph_invariants",
                "|V|=24, |E|=36, 3-regular bipartite, q=2 verified against vault",
            )
        } else {
            GuardVerdict::fail(
                "g_plr_graph_invariants",
                1,
                "G_PLR structural invariants mismatch between computed graph and vault",
            )
        });

        // Guard 3: Exhaustive Crans-Fiore-Satyendra mutual centralizer duality + 12-TET parsimony
        let mc_viol = sys12.mutual_centralizer_violations() + sys12.parsimony_violations();
        verdicts.push(if mc_viol == 0 {
            GuardVerdict::pass(
                "g_plr_mutual_centralizer_duality",
                "0 violations across all 24 triads x 12 shifts/axes x {P,L,R} (involutive, parsimonious, commuting)",
            )
        } else {
            GuardVerdict::fail(
                "g_plr_mutual_centralizer_duality",
                mc_viol,
                format!("{} mutual centralizer / parsimony violations", mc_viol),
            )
        });

        // Guard 4: Exact Z Faddeev-LeVerrier characteristic polynomial & Cayley-Hamilton zero remainder
        let (charpoly, ch_zero) = faddeev_leverrier_exact(&gram);
        let vault_charpoly: Option<Vec<i64>> = inv
            .and_then(|o| o.get("exact_charpoly_B_BT_descending_y"))
            .and_then(JsonValue::as_array)
            .and_then(|arr| arr.iter().map(JsonValue::as_i64).collect());
        verdicts.push(if ch_zero && vault_charpoly.as_ref() == Some(&charpoly) {
            GuardVerdict::pass(
                "g_plr_exact_charpoly_over_Z",
                "exact Faddeev-LeVerrier charpoly matches vault with 0 Cayley-Hamilton remainder",
            )
        } else {
            GuardVerdict::fail(
                "g_plr_exact_charpoly_over_Z",
                1,
                "charpoly mismatch between exact Faddeev-LeVerrier and vault JSON",
            )
        });

        // Guard 5: Exact Q Bass-Ihara determinant identity + completed functional equation Xi(2^-s) = Xi(2^-(1-s))
        let test_us = [
            BigRat::from_frac(1, 3),
            BigRat::from_frac(1, 5),
            BigRat::from_frac(2, 7),
            BigRat::from_frac(3, 11),
        ];
        let mut bi_viol = 0usize;
        for u in &test_us {
            let det_mat = bass_ihara_matrix_det(&adj, u);
            let det_fac = bass_ihara_d_factored_12tet(u);
            if det_mat != det_fac {
                bi_viol += 1;
            }
            let two_u2 = BigRat::from_frac(2, 1).mul(&u.mul(u));
            let inv_2u = BigRat::from_frac(1, 2).div(u);
            let rhs = two_u2.pow_u32(24).mul(&bass_ihara_d_factored_12tet(&inv_2u));
            if det_fac != rhs {
                bi_viol += 1;
            }
        }
        let rh_flag = inv
            .and_then(|o| o.get("graph_rh_verdict"))
            .and_then(|v| v.get("satisfies_graph_riemann_hypothesis"))
            .and_then(JsonValue::as_bool)
            == Some(true);
        let margin_ok = inv
            .and_then(|o| o.get("graph_rh_verdict"))
            .and_then(|v| v.get("exact_integer_squared_margin"))
            .and_then(JsonValue::as_i64)
            == Some(3);
        verdicts.push(if bi_viol == 0 && rh_flag && margin_ok {
            GuardVerdict::pass(
                "g_plr_bass_ihara_and_functional_eq_over_Q",
                "exact 24x24 det(I - uA + 2u^2 I) = D(u) = (2u^2)^24 D(1/(2u)) verified at 4 rationals; margin=3",
            )
        } else {
            GuardVerdict::fail(
                "g_plr_bass_ihara_and_functional_eq_over_Q",
                bi_viol.max(1),
                "Bass-Ihara rational determinant, functional equation, or Graph-RH margin mismatch",
            )
        });

        // Guard 6: Exact prime-cycle table (m = 2..20) + 12 LPRLPR + 4 LPLPLP minimal hexagons
        let zeta_inv = zeta_inverse_poly_12tet();
        let computed_primes = compute_prime_cycle_table(&zeta_inv, 20);
        let (lprlpr_cnt, lplplp_cnt) = enumerate_musical_hexagons_12tet();
        let mut prime_viol = 0usize;
        if let Some(arr) = inv.and_then(|o| o.get("exact_prime_cycle_table")).and_then(JsonValue::as_array) {
            if arr.len() != computed_primes.len() {
                prime_viol += 1;
            } else {
                for (row, &(m, nm, or_p, un_p)) in arr.iter().zip(computed_primes.iter()) {
                    if row.get("length_m").and_then(JsonValue::as_i64) != Some(m as i64)
                        || row.get("closed_nb_walks_N_m").and_then(JsonValue::as_i64) != Some(nm)
                        || row.get("oriented_primes").and_then(JsonValue::as_i64) != Some(or_p)
                        || row.get("unoriented_primes").and_then(JsonValue::as_i64) != Some(un_p)
                    {
                        prime_viol += 1;
                    }
                }
            }
        } else {
            prime_viol += 1;
        }
        let hex_obj = inv.and_then(|o| o.get("minimal_prime_hexagons_length_6"));
        let hex_decomp = hex_obj.and_then(|h| h.get("decomposition"));
        if hex_obj.and_then(|h| h.get("total_unoriented")).and_then(JsonValue::as_i64) != Some(16)
            || hex_decomp.and_then(|d| d.get("LPRLPR_pitch_class_dual_faces")).and_then(JsonValue::as_i64)
                != Some(lprlpr_cnt as i64)
            || hex_decomp.and_then(|d| d.get("LPLPLP_hexatonic_cycles")).and_then(JsonValue::as_i64)
                != Some(lplplp_cnt as i64)
            || lprlpr_cnt != 12
            || lplplp_cnt != 4
        {
            prime_viol += 1;
        }
        verdicts.push(if prime_viol == 0 {
            GuardVerdict::pass(
                "g_plr_prime_cycles_and_16_hexagons",
                "10 prime-cycle rows (m=2..20) + 12 LPRLPR + 4 LPLPLP = 16 minimal hexagons match vault",
            )
        } else {
            GuardVerdict::fail(
                "g_plr_prime_cycles_and_16_hexagons",
                prime_viol,
                format!("{} prime-cycle or hexagon decomposition mismatches", prime_viol),
            )
        });

        // Guard 7: Primal 12-TET Tonnetz (12 vertices, 6-regular, q=5) Ramanujan check
        let primal_lam = primal_12tet_tonnetz_max_nontrivial_abs_lambda();
        let primal_bound = 2.0 * 5.0_f64.sqrt();
        let primal_obj = parsed.get("primal_12tet_tonnetz_summary");
        let primal_vault_lam = primal_obj
            .and_then(|o| o.get("max_nontrivial_abs_lambda_approx"))
            .and_then(JsonValue::as_f64);
        let primal_vault_rh = primal_obj
            .and_then(|o| o.get("satisfies_graph_riemann_hypothesis"))
            .and_then(JsonValue::as_bool);
        let primal_ok = primal_lam < primal_bound
            && primal_vault_rh == Some(true)
            && primal_vault_lam.is_some_and(|v| (v - primal_lam).abs() < 1e-6);
        verdicts.push(if primal_ok {
            GuardVerdict::pass(
                "primal_12tet_tonnetz_ramanujan",
                format!("max|lambda|={:.6} < 2*sqrt(5)={:.6} matches vault", primal_lam, primal_bound),
            )
        } else {
            GuardVerdict::fail(
                "primal_12tet_tonnetz_ramanujan",
                1,
                "primal 12-TET Tonnetz Ramanujan summary mismatch",
            )
        });

        // Guard 8: N-TET Correspondence-Principle regime sweep (all rows verified independently)
        let mut sweep_viol = 0usize;
        let mut sweep_count = 0usize;
        if let Some(arr) = parsed.get("ntet_correspondence_regime_sweep").and_then(JsonValue::as_array) {
            sweep_count = arr.len();
            if sweep_count == 0 {
                sweep_viol += 1;
            }
            for row in arr {
                let n = match row.get("N").and_then(JsonValue::as_i64) {
                    Some(v) if v > 0 => v as usize,
                    _ => {
                        sweep_viol += 1;
                        continue;
                    }
                };
                let sys = NTetSystem::from_n(n);
                let p5_ok = row.get("P5").and_then(JsonValue::as_i64) == Some(sys.p5 as i64);
                let m3_ok = row.get("M3").and_then(JsonValue::as_i64) == Some(sys.m3 as i64);
                let min3_ok = row.get("m3").and_then(JsonValue::as_i64) == Some(sys.minor_third() as i64);
                let conn = sys.is_connected();
                let conn_ok = row.get("connected").and_then(JsonValue::as_bool) == Some(conn);
                if !(p5_ok && m3_ok && min3_ok && conn_ok) {
                    sweep_viol += 1;
                    continue;
                }
                match sys.max_nontrivial_lambda_sq() {
                    None => {
                        if row.get("satisfies_graph_rh").and_then(JsonValue::as_bool) != Some(false) {
                            sweep_viol += 1;
                        }
                    }
                    Some(lam_sq) => {
                        let passes_rh = lam_sq <= 8.0 + 1e-12;
                        let lam_ok = row
                            .get("max_lambda_sq")
                            .and_then(JsonValue::as_f64)
                            .is_some_and(|v| (v - lam_sq).abs() < 1e-4);
                        let rh_ok = row.get("satisfies_graph_rh").and_then(JsonValue::as_bool)
                            == Some(passes_rh);
                        if !(lam_ok && rh_ok) {
                            sweep_viol += 1;
                        }
                    }
                }
            }
        } else {
            sweep_viol += 1;
        }
        verdicts.push(if sweep_viol == 0 {
            GuardVerdict::pass(
                "ntet_correspondence_regime_sweep",
                format!("all {} N-TET sweep rows verified (12-TET pass; 17/24/27/41/43/53-TET fail)", sweep_count),
            )
        } else {
            GuardVerdict::fail(
                "ntet_correspondence_regime_sweep",
                sweep_viol,
                format!("{} N-TET correspondence sweep mismatches", sweep_viol),
            )
        });

        verdicts
    }
}
