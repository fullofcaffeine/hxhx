package ocaml.extlib;

/**
 * ExtLib `PMap` (polymorphic persistent map) extern surface.
 *
 * Why:
 * - The upstream Haxe compiler (and OCaml compiler code generally) uses persistent maps heavily.
 * - ExtLib’s `PMap` is a widely-used, defunctorized alternative to `Stdlib.Map.Make`,
 *   which makes it convenient for Haxe-in-Haxe bootstrapping (no functors required).
 *
 * What:
 * - This is a **minimal** typed wrapper over the OCaml `PMap` module:
 *   `type ('k,'v) t` + a starter set of functions (`add`, `find`, `remove`, `mem`, ...).
 *
 * How:
 * - We model `('k,'v) PMap.t` as an opaque Haxe `abstract` over `Dynamic`.
 * - All operations are `inline` wrappers over a hidden `extern` module binding (`PMapNative`),
 *   relying on the backend’s `@:native("PMap")` mapping for correct codegen.
 *
 * Notes:
 * - `PMap.empty` is a **value** in OCaml, not a function. We expose it as `empty<K,V>()`
 *   to stay ergonomic in Haxe, but the codegen must still emit the value (not `()`).
 */
abstract PMap<K, V>(Dynamic) {
	inline function new(v:Dynamic)
		this = v;

	public static inline function empty<K, V>():PMap<K, V> {
		return cast PMapNative.empty;
	}

	public static inline function is_empty<K, V>(m:PMap<K, V>):Bool {
		return PMapNative.is_empty(m);
	}

	public static inline function create<K, V>(cmp:K->K->Int):PMap<K, V> {
		return cast PMapNative.create(cmp);
	}

	public static inline function add<K, V>(k:K, v:V, m:PMap<K, V>):PMap<K, V> {
		return cast PMapNative.add(k, v, m);
	}

	public static inline function find<K, V>(k:K, m:PMap<K, V>):V {
		return cast PMapNative.find(k, m);
	}

	public static inline function remove<K, V>(k:K, m:PMap<K, V>):PMap<K, V> {
		return cast PMapNative.remove(k, m);
	}

	public static inline function mem<K, V>(k:K, m:PMap<K, V>):Bool {
		return PMapNative.mem(k, m);
	}

	public static inline function exists<K, V>(k:K, m:PMap<K, V>):Bool {
		return PMapNative.exists(k, m);
	}

	public static inline function iter<K, V>(f:K->V->Void, m:PMap<K, V>):Void {
		PMapNative.iter(f, m);
	}

	public static inline function map<K, V, V2>(f:V->V2, m:PMap<K, V>):PMap<K, V2> {
		return cast PMapNative.map(f, m);
	}

	public static inline function mapi<K, V, V2>(f:K->V->V2, m:PMap<K, V>):PMap<K, V2> {
		return cast PMapNative.mapi(f, m);
	}

	public static inline function fold<K, V, A>(f:V->A->A, m:PMap<K, V>, init:A):A {
		return cast PMapNative.fold(f, m, init);
	}

	public static inline function foldi<K, V, A>(f:K->V->A->A, m:PMap<K, V>, init:A):A {
		return cast PMapNative.foldi(f, m, init);
	}
}

@:noCompletion
@:native("PMap")
extern class PMapNative {
	// OCaml: `val empty : ('a, 'b) t`
	static var empty:Dynamic;

	static function is_empty(m:Dynamic):Bool;

	// OCaml: `val create : ('a -> 'a -> int) -> ('a, 'b) t`
	static function create(cmp:Dynamic):Dynamic;

	static function add(k:Dynamic, v:Dynamic, m:Dynamic):Dynamic;
	static function find(k:Dynamic, m:Dynamic):Dynamic;
	static function remove(k:Dynamic, m:Dynamic):Dynamic;
	static function mem(k:Dynamic, m:Dynamic):Bool;
	static function exists(k:Dynamic, m:Dynamic):Bool;
	static function iter(f:Dynamic, m:Dynamic):Void;
	static function map(f:Dynamic, m:Dynamic):Dynamic;
	static function mapi(f:Dynamic, m:Dynamic):Dynamic;
	static function fold(f:Dynamic, m:Dynamic, init:Dynamic):Dynamic;
	static function foldi(f:Dynamic, m:Dynamic, init:Dynamic):Dynamic;
}
