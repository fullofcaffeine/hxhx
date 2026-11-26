import haxe.macro.Expr;

/** Prints a switch argument on one line, with the shape of its cases and default. */
class Syntax {
	public static macro function show(e:Expr):Expr {
		return macro $v{describe(e)};
	}

	public static function describe(e:Expr):String {
		final printed = StringTools.replace(StringTools.replace(new haxe.macro.Printer().printExpr(e), "\n", " "), "\t", "");
		final shape = switch e.expr {
			case EParenthesis({expr: ESwitch(_, cases, edef)}) | ESwitch(_, cases, edef):
				[
					for (c in cases)
						c.values.length + (c.guard == null ? "" : "+guard") + (c.expr == null ? ":none" : ":body")
				].join(",") + (edef == null ? " default:none" : " default:body");
			case _:
				"not a switch";
		}
		return printed + " | " + shape;
	}
}
