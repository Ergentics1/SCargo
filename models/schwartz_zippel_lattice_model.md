# The Schwartz–Zippel (ODLSZ) Lattice Module: Primary Lineage, Sharp Bounds, Ring Boundaries, and PIT Integration

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)  
**Status**: Machine-Foundational Mathematical Specification (Pre-Implementation Research Layer)  
**Tradition Namespace**: `PIT-SZ` (strictly disjoint from `RIEM-A`, `RIEM-B`, `RIEM-C`, `RIEM-LATTICE`)  
**Primary Data Vaults**:  
- Schwartz–Zippel Primary Research & Benchmarks: [`schwartz_zippel_research_v1.json`](../data/sources/schwartz_zippel_research_v1.json)  
- Import-Style Riemann Lattice (`RIEM-LATTICE`): [`riemann_lattice_graph_rh_v1.json`](../data/sources/riemann_lattice_graph_rh_v1.json)  
- Verification Methodology & Probabilistic SWE-Sweep: [`verification_methodology_model.md`](verification_methodology_model.md)

---

## 1. Historical Attribution & Lineage (1922–2026)

What is commonly called the **Schwartz–Zippel Lemma** is a four-paper lineage—formally the **Ore–DeMillo–Lipton–Schwartz–Zippel (ODLSZ) Lemma**—that grew from finite-field congruence theory into the backbone of randomized algorithms, algebraic complexity, interactive proofs, and formal SNARK verification:

```mermaid
flowchart TD
    ORE["Ore 1922 (SZ-F01): F_q root bound <= d * q^(n-1)"]
    DL["DeMillo & Lipton 1978 (SZ-F02): Randomized algebraic testing"]
    ZIP["Zippel 1979 / 1993 (SZ-F03, SZ-F05): Sparse interpolation & finite subsets"]
    SCH["Schwartz 1980 (SZ-F04): Sharp total-degree PIT bound d / |S|"]

    AF["Alon-Furedi 1993 & Alon 1999 (SZ-G02, SZ-G04): Sharp grid & Nullstellensatz"]
    DKSS["Dvir 2009 & DKSS 2013 (SZ-G05, SZ-G06): Kakeya & Multiplicity SZ (Hasse)"]
    BCPS["Bishnoi-Clark-Potukuchi-Schmitt 2018 & Rote 2023 (SZ-G07, SZ-G08): Condition (D) rings"]
    SLICE["Amireddy-Behera-Srinivasan-Sudan 2025 (SZ-G09): Boolean-slice ODLSZ"]

    MATCH["Edmonds 1967 -> Lovasz 1979 -> MVV 1987 -> CGGRT & KS 2026 (SZ-A01..A08): Bipartite matching in NC"]
    DERAND["Kabanets-Impagliazzo 2004 -> LST 2021 -> AKT 2025 (SZ-C01..C08): PIT <-> Lower Bounds"]
    ZK["LFKN 1992 -> Shamir 1992 -> Thaler 2022 (SZ-P01..P03): Sum-Check, IP=PSPACE, SNARKs"]
    FORMAL["Kim-Tan AFP 2023 -> Bailey-Miller Lean 2024 -> Mathlib4 (SZ-V01..V04): Machine-checked proofs"]

    ORE --> SCH
    DL --> SCH
    ZIP --> SCH
    SCH --> AF --> BCPS
    SCH --> DKSS
    AF --> SLICE
    SCH --> MATCH
    SCH --> DERAND
    SCH --> ZK --> FORMAL
    SCH --> FORMAL
```

- **Øystein Ore (1922, `SZ-F01`)** proved the total-degree bound over finite fields $\mathbb{F}_q$ ($Z(f) \le d q^{n-1}$ for $d < q$) 56 years before computer science rediscovered it.
- **Richard A. DeMillo & Richard J. Lipton (1978, `SZ-F02`)** introduced randomized point evaluation for testing algebraic program equivalence.
- **Richard Zippel (1979, `SZ-F03`; 1993, `SZ-F05`)** proved the finite-subset multivariate zero bound for sparse polynomial interpolation.
- **Jacob T. Schwartz (1980, `SZ-F04`)** sharpened the general inductive total-degree bound $\Pr[f(r) = 0] \le d / |S|$ over arbitrary finite subsets $S$ of an integral domain and built fast probabilistic Polynomial Identity Testing (PIT) algorithms.
- **Dana Moshkovitz (2010, `SZ-F06`)** later gave a short non-inductive proof over finite fields by reducing directly to random affine lines (univariate roots).

---

## 2. Five Distinct Theorem Families (No Conflation)

The literature contains five distinct results that are often conflated in informal summaries. In `SCargo`, each carries a distinct family ID (`TF-01`–`TF-05`) and exact hypotheses (`schwartz_zippel_research_v1.json`):

| Family | Exact Bound | Required Hypotheses | Where It Wins / Breaks |
|---|---|---|---|
| **TF-01: Total-Degree ODLSZ** (`SZ-F01`, `SZ-F04`) | $Z_{S^n}(f) \le d \cdot |S|^{n-1}$ ($\Pr[f(r)=0] \le d/|S|$) | Integral domain $R$, finite $S \subseteq R$, $f \neq 0$, total degree $d$ | Simple, sharp for univariate factors; becomes **vacuous** when $d \ge |S|$. |
| **TF-02: Individual-Degree DLZ / Knuth** (`SZ-F02`, `SZ-F03`, `SZ-G08`) | $NZ_{\prod S_i}(f) \ge \prod_{i=1}^n (|S_i| - d_i)$ | Integral domain $R$, $d_i = \deg_{x_i}(f) < |S_i|$ (or lex-maximal monomial) | **Incomparable to TF-01**: beats TF-01 on $x_1 x_2$, loses on $x_1 + x_2$. |
| **TF-03: Alon–Füredi & Nullstellensatz** (`SZ-G02`, `SZ-G04`, `SZ-G07`) | $NZ_{\prod S_i}(f) \ge \min \{\prod y_i : 1 \le y_i \le |S_i|,\; \sum y_i = \sum |S_i| - d\}$ | $f$ not identically zero on $\prod S_i$ (e.g. reduced mod $\prod_{a \in S_i}(x_i-a)$) | **Strictly beats TF-01 when $d \ge |S|$** (e.g. exact $2^{n-d}$ nonzeros on $\{0,1\}^n$); gives exact $\varepsilon = 0$ deterministic existence. |
| **TF-04: Multiplicity SZ (DKSS)** (`SZ-G05`, `SZ-G06`) | $\sum_{a \in S^n} \operatorname{mult}(f, a) \le d \cdot |S|^{n-1}$ | Any field $\mathbb{F}$ (arbitrary characteristic), Hasse derivative multiplicity | Weights every root by vanishing multiplicity; avoids characteristic-$p$ division by $k!$. |
| **TF-05: Condition (D) Rings & Slices** (`SZ-G07`, `SZ-G08`, `SZ-G09`) | TF-01/02/03 hold over any commutative ring $R$ if $\forall a \neq b \in S_i$, $a - b$ is not a zero divisor; on Boolean slices $\Pr[f \neq 0] \ge (\frac{\min(k, n-k)}{n})^d(1 - o_n(1))$ | Condition (D) grid on commutative ring $R$, or Hamming-weight-$k$ slice $\{0,1\}^n_k$ | Exact ring boundary: over $\mathbb{Z}/m\mathbb{Z}$, max safe grid size drops from $m$ to smallest prime factor $p_{\min}(m)$. |

### 2.1 Exact Verified Comparison on $\mathbb{F}_5^n$ (Incomparability of TF-01 vs. TF-02)
Exhaustive exact evaluation over $\mathbb{F}_5$ (`|S| = 5`, recorded in `schwartz_zippel_research_v1.json`) demonstrates why TF-01 and TF-02 are strictly incomparable:

| Polynomial $f \in \mathbb{F}_5[x_1, \dots, x_n]$ | $(n, d, [d_i])$ | Exact Zeros | TF-01 (SZ) Max Zeros | TF-02 (DLZ) Max Zeros | Tightest |
|---|---|---:|---:|---:|---|
| $x_1 x_2$ | $(2, 2, [1, 1])$ | `9` / 25 | `10` | **`9`** | **DLZ (exact)** |
| $x_1 + x_2$ | $(2, 1, [1, 1])$ | `5` / 25 | **`5`** | `9` | **SZ (exact)** |
| $x_1(x_1 - 1)x_2$ | $(2, 3, [2, 1])$ | `13` / 25 | `15` | **`13`** | **DLZ (exact)** |
| $x_1^2 x_2 - x_3^3$ | $(3, 3, [2, 1, 3])$ | `25` / 125 | **`75`** | `101` | **SZ** |

### 2.2 High-Degree Boolean Cube Regime ($d \ge |S|$) & Multiplicity Tightness
- **Boolean cube $\{0, 1\}^4$ ($|S| = 2$, $16$ points)**: For $f = x_1 x_2 x_3$ ($d = 3 > |S| = 2$), total-degree SZ gives $d/|S| = 3/2 \ge 1$ (**vacuous**: guaranteed nonzeros `0`), whereas **Alon–Füredi (`TF-03`)** gives the exact count $2^{4 - 3} = \mathbf{2}$ nonzeros (`14` zeros).
- **Hasse-derivative Multiplicity SZ (`TF-04`)**: For $f(x, y) = (x - y)^2(x + y)$ over $\mathbb{F}_5^2$ ($d = 3$, $|S| = 5$), $f$ has `9` distinct roots (`4` of multiplicity `1`, `4` of multiplicity `2`, and $(0, 0)$ of multiplicity `3`), giving total multiplicity $4(1) + 4(2) + 1(3) = \mathbf{15} = d \cdot |S|^{n-1}$ — saturating the DKSS bound with exact equality.

---

## 3. Correspondence Principle: Regime Map & Zero-Divisor Breakdown

Under SCargo's governing **Correspondence Principle** (*every deeper theory must smoothly contain the older theory inside its proven dimensionless regime, with a quantifiable error bound on the mismatch*), polynomial verification spans three sharply delineated algebraic regimes governed by the dimensionless ratio $\rho = d / |S|$ and ring integrity:

| Regime | Algebraic Domain & Sampling Rule | Quantifiable Error Bound $\varepsilon$ | Exact Behavior |
|---|---|---|---|
| **1. Deterministic Exact Regime** | Integral domain (or Condition (D) grid), full evaluation over $\prod S_i$ with $|S_i| > d_i$ (`TF-03` / Alon 1999) | $\varepsilon = \mathbf{0}$ | Zero false positives and zero false negatives; reduces to exact coefficient / interpolation equality. |
| **2. Probabilistic PIT Regime** | Integral domain (or Condition (D) grid), $k$ independent uniform draws from $S^n$ with $\rho = d/|S| < 1$ (`TF-01`) | $\varepsilon_{\text{FP}} = 0,\quad \varepsilon_{\text{FN}} \le \left(\frac{d}{|S|}\right)^k$ | One-sided error: any nonzero evaluation is a deterministic proof that $f \not\equiv 0$; as $|S| \to \infty$ or $k \to \infty$, smoothly converges to $\varepsilon = 0$. |
| **3. Non-Integral-Domain Breakdown** | Composite commutative ring $\mathbb{Z}/m\mathbb{Z}$ with zero divisors on full ring grid ($S = \mathbb{Z}/m\mathbb{Z}$) | **Standard bound fails** (actual zero fraction exceeds $d/|S|$ by factor $\ge 2\times$) | Restored **if and only if** grid $S$ satisfies Condition (D) (`SZ-G07`), capping grid size at $|S| \le p_{\min}(m)$ (smallest prime factor of $m$). |

### 3.1 Exact Composite-Ring Counterexamples (Verified Exhaustively)
Testing the degree-2 polynomial $f(x) = x(x - 1)$ across prime vs. composite moduli $\mathbb{Z}/m\mathbb{Z}$ exposes the exact regime boundary:

| Ring $\mathbb{Z}/m\mathbb{Z}$ | Integral Domain? | Max Condition (D) Grid $p_{\min}(m)$ | Roots of $x(x-1)$ | Actual Zero Fraction | Classical SZ Bound $2/m$ | Violates SZ? |
|---|---|---:|---|---:|---:|---|
| $\mathbb{Z}/5\mathbb{Z}$ | Yes | `5` | `{0, 1}` (2) | `2/5` (`0.4000`) | `2/5` (`0.4000`) | **No** |
| $\mathbb{Z}/6\mathbb{Z}$ | **No** | `2` | `{0, 1, 3, 4}` (4) | `2/3` (`0.6667`) | `1/3` (`0.3333`) | **YES (2×)** |
| $\mathbb{Z}/7\mathbb{Z}$ | Yes | `7` | `{0, 1}` (2) | `2/7` (`0.2857`) | `2/7` (`0.2857`) | **No** |
| $\mathbb{Z}/15\mathbb{Z}$ | **No** | `3` | `{0, 1, 6, 10}` (4) | `4/15` (`0.2667`) | `2/15` (`0.1333`) | **YES (2×)** |
| $\mathbb{Z}/30\mathbb{Z}$ | **No** | `2` | `{0, 1, 6, 10, 15, 16, 21, 25}` (8) | `4/15` (`0.2667`) | `1/15` (`0.0667`) | **YES (4×)** |

For the bivariate linear polynomial $h(x, y) = 3x$ ($d = 1$, nonzero in $(\mathbb{Z}/6\mathbb{Z})[x, y]$):
- On the full ring $(\mathbb{Z}/6\mathbb{Z})^2$, $h$ vanishes on **`18/36 = 1/2`** of points, exceeding $d/|S| = 1/6$ by **3×**.
- Restricting to the Condition (D) grid $S = \{0, 1\}$ (differences $\pm 1 \in (\mathbb{Z}/6\mathbb{Z})^\times$), $h$ vanishes on **`2/4 = 1/2`**, restoring exact compliance with $d/|S| = 1/2$.

---

## 4. Algorithmic, Complexity, Interactive-Proof & Formalization Pillars

1. **Matrix Verification & Graph Matching (`SZ-A01`–`SZ-A08`)**:
   - **Freivalds (1979)** verifies $A B = C$ in $O(n^2)$ time by degree-1 Schwartz–Zippel projection.
   - **Edmonds (1967) → Lovász (1979) → Mulmuley–Vazirani–Vazirani (1987)** reduced bipartite perfect matching to PIT on $\det(B(X)) \not\equiv 0$, placing matching in `RNC`.
   - **2026 Breakthrough (`SZ-A07`, `SZ-A08`)**: **Chatterjee, Ghosh, Gurjar, Raj, & Thierauf (2026, ECCC TR26-100)** proved **Bipartite Matching is in deterministic `NC`** (plus linear matroid intersection and non-commutative rank) using explicit subspace designs; **Kopparty & Saraf (2026, `arXiv:2607.15554`)** simplified the detection criterion using polynomial multiplicities.
2. **Primality Testing (`SZ-A05`, `SZ-A06`)**:
   - **Agrawal–Biswas (2003)** overcame the composite-ring failure of direct point evaluation on $(1+z)^n - 1 - z^n \pmod n$ via random modular polynomial quotients; **Agrawal–Kayal–Saxena (2004)** derandomized this identity test to prove `PRIMES in P`.
3. **Hardness vs. Derandomization & Non-Commutative PIT (`SZ-C01`–`SZ-C08`)**:
   - **Kabanets–Impagliazzo (2004)** proved that derandomizing Schwartz–Zippel (deterministic poly-time PIT) is equivalent to proving superpolynomial circuit lower bounds.
   - **Raz–Shpilka (2005)** and **Garg–Gurvits–Oliveira–Wigderson (2016/2020)** solved non-commutative formula/ABP PIT and the non-commutative Edmonds problem in deterministic polynomial time.
   - **Limaye–Srinivasan–Tavenas (2021 FOCS / 2025 JACM)** proved unconditional superpolynomial lower bounds for all constant-depth algebraic circuits, yielding deterministic sub-exponential PIT for constant-depth circuits.
   - **Atserias–Tzameret (2024, ECCC TR24-174)** linked feasibly constructive proofs of Schwartz–Zippel to the search complexity of hitting sets; **Andrews–Kush–Tell (2025, STOC 2025)** showed uniform lower bounds are nearly necessary and sufficient for polynomial-time PIT.
4. **Interactive Proofs & Zero-Knowledge Soundness (`SZ-P01`–`SZ-P03`)**:
   - **Lund–Fortnow–Karloff–Nisan (1992)** Sum-Check (`#P in IP`) and **Shamir (1992)** (`IP = PSPACE`) use degree-bounded univariate/multivariate root bounds in every round; **Thaler (2022)** anchors modern PIOPs and SNARK soundness directly in Schwartz–Zippel.
5. **Proof-Assistant Formalizations (`SZ-V01`–`SZ-V04`)**:
   - **Isabelle/HOL AFP**: Kim & Tan (2023, `Schwartz_Zippel`) and Garvía Bosshard–Sprenger–Bootle (2024, Sum-Check).
   - **Lean 4**: Bailey & Miller (USENIX Security 2024, Linear PCP SNARK soundness over `MvPolynomial`) and **Mathlib4** `Mathlib.Algebra.MvPolynomial.SchwartzZippel` (`schwartz_zippel_sup_sum`, `schwartz_zippel_sum_degreeOf`, `schwartz_zippel_totalDegree`).

---

## 5. Direct Bridge into SCargo's Riemann Lattice (`G_PLR`) & Probabilistic SWE-Sweep

The `PIT-SZ` tradition connects directly to two live SCargo pillars without conflating namespaces:

### 5.1 Live Algebraic Targets on the Neo-Riemannian *Tonnetz* Dual $G_{PLR}$
From [`riemann_lattice_graph_rh_v1.json`](../data/sources/riemann_lattice_graph_rh_v1.json), $G_{PLR} = \operatorname{Cay}(D_{12}, \{P, L, R\})$ has $12 \times 12$ bipartite circulant biadjacency matrix $B = I_{12} + C^4 + C^9$ ($36$ edges). Exact computation establishes:

- **Exact determinant & consistency check**: $\det(B) = \mathbf{45}$, so $\det(B)^2 = \mathbf{2{,}025}$, matching the exact constant term `2025` of $\det(y I_{12} - B B^\top)$ in `riemann_lattice_graph_rh_v1.json`.
- **Exact permanent (perfect matchings)**: $\operatorname{perm}(B) = \mathbf{113}$, so the symbolic Edmonds matrix $B(X)$ has $n = 36$ edge variables, exact total degree $d = 12$, and exactly **`113` distinct multilinear monomials** in $\det(B(X))$.
- **Why deterministic all-ones substitution fails in small characteristics**: Evaluating $\det(B(1, \dots, 1)) = 45$ vanishes modulo $p = 3$ and $p = 5$ (false negative!), even though $G_{PLR}$ has $113$ perfect matchings. Random evaluation over $\mathbb{F}_p$ eliminates this failure mode with exact one-sided error $\le (12 / p)^k$.
- **Exact PIT soundness envelopes** across `G_PLR` identities ($k$ independent trials over $\mathbb{F}_p$):

| `G_PLR` Polynomial Identity | Vars / Degree | $p = 101$ ($k=1$) | $p = 65{,}521$ ($k=1$) | $p = 2^{31} - 1$ ($k=4$) | $p = 2^{61} - 1$ ($k=4$) |
|---|---:|---:|---:|---:|---:|
| Edmonds matching $\det(B(X)) \not\equiv 0$ | 36 / $d = 12$ | $1.19 \times 10^{-1}$ | $1.83 \times 10^{-4}$ | $9.75 \times 10^{-34}$ | $7.34 \times 10^{-70}$ |
| Bass–Ihara $D(u)$ factorization | 1 / $d = 48$ | $4.75 \times 10^{-1}$ | $7.33 \times 10^{-4}$ | $2.50 \times 10^{-31}$ | $1.88 \times 10^{-67}$ |
| Full $\zeta_{G_{PLR}}(u)^{-1} = (1-u^2)^{12} D(u)$ | 1 / $d = 72$ | $7.13 \times 10^{-1}$ | $1.10 \times 10^{-3}$ | $1.26 \times 10^{-30}$ | $9.51 \times 10^{-67}$ |

### 5.2 Integration with SCargo's Probabilistic SWE-Sweep (`models/verification_methodology_model.md`)
Schwartz–Zippel provides the exact mathematical soundness law for SCargo's probabilistic verification layer:
- **Fast polynomial & matrix identity witnesses** (Freivalds $O(n^2)$ check for large integer/modular matrix identities, fast PIT pre-screening of candidate algebraic factorizations before committing full Lean kernel reduction).
- **Mandatory fail-closed ring guard**: Any probabilistic PIT guard in `SCargo` must explicitly verify that the sampling modulus is prime (integral domain) or that the sampling set satisfies **Condition (D)** before asserting a $(d/|S|)^k$ error envelope—preventing silent composite-ring soundness collapse.

---

## 6. Coupled `PIT-SZ × PLR` Architecture: Remedies & Algebraic Boundary

Coupling Schwartz–Zippel (`PIT-SZ`) with the Neo-Riemannian $PLR$ lattice (`RIEM-LATTICE`) resolves the two main bottlenecks that stall polynomial identity testing on raw binary grids:

1. **12-Fold Cyclotomic / Finite-Field Torus vs. Binary Grid (`{0, 1}` & $\mathbb{Z}/12\mathbb{Z}$)**:
   - Over a raw binary grid $S = \{0, 1\}$, total-degree ODLSZ (`TF-01`) stalls immediately at $D = 2$ (exact witness: $z^2 - z$ vanishes on 100% of $\{0, 1\}$). Over the composite ring $\mathbb{Z}/12\mathbb{Z}$, zero divisors collapse the maximum Condition (D) grid right back down to $p_{\min}(12) = 2$.
   - Over any prime field $\mathbb{F}_p$ with $p \equiv 1 \pmod{12}$ (verified for $p \in \{13, 37, 61, 97, 65521, 10^9 + 9\}$), $\mathbb{F}_p^\times$ contains an exact primitive 12th root of unity $\zeta_{12}$ satisfying $\Phi_{12}(\zeta_{12}) = \zeta_{12}^4 - \zeta_{12}^2 + 1 = 0$, giving a 12-point integral-domain torus $\mu_{12} \times \{+1, -1\} \subset \mathbb{F}_p^2$.
   - On $(z, \sigma) \in \mu_{12} \times \{+1, -1\}$, the generators $P, L, R$ act as **exact degree-$\le 2$ bilinear involutions**:
     $$g_s(z, \sigma) = \bigl(z \cdot (c_s + \sigma d_s),\; -\sigma\bigr), \quad c_s = \frac{\zeta_{12}^s + \zeta_{12}^{-s}}{2},\; d_s = \frac{\zeta_{12}^s - \zeta_{12}^{-s}}{2}$$
     with $s \in \{0, 4, 9\}$, exact involutivity $g_s^2 = \mathrm{id}$, exact isomorphism to $G_{PLR}$ on all 24 triads, and exact dihedral relations $(PL)^3 = (PR)^4 = (LPR)^2 = \mathrm{id}$, $PL \neq LP$.

2. **Non-Backtracking Ramanujan Mixing via the Hashimoto / Ihara Operator $T$**:
   - On the 72 directed edges of 12-TET $G_{PLR}$ ($q = d - 1 = 2$), the Graph Riemann Hypothesis ($\max \lambda_{\text{nontriv}}^2 = 5 < 8$) forces every nontrivial eigenvalue of the Hashimoto transition operator $\frac{1}{2} T$ to have exact modulus $\frac{1}{\sqrt{2}} \approx \mathbf{0.70711}$—strictly faster than the naive simple random walk $\frac{1}{3} A$ ($\frac{\sqrt{5}}{3} \approx 0.74536$) and Alon–Boppana optimal.
   - Crossing the Graph-RH boundary into non-Ramanujan **17-TET** ($\max \lambda_{\text{nontriv}}^2 = 8.20791 > 8$) introduces a real off-line Hashimoto eigenvalue that slows non-backtracking mixing to $0.83023$ (`TV_20 = 0.023924` vs. `0.000985` on 12-TET—a **24.3× degradation**).

3. **Unlocked Capabilities**:
   - **Non-Abelian Holonomy Verification**: Over $\mathbb{F}_p$ ($p \equiv 1 \pmod{12}$), the 2D dihedral irreps $\rho_1, \rho_5 : D_{12} \hookrightarrow \mathrm{GL}_2(\mathbb{F}_p)$ are **faithful** (`24/24` matrices, kernel size `1`), cleanly separating non-commuting words (`PL` vs. `LP`) via $O(1)$ Freivalds vector tests where 1D abelianization (`k = 0`) is blind.
   - **Representation / Homology-Filtered Cycle Sieving**: Lifting $P, L, R$ to Euler's 5-limit honeycomb vectors $e_P = (1, 0), e_L = (0, 1), e_R = (-1, -1)$ cleanly partitions all **192** closed tailless non-backtracking walks of length 6 into **144 contractible walks** (winding `(0, 0)` $\to$ `12` unoriented `LPRLPR` faces) and **48 non-contractible walks** (winding `(\pm 3, \mp 3)` $\to$ `4` unoriented `LPLPLP` hexatonic cycles), testable via twisted Artin–Ihara character PIT.
   - **Low-Entropy Identity Testing**: A $k$-step non-backtracking Ramanujan walk spends only $\log_2(24) + (k - 1)$ random bits (`1` bit/step since $q = 2$), cutting randomness by **3.17×** at $k = 8$ and **4.12×** at $k = 32$ compared to independent draws.

4. **Sharper Algebraic Boundary (Constraint Arity $r$ & Global Degree $D$)**:
   - Linear combinations of $m$ arity-$r$ constraints preserve degree $D = d_c$ and stay inside the non-vacuous ODLSZ regime. Conjunctive products or nonlinear compositions drive global degree $D = m \cdot d_c$ up until crossing the exact domain boundary:

| Sampling Domain | Safe Grid Size $|S|$ | Sharp Stall Degree $D$ | Exact Vanishing Witness |
|---|---:|---:|---|
| Binary grid `{0, 1}` | `2` | `2` | $z^2 - z$ |
| Composite ring $\mathbb{Z}/12\mathbb{Z}$ | `2` ($p_{\min}(12)$) | `2` | Zero-divisor collapse (`x(x-1)` has 4 roots) |
| 12-fold cyclotomic torus $\mu_{12} \subset \mathbb{F}_p^\times$ | `12` | `12` | $z^{12} - 1$ (holds for $D \le 11$, stalls at $D = 12$) |
| Full prime field $\mathbb{F}_p$ ($p \equiv 1 \pmod{12}$) | $p$ | $p$ | Frobenius $z^p - z$ (holds for $D \le p - 1$) |

---

## 7. Implemented & Verified Standalone Per-Language Machine Layer

The coupled `PIT-SZ × PLR` engine is implemented and pressure-tested **strictly standalone** in all three compartments (zero combo scripts, dynamic cross-vault loading from [`schwartz_zippel_research_v1.json`](../data/sources/schwartz_zippel_research_v1.json) and [`riemann_lattice_graph_rh_v1.json`](../data/sources/riemann_lattice_graph_rh_v1.json), fail-closed atomic boolean guards):

1. **Lean `v4.36.0` ([`SCargoLean/SchwartzZippel.lean`](../compartments/lean/SCargoLean/SchwartzZippel.lean) & [`SCargoLean/SchwartzZippelTest.lean`](../compartments/lean/SCargoLean/SchwartzZippelTest.lean))**:
   - **Pure-kernel proof** of universal multivariate Condition (D) Schwartz–Zippel (`schwartz_zippel_conditionD`) over arbitrary commutative rings and its integral-domain specialization (`schwartz_zippel_integral_domain`), using only standard Lean core axioms (`[propext, Classical.choice, Quot.sound]`, zero `sorry`, zero `native_decide`, zero `Lean.ofReduceBool`, zero external dependencies), verified by `leanchecker` and `leanexport`.
   - Pure-kernel proofs of `F_13` & `F_65521` bilinear `P, L, R` involutivity/isomorphism on all 24 triads, faithful `rho_1/rho_5` holonomy separation, length-6 homology cycle sieving (`144 + 48 = 192`), `perm(B) = 113` perfect matchings, `TF-01..TF-05` regime witnesses, sharp boundary witnesses (`z^2 - z`, `z^12 - 1`, `z^13 - z`), and standalone executable `sz_lattice_test` with cross-vault parity and adversarial negative controls.
2. **Rust `1.100.0` ([`scargo-schwartz-zippel`](../compartments/rust/crates/scargo-schwartz-zippel/src/sz_lattice.rs))**:
   - Zero external crates, `#![forbid(unsafe_code)]`, `-D warnings`, `clippy::all` clean.
   - Verifies all 6 cyclotomic primes (`13` through `10^9 + 9`), `rho_1..rho_5` holonomy + Freivalds separation, `72 × 72` Hashimoto non-backtracking vs. SRW mixing (12-TET vs. 17-TET Graph-RH breakdown), length-6 cycle sieving + twisted character PIT, low-entropy Ramanujan walk PIT + `D = 12` stall wall, exact `det(B) = 45` / `perm(B) = 113` Edmonds & Bass–Ihara PIT, DKSS Hasse multiplicity `15/15`, and Freivalds Gram verification (9/9 atomic guards PASS; 7/7 pressure tests PASS).
3. **Open-Source Swift `6.4.3` ([`SchwartzZippel.swift`](../compartments/swift/Sources/SchwartzZippel/SchwartzZippel.swift) & [`SchwartzZippelPressureTests.swift`](../compartments/swift/Tests/SchwartzZippelTests/SchwartzZippelPressureTests.swift))**:
   - Swift 6 `Sendable`, `.treatAllWarnings(as: .error)`, zero `try?`, typed `Decodable` cross-vault loader, guarded default `swiftbuild` (`0` warnings, `0` deprecations), standalone release CLI `scargo-schwartz-zippel` (9/9 atomic guards PASS), and Swift Testing adversarial pressure suite.
