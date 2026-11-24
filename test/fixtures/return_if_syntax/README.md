# Return if syntax

Haxe 4.3.7 keeps `return if (c) a else b` as one `EReturn(EIf)`.

hxhx keeps that shape only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads. This includes abstract bodies that the scanner path re-parses. Ordinary parsing still rewrites the statement into an `if` with a return in each branch, and it sets `SIf.valueReturn`, which the typer reads for recursive results.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. It leaves out the constructors, because upstream names an abstract's constructor `_new`. Run `node_modules/.bin/haxe test/m14_return_if_syntax_test.hxml`.
