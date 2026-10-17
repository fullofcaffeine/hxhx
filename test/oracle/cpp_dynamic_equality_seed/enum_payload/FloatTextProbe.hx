/** Observe the numeric text that a String payload compares with inside an enum. */
class FloatTextProbe {
	static function main():Void {
		final values:Array<Float> = [
			0.0,
			-0.0,
			1.0,
			1.5,
			-1.5,
			Math.NaN,
			Math.POSITIVE_INFINITY,
			Math.NEGATIVE_INFINITY,
			1.2345678901234567,
			1.23456789012345,
			1.0000000000000002,
			0.00001,
			0.0001,
			1000000000000000.0,
			10000000000000000.0,
			1e20,
			1e-20,
			5e-324,
			2.2250738585072014e-308,
			1.7976931348623157e308,
			2147483647.0,
			-2147483648.0
		];
		for (index in 0...values.length)
			Sys.println(index + ":" + Std.string(values[index]));
	}
}
