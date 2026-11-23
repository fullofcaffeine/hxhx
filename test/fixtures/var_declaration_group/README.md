# Var declaration group

Haxe 4.3.7 keeps `var a = 1, b = 2;` as one `EVars` with every declarator.

hxhx keeps the declarators together only in authored parsing (`ParserStage.parseAuthored`), which the parse oracle reads, as an `SBlock` marked `declarationGroup`. The export prints the group as one `EVars`. Ordinary parsing still flattens the declarators into the enclosing block.

In single-statement position, upstream reads one declarator only, so the fixture does not use that form. `expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_var_declaration_group_test.hxml`.
