# HXHX Expression Macros (Gate1 Bring-up)

Upstream Haxe supports **expression macros**: a call expression that appears in *normal runtime code* is executed at
compile-time (in the macro context), and the call site is replaced with the expression AST returned by the macro.

What works today, in short:

- A project macro such as `Identity.preserve(function(label:String):String { ... })` runs its real Haxe body when its
  class is compiled into a project-macro plugin and the compile runs in-process. The macro receives the authored
  argument as `haxe.macro.Expr`, and the expression it returns replaces the call before typing.
  See "Project macro plugins" below.
- The plugin is still built by hand (the smoke script shows the commands); automatic building is the next step.
- Macros that need `haxe.macro.Context`, reification (`macro ...`), or the external macro host are not executed yet;
  such calls are reported as unexecuted.

The older, explicit rung of this feature still exists for Gate1 bring-up:

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

In Stage3, every compile that is not `--hxhx-type-only` runs a pre-typing rewrite pass (the built-in date macros are
always on the exact-text list, and `HXHX_EXPR_MACROS` adds more):

- file: `packages/hxhx/src/hxhx/ExprMacroExpander.hx`
- integration point: `packages/hxhx/src/hxhx/Stage3Compiler.hx`

The expander:

- walks the bootstrap AST (`ResolvedModule` → `HxStmt` / `HxExpr`)
- identifies a conservative subset of call expressions:
  - `TypePath.meth()`
  - `TypePath.meth("literal")` (single String literal arg)
- matches those call sites against an **explicit allowlist**
- replaces the call expression node with the expression returned by the macro host

Calls that do not match the allowlist are selected by declaration: when the callee resolves to a static `macro function`
through the request's header index (public, or private from its own class), the call is sent to the macro session as one
structured request (`MacroRuntimeSession.expandSelected`) carrying the selected declaration and the authored argument
syntax. An allowlisted exact call text always keeps the allowlist route, even if its callee is a macro.

The in-process session runs a selected declaration when a loaded project-macro plugin provides it (next section). When
no plugin provides it, or in the external-host mode, which has no structured dispatch method yet, the call is reported
on stdout and then typed as before, so a later failure is attributable:

```
expr_macros_unexecuted=1
expr_macro_unexecuted[0]=Main.hx: macros.Macros.items: no loaded project macro plugin provides declaration macros.Macros.items
```

An unexpanded macro call is typed by the macro call-site contract (`TyMacroCallSignature`), not as an ordinary call:
any expression is accepted at an `Expr` parameter, a trailing `Array<Expr>` parameter collects the remaining arguments,
and the call's value is `Dynamic`, because its real type would come from the expansion. The report precedes whatever that
typing produces; for example, `for (v in macros.Macros.items())` still stops with
`value loop requires a resolved iterator protocol`, since a `Dynamic` value has no known iterator. With `HXHX_TRACE_EXPR_MACROS=1`, `expr_macro_scope_gaps=N` also counts call sites the walker could not prove names for;
nothing is selected there. It is a trace line only, because standard-library switch scopes produce gaps in every program.

Important constraints:

- A selected `macro function` declaration runs only through a loaded project-macro plugin in the in-process mode.
  Otherwise it is reported and then typed by the macro call-site contract described above.
- For the exact-text allowlist route below:
  - we do **not** type-check the returned expression snippet yet; we just parse it into the bootstrap `HxExpr` subset;
  - the returned snippet must be parsable by `HxParser.parseExprText` (tiny expression grammar).

### Project macro plugins (in-process)

A project macro plugin is an OCaml library compiled from the project's macro classes by hxhx's own Stage3 emitter. For
each listed macro declaration it registers a generated adapter of Haxe type `Array<haxe.macro.Expr> -> haxe.macro.Expr`
that calls the real macro method.

```bash
# 1. Build the plugin (bytecode .cma and native .cmxs) from the macro class.
hxhx --hxhx-stage3 --hxhx-no-run \
  -cp packages/hxhx-core/src -cp src \
  -main hxhxmacrohost.MacroDeclarationPlugin \
  --hxhx-out plugin \
  -D ocaml_dune_layout=plugin \
  -D ocaml_plugin_register_macro=my.project.macros \
  -D ocaml_plugin_macro_declarations=Identity.preserve
# The compile prints exe=<plugin>/hxhx_macro_plugin_my_project_macros.cma: the plugin is a
# wrapped dune library, so its modules cannot collide with the compiler's own when loaded.
(cd plugin && dune build ./hxhx_macro_plugin_my_project_macros.cma ./hxhx_macro_plugin_my_project_macros.cmxs)

# 2. Write a receipt that binds the plugin to this compiler build, then compile the project.
node scripts/ci/native-macro-module-receipt.js write --report module/receipt.json \
  --candidate-commit <id> --plugin-id my.project.macros --declarations Identity.preserve \
  --native-artifact module/plugin.cmxs --bytecode-artifact module/plugin.cma
HXHX_NATIVE_MACRO_MODULE_RECEIPT=module/receipt.json HXHX_CANDIDATE_COMMIT=<id> \
  hxhx --hxhx-stage3 -cp src -main Main --hxhx-out out
```

During the compile, for each selected call of a provided declaration:

1. `MacroSyntaxExport` converts each authored argument to `haxe.macro.Expr`. Brace groups, function signatures,
   `return`, loops, and branches keep their public form (`EBlock`, `EFunction`, `EReturn`, ...).
2. `MacroSyntaxWire` encodes the arguments, the plugin adapter runs the macro, and the result comes back encoded. The
   compiler binary and the plugin are compiled by different OCaml backends, so `Expr` values cross the boundary as this
   versioned structured payload, never as raw memory and never as source text.
3. `MacroSyntaxImport` converts the returned expression to parser syntax, which replaces the call and is then typed
   like authored code.

A macro exception, an argument without a recorded source position, or a returned shape the importer does not support
(for example `ESwitch` or metadata other than `@:privateAccess`) is a compile error at the call; it never falls back to
an ordinary call.

Positions are approximate: a node that the parser gave a start position receives a zero-width position at that start in
the call file; other nodes reuse their nearest enclosing node's position. Exact source ranges are tracked separately.

The working example is `test/fixtures/project-macro-identity`, checked by `npm run test:macro-runtime:project-module`.

### Macro-host-side: `macro.expandExpr`

Expression expansion is performed by the Stage4 macro host via a dedicated RPC method:

- file: `packages/hxhx-macro-host/src/hxhxmacrohost/Main.hx`
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
  hxhx --hxhx-stage3 \
    -cp src -cp test/fixtures/hxhx-macros/src -main Main --hxhx-out out
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

Project macro plugins already transmit a structured expression form (`MacroSyntaxWire`) over plugin ABI version 2; the
external macro host loads such plugins but cannot dispatch them yet. The exact-text snippet route remains for built-in
and generated bring-up entrypoints, and its tests remain a regression guard for "expression macro splicing works
end-to-end".

