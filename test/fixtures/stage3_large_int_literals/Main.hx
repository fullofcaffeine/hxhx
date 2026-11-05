/**
	Unsuffixed integer literals around the signed 32-bit Int range.

	Upstream Haxe 4.3.7 types an unsuffixed decimal literal as `Int` when it
	fits the signed 32-bit range, and as `Float` otherwise. `-2147483648` is one
	literal that fits; `-2147483649` and `-(2147483648)` are Float. A
	hexadecimal literal of up to 32 bits is an `Int` with the same bits, so
	`0xFFFFFFFF` is `-1`.
**/
class Main {
	/**
		Print a Float without Float formatting: Stage3 does not format Floats
		like upstream yet (Bead haxe_ocaml-vzr17). These values are integral
		and below 2^47, so two truncated Int parts identify each one exactly.
	**/
	static function describeFloat(value:Float):String {
		return "Float " + Std.int(value / 65536) + " * 65536 + " + Std.int(value % 65536);
	}

	static function describeInt(value:Int):String {
		return "Int " + Std.string(value);
	}

	static function main() {
		final maxInt = 2147483647;
		final minInt = -2147483648;
		final aboveMax = 2147483648;
		final belowMin = -2147483649;
		final grouped = 2_147_483_648;
		final wide = 4294967296;
		final wider = 1099511627776;
		final negatedGroup = -(2147483648);
		Sys.println(describeInt(maxInt));
		Sys.println(describeInt(minInt));
		Sys.println(describeFloat(aboveMax));
		Sys.println(describeFloat(belowMin));
		Sys.println(describeFloat(grouped));
		Sys.println(describeFloat(wide));
		Sys.println(describeFloat(wider));
		Sys.println(describeFloat(negatedGroup));
		Sys.println(describeFloat(aboveMax + 1));
		Sys.println(describeFloat(aboveMax / 2));
		Sys.println(describeFloat(aboveMax - maxInt));
		Sys.println(aboveMax > maxInt);
		Sys.println(belowMin < minInt);
		Sys.println(describeInt(0xFFFFFFFF));
		Sys.println(describeInt(0x7FFFFFFF));
		Sys.println(describeInt(0x80000000));
		Sys.println(describeInt(-0x80000000));
		Sys.println(describeInt(0xFFFFFFFF + 1));
	}
}
