# Imported module functions in array iteration

A plain module import must expose its public module-level functions. Their
declared Boolean results must reach array iteration without becoming unknown
types. An ordinary class method in the same module still needs a qualified call.

Run `haxe test/m14_imported_module_function_iterator_test.hxml` from the repository
root. The test runs `Main` with upstream Haxe, types the same authored program,
generates OCaml, builds its native executable, and compares its output. It checks
call order and evaluation count, explicit function aliases, and precedence when
two imported modules expose the same function name.

The test also checks private-function and ordinary-static exclusion, type aliases,
explicit secondary type imports,
local shadowing, and preservation of module scope in typed declarations and
source projections. Two otherwise identical functions with different source
scopes must have different declaration identities and public interface revisions.
An imported Boolean call in a written `Array<Int>` must fail both upstream and
local source typing.

Private-function, ordinary-static, and type-alias negative programs are upstream
source checks plus local import-lookup checks. The local typer and projection
currently accept their unresolved bare calls; this test does not claim matching
missing-name diagnostics or native rejection for those programs.
The local-shadowing control is checked with upstream Haxe and the source typer;
it does not claim native support for local callback calls.

This is an internal compiler regression fixture. It does not change README Goals
status or establish support for native expression-macro argument transport.
