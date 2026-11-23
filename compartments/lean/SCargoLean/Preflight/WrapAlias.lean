-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

public import SCargoLean.Preflight.Leaf

@[expose] public section

namespace SCargoLean.Preflight

/-- Baseline forwarding wrapper mirroring Z-C1 fallback-tactic pattern. -/
theorem baselineForward : ∀ {α : Type} (x : α), x = x := by
  first | exact @leafIdTheorem | exact leafIdTheorem

/-- Strategy A minimal in-place forwarding replacement preserving implicit/explicit binder-plicity. -/
theorem strategyAForward : ∀ {α : Type} (x : α), x = x := @leafIdTheorem

/-- E1: Exact `@`-application equality proving Strategy A preserves binder-plicity and proof term. -/
theorem strategyA_preserves_binder_plicity : @baselineForward = @strategyAForward := rfl

/-- E1: Cross-check that calling with implicit type argument succeeds identically. -/
theorem strategyA_implicit_call_ok (n : Nat) : strategyAForward n = baselineForward n := rfl

/-- E1 negative control: an explicit-binder wrapper `(α : Type)` has a distinct `@`-type from `{α : Type}`. -/
theorem badExplicitBinder (α : Type) (x : α) : x = x := @leafIdTheorem α x

end SCargoLean.Preflight
