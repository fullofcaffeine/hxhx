import haxe.macro.Expr;

/** Macro parameters and results without a written type are Expr in the macro context. */
class Macros {
	public static macro function show(e) {
		return macro "shown";
	}

	public static macro function pair(a, b:Expr) {
		return macro "pair";
	}

	public static macro function maybe(?e) {
		return macro "maybe";
	}
}
