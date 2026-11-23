-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

public import SCargoLean.Preflight.Mid

@[expose] public section

namespace SCargoLean.Preflight

/-- E3: Hub with transitively redundant `public import SCargoLean.Preflight.Leaf` PRUNED still resolves every `Leaf` declaration via `Mid`. -/
theorem hubSeesTransitiveLeaf (a b c : Nat) :
    z2ExplicitDump a b c = a * b + c ∧ leafIdTheorem a = rfl :=
  ⟨z2_eq1_preserved a b c, rfl⟩

theorem hubUsesMid (a b c : Nat) : z2ExplicitDump a b c = z2CleanDeexpanded a b c :=
  midUsesLeaf a b c

end SCargoLean.Preflight
