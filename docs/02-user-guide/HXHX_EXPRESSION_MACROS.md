# HXHX Expression Macros (Gate1 Bring-up)

Upstream Haxe supports **expression macros**: a call expression that appears in *normal runtime code* is executed at
compile-time (in the macro context), and the call site is replaced with the expression AST returned by the macro.

What works today, in short:

- A project macro such as `Identity.preserve(function(label:String):String { ... })` runs its real Haxe body when its
  class is compiled into a project-macro plugin and the compile runs in-process. The macro receives the authored
  argument as `haxe.macro.Expr`, and the expression it returns replaces the call before typing.
  See "Project macro plugins" below.
- hxhx builds and caches that plugin by itself, so a plain `hxhx --hxhx-stage3 -cp src -main Main` runs the macro.
  This needs `dune` and the matching OCaml compiler on `PATH`.
- Macros that need `haxe.macro.Context`, reification (`macro ...`), or the external macro host are not executed yet.
  A selected call that cannot run is a compile error at the call, as it would be wrong to compile it as an ordinary
  call (upstream Haxe would have run it).

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

The in-process session runs a selected declaration through the project macro plugin that hxhx builds or reuses for the
compile (next section). When the call cannot run, the compile fails before typing. The call is reported on stdout, and
the error names the file, the declaration, and the reason. Reasons include an unsupported declaration shape, a plugin
that cannot be built, the external-host mode (which has no structured dispatch method yet), and the compilation server:

```
expr_macros_unexecuted=1
expr_macro_unexecuted[0]=Main.hx: macros.Macros.items: project macro declaration `macros.Macros.items` parameter `n` must be a required haxe.macro.Expr; other parameter kinds are not supported yet
hxhx(stage3): Main.hx: expression macro macros.Macros.items was not executed: project macro declaration `macros.Macros.items` parameter `n` must be a required haxe.macro.Expr; other parameter kinds are not supported yet
```

One declaration is exempt for now: hxhx's own `CompilerBundledSourcesMacro.files()`, which embeds standard-library
sources when hxhx compiles itself and needs `haxe.macro.Context` and reification. It is still reported, and its call is
then typed by the macro call-site contract (`TyMacroCallSignature`): any expression is accepted at an `Expr` parameter,
a trailing `Array<Expr>` parameter collects the remaining arguments, and the value is `Dynamic`. With `HXHX_TRACE_EXPR_MACROS=1`, `expr_macro_scope_gaps=N` also counts call sites the walker could not prove names for;
nothing is selected there. It is a trace line only, because standard-library switch scopes produce gaps in every program.

Important constraints:

- A selected `macro function` declaration runs only through a loaded project-macro plugin in the in-process mode.
  Otherwise the compile fails at the call (except the bundled-source declaration described above).
- For the exact-text allowlist route below:
  - we do **not** type-check the returned expression snippet yet; we just parse it into the bootstrap `HxExpr` subset;
  - the returned snippet must be parsable by `HxParser.parseExprText` (tiny expression grammar).

### Project macro plugins (in-process)

A project macro runs from a *project macro plugin*: an OCaml library that hxhx compiles from the project's macro classes
with its own Stage3 emitter. For each called macro declaration the plugin registers a generated adapter of Haxe type
`Array<haxe.macro.Expr> -> haxe.macro.Expr` that calls the real macro method.

hxhx builds, caches, and loads the plugin by itself. A plain compile is enough:

```bash
cd test/fixtures/project-macro-identity
hxhx --hxhx-stage3 -cp src -main Main
```

What happens, in order:

1. The pre-typing pass finds the calls whose callee is a supported macro declaration (a static `macro` method whose
   parameters are all required `Expr` values and whose result is `Expr`), here `Identity.preserve`.
2. hxhx computes a cache key from everything it knows before building: the digest of its own executable and its OCaml
   version, the plugin ABI versions, the declarations, the classpaths, the `-D` defines, the working directory, and the
   OCaml runtime sources the plugin is built with.
3. If `<cache>/<key>/receipt.json` exists and still matches (same compiler, versions, declarations, unchanged source
   files, unchanged artifacts), hxhx loads that plugin. The compile prints `project_macro_plugin=reused`.
4. Otherwise it takes a per-key lock, starts itself as a child compiler that compiles the macro classes in a macro
   compilation context (`--hxhx-macro-classpath`, so `#if macro` and `#if eval` branches are active), runs `dune` to
   build the `.cma` and `.cmxs`, and writes a receipt that also records every source file the child read, with its
   SHA-256. The compile prints `project_macro_plugin=built` and the reason (`project_macro_plugin_reason=`).
   Editing a macro class, or anything it uses, therefore rebuilds the plugin.

The cache lives in `$XDG_CACHE_HOME/hxhx/macro-plugins`, else `~/.cache/hxhx/macro-plugins` (or
`%LOCALAPPDATA%\hxhx\macro-plugins`). Pass `--hxhx-macro-cache <dir>` to use another directory. Every build gets a
fresh plugin id (`hxhx.project-macro.<build id>`), so two plugin builds never share OCaml unit names.

#### Toolchain requirement

Projects that call expression macros need `dune` and `ocamlopt` on `PATH`, and `ocamlopt` must be the same OCaml
version that built the hxhx binary (a plugin is linked against the binary's own runtime). Without them the call cannot
run, and the compile fails with one diagnostic that says why:

```
hxhx(stage3): .../Main.hx: expression macro Identity.preserve was not executed: the project macro plugin is unavailable:
project macros need `dune` and the OCaml native compiler (`ocamlopt`) on PATH to build their native plugin;
`ocamlopt -version` failed: ...
```

A different OCaml version is rejected the same way, before anything is built.

#### Building needs the hxhx source checkout

A plugin is compiled from hxhx's own sources: the plugin entry and payload codec
(`packages/hxhx-core/src/hxhxmacrohost`), the OCaml runtime (`packages/reflaxe.ocaml/std/runtime`), and the shim
templates (`packages/hxhx-core/shims`). hxhx finds the checkout from `HXHX_REPO_ROOT`, or by walking up from its own
executable (and, for the runtime, from the working directory). A binary copied outside the checkout therefore needs
`HXHX_REPO_ROOT=<checkout>`. Making plugins independent of the checkout is tracked as `haxe_ocaml-53uzv`.

#### Interrupted and concurrent builds

One process builds a given plugin at a time; others wait on the per-plugin lock and say so
(`hxhx: waiting for another hxhx process that is building this project macro plugin`). A lock left by an interrupted
build (for example Ctrl-C) is recovered as soon as its owner process is gone, or after 30 minutes; a compile waits up to
about 32 minutes for a lock, so an owner id reused by an unrelated process cannot make it fail first. A rebuild keeps
the build the previous receipt named and removes every other build, including partial ones. A compile that already validated that
receipt can therefore still load its plugin. Each tool run of a build (the child compiler,
then `dune`) is stopped after 30 minutes; `HXHX_MACRO_PLUGIN_BUILD_TIMEOUT=<seconds>` changes the limit. The quick
toolchain checks before a build (`ocamlopt -version`, `ocamlopt -config`, `dune --version`) have their own 10-minute limit.
A stop (time limit, or Ctrl-C on the compile) reaches the tool's whole process group, so processes it started stop too.
On Windows, and on a POSIX host whose `/bin/sh` has neither `setsid` nor job control, only the tool itself is stopped.

#### Current limits

- Only one-shot in-process compiles run project macros. In the external macro host and the compilation server, a
  selected call fails the compile with that reason.
- Macro code that calls another macro function (directly or through a helper) is "macro-in-macro". Upstream Haxe 4.3.7
  rejects it when the call runs; a plugin build fails at a helper's call with that reason when the plugin is compiled,
  even if the helper would never run, which is stricter than upstream. A call written directly in a macro function's
  body is not detected yet and runs as an ordinary call (`haxe_ocaml-48uwv`).
- The plugin compilation keeps the `ocaml` target define in macro classes, while upstream's eval macro context does
  not define the program target.
- A new file that changes which file a lookup selects, without any edit to a file the plugin read, is not detected; edit
  or touch a macro source to force a rebuild.
- A reused plugin is not compared with the current `ocamlopt -config`: compatibility is with the hxhx binary, whose
  digest and OCaml version are in the key, and the `PATH` toolchain matters only when a plugin is built.
- A compilation-server cancellation does not stop a running plugin build; the time limit bounds it.

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
external macro host cannot dispatch them yet, so hxhx does not build or load a plugin in that mode. The exact-text snippet route remains for built-in
and generated bring-up entrypoints, and its tests remain a regression guard for "expression macro splicing works
end-to-end".

