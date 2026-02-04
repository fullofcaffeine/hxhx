package ocaml;

/**
 * OCaml-native `array` surface (`Stdlib.Array`).
 *
 * Why:
 * - Haxe `Array<T>` is a growable runtime structure with Haxe semantics.
 * - OCaml’s native `'a array` is a *fixed-length* mutable array with extremely common APIs
 *   (`Array.make`, `Array.get`, `Array.set`, `Array.map`, ...).
 * - For OCaml-native mode we want a typed way to talk to native arrays without dropping down
 *   to `untyped __ocaml__`.
 *
 * What:
 * - `ocaml.Array<T>` models OCaml `'a array` as an opaque value (represented as `Dynamic` in Haxe).
 * - All operations are `inline` wrappers over an `extern` binding to `Stdlib.Array`.
 *   Inlining keeps generated output close to the 1:1 OCaml idioms.
 *
 * How:
 * - The backend’s extern `@:native("Stdlib.Array")` support maps `ArrayNative.*` callsites
 *   directly to `Stdlib.Array.*` in emitted OCaml.
 *
 * Notes:
 * - This API is intentionally small for now; expand as real workloads demand.
 * - Prefer this surface only when you explicitly want OCaml semantics/interop. For portable Haxe
 *   code, keep using `Array<T>`.
 */
abstract Array<T>(Dynamic) {
	inline function new(v:Dynamic) this = v;

	public static inline function make<T>(len:Int, init:T):Array<T> {
		return cast ArrayNative.make(len, init);
	}

	public static inline function init<T>(len:Int, f:Int->T):Array<T> {
		return cast ArrayNative.init(len, f);
	}

	public static inline function length<T>(a:Array<T>):Int {
		return ArrayNative.length(a);
	}

	public static inline function get<T>(a:Array<T>, i:Int):T {
		return cast ArrayNative.get(a, i);
	}

	public static inline function set<T>(a:Array<T>, i:Int, v:T):Void {
		ArrayNative.set(a, i, v);
	}

	public static inline function map<A, B>(f:A->B, a:Array<A>):Array<B> {
		return cast ArrayNative.map(f, a);
	}

	public static inline function iter<A>(f:A->Void, a:Array<A>):Void {
		ArrayNative.iter(f, a);
	}

	public static inline function fold_left<A, Acc>(f:Acc->A->Acc, init:Acc, a:Array<A>):Acc {
		return cast ArrayNative.fold_left(f, init, a);
	}
}

@:noCompletion
@:native("Stdlib.Array")
extern class ArrayNative {
	static function make(len:Int, init:Dynamic):Dynamic;
	static function init(len:Int, f:Dynamic):Dynamic;
	static function length(a:Dynamic):Int;
	static function get(a:Dynamic, i:Int):Dynamic;
	static function set(a:Dynamic, i:Int, v:Dynamic):Void;
	static function map(f:Dynamic, a:Dynamic):Dynamic;
	static function iter(f:Dynamic, a:Dynamic):Void;
	static function fold_left(f:Dynamic, init:Dynamic, a:Dynamic):Dynamic;
}

