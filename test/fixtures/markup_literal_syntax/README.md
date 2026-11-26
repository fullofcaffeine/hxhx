# Inline markup literal syntax

Haxe 4.3.7 reads an inline markup literal such as `<p class="a">text</p>` in expression position. The lexer takes the source text from `<` to the matching close tag: a tag with the same name nests, `/>` closes the opening tag, and `<>` starts a fragment that `</>` ends. Quotes, comments and regex text inside the literal are plain text. The parser gives `@:markup "<text>"`. A block statement that is a markup literal needs no semicolon.

A macro must process the literal. `Markup.text` returns its text, so the fixture can print what upstream read.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_markup_literal_syntax_test.hxml`.
