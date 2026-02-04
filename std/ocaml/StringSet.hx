package ocaml;

/**
 * OCaml-native persistent set with `string` elements.
 *
 * Why:
 * - `Stdlib.Set` is functorized (`Set.Make`), and we want a usable OCaml-native surface.
 *
 * What:
 * - `ocaml.StringSet` maps to `OcamlNativeStringSet.t`.
 * - Operations are `inline` wrappers over the emitted module `OcamlNativeStringSet`.
 */
abstract StringSet(Dynamic) {
	inline function new(v:Dynamic) this = v;

	public static inline function empty():StringSet {
		return cast StringSetNative.empty;
	}

	public static inline function isEmpty(s:StringSet):Bool {
		return StringSetNative.is_empty(s);
	}

	public static inline function add(x:String, s:StringSet):StringSet {
		return StringSetNative.add(x, s);
	}

	public static inline function remove(x:String, s:StringSet):StringSet {
		return StringSetNative.remove(x, s);
	}

	public static inline function mem(x:String, s:StringSet):Bool {
		return StringSetNative.mem(x, s);
	}

	public static inline function iter(f:String->Void, s:StringSet):Void {
		StringSetNative.iter(f, s);
	}
}

@:noCompletion
@:native("OcamlNativeStringSet")
extern class StringSetNative {
	static var empty:Dynamic;

	static function is_empty(s:StringSet):Bool;
	static function add(x:String, s:StringSet):StringSet;
	static function remove(x:String, s:StringSet):StringSet;
	static function mem(x:String, s:StringSet):Bool;
	static function iter(f:String->Void, s:StringSet):Void;
}
