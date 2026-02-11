package ocaml;

/**
 * OCaml-native persistent set with `int` elements.
 *
 * See `ocaml.StringSet` for the rationale and architecture.
 */
abstract IntSet(Dynamic) {
	inline function new(v:Dynamic) this = v;

	public static inline function empty():IntSet {
		return cast IntSetNative.empty;
	}

	public static inline function isEmpty(s:IntSet):Bool {
		return IntSetNative.is_empty(s);
	}

	public static inline function add(x:Int, s:IntSet):IntSet {
		return IntSetNative.add(x, s);
	}

	public static inline function remove(x:Int, s:IntSet):IntSet {
		return IntSetNative.remove(x, s);
	}

	public static inline function mem(x:Int, s:IntSet):Bool {
		return IntSetNative.mem(x, s);
	}

	public static inline function iter(f:Int->Void, s:IntSet):Void {
		IntSetNative.iter(f, s);
	}
}

@:noCompletion
@:native("OcamlNativeIntSet")
extern class IntSetNative {
	static var empty:Dynamic;

	static function is_empty(s:IntSet):Bool;
	static function add(x:Int, s:IntSet):IntSet;
	static function remove(x:Int, s:IntSet):IntSet;
	static function mem(x:Int, s:IntSet):Bool;
	static function iter(f:Int->Void, s:IntSet):Void;
}
