# Second-pass design review: nested place-plan ownership

## Verdict

The change is narrow and sound. It makes syntax use the same root function
identity that the final assignment planner used, while leaving nested call,
control-flow, and `IMap` behavior bound to each nested function's own plan.

## Ownership check

`OcamlFunctionPlanSealer` first creates nested behavior plans, then walks the
root function's complete typed expression tree. That final walk includes local
functions and registers every marked assignment or update with the root
function binding. It does not create per-nested-function place plans.

`OcamlBuilder` now names that existing ownership rule directly:

- `currentFunctionPlanBinding` still changes when syntax enters a nested
  function, so calls and control flow use the nested plan that owns them.
- `currentPlacePlanBinding` is installed once for the root function and stays
  unchanged while syntax visits nested functions, so assignments use the root
  place plan that owns them.
- The prior place binding is saved and restored with the other request-local
  builder state when the root function finishes.

The builder does not rediscover evaluation order, conversions, carriers,
runtime requirements, or assignment results. It only supplies the planner's
exact owner identity to the unchanged fail-closed resolver.

## Failure-safety check

No resolver check was weakened. A missing marker, unknown origin, wrong body,
wrong program, wrong pipeline, wrong operation, or corrupted report still
fails before source publication. The root pipeline revision moved from v81 to
v82 because the plan-consumption contract changed; exact validators and
deterministic reports were updated together.

The six regenerated reports retain every existing `*Count` value. Their large
diffs come from content-addressed identities that include the pipeline
revision, not from silently changed test coverage.

## Behavior and regression check

The focused fixture uses an indexed assignment inside two local functions. It
was red before the change with the same root-versus-twice-nested binding
mismatch as the compiler-scale source, then built and ran after the change.

The independent Haxe 4.3.7 oracle records a real target disagreement instead
of inventing one universal answer: interpreter and JavaScript agree with the
existing OCaml source-order contract, Neko swaps receiver/index order, and
Python repeats both after the store.

Verification passed:

- the focused nested-place build, native run, and exact report checks;
- the existing 29-case place-evaluation oracle;
- the local storage, representation, static storage, call, anonymous
  structure, array-literal, and Bytes plan chain;
- formatting, local-path, handwritten-OCaml ownership, and whitespace guards;
- all 107 portable compiler/runtime fixtures; and
- compiler scale past the former `EmitterStage.hx:8066` failure.

Compiler scale now stops later with an evaluator stack overflow rethrown at
`ReflectCompiler.hx:249`. That wrapper line is not the cause. The independent
localization work is tracked by `haxe_ocaml-9bome.17`.

## Scope check

No generated OCaml or handwritten OCaml was edited. No `Obj.magic`, fallback,
Stage3 exception, output repair, report-schema expansion, or readiness claim
was added. README Goals remain unchanged because this fixes one compiler-scale
boundary but does not close a user-visible product route.

## Independent-review disposition

An Oracle review was deliberately not requested. The red fixture, sealer walk,
builder lifecycle, unchanged fail-closed resolver, full portable portfolio,
and compiler-scale advance all converge on one bounded ownership model. If the
new stack-overflow task reveals competing whole-program recursion models, its
stop condition requires a separate architecture review.
