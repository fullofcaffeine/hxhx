# Expression metadata syntax

Haxe 4.3.7 keeps `@:name(args) expr` and `@name(args) expr` as `EMeta` with the exact name, and it keeps a call-site `inline f()` as `@:inline f()`.

hxhx keeps that syntax only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads, through the `HxAuthoredSyntax.META` marker. The marker carries the full name, colon included, and the export prints it as `EMeta`. Ordinary parsing keeps the `__hxhx_expr_meta` marker that the typer and macro lowering read, and it drops a call-site `inline`.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_expression_metadata_syntax_test.hxml`.
