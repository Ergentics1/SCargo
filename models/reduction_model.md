# Formal Mass-Budget & Reduction Model (`models/reduction_model.md`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

> **Separation Rule**: This document defines the **conceptual & quantitative model** only. All empirical parameter values are read from immutable datasets in [`data/baselines/`](../data/baselines/), [`data/traces/`](../data/traces/), and [`data/sources/`](../data/sources/).

## 1. Multi-Objective Size State Vector

Analogous to the Falcon Payload User's Guide mass/CG & keep-in volume state vector (§4.2, Appendix C), we model any snapshot $T$ of `Riemannian` by a five-component mass vector:

$$\mathbf{M}(T) = \bigl(F(T),\; L(T),\; B(T),\; E(T),\; C(T)\bigr)$$

where:
- $F(T)$ = tracked `.lean` file count,
- $L(T)$ = total source lines ($L_{\text{code}} + L_{\text{scaffold}} + L_{\text{blank}}$),
- $B(T)$ = total UTF-8 source bytes,
- $E(T)$ = exported kernel proof-term size (bytes / declarations in `lean4export`),
- $C(T)$ = total compilation CPU cost (core-hours) and critical-path depth (198 hops measured by `scargo-trace`).

## 2. Decomposition of Reducible Mass

We partition total line mass $L(T)$ into orthogonal compartments so reductions are neither double-counted nor conflated:

$$L(T) = L_{\text{unreach}} + L_{\text{wrap}} + L_{\text{scaffold}} + L_{\text{dead-decl/field}} + L_{\text{dup}} + L_{\text{explicit}} + L_{\text{core}}$$

| Component | Mechanism | Expected Leverage | Primary Confounder / Failure Mode |
|---|---|---|---|
| $L_{\text{unreach}}$ | Unreachable module pruning from `Main` | Immediate 100% of unreachable leaves (112 modules) | `lakefile.toml` `defaultTargets` globs |
| $L_{\text{wrap}}$ | `*Statement.lean` fallback wrapper aliasing/collapse | High file & line savings (36,255 files, 709,446 lines) | Binder-plicity collisions (`#138`), `open` namespace shadowing |
| $L_{\text{scaffold}}$ | Blank / repeated `import` / `open` / `set_option` overhead | Scales linearly with $F(T)$ (3,237,012 lines / 21.3%) | Tightly coupled to file-consolidation policy vs. build parallelism |
| $L_{\text{dead-decl/field}}$ | Declaration & structure-field liveness pruning (`#173`, `#151`) | ~12–22% of lines + cascading dead proofs | Tactic-referenced lemmas absent from final kernel term |
| $L_{\text{dup}}$ | Cross-tree proof reuse & `private theorem` factoring | Tens of thousands of lines per subtree; zero semantic risk | Import-cycle constraints and local visibility |
| $L_{\text{explicit}}$ | De-expanding `pp.explicit` typeclass dumps | 5×–20× compression per affected file (`CapelliIdentities`) | Definitional equality (`rfl`) & generated `*.eq_1` pinning |
| $L_{\text{core}}$ | Mathematical simplification along `scargo-trace` dominator spine | High-leverage subtree cuts (`RowSrc` 954.6kL / 12,425m [6.30%], `VwinOfRow` 685.3kL / 6,810m [4.52%], `SiegelEisensteinSecondTermHypotheses` 290.3kL / 3,863m [1.92%], and Behrend Iwasawa detour `SRC-04`) | Requires deep mathematical re-proof + full kernel verification |

## 3. Pareto Safety-Gated Objective

Any candidate transformation operator $\Phi$ tested in an RCT must satisfy:

$$\Delta \mathbf{M}(\Phi) < 0 \quad \text{on primary endpoint} \qquad \text{subject to} \qquad \text{SafetyGate}(\Phi(T)) = \text{true}$$

where $\text{SafetyGate}$ requires zero dangling imports, acyclic module DAG, byte-identical Zone A core, zero non-permitted axioms, and 100% pass across edited modules plus direct importers.
