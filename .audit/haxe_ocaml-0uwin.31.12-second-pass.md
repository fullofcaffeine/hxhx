# Second-pass review: standard Array mutation calls

## Outcome

The change is safe to close as a five-operation hard cut. Final typed calls to
`push`, `pop`, `shift`, `unshift`, and `reverse` on the root Haxe `Array<T>`
now carry their meaning into OCaml syntax generation. The syntax builder only
renders that checked plan; it no longer chooses these operations from a method
name late in compilation.

## Type and operation identity

Selection requires the real root `Array` declaration, the operation's exact
argument count, and the final typed call result. A user-defined class with a
field named `push` or `pop` cannot enter this path.

The plan keeps a formal parameter type separate from the source expression's
actual type. This matters for valid code such as `Array<Dynamic>.push("x")`:
the parameter is `Dynamic`, but the argument expression is `String`. The Haxe
typing result supplies an explicit compatibility proof; the OCaml target does
not try to recreate Haxe assignability from type-name strings.

`push` returns `Int`. `pop` and `shift` return `Null<T>`, including a real null
for an empty array. `unshift` and `reverse` are effect-only calls whose Haxe
result is `Void`. Focused corruption cases reject a wrong operation, formal or
actual type, compatibility proof, nullability, result kind, or call result.

## Evaluation and OCaml calling convention

The schedule evaluates the receiver once before any argument and evaluates
each argument once in source order. The Array runtime tracer verifies this for
`push` and `unshift`, and it verifies once-only receiver evaluation for
`pop`, `shift`, and `reverse`.

The runtime interface has one target-specific detail that must be explicit:
`pop`, `shift`, and `reverse` take a trailing OCaml `unit` argument, while
`push` and `unshift` do not. This convention is sealed in the typed call target
and covered by a deliberate corruption test. The builder does not infer it
from the selected function name.

## Runtime authority and reports

Each generated `HxArray` reference is authorized by one immutable runtime-use
occurrence tied to the exact call, plan revision, source span, expression
domain, profile, and runtime requirement. The focused suite rejects missing,
duplicate, stale, foreign-owner, wrong-profile, wrong-domain, and plain
unowned references.

The lowering report exposes the operation, source and parameter types,
compatibility proofs, result kind, unit convention, runtime symbol, and use
occurrences. Public inspection reconstructs and validates those facts. Its
corruption fixture changes the unit convention and confirms that inspection
fails instead of trusting the report text.

## Determinism and inventory

The function-plan revision is `v88`, the standard Array call model is `v22`,
and the lowering schema is 73. Six affected lowering goldens were regenerated
with the repository's two-run deterministic update path and then passed in
normal comparison mode.

The private-runtime inventory falls exactly from 351 to 346. Only the five
late source-method references were removed. Three different internal
`HxArray.push` uses remain because they build compiler/runtime data rather than
implementing source `Array.push`; removing them in this slice would have
broadened the claim.

## Claim boundary

Independent upstream-Haxe behavior and generated-OCaml build/run checks pass.
No generated OCaml was edited, no handwritten OCaml semantic owner was added,
and no README goal or readiness claim moved. Other Array operations, runtime
source-selection authority, and the remaining 346 migration inventory rows
stay open under the parent Bead.

Oracle review was deliberately skipped. The existing sealed-call boundary was
clear, both unexpected failures had bounded causes, and focused plus vertical
evidence converged without an unresolved architecture question.
