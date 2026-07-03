# Cpp Render Type-Flow Plan

This note records the bounded extraction plan for `haxe_ocaml-36ec`. It keeps
Cpp Gate3 work focused on repeated render-time type-flow decisions without
turning the Cpp emitter into a second typer or a broad runtime semantics sink.

Strict Cpp Gate3 remains red. This plan is blocker burn-down evidence only; it
does not move README or North Star production-readiness bars unless strict gates
and public usability evidence change.

CPP_RENDER_TYPE_FLOW_PLAN:PASS

## Current Repeated Paths

The Cpp backend currently resolves overlapping facts in several render paths:

- field-call rendering in `fieldCallExpr` computes static receiver ownership,
  receiver C++ type, primitive-backed abstract calls, known static calls, string
  receivers, vector receivers, and final call syntax.
- callable argument inference in `knownCallParams`, `knownCallDecl`,
  `ownerForKnownCall`, `renderClassMethodCallArgs`, and
  `renderInstanceMethodCallArgs` recomputes method declarations, owner classes,
  receiver types, and inferred parameter C++ types.
- return inference in `exprCppType`, `inferExprCppType`,
  `knownFieldCallReturnCppType`, `classMethodCppReturnType`, and
  `callableOrSameOwnerReturnCppType` re-enters the same receiver and method
  lookup facts.
- local preparation in `prepareFunctionScope` owns staged local/arg override
  inference, cache application, and late function signature inference through
  `functionScopePrepCache`, `functionArgTypesCache`, and
  `functionReturnTypesCache`.
- string/value conversion helpers such as `valueExprForExpectedType`,
  `stringExpr`, `isCppStringExpr`, and `eqComparableArgExpr` repeatedly probe
  `exprCppType` and `inferExprCppType` while rendering the same expression.

These paths are valid for current bring-up, but they make strict Cpp timing hard
to interpret: a timeout frontier can move because the same expression facts were
recomputed less often, not because helper body pressure or runtime behavior
actually improved.

## Extraction Boundary

The next implementation should introduce a small Cpp-owned render plan layer,
not a backend-neutral IR rewrite.

Start with a `CppFieldCallPlan` or `CppCallResolution` module that records:

- receiver expression kind;
- receiver C++ type, computed at most once per plan;
- static owner class, if the receiver is a type receiver;
- instance owner class, if the receiver type maps to a known class;
- method declaration and owner class, if known;
- inferred parameter C++ types;
- inferred return C++ type;
- selected render bucket: primitive intrinsic, known stdlib/static support,
  string/vector special case, class/static method, instance method, or fallback.

The plan should be created from existing typed/frontend-shaped data and should
reuse the existing lookup helpers. It must not infer new Haxe semantics, mutate
runtime-helper classification, or replace upstream Haxe 4.3.7 oracle evidence.

Keep the first implementation local to Cpp. A later extraction can move the
plan into its own file once the shape is stable, but the first slice should be
small enough to prove behavior unchanged with focused Cpp smoke coverage.

## Allowed During This Checkpoint

- bounded render/cache/inference optimizations;
- extra timing labels or summary scripts for existing Cpp trace output;
- helper classification and body-pressure accounting;
- call/field plan extraction that preserves existing generated output;
- cache-key cleanup for existing `functionScopePrepCache`,
  `functionArgTypesCache`, and `functionReturnTypesCache`;
- focused tests that compare generated source or runtime output before and
  after a non-semantic refactor.

## Blocked Without Separate Review

- new Serializer/Unserializer behavior;
- new Float/NaN/Infinity/Math/JSON/binary serialization behavior;
- new Reflect/Dynamic/default-stub behavior;
- moving broad runtime semantics from `CppTargetCore.hx` into
  `CppRuntimeSupport.hx` without classification;
- fake generated classes for runtime surfaces that should be declarations,
  runtime modules, templates, or intrinsic lowering;
- README or North Star progress-bar movement from internal Cpp timing frontier
  movement alone.

Use [`CPP_TARGET_RUNTIME_POLICY.md`](CPP_TARGET_RUNTIME_POLICY.md),
[`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md),
and [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before any
blocked semantic surface resumes.

## Diagnostics Contract

Existing Cpp tracing is the source of truth for deciding whether this plan
should be promoted from P2 to P1:

- `HXHX_TRACE_STAGE3_CPP_TIMINGS=1` enables Cpp timing output.
- `HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER=<Owner.method>` narrows
  statement/expression timing for a hotspot method.
- `render_helper_method_prepare_timing` and
  `render_helper_method_prepare_counts` measure `prepareFunctionScope` phases.
- `field_infer_known`, `field_infer_primitive`, `field_infer_static_owner`,
  `field_infer_receiver_type`, `field_infer_owner_type`, and
  `field_infer_instance_return` measure field-call return inference.
- `render_helper_expr_timing` lines tie expression phases to the filtered
  method and statement index.

Future implementation slices should compare the same command and timeout across
before/after runs, capturing:

- strict Cpp Gate3 elapsed frontier and failure mode;
- helper classes considered versus rendered;
- full-body versus declaration-only versus runtime-module helpers;
- top helper class and method render timings;
- prepare-scope timing for the filtered method;
- field-infer timing by phase for the filtered method;
- generated C++ line count.

## Validation

Use two validation tiers so Cpp timing work does not accidentally turn into an
hours-long serial gate.

Fast routine validation for bounded render-only changes:

- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-numeric-casts-render-bench`
- `npm run test:m14:cpp-native-backend-smoke`
- `npm run guard:cpp-render-type-flow-plan`

The helper-render bench is the fastest check for the shared helper frontier
that can block strict Cpp diagnostics before generated C++ exists. It parses a
small repo-owned utest-like fixture with `List`, `Dispatcher`, `TestHandler`,
`TestResult`, and a runner carrier, renders those helper classes directly, and
prints per-class latency. When `vendor/haxe` is present, the same bench also
renders the real vendored `haxe.ds.List` helper with the top-level `List` alias
loaded and reports `std_list_seconds`. That extra probe exists because the
strict Cpp logs identified the parsed stdlib List body as a render-time hot
spot. The production C++ path now treats stdlib `List` / `haxe.ds.List` as
target-owned runtime support, while arbitrary local classes named `List` still
use the ordinary helper renderer.

```bash
npm run test:m14:cpp-helper-render-bench
HXHX_CPP_HELPER_RENDER_BENCH_EXTRA_METHODS=64 npm run test:m14:cpp-helper-render-bench
```

The optional environment knobs are:

- `HXHX_CPP_HELPER_RENDER_BENCH_EXTRA_METHODS` scales repeated
  `TestHandler`-style methods when a renderer change needs more pressure than
  the default fixture.
- `HXHX_CPP_HELPER_RENDER_BENCH_REPS` controls how many cold helper-render
  passes are measured.

The numeric-casts render bench is the fastest check for the
`TestNumericCasts`-style `deq(expected, actual)` direct-call shape. It builds a
small repo-owned AST, renders one synthetic C++ helper method, asserts that
`deq` wrappers became direct `eq(...)` calls, and prints measured render
latency:

```bash
npm run test:m14:cpp-numeric-casts-render-bench
HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_CASES=1440 npm run test:m14:cpp-numeric-casts-render-bench
```

The optional environment knobs are:

- `HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_CASES` controls how many synthetic
  `deq(...)` call sites are rendered.
- `HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_HELPERS` controls how many same-owner
  numeric helper functions exist for method lookup pressure.
- `HXHX_CPP_NUMERIC_CASTS_RENDER_BENCH_REPS` controls how many repeated render
  passes are measured.

This bench intentionally avoids a hard wall-clock threshold because developer
machines and CI runners vary. Treat its `best_seconds` and `total_seconds`
output as comparable evidence when changing the renderer, and use the smoke
test plus guard to prove the targeted Cpp render behavior and architecture
contract stay wired without compiling the whole upstream strict workload.

Slow diagnostic validation for hotspot claims:

- strict Cpp timing probe with `HXHX_TRACE_STAGE3_CPP_TIMINGS=1` and a stable
  method filter when the current strict logs identify a type-flow hotspot;
- compare the same command and timeout before/after;
- if the probe times out before reaching render timing, record the timeout,
  elapsed/user CPU, and last trace phase in the bead instead of rerunning the
  same expensive command blindly.

README/North Star progress bars recorded as unchanged unless strict gate and
public usability evidence changes.

Promotion to P1 is justified only when latest strict Cpp logs show render/type
flow dominates after helper classification and runtime-helper policy work, or
when the same field/call inference hotspot repeats across multiple strict
frontiers.
