# Bend2-Inspired hxb Dialect Decision

Status: accepted as low-priority research; nothing implemented in this repository yet

Owning epic: `haxe_ocaml-frrmo`

First experiment: `haxe_ocaml-frrmo.1`

Priority: **below every compiler-foundations task.** Haxe 4.3.7 parity, native
self-hosting, and the native plugin SDK always come first.

## The short version

[Bend2](https://bend2.dev/notes/what-is-bend2/) is a young functional language
with two attractive properties: machine-checked proofs, and programs that run in
parallel on CPU cores and GPUs. The owner asked whether hxhx could offer the same
two things.

The answer is **yes, for a marked part of a Haxe program, without changing Haxe**:

1. You mark a class with `@:hxb`. Its functions must follow Bend2's rules: no side
   effects, each closure and each marked value is used by one owner, and every
   recursive call receives a smaller part of its input.
2. A check after typing rejects code that breaks a rule and names the file and
   line. The code keeps its ordinary Haxe meaning, so it still compiles with stock
   Haxe and runs on every Haxe target.
3. You write the **implementation in Haxe**. Simple laws are proved automatically
   by a solver. Hard laws are proved in **Bend2 (or Lean)** against definitions
   that hxhx exports from the Haxe code.
4. For speed, checked functions get a faster code path on the OCaml target and an
   explicit `Par.both(...)` fork-join on CPU cores. GPU work waits for a real
   workload.

"hxb" is a placeholder name.

## A small example

This is valid Haxe. The research prototype checks it and runs it with identical
results on the Haxe interpreter, JavaScript, and the OCaml target on 1 and 8 cores.

```haxe
@:hxb @:hxb.affine enum Tree { Leaf(x:U32); Node(l:Tree, r:Tree); }

@:hxb class Kernel {
	public static function sum(t:Tree):U32
		return switch t {
			case Leaf(x): x;
			case Node(l, r): Par.both(sum(l), sum(r), (a, b) -> a + b);
		}
}
```

The same check rejects, for example, `f(f(x))` when `f` is a closure with one
owner, an assignment to a field, a call to `trace`, and a recursive call that does
not shrink an input.

## Constraints that must always hold

- **Superset, not a fork.** The mode is opt-in and off by default. Annotations are
  ordinary metadata. There is no parser, resolver, or typer change. Ordinary Haxe
  compiles and behaves exactly as with upstream Haxe 4.3.7.
- **No effect when off.** With the mode off, compiler output is byte-identical.
  Parity and release jobs run with the mode off.
- **Haxe-authored semantics.** The check, the exporters, and the code generators
  are Haxe code. Solvers and provers are external processes, like `dune`.
- **Honest claims.** A solver timeout or "unknown" is never reported as proved.
  Proof results are tied to the exact code revision and are invalidated when the
  code, a macro result, or a callee changes.

## How proofs work

| Kind of law | Where it is proved | Example |
|---|---|---|
| Simple facts about integers, enums, and branches | An SMT solver such as Z3, directly from the typed Haxe code | "cancelling an order twice equals cancelling it once" |
| Laws that need induction or helper lemmas | A separate Bend2 or Lean file, against exported definitions | "reversing a list twice gives the original list" |

An SMT solver is a program that decides whether a logical formula can be false
and, if so, returns the input that makes it false. The research prototype proved
8 laws, refuted 2 with concrete counterexamples (one was an `Int` overflow nobody
expected), and returned "unknown" for 2 laws that need induction.

What a proof covers, precisely:

- A Bend2 or Lean proof covers the **exported model** of the code, not the code
  that a Haxe compiler emits. The exporter is trusted. Random-input cross-checks
  between the exported model and the Haxe build reduce that gap.
- Haxe does not define `Int` overflow the same way on every target. The dialect
  therefore fixes 32-bit integers, or the proof must show that no overflow occurs.
  `Float` stays out of proofs, because Bend2 cannot prove floating-point facts.
- The Haxe compiler and the target compiler stay trusted, as in every
  "prove, then compile" setup without a verified compiler.

## How speed works

| Step | What it delivers | Status |
|---|---|---|
| `Par.both` over OCaml 5 domains | Explicit fork-join on CPU cores | Prototype: 5x to 7x on 8 cores |
| Code generator for checked functions on the OCaml target | Plain OCaml without null and exception handling | Prototype: 3x to 4x on integer code |
| C generator for checked functions | C-class speed on one core, memory freed at each `match` | Later, only for a real workload |
| GPU kernels for flat numeric loops | 10x or more on uniform numeric grids | Later, only for a real workload |

Not pursued: a Bend2 or HVM target for ordinary Haxe, an hxhx-owned copy of
Bend2's GPU runtime, dependent types in the hxhx typer, and automatic
parallelization of ordinary Haxe.

Known blocker before parallel use is safe: tasks that read a shared anonymous
structure gave silently wrong results, consistent with the lookup cache in
`HxAnon.get` (`haxe_ocaml-frrmo.2`). The dialect's data model, numbers and enums
only, avoids that helper.

## Where it plugs into hxhx

| Part | Seam |
|---|---|
| Types (`U32`, `Nat`) and `Par` | An ordinary Haxe library |
| The check, first version | A macro on `Context.onAfterTyping`, which also runs on stock Haxe |
| The check, native version later | A policy and diagnostic customization, enabled like `--hxhx-customization <id>` |
| Faster OCaml for checked functions | One more direct lowering inside the OCaml target |
| Bend2 or Lean exporter, C generator | A backend or target plugin through the planned SDK |
| New syntax or dependent types | A compiler variation. **Not pursued.** |

These seams come from `HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md` and
`HXHX_HAXE_FAMILY_VARIATION_WORKFLOW.md`. The workflow's rule applies: "If the
behavior can be removed and the baseline compiler still behaves exactly the same,
start with a plugin or customization."

## Why not just write Bend2?

If a whole program has Bend2's shape and the GPU is the goal, Bend2 is the better
tool. The dialect is worth having when the pure core is one part of a Haxe
application, when it must run where Bend2 does not (Windows, every Haxe target),
or when a team wants Haxe tooling: type inference, `if`, nested `switch`, macros,
editor support, and test libraries. Bend2 itself was public for seven weeks at the
time of this decision and released 41 versions in that period.

## First experiment

`haxe_ocaml-frrmo.1`, time box 2 to 3 weeks:

1. The owner selects one real pure core of 500 to 1,000 lines.
2. Port it to the dialect. Prove some laws with the solver. Export a few functions
   to a pinned Bend2 version in a sandbox and prove two or three laws there.
3. Measure the OCaml generator and `Par`. Cross-check results on 10,000 random
   inputs across three targets and the Bend2 model.

Success: 80% or more of the functions pass the check after mechanical edits;
equal results everywhere; 3x or more from the generator and 4x more on 8 cores;
byte-identical output with the mode off; at least two non-trivial laws proved in
Bend2.

Kill: fewer than 50% of the functions pass without hurting readability; the port
needs new syntax or dependent types; the generator gives less than 2x; Bend2
releases break the exporter more than once a month.

## Open owner decisions

1. Which real pure core the experiment uses.
2. Where the dialect library lives. A separate repository is recommended, so no
   release or parity job can depend on it.
3. Permission to run the Bend2 compiler in a sandbox.
4. The required assurance for hard laws: Bend2, Lean, or either per project.
5. Whether a GPU workload exists. Without one, there is no GPU work.

## Evidence

- Oracle (GPT-6 Pro, plan mode) consultation `orq_20261116T165336Z_d36ac3bb`, with
  verified access to a bundle of this repository at `b60185ee8`.
- Two Fable research reports from the same day, including the experiments above.
  They used an Apple M2 Pro, Haxe 4.3.7, OCaml 5.4.0, and Z3 4.15.4. They did not
  run Bend2. Bend2 numbers come from its authors.
- The research prototypes (check, OCaml printer, `Par` library, solver macro,
  effect census) and the Oracle answer are kept outside this repository in
  `~/workspace/code/hxb-dialect-research` on the owner's machine.

Two compiler bugs found during the research are tracked as ordinary compiler work:
`haxe_ocaml-oxjcd` (`Std.string` of an enum value) and `haxe_ocaml-9i0pk`
(`Null<Int>` passed to an abstract-over-`Int` parameter).

README Goals status and progress bars are unchanged by this decision.
