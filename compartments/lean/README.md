# Lean 4 Compartment (`compartments/lean`)

**Organization**: Ergentics · **Copyright**: © 2026 Ergentics, LLC (MIT License)

This compartment integrates **Lean 4** as a first-class language inside `SCargo`, pinned 1:1 to `Ergentics1/Riemannian`'s toolchain (`leanprover/lean4:v4.36.0`) and strict elaborator options (`autoImplicit = false`, `relaxedAutoImplicit = false`).

## Role in the Compartment Architecture

1. **Atomic Fail-Closed Contracts (`SCargoLean/Contract.lean`)**: Parameterized `GuardVerdict` primitives and 6 machine-checked soundness/non-opacity theorems (`warningAsError = true`, `linter.deprecated = true`, `linter.unusedVariables = true`).
2. **Import-Style Riemann Lattice Machine Layer (`SCargoLean/RiemLattice.lean`)**: Pure-kernel Lean `v4.36.0` formalization (zero `sorry`, zero `native_decide`, zero external deps) of Euler's 1730s-rooted Neo-Riemannian *Tonnetz* Dual $G_{PLR} = \operatorname{Cay}(D_{12}, \{P, L, R\})$, proving:
   - Universal $N$-TET involutivity and `T_n` commutation + 12-TET Crans–Fiore–Satyendra mutual centralizer duality (`applyPLR_parsimonious`, `plr_commutes_I`, `dihedral_D12_presentation`),
   - Simple 3-regular bipartite 24-vertex / 36-edge invariants (`G_PLR_graph_invariants`) and exact circulant biadjacency $I_{12} + C^4 + C^9$,
   - Exact $\mathbb{Z}$ Faddeev–LeVerrier characteristic polynomial $(y - 9)(y - 5)^2(y - 3)^2(y - 1)^3(y^2 - 4y + 1)^2$ and zero Cayley–Hamilton remainder (`G_PLR_charpoly_and_cayley_hamilton_exact`),
   - **Zero-axiom** algebraic Graph-RH Ramanujan bound (`G_PLR_nontrivial_root_satisfies_ramanujan_bound`) and critical-circle modulus $|u|^2 = \frac{1}{2}$ (`graph_rh_critical_circle_modulus`),
   - Exact $\mathbb{Z}[u]$ Bass–Ihara Schur-complement identity, palindromic functional equation $\Xi(2^{-s}) = \Xi(2^{-(1 - s)})$, exact Möbius prime-cycle counts up to $m = 20$, and the `12 LPRLPR + 4 LPLPLP = 16` minimal prime-hexagon decomposition.
3. **Standalone Runtime & Adversarial Test Driver (`SCargoLean/RiemLatticeTest.lean`)**: Runs full $12 \times 12$ matrix Faddeev–LeVerrier against `data/sources/riemann_lattice_graph_rh_v1.json` plus poisoned negative controls (`24-TET` disconnected, `17/53-TET` Ramanujan violations, tampered charpoly, banned wiki URLs).

## Standalone Verification Commands

```bash
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean build
LEAN_ABORT_ON_PANIC=1 lake --dir compartments/lean test
LEAN_PATH=compartments/lean/.lake/build/lib/lean leanchecker SCargoLean SCargoLean.Contract SCargoLean.RiemLattice
```
