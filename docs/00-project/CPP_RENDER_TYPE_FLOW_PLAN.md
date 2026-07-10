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
- `HXHX_TRACE_STAGE3_CPP_LAMBDA_PHASES=1`, used with both settings above,
  adds inner typed-lambda setup/body/restore phases. Omit it when comparing
  enclosing statement or method timings because the nested clocks and records
  intentionally perturb those totals.
- `HXHX_TRACE_STAGE3_CPP_CALL_ARG_DETAIL_PHASES=1`, also used with the broad
  timing flag and method filter, adds the otherwise-unmeasured declared-enum,
  enum, and structural-typedef call-argument probes.
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

That behavior contract is now backed by the checked-in
`npm run test:cpp-enum-carrier-oracle-seed` runner. The seed is still oracle
evidence, not Cpp support: the next Cpp implementation must either preserve the
seeded payload behavior or explicitly classify any remaining gap as
`unsupported_diagnostic` / `known_divergence` while the carrier seam is split.

The first `haxe_ocaml-puquq` implementation seam now gives typed generated enum
carriers target-owned constructor metadata: tag, index, and stringified
payloads. Focused Cpp smoke coverage pins typed enum constructor coercion,
static metadata field coercion, same-carrier `Type.enumEq`, typed `Std.string`,
`List<T>` argument coercion, `Type.enumConstructor` / `Type.enumIndex` /
`Type.enumParameters`, Dynamic stringification, and the existing
unreachable-payload switch guard under that representation. The smoke also
builds and runs a generated C++ enum metadata program, so the helper declaration
order and runtime metadata access are covered, not only render strings.

The next `haxe_ocaml-puquq` slice extended the same representation to
compiler-known `Type.createEnum` / `Type.createEnumIndex` calls: static enum
class arguments plus literal constructor names/indexes and literal payload
arrays now lower directly to typed metadata carriers. The focused smoke builds
and runs a generated C++ factory program that prints zero-arg and payload
factory values and compares the payload factory result through `Type.enumEq`.
The switch slice then taught typed enum-carrier switches to match constructor
metadata and bind payload names from the stringified metadata parameter vector;
the generated C++ enum metadata smoke now prints a `Pair(i, s)` branch result.
A follow-up `haxe_ocaml-8604b` slice added the generated `Enum` metadata
carrier used by the injected/minimal `Type` support and std `Type` helper
rendering. Dynamic `Type.createEnum` / `Type.createEnumIndex` calls now build
typed enum carriers from constructor metadata, `Type.getEnumConstructs` reads
the same registry, and typed `Type.allEnums` constructs zero-argument values
while skipping payload constructors. The focused C++ factory smoke now covers
both literal-folded and dynamic factory calls plus typed `allEnums`.

The `haxe_ocaml-a3xh8` slice keeps that generated-carrier shape but adds a
parallel original-payload channel: generated enum carriers and erased
`EnumValue` now store `std::vector<std::any>` payloads next to the existing
string metadata vector. The string vector remains the source for `Std.string`
and focused switch payload binders; `Type.enumEq` and `Type.enumParameters`
use the original payload vector so `Box(1)` and `Box("1")` do not collapse to
the same string-only value. The focused oracle seed records upstream
`Std.isOfType` expectations, while the C++ runtime smoke verifies the same
identity boundary through target type-name output because that fixture does
not emit the full std `Std.isOfType` body. README and North Star progress bars
stay unchanged: this moves a Cpp bring-up blocker but strict Cpp and public
production readiness remain red.

The `haxe_ocaml-73r4j` slice then used those carrier prerequisites for a
focused Serializer/Unserializer enum round trip. Generated payload constructor
methods on enum carrier classes now return carrier values instead of bare
constructor-tag strings, so the original payload vector survives a direct
constructor call such as `SerializedSeed.With(9, "nine")`. A target-owned
`Serializer` / `Unserializer` support block is injected only when code actually
uses those static support receivers and no rendered helper definition exists.
The generated C++ runtime smoke now builds and runs constructor-name `w` token
round trips for a zero-arg enum and an `Int`/`String` payload enum.

The follow-up `haxe_ocaml-nd2nh` slice extends only that same focused enum
surface to `Serializer.USE_ENUM_INDEX`: generated C++ now exposes
`Serializer::USE_ENUM_INDEX`, emits upstream-compatible constructor-index `j`
tokens, and decodes them through the generated enum metadata registry. The
runtime smoke covers both zero-arg and `Int`/`String` payload indexed enum
round trips.

This is not full enum or Serializer parity. Broad erased switch payload
extraction, references/caches, custom enum resolvers, object/class payloads,
arrays/maps, bytes, floats, custom serialization hooks, and full
`haxe.Serializer` / `haxe.Unserializer` body rendering remain outside these
slices and still require the behavior matrix plus focused oracle evidence.
README and North Star progress bars stay unchanged because strict Cpp and public
production readiness remain red.

## 2026-07-09 Primitive Type-Hint Fast Path Checkpoint

After the focused enum Serializer slices, the fresh current-source strict Cpp
probe still timed out, but the completed timing data again showed
`TestBasetypes` as a dominant repeated render surface. A method-filtered
`TestBasetypes.testString` run reported the method at about 6.68s and the full
`TestBasetypes` helper class at about 31.40s. Statement timing showed repeated
local declarations paying the shared type-hint path even for canonical
primitive hints such as `String`.

The bounded seam is order-only and non-semantic: `CppTypeModel.cppTypeHint` and
the `CppTargetCore.cppTypeHint` wrapper now resolve active generic type
parameters first, then return canonical primitive Haxe hints directly, before
walking class/abstract lookup tables. `Null<T>`, bare `Null`, stale null
pointers, abstract-backed wrappers, structural typedefs, rendered aliases,
containers, functions, and C++ pointer helpers stay on their existing paths.
Focused smoke coverage pins the direct `String` path and also asserts that an
active generic type parameter still wins over the primitive fast path.

Post-change validation used a fresh current-source hxhx build and the same
480s Cpp timing command with
`HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER=TestBasetypes.testString`. In
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbasetypes-teststring-filter-after-primitive-typehint.log`,
`TestBasetypes.testString` dropped to about 5.14s and the full
`TestBasetypes` helper class dropped to about 23.27s. The probe still timed out
at the explicit 480s Cpp cap (`probe_exit=1`, target attempt exit 124), but it
advanced past the previous `TestBytes.test` frontier and stopped after
`TestEReg.test` / `TestEReg` around 32.25s. Later completed hotspots included
`TestBytes` around 38.37s, `TestExceptions` around 24.59s, `TestIO` around
19.95s, and `TestEReg` around 32.25s.

Focused local gates passed:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`

This is another internal strict Cpp burn-down checkpoint only. README and North
Star progress bars stay unchanged because strict Cpp remains red and no
user-facing production-readiness claim changed. A follow-up should investigate
the later `TestEReg` / `TestBytes` / `TestIO` render frontiers only after a
fresh comparable log confirms the next stable repeated seam.

## 2026-07-09 Prep Local-Inference Evidence Guard Checkpoint

The follow-up bead `haxe_ocaml-is77c` re-ran comparable current-source Cpp
timing probes after the primitive type-hint fast path. The last timeout
boundary moved between runs, but the shared top timings stayed stable:
`TestBytes.test`, `TestBytes`, `TestEReg`, `TestBasetypes`, `TestExceptions`,
and `TestIO` repeated as the real frontiers. The method-filtered
`TestBytes.test` probe showed that several prep local-inference phases were
walking the full method body and producing no overrides:

- `infer_string_map_locals`: about 1.24s before, 0 overrides.
- `infer_generic_factory_locals`: about 1.19s before, 0 overrides.
- `infer_optional_lambda_locals`: about 1.18s before, 0 overrides.
- `infer_bind_callable_locals`: about 1.19s before, 0 overrides.
- `infer_dynamic_locals`: about 1.18s before, 0 overrides.
- `infer_helper_typed_as_locals`: about 1.20s before, 0 overrides.

The retained seam is a syntax-only evidence guard in
`CppPrepLocalInferenceGuard`, wired before the heavy Cpp prep passes. It avoids
the pass when the method cannot contain the source form that would let that
pass produce a final local override: unhinted map locals, unhinted zero-arg
factory `new` locals, optional-lambda locals, `.bind` call evidence,
Dynamic-like/open/callable locals, or `HelperMacros.typedAs` calls. The guard is
intentionally conservative and does not replace the semantic pass. One important
case is explicitly covered: `infer_dynamic_locals` must still run for explicitly
typed local callables, because call sites can refine stale callable argument
types such as `(String)->String` to concrete call-site shapes.

Post-change timing used
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-after-prep-guards.log`.
The Cpp target still timed out at the explicit 480s cap
(`probe_exit=1`, target attempt exit 124), but the targeted prep cost collapsed:
`TestBytes.test` prep cache miss dropped from about 7.19s to about 0.002s.
`TestBytes.test` dropped from about 23.52s to about 17.69s, and the full
`TestBytes` helper class dropped from about 37.44s to about 25.69s. The timeout
frontier moved farther, from `Xml.exists` in the comparable pre-change log to
`TestXML.testBasic` after the guard. The next Cpp burn-down seam should use the
remaining shared top timings, especially `TestEReg` and the expression-render
work still visible inside `TestBytes.test`; do not patch the final timeout
boundary alone.

Validation for this slice included:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`
- current-source strict Cpp timing probe with
  `HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER=TestBytes.test`

This remains an internal strict Cpp performance checkpoint. README and North
Star progress bars stay unchanged because the strict Cpp gate still times out
and no user-facing production-readiness claim changed.

## 2026-07-09 Primitive Literal Call-Argument Fast Path

The follow-up bead `haxe_ocaml-x1w63` used the post-prep-guard timing logs to
choose the next bounded render seam. The comparable
`.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-test-filter-after-prep-guards.log`
run reached `TestEReg.test` and showed repeated direct calls where a literal
argument already matched a declared primitive parameter type. The traced
sub-phases around these arguments were tiny, but the enclosing
`param_arg_render` samples for `EString` and `EInt` were repeatedly about
0.058s to 0.061s. The missing cost sat between the traced phases, inside the
generic class/enum/reference adaptation probes that are needed for complex
arguments but not for obvious primitive literals.

The retained seam is deliberately narrow. `callArgExprForParam` now checks
primitive literals whose C++ type already matches the expected call parameter
type before it runs the generic class/enum/reference probes. The shortcut
accepts `String` literals for `std::string`, `Int` literals for `int` and
numeric promotion to `double`/`float`, `Float` literals for `double`/`float`,
and `Bool` literals for `bool`. It does not shortcut numeric literals into
`std::string`, so string-shaped `Dynamic` helpers still stringify scalar values
through the existing path. It also refuses primitive-backed abstract arguments,
which preserves abstract constructor/side-effect conversion semantics.

This shortcut is intentionally not wired into `renderKnownCppParamCallArgs`.
Known stdlib/support calls often emit stable `std::string("...")` wrappers, and
changing those broadly would create generated-code churn unrelated to the
profiled `renderFunctionCallArgs` path. A broader known-parameter shortcut can
be reconsidered only with a focused generated-shape contract.

Validation for this slice included:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`

A current-source strict Cpp timing probe was attempted with
`HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER=TestEReg.test` and wrote
`.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-test-filter-after-primitive-literal-fastpath.log`.
It timed out at the explicit 480s Cpp cap (`gate3_target_attempt_end ... exit
124`) before reaching the filtered `TestEReg.test` method, after rebuilding the
current-source binary and doing Cpp target setup. Because that log is not
comparable to the pre-change method-filtered log, it is recorded only as a
non-comparable timeout, not as proof of a `TestEReg` timing delta. The next
timing claim for this seam should use a warmed, comparable current-source Cpp
method-filtered run that reaches `TestEReg.test`, or a smaller focused timing
fixture that directly exercises declared-parameter primitive literal calls.

Follow-up `haxe_ocaml-bp310` added that smaller focused fixture to
`test/M14CppHelperRenderBenchIntegrationTest.hx`. The helper render bench now
renders a declared `String`/`Int`/`Bool`/`Float` call repeatedly through
`directCallExpr`, asserts the stable emitted call
`target("literal", 7, true, 1.25)`, and prints
`primitive_arg_calls` / `primitive_arg_seconds` in the PASS line. The default
local runs use 250 calls; the first two local samples reported about 0.24s to
0.26s for that loop. This is a cheap regression and measurement fixture for the
declared-parameter literal seam; it is not a replacement for a warmed strict Cpp
method-filtered run when making a broader `TestEReg` timing claim.

README and North Star progress bars stay unchanged. This is an internal strict
Cpp render/type-flow burn-down slice; strict Cpp remains red and no public
production-readiness claim changed.

## 2026-07-09 Known Bytes Reference Type Fast Path

The follow-up bead `haxe_ocaml-jhegi` used the comparable `TestBytes.test`
traces to select the next repeated type-flow seam instead of the moving timeout
boundary. In both
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-current.log`
and
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-after-prep-guards.log`,
known `Bytes` methods repeatedly resolved the same `std::shared_ptr<Bytes>`
return through the generic type-hint classifier. In the post-prep-guard log,
the seven `Bytes.ofString` static-return probes totaled about 0.827s, the two
`Bytes.sub` instance-return probes totaled about 0.241s, and the one
`Bytes.alloc` static-return probe took about 0.134s. The corresponding totals
in the earlier current log were about 0.793s, 0.225s, and 0.111s, confirming a
stable repeated cost rather than a single slow sample.

The retained change is limited to already-known `Bytes` API reference
positions. `knownConcreteClassReferenceCppType` resolves the selected class and
its rendered name directly, then returns its `std::shared_ptr<T>` shape. Known
`Bytes` return positions for `sub`, `alloc`, `ofString`, `ofData`, and `ofHex`,
plus the `Bytes` parameters of `blit` and `compare`, use that helper. Class
lookup remains scope-aware, so rendered module-local names and package
collisions keep their existing identity. Arbitrary type hints, abstracts,
structural values, containers, functions, and all non-`Bytes` signature
positions still use the generic classifier.

The helper render bench now includes a nested
`Bytes.ofString(...).sub(...).compare(Bytes.ofString(...))` fixture and prints
`bytes_reference_calls` / `bytes_reference_seconds`. An immediate local
before/after run of the identical ten-call fixture reported about 0.338s on the
prior generic path and about 0.112s on the retained direct-reference path,
while asserting the emitted expression remained unchanged.

The fresh current-source strict probe wrote
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-after-known-bytes-reference.log`.
It remained expected-red at the explicit 480s Cpp cap, but it reached and
completed the filtered method. The targeted phase totals dropped to about
0.0036s for seven `Bytes.ofString` static returns, 0.00083s for two `Bytes.sub`
instance returns, and 0.00048s for `Bytes.alloc`. `TestBytes.test` completed in
about 10.81s and the class in about 16.14s, versus about 17.69s and 25.69s in
the latest comparable pre-change method-filtered log. The full-method delta
also includes the already-landed primitive literal argument shortcut, so the
focused phase totals and isolated bench are the evidence for this specific
slice. The timeout boundary stopped at the beginning of `TestEReg`; it is not
used as a progress claim because setup/helper counts differed from the earlier
run.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp still
times out, and this internal type-flow improvement does not change public
production readiness.

## 2026-07-09 Omitted Bytes Encoding Parameter Guard

Follow-up bead `haxe_ocaml-tc2nu` isolated the remaining
`Bytes.ofString(String, ?Encoding)` call cost to signature preparation rather
than return-type inference. `renderClassMethodCallArgs` asked
`knownStdlibMethodParamCppTypes` for the complete signature on every call, so a
one-argument call still classified the unused optional `Encoding` type before
rendering its supplied `String`. The focused helper fixture now checks this
arity decision directly: one-argument calls receive only the known
`std::string` parameter shape, while explicit two-argument calls and
declaration/default lookups retain the complete two-parameter signature.

The retained change is intentionally specific to `Bytes.ofString`. Call-site
arity is passed into the known stdlib parameter lookup, and only the omitted
`Encoding` position is skipped. The existing `std::string` argument adaptation
still runs, the emitted `Bytes::ofString(std::string(...))` expression is
unchanged, and no arbitrary type-hint cache or broad exact-match argument
shortcut was added. Other known stdlib calls and declaration rendering keep
their existing paths.

The identical ten-call `bytes_reference_calls` helper fixture reported about
0.0968s immediately before the change and about 0.0739s and 0.0786s in two
post-change samples. The fresh current-source strict probe wrote
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-after-omitted-encoding-guard.log`.
It completed the filtered method before the expected explicit 480s Cpp
timeout. Against the immediately preceding comparable log, the five traced
`Bytes.ofString` RHS samples changed from about 0.327s, 0.340s, 0.332s,
0.582s, and 0.335s to about 0.190s, 0.181s, 0.189s, 0.314s, and 0.181s.
`TestBytes.test` changed from about 10.81s to 9.27s, and the whole `TestBytes`
class from about 16.14s to 13.77s. The timeout boundary moved beyond
`TestEReg` into `TestXML`, but that moving frontier is diagnostic context, not
the claim for this slice; the comparable filtered method and RHS phases are
the evidence.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp still
times out, and this internal parameter-preparation improvement does not change
public production readiness.

## 2026-07-09 Bytes Plain String Argument Guard

Follow-up bead `haxe_ocaml-rfjcc` split the remaining supplied-String work
inside the focused helper bench. A preliminary 200-adaptation sample measured
about 0.0606s through `valueExprForExpectedType` versus about 0.0253s through
the underlying `stringExpr`, confirming that known `Bytes.ofString` calls were
still paying generic expected-value probes before their established String
adaptation. The retained fixture measures literal, explicitly typed local, and
inferred local cases separately from the surrounding nested Bytes expression.

The retained shortcut remains specific to the first `Bytes.ofString`
parameter. String literals and locals whose surviving source hint is either
plain `String` or absent render directly to the same explicit
`std::string(...)` shape as before. Dynamic-hinted locals, abstract-hinted
locals, macro/cast wrappers, non-String values, and the optional `Encoding`
argument remain on generic adaptation. This avoids a broad same-C++-type
shortcut: primitive-backed abstract `toString` behavior and erased Dynamic
stringification still retain their existing boundaries.

Two post-change samples of the identical 300-adaptation phase loop reported
about 0.0572s and 0.0479s through generic expected-value rendering, about
0.0369s and 0.0271s through `stringExpr`, and about 0.00458s and 0.00348s
through the guarded direct wrapper path. The actual nested Bytes fixture still
asserts
`Bytes::ofString(std::string(s1))->sub(...)->compare(Bytes::ofString(std::string(s2)))`,
and a literal assertion keeps `Bytes::ofString(std::string("literal"))` stable.
The private seam assertions also prove that Dynamic- and abstract-hinted String
locals decline the shortcut.

A current-source strict probe wrote
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-after-direct-string-arg.log`.
It remained expected-red at the explicit 480s Cpp cap and did not reach the
filtered `TestBytes.test` method. This run spent about 112s reinstalling hxcpp
and stopped in `TestExceptions`, so it is recorded as non-comparable setup
overhead rather than evidence for a strict method delta. A warmed follow-up
must reach the same filtered method before making that claim.

Follow-up bead `haxe_ocaml-knwsd` obtained that comparable method evidence by
using a disposable upstream worktree outside this repository. A bounded seed
run installed and built the worktree-local hxcpp once; the retained 480s probe
then reused both utest and hxcpp, avoiding dependency setup inside the timing
budget. The worktree was removed immediately after the probe. The comparable
log is
`.artifacts/full1/cpp-strict-current/gate3-cpp-testbytes-test-filter-after-direct-string-arg-warm.log`.

Against the immediately preceding omitted-Encoding log, the five traced
`Bytes.ofString` RHS samples changed from about 0.190s, 0.181s, 0.189s,
0.314s, and 0.181s to about 0.133s, 0.128s, 0.124s, 0.191s, and 0.127s.
`TestBytes.test` changed from about 9.27s to 8.73s, and the whole `TestBytes`
class from about 13.77s to 12.75s. Both logs classify the same 384 reachable
helpers (253 full body, 83 declaration only, and 48 runtime module), so the
filtered method and expression deltas are comparable. The warmed timeout moved
past `TestXML` into `TestMisc`; as with earlier probes, that last boundary is
context only and is not the performance claim.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp still
times out, and this internal known-call render improvement does not change
public production readiness.

## 2026-07-09 Fresh EReg Return-Type Guard

Follow-up bead `haxe_ocaml-debpm` selected `TestEReg.test` from repeated shared
timings rather than the latest timeout boundary. It remains the largest
repeated method in the comparable omitted-Encoding and warmed direct-String
logs at about 22.68s and 22.41s. The earlier detailed
`.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-test-filter-after-prep-guards.log`
isolates a still-relevant receiver-type seam: six syntactic
`new EReg(...).map(...)` calls spent about 0.714s in failed generic known-field
checks, and two `new EReg(...).replace(...)` calls spent about 0.248s in failed
primitive-abstract checks before ordinary instance lookup recovered their
String return type.

The local upstream 4.3.7 stdlib declaration confirms that both `map` and
`replace` take two arguments and return `String`. The retained guard recognizes
only those two-argument methods on a syntactic fresh `EReg` receiver at the top
of expression type inference, and repeats the same guard at the lower known
field boundary. Non-fresh receivers, other methods or arities, callback
adaptation, constructor rendering, and the target-owned EReg runtime remain on
their existing paths.

The helper render bench now builds a 282-class lookup and repeatedly infers
fresh `EReg.map` and `EReg.replace` return types. Two pre-change ten-pair samples
reported about 0.577s and 0.573s. Two post-change samples reported about
0.000179s and 0.000116s while asserting that both results remain
`std::string`. The full Cpp native backend smoke also passed, including its
existing generated EReg callback and runtime-support assertions.

No new strict method-level delta is claimed for this slice. Recreating a
warmed external upstream worktree requires a serialized seed run plus the full
480s probe; the focused scaled fixture directly exercises the identified
return-type seam, while the latest comparable strict log already establishes
`TestEReg.test` as a repeated hotspot. A follow-up should phase the remaining
EReg lambda/call work before choosing another patch.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp still
times out, and this internal fresh-receiver inference improvement does not
change public production readiness.

## 2026-07-09 EReg String Callback Concatenation Guard

Follow-up bead `haxe_ocaml-rr13n` isolated the next `TestEReg.test` seam from
the same detailed phase trace. Eight `ELambda` call arguments totaled about
1.60s in `param_arg_render`, with about 1.59s attributed to
`function_expected_render`. The primitive-literal and fresh-receiver guards do
not affect those callback arguments.

The scaled helper fixture now renders a typed
`std::function<std::string(std::shared_ptr<EReg>)>` callback whose nested
concatenation reads `matchedLeft`, `matched(0)`, and `matchedRight`. Initial
ten-call samples measured about 0.319s to 0.344s for the complete expected
lambda and about 0.313s to 0.321s for generic expected-String rendering of the
body alone, proving that callback signature construction was not the hotspot.
Separate samples placed canonical `stringExpr` work around 0.218s to 0.257s,
plain rendering around 0.150s to 0.155s, and type inference around 0.030s to
0.032s.

The retained path is limited to one-argument EReg-to-String callbacks whose
body is a `+` concatenation. It recursively bypasses redundant probes on the
concatenation nodes while continuing to render every leaf through
`stringExpr`, preserving literal wrappers, erased Dynamic coercion, abstract
`toString` behavior, captures, and the expected callback signature. Other
function types, non-concatenation callback bodies, and non-EReg lambdas retain
the generic expected-value path.

An intermediate whole-body String shortcut reduced the ten-call callback loop
to about 0.291s to 0.315s. With the retained recursive concatenation guard, two
samples reported about 0.0215s and 0.0149s. An exact fixture assertion keeps
the generated callback unchanged as
`[&](std::shared_ptr<EReg> r) -> std::string { return ...; }`, including the
same nested `std::string("[")` and `matched*` expression shape. The full Cpp
native backend smoke also passed with its existing EReg runtime and callback
assertions.

No new strict method-level delta is claimed for this slice. As above, a warmed
method probe requires a serialized external-worktree seed plus the full 480s
run, while the scaled callback fixture directly proves this isolated seam. A
follow-up should obtain one warmed post-EReg-guards trace before choosing the
next `TestEReg` or shared render hotspot.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp still
times out, and this internal callback-render improvement does not change
public production readiness.

## 2026-07-09 Post-EReg Guards Warm Timing

Follow-up bead `haxe_ocaml-jcc5n` obtained the required current-source method
trace after the fresh-EReg return and EReg callback guards. As with the warmed
Bytes probe, a disposable upstream 4.3.7 worktree outside this repository was
seeded with worktree-local utest and hxcpp dependencies. The retained probe
reused that setup, reached the filtered method, and the worktree was removed
immediately afterward. The comparable log is
`.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-test-filter-post-ereg-guards-warm.log`.

Both this log and the preceding warmed direct-String-argument log contain 280
typed modules and classify the same 384 reachable helpers: 253 full body, 83
declaration only, and 48 runtime module. `TestEReg.test` changed from about
22.41s to 15.68s, while the whole class changed from about 22.42s to 15.68s.
That is a reduction of about 6.74s, or 30%. As a stability check earlier in the
same render order, `TestBytes.test` measured about 8.71s versus 8.73s in the
preceding warm log. The 480s probe still timed out later in the helper render;
that final boundary is context only and is not the performance claim.

The new detailed trace also confirms that the earlier focused seams moved in
the expected direction. Compared with the older detailed pre-guard trace,
aggregate `eq_infer_first` work fell from about 4.76s to 0.054s,
`eq_render_first` fell from about 7.93s to 4.79s, and the twenty callback
`function_expected_render` samples fell from about 1.59s to 0.59s. These phase
figures explain the current hotspot shape; the method-level claim above uses
the two comparable warmed logs.

The next repeated current seam is not the last timeout class. TestEReg
statement indices 23 through 33 are eleven immediate regex-literal
`.match(...)` calls and total about 5.21s, with individual statements around
0.45s to 0.53s. Their syntactic `new EReg(...)` receiver establishes the
target-owned owner, but `fieldCallExpr` still enters general static-receiver and
receiver-C++-type setup before rendering the method. Follow-up bead
`haxe_ocaml-0hryf` will first isolate that render setup in a scaled fixture and
will retain a shortcut only if the syntactic-owner seam remains bounded.

Focused validation for this diagnostic slice includes:

- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red at the explicit timeout, and this timing evidence does not change
public production readiness.

## 2026-07-09 Fresh EReg Field-Call Dispatch Guard

Follow-up bead `haxe_ocaml-0hryf` isolated the eleven immediate regex-literal
`.match(...)` statements identified by the warmed post-guard trace. A new
282-class helper fixture measures a complete `new EReg(...).match(...)` render
separately from the same constructor and the known `std::shared_ptr<EReg>`
instance arguments. Two pre-change ten-call samples put the full expression at
about 0.1752s, while constructor-only work was about 0.0027s to 0.0028s and
known-owner argument rendering was about 0.0023s to 0.0024s. The gap confirmed
that general expression/field-call dispatch, not EReg construction or String
argument conversion, owned this focused cost.

An intermediate shortcut inside `fieldCallExpr` only reduced the ten calls to
about 0.118s to 0.121s. The remaining time came before that helper: the general
expression dispatcher still tested many unrelated specialized field-call
guards first. The retained branch therefore recognizes the same narrow shape
near the top of `renderExpr`, before those probes. Two retained-path samples
reported about 0.0054s and 0.0067s for ten calls.

The guard accepts only a syntactic fresh `EReg` receiver with `match` arity one
or `map`/`replace` arity two. It renders arguments through the existing known
instance-method path, preserving String adaptation and the typed
EReg-to-String callback contract. Exact fixture coverage keeps the generated
match, replace, and map lines unchanged, including the map callback signature.
Non-fresh receivers, wrong arities, and other EReg methods explicitly decline
the shortcut.

This is a bounded repair in the existing Cpp expression-render seam, not a new
runtime or stdlib semantic family. Broader Cpp render/type-flow extraction
remains owned by `haxe_ocaml-36ec`, and the mega-file gravity guard remains part
of validation. No new strict method-level delta is claimed: the comparable
warm trace identified this repeated seam, while recreating the disposable
external worktree and dependency seed solely for this isolated render branch
would serialize another full timeout probe. Follow-up bead `haxe_ocaml-y0ppt`
owns that comparable warmed trace before another `TestEReg` phase is selected.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this internal dispatch improvement does not change public
production readiness.

## 2026-07-09 Post-Fresh-EReg-Dispatch Warm Timing

Follow-up bead `haxe_ocaml-y0ppt` obtained the comparable current-source trace
after the top-level fresh-EReg dispatch guard. A new disposable upstream 4.3.7
worktree outside this repository was seeded with worktree-local utest and hxcpp
dependencies, the retained 480s probe reused that setup, and the worktree was
removed immediately after the trace reached `TestEReg.test`. The log is
`.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-test-filter-post-fresh-ereg-dispatch-warm.log`.

This log and the preceding post-EReg-guards warm log both contain 280 typed
modules and classify the same 384 reachable helpers: 253 full body, 83
declaration only, and 48 runtime module. `TestEReg.test` changed from about
15.68s to 9.29s, while the class changed from about 15.68s to 9.29s. That is a
reduction of about 6.39s, or 41%. The eleven statement indices 23 through 33
that selected the focused patch fell from about 5.21s to 1.47s. Earlier shared
classes varied much less: for example, `TestBytes.test` measured about 9.17s
versus 8.71s, so the EReg method movement is substantially larger than the
cross-run noise visible before it.

The detailed phases confirm that the selected render seam moved:
`render_function_call_args` fell from about 5.50s to 1.76s,
`eq_render_first` fell from about 4.79s to 2.06s, and the sum of the 88 traced
statements fell from about 13.09s to 6.68s. The method still spends about 1.33s
in its unchanged dynamic-local preparation pass, but the largest repeated
statement family is now eleven fresh-EReg local declarations. Those statements
total about 2.63s, split between about 1.30s of local-type selection and 1.32s
of RHS rendering even though each initializer is syntactically
`new EReg(pattern, flags)`.

Follow-up bead `haxe_ocaml-9qkoe` owns a scaled declaration fixture that will
separate local-type selection, expected-value adaptation, and direct EReg
construction before retaining any shortcut. The final 480s timeout occurred
later in helper rendering and remains context only, not the next patch target.

Focused validation for this diagnostic slice includes:

- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red at the explicit timeout, and this timing checkpoint does not
change public production readiness.

## 2026-07-09 Fresh EReg Local-Type Guard

Follow-up bead `haxe_ocaml-9qkoe` isolated the eleven fresh-EReg declarations
selected by the post-dispatch warm trace. The helper bench now measures local
declaration type selection, direct `EReg` type-hint resolution, local
initializer adaptation, and direct constructor rendering separately. It also
freezes the complete unhinted and explicit declaration shapes.

Two pre-change ten-call samples put local type selection at about 0.0588s and
0.0606s. Direct `cppTypeHint("EReg")` resolution was similarly expensive at
about 0.0569s and 0.0678s. In contrast, initializer adaptation measured about
0.0031s to 0.0074s and direct construction about 0.0032s to 0.0063s. A
thousand-call sample made the boundary clearer: local type selection took about
6.43s, while initializer adaptation and construction were about 0.308s and
0.315s. The retained change therefore does not alter the RHS path.

For local declarations only, an explicit EReg hint or a syntactic
`new EReg(...)` initializer now selects `std::shared_ptr<EReg>` before general
type lookup. `cppLocalDeclaredType` still applies explicit-hint rules and
prepared source/renamed-local overrides afterward. Focused assertions keep
non-EReg inference unchanged and preserve both exact declaration forms:
`auto r = std::make_shared<EReg>(...)` and
`std::shared_ptr<EReg> typed = std::make_shared<EReg>(...)`.

Two post-change ten-call samples measured about 0.000163s and 0.000182s for
local type selection; a final validation sample was about 0.000177s. No new
strict method-level delta is claimed for this isolated slice. The current warm
trace already establishes the repeated declaration family, while the scaled
fixture directly proves the retained type-selection seam and explicitly
declines an unsupported RHS shortcut. Follow-up bead `haxe_ocaml-apz4n` owns
inner current-source RHS timing to explain the strict/interpreter discrepancy
before any behavior change is considered.

This remains a small repair inside the existing Cpp local-type dispatcher and
adds no runtime or stdlib semantic family. Broader Cpp render/type-flow
extraction remains owned by `haxe_ocaml-36ec`.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this internal local-type improvement does not change public
production readiness.

## 2026-07-09 Fresh EReg SVar RHS Phase Timing

Bead `haxe_ocaml-apz4n` added opt-in inner timing to the existing filtered Cpp
statement trace without changing rendered output. The new phases split an
`SVar` RHS across shadowed-field recovery and local-initializer rendering, then
split local initialization across macro-API recognition, structured string-map
recognition, and `newExpr`. These probes run only when the existing
`HXHX_TRACE_STAGE3_CPP_TIMINGS` method filter selects the enclosing method.

A current-source build seeded and warmed an external upstream Haxe 4.3.7
worktree. The warm trace retained the same 280 typed modules and 384-helper
inventory: 253 full bodies, 83 declaration-only helpers, and 48 runtime-owned
helpers. The temporary worktree was removed immediately after the run. The
source logs were:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-rhs-phase-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-rhs-phase-warm.log`

Across the eleven fresh-EReg declaration indices selected by the preceding
trace, statement rendering totaled about 1.196905s. The outer RHS phase totaled
about 1.194921s, local-initializer rendering about 1.193725s, and `newExpr`
about 1.191919s. The alternative probes were negligible: local type selection
totaled about 0.000452s after its guard, structured string-map recognition
about 0.000030s, shadowed-field recovery about 0.000010s, and macro-API
recognition about 0.000007s.

This explains the interpreter-fixture discrepancy: the Haxe interpreter did
not expose the target-owned construction lookup cost, while the current-source
OCaml trace assigns effectively all of the repeated RHS time to `newExpr`.
`TestEReg.test` measured about 4.91s in this run, but no direct method-level
delta is claimed because the wider run was also faster than the previous warm
probe. Follow-up bead `haxe_ocaml-5zl0h` owns an early EReg construction
preflight that can bypass general class-name and primitive-abstract setup while
preserving all non-EReg construction paths.

This diagnostic remains inside the existing opt-in Cpp timing surface and adds
no runtime, stdlib, or rendering behavior. Broader Cpp render/type-flow
extraction remains owned by `haxe_ocaml-36ec`.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this diagnostic does not change public production readiness.

## 2026-07-10 Target-Owned EReg Construction Fast Path

Follow-up bead `haxe_ocaml-5zl0h` moved syntactic EReg construction ahead of
general class-name and primitive-abstract discovery. The first cut retained
`renderConstructorArgs`; a 1,000-call interpreter fixture improved from about
0.300130s to 0.188760-0.195699s, but the current-source trace correctly rejected
that as the full strict fix. Its eleven `newExpr` phases still totaled about
1.334684s, compared with 1.191919s in the prior warm run, because constructor
argument type rediscovery remained on the target-owned path.

The retained fast path also bypasses that rediscovery. Haxe has already checked
the two EReg constructor arguments against the String contract, and the generic
constructor path ultimately rendered those String arguments through ordinary
expression rendering. The focused fixture now freezes equivalence for typed
String locals in addition to literal arguments, package-qualified EReg paths,
an explicit expected EReg carrier, and exact
`std::make_shared<EReg>(...)` output. A non-EReg constructor assertion remains
on general class and expected-type discovery; abstract and generic constructor
coverage remains in the full Cpp smoke gate.

Two post-change 1,000-call samples measured about 0.004904s and 0.004951s for
direct EReg construction. A rebuilt current-source warm trace retained the same
280 typed modules and 384-helper inventory: 253 full bodies, 83 declaration-only
helpers, and 48 runtime-owned helpers. Across the same eleven declaration
indices, `newExpr` fell from about 1.191919s to 0.000434s and the complete SVar
statements fell from about 1.311631s to 0.124541s. The enclosing trace phases
include the cost of printing their inner timing records, so `newExpr` is the
cleanest measurement of the moved seam.

`TestEReg.test` fell from about 4.910285s to 1.742630s, roughly 64.5%. This is
larger than cross-run variation and moved in the opposite direction from two
controls: `TestBytes.test` rose from about 8.091464s to 8.569097s, and
`TestXML.testBasic` rose from about 7.480588s to 7.818682s. The 480s probe still
timed out later after `TestMisc`, so strict Cpp remains expected-red. The seeded
external upstream worktree was removed after the final run. Relevant logs are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-constructor-preflight-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-after-construction-preflight-warm.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-after-direct-constructor-args-warm.log`

After the construction seam moved, statement indices 41-50 became the next
repeated family at about 0.932430s. Index 42 alone measured about 0.260401s and
repeatedly rediscovered a typed EReg local and the String-vector result of
`split`. Follow-up bead `haxe_ocaml-eovyq` owns a scaled split-chain fixture
before any broader instance-dispatch shortcut is retained.

This is a narrow target-owned construction branch inside the existing Cpp
dispatcher. It adds no runtime or stdlib implementation and changes no
non-EReg construction behavior. Broader Cpp render/type-flow extraction remains
owned by `haxe_ocaml-36ec`. Committed bootstrap snapshots are not regenerated
because the slice changes neither the bootstrap interface nor snapshot
acceptance.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this internal render-latency improvement does not change
public production readiness.

## 2026-07-10 Typed-Local EReg Split Fast Path

Follow-up bead `haxe_ocaml-eovyq` isolated the typed-local EReg split chain at
the head of the post-construction trace. The helper bench now measures split
return inference, direct call rendering, field-call argument rendering, and
the enclosing vector `length` and `join` shapes separately. It also proves
that non-EReg locals, the wrong split arity, and non-split EReg methods decline
the shortcut.

Across two pre-change 100-call samples, return inference measured about
0.0251-0.0253s, direct rendering about 0.0433-0.0437s, argument rendering about
0.0210-0.0212s, vector length rendering about 0.1236-0.1263s, and join rendering
about 0.0998-0.1036s. The retained path recognizes only an identifier whose
prepared local type is `std::shared_ptr<EReg>`, the method `split`, and arity
one. It returns the known `std::vector<std::string>` carrier and renders the
target-owned call without general instance-owner discovery. Exact fixture
assertions preserve `block->split("a")`, its String argument, vector `.size()`,
and `__hxhx_join(...)` output.

Two final 100-call samples measured about 0.0062-0.0063s for return inference,
0.0225-0.0229s for direct rendering, 0.0209-0.0212s for argument rendering,
0.0464-0.0468s for length rendering, and 0.0450-0.0457s for join rendering.
Argument rendering is intentionally unchanged; the other isolated phases fell
by roughly 48% to 75%.

A rebuilt current-source warm trace retained the same 280 typed modules and
384-helper inventory: 253 full bodies, 83 declaration-only helpers, and 48
runtime-owned helpers. Statement indices 41-50 fell from about 0.932430s to
0.739076s. Index 42, the selected split-chain statement, fell from about
0.260401s to 0.105550s, roughly 59.5%. `TestEReg.test` fell from about
1.742630s to 1.510947s, roughly 13.3%. Earlier controls were also somewhat
faster in this run (`TestBytes.test` by about 5.0% and `TestXML.testBasic` by
about 1.4%), but the targeted statement moved substantially more than either
control. The 480s probe reached beyond `TestResource` and timed out during
`TestInt64`, so strict Cpp remains expected-red. Relevant logs are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-split-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-after-typed-split-warm.log`

The disposable external upstream 4.3.7 worktree was removed after the run.
The next repeated bounded family is fresh `EReg.map(...)` callback rendering
at statement indices 43 and 44. Those statements total about 0.218876s, with
about 0.210648s in their typed callback render phase. Follow-up bead
`haxe_ocaml-j941e` owns a focused callback fixture before any broader function
or instance-argument shortcut is considered.

This remains a documented target-owned branch inside the existing Cpp
dispatcher. It adds no runtime or stdlib implementation and changes no
unsupported receiver or method behavior. Broader Cpp render/type-flow
extraction remains owned by `haxe_ocaml-36ec`. Committed bootstrap snapshots
are not regenerated because the slice changes neither the bootstrap interface
nor snapshot acceptance.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this internal render-latency improvement does not change
public production readiness.

## 2026-07-10 Fresh EReg Map Callback Leaf Fast Path

Follow-up bead `haxe_ocaml-j941e` isolated fresh `EReg.map(...)` callback
adaptation after the typed-local split improvement. The two selected statements
at indices 43 and 44 totaled about 0.218876s, including about 0.210648s in their
typed `std::function<std::string(std::shared_ptr<EReg>)>` callback render phases.

The first focused fixture separated full fresh-map rendering, known-owner
argument rendering, typed lambda adaptation, direct callback-body rendering,
standalone EReg leaf rendering, and the existing generic String/body probes.
It confirmed that the existing EReg-to-String concatenation helper still spent
most of its time rediscovering callback-owned `matched*` leaves. A first narrow
literal/direct-leaf shortcut improved the interpreter fixture, but the first
rebuilt current-source trace rejected it as the selected strict boundary:
indices 43 and 44 and their approximately 0.105s callback phases did not move,
and the method-level change matched control noise. That trace is retained as
negative evidence rather than presented as an improvement.

A behavior-level upstream 4.3.7 oracle check then showed that the selected
callbacks continue from a matched String into a String slicing call. No
upstream fixture was copied. A distinct repo-owned fixture uses different
literals and indices to measure a callback-owned `matched`/`substr` chain. In
its pre-shortcut 100-call sample, full map rendering measured about 0.489044s,
known-owner argument rendering about 0.496950s, nested typed-lambda adaptation
about 0.240668s, and its direct nested body about 0.197422s. The same nested
leaf rendered through the general standalone path in about 0.153195s.

The retained helper is confined to an EReg-to-String concatenation callback
whose single typed argument is the callback receiver. It directly preserves
String literals, callback-owned zero-argument `matchedLeft`/`matchedRight`, a
literal-index `matched`, and a literal-index `matched(...).substr(...)` chain.
All other leaves still call the canonical String renderer. Focused decline
assertions cover other receivers, unsupported methods, non-literal match and
substr indices, non-EReg arguments, non-String returns, and non-concatenation
callbacks. Exact assertions freeze the full target-owned map call, typed lambda,
concatenation, matched calls, and nested substr output.

Two final 100-call samples measured about 0.291510-0.291960s for the full map,
0.288123-0.289503s for known-owner arguments, 0.002326-0.002340s for the nested
typed lambda, and 0.000904-0.000926s for its direct nested body. The standalone
general nested leaf remained about 0.158684-0.160503s, confirming that the
shortcut does not broaden ordinary EReg or String call rendering.

The final rebuilt current-source warm trace retained the same 280 typed modules
and 384-helper inventory: 253 full bodies, 83 declaration-only helpers, and 48
runtime-owned helpers. Index 43 callback adaptation fell from about 0.105812s
to 0.051508s and its complete statement from about 0.109953s to 0.055540s.
Index 44 callback adaptation fell from about 0.104836s to 0.051652s and its
statement from about 0.108923s to 0.055613s. Combined, the selected callback
phases fell by about 51.0% and their statements by about 49.2%. Statement
indices 41-50 fell from about 0.739076s to 0.600665s.

`TestEReg.test` fell from about 1.510947s to 1.336176s, roughly 11.6%. Controls
were also faster: `TestBytes.test` by about 3.7% and `TestXML.testBasic` by
about 6.3%. The selected callback phases moved by about 51%, substantially more
than either control, while the method-level result is treated more cautiously.
The 480s trace again timed out during `TestInt64`, so strict Cpp remains
expected-red. Relevant logs are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-map-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-after-map-callback-warm.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-map-final-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-after-nested-map-callback-warm.log`

Both disposable external upstream 4.3.7 worktrees were removed after their
runs. Eight inline EReg-to-String callbacks now retain a nearly uniform
0.050906-0.051980s setup floor, about 0.410834s total, even though the focused
direct body is nearly free. Follow-up bead `haxe_ocaml-bqd0n` owns opt-in phases
inside typed lambda setup and scope restoration before another shortcut is
considered.

This remains a bounded extension of the existing EReg callback-concatenation
helper, not a general lambda, EReg, or String dispatch path. It adds no runtime
or stdlib implementation. Broader Cpp render/type-flow extraction remains
owned by `haxe_ocaml-36ec`. Committed bootstrap snapshots are not regenerated
because the slice changes neither the bootstrap interface nor snapshot
acceptance.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this internal callback-render improvement does not change
public production readiness.

## 2026-07-10 EReg Callback Setup Phase Timing

Follow-up bead `haxe_ocaml-bqd0n` added opt-in inner timing around direct typed
lambda rendering without changing generated C++. The phases separate expected
function argument and return parsing, lambda header construction, local type
and name map copies, callback argument registration, direct EReg body
recognition/rendering, fallback body rendering, scope restoration, and final
lambda assembly. They run only when the existing filtered Cpp statement trace
and `HXHX_TRACE_STAGE3_CPP_LAMBDA_PHASES=1` are both enabled. Keeping the inner
flag separate preserves comparable outer statement and method timing when only
the broad trace is requested.

A rebuilt current-source warm trace retained the same 280 typed modules and
384-helper inventory: 253 full bodies, 83 declaration-only helpers, and 48
runtime-owned helpers. For selected inline callback indices 43 and 44,
expected-argument parsing measured about 0.000044s each, expected-return parsing
about 0.000012-0.000013s, header construction about 0.000015-0.000018s, local
type copying about 0.000010s, local name copying about 0.000006s, callback
registration about 0.000002-0.000003s, and direct EReg body rendering about
0.000038s. Direct-body selection, restoration, and assembly were at or below
about 0.000002s each. The measured inner work totals only about 0.000132s per
selected callback, while the enclosing expected-function render remains about
0.0513s.

The focused 100-call fixture closes that attribution gap. Full
`valueExprForExpectedType` adaptation for the direct typed lambda measured
about 0.291614-0.305562s. The function-specific preflights after the general
value cascade were negligible: dynamic identity about 0.000072-0.000074s,
bound-function recognition about 0.000015s, and Reflect varargs recognition
about 0.000009-0.000010s. Direct typed-lambda rendering measured about
0.004159-0.006684s. The repeated cost therefore belongs to the general value
adaptation probes before the existing raw-lambda/function-expected branch, not
to expected-function parsing, lambda scope copying, EReg body rendering, or
scope restoration.

No shortcut is retained in this diagnostic slice. Follow-up bead
`haxe_ocaml-r902r` owns an early path limited to a syntactic `ELambda` with a
C++ function expected type. Non-lambda function values and non-function
expected types must retain the existing identity, bind, Reflect varargs,
optional-lambda, bound-method, method-value, and general value-adaptation paths.

The seeded and warm traces are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-lambda-phase-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-lambda-phase-warm.log`

The warm run timed out during `TestInt64` as expected. The external upstream
4.3.7 worktree was removed afterward. No method-level performance delta is
claimed because the added nested trace records intentionally perturb enclosing
timings; their inner clocks and the scaled fixture are the diagnostic evidence.

This is opt-in timing inside the existing Cpp lambda/value-render seam and adds
no runtime, stdlib, or output behavior. Broader Cpp render/type-flow extraction
remains owned by `haxe_ocaml-36ec`. Committed bootstrap snapshots are not
regenerated because the slice changes neither the bootstrap interface nor
snapshot acceptance.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this diagnostic does not change public production readiness.

## 2026-07-10 Direct Expected-Function Lambda Fast Path

Follow-up bead `haxe_ocaml-r902r` moved only a raw `ELambda` with an expected
C++ function type ahead of the general value-adaptation probes that cannot
match that syntactic shape. The shortcut delegates to the existing typed-lambda
renderer, so capture, expected argument and return types, local scope
shadowing/restoration, callback bodies, and generated C++ remain owned by the
canonical path. Named function values, bound calls, Reflect varargs, non-lambda
expressions, and non-function expected types continue through general value
adaptation.

Focused hit/decline assertions freeze that boundary and the exact nested
`std::function<std::string(std::shared_ptr<EReg>)>` lambda output. In two final
100-call samples, full expected-function value adaptation fell from the prior
0.291614-0.305562s range to 0.002460-0.002530s. The complete map fixture measured
0.043114-0.045682s, known-owner argument rendering 0.041042-0.044445s, direct
typed-lambda rendering 0.003615-0.003817s, and the nested callback
0.002445-0.002474s.

The rebuilt current-source warm trace retained the same 280 typed modules and
384-helper inventory: 253 full bodies, 83 declaration-only helpers, and 48
runtime-owned helpers. Index 43 expected-function adaptation fell from
0.051508s to 0.000121s and its complete statement from 0.055540s to 0.004166s.
Index 44 adaptation fell from 0.051652s to 0.000116s and its statement from
0.055613s to 0.004156s.

Across all eight inline EReg-to-String callbacks, expected-function adaptation
fell from 0.410734s to 0.001000s, about 99.76%. The seven callback statements at
indices 43-47, 49, and 50 fell from 0.389602s to 0.031516s, about 91.91%, while
the broader indices 41-50 window fell from 0.600665s to 0.251815s, about 58.08%.
`TestEReg.test` fell from 1.336176s to 0.748521s, about 43.98%. The nearby
controls moved much less and in opposite directions: `TestBytes.test` was about
6.9% faster while `TestXML.testBasic` was about 4.8% slower. The callback and
method deltas are therefore treated as localized evidence, not as a full-target
throughput claim.

The 480s trace timed out at the start of `TestResource` as expected, so strict
Cpp remains red. Relevant logs are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-direct-lambda-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-after-direct-expected-lambda-warm.log`

The disposable external upstream 4.3.7 worktree was removed after the run.
Indices 41 and 42 are now the top `TestEReg.test` statements at about 0.112885s
and 0.106976s. Each passes a scope-typed String identifier whose final render is
only about 0.000013s but whose enclosing parameter render remains about
0.055-0.056s. Follow-up bead `haxe_ocaml-neeo0` owns diagnostic attribution of
the intervening class/enum/value probes before any further shortcut is chosen.

This remains a narrow ordering optimization inside the existing value/lambda
render seam and adds no runtime or stdlib behavior. Broader Cpp render/type-flow
extraction remains owned by `haxe_ocaml-36ec`. Committed bootstrap snapshots are
not regenerated because the slice changes neither the bootstrap interface nor
snapshot acceptance.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this internal render-latency improvement does not change
public production readiness.

## 2026-07-10 Matched String Call-Argument Phase Timing

Follow-up bead `haxe_ocaml-neeo0` added an opt-in detail flag around the
unmeasured declared-enum, enum, and structural-typedef probes in
`callArgExprForParam`. The diagnostics do not change generated C++. A focused
fixture now reproduces the remaining `TestEReg.test` shape with a local named
`test`, prepared as `std::string`, passed to an expected String parameter. It
freezes the exact direct `test` output and confirms that the value is neither an
enum reference nor a structural typedef value.

Two cold 100-call samples measured full argument rendering at 0.286472s and
0.285453s. The structural-typedef lookup alone measured 0.263097s and
0.265933s, about 91.8-93.2% of the full path. Each enum probe measured only
about 0.000033-0.000036s, actual-type lookup about 0.00104-0.00107s, and final
identifier rendering about 0.00123-0.00132s.

The rebuilt current-source detail trace retained 280 typed modules and the
same 384-helper inventory: 253 full bodies, 83 declaration-only helpers, and
48 runtime-owned helpers. At statement index 41, the structural-typedef probe
measured 0.054136s out of a 0.055775s parameter render. At index 42 it measured
0.053918s out of 0.055553s. Both are about 97.06%; their declared-enum and enum
probes were at timer resolution, actual-type lookup was about 0.000010s, and
final rendering about 0.000016-0.000020s.

The detail records did not materially perturb the enclosing result:
`TestEReg.test` measured 0.750973s versus 0.748521s in the preceding broad
trace. Index 41 measured 0.112638s and index 42 0.106813s. Controls were
`TestBytes.test` at 7.199936s and `TestXML.testBasic` at 7.517039s. The 480s
trace timed out during `TestInt64` as expected, so strict Cpp remains red.
Relevant logs are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-string-arg-detail-seed.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-testereg-string-arg-detail-warm.log`

The disposable upstream 4.3.7 worktree was removed after the run. No shortcut
is retained in this diagnostic slice. Follow-up bead `haxe_ocaml-47jmk` owns a
condition reorder limited to declining structural-typedef discovery before the
lookup when `actualType == valueType`; mismatched types must retain the existing
lookup and structural conversion.

This remains opt-in timing and focused benchmark coverage inside the existing
call-argument seam. Broader Cpp render/type-flow extraction remains owned by
`haxe_ocaml-36ec`. Committed bootstrap snapshots are not regenerated because
the slice changes neither the bootstrap interface nor snapshot acceptance.

Focused validation for this slice includes:

- `npm run test:m14:cpp-native-backend-smoke`
- `npm run test:m14:cpp-helper-render-bench`
- `npm run test:m14:cpp-strict-frontier-summary`
- `npm run guard:cpp-render-type-flow-plan`
- `npm run guard:mega-file-gravity-watch`
- `npm run guard:hx-format:changed`
- `npm run guard:hx-format`
- `git diff --check`

README Goals and North Star progress bars remain unchanged. Strict Cpp remains
expected-red, and this diagnostic does not change public production readiness.

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
