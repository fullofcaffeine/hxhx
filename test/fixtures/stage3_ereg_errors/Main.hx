/**
	Native-only failures of `EReg` on the Stage3 route that must be catchable.

	An invalid pattern must throw a Haxe value that `catch` can see, not an
	uncaught OCaml exception. A method call on an `EReg` held in `Dynamic`
	is not supported natively yet; it must throw a named Haxe error instead of
	crashing the process.
**/
class Main {
	static function main():Void {
		try {
			new EReg("(", "");
			Sys.println("built");
		} catch (e:Dynamic) {
			Sys.println("invalid pattern: " + Std.string(e));
		}
		try {
			final r = new EReg("a)", "g");
			Sys.println("built " + Std.string(r.match("a)")));
		} catch (e:String) {
			Sys.println("invalid pattern as String: " + e);
		}
		final d:Dynamic = ~/a+/;
		try {
			Sys.println(d.match("baaa"));
		} catch (e:Dynamic) {
			Sys.println("dynamic call: " + Std.string(e));
		}
		Sys.println("after");
	}
}
