/** Stand-in for hxhx's own bundled-source macro, the one declaration allowed to stay unexecuted. */
class CompilerBundledSourcesMacro {
	public static macro function files():haxe.macro.Expr {
		return macro [];
	}
}
