# Cast pattern syntax

Haxe 4.3.7 keeps a `case cast Array:` class-value pattern as an `ECast` in the syntax tree.

hxhx marks the pattern only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads, as `PEnumValue(name, true)`. The export prints `cast Array`. Ordinary parsing keeps the plain class-value pattern.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_cast_pattern_syntax_test.hxml`.
