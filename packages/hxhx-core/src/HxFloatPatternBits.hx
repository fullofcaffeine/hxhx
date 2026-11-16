/**
	The IEEE-754 bits of a Float, as 16 hex digits.

	Backends that rebuild a Float switch constant exactly use this instead of
	printing the value, which depends on the host and can round. For example,
	`backend.ocaml.Stage3OcamlFloatConstant` emits
	`Int64.float_of_bits 0x3FF8000000000000L` for `1.5`.
**/
class HxFloatPatternBits {
	public static function of(value:Float):String {
		final bits = haxe.io.FPHelper.doubleToI64(value);
		return StringTools.hex(bits.high, 8) + StringTools.hex(bits.low, 8);
	}
}
