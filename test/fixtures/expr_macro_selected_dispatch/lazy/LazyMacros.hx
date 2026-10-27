package lazy;

class LazyMacros {
	public static macro function lazyItems():haxe.macro.Expr {
		throw "body must not run during selection";
	}

	public static function viaLazy():Int {
		return macros.Macros.items();
	}
}
