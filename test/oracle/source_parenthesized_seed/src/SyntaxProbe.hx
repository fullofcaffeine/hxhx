import haxe.macro.Expr;

/** Observe public macro syntax without inspecting upstream compiler implementation. */
class SyntaxProbe {
	static function shape(expression:Expr):String {
		return switch expression.expr {
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case EConst(CIdent(name)): name;
			case EConst(CInt(value, _)): value;
			case EBinop(OpAssign, left, right): "assign(" + shape(left) + "," + shape(right) + ")";
			case EBinop(OpAdd, left, right): "add(" + shape(left) + "," + shape(right) + ")";
			case EBinop(OpMult, left, right): "mul(" + shape(left) + "," + shape(right) + ")";
			case _: throw "unexpected syntax probe expression";
		};
	}

	public static macro function observe():Expr {
		final cases = ["((value))", "(value = 3)", "((value = 3))", "(1 + 2) * 3", "(value) = 4"];
		return macro $v{
			[
				for (source in cases)
					shape(haxe.macro.Context.parse(source, haxe.macro.Context.currentPos()))
			].join("\n")
		};
	}
}
