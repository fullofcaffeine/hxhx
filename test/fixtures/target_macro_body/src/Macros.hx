import haxe.macro.Expr;

/**
	A macro class with no `#if macro` guard (haxe_ocaml-q3mio). Upstream Haxe 4.3.7 gives a macro
	function no body in a non-macro compile, so its body is never typed there: the reification
	support code (`$v{}`) never reaches the target program.
**/
class Macros {
	public static function greeting():String
		return "hello";

	public static macro function answer():Expr {
		final pos = (macro null).pos;
		return macro @:pos(pos) 42;
	}

	public static macro function values():Expr {
		return macro $v{[1, 2]};
	}
}
