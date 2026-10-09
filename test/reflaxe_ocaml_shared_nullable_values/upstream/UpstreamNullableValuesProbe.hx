/** Assert source behavior independently before testing either target adapter. */
class UpstreamNullableValuesProbe {
	static function main():Void {
		if (Main.direct(true) != 3 || Main.direct(false) != 9)
			throw "nullable branch argument changed its selected value";
		if (Main.select(true, 0) != 0 || Main.select(false, 0) != null)
			throw "nullable zero and null were conflated";
		if (Main.recover(Main.retained(Main.select(true, 0))) != 0)
			throw "nullable zero was lost through a local and return";
		if (Main.recover(Main.retained(Main.select(false, 0))) != 9)
			throw "null was lost through a local and return";
		if (Main.recover(Main.select(true, -7)) != -7)
			throw "nullable negative integer changed";
		for (value in [0, -7, 41, 2147483647, -2147483648]) {
			if (Main.recover(value) != value || Main.recover(Main.retained(Main.select(true, value))) != value)
				throw "nullable integer boundary value changed";
			if (Main.recover(Main.retained(Main.select(false, value))) != 9)
				throw "null recovery depended on the discarded integer value";
		}
	}
}
