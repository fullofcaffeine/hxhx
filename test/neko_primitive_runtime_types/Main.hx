/** Observe primitive classification at the intentionally heterogeneous runtime boundary. */
class Main {
	/** Dynamic is necessary here: the predicates inspect the native representation of each supplied value. */
	static function observe(label:String, value:Dynamic):Void {
		Sys.println(label + ":" + (value is Int) + ":" + (value is Float) + ":" + (value is Bool) + ":" + Std.isOfType(value, Int) + ":"
			+ Std.isOfType(value, Float) + ":" + Std.isOfType(value, Bool));
	}

	static function divide(numerator:Float, denominator:Float):Float
		return numerator / denominator;

	static function negate(value:Float):Float
		return -value;

	static function main():Void {
		observe("integer", 1);
		observe("integral-float", 1.0);
		observe("fraction", 1.5);
		observe("zero", 0.0);
		observe("negative-zero", -0.0);
		observe("nan", divide(0.0, 0.0));
		observe("positive-infinity", divide(1.0, 0.0));
		observe("negative-infinity", divide(-1.0, 0.0));
		observe("max-31bit-float", 1073741823.0);
		observe("above-31bit-float", 1073741824.0);
		observe("min-31bit-float", -1073741824.0);
		observe("below-31bit-float", -1073741825.0);
		observe("max-int", 2147483647);
		observe("max-int-float", 2147483647.0);
		observe("above-max-int", 2147483648.0);
		observe("min-int", -2147483648);
		observe("min-int-float", -2147483648.0);
		observe("small-exponent", 1e-20);
		observe("large-exponent", 1e30);
		observe("true", true);
		observe("false", false);
		observe("string", "text");
		observe("null", null);
		observe("object", {});
		Sys.println("negative-zero-sign:" + (divide(1.0, -0.0) < 0));
		Sys.println("runtime-zero-negation:" + (divide(1.0, negate(0.0)) < 0));
		Sys.println("runtime-negative-zero-negation:" + (divide(1.0, negate(-0.0)) < 0));
	}
}
