package ocaml;

/**
 * OCaml-native `Seq` surface (`Stdlib.Seq`).
 *
 * Why:
 * - `Seq` is a standard “delayed list” abstraction used throughout modern OCaml code.
 * - The upstream Haxe compiler and many libraries use sequences for lazy traversals.
 *
 * What:
 * - `ocaml.Seq<T>` models OCaml `'a Seq.t` as an opaque value.
 * - Exposes a minimal, stable subset of the `Stdlib.Seq` API.
 *
 * How:
 * - Calls are `inline` wrappers over an `extern` binding to `Stdlib.Seq`.
 *
 * Notes:
 * - We intentionally keep `Seq` opaque. The concrete representation is
 *   `unit -> 'a Seq.node` in OCaml, which is not convenient to expose directly in Haxe.
 */
abstract Seq<T>(Dynamic) {
	inline function new(v:Dynamic) this = v;

	public static inline function empty<T>():Seq<T> {
		return cast SeqNative.empty;
	}

	public static inline function return_<T>(x:T):Seq<T> {
		return cast SeqNative.return_(x);
	}

	public static inline function cons<T>(x:T, xs:Seq<T>):Seq<T> {
		return cast SeqNative.cons(x, xs);
	}

	public static inline function append<T>(a:Seq<T>, b:Seq<T>):Seq<T> {
		return cast SeqNative.append(a, b);
	}

	public static inline function map<A, B>(f:A->B, xs:Seq<A>):Seq<B> {
		return cast SeqNative.map(f, xs);
	}

	public static inline function filter<A>(p:A->Bool, xs:Seq<A>):Seq<A> {
		return cast SeqNative.filter(p, xs);
	}

	public static inline function iter<A>(f:A->Void, xs:Seq<A>):Void {
		SeqNative.iter(f, xs);
	}

	public static inline function foldLeft<A, Acc>(f:Acc->A->Acc, init:Acc, xs:Seq<A>):Acc {
		return cast SeqNative.fold_left(f, init, xs);
	}
}

@:noCompletion
@:native("Stdlib.Seq")
extern class SeqNative {
	// `empty` is a value in OCaml, not a function.
	static var empty:Seq<Dynamic>;

	@:native("return")
	static function return_<T>(x:T):Seq<T>;

	static function cons<T>(x:T, xs:Seq<T>):Seq<T>;
	static function append<T>(a:Seq<T>, b:Seq<T>):Seq<T>;
	static function map<A, B>(f:A->B, xs:Seq<A>):Seq<B>;
	static function filter<A>(p:A->Bool, xs:Seq<A>):Seq<A>;
	static function iter<A>(f:A->Void, xs:Seq<A>):Void;
	static function fold_left<A, Acc>(f:Acc->A->Acc, init:Acc, xs:Seq<A>):Acc;
}
