# `for` with an expression

Haxe 4.3.7 reads any expression after `for (`, so `for (1) "foo"` is `EFor(1, "foo")`. Only typing requires `name in iterable`. The upstream unit suite quotes such a loop (`macro for (1) "foo"` in `unitstd/haxe/macro/ExprTools.unit.hx`).

hxhx keeps a loop whose head is `name in ...` or `key => value in ...` as `ESourceFor`. Any other head becomes `__hxhx_for_expression(iterator, body)`. `MacroSyntaxExport` exports both as `EFor`, and `MacroSyntaxImport` turns `EFor` back into the same parser form.

`Syntax.show` prints each argument and the shape of its `for` iterator; `expected.stdout` is upstream's output. Run `node_modules/.bin/haxe test/m14_for_expression_syntax_test.hxml`.
