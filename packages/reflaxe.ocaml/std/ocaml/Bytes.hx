package ocaml;

/**
 * OCaml-native `bytes` surface (`Stdlib.Bytes`).
 *
 * Why:
 * - `bytes` is a core OCaml type used heavily by libraries and by the compiler implementation.
 * - Haxe has `haxe.io.Bytes`, but that is a Haxe stdlib type with target-specific runtime semantics.
 * - In OCaml-native mode we need to exchange native `bytes` values with OCaml APIs directly.
 *
 * What:
 * - `ocaml.Bytes` models OCaml `bytes` as an opaque value.
 * - Exposes a small subset of the `Stdlib.Bytes` API that is stable and broadly useful.
 *
 * How:
 * - All calls are `inline` wrappers over an `extern` module binding.
 * - Codegen uses `@:native("Stdlib.Bytes")` mapping so emitted OCaml stays idiomatic.
 *
 * Notes:
 * - This is not the same as `haxe.io.Bytes`. Conversions are explicit (`ofString`/`toString`).
 */
abstract Bytes(Dynamic) {
	inline function new(v:Dynamic) this = v;

	public static inline function make(len:Int, fill:Char):Bytes {
		return cast BytesNative.make(len, fill);
	}

	public static inline function length(b:Bytes):Int {
		return BytesNative.length(b);
	}

	public static inline function ofString(s:String):Bytes {
		return cast BytesNative.of_string(s);
	}

	public static inline function toString(b:Bytes):String {
		return BytesNative.to_string(b);
	}

	public static inline function sub(b:Bytes, pos:Int, len:Int):Bytes {
		return cast BytesNative.sub(b, pos, len);
	}
}

@:noCompletion
@:native("Stdlib.Bytes")
extern class BytesNative {
	static function make(len:Int, fill:Char):Bytes;
	static function length(b:Bytes):Int;
	static function of_string(s:String):Bytes;
	static function to_string(b:Bytes):String;
	static function sub(b:Bytes, pos:Int, len:Int):Bytes;
}
