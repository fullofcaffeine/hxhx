import haxe.macro.Expr;
import haxe.macro.Type;
import hxhxmacrohost.api.RuntimeMacroExprs;
import hxhxmacrohost.api.RuntimeTypedExprs;

class M14RuntimeTypedLambdaIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function main():Void {
		final pos:Position = cast {
			file: "RuntimeTypedLambdaIntegrationTest.hx",
			min: 0,
			max: 0
		};
		final prefixIncrement = RuntimeMacroExprs.parseInlineString("++value", pos);
		switch (prefixIncrement.expr) {
			case EUnop(OpIncrement, false, {expr: EConst(CIdent("value"))}):
			case _:
				fail("expected prefix increment to preserve postFix=false");
		}
		final postfixIncrement = RuntimeMacroExprs.parseInlineString("value++", pos);
		switch (postfixIncrement.expr) {
			case EUnop(OpIncrement, true, {expr: EConst(CIdent("value"))}):
			case _:
				fail("expected postfix increment to preserve postFix=true");
		}
		final typedPrefixIncrement = RuntimeTypedExprs.typeExpr(prefixIncrement);
		assertTrue(RuntimeTypedExprs.toString(typedPrefixIncrement) == "++value", "expected typed prefix increment text");
		switch (RuntimeTypedExprs.toExpr(typedPrefixIncrement).expr) {
			case EUnop(OpIncrement, false, {expr: EConst(CIdent("value"))}):
			case _:
				fail("expected typed prefix increment round-trip to preserve postFix=false");
		}
		final typedPostfixIncrement = RuntimeTypedExprs.typeExpr(postfixIncrement);
		assertTrue(RuntimeTypedExprs.toString(typedPostfixIncrement) == "value++", "expected typed postfix increment text");
		switch (RuntimeTypedExprs.toExpr(typedPostfixIncrement).expr) {
			case EUnop(OpIncrement, true, {expr: EConst(CIdent("value"))}):
			case _:
				fail("expected typed postfix increment round-trip to preserve postFix=true");
		}
		final typedPrefixDecrement = RuntimeTypedExprs.typeExpr(RuntimeMacroExprs.parseInlineString("--value", pos));
		assertTrue(RuntimeTypedExprs.toString(typedPrefixDecrement) == "--value", "expected typed prefix decrement text");
		switch (RuntimeTypedExprs.toExpr(typedPrefixDecrement).expr) {
			case EUnop(OpDecrement, false, {expr: EConst(CIdent("value"))}):
			case _:
				fail("expected typed prefix decrement round-trip to preserve its operator and postFix=false");
		}
		final parsed = RuntimeMacroExprs.parseInlineString("(item) -> item.name", pos);
		switch (parsed.expr) {
			case EFunction(FArrow, fn):
				assertTrue(fn.args != null && fn.args.length == 1, "expected one arrow arg");
				assertTrue(fn.args[0].name == "item", "expected arrow arg name item");
				switch (fn.expr.expr) {
					case EField(owner, "name", _):
						switch (owner.expr) {
							case EConst(CIdent("item")):
							case _:
								fail("expected arrow body owner item");
						}
					case _:
						fail("expected arrow body field access");
				}
			case _:
				fail("expected parsed arrow function");
		}

		final typed = RuntimeTypedExprs.typeExpr(parsed);
		assertTrue(RuntimeTypedExprs.toString(typed) == "(item) -> item.name", "expected typed arrow string");
		assertTrue(switch (typed.t) {
			case TFun(args, ret): args.length == 1 && args[0].name == "item" && RuntimeTypedExprs.toString(typed) == "(item) -> item.name";
			case _:
				false;
		}, "expected typed arrow function type");

		switch (typed.expr) {
			case TFunction(fun):
				assertTrue(fun.args != null && fun.args.length == 1, "expected typed arrow arg");
				assertTrue(fun.args[0].v.name == "item", "expected typed arrow arg name item");
				assertTrue(switch (fun.expr.expr) {
					case TField(owner, FDynamic("name")):
						switch (owner.expr) {
							case TIdent("item"): true;
							case _: false;
						}
					case _: false;
				}, "expected typed arrow body field access");
			case _:
				fail("expected TFunction typed expr");
		}

		final roundTrip = RuntimeTypedExprs.toExpr(typed);
		switch (roundTrip.expr) {
			case EFunction(FArrow, fn):
				assertTrue(fn.args != null && fn.args.length == 1, "expected one roundtrip arrow arg");
				assertTrue(fn.args[0].name == "item", "expected roundtrip arrow arg name item");
				switch (fn.expr.expr) {
					case EField(owner, "name", _):
						switch (owner.expr) {
							case EConst(CIdent("item")):
							case _:
								fail("expected roundtrip arrow owner item");
						}
					case _:
						fail("expected roundtrip arrow body field access");
				}
			case _:
				fail("expected roundtrip arrow function");
		}
	}
}
