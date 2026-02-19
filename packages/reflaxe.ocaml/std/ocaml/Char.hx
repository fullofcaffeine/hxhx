package ocaml;

/**
 * OCaml-native `char` surface (`Stdlib.Char`).
 *
 * Why:
 * - Some core OCaml APIs (e.g. `Bytes.make`) require a `char`.
 * - Haxe does not have a distinct `char` type, so we provide a tiny, typed wrapper.
 *
 * What:
 * - Models OCaml `char` as an opaque value.
 * - Exposes a constructor from an Int codepoint (`Char.ofInt`).
 *
 * Notes:
 * - OCaml `char` is a byte (0..255). Passing out-of-range values is an error in OCaml.
 */
abstract Char(Dynamic) {
	inline function new(v:Dynamic)
		this = v;

	public static inline function ofInt(code:Int):Char {
		return cast CharNative.chr(code);
	}
}

@:noCompletion
@:native("Stdlib.Char")
extern class CharNative {
	static function chr(i:Int):Char;
}
