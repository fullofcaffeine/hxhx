import haxe.macro.Expr;

/**
	A macro function that reaches another one through an ordinary helper. Upstream Haxe 4.3.7
	rejects this at the helper's call with "macro-in-macro"; inside a macro compilation (a
	project-macro plugin build) hxhx reports the call with the same reason.
**/
class MacroChain {
	public static function main():Void {}

	public static macro function outer(value:Expr):Expr {
		return helper(value);
	}

	static function helper(value:Expr):Expr {
		final checked:Expr = MacroChain.inner(value);
		return checked;
	}

	public static macro function inner(value:Expr):Expr {
		return value;
	}
}
