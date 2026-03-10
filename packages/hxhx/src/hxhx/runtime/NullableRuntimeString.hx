package hxhx.runtime;

/**
	Normalize OCaml runtime nullable-string sentinels before normal Haxe string handling.

	Why
	- Under the OCaml runtime, nullable `String` values may arrive as the internal
	  `hx_null` string sentinel rather than Haxe `null`.
	- Compiler code that immediately calls `StringTools.trim`, `toLowerCase`, or
	  `split` on `Sys.getEnv(...)` can accidentally treat that sentinel as real text.

	What
	- `normalize(s)` converts the OCaml null-string sentinel back to `null`.
	- `trimToEmpty(s)` is the safe helper for env/flag parsing.

	How
	- On OCaml-target builds, this binds to the runtime `HxString.isNull` helper.
	- On non-OCaml builds, it behaves like a normal nullable-string pass-through.
 */
class NullableRuntimeString {
	public static inline function normalize(s:Null<String>):Null<String> {
		if (s == null)
			return null;
		#if ocaml_output
		if (NativeHxString.isNull(s))
			return null;
		#end
		return s;
	}

	public static inline function trimToEmpty(s:Null<String>):String {
		final normalized = normalize(s);
		return normalized == null ? "" : StringTools.trim(normalized);
	}
}

@:native("HxString")
private extern class NativeHxString {
	static function isNull(s:String):Bool;
}
