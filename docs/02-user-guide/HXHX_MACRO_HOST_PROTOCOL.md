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

### `compiler.emitHxModule` (bring-up rung)

Stage 4 macro-time codegen rung: a macro can request the compiler to emit a Haxe module into a compiler-managed
generated directory that is included in the classpath for the current compilation.

This is a bring-up mechanism, not the long-term `Context.defineType/defineModule` API. It exists to prove a macro can
generate *new source code* that affects module resolution and typing.

- request: `req <id> compiler.emitHxModule n=<...> s=<...>`
  - `n`: module name (simple identifier, e.g. `Gen`)
  - `s`: `.hx` source text
- response: `res <id> ok v=2:ok`

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

Invokes a **builtin** macro entrypoint by opaque expression text.

This is not user-macro execution yet. It exists to validate the end-to-end request path we will later
use for `--macro` and build macros.

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
