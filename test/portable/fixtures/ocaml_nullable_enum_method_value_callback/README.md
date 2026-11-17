# Pass a nullable-enum method as a non-null enum callback

`Refs.expression(node:Null<Expr>)` is passed as a method value to
`Walk.children(node:Expr, onChild:Expr->Void)`. `Refs` and `Walk` refer to each
other, so the backend emits them in one recursive module group with explicit
signatures. That signature fixes the callback parameter to `Expr`, while the
method expects `Null<Expr>`, which the OCaml target carries as `Obj.t`.

This reproduces the bootstrap regeneration failure in
`backend_ocaml_OcamlPreludeReferences.ml`, where OCaml rejected
`fun a0 -> expression self a0`. The bound method closure must convert the plain
enum value to the nullable carrier, exactly as lambda callback adapters do.

Run `PORTABLE_FIXTURE_ALLOWLIST=ocaml_nullable_enum_method_value_callback bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
