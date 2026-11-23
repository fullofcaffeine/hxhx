# Block ends expression

Haxe 4.3.7 continues an expression after `{ ... }` only when the braces are an object literal (`grammar.mly:1388-1390`). After `if (flag) { ... }`, a line that starts with `(` is the next statement.

hxhx used to parse that line as a call of the block. The switch case then lost its value, and hxhx rejected the valid program. `haxe.macro.Printer.printTypeDefinition` has this shape.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_block_ends_expression_test.hxml`.
