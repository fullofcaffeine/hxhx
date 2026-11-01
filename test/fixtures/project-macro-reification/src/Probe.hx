import haxe.macro.Expr;

/**
	Print the structure of the expression `Macros.build` returns, without positions.

	Upstream runs it in the macro context (`haxe -cp src --macro Probe.main() --no-output`);
	hxhx compiles it natively through its Stage3 emitter. Both must print `probe-expected.stdout`.
**/
class Probe {
	public static function main():Void {
		// Positions are not printed: upstream's eval keeps them opaque, so only the shape is comparable.
		Sys.println(shape(Macros.build(macro ["alpha", "beta"])));
	}

	static function shape(e:Expr):String {
		return switch e.expr {
			case EConst(CInt(v, _)): v;
			case EConst(CFloat(v, _)): v;
			case EConst(CString(v, _)): '"' + v + '"';
			case EConst(CIdent(v)): v;
			case EConst(CRegexp(_, _)): "~";
			case EBlock(entries): "{" + [for (entry in entries) shape(entry)].join("; ") + "}";
			case EArrayDecl(values): "[" + [for (value in values) shape(value)].join(", ") + "]";
			case ECall(callee, arguments): shape(callee) + "(" + [for (argument in arguments) shape(argument)].join(", ") + ")";
			case EField(owner, name, _): shape(owner) + "." + name;
			case EBinop(OpAdd, left, right): "(" + shape(left) + " + " + shape(right) + ")";
			case EBinop(_, left, right): "(" + shape(left) + " ? " + shape(right) + ")";
			case EIf(condition, whenTrue, whenFalse): "if " + shape(condition) + " " + shape(whenTrue) + (whenFalse == null ? "" : " else " + shape(whenFalse));
			case EVars(declarations): "var " + [
					for (declaration in declarations)
						declaration.name + " = " + (declaration.expr == null ? "?" : shape(declaration.expr))
				].join(", ");
			case EMeta(entry, inner): "@" + entry.name + " " + shape(inner);
			case EParenthesis(inner): "(" + shape(inner) + ")";
			case _: "<other>";
		};
	}
}
