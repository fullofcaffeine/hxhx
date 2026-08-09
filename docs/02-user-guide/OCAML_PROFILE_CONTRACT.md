# OCaml Profile Contract (`-D ocaml_profile=portable|metal`)

This document defines the canonical OCaml profile switch used by OCaml backends in this repo (`hxhx` Stage3 and `reflaxe.ocaml` Stage0 runtime planning).

## Goal

Keep build-wide strictness and runtime policy explicit without making users
choose a profile merely to receive efficient OCaml output.

## Product policy (performance)

- `portable` stays the default because `hxhx` must remain cross-target viable.
- `metal` stays the current build-wide strict/selective-runtime preset (no implicit fallback).
- Portable code receives direct typed OCaml lowering whenever the compiler can prove that Haxe behavior is preserved.
- Typed `ocaml.*` APIs and externs express explicit OCaml-native source intent under either profile; the portable native-surface policy reports or rejects that dependency when requested.
- Performance work prioritizes profile-agnostic optimizations. `metal` is not required merely to request faster output.
- Convergence budgets and ratio lanes are tracked by the KPI harness (`scripts/hxhx/bench-kpi.sh`) and documented in:
  - `docs/benchmarks/HXHX_KPI_BASELINE.md`
  - `docs/benchmarks/HXHX_KPI_THRESHOLDS.md`
  - `docs/benchmarks/PORTABLE_BOUNDARY_BOXING_HOTSPOTS.md`

## Accepted values

- `portable` (default)
- `metal`

Any other value is invalid and fails fast.

## Defaulting and normalization

- If `ocaml_profile` is missing or empty, it resolves to `portable`.
- Values are normalized to lowercase (`Portable` becomes `portable`, etc.).
- The normalized value is written back to the effective backend define map.

## Current semantics (today)

- `portable`:
  - current default behavior for OCaml emission.
  - intended to preserve existing Haxe-oriented portability expectations.
  - Stage3 runs a direct-lowering planner, historically named the portable
    auto-metalization planner. It classifies function regions, applies selected
    typed lowerings when they preserve Haxe behavior, and emits a deterministic
    report. Current lowered hotspots include typed `Array.map` and typed
    `Array<String>.join`; no source annotation enables this work.
- `metal`:
  - current build-wide strictness, fallback, and runtime-layering preset.
  - always links any helper module recorded while translating a specific Haxe
    operation, then uses structured target-syntax observations for compiler
    families that have not migrated yet; the locked runtime-source manifest
    supplies dependencies for both.
  - runs `MetalProfileVerifier` before OCaml emit and fails fast on dynamic/reflection-heavy constructs.
  - enables numeric-specialization fallback in Stage3 expression lowering for arithmetic hot paths (reduces `(Obj.magic 0)` poison for mixed numeric forms while keeping explicit verifier guardrails).
  - enables array/string specialization for typed hot paths (`Array.map` and `Array<String>.join`) and fails fast for unsupported non-metal-safe semantics (for example mixed-type array literals or non-`Array<String>` join receivers).

## Runtime capability knobs (Stage0 runtime planning)

`reflaxe.ocaml` Stage0 runtime planning supports explicit capability overrides:

- `-D ocaml_runtime_mode=full|selective`
  - default is profile-driven (`portable => full`, `metal => selective`)
  - explicit value overrides the profile default
  - `none` is intentionally unsupported (fail-fast) to avoid ambiguous no-runtime semantics
  - if you need minimal runtime planning, use:
    - `-D ocaml_runtime_mode=selective`
    - `-D ocaml_runtime_no_infer`
    - optional `-D ocaml_runtime_modules=...`
- `-D ocaml_runtime_modules=HxRuntime,HxArray,...`
  - manual runtime module seed list for selective mode
  - unknown, tooling-only, or profile-incompatible names fail before OCaml output instead of being ignored
- `-D ocaml_runtime_no_infer`
  - disables compiler-observed runtime discovery in selective mode
  - does not remove a helper module that the compiler already recorded as
    necessary for a Haxe operation, generated module, or packaging rule
  - still checks generated target syntax; compilation fails before packaging is
    accepted if the manual list omits an observed runtime module
  - useful for explicit/manual runtime planning experiments
- `-D ocaml_runtime_token_scan_fallback`
  - debug-only selective fallback for token scan merge
  - requires `-D ocaml_runtime_debug_lane` (debug diagnostics lane)
  - ignored when inference is disabled or runtime mode is `full`
- `-D ocaml_runtime_debug_lane`
  - explicit opt-in lane for runtime diagnostics knobs
  - non-release by design; CI/release lanes must keep this disabled
- `-D ocaml_portable_native_surface=warn|allow|error`
  - policy for `ocaml.*` usage while `ocaml_profile=portable`
  - default: `warn`
  - `error`: fail fast on non-portable `ocaml.*` surface usage
  - CI portability lanes (stdlib tier1/full) intentionally run with `error` while local default remains `warn`
- `-D ocaml_atomic_semantics=emulated`
  - portable `haxe.atomic.*` contract selector (default: `emulated`)
  - current implementation is API-compatible single-thread emulation, not hardware/thread-level atomics
  - any non-`emulated` value fails fast (true atomic mode is not available yet)
  - portable builds emit an explicit compile-time diagnostic when `haxe.atomic.*` is used, to avoid overclaiming thread-safety

## Scope

- The value contract (`portable|metal`, defaulting, normalization, invalid-value failures) is enforced on:
  - Stage3 OCaml backend paths (`--ocaml` and compatible OCaml wrappers)
  - Stage0 `reflaxe.ocaml` runtime planning/report generation path
- Stage3 currently runs the metal verifier before emit.
- Stage0 runs strict boundary enforcement in macro-time for:
  - global metal profile (`ocaml_profile=metal`)
  - optional global portable strictness (`ocaml_strict`)
  - optional portable native-surface policy (`ocaml_portable_native_surface`)
- The unpublished source-local metal annotation was removed without a compatibility layer.
- Native JS paths do not enforce this define.

## Failure behavior

Invalid values fail with an actionable message:

- `invalid -D ocaml_profile=<value> (expected portable|metal)`
- `invalid -D ocaml_atomic_semantics=<value> (only emulated is currently supported; true thread-level atomic mode is not available yet)`
- `invalid -D ocaml_runtime_mode=<value> (expected full|selective)`
- `invalid -D ocaml_runtime_mode=none` explains how to use selective mode,
  disable automatic syntax discovery, and supply every module named by the
  fail-closed runtime validation

Metal verifier failures (`-D ocaml_profile=metal`) are formatted with:

- `construct`: what was rejected
- `reason`: why metal mode rejects it
- `migration`: concrete code-level alternative
- `next`: explicit next step (fix in metal or switch lane explicitly)

## Strict default policy (`metal`)

- `metal` is strict-by-default and fail-fast.
- There is **no implicit `metal -> portable` fallback** in normal compile paths.
- Stage0 (`reflaxe.ocaml`) enforces strict application-boundary checks in metal mode:
  - raw `__ocaml__` injection
  - reflection calls (`Reflect.*`, `Type.*`)
  - explicit `Dynamic` annotations in key typed positions
- Stage0 portable builds can enforce the same application-boundary checks for
  the whole build with `-D ocaml_strict`.
- Scoped raw-injection authority is tracked separately in
  `docs/00-project/OCAML_SCOPED_RAW_INJECTION_AUTHORITY.md`; the proposed `@:ocamlAllowRaw` marker is portable-only
  and must not bypass global `metal` rejection of raw `__ocaml__`.
- If compilation must continue without metal constraints, users must explicitly choose:
  - `-D ocaml_profile=portable`
- Explicit fallback lane (Stage0): `-D ocaml_metal_allow_fallback`
  - keeps `ocaml_profile=metal`
  - downgrades strict-boundary violations to warnings/report-only
  - intended for migration/debugging, not release builds
- Any other debug fallback knobs are opt-in diagnostics tooling and are non-release.

## Compile reports

`reflaxe.ocaml` emits machine-readable profile/runtime plan reports into `ocaml_output`:

- `ocaml_profile_report.json`
  - `schemaVersion` (current: `3`)
  - `requestedProfile`
  - `normalizedProfile`
  - `atomicSemantics`
  - `runtimeMode`
  - `portableNativeSurfacePolicy`
  - `strictUserBoundaries`
  - `metalFallbackAllowed`
  - verifier summary fields; `strictScope` is `disabled`, `global_strict`, or
    `global_metal`. Schema 3 removes the former module-lane inventory because
    source-local metal annotations are no longer part of the contract.
- `ocaml_runtime_plan_report.json`
  - `schemaVersion` (current: `2`)
  - `profile`
  - `runtimeMode` (`full` or `selective`)
  - `selectionMode`
    - `full` (all runtime modules)
    - `requirements` (only helpers backed by explicit compiler requirement
      records, plus the core runtime)
    - `requirements_plus_compiler_observed` (those recorded helpers plus
      runtime references found in structured target syntax or explicitly
      declared by compiler-generated modules; the metal default while other
      compiler families migrate)
    - `requirements_plus_manual` (recorded helpers plus explicit manual
      seeds, with automatic compiler-observed selection disabled)
    - `requirements_plus_compiler_observed_plus_manual` (recorded helpers,
      compiler observations, and manual seeds)
    - `compiler_observed` (temporary selective fallback when no explicit
      requirement exists)
    - `compiler_observed_plus_manual` (that fallback plus manual seeds)
    - `manual_only` (legacy/unmigrated-only case with manual seeds and no
      explicit requirement)
    - `minimal_core` (no requirement, observed root, or manual seed;
      core runtime only)
    - each selective mode may end with `_plus_token_scan_fallback` when debug fallback is enabled
  - `availableModules`
  - `trackedModules` (the schema-2 name for compiler-observed runtime modules;
    these come from structured target syntax and explicit declarations made
    by compiler-generated string/template modules)
  - `manualModules` (manual selective seeds)
  - `runtimeInferenceDisabled`
  - `runtimeDebugLaneEnabled`
  - `tokenScanFallbackEnabled` (`true` only when debug fallback define is enabled)
  - `selectedModules`
  - `selectedFeatures`
  - `inclusionReasons` (deterministic per-module reason list)
- `ocaml_runtime_requirement_report.json`
  - `schemaVersion` (current: `5`)
  - `authorityStatus` (currently `partial`, because some generated runtime uses
    still have only module-name observations rather than one exact source
    operation or compiler decision)
  - `recordedSemanticCapabilities` and
    `recordedRequirementSourceKinds`; both lists are derived from this
    compilation's sealed requirement records rather than a manually maintained
    global coverage summary
  - `runtimeMode` and `selectionMode`
  - `requirementRevision` and `runtimeSourceRevision`
  - `requirements`, where each entry explains what needs compatibility
    support, the compiler decision that caused it, and its runtime root module
  - `subject`, which separates the kind and stable identity of the thing being
    supported; examples are `haxe-type:Int`,
    `generated-module:HxTypeRegistry`,
    `compiler-policy:runtime-packaging`, and
    `native-boundary:sys.io.Stdio::sys.io._Stdio.NativeHxStdio.flush -> HxStdio.flush`
    (`_Stdio` is Haxe's canonical namespace for a private extra type declared
    in `Stdio.hx`, not an OCaml module users must write)
  - `requirementChains`, which resolve each explanation through the locked
    runtime dependency catalog
  - `requirementRootModules`; a root is the first compatibility helper directly
    selected by a recorded compiler decision
  - `requirementClosureModules` and `runtimeSources`, which follow those roots
    through dependencies and include exact source hashes, Dune libraries,
    eligible profiles, and licenses
  - `compilerObservationGranularity` (currently `module-name-only`) and
    `compilerObservedModules`
  - `compilerObservedModulesWithRequirementRoots` and
    `compilerObservedModulesWithoutRequirementRoots`; these report module-name
    overlap only and do not claim that every generated use of an overlapping
    module has its own explanation
  - `requirementRootsNotCompilerObserved`, which keeps deliberate packaging
    requirements visible even when no generated expression refers to them
  - source locations use project-relative or stable library labels; generated
    reports do not retain a developer's home-directory or tool-cache prefix
- `ocaml_runtime_selection_shadow_report.json`
  - `authorityStatus` is `observation-only`: this report never chooses or copies
    a runtime file
  - `runtimeMode`, `selectionMode`, and `requirementRevision` bind the comparison
    to the exact current packaging policy and sealed requirement ledger
  - `currentSelection` describes the roots, dependency closure, checked source
    paths and SHA-256 identities, and reasons used by today's compiler
  - `requirementsOnlySelection` resolves only the sealed semantic requirement
    roots through the same checked runtime manifest
  - `sourceSelectionStatus` says whether both paths select the same modules and
    exact source bytes; `exactComparisonStatus` additionally requires the same
    direct roots and reasons
  - `differences` keeps current-only and requirements-only roots, modules,
    source files, changed source identities, and reasons separate so a
    redundant observation is not confused with a missing runtime file
  - a mismatch blocks removing the current selection path; a match is useful
    evidence but does not authorize removal by itself. The private-runtime
    legacy inventory must also reach zero and every generated helper use must
    reconcile with one sealed compiler decision.
- `ocaml_lowering_report.json` when `-D ocaml_lowering_report` is enabled
  - `schemaVersion` (current: `46`)
  - local identities use the `lexical-local-v1` form. They describe the
    variable's stable lexical declaration inside its owning function rather
    than exposing the Haxe macro process's temporary numeric variable ID.
    Unchanged source therefore produces comparable local and plan evidence
    across clean compiler processes.
  - the sealed assignment/update plans and their source locations
  - `anonymousStructures` describes each admitted mutable anonymous-object
    shape before OCaml text is written. It lists the exact Haxe field types,
    OCaml storage types, aliasing and mutation rules, and the representation
    revision that generated code must use.
  - `anonymousStructureOperations` describes each admitted object creation,
    field initialization, field read, plain field write, and `Int +=` field
    update. Each entry records the source location, owning object shape, field
    conversion, result type, runtime requirements, and observable evaluation
    order. For example, an `Int +=` entry states that the object is evaluated
    once, its old field is read, the right-hand side is evaluated once, Haxe
    Int addition is applied, and the result is stored and returned. Its runtime
    requirements therefore name both `HxAnon` for mutable field storage and
    `HxInt` for Haxe integer arithmetic. Field names are sorted only to give a
    stable object-shape identity; literal initializers retain their original
    source order so their side effects do not move.
    The proof applies to each admitted occurrence, not to every expression in
    its function. A function may also pass an object through `Dynamic` or use
    it in a pattern; those operations stay outside this plan even when the
    direct literal and its initializers are recorded.
    Signed-overflow validation uses stock Haxe eval and Neko as the 32-bit
    behavior oracle. Stock JavaScript stores `Int` in JavaScript numbers, so
    its `2147483647 + 1` result is `2147483648`; native OCaml intentionally
    matches the wrapping eval/Neko result `-2147483648` through `HxInt`.
  - `callModel`, `callableBoundaries`, and `calls`, which show what each
    admitted Haxe function accepts and returns, how each source argument is
    represented before and after the call boundary, and the exact source-order
    schedule used before invocation. For example, an `Int` passed to an exact
    `Null<Int>` parameter records one `box-exact-int-to-nullable-int`
    conversion; an existing `Null<Int>` records a carrier-preserving crossing.
    This makes the conversion inspectable before OCaml syntax is written.
  - a call with `kind: standard-imap-method` includes
    `standardIMapTarget`. This is the complete target decision for one call
    whose receiver is the standard `haxe.Constraints.IMap<K, V>` interface:
    the fixed `String`, `Int`, or non-generic class key family, selected
    `HxMap` carrier and operation, receiver-and-argument schedule, result
    adapter, text conversion policy when needed, and exact runtime
    capabilities. For example, `values.get(key)` on
    `IMap<String, Int>` records `HxMap.string_map`, `get_string`, and a
    `Null<Int>` result before target syntax. The current record applies to
    values originating from the standard Map specializations. Enum-key maps,
    structural or type-parameter keys, and arbitrary user implementations are
    not supported by this boundary; user implementations need a separate typed
    interface conversion and dispatch contract.
  - `controlModel`, `controls`, and `controlTargets`, which show the exact
    function or loop affected by an admitted non-local transfer. Exact
    `Null<Int>` and `Null<Bool>` early returns record
    `preserve-nullable-carrier`: their existing `Obj.t` value crosses the
    private return signal unchanged, so null and zero/false cannot collapse
    through a second box or unchecked cast.
    An exact `Int` or `Bool` returned early from a function whose result is the
    matching `Null<Int>` or `Null<Bool>` instead records
    `box-exact-int-to-nullable-carrier` or
    `box-exact-bool-to-nullable-carrier`. The value is boxed once before the
    private signal, and the function boundary preserves that resulting
    `Obj.t` carrier. Existing nullable and newly converted early returns may
    share one boundary; an incompatible mixed family fails before output.
    A constructor-produced local of an admitted closed user class records
    `box-and-recover-nominal-value`. Its payload names the exact OCaml record
    type, layout revision, and representation proof selected for the complete
    program. The compiler boxes that same reference only while the private
    signal is in flight and recovers the registered record at the owning
    function boundary. Class parameters, call-produced class locals, and
    `return null` are not implied by this record and remain unadmitted.
    Exact `Null<Int>` and `Null<Bool>` throws also use sealed control records.
    `preserve-nullable-int-throw-carrier` sends the existing nullable Int
    carrier unchanged. `normalize-nullable-bool-throw-carrier` preserves null
    but converts a non-null nullable Bool once into the runtime's unambiguous
    boxed-Bool exception carrier. Both records keep only `Dynamic` as a static
    tag; the exception channel derives `Int` or `Bool` from the actual
    non-null payload, so null reaches only a `Dynamic` catch.
    A throw of one admitted whole-program-monomorphic class records
    `box-nominal-throw-carrier` plus the exact target record name, layout
    revision, and representation proof. Its matching class catch records
    `recover-nominal-value`: it checks the runtime class tag and recovers that
    exact registered record without copying the object. Only `Dynamic` is a
    static throw tag. A real class record contributes its exact tag through
    the existing runtime `__hx_type` marker, while a class-typed null has no
    such marker and therefore reaches only `Dynamic`. The reported proof is
    limited to concrete, non-extern, non-generic classes without hierarchy,
    interfaces, or dynamic methods; it does not admit general class,
    `haxe.Exception`, enum, abstract, or nullable-catch behavior.
    A throw whose static type is `Dynamic` records
    `preserve-dynamic-throw-carrier`. The source value already uses `Obj.t`,
    so the exception channel transports that exact carrier without another
    box. `Dynamic` is the only static tag; the runtime value may add its exact
    primitive or admitted class tag, while null remains `Dynamic`-only. This
    control-only record does not claim that Dynamic storage, calls, operators,
    reflection, public ABI, or the metal profile are generally admitted.
  - `staticStorageRevision`, `staticStorageCount`, and `staticStorage`, which
    record each mutable static cell before type emission, including its owner,
    generated name, Haxe meaning, OCaml storage type, declaration point, and
    initialization order, and direct dependencies on other mutable static
    initializers
  - `runtimeRequirementRevision` and `runtimeRequirementCount`
  - `runtimeRequirements`, where every admitted `HxInt`/`HxArray` need and
    every sealed standard-`IMap` call need explains the Haxe behavior, target
    decision, implementation feature, eligible profiles, and checked runtime
    root that caused it. Standard-`IMap` records name the exact source call and
    may select `HxMap`, `HxIterator`, `HxArray`, `HxString`, or `HxDynamic`
    according to the sealed operation and result adapter.

The lowering report is complete for its stated assignment/update and admitted
standard-`IMap` families. The
runtime-requirement report additionally covers core packaging, the generated
type registry, and declared static native runtime boundaries, but it is still
not complete for the whole program. Runtime
packaging checks that every recorded requirement resolves to selected,
hash-verified source. The separate runtime selection report still includes
compiler-observed roots while the remaining compiler families migrate to the
same explicit model.

`hxhx` Stage3 OCaml emission also emits:

- `ocaml_portable_metalization_plan_report.json`
  - `schemaVersion` (current: `1`)
  - `profile` (`portable`/`metal`)
  - `plannerMode` (`portable_auto_metalization` or `disabled_non_portable_profile`)
  - `summary` (`totalRegions`, `autoMetalizedRegions`, `excludedRegions`, `usedMetalStyleRegions`)
  - `excludedByCode` (deterministic exclusion counts by verifier code)
  - `regions` (deterministic per-function classification with:
    - `status` (`auto_metalized` / `excluded`)
    - `reasonCodes` + `exclusionReasons`
    - `usedMetalStyleLowerings`)

Debug fallback define (non-default, diagnostics only):

- `-D ocaml_runtime_token_scan_fallback`
  - Keeps roots from recorded runtime requirements mandatory and uses compiler
    observations as the normal migration path.
  - Adds legacy output token scanning as a temporary merge source for investigations.
  - The token scan can add a debug root, but it no longer discovers dependencies by searching runtime source text; the checked source manifest owns dependency closure in every mode.
  - Requires `-D ocaml_runtime_debug_lane`; otherwise it is ignored with a warning.
  - Explicitly debug-only (non-release); this does not enable any implicit profile fallback.
  - Ignored in `full` runtime mode and when `-D ocaml_runtime_no_infer` is set.

## Metal verifier code map (common migrations)

- `[untyped_expr]`
  - rejected construct: `` `untyped` expression ``
  - why: bypasses typed lowering/specialization guarantees
  - migration: replace `untyped` with typed abstractions/externs or keep that code in portable profile
- `[reflection_call]`
  - rejected construct: `Reflect.*` / `Type.*` calls (for example `Reflect.field`, `Type.resolveClass`)
  - why: reflection-heavy paths block static specialization in metal mode
  - migration: replace reflection with static/typed APIs and explicit data structures
- `[dynamic_type_hint]`
  - rejected construct: explicit `Dynamic` hints (args/locals/fields/casts/catches)
  - why: `Dynamic` widens the program shape and disables metal specialization
  - migration: replace `Dynamic` with concrete types (or move that code path to portable)
- `[unsupported_expr]`, `[unsupported_semantic]`
  - rejected construct: bootstrap fallback nodes like `EUnsupported(...)`, `ETryCatchRaw(...)`, `ESwitchRaw(...)`
  - why: fallback nodes mean the parser/typer path is still non-metal for that construct
  - migration: rewrite to currently supported typed forms and/or file a metal coverage bead for missing frontend support

## Examples

```bash
# default (portable)
"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml --hxhx-no-emit -cp src -main Main

# explicit portable
"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml --hxhx-no-emit -cp src -main Main -D ocaml_profile=portable

# explicit metal (runtime-layered mode)
"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml --hxhx-no-emit -cp src -main Main -D ocaml_profile=metal
```

## Related docs

- Runtime capability matrix (`portable` vs `metal`): `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md`
- Portable/OCaml-native compatibility map: `docs/02-user-guide/COMPATIBILITY_MATRIX.md`
- Portable stdlib parity baseline and matrix:
  - `docs/00-project/STDLIB_PORTABLE_BASELINE_HAXE_4_3_7.json`
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`
