/** Ordinary methods exercise the conversion independently of standard hex formatting. */
class IntegerCalls {
	public static function describe(value:Int, ?extra:Int):String {
		return value + ":" + (extra == null ? "absent" : Std.string(extra));
	}
}

/** Retained Int32 field and local types must cross ordinary Int call boundaries. */
class Main {
	static function main():Void {
		final bits = haxe.io.FPHelper.doubleToI64(1.0);
		Sys.println(StringTools.hex(bits.high, 8) + StringTools.hex(bits.low, 8));
		final pair = haxe.Int64.make(-1, 7);
		Sys.println(IntegerCalls.describe(pair.high, pair.low));
		final word:haxe.Int32 = -2147483648;
		Sys.println(IntegerCalls.describe(word));
	}
}
