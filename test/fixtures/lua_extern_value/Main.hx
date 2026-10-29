/** A host library table is an extern value, not a generated Haxe class. */
@:native("_G.string")
extern class TextHost {
	public static function len(value:String):Int;
}

/** The observer replaces this host table to expose premature lookup or caching. */
@:native("_G.nativeLibrary")
extern class ChangingHost {
	@:native("len") public static function size(value:String):Int;
	@:native("length") public static function count(value:String):Int;
	public static function replace():Void;
}

/** A type-only declaration must not attempt to read this absent host path. */
@:native("_G.absent.value")
extern class TypeOnly {}

/** Direct native calls and saved type values must select the same host table. */
class Main {
	static var initial = TextHost;
	static var unused:TypeOnly;

	static function main():Void {
		final saved = TextHost;
		{
			final TextHost = 9;
			if (TextHost != 9)
				throw "local shadow was replaced by an extern value";
		}
		if (saved != TextHost)
			throw "extern identity changed";
		if (initial != saved)
			throw "extern field initializer changed";
		Sys.println(TextHost.len("abc"));
		final callback = TextHost.len;
		if (callback("abc") != 3)
			throw "saved native method changed";
		final before = ChangingHost;
		Sys.println(ChangingHost.size("abc"));
		final count = ChangingHost.count;
		if (ChangingHost.count("abc") != 3 || count("abc") != 3)
			throw "native member name was interpreted as a Haxe intrinsic";
		ChangingHost.size("unused");
		ChangingHost.replace();
		if (before == ChangingHost)
			throw "extern host lookup was cached";
		Sys.println(ChangingHost.size("abc"));
	}
}
