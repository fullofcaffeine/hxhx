package ocaml;

/**
 * OCaml-native persistent map with `int` keys.
 *
 * See `ocaml.StringMap` for the rationale and architecture.
 *
 * This maps to the emitted module `OcamlNativeIntMap` (`'v OcamlNativeIntMap.t`).
 */
abstract IntMap<V>(Dynamic) {
	inline function new(v:Dynamic) this = v;

	public static inline function empty<V>():IntMap<V> {
		return cast IntMapNative.empty;
	}

	public static inline function isEmpty<V>(m:IntMap<V>):Bool {
		return IntMapNative.is_empty(m);
	}

	public static inline function add<V>(k:Int, v:V, m:IntMap<V>):IntMap<V> {
		return IntMapNative.add(k, v, m);
	}

	public static inline function remove<V>(k:Int, m:IntMap<V>):IntMap<V> {
		return IntMapNative.remove(k, m);
	}

	public static inline function mem<V>(k:Int, m:IntMap<V>):Bool {
		return IntMapNative.mem(k, m);
	}

	public static inline function find<V>(k:Int, m:IntMap<V>):V {
		return IntMapNative.find(k, m);
	}

	public static inline function findOpt<V>(k:Int, m:IntMap<V>):Option<V> {
		return IntMapNative.find_opt(k, m);
	}

	public static inline function iter<V>(f:Int->V->Void, m:IntMap<V>):Void {
		IntMapNative.iter(f, m);
	}

	public static inline function fold<V, A>(f:Int->V->A->A, m:IntMap<V>, init:A):A {
		return IntMapNative.fold(f, m, init);
	}
}

@:noCompletion
@:native("OcamlNativeIntMap")
extern class IntMapNative {
	static var empty:Dynamic;

	static function is_empty<V>(m:IntMap<V>):Bool;
	static function add<V>(k:Int, v:V, m:IntMap<V>):IntMap<V>;
	static function remove<V>(k:Int, m:IntMap<V>):IntMap<V>;
	static function mem<V>(k:Int, m:IntMap<V>):Bool;
	static function find<V>(k:Int, m:IntMap<V>):V;
	static function find_opt<V>(k:Int, m:IntMap<V>):Option<V>;
	static function iter<V>(f:Int->V->Void, m:IntMap<V>):Void;
	static function fold<V, A>(f:Int->V->A->A, m:IntMap<V>, init:A):A;
}
