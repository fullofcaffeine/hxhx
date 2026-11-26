package probe;

import haxe.macro.Expr;

/**
	Macro functions as a target compile sees them (haxe_ocaml-q3mio). Upstream Haxe 4.3.7 gives
	each one no body and a target-view signature: `ExprOf<T>` becomes `T`, every other type
	becomes `Dynamic`, defaults are dropped, and an instance macro loses its first argument.
	`M14MacroTargetSignatureTest` records upstream's signatures for this class.
**/
class MacroView {
	public function new() {}

	public static macro function untypedArgs(x, y) {
		return macro null;
	}

	public static macro function constant(key:String) {
		return macro $v{key};
	}

	public static macro function exprOf(e:ExprOf<Int>, ?k:ExprOf<Int>, n:Int = 3, q:ExprOf<Int> = null):ExprOf<String> {
		return macro "";
	}

	public static macro function spellings(a:haxe.macro.Expr.ExprOf<Bool>, b:Expr, c:Array<Expr>, d:Int->Int, e:{x:Int}, f:Null<ExprOf<Int>>):Expr {
		return macro null;
	}

	public static macro function generic<T>(e:ExprOf<T>):ExprOf<T> {
		return e;
	}

	public macro function instance(ethis:Expr, e:Expr, n:Int):ExprOf<String> {
		return macro "";
	}

	public static macro function voidResult(e:Expr):Void {}

	public static macro function rest(e:Expr, rest:Array<Expr>):Expr {
		return macro null;
	}

	public static macro function restDots(e:Expr, ...rest:Expr):Expr {
		return macro null;
	}

	/** Calls still pass syntax to the macro: the target view does not decide what a call accepts. */
	public static function caller():Void {
		rest(1, 2, 3);
		exprOf("text");
	}
}
