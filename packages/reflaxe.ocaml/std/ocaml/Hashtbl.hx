package ocaml;

/**
 * OCaml-native `Hashtbl` surface (`Stdlib.Hashtbl`).
 *
 * Why:
 * - The OCaml ecosystem (and the upstream Haxe compiler implementation) uses hash tables heavily
 *   for imperative maps and caches.
 * - OCaml’s `Hashtbl.create` also uses an *optional labelled argument* (`?random:`), which is a
 *   good stress-test for our extern interop story.
 *
 * What:
 * - `ocaml.Hashtbl<K,V>` models `('k,'v) Hashtbl.t` as an opaque value.
 * - Exposes a small, common subset of the `Stdlib.Hashtbl` API.
 *
 * How:
 * - Calls are `inline` wrappers over an `extern` binding (`HashtblNative`).
 * - `HashtblNative.create` uses `@:ocamlLabel("random")` so the backend emits `?random:` at
 *   the OCaml callsite.
 */
abstract Hashtbl<K, V>(Dynamic) {
	inline function new(v:Dynamic)
		this = v;

	public static inline function create<K, V>(size:Int, ?random:Bool):Hashtbl<K, V> {
		return cast(random == null ? HashtblNative.create(size) : HashtblNative.createWithRandom(random, size));
	}

	public static inline function length<K, V>(t:Hashtbl<K, V>):Int {
		return HashtblNative.length(t);
	}

	public static inline function add<K, V>(t:Hashtbl<K, V>, k:K, v:V):Void {
		HashtblNative.add(t, k, v);
	}

	public static inline function replace<K, V>(t:Hashtbl<K, V>, k:K, v:V):Void {
		HashtblNative.replace(t, k, v);
	}

	public static inline function remove<K, V>(t:Hashtbl<K, V>, k:K):Void {
		HashtblNative.remove(t, k);
	}

	public static inline function mem<K, V>(t:Hashtbl<K, V>, k:K):Bool {
		return HashtblNative.mem(t, k);
	}

	public static inline function find<K, V>(t:Hashtbl<K, V>, k:K):V {
		return cast HashtblNative.find(t, k);
	}

	public static inline function findOpt<K, V>(t:Hashtbl<K, V>, k:K):Option<V> {
		return cast HashtblNative.find_opt(t, k);
	}
}

@:noCompletion
@:native("Stdlib.Hashtbl")
extern class HashtblNative {
	static function create<K, V>(size:Int):Hashtbl<K, V>;

	/**
	 * Same OCaml function as `create`, but with the optional labelled `?random:` argument exposed.
	 *
	 * Why:
	 * - In OCaml, `Hashtbl.create` is `?random:bool -> int -> t`.
	 * - In Haxe, it's much more ergonomic to call `Hashtbl.create(size, ?random)` than to
	 *   force optional args to appear before required ones.
	 *
	 * How:
	 * - We expose two entry points that both map to the same OCaml identifier (`create`).
	 * - `reflaxe.ocaml`'s extern `@:ocamlLabel` support takes care of emitting `?random:...`.
	 */
	@:native("create")
	static function createWithRandom<K, V>(@:ocamlLabel("random") ?random:Bool, size:Int):Hashtbl<K, V>;

	static function length<K, V>(t:Hashtbl<K, V>):Int;
	static function add<K, V>(t:Hashtbl<K, V>, k:K, v:V):Void;
	static function replace<K, V>(t:Hashtbl<K, V>, k:K, v:V):Void;
	static function remove<K, V>(t:Hashtbl<K, V>, k:K):Void;
	static function mem<K, V>(t:Hashtbl<K, V>, k:K):Bool;
	static function find<K, V>(t:Hashtbl<K, V>, k:K):V;
	static function find_opt<K, V>(t:Hashtbl<K, V>, k:K):Option<V>;
}
