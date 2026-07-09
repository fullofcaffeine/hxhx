package haxe.io;

/**
	OCaml target override for `haxe.io.FPHelper`.

	Why
	- The upstream `FPHelper` implementation is written in portable Haxe and relies on
	  a fairly complex algorithm (plus inlining) to emulate IEEE754 bit-casts.
	- On this OCaml target bring-up, that portable implementation currently produces
	  generated OCaml which can end up returning `Obj.t` where a concrete `haxe.Int64`
	  record is expected (e.g. when `doubleToI64()` is used by `BytesBuffer.addDouble()`).
	- OCaml already exposes the exact primitives we need:
	  - `Int32.bits_of_float` / `Int32.float_of_bits`
	  - `Int64.bits_of_float` / `Int64.float_of_bits`

	What
	- Re-implement the public `FPHelper` surface by delegating to a small OCaml runtime
	  module (`std/runtime/HxFPHelper.ml`) which performs the bit conversions directly.

	How
	- `floatToI32`/`i32ToFloat` use OCaml's 32-bit float primitives.
	- `doubleToI64`/`i64ToDouble` use OCaml's 64-bit float primitives and bridge to
	  `haxe.Int64` using the target's `Haxe_Int64.___int64_create` constructor.

	Gotchas
	- This is *target-specific* behavior: it reflects the OCaml runtime's IEEE754
	  representation. That is what we want for correct OCaml binaries, but it is not a
	  "portable algorithm" like the upstream implementation.
**/
class FPHelper {
	public static function i32ToFloat(i:Int):Float {
		return NativeFPHelper.i32ToFloat(i);
	}

	public static function floatToI32(f:Float):Int {
		return NativeFPHelper.floatToI32(f);
	}

	public static function i64ToDouble(low:Int, high:Int):Float {
		return NativeFPHelper.i64ToDouble(low, high);
	}

	public static function doubleToI64(v:Float):haxe.Int64 {
		final parts = NativeFPHelper.doubleToI64Parts(v);
		// Runtime returns `[low, high]` (signed 32-bit chunks).
		return haxe.Int64.make(parts[1], parts[0]);
	}
}

/**
	Native OCaml bit-cast helpers for floats.

	See `std/runtime/HxFPHelper.ml` for the implementation.
**/
@:native("HxFPHelper")
private extern class NativeFPHelper {
	public static function i32ToFloat(i:Int):Float;
	public static function floatToI32(f:Float):Int;
	public static function i64ToDouble(low:Int, high:Int):Float;
	public static function doubleToI64Parts(v:Float):Array<Int>;
}
