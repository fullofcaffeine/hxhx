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

- On the OCaml target, the client-side “spawn + pipes + flush” is currently implemented in
  `std/runtime/HxHxMacroRpc.ml` and exposed to Haxe via an extern (`NativeMacroRpc`).
- This is a bootstrap seam for correctness and CI stability while the portable process APIs mature.
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

### `context.defined`

Models the shape of `haxe.macro.Context.defined(name)`.

- request: `req <id> context.defined n=<...>`
- response: `res <id> ok v=1:1` (or `v=1:0`)

### `context.definedValue`

Models the shape of `haxe.macro.Context.definedValue(name)`.

- request: `req <id> context.definedValue n=<...>`
- response: `res <id> ok v=<len>:<value>`

### `macro.run` (bring-up rung)

Invokes a **builtin** macro entrypoint by opaque expression text.

This is not user-macro execution yet. It exists to validate the end-to-end request path we will later
use for `--macro` and build macros.

- request: `req <id> macro.run e=<len>:<expr>`
- response: `res <id> ok v=<len>:<result>`

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
- `HXHX_MACRO_HOST_EXE=... <hxhx> --hxhx-macro-run "Macro.init()"`
