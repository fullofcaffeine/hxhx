package ocaml;

/**
 * OCaml-native `Buffer` surface (`Stdlib.Buffer`).
 *
 * Why:
 * - OCaml's `Buffer` is the idiomatic, efficient way to build strings incrementally.
 * - Haxe's portable `StringBuf` can be implemented efficiently on OCaml by delegating
 *   to `Stdlib.Buffer` operations, avoiding repeated string concatenations.
 *
 * What:
 * - `ocaml.Buffer` models `Stdlib.Buffer.t` as an opaque value (represented as `Dynamic` in Haxe).
 * - Operations are thin `inline` wrappers over an extern binding to `Stdlib.Buffer`.
 *
 * How:
 * - The backend treats `ocaml.*` abstracts as concrete OCaml types in type annotations.
 * - `@:native("Stdlib.Buffer")` maps extern callsites directly to `Stdlib.Buffer.*` in emitted OCaml.
 *
 * Notes:
 * - This API is intentionally small; expand as real workloads demand.
 * - Prefer this surface only when you explicitly want OCaml semantics/interop. Portable Haxe
 *   code should normally use `StringBuf` (which this backend can implement via this surface).
 */
abstract Buffer(Dynamic) {
	inline function new(v:Dynamic)
		this = v;

	public static inline function create(size:Int):Buffer {
		return cast BufferNative.create(size);
	}

	public static inline function length(b:Buffer):Int {
		return BufferNative.length(b);
	}

	public static inline function addString(b:Buffer, s:String):Void {
		BufferNative.add_string(b, s);
	}

	public static inline function contents(b:Buffer):String {
		return BufferNative.contents(b);
	}
}

@:noCompletion
@:native("Stdlib.Buffer")
extern class BufferNative {
	static function create(size:Int):Buffer;
	static function length(b:Buffer):Int;
	static function add_string(b:Buffer, s:String):Void;
	static function contents(b:Buffer):String;
}
