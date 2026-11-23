-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

public import SCargoLean.Preflight.Leaf

@[expose] public section

namespace SCargoLean.Preflight

/-- Intermediate module that publicly re-exports `Leaf` for Z-C4 transitive import closure testing. -/
theorem midUsesLeaf (a b c : Nat) : z2ExplicitDump a b c = z2CleanDeexpanded a b c :=
  congrFun (congrFun (congrFun z2_defeq_rfl a) b) c

end SCargoLean.Preflight
