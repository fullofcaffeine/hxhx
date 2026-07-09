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
  `functionReturnTypesCache`. Cheap syntax-only preconditions that are proven
  safe, such as bind-callable evidence checks, live outside the main emitter so
  no-op inference guards do not add more traversal logic to `CppTargetCore`.
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
- syntax guards for prep local-inference phases when the guard is conservative,
  focused on one proven no-op seam, and covered by direct predicate tests;
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
- `scripts/ci/cpp-strict-frontier-summary.js` compares one or more strict Cpp
  timing logs and emits `CPP_STRICT_FRONTIER_SUMMARY:PASS` with a classification:
  `repeated-frontier`, `shared-hotspots-moving-frontier`, `moving-frontier`, or
  `single-log`.

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
- `npm run test:m14:cpp-strict-frontier-summary`
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

## 2026-07-09 Bind Evidence Guard Checkpoint

After moving `Bytes`, `BytesBuffer`, and base `haxe.io.Input`/`Output` helper
surfaces to target-owned runtime modules, the strict current-source Cpp probe
still timed out at 360s. The next dominant completed class was
`TestBasetypes` at about 42.18s; filtered timing for
`TestBasetypes.testAbstractCast` showed `prepareFunctionScope` cache-miss work
at about 4.49s before cached replays dropped to near-zero.

The retained bounded seam is `CppPrepLocalInferenceGuard`, limited to a cheap
`.bind` evidence scan for `infer_bind_callable_locals`. That phase already
collects unhinted local-lambda candidates. When candidates exist but the method
body contains no `.bind` expression, the expensive evidence walk cannot produce
an override, so the pass now restores local scope state and returns early.

A broader multi-phase prep guard was tried first and rejected: the strict 360s
probe regressed from reaching past `TestBasetypes` to timing out around
`TestOps`. That evidence keeps the current slice narrow. Other prep phases,
including `infer_dynamic_locals`, remain on their existing behavior because the
`testAbstractCast` timing probe showed dynamic inference produced real local
overrides.

The syntax-only guard lives outside `CppTargetCore` to avoid adding another
traversal subsystem to the mega-file. `CppTargetCore` still owns the real
bind-callable inference and only calls the guard after local lambda candidates
are known.

Focused coverage lives in
`test/M14CppNativeBackendSmokeIntegrationTest.hx` and asserts both no-trigger
skips and positive `.bind` trigger cases. Strict Cpp remains red until the 360s
probe completes; this checkpoint is render/type-flow burn-down evidence only,
so README and North Star progress bars stay unchanged.

Post-change filtered timing for `TestBasetypes.testAbstractCast` reduced
`infer_bind_callable_locals` from about 1.95s to about 0.50s, total prep
cache-miss time from about 4.49s to about 3.31s, and the filtered method from
about 11.51s to about 10.62s. The strict 360s probe still timed out
(`probe_exit=124`) and stopped around the `UInt` frontier, so this is not a
strict gate pass or a production-readiness change.

The next repeated hotspot was not another prep pass. Filtered timing showed
direct `eq(tpl.get().execute(...), "...")`, anonymous-field
`obj.tpl.get().execute(...)`, and array-element `arr[i].get().execute(...)`
expressions spending about 0.13-0.15s in first-argument inference and about
0.32-0.48s in first-argument rendering each time because the generic field-call
path did not know the generated `TemplateWrap` value-wrapper surface.

`TemplateWrap` is already a target-owned C++ value wrapper. The bounded seam is
therefore to recognize value-wrapper `get()`, `execute(...)`, and `toString()`
as generated support methods in Cpp type/render flow rather than adding a broad
expression cache. Focused smoke coverage asserts that both direct
`tpl.execute("ok")` and nested `tpl.get().execute("ok")` render as typed
`std::string` calls without fallback stringification.

Post-change direct current-source timing with the same
`TestBasetypes.testAbstractCast` filter reduced the repeated `get().execute`
`eq_infer_first` slices to about 0.002-0.029s and `eq_render_first` slices to
about 0.002-0.080s. The filtered method dropped from about 10.62s to about
6.19s, and `TestBasetypes` class render time dropped from about 42.54s to about
39.16s. The direct 360s probe still timed out (`probe_exit=124`), now after
rendering `TestBasetypes`, `UInt`, numeric suffix/separator helpers, and into
`StringBuf`, so this remains internal burn-down evidence only. README and North
Star progress bars stay unchanged.

## 2026-07-09 StringBuf Runtime Support Checkpoint

The post-TemplateWrap strict timing frontier reached stdlib `StringBuf`.
Filtered timing showed the parsed `StringBuf.get_length` single-return body
spending about 0.23-0.24s in statement rendering, and the full helper class
about 1.05s, even though the class is only the standard string accumulator
surface. That made it a bounded runtime-module candidate rather than evidence
for a broad expression cache.

The Cpp backend now recognizes real stdlib `StringBuf` by source identity,
including the active Haxe versioned std root reported by current-source probes
(`/haxe/versions/.../std/StringBuf.hx`), the repo `vendor/haxe/std/StringBuf.hx`
path, and Cpp `_std` resolver variants. `CppRuntimeSupport.stringBufSupportLines`
emits the target-owned C++ surface and the helper-classification detail trace
now includes `source=...` so future probes can explain source-identity misses.

Focused validation used
`.artifacts/full1/cpp-strict-current/stringbuf-identity-probe-after-fix.log`:
the tiny Cpp fixture classified `StringBuf` as `runtime_module` from
`/Users/fullofcaffeine/haxe/versions/4.3.7/std/StringBuf.hx`, built, ran, and
printed `ab`. The full direct current-source 360s probe still timed out
(`probe_exit=124`) in
`.artifacts/full1/cpp-strict-current/direct-source-only-stringbuf-versioned-runtime-timing-current.log`;
because render timing is noisy, that run stopped earlier, inside
`TestBasetypes.testAbstractOperatorOverload`, before reaching `StringBuf`.
This confirms the bounded classification fix but not a strict gate improvement.
README and North Star progress bars stay unchanged.

## 2026-07-09 Empty Map `toString` Checkpoint

The post-StringBuf strict probe showed run-to-run frontier variance, but a
filtered `TestBasetypes.testMap` run exposed a stable repeated hotspot:
four immediate empty generic map constructions rendered only to compare
`new Map<K,V>().toString()` with `"[]"`. In
`.artifacts/full1/cpp-strict-current/direct-source-only-testbasetypes-testmap-timing-current.log`,
those four statements consumed about 1.68s, 1.66s, 3.37s, and 3.25s
respectively, with `eq_infer_first` plus `eq_render_first` dominating each
case. The full method took about 10.55s and the `TestBasetypes` helper class
took about 38.39s.

The bounded seam is now an expression intrinsic for the immediate fresh
construction only: `new Map<K,V>().toString()` with no constructor arguments and
no `toString` arguments lowers directly to `std::string("[]")` and infers
`std::string`. This deliberately does not change mutated map behavior, map
literal behavior, generic map factory rendering for locals, or any broad
expression-cache policy. The safety argument is local to the syntax: no code can
mutate the just-constructed empty map between construction and the immediate
`toString` call.

Focused smoke coverage asserts both the direct render/type inference result and
the generated helper shape: ordinary inferred generic map locals still render
through typed `__hxhx_make_shared_Map<...>()` factories, while the expression
only empty-map `toString` comparison folds without allocating a temporary helper
map.

Post-change validation used the current-source build and the same 360s strict
probe with `HXHX_TRACE_STAGE3_CPP_TIMINGS=1` and
`HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER=TestBasetypes.testMap`. In
`.artifacts/full1/cpp-strict-current/direct-source-only-testmap-empty-map-fold-timing-current.log`,
`TestBasetypes.testMap` dropped to about 3.30s and the `TestBasetypes` helper
class dropped to about 31.17s. `StringBuf` remained a runtime module
(`render_helper_class_timing name=StringBuf seconds=0.000480...`). The direct
strict probe still timed out at 360s, after reaching Date/GADT/Exception and
`TestExceptions` timings (`testWildCardCatch_rethrow` about 2.46s and
`testCatchAbstract` about 1.02s). That later frontier should be handled by a
separate exception-render investigation instead of widening this map-specific
fold.

This is another internal strict Cpp burn-down checkpoint only. README and North
Star progress bars stay unchanged because strict Cpp remains red and no public
production-usability claim changed.

## 2026-07-09 TestExceptions Variance Checkpoint

The next investigation tried to validate whether the later
`TestExceptions.testWildCardCatch_rethrow` and `testCatchAbstract` timings from
the empty-map probe were a credible bounded seam. They were not reproducible
enough to patch.

The post-map probe
`.artifacts/full1/cpp-strict-current/direct-source-only-testmap-empty-map-fold-timing-current.log`
reached `TestExceptions` before the 360s timeout and reported
`testWildCardCatch_rethrow` at about 2.46s and `testCatchAbstract` at about
1.02s. A same-commit current-source rerun with
`HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER=TestExceptions.testWildCardCatch_rethrow`
wrote
`.artifacts/full1/cpp-strict-current/direct-source-only-testexceptions-rethrow-timing-current.log`,
but timed out at 360s before reaching `TestExceptions`; the final completed
render timing was around `Lambda.map`. Its largest completed helper timings
were broad early/runtime surfaces such as `Assertation` (~2.63s), `Type`
(~2.57s), `Sys` (~2.00s), `StringMap` (~1.69s), and `TestOps` (~1.51s).

That evidence means the exception-test timings are currently a moving frontier,
not a stable exception-specific hotspot. Do not widen exception lowering or
runtime semantics from this log alone. The next Cpp strict burn-down should pick
a seam only after a repeated filtered run reaches the same class/method
frontier, or after diagnostics are improved enough to separate render-time
work from timeout-bound ordering variance.

No code change was made for this checkpoint. README and North Star progress
bars stay unchanged because strict Cpp remains red and this checkpoint records
negative evidence, not a production-readiness improvement.

## 2026-07-09 Assertation Shared Timing Checkpoint

The follow-up diagnostic checked whether the repeated `Assertation` helper
timing from the TestExceptions variance run was a credible next Cpp patch seam.
It is not, at least not as a timing-only change.

A two-log comparison of the latest comparable timeout probes:

```bash
node scripts/ci/cpp-strict-frontier-summary.js --top 8 \
  .artifacts/full1/cpp-strict-current/direct-source-only-testmap-empty-map-fold-timing-current.log \
  .artifacts/full1/cpp-strict-current/direct-source-only-testexceptions-rethrow-timing-current.log
```

reported `CPP_STRICT_FRONTIER_SUMMARY:PASS classification=moving-frontier`,
with no repeated frontier and no repeated top timings. The post-map run reached
`TestExceptions.testValueException`; the TestExceptions-filtered rerun stopped
much earlier at `Lambda.map`.

A broader comparison that also included older completed source-only runs:

```bash
node scripts/ci/cpp-strict-frontier-summary.js --top 8 \
  .artifacts/full1/cpp-strict-current/direct-source-only-testmap-empty-map-fold-timing-current.log \
  .artifacts/full1/cpp-strict-current/direct-source-only-testexceptions-rethrow-timing-current.log \
  .artifacts/full1/cpp-strict-current/direct-source-only-kind-cache-timing.log \
  .artifacts/full1/cpp-strict-current/direct-source-only-after-anon-local-callable.log \
  .artifacts/full1/cpp-strict-current/direct-source-only-after-enum-constructor-value.log
```

reported `classification=repeated-frontier` only because the two older
completed runs both ended at `Report`, which rendered in about 0.007s. That is
a completion marker, not a performance target. The expensive completed classes
in those older logs remained much larger moving surfaces such as
`TestNumericCasts` (~236-239s), `TestXML` (~86-87s), `TestType` (~67s),
`TestBasetypes` (~36s), and `TestExceptions` (~13s).

Direct extraction across seven strict timing logs showed `Assertation` is stable
but small:

- `direct-source-only-fast-assert-timing.log`: ~2.03s
- `direct-source-only-after-anon-method-carrier.log`: ~2.97s
- `direct-source-only-testmap-empty-map-fold-timing-current.log`: ~1.85s
- `direct-source-only-testexceptions-rethrow-timing-current.log`: ~2.63s
- `direct-source-only-kind-cache-timing.log`: ~1.89s
- `direct-source-only-after-anon-local-callable.log`: ~1.72s
- `direct-source-only-after-enum-constructor-value.log`: ~1.72s

The local utest source confirms `Assertation` is an enum with nine constructors
from `utest.Assertation`. The generated Cpp artifact currently renders those
constructors as static tag-returning methods such as
`static std::string Error(...) { return std::string("Error"); }`; general enum
payloads are still not preserved by the Cpp enum carrier model. The slowest
`Assertation` method timings are the payload-shaped constructors, but each
method emits only three lines. That points to repeated helper-method
preparation/type-flow overhead around enum constructors rather than a large
method body that can be optimized safely in isolation.

Do not add an `Assertation`-specific special case. A general shortcut that
renders generated enum-constructor methods directly as tag-returning helpers may
be a valid non-semantic optimization, but it must be decided together with the
enum carrier behavior contract so it does not freeze today's payload-dropping
bring-up model. The design decision is tracked in `haxe_ocaml-gs7lw`.

The `haxe_ocaml-gs7lw` design checkpoint added the enum carrier behavior matrix
to [`CPP_TARGET_RUNTIME_POLICY.md`](CPP_TARGET_RUNTIME_POLICY.md). The decision
is to avoid both `Assertation`-specific shortcuts and generic payload-constructor
tag shortcuts until Cpp has a payload-preserving enum carrier seam. Timing-only
evidence is not enough because upstream Haxe 4.3.7 observes enum payloads
through `Std.string`, `Type.enumEq`, switch binders, `Type.createEnum`,
Dynamic/`EnumValue`, and Serializer/Unserializer flows.

No code change was made for this checkpoint. README and North Star progress
bars stay unchanged because strict Cpp remains red, public production readiness
did not change, and the only new implementation path is the payload-preserving
enum carrier follow-up `haxe_ocaml-puquq`.

Slow diagnostic validation for hotspot claims:

- run `node scripts/ci/cpp-strict-frontier-summary.js --top 15 <log>...` over
  the latest comparable strict Cpp timing logs before choosing a new patch seam;
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
