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
  - links only runtime modules required by the emitted program + runtime transitive dependencies.
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
- `-D ocaml_runtime_no_infer`
  - disables compiler-tracked runtime inference in selective mode
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
- `invalid -D ocaml_runtime_mode=none (none is not supported; use selective + ocaml_runtime_no_infer + optional ocaml_runtime_modules)`

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
    - `compiler_tracked` (metal default selective)
    - `compiler_tracked_plus_manual` (selective with tracked + manual seeds)
    - `manual_only` (selective, inference disabled with manual seeds)
    - `minimal_core` (selective, no tracked/manual seeds; core runtime only)
    - each selective mode may end with `_plus_token_scan_fallback` when debug fallback is enabled
  - `availableModules`
  - `trackedModules` (compiler-tracked runtime module references)
  - `manualModules` (manual selective seeds)
  - `runtimeInferenceDisabled`
  - `runtimeDebugLaneEnabled`
  - `tokenScanFallbackEnabled` (`true` only when debug fallback define is enabled)
  - `selectedModules`
  - `selectedFeatures`
  - `inclusionReasons` (deterministic per-module reason list)

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
  - Keeps compiler-tracked selection as the primary source of truth.
  - Adds legacy output token scanning as a temporary merge source for investigations.
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
