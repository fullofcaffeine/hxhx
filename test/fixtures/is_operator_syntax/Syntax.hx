import haxe.macro.Expr;

/** Prints a macro argument and the structure of each `is` type in it. */
class Syntax {
	public static macro function show(e:Expr):Expr {
		return macro $v{describe(e)};
	}

	public static function describe(e:Expr):String {
		final types = [];
		function visit(value:Expr):Void {
			switch value.expr {
				case EIs(_, type):
					types.push(typeStructure(type));
				case _:
			}
			haxe.macro.ExprTools.iter(value, visit);
		}
		visit(e);
		return new haxe.macro.Printer().printExpr(e) + " | " + types.join(" ; ");
	}

	static function typeStructure(type:ComplexType):String {
		return switch type {
			case TPath(path):
				final parameters = path.params == null ? [] : [
					for (parameter in path.params)
						switch parameter {
							case TPType(inner):
								typeStructure(inner);
							case TPExpr(_):
								"expr";
						}
				];
				"TPath("
				+ path.pack.join(".")
				+ "|"
				+ path.name
				+ "|"
				+ (path.sub == null ? "" : path.sub)
				+ "|["
				+ parameters.join(",")
				+ "])";
			case _:
				"other";
		}
	}
}
