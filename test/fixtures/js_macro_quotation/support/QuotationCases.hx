import haxe.macro.Expr;

/** Observe the original quoted syntax through real public enum constructors and payloads. */
class QuotationCases {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function isInt(value:Expr, expected:String):Bool
		return switch value.expr {
			case EConst(CInt(text, _)): text == expected;
			case _: false;
		};

	public static function run():Void {
		final string = macro "bar";
		switch string.expr {
			case EConst(CString("bar", _)):
			case _:
				throw "string quotation";
		}
		final field = macro null.foo;
		switch field.expr {
			case EField({expr: EConst(CIdent("null"))}, "foo", _):
			case _:
				throw "field quotation";
		}
		final binary = macro 1
		in 0;
		switch binary.expr {
			case EBinop(OpIn, left, right):
				require(isInt(left, "1") && isInt(right, "0"), "in operands");
			case _:
				throw "in quotation";
		}
		final name = "selected";
		final splice = macro deq(0, $i{name}(0));
		switch splice.expr {
			case ECall({expr: EConst(CIdent("deq"))}, [left, {expr: ECall({expr: EConst(CIdent("selected"))}, [right])}]):
				require(isInt(left, "0") && isInt(right, "0"), "splice arguments");
			case _:
				throw "identifier splice";
		}
		final absent = macro if (1) 2;
		switch absent.expr {
			case EIf(condition, yes, no):
				require(isInt(condition, "1") && isInt(yes, "2") && no == null, "missing else");
			case _:
				throw "if quotation";
		}
		final present = macro if (1) 2 else 3;
		switch present.expr {
			case EIf(condition, yes, no):
				require(isInt(condition, "1") && isInt(yes, "2") && no != null && isInt(no, "3"), "present else");
			case _:
				throw "if else quotation";
		}
		final type = macro :X->Y;
		switch type {
			case TFunction([TPath({name: "X"})], TPath({name: "Y"})):
			case _:
				throw "function type quotation";
		}
		final constructed = TOptional(TNamed("a", macro :Int));
		switch constructed {
			case TOptional(TNamed("a", TPath({name: "Int"}))):
			case _:
				throw "nested enum construction";
		}
	}
}
