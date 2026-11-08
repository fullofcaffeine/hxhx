package macros;

class Macros {
	public static macro function items():haxe.macro.Expr {
		return macro null;
	}

	public static macro function access(x:haxe.macro.Expr, rest:Array<haxe.macro.Expr>):haxe.macro.Expr {
		return x;
	}
}
