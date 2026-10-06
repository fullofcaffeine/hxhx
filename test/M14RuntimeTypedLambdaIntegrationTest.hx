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

	/** An identity macro must see every authored group and return the same syntax object. */
	static function identitySourceFunction(value:Expr):Expr {
		switch value.expr {
			case EFunction(FAnonymous, fn):
				assertTrue(fn.args.length == 1 && fn.args[0].name == "item" && !fn.args[0].opt && fn.args[0].value == null,
					"source function changed its required parameter or fabricated a default");
				assertTrue(switch [fn.args[0].type, fn.ret] {
					case [TPath({pack: [], name: "String"}), TPath({pack: [], name: "Dynamic"})]: true;
					case _: false;
				}, "source function changed its written signature");
				assertTrue(switch fn.expr.expr {
					case EBlock([
						{
							expr: EVars([
								{
									name: "result",
									type: null,
									expr: {
										expr: EBlock([
											{expr: EBlock([{expr: EReturn({expr: EConst(CIdent("item"))})}])},
											{expr: EConst(CString("wrong", _))}
										])
									}
								}
							])
						},
						{
							expr: EBinop(OpAssignOp(OpAdd), {expr: EField({expr: EConst(CIdent("State"))}, "events", _)}, {expr: EConst(CString("after", _))})
						},
						{expr: EReturn({expr: EConst(CIdent("result"))})}
					]): true;
					case _: false;
				}, "source function changed nested braces, explicit returns, or later syntax");
			case _:
				fail("source function changed its anonymous function kind");
		}
		return value;
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
		final emptyWhile = RuntimeMacroExprs.parseInlineString("while (ready) {}", pos);
		switch RuntimeMacroExprs.parseInlineString("do { ping(); } while (ready)", pos).expr {
			case EWhile({expr: EConst(CIdent("ready"))}, {expr: EBlock([{expr: ECall({expr: EConst(CIdent("ping"))}, [])}])}, false):
			case _:
				fail("expected do/while to preserve the public macro loop kind");
		}

		switch (emptyWhile.expr) {
			case EWhile({expr: EConst(CIdent("ready"))}, {expr: EBlock(body)}, true):
				assertTrue(body.length == 0, "expected the macro while body to remain an empty block");
			case _:
				fail("expected an expression-position while loop to reach the macro API as EWhile");
		}
		final populatedWhile = RuntimeMacroExprs.parseInlineString("while (ready) { ping(); }", pos);
		switch (populatedWhile.expr) {
			case EWhile({expr: EConst(CIdent("ready"))}, {expr: EBlock([{expr: ECall({expr: EConst(CIdent("ping"))}, [])}])}, true):
			case _:
				fail("expected a non-empty macro while body to preserve its nested call");
		}
		switch (RuntimeMacroExprs.parseInlineString("break", pos).expr) {
			case EBreak:
			case _:
				fail("expected expression-position break to reach the macro API as EBreak");
		}
		switch (RuntimeMacroExprs.parseInlineString("continue", pos).expr) {
			case EContinue:
			case _:
				fail("expected expression-position continue to reach the macro API as EContinue");
		}
		final parsed = RuntimeMacroExprs.parseInlineString("(item) -> item.name", pos);
		for (source in ["(item:Int = 5) -> item", "function(item:Int = 5) return item"])
			switch RuntimeMacroExprs.parseInlineString(source, pos).expr {
				case EFunction(kind, fn):
					assertTrue(fn.args.length == 1 && fn.args[0].opt == (kind == FArrow),
						"defaulted arrow and full function lost their distinct upstream optional flags");
					assertTrue(switch fn.args[0].value.expr {
						case EConst(CInt("5", _)): true;
						case _: false;
					}, "macro arrow lost its default expression");
				case _:
					fail("defaulted source function lost its macro function form");
			}
		final annotated = RuntimeMacroExprs.parseInlineString("function(item:String):Dynamic return item", pos);
		final grouped = RuntimeMacroExprs.parseInlineString('function(item:String):Dynamic {'
			+ 'var result = { { return item; } "wrong"; }; State.events += "after"; return result; }', pos);
		assertTrue(identitySourceFunction(grouped) == grouped, "identity macro replaced the original syntax object");
		switch (annotated.expr) {
			case EFunction(FAnonymous, fn):
				assertTrue(fn.args.length == 1 && fn.args[0].name == "item", "annotated function lost its parameter");
				assertTrue(switch (fn.args[0].type) {
					case TPath({pack: [], name: "String"}): true;
					case _: false;
				}, "annotated function lost its written String parameter");
				assertTrue(switch (fn.ret) {
					case TPath({pack: [], name: "Dynamic"}): true;
					case _: false;
				}, "annotated function lost its written Dynamic result");
				assertTrue(switch (fn.expr.expr) {
					case EReturn({expr: EConst(CIdent("item"))}): true;
					case _: false;
				}, "annotated function lost its authored return expression");
			case _:
				fail("full function syntax became an arrow function in the macro AST");
		}
		final sequence = RuntimeMacroExprs.parseInlineString("function() { ping(); return 7; }", pos);
		switch (sequence.expr) {
			case EFunction(_, {
				expr: {
					expr: EBlock([
						{expr: ECall({expr: EConst(CIdent("ping"))}, [])},
						{expr: EReturn({expr: EConst(CInt("7", _))})}
					])
				}
			}):
			case _:
				fail("expected the macro function body to preserve the call before its result");
		}
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
