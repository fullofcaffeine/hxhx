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

- Added `packages/hxhx-core/src/HihBackendDialect.hx`.
- Introduced `HihBackendDialect` with three methods:
  - `runtimeIsNull(...)`
  - `runtimeDynamicEquals(...)`
  - `dynamicNullValue()`
- Added `HihOcamlBackendDialect` as the current OCaml implementation.
- Routed switch-pattern null/equality lowering in `EmitterStage` through this dialect seam.

This is intentionally small: it proves the extraction shape without changing emitted OCaml semantics.

## Backend contract rung (current implementation)

To reduce backend-selection drift, builtin Stage3 targets now share a canonical registry contract:

- `packages/hxhx-core/src/backend/TargetDescriptor.hx`
- `packages/hxhx-core/src/backend/TargetRequirements.hx`
- `packages/hxhx-core/src/backend/GenIrProgram.hx`
- `packages/hxhx-core/src/backend/BackendRegistry.hx`

This registry is now the source of truth for:

- backend identity (`id`, `implId`)
- compatibility requirements (`genIrVersion`, `macroApiVersion`, `hostCaps`)
- deterministic precedence (`priority`)
- Stage3 capability flags (`supportsNoEmit`, `supportsBuildExecutable`, `supportsCustomOutputFile`)
- codegen input contract naming (`GenIrProgram` v0 alias)

`Stage3Compiler` resolves backends through `BackendRegistry.requireForTarget(...)` rather than hardcoded switch branches.

## GenIR boundary decision (`haxe.ocaml-3b7`)

Chosen path (near-term): **Approach B** from the design options, with a strict cast policy.

- Keep backend dispatch APIs statically typed:
  - `IBackend.emit(program:GenIrProgram, context:BackendContext):EmitResult`
  - `ITargetCore.emit(program:GenIrProgram, context:BackendContext):EmitResult`
- Keep target-core implementations (`OcamlTargetCore`, `JsTargetCore`) free of `program` boundary casts.
- Keep provider registration behind one explicit typed boundary:
  - `BackendRegistry.registerProvider(regs)`

Allowed cast boundaries (narrow and documented):

- Shared backend GenIR boundary helper:
  - `packages/hxhx-core/src/backend/GenIrBoundary.hx`
  - `GenIrBoundary.requireProgram(program:Dynamic):GenIrProgram`
- Stage3 provider boundary seam in `hxhx.BackendProviderResolver.requireProvider(...)`
  (`cast providerContract` after `Std.downcast(..., ITargetBackendProvider)` validation).
- Stage3 reflaxe bridge dispatch for known backend wrapper types in `emitWithBackend(...)`.

Not allowed:

- local `program:Dynamic`/`cast program` helpers duplicated inside target-core codegen classes.
- spreading `GenIrProgram` recovery casts through backend emitters.

Medium-term roadmap:

1. Keep provider dispatch on the current mixed model:
   compile-time known-provider table + typed dynamic provider loading.
2. Replace `GenIrProgram` typedef alias with a concrete wrapper value once backend IR extraction is ready.
3. Keep a single enforcement check in CI so regressions are caught before bootstrap OCaml type-check.

Validation matrix for this boundary:

```bash
haxe -cp packages/hxhx/src -cp packages/hxhx-core/src -cp packages/reflaxe.ocaml/src -cp packages/reflaxe.ocaml/std -main hxhx.Main --no-output -D hih_native_parser
npm run -s test:hxhx:builtin-target-smoke
```

## Target promotion shape (plugin → native without rewrite)

The intended long-term pattern for Reflaxe targets is:

1. **Target Core**
   Pure codegen module: `TargetCore.emit(GenIR, cfg, host) -> EmitResult`.
2. **Plugin wrapper**
   Library/macro activation that feeds the same Target Core.
3. **Builtin wrapper**
   Linked backend implementation that feeds the same Target Core.

Practical outcome:

- “promoting” a target from plugin mode to builtin mode becomes a packaging/loading change,
  not a full codegen rewrite.
- `reflaxe.ocaml` can remain useful both as:
  - a standalone backend for external workflows, and
  - a native `hxhx` backend implementation path.

This promotion lifecycle is why we keep extracting backend contracts now, even while OCaml bootstrap is still the main host substrate.

Pilot status:

- `packages/hxhx-core/src/backend/ITargetCore.hx` defines the reusable target-core contract.
- `packages/hxhx-core/src/backend/TargetCoreBackend.hx` is the generic wrapper adapter (`TargetDescriptor` + `ITargetCore` -> `IBackend`).
- `packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx` is the first concrete target-core pilot.
- `packages/hxhx-core/src/backend/js/JsTargetCore.hx` now applies the same pattern for JS.
- `OcamlStage3Backend` and `JsBackend` now delegate emission to their target-core classes, proving wrapper/core separation without behavior changes.
- `BackendRegistry` now supports a dynamic provider seam (`register`, `registerProvider`, `clearDynamicRegistrations`) so plugin wrappers can join builtin resolution without custom selection paths.
- `Stage3Compiler` now loads provider declarations per request (`HXHX_BACKEND_PROVIDERS` / `-D hxhx_backend_provider=...`) before resolving `--hxhx-backend`, so fallback to builtins stays deterministic when no providers are declared.

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
