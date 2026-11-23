# Interpolation syntax

Haxe 4.3.7 keeps a single-quoted string that contains `$` as one `CString(text, SingleQuotes)`, and it expands the interpolation during typing.

hxhx keeps that string only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads, as `EString(text, true)`. Ordinary parsing still expands `'a ${x}'` into concatenation while parsing. The parse oracle prints single-quoted strings without `$` with double quotes on both sides, and so does upstream's recorder here.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_interpolation_syntax_test.hxml`.
