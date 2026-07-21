# OCaml Profile Contract (`-D ocaml_profile=portable|metal`)

This document defines the canonical OCaml profile switch used by OCaml backends in this repo (`hxhx` Stage3 and `reflaxe.ocaml` Stage0 runtime planning).

## Goal

Make profile selection explicit and deterministic while we evolve portable/metal behavior.

## Product policy (performance)

- `portable` stays the default because `hxhx` must remain cross-target viable.
- `metal` stays the strict performance lane (no implicit fallback).
- Performance work prioritizes profile-agnostic optimizations so portable converges toward metal on compiler workloads.
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
  - Stage3 runs a portable auto-metalization planner that classifies function regions,
    applies selected metal-style lowerings in metal-safe regions, and emits a deterministic
    planner report (current lowered hotspots include typed `Array.map` and typed `Array<String>.join`).
- `metal`:
  - native-oriented runtime layering mode.
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
  - portable metal-islands (`@:haxeMetal` modules)
  - optional portable native-surface policy (`ocaml_portable_native_surface`)
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
- Stage0 portable builds can still enforce strict checks in `@:haxeMetal` modules.
- Scoped raw-injection authority is tracked separately in
  `docs/00-project/OCAML_SCOPED_RAW_INJECTION_AUTHORITY.md`; the proposed `@:ocamlAllowRaw` marker is portable-only
  and must not bypass `metal` or `@:haxeMetal` rejection of raw `__ocaml__`.
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
  - `schemaVersion` (current: `2`)
  - `requestedProfile`
  - `normalizedProfile`
  - `atomicSemantics`
  - `runtimeMode`
  - `portableNativeSurfacePolicy`
  - `strictUserBoundaries`
  - `metalFallbackAllowed`
  - verifier summary fields
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
  - `schemaVersion` (current: `3`)
  - `authorityStatus` (currently `partial`, because core packaging, the
    generated type registry, declared static native runtime boundaries, and
    typed assignment/update operations are covered, while other compiler paths
    still rely on observations)
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
- `ocaml_lowering_report.json` when `-D ocaml_lowering_report` is enabled
  - `schemaVersion` (current: `9`)
  - the sealed assignment/update plans and their source locations
  - `staticStorageRevision`, `staticStorageCount`, and `staticStorage`, which
    record each mutable static cell before type emission, including its owner,
    generated name, Haxe meaning, OCaml storage type, declaration point, and
    initialization order, and direct dependencies on other mutable static
    initializers
  - `runtimeRequirementRevision` and `runtimeRequirementCount`
  - `runtimeRequirements`, where every admitted `HxInt`/`HxArray` need explains
    the Haxe behavior, target decision, implementation feature, eligible
    profiles, and checked runtime root that caused it

The lowering report is complete for its stated assignment/update family. The
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
