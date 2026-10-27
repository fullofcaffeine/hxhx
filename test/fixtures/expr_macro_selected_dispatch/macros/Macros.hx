package macros;

class Macros {
	public static macro function items():haxe.macro.Expr {
		throw "body must not run during selection";
	}

	static macro function hidden():haxe.macro.Expr {
		throw "body must not run during selection";
	}

	public static function fromOwnClass():Int {
		return hidden();
	}
}
