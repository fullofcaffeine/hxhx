/** Independent API probe: preserve the written numeric or opaque input until Std.int. */
class Main {
	static function number(name:String):Float {
		return switch (name) {
			case "zero": 0.0;
			case "negative_zero": -0.0;
			case "positive_fraction": 17.875;
			case "negative_fraction": -17.875;
			case "positive_subunit": 0.75;
			case "negative_subunit": -0.75;
			case "max": 2147483647.0;
			case "min": -2147483648.0;
			case "near_max": 2147483646.875;
			case "near_min": -2147483647.875;
			case "past_max_fraction": 2147483647.875;
			case "past_min_fraction": -2147483648.875;
			case "above": 2147483648.0;
			case "below": -2147483649.0;
			case "huge": 1.0e100;
			case "nan": Math.NaN;
			case "positive_infinity": Math.POSITIVE_INFINITY;
			case "negative_infinity": Math.NEGATIVE_INFINITY;
			case _: throw "unknown numeric case";
		};
	}

	/** Dynamic is intentional here: the probe measures this standard API's foreign-value boundary. */
	static function opaque(name:String):Dynamic {
		return switch (name) {
			case "integer": 42;
			case "negative_integer": -42;
			case "integer_min": -2147483647 - 1;
			case "integer_max": 2147483647;
			case "null": null;
			case "true": true;
			case "false": false;
			case "numeric_string": "17.5";
			case "word": "seventeen";
			case "array": [17];
			case "record": {value: 17};
			case "int64_small": haxe.Int64.ofInt(42);
			case "int64_wide": haxe.Int64.make(1, 7);
			case _: number(name);
		};
	}

	static function main():Void {
		final args = Sys.args();
		if (args.length != 2)
			throw "expected route and case";
		final result = args[0] == "typed" ? Std.int(number(args[1])) : Std.int(opaque(args[1]));
		Sys.println(result);
	}
}
