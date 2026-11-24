-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

@[expose] public section

namespace SCargoLean.Preflight

/-- Multi-line pretty-printer `@`-instance dump mirroring Z-C2 `CapelliIdentities` bloat. -/
def z2MultilineDump (a b c : Nat) : Nat :=
  (@HAdd.hAdd
    Nat
    Nat
    Nat
    (@instHAdd
      Nat
      instAddNat)
    (@HMul.hMul
      Nat
      Nat
      Nat
      (@instHMul
        Nat
        instMulNat)
      a
      b)
    c)

/-- Token-identical layout-free collapsed form (`<= 160`-char wrap, zero layout keywords inside span). -/
def z2Wrapped160 (a b c : Nat) : Nat :=
  (@HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat) (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c)

/-- Guarded closed-subtree (`0` free local variables) `abbrev` hoisted inside `@[expose] public section`. -/
abbrev _scargo_inst_nat_add : HAdd Nat Nat Nat := (@instHAdd Nat instAddNat)

/-- Guarded closed-subtree (`0` free local variables) `abbrev` for `Nat` multiplication instance. -/
abbrev _scargo_inst_nat_mul : HMul Nat Nat Nat := (@instHMul Nat instMulNat)

/-- Closed-subtree CSE rewritten form using the `0`-free-variable public `abbrev`s. -/
def z2ClosedCse (a b c : Nat) : Nat :=
  @HAdd.hAdd Nat Nat Nat _scargo_inst_nat_add (@HMul.hMul Nat Nat Nat _scargo_inst_nat_mul a b) c

/-- P2: Exact definitional equality (`rfl`) between multi-line `@`-dump and `<= 160` token-identical collapse. -/
theorem z2_compact_defeq_rfl : z2MultilineDump = z2Wrapped160 := rfl

/-- P2: Exact `*.eq_1` equation-lemma preservation for `z2Wrapped160`. -/
theorem z2_compact_eq1_preserved (a b c : Nat) :
    z2MultilineDump a b c = a * b + c :=
  z2Wrapped160.eq_1 a b c

/-- P3: Exact definitional equality (`rfl`) between multi-line `@`-dump and closed-subtree `abbrev` CSE. -/
theorem z2_closed_cse_defeq_rfl : z2MultilineDump = z2ClosedCse := rfl

/-- P3: Exact `*.eq_1` equation-lemma preservation for `z2ClosedCse` inside Lean 4.36 `module`. -/
theorem z2_closed_cse_eq1_preserved (a b c : Nat) :
    z2MultilineDump a b c = a * b + c :=
  z2ClosedCse.eq_1 a b c

end SCargoLean.Preflight
