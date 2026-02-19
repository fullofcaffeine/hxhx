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

- `packages/hih-compiler/src/backend/TargetDescriptor.hx`
  - `id`: target ID (`ocaml-stage3`, `js-native`, ...)
  - `implId`: implementation ID (`builtin/js-native`, ...)
  - `abiVersion`, `priority`, `description`
  - `capabilities` (`supportsNoEmit`, `supportsBuildExecutable`, `supportsCustomOutputFile`)
  - `requires` (`genIrVersion`, `macroApiVersion`, `hostCaps`)
- `packages/hih-compiler/src/backend/BackendRegistry.hx`
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

- `packages/hih-compiler/src/backend/ocaml/OcamlStage3Backend.hx`
- `packages/hih-compiler/src/backend/js/JsBackend.hx`

Current codegen contract + target-core pilot:

- `packages/hih-compiler/src/backend/GenIrProgram.hx` defines the Stage3 backend input contract (`GenIR` v0 alias).
- `packages/hih-compiler/src/backend/ITargetCore.hx` defines reusable target-core emission.
- `packages/hih-compiler/src/backend/ocaml/OcamlTargetCore.hx` and `packages/hih-compiler/src/backend/js/JsTargetCore.hx`
  are current promotion pilots used by builtin wrappers.

`hxhx` target presets (`packages/hxhx/src/hxhx/TargetPresets.hx`) now verify that builtin preset IDs are registered in this canonical registry.

Dynamic registration notes:

- Dynamic registrations are intended for plugin/bundled wrappers that should participate in
  the same precedence logic as builtins.
- Selection rule remains global and deterministic: higher `priority` wins, then `implId`
  lexical tie-break.
- Stage3 now resolves dynamic providers per request (before backend selection) from:
  - `HXHX_BACKEND_PROVIDERS=TypeA;TypeB`
  - `-D hxhx_backend_provider=TypeA`
  - `-D hxhx_backend_providers=TypeA;TypeB`
  - `-D hxhx.backend.provider=TypeA`
- Provider type requirement:
  - each declared provider must expose static `providerRegistrations():Array<BackendRegistrationSpec>`
  - instance-only `registrations()` providers are intentionally not loaded in Stage3.
- Fallback behavior is explicit: if no provider declarations are present, Stage3 uses builtin
  registrations only (`BackendRegistry.clearDynamicRegistrations()` runs per request).
- Optional diagnostics: `HXHX_TRACE_BACKEND_SELECTION=1` prints selected `implId`, and
  `HXHX_TRACE_BACKEND_PROVIDERS=1` prints provider registration counts.
- Cast policy for `GenIrProgram` boundary:
  - allowed in shared helper `backend.GenIrBoundary.requireProgram(...)` for interface-boundary
    recovery in target cores,
  - and at Stage3 reflection seams (`Reflect.callMethod` provider registration bridge,
    reflaxe backend bridge dispatch for known wrapper types),
  - not allowed inside target-core emitters (`OcamlTargetCore`, `JsTargetCore`).

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
- linked builtin Stage3 targets (`--target ocaml-stage3`, `--target js-native`) remain allowed

This lets gates explicitly prove “no stage0 delegation” for selected workflows without removing shim compatibility for other development paths.

## How bundling works (without static linking)

Bundling is the simplest starting point and works even while `hxhx` is still a stage0 shim:

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
  - kind: `both` (bundled-first, stage0 delegation today)
  - behavior: injects `reflaxe.ocaml` wiring (`-lib`/`-cp`/init macros/defines) and delegates to stage0 `haxe`
- `--target ocaml-stage3`
  - kind: `builtin`
  - behavior: runs linked `Stage3Compiler` directly (no `--library reflaxe.ocaml` requirement)
- `--target js`
  - kind: `bundled`
  - behavior: delegates to stage0 `haxe` and injects `--js out.js` when no explicit output target is present
- `--target js-native`
  - kind: `builtin`
  - behavior: routes through linked Stage3 backend dispatch with backend ID `js-native`
  - status: MVP non-delegating JS emitter is enabled (constrained subset; emits one JS file artifact and Stage3 runs it via `node` when available)
- `--target flash|swf|as3`
  - status: intentionally unsupported in `hxhx` (fails fast with a clear message)
- raw legacy target flags (`--swf`, `--as3`)
  - status: intentionally unsupported in `hxhx` (fails fast with the same message)
- `--hxhx-strict-cli`
  - status: available
  - behavior: enforces upstream-style CLI surface by rejecting hxhx-only flags (`--target`, `--hxhx-*`), while preserving normal extension mode when the flag is omitted

### `js-native` semantics snapshot (MVP)

Supported today (covered by `scripts/test-hxhx-targets.sh`):

- statement-level `switch` lowering over enum-like tags (`Build`, `Run`, etc.) via Stage3 `HxSwitchPattern`
- statement-level `try/catch` + `throw` (including nested rethrow flow in smoke fixture)
- ordered multi-catch dispatch for common typed hints (`Int`, `Float`, `Bool`, `String`, `Array`, `Dynamic`) with fallback rethrow when no catch matches
- basic reflection helpers through a lightweight JS prelude:
  - `Type.resolveClass(name)`
  - `Type.getClassName(cls)`
  - `Type.enumConstructor(value)`
  - `Type.enumIndex(value)` (best-effort)
  - `Type.enumParameters(value)` (best-effort)
- single-file emit artifact + Stage3 run markers (`stage3=ok`, `artifact=...`, `run=ok`)

Known unsupported semantics (explicit fail-fast behavior):

- full Haxe class/interface typed-catch semantics (`catch (e:SomeType)` with exact runtime type matching beyond primitive/common builtins)
- full Haxe enum runtime/model parity (constructors with parameters, exact enum index semantics)
- full Haxe `Type` API parity beyond the helpers above

Why this matters:

- It is our first concrete linked-backend fast-path (`kind=builtin`) in the registry.
- It gives a no-classpath-scan execution path for OCaml Stage3 bring-up and perf tracking.
- It keeps the stable `--target` UX while we move from stage0 delegation to native `hxhx` execution.
- The JS presets now cover both delegated (`js`) and non-delegating MVP (`js-native`) paths so CI and Gate wiring can evolve without hidden fallbacks.
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

## Example: `reflaxe.elixir` as a bundled vs builtin backend

Bundled (early, stage0 shim compatible):

- `hxhx` ships `reflaxe.elixir` sources.
- `hxhx --target elixir` expands to:
  - add `-cp <dist>/lib/reflaxe.elixir/src` (or equivalent)
  - add `--library reflaxe.elixir`
  - add the defines that the backend expects

Builtin (later, after macro execution is native):

- `reflaxe.elixir` is compiled/linked into `hxhx`.
- `hxhx --target elixir` selects the builtin backend implementation with no classpath injection.

## Beads tracking

The implementation work described here should be tracked as a dedicated epic and tasks (see beads).
