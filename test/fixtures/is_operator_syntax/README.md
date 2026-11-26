# `is` operator syntax

Haxe 4.3.7 parses `x is T` as `EIs(x, T)`, where `T` is a type, not an expression, so `x is T<Int>` keeps its type parameters. A macro receives that syntax before typing.

hxhx keeps `x is T` as an `is` binary operation. The right side is the type path written as an expression, or `__hxhx_is_type_arguments("T<Int>")` when the type has parameters. `MacroSyntaxExport` exports it as `EIs`, and `MacroSyntaxImport` turns `EIs` back into the same parser form.

`Syntax.show` prints each argument and the structure of its `is` types; `expected.stdout` is upstream's output. Run `node_modules/.bin/haxe test/m14_is_operator_syntax_test.hxml`.
