# HXHX Backend Layering (Plain-English + Engineering Detail)

This guide explains how `hxhx` can evolve from a practical OCaml-bootstrap compiler into a cleaner, target-agnostic compiler core over time.

It is written for two audiences:

- contributors who are not compiler specialists but want to understand the roadmap,
- contributors implementing backend/emit changes who need concrete seam boundaries.

## Why this document exists

Right now, our Stage3 path emits OCaml source directly. That is useful and intentional for bootstrap speed, but it can hide where the true portability boundaries should be.

If we want long-term flexibility (and easier experimentation with additional backends), we need to make those boundaries explicit.

This document is the first published design note for bead `haxe.ocaml-xgv.10.5`.

## Current architecture (today)

In practical terms, the pipeline looks like this:

1. Frontend + typing resolve and type the Haxe program.
2. `EmitterStage` lowers typed/parsed forms directly into OCaml text.
3. OCaml runtime helpers (`HxRuntime`, `HxAnon`, etc.) provide dynamic semantics.

This works, but many runtime-sensitive snippets are currently inlined as OCaml strings.

## Target architecture (incremental, not rewrite-first)

Long-term direction:

1. **Frontend/typing**: language understanding and type reasoning.
2. **Target-agnostic lowering layer**: runtime intent represented in backend-neutral form.
3. **Backend dialect/emitter**: concrete target syntax and runtime call shapes.

Important: we are not doing a big-bang rewrite. We are extracting seams one rung at a time while keeping behavior stable.

## OCaml-coupled seams to extract

These are the main seam categories we should keep pulling behind interfaces/IR nodes:

- **Dynamic equality / null checks**
  - today: inlined `HxRuntime.dynamic_equals`, `HxRuntime.is_null`, `HxRuntime.hx_null`
  - risk: semantics are hardcoded where pattern lowering happens
- **Anonymous-object field access**
  - today: inlined `HxAnon.get/set/...` calls
  - risk: object semantics are tied to one runtime shape
- **Dynamic stringification and casts**
  - today: inlined `Obj.repr`/`Obj.magic` + runtime helpers
  - risk: target-specific coercion details leak into general lowering logic
- **Collection/stdlib bridge calls**
  - today: direct OCaml/runtime call text appears in emission rules
  - risk: difficult to reason about cross-target behavior contracts

## What landed in this rung (`haxe.ocaml-xgv.10.5`)

Minimal proof-of-concept extraction (no behavior change):

- Added `packages/hih-compiler/src/HihBackendDialect.hx`.
- Introduced `HihBackendDialect` with three methods:
  - `runtimeIsNull(...)`
  - `runtimeDynamicEquals(...)`
  - `dynamicNullValue()`
- Added `HihOcamlBackendDialect` as the current OCaml implementation.
- Routed switch-pattern null/equality lowering in `EmitterStage` through this dialect seam.

This is intentionally small: it proves the extraction shape without changing emitted OCaml semantics.

## Why this helps immediately

- Makes OCaml coupling visible and reviewable.
- Reduces “hidden target assumptions” in the core lowering path.
- Creates a safe place to grow backend diversity without destabilizing current gates.

## What this does **not** claim yet

- It does not make `hxhx` target-agnostic today.
- It does not replace the OCaml backend/runtime model.
- It does not introduce a full backend-neutral IR yet.

## Next extraction sequence (recommended)

1. Expand dialect seam to anon-object get/set/has/delete operations.
2. Pull dynamic coercion/stringification snippets into dialect helpers.
3. Introduce a tiny backend-neutral lowering struct for runtime-intent nodes used by multiple sites.
4. Keep proving each rung with regression tests before broadening scope.

## Acceptance checks for this design rung

Use these commands to ensure no regression in current behavior:

```bash
npm run test:hxhx-targets
npm test
npm run ci:guards
```

## Relationship to 1.0 goals

This work supports the `hxhx 1.0` path, but it is not the immediate critical path blocker.

- Immediate blocker remains native `RunCi` progression (`haxe.ocaml-xgv.10.11`).
- This layering work reduces long-term architecture risk and supports future product split/target plans.
