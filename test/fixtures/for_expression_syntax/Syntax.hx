import haxe.macro.Expr;

/** Prints a macro argument and the iterator of each `for` in it. */
class Syntax {
	public static macro function show(e:Expr):Expr {
		return macro $v{describe(e)};
	}

	public static function describe(e:Expr):String {
		final iterators = [];
		function visit(value:Expr):Void {
			switch value.expr {
				case EFor(iterator, _):
					iterators.push(kind(iterator));
				case _:
			}
			haxe.macro.ExprTools.iter(value, visit);
		}
		visit(e);
		return new haxe.macro.Printer().printExpr(e) + " | " + iterators.join(" ; ");
	}

	static function kind(e:Expr):String {
		return switch e.expr {
			case EConst(CInt(value, _)): "int " + value;
			case EConst(CIdent(name)): "ident " + name;
			case EParenthesis(inner): "paren(" + kind(inner) + ")";
			case EBinop(OpIn, left, right): "in(" + kind(left) + "," + kind(right) + ")";
			case EBinop(OpArrow, left, right): "arrow(" + kind(left) + "," + kind(right) + ")";
			case ECall(callee, arguments): "call(" + kind(callee) + "," + arguments.length + ")";
			case _: "other";
		}
	}
}
