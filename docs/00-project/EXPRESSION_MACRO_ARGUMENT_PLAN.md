# Pass authored syntax to project expression macros

Status: proposed implementation sequence; native argument transport is unfinished.
Owners: `haxe_ocaml-9sj5p` and `haxe_ocaml-geafz`.

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

`MacroRuntimeSession.expandExpr` sends a string and receives expression text.
Both runtime modes reach native handlers through `NativeMacroModuleHost`.
The native registration stores a `unit -> string` callback. It cannot receive
syntax arguments or return structured syntax with preserved positions.

The [first project-module decision](PROJECT_MACRO_MODULE_PATH_DECISION.md)
proves loading, identity checks, and no-argument handlers. Its fixture uses a
separate native text handler. It does not prove compilation of the real macro
body or general `haxe.macro.Expr` arguments.

`HxSourceMacroSyntax` maps several authored constructs to public macro syntax.
It is useful conversion infrastructure, not a complete transport contract.
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
