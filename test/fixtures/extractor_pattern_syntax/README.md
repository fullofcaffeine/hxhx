# Extractor pattern syntax

Haxe 4.3.7 parses a case pattern as an expression. An extractor such as `_.get() => v` is an `=>` binary operation: the left side runs on the matched value (`_`), and the right side is the pattern for its result.

The hxhx parser keeps the left side as source text (`HxSwitchPattern.PExtractor(text, result)`). `MacroBodyExport` reads that text again with the authored parser and exports the pattern as the same `=>` operation, so the parse oracle compares it with upstream.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_extractor_pattern_syntax_test.hxml`.
