# OCaml Profile Contract (`-D ocaml_profile=portable|metal`)

This document defines the canonical OCaml profile switch used by `hxhx` Stage3 OCaml backends.

## Goal

Make profile selection explicit, deterministic, and backward compatible while we evolve portable/metal behavior.

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
- `metal`:
  - native-oriented runtime layering mode.
  - links only runtime modules required by the emitted program + runtime transitive dependencies.
  - runs `MetalProfileVerifier` before OCaml emit and fails fast on dynamic/reflection-heavy constructs.
  - enables numeric-specialization fallback in Stage3 expression lowering for arithmetic hot paths (reduces `(Obj.magic 0)` poison for mixed numeric forms while keeping explicit verifier guardrails).
  - enables array/string specialization for typed hot paths (`Array.map` and `Array<String>.join`) and fails fast for unsupported non-metal-safe semantics (for example mixed-type array literals or non-`Array<String>` join receivers).

## Scope

- The contract is enforced on Stage3 OCaml backend paths (`ocaml-stage3` and compatible OCaml wrappers).
- JS-native paths do not enforce this define.

## Failure behavior

Invalid values fail with an actionable message:

- `invalid -D ocaml_profile=<value> (expected portable|metal)`

Metal verifier failures (`-D ocaml_profile=metal`) are formatted with:

- `construct`: what was rejected
- `reason`: why metal mode rejects it
- `migration`: concrete code-level alternative

## Compile reports

`reflaxe.ocaml` emits machine-readable profile/runtime plan reports into `ocaml_output`:

- `ocaml_profile_report.json`
  - `contractVersion`
  - `requestedProfile`
  - `normalizedProfile`
  - verifier summary fields
- `ocaml_runtime_plan_report.json`
  - `profile`
  - `selectionMode`
    - `full` (portable)
    - `compiler_tracked` (metal default)
    - `compiler_tracked_plus_token_scan_fallback` (metal debug fallback)
  - `availableModules`
  - `trackedModules` (compiler-tracked runtime module references)
  - `tokenScanFallbackEnabled` (`true` only when debug fallback define is enabled)
  - `selectedModules`
  - `selectedFeatures`

Debug fallback define (non-default, diagnostics only):

- `-D ocaml_runtime_token_scan_fallback`
  - Keeps compiler-tracked selection as the primary source of truth.
  - Adds legacy output token scanning as a temporary merge source for investigations.

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
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main

# explicit portable
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main -D ocaml_profile=portable

# explicit metal (runtime-layered mode)
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main -D ocaml_profile=metal
```

## Related docs

- Runtime capability matrix (`portable` vs `metal`): `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md`
- Portable/OCaml-native compatibility map: `docs/02-user-guide/COMPATIBILITY_MATRIX.md`
