import haxe.macro.Context;
import haxe.macro.Expr;

/**
	A macro class with no `#if macro` guard. Upstream Haxe 4.3.7 gives a macro function no body
	in a non-macro compile, so `Context` and `haxe.macro.Type` never reach the target program.
**/
class Macros {
	public static function greeting():String
		return "hello";

	public static macro function answer():Expr {
		final pos = Context.currentPos();
		return macro @:pos(pos) 42;
	}
}
