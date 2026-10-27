package macros;

class Overloaded {
	public static macro function pick(value:haxe.macro.Expr):haxe.macro.Expr {
		throw "body must not run during selection";
	}

	public static macro function pick(value:String):haxe.macro.Expr {
		throw "body must not run during selection";
	}
}
