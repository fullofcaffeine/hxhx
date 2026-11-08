/**
	A project class that only shares its name with hxhx's own bundled-source macro. It must not get
	that macro's exception: a selected call to it that cannot run fails the compile.
**/
class CompilerBundledSourcesMacro {
	public static macro function files():haxe.macro.Expr {
		return macro [];
	}
}
