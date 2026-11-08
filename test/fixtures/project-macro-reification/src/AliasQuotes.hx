import haxe.macro.Expr;
import haxe.ds.StringMap as Std;

/** An import alias named `Std` must not be the `Std` that `$v{}` on a Float calls. */
class AliasQuotes {
	public static function value():Expr {
		final f = 2.5;
		return macro $v{f};
	}
}
