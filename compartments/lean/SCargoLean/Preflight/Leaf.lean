-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

@[expose] public section

namespace SCargoLean.Preflight

/-- Sample theorem with implicit type binder and explicit value binder for Z-C1A binder-plicity testing. -/
theorem leafIdTheorem {α : Type} (x : α) : x = x := rfl

/-- Sample definition with implicit, instance, and explicit binders. -/
def leafScaled {n : Nat} [Inhabited Nat] (x : Nat) : Nat := x + n

/-- Explicit `@`-expanded definition mirroring Z-C2 `pp.explicit` output. -/
def z2ExplicitDump (a b c : Nat) : Nat :=
  @HAdd.hAdd Nat Nat Nat (@instHAdd Nat instAddNat)
    (@HMul.hMul Nat Nat Nat (@instHMul Nat instMulNat) a b) c

/-- Clean de-expanded definition produced by Z-C2 simplification. -/
def z2CleanDeexpanded (a b c : Nat) : Nat :=
  a * b + c

/-- E2: Exact definitional equality (`rfl`) between explicit `@`-dump and clean de-expanded term. -/
theorem z2_defeq_rfl : z2ExplicitDump = z2CleanDeexpanded := rfl

/-- E2: Exact `*.eq_1` equation-lemma compatibility after Z-C2 de-expansion. -/
theorem z2_eq1_preserved (a b c : Nat) : z2ExplicitDump a b c = a * b + c :=
  z2CleanDeexpanded.eq_1 a b c

end SCargoLean.Preflight
