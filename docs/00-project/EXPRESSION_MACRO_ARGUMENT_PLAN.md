# Pass authored syntax to project expression macros

Status: approved plan (2026-10-29); step 1 (in-process identity macro) implemented by `haxe_ocaml-9sj5p.3`; step 2
(macro compilation context and plugin build and cache driver) implemented by `haxe_ocaml-9sj5p.4`.
Owners: `haxe_ocaml-9sj5p` and `haxe_ocaml-geafz`.

## What works now (after step 1)

A project macro body runs for real in an in-process compile: hxhx compiles its class into a
project-macro plugin, caches the plugin, and loads it (step 2, `hxhx.macro.ProjectMacroPluginCache`). For example, `test/fixtures/project-macro-identity` calls
`Identity.preserve(function(label:String):String { { if (label == "ok") { return label; } ... } ... })`.
The macro receives the function as `haxe.macro.Expr`, checks its written signature, nested brace
group, both returns, and the statements after the group, and returns it unchanged. The native
program prints `ok` and an empty event line, as upstream Haxe 4.3.7 does.

The pieces, in call order:

1. `ExprMacroExpander` selects the declaration and sends one `ExprMacroDispatchRequest`
   (unchanged from the selection step below). Since step 2, `Stage3ProjectMacroPlugins` first
   records the supported declarations, provides their plugin, and then repeats the pass.
2. `InProcMacroSession.expandSelected` looks up the declaration key `<owner>.<method>`. With no
   plugin providing it the call stays `Unavailable`, is reported, and fails the compile.
3. `MacroSyntaxExport` converts each argument (`HxExpr`) to `haxe.macro.Expr`.
4. `MacroSyntaxWire` encodes the arguments. The plugin's generated adapter
   (`Array<Expr> -> Expr`, emitted by `Stage3OcamlMacroPluginEntry` for the declarations listed in
   `-D ocaml_plugin_macro_declarations`) decodes them, runs the macro, and encodes its result or
   its failure.
5. `MacroSyntaxImport` converts the returned expression back to parser syntax, which replaces the
   call before typing.

Why a payload crosses the plugin boundary instead of `Expr` values: the `hxhx` binary is compiled
by `reflaxe.ocaml`, while the plugin is compiled by hxhx's Stage3 emitter. The two backends lay out
the same Haxe enum differently in memory (Stage3 boxes every enum value and uses `HxBootArray`), so
a raw value cannot be shared. Both sides compile the one Haxe-authored codec instead; native code
only stores the closure and passes the payload through (plugin ABI version 2,
`register_macro_declaration`).

Standing boundary contract (accepted by review, 2026-10-29): raw Haxe values never cross the
plugin boundary. The native ABI surface is `string -> string` (`register_macro_declaration` stores
a callback from an encoded request payload to an encoded response payload), and native code never
reads either payload. Both runtime routes use the same `MacroSyntaxWire` payloads: the in-process
Dynlink route today, and the external macro host, which should gain a `macro.runDeclaration`
method that carries exactly the same request and response payloads. Later Context services
(`haxe_ocaml-9sj5p.6`) extend this contract with host-resolved type handles instead of serialized
`haxe.macro.Type` values (`haxe_ocaml-expdc`).

Contract details and limits:

- Positions: a node that owns a known `HxPos` gets `{file: <call file>, min: start, max: start}`.
  The end is not known, so the span is zero-width. Other nodes reuse the nearest enclosing owned
  position. An argument whose root owns no position fails explicitly. On import, positions this
  call exported restore the original `HxPos`; any other position falls back to the first
  argument's start. Exact ranges remain `haxe_ocaml-9sj5p.2`.
- Import handles every `ExprDef` constructor. It rejects, with a compile error at the call,
  shapes the parser has no faithful form for yet: `ESwitch`, `EDisplay`, `EIs`, metadata other
  than `@:privateAccess`, local functions with type parameters, literal suffixes, and
  single-quoted interpolation.
- Export rejects pattern switches, comprehensions, raw text, lowered sequences without source
  groups, and `is`. Written types are read with the shared type grammar
  (`HxTypedefParser.parseTypeHint`) and printed back in the parser's compact text form.
- Plugin declarations must be static `macro` methods whose parameters are all required `Expr`
  values and whose result is `Expr`.
- The external macro host has no structured dispatch method (`macro.runDeclaration`, above), so
  hxhx neither builds nor loads a plugin in that mode; a selected declaration fails the compile.
- One in-process session loads at most one plugin; a second load is rejected. Registrations must
  name `pack.Type.method`, and `haxe.macro.*` owners are reserved.
- Follow-ups: literal spelling and quote kind (`haxe_ocaml-gzufu`), reflaxe.ocaml pattern
  workarounds (`haxe_ocaml-hhihe`), toolchain-bound receipts and unique plugin library names
  (`haxe_ocaml-kokp8`), typed adapter methods instead of the OCaml adapter template
  (`haxe_ocaml-gal5o`), and the macro host's own converter (`haxe_ocaml-0ln1t`).
- No `haxe.macro.Context` API is available to plugin code yet. In the plugin compilation, a macro
  `Position` is opaque (see the define gap below); `MacroSyntaxWire` is the only code that reads
  or builds its `{file, min, max}` record.
- Since step 2 hxhx builds the plugin itself. A plain `hxhx --hxhx-stage3 -cp src -main Main`
  records the selected declarations in a first pass, reuses or builds the plugin
  (`ProjectMacroPluginCache`: cache key over the compiler executable digest and OCaml version,
  ABI versions, declarations, classpaths, defines, working directory, and the runtime and shim
  sources; a receipt that also binds every source file the plugin compilation read), loads it,
  and runs the macros in a second pass. A child hxhx compiles the plugin with
  `--hxhx-macro-classpath` for each project classpath, and `dune` builds it. Each build gets a
  fresh plugin id, so plugin libraries never share OCaml unit names (`haxe_ocaml-kokp8`). A
  missing `dune`/`ocamlopt`, or an `ocamlopt` of another OCaml version than the binary, is one
  diagnostic before any build. The cache test is `npm run test:m14:project-macro-plugin-cache`;
  the end-to-end check with a native hxhx is `npm run test:macro-runtime:project-module`.
- Step 2 limits: the external host and the compilation server do not build or load plugins
  (the server needs one external host per plugin digest, as planned); a new file that changes a
  lookup without editing any recorded file is not detected; macro calls inside macro classes are
  not run.

## Approved plan (2026-10-29)

The owner approved this executor model after an independent design review (recorded on
`haxe_ocaml-9sj5p`). One native plugin per project is compiled by hxhx's own Stage3 OCaml emitter
in a macro compilation context and loaded through the existing receipt and Dynlink ABI, with one
typed adapter per macro declaration. Projects with macros require `dune` and `ocaml`; a missing
toolchain must produce one clear error. Plugins are cached by content digest. One-shot compiles
load plugins in-process; the `--wait` server uses the external macro host per plugin digest and
restarts it when the digest changes. An interpreter-based executor is deferred as post-Full1
research. Hard cuts follow the compatibility policy, and `expr_macro_unexecuted` becomes an error
after step 2.

1. Typed executor seam and in-process identity macro: `MacroSyntaxExport`/`MacroSyntaxImport`,
   `register_macro_declaration` with an ABI bump (`haxe_ocaml-9sj5p.3`, done).
2. Macro compilation context and plugin build and cache driver (`haxe_ocaml-9sj5p.4`).
3. Lower macro reification before backend emission (`haxe_ocaml-9sj5p.5`).
4. `MacroContextServices` v1 bound to the real typer; retire the synthetic `typeof`/`getType`
   in `hxhxmacrohost/api` (`haxe_ocaml-9sj5p.6`).
5. Real `--macro` init macros and compiler hooks; delete the fake
   `InProcGeneratedEntrypoints`/`EntryPointsGen` `Macro.init()` (`haxe_ocaml-9sj5p.7`).
6. Gate 1 Lite: `UnitBuilder.generateSpec` executes (`haxe_ocaml-9sj5p.8`).

### Prerequisites found by the review

- Reification: `EmitterStage.exprToOcaml` handles `EMacroExpr` (a `macro ...` quote) at
  `packages/hxhx-core/src/EmitterStage.hx:3381` only by rejecting lost source groups; it has no
  lowering, so a plugin whose macro body uses `macro ...` cannot be emitted. Step 3 owns it. The
  identity fixture therefore builds its result without reification.
- Macro-context defines: before step 2, `ModuleLoader.moduleDefines` and two copies in
  `ResolverStage` set `macro` and `eval` only for modules under `haxe.macro.*`, so in a plugin
  compilation the standard macro types saw the macro context while the project's own macro
  classes did not. Step 2 moved that rule into `MacroCompilationContext`
  (`packages/hxhx-core/src/MacroCompilationContext.hx`), which the resolver and the lazy loader
  share. A request can now name macro classpaths (`--hxhx-macro-classpath <dir>`); modules
  resolved through them are compiled with `macro` and `eval` added to the request defines.
  Standard-library roots keep their target branches, even when nested inside a macro classpath,
  because the plugin is still compiled to OCaml. One difference from upstream remains: the
  `ocaml` target define stays defined in macro modules, while upstream's eval macro context does
  not define the program's target. Covered by `npm run
  test:m14:macro-compilation-context`.
- Prerequisite beads checked on 2026-10-29: `o25kr` (source groups) has landed enough for the
  identity function (`ESourceGroup`/`ESourceFunction` round-trip exactly); `yhvzj` (nested
  patterns) and `05q72` (object literals) no longer block the identity macro, whose nested enum
  patterns and object literals compile and run natively; `20jan` (comprehensions) is not needed
  by the identity case; `pi2q3` concerns the macro host build and is not needed for in-process
  plugins.
- A Stage3 callback-program defect blocked the identity program itself: a selected instance call
  (`events.push(...)`) inside a function value was counted as callback arguments
  (`haxe_ocaml-fikpj`). Step 1 fixed the no-callback-parameter case; instance methods that take
  callbacks still need the full fix.

A real expression macro receives written Haxe syntax before ordinary typing.
For example, it can inspect `while (unknown) { tick(unknown); }` and replace it
with a string. The compiler must not resolve those names or execute the loop
when the macro consumes that argument.

The fixture in `test/fixtures/expression_macro_while` states this contract.
Upstream Haxe 4.3.7 accepts it and prints `syntax-ok`. Its ordinary-call control
fails with `Void should be Dynamic`. The identity-macro workload recorded in
`haxe_ocaml-9sj5p` also requires authored functions, signatures, braces, and returns.

## Current boundaries and their limits

`Stage3Compiler` invokes `ExprMacroExpander` before shared typing. However,
expansion requires an explicit list of exact expression strings.
`renderSimpleCall` recognizes only zero arguments or one string literal.
The parser already retains the `macro` modifier in function metadata.
The expansion pass does not use that metadata to select real macro declarations.

`ExprMacroDeclarationSelector` now provides a separate query for one public static
macro declaration. It uses shared import resolution and retains original argument
nodes without typing or expanding them. Its focused test covers aliases, ordinary
calls, caller-supplied visible names, and outer-call syntax retention.
Production expansion now calls this query through `Stage3ExprMacroPass`. The pass
builds the header index and request loader, marks the resolved modules, and hands
both to `ExprMacroExpander` as an `ExprMacroSelectionContext`; modules the loader
discovers during selection are walked too, and after any rewrite the index and
loader are rebuilt once (the rebuilt loader keeps the record of missing-type hooks
already asked). Modules loaded during selection are reported to the driver so the
no-emit lane, which otherwise types only its roots plus what typing discovers, still
types their bodies. A receiver path whose last segment is not uppercase-initial
(`Main.instance.run()`) is never resolved as a type, matching the typer. Precedence per call: a registered exact-text expression (the
allowlist, including promoted no-argument plugins) keeps the exact-text route; else
a callee that selects a macro declaration is consumed before its children are
visited and sent to `MacroRuntimeSession.expandSelected` as one
`ExprMacroDispatchRequest` (selected declaration, original argument nodes, call
file); `Expanded` syntax is inserted in place. A private static macro is selectable
from its own class. Calls inside a lexical gap are not selected; the gap count is
reported. When the session answers `Unavailable`, the call is recorded
(`expr_macro_unexecuted[i]=<file>: <declaration>: <reason>`). Since step 2 that is a compile
error (`<file>: expression macro <declaration> was not executed: <reason>`), because
compiling the call as an ordinary call would give a program upstream Haxe never produces. One
scoped exception remains, hxhx's own `CompilerBundledSourcesMacro.files()` (it embeds
standard-library sources during hxhx's own build and needs `Context` and reification, steps 3
and 4); that call is still typed under the macro call-site contract (`TyMacroCallSignature`:
`Expr` positions accept any expression, a trailing `Array<Expr>` is a rest position, the result
is `Dynamic`). Before step 2, every unexecuted call continued that way, which also kept the
emitter's `isCi` intrinsic for upstream `tests/runci/Config.hx` working; `isCi` uses
reification, so Stage3 compiles of the runci sources now stop at that call until step 3. Static-extension and
value-receiver macro calls are not selected (haxe_ocaml-1tyip); modules first loaded
during body typing are not walked (haxe_ocaml-uf1hx).
Mixed imported fields and
methods produce an explicit unsupported diagnostic until shared lookup returns one
ordered member. This query does not prove execution of a project's macro body.

`MacroRuntimeSession.expandExpr` sends a string and receives expression text; it now serves only
built-in and generated exact-text entrypoints. Before step 1 the native plugin registration
stored a `unit -> string` callback that could not receive syntax arguments or return structured
syntax; plugin ABI version 2 removed it.

The [first project-module decision](PROJECT_MACRO_MODULE_PATH_DECISION.md)
proved loading, identity checks, and no-argument handlers. It is superseded by step 1.

`HxSourceMacroSyntax` maps several authored constructs to public macro syntax.
`MacroSyntaxExport` uses it for authored control syntax; `RuntimeMacroExprs.convert` in the macro
host still keeps its own copy of the remaining cases.
`RuntimeMacroExprs.convert` currently assigns the supplied position to each
converted node. `HxPos` records a start index, line, and column; it has no end
index or file identity. Several expression constructors have no position.
These facts prevent a claim of complete source-span preservation.

## Proposed ownership

1. Resolve the called declaration before choosing macro or ordinary typing.
   Use resolved modules, imports, and the declaration's `macro` metadata.
   Identify the declaration independently of its argument text.
   Keep local shadowing and ordinary functions on the ordinary typing path.
2. Preserve arguments as authored syntax until the selected macro consumes them.
   Do not recursively expand nested calls in an outer macro's syntax arguments
   merely because the existing ordinary-call traversal visits children first.
3. Compile the project's actual macro body with the macro compilation context.
   Generate a typed Haxe adapter for its declared parameters and `Expr` result.
   Do not substitute a handwritten handler with equivalent output.
4. Keep a reusable host and separately compiled project plugins.
   Use one versioned structured request and result contract in both modes.
   Decode external data immediately into validated Haxe types.
5. Keep native code limited to loading and calling the registered callback.
   Haxe owns declaration selection, argument conversion, validation, positions,
   result conversion, and failure policy.
6. Replace the old plugin contract with an explicit ABI and receipt version change.
   Migrate its consumers together; reject old receipts and registrations.
   Retain candidate, path, digest, duplicate-registration, and isolation checks.

Strings can carry an encoded request across the existing process boundary.
They must not become source text that native adapters parse to infer intent.
The precise syntax schema remains an implementation decision. It must preserve
ordered children, written type annotations, omitted fields, and available positions.
Unknown node kinds or malformed results must fail before ordinary typing.

## Implementation order and decisive checks

First, restore traversal of current source nodes. Parentheses and source `try`
must preserve their structure, catch declarations, and positions during expansion.
A unit test can prove this with controlled no-argument handlers. That result
does not prove real macro invocation.

Next, compile the actual identity macro body through the current Haxe-authored
native route. Prove its public enum patterns and expression records before
changing the plugin ABI. Record any compiler gap at its reusable owner.

Then establish declaration selection and source-position ownership. Check an
ordinary same-named function, an imported macro, a shadowed name, and a nested
macro call retained as argument syntax. Preserve real file identity and exact
spans where the public API exposes them; do not invent end positions.

The first actual macro-body probe compiled an executable but exposed incomplete
generated behavior. Array and object pattern predicates became `false`.
The reduced ordinary pattern program is owned by `haxe_ocaml-yhvzj`.
Object literals also become placeholder values; `haxe_ocaml-05q72` owns that
allocation and typed-storage requirement. Compilation alone cannot clear either
prerequisite or prove execution of the macro body.

Only then implement structured requests, generated adapters, and result insertion.
Run the unchanged identity and loop fixtures in both native macro modes.
Build the host once and reuse it across projects. Require equivalent output and
syntax observations, plus rejection of malformed payloads and invalid receipts.

Finally, reconcile the typed-body loop fixture with that real pre-typing path.
Retain the ordinary-call rejection and the full typed-body integration command.
Run macro/plugin, source-control, bootstrap, and combined checks before closure.

## Review and claims

A local second pass must challenge staging order, declaration identity, public
syntax shape, source spans, and host reuse. The session forbids another Oracle
request. Existing Oracle advice is advisory evidence, not transport validation.

Do not increase Full1 or release readiness from upstream-only checks, a mocked
session, or the no-argument plugin pilot. Native execution and the relevant
upstream suites remain required evidence. Neither owning task closes with this plan.
