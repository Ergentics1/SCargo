-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

module

@[expose] public section

namespace SCargoLean.Preflight.PrivateDedupe

/-- Canonical promoted shared helper representing a Z-C3 deduplicated self-contained lemma. -/
theorem sharedSelfContainedHelper (a b : Nat) (h : a = b) : b + 1 = a + 1 := by
  rw [h]

namespace ConsumerAlpha
/-- Baseline duplicate private helper prior to Z-C3 deduplication. -/
private theorem dupHelper (a b : Nat) (h : a = b) : b + 1 = a + 1 := by
  rw [h]

/-- Post-deduplication caller delegating directly to the canonical promoted helper. -/
theorem alphaMain (x y : Nat) (h : x = y) : y + 1 = x + 1 :=
  SCargoLean.Preflight.PrivateDedupe.sharedSelfContainedHelper x y h

theorem alphaBaseline (x y : Nat) (h : x = y) : y + 1 = x + 1 :=
  dupHelper x y h

/-- Exact proof-term equivalence (`rfl`) between duplicated private helper and promoted canonical helper. -/
theorem alpha_dedupe_defeq : @alphaMain = @alphaBaseline := rfl
end ConsumerAlpha

namespace ConsumerBeta
/-- Second independent consumer namespace delegating to the same canonical helper without cycles. -/
private theorem dupHelper (a b : Nat) (h : a = b) : b + 1 = a + 1 := by
  rw [h]

theorem betaMain (x y : Nat) (h : x = y) : y + 1 = x + 1 :=
  SCargoLean.Preflight.PrivateDedupe.sharedSelfContainedHelper x y h

theorem betaBaseline (x y : Nat) (h : x = y) : y + 1 = x + 1 :=
  dupHelper x y h

/-- Exact proof-term equivalence (`rfl`) in the second consumer namespace. -/
theorem beta_dedupe_defeq : @betaMain = @betaBaseline := rfl
end ConsumerBeta

/-- Cross-consumer agreement proving single-definition promotion satisfies both consumers identically. -/
theorem cross_consumer_dedupe_rfl :
    @ConsumerAlpha.alphaMain = @ConsumerBeta.betaMain := rfl

end SCargoLean.Preflight.PrivateDedupe
