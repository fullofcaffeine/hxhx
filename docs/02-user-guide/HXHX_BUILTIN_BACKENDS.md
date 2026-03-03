# HXHX Builtin Backends (Bundled `--library` vs `--target` Registry)

This document untangles a concept that comes up quickly once `hxhx` exists as a native binary:

- We want `hxhx` to behave like `haxe` (forward-compatible CLI, same mental model).
- We also want a distribution that is *pleasant* to use: common backends can be **bundled** and enabled with a single flag.
- We want a path to **statically linking** some backends into the compiler for performance and tighter integration.

This doc defines a concrete “builtin backend registry” interface and how it interacts with `--library`.

## Terms

- **Stage0 `haxe`**: the upstream OCaml compiler binary installed on the host.
- **Stage0 `hxhx`**: a native OCaml binary built by `reflaxe.ocaml` that still delegates compilation to stage0 `haxe`.
- **Macro backend**: a target implemented as Haxe macro code (e.g. Reflaxe targets like `reflaxe.ocaml`, `reflaxe.elixir`).
- **Bundled backend**: backend source shipped *next to* `hxhx` so users don’t need to install it separately.
- **Builtin backend**: backend code compiled/linked *into* the `hxhx` executable.

Important: “bundled” and “builtin” are orthogonal. A backend can be:

- bundled only (source shipped, still loaded from classpath),
- builtin only (linked in, no source shipped),
- or both (ship source for debugging + link in for fast-path).

## Why do we need a registry at all?

In upstream Haxe, “which target am I compiling to?” is normally selected by *target flags* (`-js`, `-cpp`, `--interp`, etc.)
plus optional macro libraries.

Reflaxe targets are different: they are typically enabled via:

- `--library <target-lib>` (aka `-lib`)
- plus a define-based configuration (e.g. `-D reflaxe-target=ocaml` and `-D ocaml_output=...`)

That’s flexible, but it’s verbose and easy to get wrong.

For `hxhx` distribution goals (Gate 4), we want to be able to say:

- “This `hxhx` build ships with backends X/Y/Z.”
- “Enable backend `elixir` with one flag.”
- “Those backends are version-pinned to the `hxhx` release.”

That implies a small, explicit registry owned by the `hxhx` distribution.

## CLI surface (proposed)

`hxhx` supports two ways to enable backends:

1) **Bundled / explicit macro backends** (the “upstream Haxe” way)

Users pass everything explicitly, and `hxhx` forwards it:

```bash
hxhx ... --library reflaxe.elixir -D reflaxe-target=elixir -D elixir_output=out ...
```

2) **Builtin backend selection** (distribution convenience)

Users pick a target by name:

```bash
hxhx ... --target elixir ...
```

And `hxhx` injects the equivalent `--library`/`-D` flags (or routes to a builtin backend entrypoint).

### Why `--target` and not a new `-D`?

- We want a *single* stable UX for “pick the bundled backend”.
- Defines are appropriate for feature switches, but a registry selection is closer to “which compiler backend”.

Compatibility note:

- Upstream `haxe` does not have a generic `--target <name>` flag, so `hxhx` can safely treat this as a shim-only option
  and strip it before delegating to stage0 `haxe`.

If we discover a conflict, we can rename to `--hxhx-target` without changing the underlying registry design.

## Registry interface (implemented)

Builtin Stage3 backend registration now uses explicit metadata + factory contracts in code:

- `packages/hxhx-core/src/backend/TargetDescriptor.hx`
  - `id`: target ID (`ocaml-stage3`, `js-native`, ...)
  - `implId`: implementation ID (`builtin/js-native`, ...)
  - `abiVersion`, `priority`, `description`
  - `capabilities` (`supportsNoEmit`, `supportsBuildExecutable`, `supportsCustomOutputFile`)
  - `requires` (`genIrVersion`, `macroApiVersion`, `hostCaps`)
- `packages/hxhx-core/src/backend/BackendRegistry.hx`
  - canonical source of builtin backend registrations
  - deterministic resolution (`priority` first, then `implId` tie-break)
  - typed entrypoints:
    - `listDescriptors()`
    - `supportedTargetIds()`
    - `descriptorForTarget(id)`
    - `requireForTarget(id)`
    - dynamic/provider seam:
      - `register(spec)`
      - `registerProvider(regs)` (registers one provider's descriptor/factory list)
      - `clearDynamicRegistrations()`

Current builtin registrations are declared by:

- `packages/hxhx-core/src/backend/ocaml/OcamlStage3Backend.hx`
- `packages/hxhx-core/src/backend/js/JsBackend.hx`

Current codegen contract + target-core pilot:

- `packages/hxhx-core/src/backend/GenIrProgram.hx` defines the Stage3 backend input contract (`GenIR` v0 alias).
- `packages/hxhx-core/src/backend/ITargetCore.hx` defines reusable target-core emission.
- `packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx` and `packages/hxhx-core/src/backend/js/JsTargetCore.hx`
  are current promotion pilots used by builtin wrappers.

`hxhx` target presets (`packages/hxhx/src/hxhx/TargetPresets.hx`) now verify that builtin preset IDs are registered in this canonical registry.

Dynamic registration notes:

- Dynamic registrations are intended for plugin/bundled wrappers that should participate in
  the same precedence logic as builtins.
- Selection rule remains global and deterministic: higher `priority` wins, then `implId`
  lexical tie-break.
- Stage3 now resolves dynamic providers per request (before backend selection) from:
  - explicit provider declarations:
    - `HXHX_BACKEND_PROVIDERS=TypeA;TypeB`
    - `-D hxhx_backend_provider=TypeA`
    - `-D hxhx_backend_providers=TypeA;TypeB`
    - `-D hxhx.backend.provider=TypeA`
  - bundled provider declarations:
    - `HXHX_BACKEND_BUNDLED_PROVIDERS=TypeA;TypeB`
    - `-D hxhx_backend_bundled_provider=TypeA`
    - `-D hxhx_backend_bundled_providers=TypeA;TypeB`
    - `-D hxhx.backend.bundled.provider=TypeA`
- Stage3 can also resolve provider declarations from plugin manifests:
  - explicit manifests:
    - `HXHX_BACKEND_PLUGIN_MANIFESTS=plugins/a.json;plugins/b.json`
    - `-D hxhx_backend_plugin_manifest=plugins/a.json`
    - `-D hxhx_backend_plugin_manifests=plugins/a.json;plugins/b.json`
    - `-D hxhx.backend.plugin.manifest=plugins/a.json`
  - bundled manifests:
    - `HXHX_BACKEND_BUNDLED_PLUGIN_MANIFESTS=plugins/a.json;plugins/b.json`
    - `-D hxhx_backend_bundled_plugin_manifest=plugins/a.json`
    - `-D hxhx_backend_bundled_plugin_manifests=plugins/a.json;plugins/b.json`
    - `-D hxhx.backend.bundled.plugin.manifest=plugins/a.json`
- Manifest schema (v1):
  - `docs/02-user-guide/compat/hxhx-backend-plugin-manifest-v1.schema.json`
  - supported runtime kinds:
    - `linked-provider` (current Stage3 linked-provider load path)
    - `ocaml-dynlink` (native load path now goes through Dynlink in OCaml runtime builds)
- Native plugin host registration ABI (C5R1):
  - runtime bridge module:
    - `packages/reflaxe.ocaml/std/runtime/HxHxBackendPluginHost.ml`
  - Haxe boundary seam:
    - `packages/hxhx/src/hxhx/NativeBackendPluginHost.hx`
    - `packages/hxhx/src/hxhx/NativeBackendPluginHostAbi.hx`
  - side-effect registration contract:
    - plugin entrypoints call `register_provider_type(pluginId, providerType)` during load.
    - host clears capture state before load and reads `snapshot()` after load.
    - snapshot wire format is deterministic:
      - header line `v1`
      - one row per registration: `<pluginId>\t<providerType>`
  - fail-fast validation in host ABI:
    - empty/malformed rows fail with source-labeled diagnostics,
    - pluginId mismatch fails,
    - duplicate providerType rows fail,
    - duplicate descriptor `implId`/target conflicts fail before registry registration.
- Provider type requirement:
  - each declared provider must resolve to a class implementing
    `ITargetBackendProvider` with `new()` and
    `registrations():Array<BackendRegistrationSpec>`.
  - known builtin providers may still be fast-pathed through the compile-time
    provider table in `BackendProviderResolver`.
- Strategy choice (current): **mixed model**.
  - Keep compile-time known-provider fast paths for bundled builtins.
  - Keep typed dynamic loading for plugin/bundled provider classes by type path.
  - Defer macro-generated provider registries until provider count/maintenance
    overhead justifies the extra macro/build complexity.
- Source precedence policy is deterministic:
  - `explicit` plugin declarations override `bundled` declarations.
  - plugin declarations override builtin targets via priority bands.
  - duplicate plugin `implId` declarations in the same source tier fail fast.
- Fallback behavior is explicit: if no provider declarations are present, Stage3 uses builtin
  registrations only (`BackendRegistry.clearDynamicRegistrations()` runs per request).
- Optional diagnostics: `HXHX_TRACE_BACKEND_SELECTION=1` prints selected `implId`, and
  `HXHX_TRACE_BACKEND_PROVIDERS=1` prints provider registration counts.
- Cast policy for `GenIrProgram` boundary:
  - allowed in shared helper `backend.GenIrBoundary.requireProgram(...)` for interface-boundary
    recovery in target cores,
  - at the scoped provider boundary seam in
    `hxhx.BackendProviderResolver.requireProvider(...)`,
  - and at `backend.BackendDispatchBoundary.emit(...)` for Stage3 wrapper fast-path dispatch,
  - Stage3 emit fallback uses typed `IBackend.emit` (no `Reflect.callMethod` path),
  - not allowed inside target-core emitters (`OcamlTargetCore`, `JsTargetCore`).

### Native backend plugin build workflow (`.cmxs` / `.cma`)

Use the native plugin build helper to produce a deterministic artifact bundle:

```bash
bash scripts/hxhx/build-backend-plugin.sh \
  --plugin-id fixture.native.backend.plugin \
  --plugin-version 0.1.0 \
  --kind ocaml-dynlink \
  --source-dir test/fixtures/native_backend_plugin \
  --dune-target hxhx_backend_plugin_fixture.cmxs \
  --entry plugins/hxhx_backend_plugin_fixture.cmxs \
  --target-id js-native \
  --out-dir .tmp/plugin-out
```

Outputs:

- `.tmp/plugin-out/backend-plugin.json` (manifest, schema v1)
- `.tmp/plugin-out/plugins/hxhx_backend_plugin_fixture.cmxs` (native plugin artifact for native host)

For bytecode hosts (`hxhx` `.bc`), build with `.cma` instead:

```bash
bash scripts/hxhx/build-backend-plugin.sh \
  --plugin-id fixture.native.backend.plugin \
  --plugin-version 0.1.0 \
  --kind ocaml-dynlink \
  --source-dir test/fixtures/native_backend_plugin \
  --dune-target hxhx_backend_plugin_fixture.cma \
  --entry plugins/hxhx_backend_plugin_fixture.cma \
  --target-id js-native \
  --out-dir .tmp/plugin-out
```

Runtime load smoke (build + load + emit + run + negative checks):

```bash
npm run test:hxhx:native-plugin-runtime-smoke
```

Note: this smoke defaults to source-lane `hxhx` build (`HXHX_FORCE_STAGE0=1`) so runtime
bridge changes are exercised even when bootstrap snapshots lag. Set
`HXHX_NATIVE_PLUGIN_RUNTIME_STAGE0_BUILD=0` to use the bootstrap lane.

This smoke validates:

- relative and absolute manifest entry path loading,
- backend selection override (`provider/js-native-wrapper`),
- runtime output equivalence (`sum=6`),
- negative diagnostics for missing plugin artifact and ABI mismatch.

Common runtime load failures:

- `native plugin artifact not found`: manifest `backend.entry` path is wrong relative to manifest location.
- `backend ABI mismatch`: plugin manifest `abiVersion` does not match host ABI (`1`).

Manifest-only flow for Haxe providers (no `.cmxs` build step):

```bash
bash scripts/hxhx/build-backend-plugin.sh \
  --plugin-id fixture.haxe.provider \
  --plugin-version 0.1.0 \
  --kind linked-provider \
  --entry my.backend.Provider \
  --target-id js-native \
  --out-dir .tmp/plugin-out
```

### Injection rules (important for predictable UX)

When `--target <id>` is used, injection follows these rules:

- **Additive by default**: inject missing flags, do not rewrite user-provided ones.
- **User flags win**: if the user explicitly passes `--library X` or `-D something=...`, do not override it.
- **Fail fast on contradiction**: if `--target elixir` is used but the user explicitly sets `-D reflaxe-target=ocaml`,
  print an error explaining the conflict.

This keeps `--target` as “a preset”, not a separate parallel configuration system.

## Stage0 delegation guard (runtime policy switch)

To enforce native-path-only invocations in CI or release validation flows, use:

```bash
HXHX_FORBID_STAGE0=1 hxhx ...
```

Behavior:

- any path that would delegate to stage0 `haxe` fails fast with a clear error
- linked builtin Stage3 targets (`--target ocaml`, `--target js`) remain allowed

This lets gates explicitly prove “no stage0 delegation” for selected workflows without removing shim compatibility for other development paths.

## How bundling works (without static linking)

Bundling is the simplest starting point and works well for delegated/compat lanes while native lanes continue to mature:

- `dist/hxhx/.../lib/<backend>/` contains the backend source (and possibly its `haxelib.json`).
- `hxhx` computes its install root (relative to `argv[0]`) and adds `-cp <dist>/lib/...` to the forwarded `haxe` args.
- `--target elixir` injection then adds `--library reflaxe.elixir` (or `-cp` directly) plus required defines.

This gives a “batteries included” UX *without* needing `hxhx` to execute macros itself.

## How builtin linking works (later, when `hxhx` executes macros)

Once `hxhx` is no longer delegating (it types and runs macros itself), we can optionally make some backends “builtin”:

- compile the backend Haxe code to OCaml as part of the `hxhx` build
- link it into the `hxhx` executable
- register it in the backend registry as `kind=builtin` or `kind=both`

At that point, `--target elixir` does **not** need to add `--library reflaxe.elixir` at all — it can call the backend
entrypoint directly.

This is an optimization / integration lever:

- faster startup (no classpath scanning / macro compilation)
- more control over versioning (backend pinned to compiler build)
- possibility of deeper integration (shared caches, structured config)

## Current implementation status

Current `hxhx` target presets:

- `--target ocaml`
  - kind: `builtin`
  - behavior: runs linked `Stage3Compiler` directly (no `--library reflaxe.ocaml` requirement)
- `--target ocaml-compat`
  - kind: `both` (bundled-first, stage0 delegation today)
  - behavior: injects `reflaxe.ocaml` wiring (`-lib`/`-cp`/init macros/defines) and delegates to stage0 `haxe`
- `--target js-compat`
  - kind: `bundled`
  - behavior: delegates to stage0 `haxe` and injects `--js out.js` when no explicit output target is present
- `--target js`
  - kind: `builtin`
  - behavior: routes through linked Stage3 backend dispatch with backend ID `js-native`
  - status: MVP non-delegating JS emitter is enabled (constrained subset; emits one JS file artifact and Stage3 runs it via `node` when available)
- standard `-js` / `--js` (no `--target`)
  - kind: auto-selected builtin path when compatible
  - behavior: routes through linked `js-native` Stage3 backend when no conflicting non-JS target flag is present
  - fallback: if native JS backend is unavailable in the current binary, shim mode falls back to stage0 delegation unless `HXHX_FORBID_STAGE0=1` is set
- `--target flash|swf|as3`
  - status: intentionally unsupported in `hxhx` (fails fast with a clear message)
- raw legacy target flags (`--swf`, `--as3`)
  - status: intentionally unsupported in `hxhx` (fails fast with the same message)
- `--hxhx-strict-cli`
  - status: available
  - behavior: enforces upstream-style CLI surface by rejecting hxhx-only flags (`--target`, `--hxhx-*`), while still allowing upstream JS flags (`-js` / `--js`) to route to linked native JS backend (`id=js-native`)

### Native JS semantics snapshot (MVP)

Canonical 1.0 scope lives in:

- `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`

This matrix is the single source of truth for:

- in-scope semantics,
- out-of-scope boundaries,
- and required regression evidence (fixtures/gates).

Why this matters:

- It is our first concrete linked-backend fast-path (`kind=builtin`) in the registry.
- It gives a no-classpath-scan execution path for OCaml Stage3 bring-up and perf tracking.
- It keeps the stable `--target` UX while we move from stage0 delegation to native `hxhx` execution.
- The JS presets now cover both delegated (`js-compat`) and non-delegating MVP (`js`) paths so CI and Gate wiring can evolve without hidden fallbacks.
- Strict CLI mode provides an explicit upstream-compatibility interface without removing hxhx extension workflows.

## How this relates to the macro “plugin system”

This registry is *not* the macro plugin system itself.

- The macro plugin system is defined by `haxe.macro.Context` hook points and macro execution behavior.
- The backend registry is a distribution-level switchboard for “which backend do you want to use”.

When `hxhx` becomes replacement-ready, both are needed:

- macro execution + hook points (so macro libraries work),
- registry/bundling (so the compiler distribution is ergonomic and reproducible).

See:

- `docs/02-user-guide/COMPILER_PLUGIN_SYSTEM.md:1`
- `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`

## External promotion example: `reflaxe.elixir` (copyleft-safe integration mode)

For `reflaxe.elixir`, this monorepo uses an **external integration workflow**:

- fetch external sources into `vendor/reflaxe-elixir` (git-ignored),
- run promotion/build/load checks from local scripts/CI pilot lanes,
- do **not** vendor/copy `reflaxe.elixir` sources into this MIT repository.

Why:

- `reflaxe.elixir` is copyleft-licensed, so we keep a strict provenance boundary for this MIT monorepo.
- The pilot workflow remains reproducible without mixing tracked source trees.

Canonical workflow and policy:

- `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`

General note:

- “Bundled sources in dist” remains a valid pattern for permissively licensed backends.
- `reflaxe.elixir` is intentionally **external-only** in this repository’s default distribution posture.

## Beads tracking

The implementation work described here should be tracked as a dedicated epic and tasks (see beads).
