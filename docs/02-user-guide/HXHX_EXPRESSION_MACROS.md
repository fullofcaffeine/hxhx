# HXHX Expression Macros (Gate1 Bring-up)

Upstream Haxe supports **expression macros**: a call expression that appears in *normal runtime code* is executed at
compile-time (in the macro context), and the call site is replaced with the expression AST returned by the macro.

This repository implements a small, explicit rung of that feature to support Gate1 bring-up and to validate the pipeline:

- detect eligible call sites
- ask the macro host to expand them
- parse the returned expression snippet
- splice it into the program *before* typing/emission continues

## Why this is a separate rung

Expression macros are normally integrated deeply into the compiler:

- the typer decides which calls are “macro calls” based on `macro function` declarations and typing context
- macro execution returns an AST (`haxe.macro.Expr`), not text
- the compiler splices the returned AST and continues typing on the rewritten program

During `hxhx` Stage3/Stage4 bring-up we do not have that full integration yet. The goal here is to prove the *shape* of
the feature with a conservative and auditable mechanism, then expand coverage only when the next gate requires it.

## Current model (bring-up, not full upstream semantics)

### Compiler-side: `ExprMacroExpander`

In Stage3, when `HXHX_EXPR_MACROS` is set, `hxhx` runs a pre-typing rewrite pass:

- file: `packages/hxhx/src/hxhx/ExprMacroExpander.hx`
- integration point: `packages/hxhx/src/hxhx/Stage3Compiler.hx`

The expander:

- walks the bootstrap AST (`ResolvedModule` → `HxStmt` / `HxExpr`)
- identifies a conservative subset of call expressions:
  - `TypePath.meth()`
  - `TypePath.meth("literal")` (single String literal arg)
- matches those call sites against an **explicit allowlist**
- replaces the call expression node with the expression returned by the macro host

Important constraints:

- We do **not** detect `macro function` declarations yet.
- We do **not** type-check the returned expression snippet yet; we just parse it into the bootstrap `HxExpr` subset.
- The returned snippet must be parsable by `HxParser.parseExprText` (tiny expression grammar).

### Macro-host-side: `macro.expandExpr`

Expression expansion is performed by the Stage4 macro host via a dedicated RPC method:

- file: `tools/hxhx-macro-host/src/hxhxmacrohost/Main.hx`
- RPC: `macro.expandExpr`

`macro.expandExpr` takes the call expression text (a deterministic, allowlisted string), dispatches it to a compiled-in
entrypoint, and returns the result as **Haxe expression text**.

This is intentionally *not* “arbitrary evaluation”:

- the macro host does not reflectively call unknown methods
- it only dispatches exact expression strings that were registered at build time

## Configuration

### Enable expression macro expansion

Set `HXHX_EXPR_MACROS` to a `;`- or `,`-separated list of **fully-qualified call strings**.

Example:

```bash
HXHX_EXPR_MACROS='hxhxmacros.ExprMacroShim.hello()' \
  HXHX_MACRO_HOST_EXE=/path/to/hxhx-macro-host \
  hxhx --hxhx-stage3 --hxhx-emit-full-bodies \
    -cp src -cp examples/hxhx-macros/src -main Main --hxhx-out out
```

Notes:

- The allowlist entries are intentionally **fully-qualified**, because the macro host entrypoint registry dispatches
  via static references like `hxhxmacros.ExprMacroShim.hello()`.
- In normal code you may still call via imports (`ExprMacroShim.hello()`); `hxhx` resolves this for allowlist matching
  during bring-up.

### Trace expansion decisions (debug)

Set `HXHX_TRACE_EXPR_MACROS=1` to print trace lines during rewriting:

- candidates encountered (in the supported shape)
- expansions performed

This is intended for bring-up diagnostics and may be noisy for large module graphs.

## Authoring an expression macro entrypoint (bring-up rule)

In this rung, the macro host expects the entrypoint to return a **String containing expression text**, not the final
runtime value.

Example: return a string-literal expression (`"HELLO"`) by including quotes in the returned text:

```haxe
class ExprMacroShim {
  public static function hello():String {
    return "\"HELLO\""; // expression snippet
  }
}
```

## Relationship to Stage4 plugin ABI

This rung is compatible with the Stage4 macro-host model:

- the compiler core remains in Haxe
- macro execution is isolated in the macro-host process
- the bridge is a small, versioned RPC protocol

As Stage4 grows toward full upstream macro compatibility, this bring-up “expression text snippet” approach is expected
to evolve toward transmitting a real expression AST over the macro ABI (or an equivalent structured form), while keeping
this rung’s tests as a regression guard for “expression macro splicing works end-to-end”.

