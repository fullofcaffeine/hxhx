# Char code pattern syntax

Haxe 4.3.7 keeps `case "x".code:` as the field access `"x".code` in the syntax tree, also inside or-patterns and array patterns.

hxhx records the string on the pattern only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads, as `PInt(code, text)`. The export prints the pattern as `"x".code`. Ordinary parsing keeps the folded `PInt(code)` pattern.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_char_code_pattern_syntax_test.hxml`.
