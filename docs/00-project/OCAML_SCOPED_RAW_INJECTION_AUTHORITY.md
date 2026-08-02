# OCaml Scoped Raw Injection Authority

This is the design record for a narrow, metadata-based authority island for raw
OCaml injection in `reflaxe.ocaml` / `hxhx` OCaml lanes.

Status: design policy, not yet a full analyzer implementation.
Owning bead: `haxe.ocaml-x0r2`.

## Decision

Use target-specific metadata named `@:ocamlAllowRaw` for rare low-level
abstraction modules that must call raw `__ocaml__` while strict application
boundary checks are enabled.

This metadata is an exception marker, not a normal user feature.

Default policy remains:

- application code should not use raw `__ocaml__` directly;
- reusable target behavior should be expressed through typed externs, core APIs,
  target runtime modules, or compiler intrinsics;
- the global `metal` profile must continue rejecting raw `__ocaml__` even if a
  module is tagged with `@:ocamlAllowRaw`.

## Why This Exists

Raw target injection is powerful but it is also the fastest way to create an
unanalyzable target-specific codebase. If every missing runtime or stdlib feature
is solved by dropping OCaml snippets into application code, the compiler loses
clear contracts for portability, profile checking, optimization, and release
claims.

At the same time, some low-level framework or stdlib abstraction modules need a
short escape hatch while a typed extern/runtime boundary is still being built.
Examples include tiny bridges around runtime internals or platform APIs whose
safe typed shape is the real public API.

`@:ocamlAllowRaw` makes those islands explicit and reviewable without weakening
the broader no-raw-app-code rule.

## Sibling Comparison

### `haxe.go`

`haxe.go` uses Reflaxe target-code injection through `__go__` and keeps it out of
normal app/examples by default:

- `BoundaryEnforcer` forbids raw `__go__` in strict examples.
- `StrictModeEnforcer` forbids raw `__go__` in strict application sources.
- `MetalLaneEnforcer` forbids raw `__go__` in `@:goMetal` lanes.
- `PortableNativeImportGate` separately warns/errors for target-native `go.*`
  surface usage in portable profiles.
- `@:goAllowRaw` authorizes narrow framework-owned raw islands.

The architectural rationale is useful for OCaml: raw injection must not become a
substitute for typed interop (`@:go.import`, `@:go.name`, etc.) or runtime/helper
modules. It is only a last-resort bridge for controlled low-level abstractions.

### `reflaxe.rust`

`reflaxe.rust` uses `__rust__` and `@:rustAllowRaw`:

- strict mode rejects raw app-side `__rust__`;
- `@:rustAllowRaw` marks a module/type as an authority island;
- the authority marker resolves to the owning module;
- metal cleanliness is enforced separately, so `@:rustAllowRaw` does not bypass
  Rust's global or source-local metal restrictions.

This maps closely to the desired OCaml behavior. The important part is not the
exact implementation shape; it is the separation between a strict app-boundary
exception and the stricter native-performance contract.

### Local OCaml Architecture

Current OCaml surfaces differ from Go/Rust in a few important ways:

- Stage0 `reflaxe.ocaml` already has `StrictModeEnforcer`, which rejects raw
  `__ocaml__`, reflection, and explicit `Dynamic` in global metal or
  `ocaml_strict` builds.
- Stage3 native `hxhx` has `MetalProfileVerifier`, which rejects all `untyped`
  expressions in `metal` before emit.
- `hxhx-macro-host` already has `hxhxmacrohost.OcamlInjection`, a typed macro
  shim for repo-owned macro-host internals.
- `ocaml.*` native surfaces are tracked separately through the portable native
  surface policy.

Because Stage3 metal currently rejects `untyped` broadly, `@:ocamlAllowRaw`
should not weaken metal. It should only be considered by strict application
boundary checks in portable-style lanes where raw target injection is already
technically available but intentionally discouraged.

## Metadata Shape

Name: `@:ocamlAllowRaw`

Allowed placement:

- class
- enum
- abstract
- typedef

Initial implementation should resolve the marker to the owning module. A tagged
primary type authorizes the whole module file, matching the sibling-family model
and avoiding surprising per-method behavior.

Do not introduce method-level authority initially. If a file has grown so large
that method-level exceptions feel necessary, split the low-level bridge into a
smaller module first.

## Lane And Profile Boundaries

| Scope | Raw `__ocaml__` default | Effect of `@:ocamlAllowRaw` |
| --- | --- | --- |
| Normal portable app code | Discouraged; may be accepted by current backend if no strict policy is enabled | Should authorize strict-boundary exceptions only for the tagged module once an analyzer exists |
| Portable strict user boundaries | Rejected by strict boundary policy | Allowed only in the tagged low-level module, with documentation and tests |
| `-D ocaml_profile=metal` | Rejected | Still rejected |
| Stage3 `MetalProfileVerifier` | Rejects `untyped` broadly | Still rejected |
| Repo-owned macro-host internals | Prefer typed shim `hxhxmacrohost.OcamlInjection` | Metadata is optional policy documentation, not a bypass |
| Public examples/quickstarts | Should not use raw `__ocaml__` | Do not use as teaching material |

## Documentation Requirements

Every `@:ocamlAllowRaw` module must have HaxeDoc or nearby technical docs that
answer:

- Why raw OCaml is necessary here.
- What typed Haxe API callers should use instead.
- How the raw snippet preserves Haxe semantics.
- Why a typed extern, runtime support module, or intrinsic is not enough yet.
- What the migration/exit criterion is for removing the raw island.
- Which focused regression proves the allowed island and which negative test
  proves non-authorized raw app code is still rejected.

Public README and getting-started docs should not teach `untyped __ocaml__` as a
normal production workflow. If raw injection must be mentioned, describe it as a
low-level target-authoring escape hatch and link here.

## Implementation Plan Before Coding

A future implementation bead should add the analyzer in a small, test-first
slice:

1. Add an `OcamlRawInjectionAuthorityAnalyzer` that collects `@:ocamlAllowRaw`
   declarations from typed module types and resolves them to owning modules.
2. Teach Stage0 `StrictModeEnforcer` to allow raw `__ocaml__` only when the
   current strict scope is portable `ocaml_strict`, not global metal, and the
   module is authorized.
3. Keep `MetalProfileVerifier` unchanged unless a separate metal design review
   proves a safe typed replacement. The current policy is to continue rejecting
   all raw/untyped fallback there.
4. Add a positive regression for a tagged portable low-level module.
5. Add negative regressions proving normal strict app code and
   `ocaml_profile=metal` still reject raw injection.
6. Update `scripts/ci/no-dynamic-check.js` only if the analyzer creates a stable
   first-class allowlist model; until then, keep CI guard exceptions explicit and
   narrow.

## Non-Goals

- This does not authorize raw OCaml in app business logic.
- This does not make raw injection part of the beginner-facing API.
- This does not bypass global metal or Stage3 native profile checks.
- This does not replace typed externs, runtime modules, or compiler intrinsics.
- This does not permit copying upstream compiler implementation code.
