-- Copyright (c) 2026 Ergentics, LLC
-- Licensed under the MIT License. See LICENSE in the project root.

import SCargoLean.Contract
import SCargoLean.SweepWitness

/-!
# SCargo Lean Compartment: Rung 2 Shared Ground Codec, Metamorphic Invariance & Rung 1 Containment

Pure-kernel Lean 4.36.0 formalization of:
1. Shared GroundModule / GroundGraph schema and validation (no duplicate names, root present, no dangling imports).
2. Exact fixed-point reachability, Kahn topological cycle detection, dead-leaf partitioning, and mass conservation.
3. Wrapper AST classification with machine-checked comment/blank-line metamorphic invariance (MR-2).
4. Correspondence Principle theorem proving Rung 2 smoothly contains Rung 1 (delta_logic = 0).
-/

namespace SCargoLean.GroundCodec

open SCargoLean
open SCargoLean.SweepWitness

/-- Canonical wrapper classification shared across Lean, Rust, and Swift. -/
inductive WrapperKind where
  | pure_wrapper
  | reexport_hub
  | substantive
  deriving Repr, DecidableEq

/-- Returns true when a trimmed line is empty or a single-line Lean comment. -/
def isIgnorableLine (line : String) : Bool :=
  let t := line.trimAscii.toString
  t.isEmpty || t.startsWith "--"

def isSubstantiveDeclLine (line : String) : Bool :=
  let t := line.trimAscii.toString
  t.startsWith "theorem " || t.startsWith "lemma " || t.startsWith "def " ||
  t.startsWith "structure " || t.startsWith "inductive " || t.startsWith "class " ||
  t.startsWith "instance " || t.startsWith "abbrev " ||
  t.startsWith "private theorem " || t.startsWith "private def "

def isPublicImportLine (line : String) : Bool :=
  let t := line.trimAscii.toString
  t.startsWith "public import "

def isAnyImportLine (line : String) : Bool :=
  let t := line.trimAscii.toString
  t.startsWith "import " || t.startsWith "public import " ||
  t.startsWith "private import " || t.startsWith "meta import "

/-- Classifies a Lean module line list into pure_wrapper, reexport_hub, or substantive. -/
def classifyWrapperAux : List String → Nat → Nat → Bool → WrapperKind
  | [], impCount, pubCount, hasDecl =>
    if hasDecl then .substantive
    else if pubCount ≥ 2 then .reexport_hub
    else if impCount ≥ 1 then .pure_wrapper
    else .substantive
  | l :: ls, impCount, pubCount, hasDecl =>
    if isIgnorableLine l then
      classifyWrapperAux ls impCount pubCount hasDecl
    else
      let hasDecl' := hasDecl || isSubstantiveDeclLine l
      let pubCount' := if isPublicImportLine l then pubCount + 1 else pubCount
      let impCount' := if isAnyImportLine l then impCount + 1 else impCount
      classifyWrapperAux ls impCount' pubCount' hasDecl'

def classifyWrapperLines (lines : List String) : WrapperKind :=
  classifyWrapperAux lines 0 0 false

/-- MR-2 Metamorphic Invariance Theorem: prepending any blank or `--` comment line leaves wrapper classification unchanged. -/
theorem wrapper_ignores_ignorable_prefix (line : String) (lines : List String)
    (h : isIgnorableLine line = true) :
    classifyWrapperLines (line :: lines) = classifyWrapperLines lines := by
  simp [classifyWrapperLines, classifyWrapperAux, h]

/-- Shared Ground Module representation. -/
structure GroundModule where
  name : String
  lines : Nat
  bytes : Nat
  imports : List String
  deriving Repr, DecidableEq

/-- Shared Ground Import Graph. -/
structure GroundGraph where
  root : String
  modules : List GroundModule
  deriving Repr, DecidableEq

def moduleNames (g : GroundGraph) : List String :=
  g.modules.map (·.name)

def hasNoDuplicateNames : List String → Bool
  | [] => true
  | x :: xs => (!xs.contains x) && hasNoDuplicateNames xs

def graphValid (g : GroundGraph) : Bool :=
  let names := moduleNames g
  hasNoDuplicateNames names &&
  names.contains g.root &&
  g.modules.all (fun m => m.imports.all (fun imp => names.contains imp))

def importsOf (g : GroundGraph) (name : String) : List String :=
  match g.modules.find? (fun m => m.name == name) with
  | some m => m.imports
  | none => []

def addUnique (acc : List String) (items : List String) : List String :=
  items.foldl (fun a x => if a.contains x then a else x :: a) acc

def expandReachable (g : GroundGraph) : Nat → List String → List String
  | 0, visited => visited
  | fuel + 1, visited =>
    let nexts := visited.foldl (fun acc u => addUnique acc (importsOf g u)) visited
    if nexts.length == visited.length then visited
    else expandReachable g fuel nexts

/-- Exact fixed-point set of modules reachable from `g.root`. -/
def reachableFromRoot (g : GroundGraph) : List String :=
  if (moduleNames g).contains g.root then
    expandReachable g g.modules.length [g.root]
  else
    []

/-- Exact unreachable (dead-leaf) modules. -/
def deadLeaves (g : GroundGraph) : List String :=
  (moduleNames g).filter (fun name => !(reachableFromRoot g).contains name)

theorem dead_leaves_disjoint_from_reachable (g : GroundGraph) (name : String)
    (hdead : name ∈ deadLeaves g) :
    (reachableFromRoot g).contains name = false := by
  unfold deadLeaves at hdead
  rw [List.mem_filter] at hdead
  simpa using hdead.2

def sumLines (ms : List GroundModule) : Nat :=
  ms.foldl (fun acc m => acc + m.lines) 0

def sumBytes (ms : List GroundModule) : Nat :=
  ms.foldl (fun acc m => acc + m.bytes) 0

def totalMassLines (g : GroundGraph) : Nat := sumLines g.modules
def totalMassBytes (g : GroundGraph) : Nat := sumBytes g.modules

def reachableMassLines (g : GroundGraph) : Nat :=
  sumLines (g.modules.filter (fun m => (reachableFromRoot g).contains m.name))

def deadMassLines (g : GroundGraph) : Nat :=
  sumLines (g.modules.filter (fun m => !(reachableFromRoot g).contains m.name))

def reachableMassBytes (g : GroundGraph) : Nat :=
  sumBytes (g.modules.filter (fun m => (reachableFromRoot g).contains m.name))

def deadMassBytes (g : GroundGraph) : Nat :=
  sumBytes (g.modules.filter (fun m => !(reachableFromRoot g).contains m.name))

private theorem foldl_add_shift {α : Type} (f : α → Nat) (xs : List α) (init : Nat) :
    xs.foldl (fun acc x => acc + f x) init = init + xs.foldl (fun acc x => acc + f x) 0 := by
  induction xs generalizing init with
  | nil => simp
  | cons x xs ih =>
    simp only [List.foldl_cons, Nat.zero_add]
    rw [ih (init + f x), ih (f x)]
    omega

private theorem partition_sum_conserved {α : Type} (p : α → Bool) (f : α → Nat) (xs : List α) :
    (xs.filter p).foldl (fun acc x => acc + f x) 0 +
    (xs.filter (fun x => !p x)).foldl (fun acc x => acc + f x) 0 =
    xs.foldl (fun acc x => acc + f x) 0 := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    cases hp : p x with
    | true =>
      simp only [List.filter_cons, hp, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
        List.foldl_cons, Nat.zero_add]
      rw [foldl_add_shift f (xs.filter p) (f x), foldl_add_shift f xs (f x)]
      omega
    | false =>
      simp only [List.filter_cons, hp, Bool.not_false, Bool.false_eq_true, ↓reduceIte,
        List.foldl_cons, Nat.zero_add]
      rw [foldl_add_shift f (xs.filter (fun y => !p y)) (f x), foldl_add_shift f xs (f x)]
      omega

/-- Exact line-mass conservation theorem: reachable + dead = total for EVERY GroundGraph. -/
theorem mass_lines_conserved (g : GroundGraph) :
    reachableMassLines g + deadMassLines g = totalMassLines g := by
  exact partition_sum_conserved (fun m => (reachableFromRoot g).contains m.name) (·.lines) g.modules

/-- Exact byte-mass conservation theorem: reachable + dead = total for EVERY GroundGraph. -/
theorem mass_bytes_conserved (g : GroundGraph) :
    reachableMassBytes g + deadMassBytes g = totalMassBytes g := by
  exact partition_sum_conserved (fun m => (reachableFromRoot g).contains m.name) (·.bytes) g.modules

/-- Kahn topological peel over dependency lists: removes nodes whose imports are all already peeled. -/
def kahnPeel (g : GroundGraph) : Nat → List String → List String
  | 0, peeled => peeled
  | fuel + 1, peeled =>
    let ready := g.modules.filter (fun m =>
      !(peeled.contains m.name) && m.imports.all (fun imp => peeled.contains imp))
    if ready.isEmpty then peeled
    else kahnPeel g fuel (peeled ++ ready.map (·.name))

def hasCycle (g : GroundGraph) : Bool :=
  let peeled := kahnPeel g g.modules.length []
  decide (peeled.length < g.modules.length)

/-- Canonical verified fixtures: diamond DAG, reversed diamond DAG (MR-1), and self-loop cycle. -/
def diamondDag : GroundGraph :=
  { root := "Main"
    modules :=
      [ { name := "Main", lines := 10, bytes := 200, imports := ["A", "B"] }
      , { name := "A",    lines := 20, bytes := 400, imports := ["Base"] }
      , { name := "B",    lines := 30, bytes := 600, imports := ["Base"] }
      , { name := "Base", lines := 40, bytes := 800, imports := [] }
      , { name := "Dead", lines := 50, bytes := 1000, imports := ["Base"] } ] }

def diamondDagReversed : GroundGraph :=
  { root := "Main"
    modules := diamondDag.modules.reverse.map (fun m => { m with imports := m.imports.reverse }) }

def selfLoopGraph : GroundGraph :=
  { root := "Loop"
    modules := [ { name := "Loop", lines := 5, bytes := 100, imports := ["Loop"] } ] }

theorem diamond_dag_acyclic_and_mr1_invariant :
    graphValid diamondDag = true ∧
    hasCycle diamondDag = false ∧
    hasCycle diamondDagReversed = false ∧
    (reachableFromRoot diamondDag).length = 4 ∧
    (reachableFromRoot diamondDagReversed).length = 4 ∧
    (deadLeaves diamondDag).length = 1 ∧
    (deadLeaves diamondDagReversed).length = 1 := by
  decide

theorem self_loop_is_cyclic :
    graphValid selfLoopGraph = true ∧ hasCycle selfLoopGraph = true := by
  decide

/-- Rung 2 Correspondence Receipt embedding the complete Rung 1 13-witness suite. -/
structure Rung2Receipt where
  rung1Witnesses : List CompartmentWitness
  corpusCasesPerFamily : Nat
  minCasesRequired : Nat
  metamorphicMismatches : Nat
  shrinkingViolations : Nat
  malformedEscapes : Nat
  parityMismatches : Nat
  deriving Repr, DecidableEq

def rung2AllPass (r : Rung2Receipt) : Bool :=
  suiteAllPass r.rung1Witnesses &&
  decide (r.corpusCasesPerFamily ≥ r.minCasesRequired) &&
  (r.metamorphicMismatches == 0) &&
  (r.shrinkingViolations == 0) &&
  (r.malformedEscapes == 0) &&
  (r.parityMismatches == 0)

/-- Correspondence Principle (Rung 1 -> Rung 2): Rung 2 smoothly contains Rung 1 (delta_logic = 0). -/
theorem rung2_smoothly_contains_rung1 (r : Rung2Receipt) (h : rung2AllPass r = true) :
    suiteAllPass r.rung1Witnesses = true := by
  simp [rung2AllPass, Bool.and_eq_true] at h
  exact h.1.1.1.1.1

end SCargoLean.GroundCodec
