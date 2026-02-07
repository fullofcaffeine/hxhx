# HXHX Macro Host Protocol (Stage 4 · Model A)

This document describes the **first-rung** RPC protocol between:

- `hxhx` (compiler core)
- `hxhx-macro-host` (out-of-process macro runtime)

This is Stage 4 (“native macro execution”) using **Model A** as defined in:

- `docs/02-user-guide/HXHX_STAGE4_MACROS_AND_PLUGIN_ABI.md:1`

## Why an out-of-process macro host?

We start with RPC because it keeps the compiler process isolated from macro code and avoids OCaml dynlink complexity
while we bootstrap:

- macro crashes don’t corrupt the compiler
- macro state can be reset deterministically
- the ABI boundary becomes explicit and testable (good for Gate 1/Gate 2)

## Macro host implementations in this repo (bring-up)

There are currently **two** macro-host entrypoints, depending on how the host is built:

- Stage 4 host (`hxhxmacrohost.Main`)
  - Built by stage0 `haxe` + `reflaxe.ocaml` (or via the committed OCaml bootstrap snapshot when no dynamic entrypoints are requested).
  - Implements the broader bring-up method set documented below (including reverse-RPC).
- Stage 3 host (`hxhxmacrohost.Stage3Main`)
  - Built by `hxhx --hxhx-stage3` (stage0-free) and used specifically to make dynamic macro-host builds possible
    without a stage0 toolchain.
  - **Protocol-correct** for the handshake and the `--hxhx-macro-selftest` probe, but intentionally minimal:
    - `ping`
    - `compiler.define`
    - `context.defined`
    - `context.definedValue`

When you see “macro host” in Gate bring-up notes, it may refer to either implementation.

## Versioning rules

This is a versioned protocol.

- The server announces a concrete version in its banner: `hxhx_macro_rpc_v=<N>`.
- The client must only proceed if it supports that version.
- Any incompatible change increments `<N>`.

Stage 4 bring-up starts at `N=1`.

## Transport and framing

Transport:

- server reads from `stdin`
- server writes to `stdout`
- messages are **single-line** records terminated by `\n`

Implementation note (portability):

- On the OCaml target, the client uses `sys.io.Process` to spawn the macro host and communicate over
  stdin/stdout. That API is implemented by an OCaml-target override in `std/_std/sys/io/Process.hx`,
  backed by the runtime shim `std/runtime/HxProcess.ml`.
- This is a bootstrap seam for correctness and CI stability while the portable OCaml-target process APIs mature.
- For non-OCaml builds of `hxhx` (e.g. Rust/C++ targets), an equivalent transport implementation must exist:
  either pure Haxe (preferred) or a small target-specific shim.

Framing:

- the first few fields are space-separated
- payload fragments use **length-prefixed** values so strings can contain spaces safely

### Escaping

Length-prefixed payload text supports a minimal escape set:

- `\\n`, `\\r`, `\\t`, `\\\\`

## Handshake (v=1)

1. Server prints:

   - `hxhx_macro_rpc_v=1`

2. Client prints:

   - `hello proto=1`

3. Server prints:

   - `ok`

If the handshake fails, the server may print `err ...` and exit.

## Requests / responses (v=1)

Requests:

- `req <id> <method> <payload...>`

Responses:

- `res <id> ok <payload...>`
- `res <id> err <payload...>`

`<id>` is an integer chosen by the client so it can correlate responses.

### Duplex note (Stage 4 bring-up)

Stage 4 requires **duplex** communication:

- the compiler sends a `req` to the macro host (e.g. `macro.run`)
- while the compiler is waiting for the corresponding `res`, the macro host may send its own `req`
  back to the compiler (e.g. `compiler.define`, `context.defined`, `context.definedValue`)
- the compiler must handle these inbound requests and reply with `res` lines, then continue waiting
  for its original `res`

In the current bring-up rungs:

- compiler-initiated requests use positive IDs
- macro-host-initiated reverse requests use **negative IDs** to avoid collisions

### Payload fragments

Payload fragments are key/value parts with length-prefixed text:

- `<k>=<len>:<escaped>`

Examples:

- `n=3:foo`
- `v=3:bar`

## Implemented methods (skeleton)

This bead intentionally implements only a tiny stub surface, so we can test the boundary end-to-end.

### `ping`

- request: `req <id> ping`
- response: `res <id> ok v=4:pong`

### `compiler.define`

Models the shape of `haxe.macro.Compiler.define(name, value)`.

- request: `req <id> compiler.define n=<...> v=<...>`
- response: `res <id> ok v=2:ok`

### `compiler.getDefine` (bring-up rung)

Bring-up read-define primitive (roughly corresponds to `haxe.macro.Compiler.getDefine` expanding to `Context.definedValue`).

- request: `req <id> compiler.getDefine n=<...>`
- response: `res <id> ok v=<len>:<payload>`

`<payload>` is a list of length-prefixed fragments:

- `d=<len>:<0|1>` (defined?)
- `v=<len>:<value>` (define value)

The macro host treats `defined=false` as “no define” and returns `null`.

### `compiler.registerHook` (bring-up rung)

Compiler-side registration hook called by the macro host when macro code registers a callback.

This models the *shape* of upstream hook registration (`Context.onAfterTyping`, `Context.onGenerate`) without
shipping closures over the ABI.

- request: `req <id> compiler.registerHook k=<...> i=<...>`
  - `k`: hook kind (`afterTyping` or `onGenerate`)
  - `i`: hook ID (integer assigned by the macro host)
- response: `res <id> ok v=2:ok`

### `compiler.emitOcamlModule` (bring-up rung)

Stage 4 “generate code” rung: a macro can request the compiler to emit an additional OCaml compilation unit.

This is not the long-term macro generation API (which will be typed AST/field generation). It exists so we can
prove the artifact plumbing works end-to-end before we implement full transforms.

- request: `req <id> compiler.emitOcamlModule n=<...> s=<...>`
  - `n`: module name (e.g. `HxHxGen`)
  - `s`: raw `.ml` source text
- response: `res <id> ok v=2:ok`

### `compiler.addClassPath` (bring-up rung)

Stage 4 macro-time configuration rung: a macro can add a compiler classpath.

This models the shape of `haxe.macro.Compiler.addClassPath(path)` and is a useful early “macro influences compilation”
effect: it changes which modules can be resolved.

- request: `req <id> compiler.addClassPath cp=<...>`
- response: `res <id> ok v=2:ok`

### `compiler.includeModule` (bring-up rung)

Stage 4 macro-time reachability rung: a macro can force-include a module into the compilation universe.

This models the shape of upstream `--macro include("pack.Mod")` in the smallest possible way:

- the macro host parses `include("...")` as a builtin `macro.run` expression, and
- issues a reverse RPC that records additional resolver roots in the compiler.

- request: `req <id> compiler.includeModule m=<...>`
  - `m`: module path (e.g. `unit.TestInt64`)
- response: `res <id> ok v=2:ok`

### `compiler.emitHxModule` (bring-up rung)

Stage 4 macro-time codegen rung: a macro can request the compiler to emit a Haxe module into a compiler-managed
generated directory that is included in the classpath for the current compilation.

This is a bring-up mechanism, not the long-term `Context.defineType/defineModule` API. It exists to prove a macro can
generate *new source code* that affects module resolution and typing.

- request: `req <id> compiler.emitHxModule n=<...> s=<...>`
  - `n`: module name (simple identifier, e.g. `Gen`)
  - `s`: `.hx` source text
- response: `res <id> ok v=2:ok`

### `compiler.emitBuildFields` (bring-up rung)

Stage 4 “build macro” rung: a macro can request the compiler to merge **new class members** into a module’s
main class, as if they were produced by `@:build(...)`.

This is explicitly **not** the long-term implementation of upstream build macros (which return
`Array<haxe.macro.Expr.Field>` and require a real macro interpreter + typed AST integration). Instead, this rung:

- keeps the ABI boundary explicit (`compiler` ↔ `macro host`)
- proves that `@:build(...)` can have an observable effect on typing + emission
- transports raw Haxe member source strings that our bootstrap parser can re-parse

In current bring-up, this method is used in two ways:

- directly, by a macro calling `Compiler.emitBuildFields(modulePath, snippet)`
- indirectly, when an allowlisted `@:build(...)` entrypoint returns `Array<haxe.macro.Expr.Field>`:
  the macro host converts *new* fields into member snippets and forwards them via `compiler.emitBuildFields`

- request: `req <id> compiler.emitBuildFields m=<...> s=<...>`
  - `m`: module path (e.g. `demo.Main`)
  - `s`: Haxe class-member snippet(s) to merge into that module’s main class
- response: `res <id> ok v=2:ok`

### `context.getBuildFields` (bring-up rung)

Bring-up read-build-fields primitive (corresponds to `haxe.macro.Context.getBuildFields()`).

This exists so upstream-ish build macros that start with `Context.getBuildFields()` can execute without
immediately throwing "Can't be called outside of macro".

- request: `req <id> context.getBuildFields`
- response: `res <id> ok v=<len>:<payload>`

`<payload>` is a list of length-prefixed fragments describing the class currently being built:

- `c=<len>:<count>`
- then for each field index `i` in `0..count-1`:
  - `n<i>=<...>` (name)
  - `k<i>=<...>` (`fun` or `var`)
  - `s<i>=<...>` (`1` if static, else `0`)
  - `v<i>=<...>` (`Public` or `Private`)

Notes:

- This RPC is wired to a runtime subset of `haxe.macro.Context.getBuildFields()` inside the macro host.
  The macro host calls `context.getBuildFields` over reverse RPC and returns a shallow
  `Array<haxe.macro.Expr.Field>`.
- Returned `Field` values are **stubby** by design:
  - `pos` is currently `null` (no macro-user positions yet)
  - `FFun` bodies are stubbed with a trivial `null` expression
  - only `name`, `access`, and a coarse `kind` (`fun` vs `var`) are preserved
- When an allowlisted build-macro entrypoint returns `Array<Field>`, the macro host prints the supported
  subset of fields into raw member snippets and forwards them via `compiler.emitBuildFields`.
  - If the emitted snippet has the same name as an existing member, the compiler treats it as a
    **replacement** (drop old, keep new).
  - Deletion by omission is not supported yet.

### `context.defined`

Models the shape of `haxe.macro.Context.defined(name)`.

- request: `req <id> context.defined n=<...>`
- response: `res <id> ok v=1:1` (or `v=1:0`)

### `context.definedValue`

Models the shape of `haxe.macro.Context.definedValue(name)`.

- request: `req <id> context.definedValue n=<...>`
- response: `res <id> ok v=<len>:<value>`

### `context.onAfterTyping` / `context.onGenerate` (bring-up rung)

Hook registration APIs used from within macro code.

In Model A, hook callbacks are stored inside the macro host process. Registration therefore triggers a reverse RPC
`compiler.registerHook` so the compiler can remember which hooks to run later.

### `context.getDefines` (bring-up rung)

Bring-up define enumeration primitive (corresponds to `haxe.macro.Context.getDefines()`).

- request: `req <id> context.getDefines`
- response: `res <id> ok v=<len>:<payload>`

`<payload>` is a list of length-prefixed fragments:

- `c=<len>:<count>`
- then `k0=<...> v0=<...> k1=<...> v1=<...> ...` (sorted by key)

### `macro.run` (bring-up rung)

Invokes a macro entrypoint by opaque expression text.

This is not full user-macro execution yet. It exists to validate the end-to-end request path we will later
use for `--macro` and build macros.


In the current bring-up rung:

- `hxhxmacrohost.BuiltinMacros.*` is dispatched directly (builtins).
- A small allowlist may include non-builtin macro modules compiled into the macro host binary for tests
  (e.g. `hxhxmacros.ExternalMacros.external()` when built with an extra `-cp`).

Bring-up limitation (important):

- The generated allowlist dispatcher (`scripts/hxhx/build-hxhx-macro-host.sh`) currently supports only
  calls of the shapes:
  - `pack.Class.method()` (no args)
  - `pack.Class.method("...")` (one String literal arg)
- Expressions like `nullSafety("reflaxe")` are not executed yet in the Stage 4 bring-up model.
  They will become supported once we replace the allowlist with a real
  macro-expression evaluation model and/or a richer entrypoint registry.

- request: `req <id> macro.run e=<len>:<expr>`
- response: `res <id> ok v=<len>:<result>`

### `macro.runHook` (bring-up rung)

Invoke a previously registered hook callback inside the macro host.

- request: `req <id> macro.runHook k=<...> i=<...>`
  - `k`: hook kind (`afterTyping` or `onGenerate`)
  - `i`: hook ID (integer assigned by the macro host)
- response: `res <id> ok v=2:ok`

### `context.getType` (bring-up rung)

Models the *shape* of `haxe.macro.Context.getType(name)` for a tiny allowlist.

This does not return a real typed representation yet. It returns a deterministic string descriptor:

- `builtin:<name>` for `Int`, `Float`, `Bool`, `String`, `Void`
- `unknown:<name>` for anything else

- request: `req <id> context.getType n=<len>:<name>`
- response: `res <id> ok v=<len>:<desc>`

## How to run locally

Build and run the selftest (requires `haxe`, `ocamlc`, `dune`):

```bash
bash scripts/test-hxhx-targets.sh
```

The macro RPC section specifically runs:

- `bash scripts/hxhx/build-hxhx-macro-host.sh`
- `bash scripts/hxhx/build-hxhx.sh`
- `HXHX_MACRO_HOST_EXE=... <hxhx> --hxhx-macro-selftest`
- `HXHX_MACRO_HOST_EXE=... <hxhx> --hxhx-macro-run "BuiltinMacros.smoke()"`

### Macro host build modes (bootstrap vs stage0 vs Stage3)

`scripts/hxhx/build-hxhx-macro-host.sh` has three distinct build modes:

- **Bootstrap snapshot (stage0-free, default when possible)**:
  - If `tools/hxhx-macro-host/bootstrap_out/` exists *and* no dynamic entrypoints/classpaths are requested,
    the macro host is built via dune from the committed snapshot.
- **Stage3 build attempt (stage0-free, experimental)**:
  - When `HXHX_MACRO_HOST_ENTRYPOINTS` and/or `HXHX_MACRO_HOST_EXTRA_CP` are set, the script can *optionally*
    attempt to build via `hxhx --hxhx-stage3` by setting `HXHX_MACRO_HOST_PREFER_HXHX=1`.
  - This requires a real Haxe std root so the macro host can resolve `haxe.macro.*`:
    - set `HAXE_STD_PATH=/path/to/haxe/std`, or
    - have an untracked upstream checkout at `vendor/haxe/std`, or
    - set `HAXE_UPSTREAM_DIR=/path/to/haxe` (the script uses `<dir>/std`).
  - Internally, this uses Stage3’s `--hxhx-no-run` so the server executable is *built* but not executed.
- **Stage0 fallback**:
  - If the Stage3 build attempt fails and `haxe` is available, the script falls back to stage0 generation.
  - Gate runners can enforce stage0-free behavior by disabling `haxe` on `PATH` (and ensuring the Stage3 build works).
