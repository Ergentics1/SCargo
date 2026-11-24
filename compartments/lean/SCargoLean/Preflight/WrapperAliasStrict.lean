-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

public import SCargoLean.Preflight.Leaf

@[expose] public section

namespace SCargoLean.Preflight.WrapperAliasStrict

/-- Universe-polymorphic implementation theorem with implicit, instance, and explicit binders. -/
theorem implPoly.{u} {α : Type u} [Inhabited α] (x : α) : x = x := rfl

/-- Classical implementation theorem exercising `Classical.choice` inside `Prop`. -/
theorem implClassical {α : Type} [Nonempty α] : ∃ _ : α, True :=
  ⟨Classical.choice inferInstance, trivial⟩

/-- Mode A1 (core Lean 4.36): `abbrev` alias preserves exact implicit/instance/universe binder-plicity with 0 warnings. -/
abbrev _root_.SCargoLean.Preflight.WrapperAliasStrict.aliasPoly := @implPoly

/-- Mode A1 (core Lean 4.36): `abbrev` alias over a `Classical.choice` theorem requires zero `noncomputable`. -/
abbrev _root_.SCargoLean.Preflight.WrapperAliasStrict.aliasClassical := @implClassical

/-- Mode A2 (tight theorem): retains explicit signature while dropping multi-branch fallback tactic overhead. -/
theorem tightTheoremPoly.{u} {α : Type u} [Inhabited α] (x : α) : x = x :=
  @implPoly.{u} α _ x

/-- A1 Proof 1: Exact `@`-binder-plicity & proof-term definitional equality (`rfl`) across universe `u`. -/
theorem aliasPoly_preserves_at_plicit.{u} :
    @_root_.SCargoLean.Preflight.WrapperAliasStrict.aliasPoly.{u} = @implPoly.{u} := rfl

/-- A1 Proof 2: Direct implicit + typeclass-synthesized call works identically without `@`. -/
theorem aliasPoly_implicit_call_ok (n : Nat) :
    _root_.SCargoLean.Preflight.WrapperAliasStrict.aliasPoly n = rfl := rfl

/-- A1 Proof 3: Classical `abbrev` alias preserves exact `@`-equality (`rfl`) and synthesizes `Nonempty`. -/
theorem aliasClassical_preserves_at_plicit :
    @_root_.SCargoLean.Preflight.WrapperAliasStrict.aliasClassical = @implClassical := rfl

theorem aliasClassical_call_ok : ∃ _ : Nat, True :=
  _root_.SCargoLean.Preflight.WrapperAliasStrict.aliasClassical

/-- A2 Proof: Tight theorem preserves exact `@`-equality (`rfl`) with the underlying implementation. -/
theorem tightTheoremPoly_preserves_at_plicit.{u} :
    @tightTheoremPoly.{u} = @implPoly.{u} := rfl

/-- Transitive `public import` check: re-exports `leafIdTheorem` cleanly from `SCargoLean.Preflight.Leaf`. -/
abbrev _root_.SCargoLean.Preflight.WrapperAliasStrict.aliasLeaf := @SCargoLean.Preflight.leafIdTheorem

theorem aliasLeaf_preserves_at_plicit :
    @_root_.SCargoLean.Preflight.WrapperAliasStrict.aliasLeaf = @SCargoLean.Preflight.leafIdTheorem := rfl

end SCargoLean.Preflight.WrapperAliasStrict
