import haxe.macro.Expr;
import hxhxmacrohost.api.RuntimeMacroExprs;

class M14RuntimeInlineMarkupParseIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function assertMarkup(expr:Expr, expectedPayload:String, label:String):Void {
		switch (expr.expr) {
			case EMeta(meta, inner):
				assertTrue(meta != null && meta.name == ":markup", label + ": expected :markup metadata");
				switch (inner.expr) {
					case EConst(CString(value, _)):
						assertTrue(value == expectedPayload, label + ": expected markup payload " + expectedPayload + " but got " + value);
					case _:
						fail(label + ": expected markup payload string");
				}
			case _:
				fail(label + ": expected markup expr");
		}
	}

	static function main():Void {
		final pos:Position = cast {
			file: "RuntimeInlineMarkupParseIntegrationTest.hx",
			min: 0,
			max: 0
		};

		final rootMarkup = RuntimeMacroExprs.parseInlineString('<div class="shell">$${title}</div>', pos);
		assertMarkup(rootMarkup, '<div class="shell">$${title}</div>', "root markup");

		final conditionalMarkup = RuntimeMacroExprs.parseInlineString('if (assigns.show) <span class="yes">Yes</span> else <span class="no">No</span>', pos);
		switch (conditionalMarkup.expr) {
			case EIf(cond, thenExpr, elseExpr):
				switch (cond.expr) {
					case EField(owner, "show", _):
						switch (owner.expr) {
							case EConst(CIdent("assigns")):
							case _:
								fail("if markup: expected assigns.show owner");
						}
					case _:
						fail("if markup: expected assigns.show condition");
				}
				assertMarkup(thenExpr, '<span class="yes">Yes</span>', "if markup then");
				assertTrue(elseExpr != null, "if markup: expected else branch");
				assertMarkup(elseExpr, '<span class="no">No</span>', "if markup else");
			case _:
				fail("if markup: expected EIf");
		}

		final forEachMarkup = RuntimeMacroExprs.parseInlineString('HeexTemplate.for_each(assigns.items, (item) -> <li>$${item.name}</li>)', pos);
		switch (forEachMarkup.expr) {
			case ECall(callee, args):
				assertTrue(args.length == 2, "for_each markup: expected two args");
				switch (callee.expr) {
					case EField(owner, "for_each", _):
						switch (owner.expr) {
							case EConst(CIdent("HeexTemplate")):
							case _:
								fail("for_each markup: expected HeexTemplate owner");
						}
					case _:
						fail("for_each markup: expected field callee");
				}
				switch (args[0].expr) {
					case EField(owner, "items", _):
						switch (owner.expr) {
							case EConst(CIdent("assigns")):
							case _:
								fail("for_each markup: expected assigns.items owner");
						}
					case _:
						fail("for_each markup: expected assigns.items arg");
				}
				switch (args[1].expr) {
					case EFunction(FArrow, fn):
						assertTrue(fn.args != null && fn.args.length == 1 && fn.args[0].name == "item", "for_each markup: expected arrow arg item");
						assertMarkup(fn.expr, '<li>$${item.name}</li>', "for_each markup body");
					case _:
						fail("for_each markup: expected arrow lambda");
				}
			case _:
				fail("for_each markup: expected ECall");
		}

		final eachMarkup = RuntimeMacroExprs.parseInlineString('H.each(assigns.items, (item) -> <li>$${item.name}</li>)', pos);
		switch (eachMarkup.expr) {
			case ECall(callee, args):
				assertTrue(args.length == 2, "each markup: expected two args");
				switch (callee.expr) {
					case EField(owner, "each", _):
						switch (owner.expr) {
							case EConst(CIdent("H")):
							case _:
								fail("each markup: expected H owner");
						}
					case _:
						fail("each markup: expected field callee");
				}
				switch (args[1].expr) {
					case EFunction(FArrow, fn):
						assertTrue(fn.args != null && fn.args.length == 1 && fn.args[0].name == "item", "each markup: expected arrow arg item");
						assertMarkup(fn.expr, '<li>$${item.name}</li>', "each markup body");
					case _:
						fail("each markup: expected arrow lambda");
				}
			case _:
				fail("each markup: expected ECall");
		}
	}
}
