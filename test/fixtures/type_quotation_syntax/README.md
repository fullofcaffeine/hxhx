# Type quotation syntax

Haxe 4.3.7 turns a type quotation, `macro : T`, into ordinary syntax while it parses. The result is an expression that builds the `ComplexType` value, such as `(TPath({ pack : [], name : "Null", params : [TPType(t)] }) : haxe.macro.Expr.ComplexType)`. That is why this fixture runs outside a macro context.

hxhx keeps the quotation as `HxExpr.EMacroType(text)` until the typer lowers it. `MacroSyntaxExport` writes the same construction syntax as upstream (`MacroTypeQuotation`), so the parse oracle compares it with upstream.

`expected.bodies.json` holds the bodies that upstream's parse recorder printed. Run `node_modules/.bin/haxe test/m14_type_quotation_syntax_test.hxml`.
